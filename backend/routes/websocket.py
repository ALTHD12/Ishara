import json
import cv2
import numpy as np
import os
import time
import threading
import subprocess
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ai.mediapipe_model import mp_service

import tensorflow as tf
from tensorflow.keras.models import load_model

MODEL_PATH = "ai/isl_model.keras"
CLASSES_PATH = "ai/label_encoder_classes.json"
TRAIN_DIR = "data/training_data"

os.makedirs(TRAIN_DIR, exist_ok=True)

model = None
classes = []

def load_ml_model():
    global model, classes
    if os.path.exists(MODEL_PATH) and os.path.exists(CLASSES_PATH):
        model = load_model(MODEL_PATH)
        with open(CLASSES_PATH, "r") as f:
            classes = json.load(f)
        print(f"✅ Loaded ML model with classes: {classes}")
    else:
        print("⚠️ No trained ML model found. Run ai/bilstm_model.py first.")

load_ml_model()

def extract_342_features(data):
    """Extract comprehensive 342-dimensional feature vector.
    
    Layout: 
    - Pose (2D relative): 10*3=30
    - Face (2D relative): 20*3=60
    - L Hand (2D relative): 21*3=63
    - R Hand (2D relative): 21*3=63
    - L Hand (3D world): 21*3=63
    - R Hand (3D world): 21*3=63
    Total = 342 features.
    
    This provides explicit finger placement (world) AND spatial positioning (relative).
    """
    
    # --- Step 1: Find body anchor and scale ---
    pose_nodes = data.get("pose", [])
    
    anchor_x, anchor_y, anchor_z = 0.5, 0.5, 0.0
    scale = 1.0
    
    if len(pose_nodes) > 12:
        nose = pose_nodes[0]
        anchor_x = nose.get("x", 0.5)
        anchor_y = nose.get("y", 0.5)
        anchor_z = nose.get("z", 0.0)
        
        ls = pose_nodes[11]
        rs = pose_nodes[12]
        dx = ls.get("x", 0) - rs.get("x", 0)
        dy = ls.get("y", 0) - rs.get("y", 0)
        shoulder_dist = (dx**2 + dy**2) ** 0.5
        if shoulder_dist > 0.01:
            scale = shoulder_dist
        else:
            scale = 0.2
    
    def normalize_and_flatten(nodes, target_len):
        if not nodes:
            return np.zeros(target_len * 3)
        subset = nodes[:target_len]
        while len(subset) < target_len:
            subset.append({"x": 0, "y": 0, "z": 0})
        arr = []
        for n in subset:
            nx = n.get("x", 0)
            ny = n.get("y", 0)
            nz = n.get("z", 0)
            if nx == 0 and ny == 0 and nz == 0:
                arr.extend([0.0, 0.0, 0.0])
            else:
                arr.extend([
                    (nx - anchor_x) / scale,
                    (ny - anchor_y) / scale,
                    nz / scale
                ])
        return np.array(arr)

    def flatten_raw(nodes, target_len):
        if not nodes:
            return np.zeros(target_len * 3)
        subset = nodes[:target_len]
        while len(subset) < target_len:
            subset.append({"x": 0, "y": 0, "z": 0})
        arr = []
        for n in subset:
            arr.extend([n.get("x", 0), n.get("y", 0), n.get("z", 0)])
        return np.array(arr)

    pose_subset = pose_nodes[11:21] if len(pose_nodes) > 20 else []
    pose_arr = normalize_and_flatten(pose_subset, 10)
    face_arr = normalize_and_flatten(data.get("face", []), 20)
    l_hand_arr = normalize_and_flatten(data.get("left_hand", []), 21)
    r_hand_arr = normalize_and_flatten(data.get("right_hand", []), 21)
    
    # 3D World Landmarks (no anchor needed, they are hand-centric in meters)
    l_hand_world_arr = flatten_raw(data.get("left_hand_world", []), 21)
    r_hand_world_arr = flatten_raw(data.get("right_hand_world", []), 21)

    return np.concatenate([
        pose_arr, face_arr, 
        l_hand_arr, r_hand_arr, 
        l_hand_world_arr, r_hand_world_arr
    ])

def train_model_thread():
    print("🚀 Starting background training...")
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg" 
    import sys
    result = subprocess.run([sys.executable, "ai/bilstm_model.py"], env=env)
    
    # We use a global mechanism to pass back the status to the websocket loop
    # We'll just attach it to the router or process state since websocket objects are local
    if result.returncode == 0:
        print("✅ Training complete. Reloading model...")
        load_ml_model()
        return True
    else:
        print("❌ Training failed.")
        return False

router = APIRouter()

@router.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Flutter Client connected!")
    sequence_buffer = []
    
    # Recording State Variables
    is_recording_mode = False
    recording_state = "idle" # idle, countdown, recording, relax, training
    recording_label = ""
    target_seqs = 4
    current_seq_idx = 0
    frames_per_seq = 30
    frame_counter = 0 # generic counter for state
    recorded_sequences = []
    recording_start_time = 0.0

    try:
        while True:
            # receive can be text or bytes
            message_dict = await websocket.receive()
            
            if message_dict.get("type") == "websocket.disconnect":
                print("Flutter Client sent disconnect message.")
                break
            
            # Handle JSON Control Messages
            if "text" in message_dict and message_dict["text"]:
                try:
                    cmd = json.loads(message_dict["text"])
                    action = cmd.get("action")
                    if action == "start_continuous_recording":
                        is_recording_mode = True
                        recording_label = cmd.get("label", "UNKNOWN").upper()
                        recording_state = "continuous_recording"
                        continuous_buffer = []
                        recording_start_time = time.time()
                        print(f"Started continuous 30s recording for {recording_label}")
                    elif action == "train_model":
                        recording_state = "training"
                        
                        def thread_worker():
                            success = train_model_thread()
                            websocket.training_finished = True
                            websocket.training_success = success
                            
                        threading.Thread(target=thread_worker).start()
                        print("Triggered model training.")
                except json.JSONDecodeError:
                    pass
                continue
            
            if "bytes" not in message_dict or not message_dict["bytes"]:
                continue
                
            message = message_dict["bytes"]
            
            try:
                if len(message) < 12:
                    await websocket.send_text("{}")
                    continue
                    
                rotation = int.from_bytes(message[0:4], byteorder='big')
                width = int.from_bytes(message[4:8], byteorder='big')
                height = int.from_bytes(message[8:12], byteorder='big')
                img_data = message[12:]
                
                try:
                    img_rgb = np.frombuffer(img_data, dtype=np.uint8).reshape((height, width, 3))
                except Exception as reshape_err:
                    await websocket.send_text("{}")
                    continue
                
                if rotation == 90:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_CLOCKWISE)
                elif rotation == 270:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_COUNTERCLOCKWISE)
                elif rotation == 180:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_180)
                    
                landmarks = mp_service.process_image(img_rgb)
                
                status_msg = ""
                
                if is_recording_mode:
                    if recording_state == "continuous_recording":
                        features = extract_342_features(landmarks)
                        continuous_buffer.append(features)
                        
                        elapsed_time = time.time() - recording_start_time
                        seconds_left = max(0, 30 - int(elapsed_time))
                        
                        status_msg = f"RECORDING... {seconds_left}s remaining"
                        
                        if elapsed_time >= 30: # Strictly 30 real-world seconds
                            recording_state = "processing"
                            status_msg = "Processing and Saving..."
                            
                            # Slice into overlapping sequences
                            sequences = []
                            # Step by 5 frames (gives ~174 sequences from 900 frames)
                            for i in range(0, len(continuous_buffer) - 30, 5):
                                sequences.append(continuous_buffer[i:i+30])
                                
                            if sequences:
                                np_data = np.array(sequences)
                                path = os.path.join(TRAIN_DIR, f"{recording_label}.npy")
                                if os.path.exists(path):
                                    existing_data = np.load(path)
                                    np_data = np.concatenate([existing_data, np_data])
                                np.save(path, np_data)
                                
                            recording_state = "idle"
                            is_recording_mode = False
                            status_msg = f"Saved {len(sequences)} sequences for {recording_label}!"
                else:
                    # ML Inference Integration
                    if model is not None and recording_state != "training":
                        l_hand = landmarks.get("left_hand", [])
                        r_hand = landmarks.get("right_hand", [])
                        
                        has_hands = bool(l_hand or r_hand)
                        
                        features = extract_342_features(landmarks)
                        
                        # Store tuple of (features, has_hands)
                        sequence_tuple_buffer = getattr(websocket, 'sequence_tuple_buffer', [])
                        sequence_tuple_buffer.append((features, has_hands))
                        if len(sequence_tuple_buffer) > 30:
                            sequence_tuple_buffer.pop(0)
                        websocket.sequence_tuple_buffer = sequence_tuple_buffer
                        
                        # Track consecutive no-hand frames for prediction decay
                        no_hand_streak = getattr(websocket, 'no_hand_streak', 0)
                        if not has_hands:
                            no_hand_streak += 1
                        else:
                            no_hand_streak = 0
                        websocket.no_hand_streak = no_hand_streak
                        
                        # Auto-clear prediction after ~2 seconds of no hands (60 frames)
                        if no_hand_streak > 60:
                            websocket.last_predicted_sign = None
                            websocket.last_confidence = 0.0
                            getattr(websocket, 'prediction_history', []).clear()
                            
                        if len(sequence_tuple_buffer) == 30:
                            active_frames = sum(1 for _, h in sequence_tuple_buffer if h)
                            
                            if active_frames < 15:
                                # User is idle — hands must be visible in at least HALF the window
                                getattr(websocket, 'prediction_history', []).clear()
                                websocket.last_predicted_sign = None
                                websocket.last_confidence = 0.0
                            else:
                                inf_counter = getattr(websocket, 'inf_counter', 0)
                                
                                if inf_counter % 3 == 0:
                                    input_data = np.expand_dims([f for f, _ in sequence_tuple_buffer], axis=0)
                                    prediction = model(input_data, training=False).numpy()[0]
                                    max_idx = np.argmax(prediction)
                                    confidence = float(prediction[max_idx])
                                    
                                    # PREDICTION SMOOTHING
                                    history = getattr(websocket, 'prediction_history', [])
                                    if confidence >= 0.55:
                                        history.append(max_idx)
                                    else:
                                        history.append(-1)
                                        
                                    if len(history) > 5:
                                        history.pop(0)
                                    
                                    if len(history) == 5:
                                        valid_history = [x for x in history if x != -1]
                                        if len(valid_history) >= 3:
                                            counts = np.bincount(valid_history)
                                            top_idx = np.argmax(counts)
                                            if counts[top_idx] >= 3:
                                                websocket.last_predicted_sign = classes[top_idx]
                                                websocket.last_confidence = 1.0
                                                
                                                # SLIDING WINDOW FLUSH
                                                websocket.sequence_tuple_buffer = sequence_tuple_buffer[15:]
                                                history.clear()
                                        else:
                                            # Not enough high-confidence frames — don't predict
                                            pass
                                    websocket.prediction_history = history
                                        
                                websocket.inf_counter = inf_counter + 1
                                
                        if getattr(websocket, 'last_confidence', 0.0) >= 0.50:
                            landmarks["sign"] = getattr(websocket, 'last_predicted_sign', None)
                            landmarks["confidence"] = getattr(websocket, 'last_confidence', 0.0)
                                
                    elif recording_state == "training":
                        if getattr(websocket, 'training_finished', False):
                            recording_state = "idle"
                            if getattr(websocket, 'training_success', False):
                                status_msg = "✅ Training Complete! Model Reloaded."
                            else:
                                status_msg = "❌ Training Failed! You need at least 2 signs recorded."
                                
                            websocket.training_finished = False # reset flag
                        else:
                            status_msg = "Training model in background... (Check Terminal for progress)"
                
                if status_msg:
                    landmarks["recording_status"] = status_msg
                
                await websocket.send_text(json.dumps(landmarks))
                
            except Exception as frame_error:
                await websocket.send_text("{}")
                continue
                
    except WebSocketDisconnect:
        print("Flutter Client disconnected.")
