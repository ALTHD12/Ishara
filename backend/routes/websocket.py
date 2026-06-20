import json
import cv2
import numpy as np
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ai.mediapipe_model import mp_service

router = APIRouter()

@router.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Flutter Client connected!")
    try:
        while True:
            message = await websocket.receive_bytes()
            try:
                if len(message) < 12:
                    continue
                    
                width = int.from_bytes(message[0:4], byteorder='big')
                height = int.from_bytes(message[4:8], byteorder='big')
                rotation = int.from_bytes(message[8:12], byteorder='big')
                
                rgb_data = message[12:]
                expected_size = width * height * 3
                if len(rgb_data) != expected_size:
                    continue
                    
                img_rgb = np.frombuffer(rgb_data, dtype=np.uint8).reshape((height, width, 3))
                
                if rotation == 90:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_CLOCKWISE)
                elif rotation == 270:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_90_COUNTERCLOCKWISE)
                elif rotation == 180:
                    img_rgb = cv2.rotate(img_rgb, cv2.ROTATE_180)
                    
                landmarks = mp_service.process_image(img_rgb)
                await websocket.send_text(json.dumps(landmarks))
                
            except Exception as frame_error:
                print(f"Skipped frame due to error: {frame_error}")
                continue
                
    except WebSocketDisconnect:
        print("Flutter Client disconnected.")
