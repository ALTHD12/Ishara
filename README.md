# Ishara - ISL Translator

This application is a real-time Indian Sign Language (ISL) translator. It uses a **Thin-Client Architecture** where the heavy Machine Learning models are offloaded to a high-performance Python backend, and the lightweight Flutter mobile app handles the camera and UI.

## 📱 Architecture Overview

1.  **Frontend (Flutter Mobile App)**
    *   Located in `sign_translator/`
    *   Handles UI, Camera stream, and WebSocket communication.
    *   No heavy processing is done here. The camera simply downsamples frames and streams them to the server.

2.  **Backend (Python FastAPI)**
    *   Located in `backend/`
    *   **MediaPipe AI:** Processes incoming frames over WebSocket to extract 553 holistic coordinates (Face, Pose, Hands).
    *   **spaCy NLP:** Converts English sentences into ISL Semantic Gloss structure via HTTP POST requests.

---

## 🛠️ How to Run the System

### 1. Start the Python Backend

1.  Open a terminal and navigate to the backend directory:
    ```bash
    cd backend
    ```
2.  Activate your virtual environment:
    *   **Windows**: `venv\Scripts\activate`
    *   **macOS/Linux**: `source venv/bin/activate`
3.  Start the FastAPI & WebSocket server:
    ```bash
    python main.py
    ```

### 2. Start the Flutter Mobile App

1.  Open a **new** terminal window and navigate to the app directory:
    ```bash
    cd sign_translator
    ```
2.  Connect your physical Android/iOS phone via USB (ensure USB Debugging is ON).
3.  Run the app:
    ```bash
    flutter run
    ```
