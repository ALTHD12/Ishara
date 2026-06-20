import os
import urllib.request
import mediapipe as mp
import cv2

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
    def __init__(self):
        self.pose_landmarker = PoseLandmarker.create_from_options(
            mp.tasks.vision.PoseLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='pose_landmarker.task'),
                running_mode=mp.tasks.vision.RunningMode.IMAGE))

        self.hand_landmarker = HandLandmarker.create_from_options(
            mp.tasks.vision.HandLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='hand_landmarker.task'),
                num_hands=2,
                running_mode=mp.tasks.vision.RunningMode.IMAGE))

        self.face_landmarker = FaceLandmarker.create_from_options(
            mp.tasks.vision.FaceLandmarkerOptions(
                base_options=BaseOptions(model_asset_path='face_landmarker.task'),
                running_mode=mp.tasks.vision.RunningMode.IMAGE))
                
        print("MediaPipe Models loaded successfully!")

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
                
        return data

    def process_image(self, img_rgb):
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
        
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=squared_img)
        
        pose_result = self.pose_landmarker.detect(mp_image)
        hand_result = self.hand_landmarker.detect(mp_image)
        face_result = self.face_landmarker.detect(mp_image)
        
        return self.extract_landmarks(
            pose_result, hand_result, face_result, 
            pad_left, pad_top, size, w, h
        )

# Global instance for routes to use
mp_service = MediaPipeService()
