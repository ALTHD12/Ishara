"""
MP4 to ISL Sign Playback Converter
===================================
Reads a video file, runs MediaPipe Tasks API on every frame, and outputs
a .bytes file that the Flutter SigningPlaybackWidget can animate.

Usage:
    python mp4_to_sign.py <video_path> <sign_name>
    
Example:
    python mp4_to_sign.py videos/YOU.mp4 YOU

Output:
    ../sign_translator/assets/recordings/<SIGN_NAME>.bytes
"""

import sys
import os
import cv2
import numpy as np
import mediapipe as mp

# -------------------------------------------------------------------
# Layout of one frame (75 points x 3 coords = 225 floats):
#   [0..9]   = 10 Pose points  (shoulders, elbows, wrists, hips, knees)
#   [10..29] = 20 Face expression points (eyebrows, eyes, mouth)
#   [30..50] = 21 Left-hand points
#   [51..71] = 21 Right-hand points
#   [72..74] = 3 extra: nose tip, chin, forehead (for head shape)
# Total = 75 points * 3 = 225 floats per frame
# -------------------------------------------------------------------

POSE_INDICES = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26]

FACE_EXPR_INDICES = [
    # Left eyebrow (5)
    70, 63, 105, 66, 107,
    # Right eyebrow (5)
    300, 293, 334, 296, 336,
    # Left eye outline (4)
    33, 133, 159, 145,
    # Right eye outline (4)
    362, 263, 386, 374,
    # Mouth corners (2)
    61, 291,
]

HEAD_INDICES = [1, 152, 10]  # nose tip, chin, forehead


def setup_landmarkers():
    """Create MediaPipe Tasks landmarkers using the same .task files the project already has."""
    BaseOptions = mp.tasks.BaseOptions

    pose = mp.tasks.vision.PoseLandmarker.create_from_options(
        mp.tasks.vision.PoseLandmarkerOptions(
            base_options=BaseOptions(model_asset_path='pose_landmarker.task'),
            running_mode=mp.tasks.vision.RunningMode.IMAGE))

    hands = mp.tasks.vision.HandLandmarker.create_from_options(
        mp.tasks.vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path='hand_landmarker.task'),
            num_hands=2,
            running_mode=mp.tasks.vision.RunningMode.IMAGE))

    face = mp.tasks.vision.FaceLandmarker.create_from_options(
        mp.tasks.vision.FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path='face_landmarker.task'),
            running_mode=mp.tasks.vision.RunningMode.IMAGE))

    return pose, hands, face


def make_square(img_rgb):
    """Pad to square, return (squared_img, pad_left, pad_top, size, w, h)."""
    h, w, _ = img_rgb.shape
    size = max(h, w)
    pad_top = (size - h) // 2
    pad_bottom = size - h - pad_top
    pad_left = (size - w) // 2
    pad_right = size - w - pad_left
    squared = cv2.copyMakeBorder(
        img_rgb, pad_top, pad_bottom, pad_left, pad_right,
        cv2.BORDER_CONSTANT, value=[0, 0, 0])
    return squared, pad_left, pad_top, size, w, h


def unpad(node, pad_left, pad_top, size, w, h):
    """Convert padded-square coords back to original image 0..1 coords."""
    return (
        (node.x * size - pad_left) / w,
        (node.y * size - pad_top) / h,
        node.z
    )


def extract_frame(pose_res, hand_res, face_res, pad_left, pad_top, size, w, h):
    """Extract one frame's landmarks into a flat list of 225 floats."""
    out = []

    # --- Pose (10 points) ---
    for idx in POSE_INDICES:
        if pose_res.pose_landmarks and idx < len(pose_res.pose_landmarks[0]):
            x, y, z = unpad(pose_res.pose_landmarks[0][idx], pad_left, pad_top, size, w, h)
            out.extend([x, y, z])
        else:
            out.extend([0.0, 0.0, 0.0])

    # --- Face expression (20 points) ---
    for idx in FACE_EXPR_INDICES:
        if face_res.face_landmarks and idx < len(face_res.face_landmarks[0]):
            x, y, z = unpad(face_res.face_landmarks[0][idx], pad_left, pad_top, size, w, h)
            out.extend([x, y, z])
        else:
            out.extend([0.0, 0.0, 0.0])

    # --- Left hand (21 points) ---
    left_hand = None
    if hand_res.hand_landmarks and hand_res.handedness:
        for i, handedness in enumerate(hand_res.handedness):
            if handedness[0].category_name.lower() == "left":
                left_hand = hand_res.hand_landmarks[i]
    for j in range(21):
        if left_hand and j < len(left_hand):
            x, y, z = unpad(left_hand[j], pad_left, pad_top, size, w, h)
            out.extend([x, y, z])
        else:
            out.extend([0.0, 0.0, 0.0])

    # --- Right hand (21 points) ---
    right_hand = None
    if hand_res.hand_landmarks and hand_res.handedness:
        for i, handedness in enumerate(hand_res.handedness):
            if handedness[0].category_name.lower() == "right":
                right_hand = hand_res.hand_landmarks[i]
    for j in range(21):
        if right_hand and j < len(right_hand):
            x, y, z = unpad(right_hand[j], pad_left, pad_top, size, w, h)
            out.extend([x, y, z])
        else:
            out.extend([0.0, 0.0, 0.0])

    # --- Head orientation (3 points: nose tip, chin, forehead) ---
    for idx in HEAD_INDICES:
        if face_res.face_landmarks and idx < len(face_res.face_landmarks[0]):
            x, y, z = unpad(face_res.face_landmarks[0][idx], pad_left, pad_top, size, w, h)
            out.extend([x, y, z])
        else:
            out.extend([0.0, 0.0, 0.0])

    return out  # 75 * 3 = 225


def process_video(video_path, sign_name, target_fps=30):
    output_dir = "../sign_translator/assets/recordings"
    os.makedirs(output_dir, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"ERROR: Cannot open video: {video_path}")
        sys.exit(1)

    src_fps = cap.get(cv2.CAP_PROP_FPS) or 30
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / src_fps
    print(f"Video: {video_path}")
    print(f"  Resolution: {int(cap.get(3))}x{int(cap.get(4))}")
    print(f"  FPS: {src_fps:.1f}, Frames: {total_frames}, Duration: {duration:.1f}s")

    target_frame_count = int(duration * target_fps)
    if target_frame_count < 5:
        print("ERROR: Video is too short (need at least 0.2 seconds)")
        sys.exit(1)

    sample_indices = np.linspace(0, total_frames - 1, target_frame_count).astype(int)

    print("  Loading MediaPipe models...")
    pose_lm, hand_lm, face_lm = setup_landmarkers()

    all_frames = []
    processed = 0

    for target_idx in sample_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, target_idx)
        ret, frame = cap.read()
        if not ret:
            all_frames.append([0.0] * 225)
            continue

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        squared, pad_left, pad_top, size, w, h = make_square(rgb)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=squared)

        pose_res = pose_lm.detect(mp_image)
        hand_res = hand_lm.detect(mp_image)
        face_res = face_lm.detect(mp_image)

        frame_data = extract_frame(pose_res, hand_res, face_res, pad_left, pad_top, size, w, h)
        all_frames.append(frame_data)

        processed += 1
        if processed % 10 == 0:
            print(f"  Processed {processed}/{len(sample_indices)} frames...")

    cap.release()
    pose_lm.close()
    hand_lm.close()
    face_lm.close()

    if not all_frames:
        print("ERROR: No frames extracted.")
        sys.exit(1)

    print(f"  Extracted {len(all_frames)} total frames from the video.")

    # Convert to numpy for analysis
    all_frames_np = np.array(all_frames, dtype=np.float32)

    # We want to isolate the exact moment the sign happens!
    # A standard ISL sign takes about 2 seconds. At target_fps=30, that's 60 frames.
    WINDOW_SIZE = min(60, len(all_frames_np))

    best_window = all_frames_np
    if len(all_frames_np) > WINDOW_SIZE:
        print(f"  Auto-cropping to the best {WINDOW_SIZE}-frame action window...")
        max_movement = -1
        best_start_idx = 0
        
        # Slide a window across the entire video
        for i in range(len(all_frames_np) - WINDOW_SIZE + 1):
            window = all_frames_np[i : i + WINDOW_SIZE]
            
            # Extract just the hands (floats 90 to 216)
            hands = window[:, 90:216]
            
            # The "movement" is the sum of standard deviations of hand coordinates
            movement = np.sum(np.std(hands, axis=0))
            
            if movement > max_movement:
                max_movement = movement
                best_start_idx = i

        print(f"  Found action starting at frame {best_start_idx} (Score: {max_movement:.2f})")
        best_window = all_frames_np[best_start_idx : best_start_idx + WINDOW_SIZE]

    flat = best_window.flatten()
    out_path = os.path.join(output_dir, f"{sign_name}.bytes")

    with open(out_path, 'wb') as f:
        f.write(flat.tobytes())

    print(f"  Saved: {out_path} ({len(flat)} floats, {len(best_window)} frames)")
    print("Done!")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python mp4_to_sign.py <video_path> <sign_name>")
        print("Example: python mp4_to_sign.py videos/YOU.mp4 YOU")
        sys.exit(1)

    video_path = sys.argv[1]
    sign_name = sys.argv[2].upper()
    process_video(video_path, sign_name)
