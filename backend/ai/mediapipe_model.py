import os
import urllib.request
import mediapipe as mp
import cv2
import time

MODELS = {
    "pose_landmarker.task": "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task",
    "hand_landmarker.task": "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task",
    "face_landmarker.task": "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
}

# Download models if they don't exist
print("Checking for MediaPipe Task Models...")
for model_name, url in MODELS.items():
    if not os.path.exists(model_name):
        print(f"Downloading {model_name} (this may take a minute)...")
        urllib.request.urlretrieve(url, model_name)

BaseOptions = mp.tasks.BaseOptions
PoseLandmarker = mp.tasks.vision.PoseLandmarker
HandLandmarker = mp.tasks.vision.HandLandmarker
FaceLandmarker = mp.tasks.vision.FaceLandmarker

class MediaPipeService:
    """IMAGE-mode landmarkers (used for data recording, unchanged) plus
    VIDEO-mode landmarkers (live inference: temporal tracking, cheaper hand
    detection). Instances are created once and reused. Not thread-safe: call
    from a single worker thread."""

    def __init__(self):
        self.pose_landmarker, self.hand_landmarker, self.face_landmarker =             self._create(mp.tasks.vision.RunningMode.IMAGE)
        self.pose_video, self.hand_video, self.face_video =             self._create(mp.tasks.vision.RunningMode.VIDEO)
        self._last_ts_ms = -1
        print("MediaPipe Models loaded successfully!")

    @staticmethod
    def _create(mode):
        pose = PoseLandmarker.create_from_options(
            mp.tasks.vision.PoseLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='pose_landmarker.task'),
                running_mode=mode))
        hand = HandLandmarker.create_from_options(
            mp.tasks.vision.HandLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='hand_landmarker.task'),
                num_hands=2,
                running_mode=mode))
        face = FaceLandmarker.create_from_options(
            mp.tasks.vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='face_landmarker.task'),
                running_mode=mode))
        return pose, hand, face

    def next_timestamp_ms(self, t_ms=None):
        """Strictly increasing timestamp for VIDEO mode."""
        if t_ms is None:
            t_ms = time.monotonic() * 1000.0
        ts = max(int(t_ms), self._last_ts_ms + 1)
        self._last_ts_ms = ts
        return ts

    def extract_landmarks(self, pose_res, hand_res, face_res, pad_left, pad_top, size, w, h):
        data = {}
        def unpad(node):
            return {
                "x": (node.x * size - pad_left) / w,
                "y": (node.y * size - pad_top) / h,
                "z": node.z,
                "v": getattr(node, "visibility", 1.0)
            }
        
        if pose_res.pose_landmarks:
            data["pose"] = [unpad(res) for res in pose_res.pose_landmarks[0]]
        if face_res.face_landmarks:
            data["face"] = [unpad(res) for res in face_res.face_landmarks[0]]
        if hand_res.hand_landmarks and hand_res.handedness:
            for idx, handedness in enumerate(hand_res.handedness):
                label = handedness[0].category_name.lower()
                data[f"{label}_hand"] = [unpad(res) for res in hand_res.hand_landmarks[idx]]
                
        # Extract true 3D World Landmarks for Hands (explicit finger placement)
        if hand_res.hand_world_landmarks and hand_res.handedness:
            for idx, handedness in enumerate(hand_res.handedness):
                label = handedness[0].category_name.lower()
                data[f"{label}_hand_world"] = [
                    {"x": res.x, "y": res.y, "z": res.z} 
                    for res in hand_res.hand_world_landmarks[idx]
                ]
                
        return data

    @staticmethod
    def _square(img_rgb):
        h, w, _ = img_rgb.shape
        size = max(h, w)
        pad_top = (size - h) // 2
        pad_bottom = size - h - pad_top
        pad_left = (size - w) // 2
        pad_right = size - w - pad_left
        squared_img = cv2.copyMakeBorder(
            img_rgb, pad_top, pad_bottom, pad_left, pad_right,
            cv2.BORDER_CONSTANT, value=[0, 0, 0]
        )
        return squared_img, pad_left, pad_top, size, w, h

    def _run(self, img_rgb, timer, detect_pose, detect_hand, detect_face):
        squared_img, pad_left, pad_top, size, w, h = self._square(img_rgb)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=squared_img)

        t = time.perf_counter()
        pose_result = detect_pose(mp_image)
        t_pose = time.perf_counter()
        hand_result = detect_hand(mp_image)
        t_hand = time.perf_counter()
        face_result = detect_face(mp_image)
        t_face = time.perf_counter()
        if timer is not None:
            timer.add("mp_pose", (t_pose - t) * 1000.0)
            timer.add("mp_hand", (t_hand - t_pose) * 1000.0)
            timer.add("mp_face", (t_face - t_hand) * 1000.0)

        return self.extract_landmarks(
            pose_result, hand_result, face_result,
            pad_left, pad_top, size, w, h
        )

    def process_image(self, img_rgb, timer=None):
        """IMAGE mode: each frame independent (used for recording)."""
        return self._run(img_rgb, timer,
                         self.pose_landmarker.detect,
                         self.hand_landmarker.detect,
                         self.face_landmarker.detect)

    def process_video_frame(self, img_rgb, t_ms=None, timer=None):
        """VIDEO mode: tracks across frames. t_ms is made strictly increasing."""
        ts = self.next_timestamp_ms(t_ms)
        return self._run(img_rgb, timer,
                         lambda im: self.pose_video.detect_for_video(im, ts),
                         lambda im: self.hand_video.detect_for_video(im, ts),
                         lambda im: self.face_video.detect_for_video(im, ts))

# Global instance for routes to use
mp_service = MediaPipeService()
