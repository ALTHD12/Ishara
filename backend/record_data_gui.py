import cv2
import tkinter as tk
from tkinter import messagebox, filedialog
from PIL import Image, ImageTk
import numpy as np
import json
import os
import time
import threading

# Import the existing MediaPipe service
from ai.mediapipe_model import mp_service

# Directories
TRAIN_DIR = "data/training_data"
AVATAR_DIR = "data/avatar_takes"
os.makedirs(TRAIN_DIR, exist_ok=True)
os.makedirs(AVATAR_DIR, exist_ok=True)

class ISLRecorderApp:
    def __init__(self, window):
        self.window = window
        self.window.title("ISL Data Recording Studio")
        self.window.geometry("800x600")
        self.window.configure(bg="#f4f4f9")

        self.cap = cv2.VideoCapture(0)
        
        # State variables
        self.is_recording_training = False
        self.is_recording_hero = False
        self.training_sequences = []
        self.current_sequence = []
        self.hero_frames = []
        self.seq_count = 0
        self.num_sequences = 2
        self.seq_count = 0
        self.target_seqs = 2
        self.frames_per_seq = 30
        self.countdown = 0

        # UI Elements
        self.video_label = tk.Label(window)
        self.video_label.pack(pady=10)

        self.control_frame = tk.Frame(window)
        self.control_frame.pack(pady=10)

        tk.Label(self.control_frame, text="Sentence / Gloss:", font=("Arial", 12)).grid(row=0, column=0, padx=5)
        self.sentence_entry = tk.Entry(self.control_frame, font=("Arial", 12), width=20)
        self.sentence_entry.grid(row=0, column=1, padx=5)

        self.train_btn = tk.Button(self.control_frame, text="Record Training Set (2x)", 
                                   command=self.start_training, bg="blue", fg="white", font=("Arial", 12, "bold"), width=25)
        self.train_btn.grid(row=1, column=0, columnspan=2, pady=10)

        self.hero_btn = tk.Button(self.control_frame, text="Start Hero Avatar Take", 
                                  command=self.toggle_hero, bg="green", fg="white", font=("Arial", 12, "bold"), width=25)
        self.hero_btn.grid(row=2, column=0, columnspan=2, pady=5)

        self.upload_btn = tk.Button(self.control_frame, text="Upload Video File (.mp4)", 
                                    command=self.upload_video, bg="purple", fg="white", font=("Arial", 12, "bold"), width=25)
        self.upload_btn.grid(row=3, column=0, columnspan=2, pady=5)

        self.status_label = tk.Label(window, text="Ready.", font=("Arial", 14), fg="black")
        self.status_label.pack(pady=10)

        self.update_video()

    def get_sentence(self):
        val = self.sentence_entry.get().strip().upper()
        if not val:
            messagebox.showerror("Error", "Please enter a sentence or gloss name first.")
            return None
        return val

    def extract_216_features(self, data):
        """ Extracts exactly 216 features (x, y, z) for BiLSTM """
        # Flatten helper
        def flatten(nodes, target_len):
            if not nodes:
                return np.zeros(target_len * 3)
            # Take up to target_len nodes
            subset = nodes[:target_len]
            # Pad if not enough
            while len(subset) < target_len:
                subset.append({"x": 0, "y": 0, "z": 0})
            
            arr = []
            for n in subset:
                arr.extend([n["x"], n["y"], n["z"]])
            return np.array(arr)

        # Pose: 10 nodes (indices 11-20 are upper body)
        pose_nodes = data.get("pose", [])
        if len(pose_nodes) > 20:
            pose_subset = pose_nodes[11:21]
        else:
            pose_subset = []
        pose_arr = flatten(pose_subset, 10) # 30 features

        # Face: 20 nodes (0-19)
        face_nodes = data.get("face", [])
        face_arr = flatten(face_nodes, 20) # 60 features

        # Left Hand: 21 nodes
        l_hand = data.get("left_hand", [])
        l_hand_arr = flatten(l_hand, 21) # 63 features

        # Right Hand: 21 nodes
        r_hand = data.get("right_hand", [])
        r_hand_arr = flatten(r_hand, 21) # 63 features

        # Total = 30 + 60 + 63 + 63 = 216
        combined = np.concatenate([pose_arr, face_arr, l_hand_arr, r_hand_arr])
        return combined

    def start_training(self):
        sentence = self.get_sentence()
        if not sentence: return
        
        self.is_recording_training = True
        self.training_sequences = []
        self.seq_count = 0
        self.train_btn.config(state="disabled")
        self.hero_btn.config(state="disabled")
        
        # Start a thread to manage the recording phases without freezing UI
        threading.Thread(target=self.training_loop).start()

    def training_loop(self):
        while self.seq_count < self.target_seqs:
            # 2 seconds prep time
            for i in range(2, 0, -1):
                self.status_label.config(text=f"Get Ready... {i}", fg="orange")
                time.sleep(1)
            
            self.status_label.config(text=f"RECORDING SEQUENCE {self.seq_count + 1}/{self.target_seqs}!", fg="red")
            self.current_sequence = []
            
            # Wait for 30 frames to be captured in the video update loop
            time.sleep(0.1) # small buffer
            start_t = time.time()
            while len(self.current_sequence) < self.frames_per_seq:
                if time.time() - start_t > 5: break # Timeout safeguard
                time.sleep(0.01)
                
            if len(self.current_sequence) == self.frames_per_seq:
                self.training_sequences.append(self.current_sequence)
                self.seq_count += 1
            
            self.status_label.config(text="Relax...", fg="blue")
            time.sleep(1)
            
        # Save training data
        sentence = self.get_sentence()
        np_data = np.array(self.training_sequences) # Shape (30, 30, 216)
        path = os.path.join(TRAIN_DIR, f"{sentence}.npy")
        np.save(path, np_data)
        
        self.is_recording_training = False
        self.status_label.config(text=f"Saved {self.target_seqs} sequences to {path}", fg="green")
        self.train_btn.config(state="normal")
        self.hero_btn.config(state="normal")

    def toggle_hero(self):
        if not self.is_recording_hero:
            sentence = self.get_sentence()
            if not sentence: return
            self.is_recording_hero = True
            self.hero_frames = []
            self.hero_btn.config(text="Stop Hero Take", bg="red")
            self.train_btn.config(state="disabled")
            self.status_label.config(text="RECORDING HERO TAKE! Perform clearly.", fg="red")
        else:
            self.is_recording_hero = False
            sentence = self.get_sentence()
            
            path = os.path.join(AVATAR_DIR, f"{sentence}_hero.json")
            with open(path, "w") as f:
                json.dump(self.hero_frames, f)
                
            self.hero_btn.config(text="Start Hero Avatar Take", bg="green")
            self.train_btn.config(state="normal")
            if hasattr(self, 'upload_btn'): self.upload_btn.config(state="normal")
            self.status_label.config(text=f"Saved Hero JSON to {path}", fg="green")

    def upload_video(self):
        sentence = self.get_sentence()
        if not sentence: return
        
        file_path = filedialog.askopenfilename(filetypes=[("Video Files", "*.mp4 *.avi *.mov")])
        if not file_path: return
        
        # Ask user if this is for Training Data or Hero Avatar
        mode = messagebox.askquestion("Mode Selection", "Do you want to process this as Training Data?\n(Yes = Slice into 30-frame chunks for AI)\n(No = Save entire clip for Hero Avatar playback)")
        
        self.train_btn.config(state="disabled")
        self.hero_btn.config(state="disabled")
        self.upload_btn.config(state="disabled")
        
        threading.Thread(target=self.process_video_file, args=(file_path, sentence, mode == 'yes')).start()

    def process_video_file(self, file_path, sentence, is_training):
        self.status_label.config(text=f"Processing Video...", fg="purple")
        vid_cap = cv2.VideoCapture(file_path)
        
        sequences = []
        current_seq = []
        hero_frames = []
        
        frame_count = 0
        while True:
            ret, frame = vid_cap.read()
            if not ret: break
            
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            data = mp_service.process_image(rgb_frame)
            
            if is_training:
                features = self.extract_216_features(data)
                current_seq.append(features)
                
                if len(current_seq) == self.frames_per_seq:
                    sequences.append(current_seq)
                    current_seq = []
            else:
                hero_frames.append(data)
                
            frame_count += 1
            if frame_count % 10 == 0:
                self.status_label.config(text=f"Processed {frame_count} frames...", fg="purple")
                
        vid_cap.release()
        
        if is_training:
            if not sequences:
                self.status_label.config(text="Video too short (less than 30 frames).", fg="red")
            else:
                np_data = np.array(sequences)
                
                path = os.path.join(TRAIN_DIR, f"{sentence}.npy")
                if os.path.exists(path):
                    existing_data = np.load(path)
                    np_data = np.concatenate([existing_data, np_data])
                    
                np.save(path, np_data)
                self.status_label.config(text=f"Appended {len(sequences)} chunks to {sentence}.npy", fg="green")
        else:
            path = os.path.join(AVATAR_DIR, f"{sentence}_hero.json")
            with open(path, "w") as f:
                json.dump(hero_frames, f)
            self.status_label.config(text=f"Saved Hero JSON ({frame_count} frames)", fg="green")
            
        self.window.after(0, lambda: self.train_btn.config(state="normal"))
        self.window.after(0, lambda: self.hero_btn.config(state="normal"))
        self.window.after(0, lambda: self.upload_btn.config(state="normal"))

    def update_video(self):
        ret, frame = self.cap.read()
        if ret:
            # Flip horizontally for selfie view
            frame = cv2.flip(frame, 1)
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            
            # Process via MediaPipe
            data = mp_service.process_image(rgb_frame)
            
            # Handle recording states
            status_text = self.status_label.cget("text")
            
            if self.is_recording_training:
                if "Get Ready" in status_text:
                    # Draw big orange countdown on video
                    cv2.putText(rgb_frame, status_text, (50, 200), cv2.FONT_HERSHEY_SIMPLEX, 2, (255, 165, 0), 5)
                elif "RECORDING" in status_text:
                    if len(self.current_sequence) < self.frames_per_seq:
                        features = self.extract_216_features(data)
                        self.current_sequence.append(features)
                    
                    # Draw big red recording indicator on video
                    cv2.putText(rgb_frame, f"RECORDING! ({len(self.current_sequence)}/{self.frames_per_seq})", (50, 200), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 0, 0), 4)
                    cv2.circle(rgb_frame, (30, 30), 15, (255, 0, 0), -1)
                elif "Relax" in status_text:
                    cv2.putText(rgb_frame, "Relax...", (50, 200), cv2.FONT_HERSHEY_SIMPLEX, 2, (0, 255, 0), 5)
                
            if self.is_recording_hero:
                self.hero_frames.append(data) # Store raw JSON for avatar
                cv2.putText(rgb_frame, "RECORDING HERO TAKE", (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 0, 0), 3)
                cv2.circle(rgb_frame, (30, 30), 15, (255, 0, 0), -1)

            # Update Canvas
            img = Image.fromarray(rgb_frame)
            imgtk = ImageTk.PhotoImage(image=img)
            self.video_label.imgtk = imgtk
            self.video_label.configure(image=imgtk)

        self.window.after(10, self.update_video)

    def on_closing(self):
        self.cap.release()
        self.window.destroy()

if __name__ == "__main__":
    root = tk.Tk()
    app = ISLRecorderApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_closing)
    root.mainloop()
