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

## 🗂️ Project Structure

> Note: filenames below reflect the standard layout for a FastAPI + Flutter project of this kind. Rename/adjust paths in this section to match your repo exactly if anything has diverged.

```
Ishara/
├── backend/                        # Python FastAPI service (ML + NLP)
│   ├── main.py                     # FastAPI app entrypoint — starts HTTP + WebSocket server
│   ├── requirements.txt            # Python dependencies (fastapi, uvicorn, mediapipe, spacy, etc.)
│   ├── venv/                       # Local virtual environment (not committed)
│   │
│   ├── routers/                    # API route definitions
│   │   ├── websocket_routes.py     # /ws endpoint — receives camera frames, streams predictions
│   │   └── nlp_routes.py           # /translate (or similar) — English → ISL gloss endpoint
│   │
│   ├── services/                   # Core processing logic
│   │   ├── mediapipe_service.py    # Holistic model wrapper — extracts 553 face/pose/hand landmarks
│   │   ├── gloss_service.py        # spaCy-based English → ISL Semantic Gloss conversion
│   │   └── model_inference.py      # Loads trained sign-classification model, runs predictions
│   │
│   ├── models/                     # Saved/trained ML models (e.g. .h5, .pkl, .onnx)
│   │
│   ├── schemas/                    # Pydantic request/response models
│   │   └── translation_schema.py
│   │
│   └── utils/                      # Helper functions (frame decoding, normalization, etc.)
│
├── sign_translator/                 # Flutter mobile app (thin client)
│   ├── lib/
│   │   ├── main.dart               # App entrypoint
│   │   ├── screens/                # UI screens (camera view, results, settings)
│   │   ├── services/               # WebSocket client, HTTP client for backend calls
│   │   ├── widgets/                # Reusable UI components
│   │   └── models/                 # Dart data models mirroring backend schemas
│   │
│   ├── android/                    # Android platform project
│   ├── ios/                        # iOS platform project
│   ├── assets/                     # Icons, fonts, sample images
│   ├── pubspec.yaml                # Flutter/Dart dependencies
│   └── test/                       # Widget/unit tests
│
├── Flutter/                         # (Additional Flutter-related resources/tooling, if separate from sign_translator/)
│
├── run.bat                          # Windows helper script to launch backend + app
├── .gitignore
└── README.md
```

### Key file responsibilities

| Path | Responsibility |
|---|---|
| `backend/main.py` | Boots the FastAPI server, mounts REST + WebSocket routes |
| `backend/services/mediapipe_service.py` | Runs MediaPipe Holistic on incoming frames to extract 553 landmark coordinates |
| `backend/services/gloss_service.py` | Uses spaCy to convert English sentences into ISL gloss order/structure |
| `backend/services/model_inference.py` | Feeds landmark sequences into the trained sign-recognition model |
| `sign_translator/lib/main.dart` | Flutter app entrypoint — initializes camera and navigation |
| `sign_translator/lib/services/` | Manages the WebSocket connection streaming frames to the backend |
| `run.bat` | One-click script to start both backend and Flutter app on Windows |

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
3.  Install dependencies (first run only):
    ```bash
    pip install -r requirements.txt
    ```
4.  Start the FastAPI & WebSocket server:
    ```bash
    python main.py
    ```

### 2. Start the Flutter Mobile App

1.  Open a **new** terminal window and navigate to the app directory:
    ```bash
    cd sign_translator
    ```
2.  Connect your physical Android/iOS phone via USB (ensure USB Debugging is ON).
3.  Install dependencies (first run only):
    ```bash
    flutter pub get
    ```
4.  Run the app:
    ```bash
    flutter run
    ```

### Windows Quick Start

On Windows, you can use the provided helper script to launch both services at once:
```bash
run.bat
```

---

## 📦 Requirements

- Python 3.9+ (backend)
- Flutter SDK (frontend) — Android Studio / Xcode for platform builds
- A physical Android or iOS device (camera access is required; emulators are not recommended for real-time camera streaming)

