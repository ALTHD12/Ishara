import asyncio
import base64
import json
import cv2
import numpy as np
import os
import time
import threading
import subprocess
from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ai.mediapipe_model import mp_service
from timing import DEBUG_TIMING, FrameTimer, TimingStats
from features import extract_342_features
from frame_codec import packed_yuv420_to_rgb
from live_decoder import LiveDecoder
import live_config as LC

import tensorflow as tf
from tensorflow.keras.models import load_model

MODEL_PATH = "ai/isl_model.keras"
CLASSES_PATH = "ai/label_encoder_classes.json"
TRAIN_DIR = "data/training_data"

os.makedirs(TRAIN_DIR, exist_ok=True)

model = None
classes = []
_predict_graph = None


def load_ml_model():
    global model, classes, _predict_graph
    if os.path.exists(MODEL_PATH) and os.path.exists(CLASSES_PATH):
        m = load_model(MODEL_PATH)
        with open(CLASSES_PATH, "r") as f:
            cls = json.load(f)

        # Graph-compiled call: same weights, same math as model(x), but avoids
        # Keras eager dispatch (~380 ms -> ~17 ms per call on CPU).
        @tf.function(input_signature=[tf.TensorSpec([1, LC.WINDOW_FRAMES, 342], tf.float32)])
        def graph_fn(x):
            return m(x, training=False)

        graph_fn(tf.zeros([1, LC.WINDOW_FRAMES, 342], tf.float32))  # trace + warm up
        model, classes, _predict_graph = m, cls, graph_fn
        print(f"[OK] Loaded ML model with classes: {classes}")
    else:
        print("[WARN] No trained ML model found. Run ai/bilstm_model.py first.")


def predict_window(window):
    """window: (30, 342) -> class probabilities (numpy)."""
    x = tf.constant(np.asarray(window, dtype=np.float32)[None])
    return _predict_graph(x).numpy()[0]


load_ml_model()


def train_model_thread():
    print("[INFO] Starting background training...")
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    import sys
    result = subprocess.run([sys.executable, "ai/bilstm_model.py"], env=env)

    if result.returncode == 0:
        print("[OK] Training complete. Reloading model...")
        load_ml_model()
        return True
    else:
        print("[ERROR] Training failed.")
        return False


# MediaPipe instances are shared and not thread-safe: all frame work runs on
# this single worker thread, off the asyncio loop, so receiving never blocks.
_frame_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="frame")

# Optional extension of the 12-byte header: if this bit is set in the rotation
# field, an 8-byte big-endian int64 capture timestamp (microseconds, client
# monotonic clock) follows the header. Old clients never set it.
HDR_FLAG_TIMESTAMP = 0x10000
# Payload is packed YUV420 (Y, U, V planes; 1.5 B/px) instead of RGB; decoded
# with the client's exact integer math -> bit-identical RGB (frame_codec.py).
HDR_FLAG_YUV420 = 0x40000

# Debug: ISL_DEBUG_SAVE_FRAMES=<dir> saves every 30th upright frame as PNG
# (to check orientation / colour / distortion of what the phone sends).
_SAVE_FRAMES_DIR = os.environ.get("ISL_DEBUG_SAVE_FRAMES", "")
if _SAVE_FRAMES_DIR:
    os.makedirs(_SAVE_FRAMES_DIR, exist_ok=True)

# Debug: ISL_DEBUG_DECISIONS=1 adds "why" (reason the last frame did not emit a
# word, see LiveDecoder.last_reason) to every live response and logs changes.
DEBUG_DECISIONS = os.environ.get("ISL_DEBUG_DECISIONS", "").lower() in ("1", "true", "yes")


def _compact_nodes(nodes):
    d = LC.OVERLAY_DECIMALS
    return [[round(n["x"], d), round(n["y"], d)] for n in nodes]


def _quantized_nodes(nodes):
    """Overlay only: x,y as little-endian int16 (value * OVERLAY_Q_SCALE),
    base64. No z. 478 face points -> ~2.5 KB instead of ~8.5 KB of JSON floats."""
    xy = np.array([(n["x"], n["y"]) for n in nodes], dtype=np.float64) * LC.OVERLAY_Q_SCALE
    q = np.clip(np.round(xy), -32768, 32767).astype("<i2")
    return base64.b64encode(q.tobytes()).decode("ascii")


class ConnState:
    """Per-connection state. Mutated only on the frame worker thread, except
    for the simple flags set by control messages."""

    def __init__(self):
        self.decoder = LiveDecoder(lambda w: predict_window(w), classes)
        self.is_recording_mode = False
        self.recording_state = "idle"  # idle, continuous_recording, processing, training
        self.recording_label = ""
        self.continuous_buffer = []
        self.recording_start_time = 0.0
        self.training_finished = False
        self.training_success = False
        self.server_dropped = 0
        # Set by the {"action":"reset"} handler, applied on the frame worker
        # thread before the next frame (the decoder is not thread-safe).
        self.reset_requested = False
        # Overlay face detail: "full" (478-point mesh, quantized) or "light"
        # (OVERLAY_FACE_POINTS subset). Set by {"action":"overlay","face":...}.
        self.face_mode = LC.OVERLAY_FACE_DEFAULT
        self.last_reason_logged = None


def process_frame(st, message, t_recv, timer):
    """Runs on the frame worker thread. Returns the JSON-able response dict."""
    if len(message) < 12:
        return {}
    rotation = int.from_bytes(message[0:4], byteorder='big')
    width = int.from_bytes(message[4:8], byteorder='big')
    height = int.from_bytes(message[8:12], byteorder='big')
    offset = 12
    t_frame = t_recv
    flags = rotation & ~0xFFFF
    rotation &= 0xFFFF
    if flags & HDR_FLAG_TIMESTAMP:
        t_frame = int.from_bytes(message[12:20], byteorder='big', signed=True) / 1e6
        offset = 20
    img_data = message[offset:]

    try:
        if flags & HDR_FLAG_YUV420:
            img_rgb = packed_yuv420_to_rgb(img_data, width, height)
        else:
            img_rgb = np.frombuffer(img_data, dtype=np.uint8).reshape((height, width, 3))
    except Exception:
        return {}

    if rotation == 90:
        img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_CLOCKWISE)
    elif rotation == 270:
        img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_COUNTERCLOCKWISE)
    elif rotation == 180:
        img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_180)
    if timer: timer.mark("decode")
    if _SAVE_FRAMES_DIR:
        st.saved_frame_counter = getattr(st, "saved_frame_counter", 0) + 1
        if st.saved_frame_counter % 30 == 1:
            cv2.imwrite(os.path.join(_SAVE_FRAMES_DIR, f"frame_{st.saved_frame_counter:05d}.png"),
                        cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR))

    if st.reset_requested:
        st.reset_requested = False
        st.decoder.reset()

    live = not st.is_recording_mode
    if live and LC.MEDIAPIPE_VIDEO_MODE:
        landmarks = mp_service.process_video_frame(img_rgb, t_frame * 1000.0, timer)
    else:
        # IMAGE mode: identical to how all training data was recorded.
        landmarks = mp_service.process_image(img_rgb, timer)
    if timer: timer.mark("mediapipe")

    status_msg = ""
    out = {}

    if st.is_recording_mode:
        if st.recording_state == "continuous_recording":
            features = extract_342_features(landmarks)
            st.continuous_buffer.append(features)

            elapsed_time = time.time() - st.recording_start_time
            seconds_left = max(0, 30 - int(elapsed_time))
            status_msg = f"RECORDING... {seconds_left}s remaining"

            if elapsed_time >= 30:  # Strictly 30 real-world seconds
                st.recording_state = "processing"
                # Slice into overlapping sequences (step 5)
                sequences = []
                for i in range(0, len(st.continuous_buffer) - 30, 5):
                    sequences.append(st.continuous_buffer[i:i + 30])

                if sequences:
                    np_data = np.array(sequences)
                    path = os.path.join(TRAIN_DIR, f"{st.recording_label}.npy")
                    if os.path.exists(path):
                        existing_data = np.load(path)
                        np_data = np.concatenate([existing_data, np_data])
                    np.save(path, np_data)

                fps = len(st.continuous_buffer) / max(elapsed_time, 1e-6)
                print(f"[REC] {st.recording_label}: {len(st.continuous_buffer)} frames in "
                      f"{elapsed_time:.1f}s ({fps:.1f} fps) -> {len(sequences)} windows")
                st.recording_state = "idle"
                st.is_recording_mode = False
                status_msg = f"Saved {len(sequences)} sequences for {st.recording_label}!"
    elif st.recording_state == "training":
        if st.training_finished:
            st.recording_state = "idle"
            status_msg = ("Training Complete! Model Reloaded." if st.training_success
                          else "Training Failed! You need at least 2 signs recorded.")
            st.training_finished = False
            eid = st.decoder.event_id  # keep ids monotonic (client drops eid <= last seen)
            st.decoder = LiveDecoder(lambda w: predict_window(w), classes)
            st.decoder.event_id = eid
        else:
            status_msg = "Training model in background... (Check Terminal for progress)"
    elif model is not None:
        has_hands = bool(landmarks.get("left_hand") or landmarks.get("right_hand"))
        features = extract_342_features(landmarks)
        t_model = time.perf_counter()
        n_inf_before = st.decoder.last_probs
        st.decoder.push(t_frame, features, has_hands)
        if timer and st.decoder.last_probs is not n_inf_before:
            timer.add("model+decode", (time.perf_counter() - t_model) * 1000.0)
        if st.decoder.display_sign:
            out["sign"] = st.decoder.display_sign
            out["confidence"] = st.decoder.display_conf
        if st.decoder.last_event:
            eid, esign, _ = st.decoder.last_event
            out["eid"] = eid      # client appends a word whenever eid increases
            out["esign"] = esign
        if DEBUG_DECISIONS:
            why = st.decoder.last_reason
            out["why"] = why
            kind = why.split(" ", 1)[0]
            if kind != st.last_reason_logged:
                st.last_reason_logged = kind
                print(f"[DECISION] t={t_frame:.2f} hands={int(has_hands)} {why}", flush=True)

    for key, name in (("pose", "pose"), ("face", "face"),
                      ("left_hand", "left_hand"), ("right_hand", "right_hand")):
        if key in landmarks:
            nodes = landmarks[key]
            if key == "face" and live and len(nodes) >= 468:
                # Overlay only - features were computed from the full landmarks above.
                if st.face_mode == "full":
                    out["face_q"] = _quantized_nodes(nodes)
                    continue
                if LC.OVERLAY_FACE_POINTS is not None:
                    nodes = [nodes[i] for i in LC.OVERLAY_FACE_POINTS]
            out[name] = _compact_nodes(nodes)
    if status_msg:
        out["recording_status"] = status_msg
    if timer:
        timer.mark("post")
    return out


router = APIRouter()


@router.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Flutter Client connected!")
    timing_stats = TimingStats("server")
    loop = asyncio.get_running_loop()
    st = ConnState()

    send_lock = asyncio.Lock()
    pending = {"msg": None}        # newest unprocessed frame only
    frame_ready = asyncio.Event()
    closed = False

    async def send_json(obj):
        async with send_lock:
            await websocket.send_text(json.dumps(obj))

    async def frame_worker():
        while not closed:
            await frame_ready.wait()
            frame_ready.clear()
            item = pending["msg"]
            pending["msg"] = None
            if item is None:
                continue
            message, t_recv, t0 = item
            timer = FrameTimer(t0) if DEBUG_TIMING else None
            if timer: timer.mark("queue")
            try:
                out = await loop.run_in_executor(_frame_executor, process_frame, st, message, t_recv, timer)
            except Exception as e:
                print(f"[WARN] frame error: {e}")
                out = {}
            if timer:
                payload = json.dumps(out)
                timer.mark("json")
                timer.stages["json_bytes_k"] = len(payload) / 1024.0
                out["_t"] = {k: round(v, 2) for k, v in timer.stages.items()}
                out["_t"]["server_total"] = round(timer.total_ms(), 2)
                out["_t"]["server_dropped"] = st.server_dropped
            try:
                await send_json(out)
            except Exception:
                return
            if timer:
                timer.mark("send")
                timing_stats.record(timer.stages)

    worker_task = asyncio.create_task(frame_worker())

    try:
        while True:
            message_dict = await websocket.receive()

            if message_dict.get("type") == "websocket.disconnect":
                print("Flutter Client sent disconnect message.")
                break

            # Handle JSON Control Messages
            if "text" in message_dict and message_dict["text"]:
                try:
                    cmd = json.loads(message_dict["text"])
                    action = cmd.get("action")
                    if action == "ping":
                        await send_json({"pong": time.time()})
                    elif action == "start_continuous_recording":
                        st.recording_label = cmd.get("label", "UNKNOWN").upper()
                        st.continuous_buffer = []
                        st.recording_start_time = time.time()
                        st.recording_state = "continuous_recording"
                        st.is_recording_mode = True
                        print(f"Started continuous 30s recording for {st.recording_label}")
                    elif action == "overlay":
                        if cmd.get("face") in ("full", "light"):
                            st.face_mode = cmd["face"]
                    elif action == "reset":
                        st.reset_requested = True
                    elif action == "train_model":
                        st.recording_state = "training"

                        def thread_worker():
                            success = train_model_thread()
                            st.training_success = success
                            st.training_finished = True

                        threading.Thread(target=thread_worker, daemon=True).start()
                        print("Triggered model training.")
                except json.JSONDecodeError:
                    pass
                continue

            if "bytes" not in message_dict or not message_dict["bytes"]:
                continue

            # Latest-frame-wins: if the worker is busy, an older pending frame
            # is replaced (dropped) so we always process the newest one.
            if pending["msg"] is not None:
                st.server_dropped += 1
            pending["msg"] = (message_dict["bytes"], time.monotonic(), time.perf_counter())
            frame_ready.set()

    except WebSocketDisconnect:
        print("Flutter Client disconnected.")
    finally:
        closed = True
        frame_ready.set()
        worker_task.cancel()
