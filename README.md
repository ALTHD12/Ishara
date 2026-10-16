# Ishara - ISL Translator

Real-time **Indian Sign Language** translator for emergency use (hospital / accident). A thin Flutter app on the phone streams camera frames to a Python backend on a laptop. The backend runs MediaPipe and a BiLSTM sign classifier, then sends back landmarks and recognised words. Works over USB or **cable-free over Wi-Fi / phone hotspot**.

## 📱 Architecture

```
Flutter app (sign_translator/) ──ws://<laptop-ip>:8765/──► FastAPI backend (backend/)
  camera → YUV frames (background isolate)     ├─ MediaPipe → 342-dim features → BiLSTM → words
                                               └─ spaCy NLP: POST /english-to-isl, /isl-to-english
```

- **Port** `8765`, WebSocket path `/` (bare root). `GET /health` and `GET /` (browser test page) on the same port.
- **Features**: 342 dims per frame (pose 30, face 60, L/R hand 63+63, L/R hand-world 63+63), window of 30 frames.

## 🗂️ Project structure

```
backend/
  main.py                 # FastAPI app, LAN IP banner, /health, optional adb USB tunnel
  routes/websocket.py     # live WS: frame decode, MediaPipe, inference, recording, training trigger
  routes/nlp.py           # English <-> ISL gloss endpoints
  live_config.py          # ALL live-inference thresholds (one place)
  live_decoder.py         # time-based decision logic (resampling, vote, cooldown)
  features.py             # extract_342_features - shared by recording AND inference
  frame_codec.py          # packed YUV420 -> RGB (bit-identical to the app's conversion)
  ai/mediapipe_model.py   # MediaPipe pose/hand/face landmarkers
  ai/bilstm_model.py      # model definition + training script
  ai/isl_model.keras      # trained model (11 classes, ai/label_encoder_classes.json)
  data/training_data/     # <LABEL>.npy, shape (N, 30, 342)
  tools/                  # measurement / analysis scripts (see below)
sign_translator/lib/
  config/app_config.dart  # server address (editable in app, saved on device)
  config/live_config.dart # client-side live thresholds
  services/frame_link.dart            # background isolate owning the WebSocket
  services/sign_classifier_service.dart  # connection, reconnect, heartbeat, backpressure
  screens/isl_to_english_screen.dart  # live sign -> English
  screens/data_recorder_screen.dart   # 30 s training-data recording
docs/connection-latency-report.md     # detailed measurements and findings
run.bat                               # backend launcher
Flutter/                              # the Flutter SDK used on this machine (on PATH)
```

## 🛠️ How to run

### 1. Backend (terminal 1)

One-time setup (Python **3.10–3.13**; TensorFlow has no stable build for 3.14):
```bash
cd backend
py -3.12 -m venv --clear venv
venv\Scripts\python -m pip install -r requirements.txt
venv\Scripts\python -m spacy download en_core_web_sm
```

Start:
```bash
run.bat            # normal
run.bat debug      # + per-stage latency logs
run.bat nousb      # Wi-Fi only, no adb tunnel
```
The banner prints the address for the app, e.g. `192.168.68.104:8765`. To use a different interpreter: `set ISL_PYTHON=C:\path\to\python.exe` before `run.bat`.

### 2. App (terminal 2, phone on USB with USB debugging on)
```bash
cd sign_translator
flutter pub get
flutter run --release
```
In the app: **☰ → BACKEND SERVER** (or long-press the status badge):
- USB cable: `127.0.0.1:8765`
- Wi-Fi / hotspot: the laptop IP from the banner

The badge shows ONLINE / RECONNECTING; tap it to retry now.

### Cable-free demo checklist
1. Allow port 8765 through the Windows firewall (admin PowerShell, once):
   `New-NetFirewallRule -DisplayName "Ishara backend 8765" -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private,Public`
2. Build the APK once: `flutter build apk --release` → `build\app\outputs\flutter-apk\app-release.apk`. Install it by copying it to the phone, or with `adb install -r`.
3. Turn the phone hotspot on and connect the laptop to it (or put both on the same Wi-Fi).
4. `run.bat nousb`, then on the phone's browser open `http://<laptop-ip>:8765/`. It should say "reachable … WebSocket OK".
5. Set the server in the app, then START TRANSLATING.

### Debug / measurement
- Latency logs: `run.bat debug` + `flutter run --release --dart-define=ISL_DEBUG_TIMING=true` (logcat `[TIMING client]`).
- `ISL_DEBUG_SAVE_FRAMES=<dir>` saves every 30th received frame as PNG.
- `backend/tools/`:
  - `sim_client.py`: stream a video like the phone does
  - `sim_decoder.py`: decision-latency simulation
  - `compare_mp_modes.py`: MediaPipe IMAGE vs VIDEO mode comparison
  - `check_yuv_packing.py`: YUV packing check
  - `analyze_training_data.py`: training-data audit
  - `replay_compare.py`: replay vs training-data comparison

## 📝 Notes for developers

**Rules**
- `extract_342_features()` is shared by training and inference. Changing it, the 342-dim layout or the 30-frame window means re-recording all data and retraining.
- Tune live behaviour only in `backend/live_config.py` and `sign_translator/lib/config/live_config.dart`.
- Ask before deleting anything in `backend/data/training_data/`.

**Latency work done** (details in `docs/connection-latency-report.md`)
- Model runs in graph mode: ~385 ms → ~20 ms per call. This eager-Keras stall was the main delay.
- Frame processing moved off the WebSocket receive loop and the phone's UI thread. Frames are sent as packed YUV (half the bytes, identical pixels), capped at 12 fps with backpressure.
- Live window is resampled by timestamp to 30 fps, so 30 frames ≈ 1 s, as in most training data. Before, at the phone's ~10 fps, the window spanned ~3 s and replayed sessions produced no words.
- The same sign can now be repeated (1.5 s cooldown).
- Camera→overlay over Wi-Fi: ~82 ms p50 (was ~90 / ~500 ms p50/p95 over USB).

**Known problems (not fixed - need re-recording + retraining)**
- One recording session per class; body/face position alone separates the classes (97%), so the model may not have learned the signs themselves.
- No active-hand filter while recording: 13.9% of windows are idle (up to 79% for BREATH).
- Validation split is leaky: overlapping windows from the same session land in train and val.
- Recording rates vary from 2.5 to 30 fps; class sizes from 10 to 174 windows.
- GO / WHERE / YOU have data but are not in the trained model.
- MediaPipe VIDEO mode is ~25% faster but shifts features, so it stays off (`MEDIAPIPE_VIDEO_MODE`).

**Next steps**
1. Test with a live signer; confirm the overlay sits on hands/face.
2. Re-record 3–5+ sessions per class (different people/places), record on a 30 fps timestamp grid, drop idle windows, split train/val by session, rebalance, retrain.
3. Cleanup: remove unused `tflite_flutter` / `image` deps (APK 89 MB), fix or delete stale `screens/camera_screen.dart`, stop tracking `__pycache__`.

## 📦 Requirements
- Python 3.10–3.13 (backend)
- Flutter SDK; Android Studio for Android builds (Gradle needs JDK 17)
- A physical Android phone (camera required)
