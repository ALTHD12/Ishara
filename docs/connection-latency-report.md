# Connection & latency report — branch `fix/connection-latency`

Device: Samsung SM-S918B (Android 16). Laptop: Windows 11, CPU only.
Backend measured with the root `.venv` (Python 3.14, TensorFlow 2.22.0rc0), because
`backend/venv` is broken (its base Python `C:\Applications\python` no longer exists).
No model, feature layout, window length or training data was changed.

## Root causes

| # | Cause | Evidence | Fixed? |
|---|---|---|---|
| 1 | **Eager Keras model call** blocked the WS loop for ~385 ms every 3rd frame | Step 1 timings: `s.model` p50 385 ms; graph-mode (`tf.function`) 17–21 ms, max output diff 1e-13 | Yes |
| 2 | **Temporal skew**: live window = last 30 *received* frames (~10 fps on device → ~3 s), but most training windows are 30 fps (~1 s) | 6 of 11 classes recorded at 29.8 fps; replaying training sessions at ≤12.7 fps through the legacy decoder emits **0 words** | Yes (timestamp resampling, no retraining) |
| 3 | Per-frame work on the UI thread (convert + 230 KB WebSocket masking/send) | `send` 24 ms + `convert` 1.7 ms + `parse` 1.4 ms on UI thread | Yes (background isolate) |
| 4 | Slow decision chain: infer every 3rd frame, 3-of-5 vote, client 2-consecutive, no repeats | `tools/sim_decoder.py` | Yes (tuned, see below) |
| 5 | Training data: 1 session per class, idle windows, leaky validation, 2.5–30 fps mix, body-framing shortcut | Step 5 | **No — needs re-recording + retraining** |

## Changes (commit order)

1. `542a70c` perf: per-stage latency instrumentation (`ISL_DEBUG_TIMING`, `--dart-define=ISL_DEBUG_TIMING=true`), `tools/sim_client.py`.
2. `350c875` feat: cable-free connection — server address setting (shared_preferences), status badge, idempotent connect, backoff 0.5–8 s, 2 s heartbeat / 6 s dead-link, background/resume handling; backend ping/pong, `GET /health`, `GET /` test page, optional robust adb tunnel, LAN IP banner, new `run.bat`.
3. `760e719` build: R8 `-dontwarn` for tflite GPU class — release APK did not build before.
4. `0a76143` perf(backend): graph-mode model, latest-frame-wins non-blocking pipeline, compact overlay JSON, optional capture timestamp, VIDEO mode (off), `features.py` (verbatim move), `LiveDecoder` + `live_config.py`.
5. `b1865c7` perf(backend): packed-YUV420 frames, bit-identical RGB (`frame_codec.py`, `tools/check_yuv_packing.py`); `ISL_DEBUG_SAVE_FRAMES`.
6. `c6f9a12` perf(app): `FrameLink` isolate, 12 fps cap + result/800 ms backpressure, word events (repeatable signs), `LiveConfig`.
7. `bc6383a` docs: VIDEO-mode note corrected.
8. `9b9bdab` tools: `analyze_training_data.py`, `replay_compare.py` (report only).

## Numbers

### Step 1 — which stage dominated (before)
Device over USB, release build, p50/p95 ms:

| convert (UI) | send (UI) | network+queue | server MediaPipe | **server model** | result→drawn | **capture→drawn** |
|---|---|---|---|---|---|---|
| 1.7 / 2.2 | 24 / 32 | 11 / 20 | 38 / 45 | **~390** (every 3rd frame) | 12 / 43 | **90 / ~500** |

MediaPipe breakdown: pose ~21, hand 9–16, face ~6 ms.

### Pipeline after

| | before | after |
|---|---|---|
| UI-thread work per frame | ~27 ms | **0.1 ms** |
| server model call | ~385 ms | ~20 ms |
| server RTT p95 (sim client, localhost) | 426 ms | 70 ms |
| server throughput (uncapped sim) | 12.7 fps | 21 fps |
| response JSON | ~7 KB | ~0.7 KB |
| frame bytes on the wire | 230 KB | 115 KB (lossless) |
| capture→drawn, USB | 90 / ~500 ms | ~77 / ~90 ms (RGB build) |
| capture→drawn, **Wi-Fi** | — (cable only) | **82 / ~100 ms** |

### Sign start → word displayed
Simulated by replaying the recorded sessions through each decoder at the device's effective rate (~10 fps).
These sessions were training data, so accuracy is optimistic; latency is the comparison.

| | onset → word p50 | p90 | onsets that produce a word |
|---|---|---|---|
| Before (legacy decoder @10 fps) | never | never | **0 %** |
| Before, if it had run at 15 / 30 fps | 1.90 s / 1.13 s | — | 11 % / 15 % |
| **After** (resampled, every-frame, 3-of-4, 1.5 s cooldown) | **0.85 s** + ~0.08 s pipeline | 1.69 s | **67 %** (98 % correct) |

Not yet measured with a live signer.

## Feature-safety checks
- `extract_342_features` moved byte-for-byte (diff only a trailing newline).
- Recording path: identical `.npy` vs legacy pipeline (in-process test, scratch dir).
- Packed YUV: bit-identical RGB to the Dart converter (4 stride/size cases).
- Frame size/conversion unchanged (~300px rule, same integer YUV math). Device frames dumped: upright, correct colour, no distortion.
- **bgra8888 on Android**: `camera_android 0.10.10+18` maps `bgra8888` → `yuv420` (`lib/src/utils.dart:125`), so it cannot be "restored" there; Android always streamed yuv420.
- **VIDEO mode**: ~25 % faster (32 vs 43 ms) but features shift 0.3–1.3 training-std and hand presence differs on 5–9 % of frames vs IMAGE mode → left **off** (`MEDIAPIPE_VIDEO_MODE`).

## Step 5 findings (no fixes applied)

`python tools/analyze_training_data.py`:

| file | windows | sessions | ~fps | idle windows |
|---|---|---|---|---|
| AMBULANCE | 174 | 1 | 29.8 | 17.2 % |
| BLOOD | 23 | 2 | 2.8 | 39.1 % |
| BREATH | 14 | 1 | 3.2 | 78.6 % |
| CALL | 174 | 1 | 29.8 | 10.3 % |
| EMERGENCY | 10 | 1 | 2.5 | 0 % |
| HE | 174 | 1 | 29.8 | 2.3 % |
| QUICKLY | 174 | 1 | 29.8 | 2.3 % |
| ROOM | 10 | 1 | 2.5 | 20.0 % |
| SHE | 174 | 1 | 29.8 | 18.4 % |
| THIS | 11 | 1 | 2.7 | 63.6 % |
| UNCONSCIOUS | 174 | 1 | 29.8 | 2.9 % |
| GO / WHERE / YOU* | 35 / 29 / 31 | 1 | 6.7 / 5.7 / 6.0 | 66 / 10 / 65 % |

\* on disk but **not in the deployed model** (11 classes).

- **Idle windows confirmed**: recording has no active-hand filter (`process_frame` appends every frame); live inference skips windows with <15/30 active frames. 13.9 % of all windows are ones live would never classify; BREATH 79 %, THIS 64 %.
- **Validation leakage confirmed**: with the training split, 100 % of validation windows overlap a training window of the same session, 94–95 % share 25/30 frames, 95 % have every frame seen in training.
- **One session per class + framing shortcut**: logistic regression on window-averaged **pose+face only (no hands)** gets **97.3 %** on the same split. Classes are separable by body position/framing, so high accuracy does not show the model learned the signs.
- **Mixed recording rates** (2.5–30 fps) mean windows span 1 s to 12 s.
- **Replay vs training** (`tools/replay_compare.py videos/GO.mp4 --label GO --mirror`): no NaNs. A different setup shifts pose by 4–12 training-std and face presence 95 %→0–6 %. The mirrored replay moves the hand to the other slot and flips wrist side, so mirroring changes which half of the feature vector is used.

### Re-recording / retraining needed
1. ≥3–5 sessions per class, different days, people, distances and backgrounds, all recorded with the phone app (front camera, portrait).
2. Record on the 30 fps timestamp grid (reuse `resample_window` in the recorder), so every window = 1 s.
3. Drop or trim idle windows at recording (same ≥15/30 active rule as inference).
4. Split train/val **by session**, never by window. Rebalance classes (174 vs 10).
5. Retrain including GO/WHERE/YOU, or delete those files.
6. Only then consider VIDEO mode (record in VIDEO mode too) and tune `CONFIDENCE_THRESHOLD` on held-out sessions. On training data it has no effect (0.55 vs 0.70 identical).

## Left unfixed / not verified
- Overlay alignment not visually confirmed with a person in view. The geometry is consistent with the dumped frames.
- `send` in the isolate is still ~22 ms (dart:io masks every byte); it no longer blocks UI.
- `backend/venv` broken; `run.bat` detects this and prints rebuild steps.
- `tflite_flutter` and `image` dependencies unused (APK 89 MB).
- `camera_screen.dart` still stale (wrong `processFrame` arity).
- `backend/**/__pycache__/*.pyc` are tracked in git.
- CLAUDE.md is out of date: `Flutter/` is the Flutter SDK on PATH (not dead), `run.bat` now works, thresholds moved to `backend/live_config.py` / `lib/config/live_config.dart`.

## Demo checklist (cable-free)

**Laptop (once)**
1. Python env: `backend\venv` must be rebuilt (Python 3.10–3.13):
   `cd backend && py -3.12 -m venv venv && venv\Scripts\python -m pip install -r requirements.txt && venv\Scripts\python -m spacy download en_core_web_sm`
2. Firewall (admin PowerShell):
   `New-NetFirewallRule -DisplayName "Ishara backend 8765" -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private,Public`
   (Wi-Fi reached it in testing because Python already had an app rule, which may not hold on another laptop.)

**Build & install the release APK (once)**
3. `cd sign_translator && flutter build apk --release`
   → `build\app\outputs\flutter-apk\app-release.apk`
4. Install without a cable: copy the APK to the phone (Drive / USB stick / Nearby Share) and open it (allow "install unknown apps"), or `adb pair` + `adb connect` (Wireless debugging) then `adb install -r app-release.apk`.

**Each demo**
5. Network: phone hotspot ON → laptop joins it (or both on the same Wi-Fi). Set the hotspot network as *Private* on Windows, or keep `Public` in the firewall rule.
6. Laptop: `run.bat nousb` → note the printed `ws://<laptop-ip>:8765/`.
7. Phone browser: `http://<laptop-ip>:8765/` → must say "reachable … WebSocket OK".
8. App: ☰ → BACKEND SERVER → `<laptop-ip>:8765` → SAVE & CONNECT → badge shows **ONLINE nn ms**.
9. START TRANSLATING. If the badge goes RECONNECTING it retries by itself; tap it to retry now.
10. Latency debugging: `run.bat debug` and build with `--dart-define=ISL_DEBUG_TIMING=true` (logcat `[TIMING client]`).
