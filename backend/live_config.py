"""All live-inference tuning constants in one place.

Client-side counterparts live in sign_translator/lib/config/live_config.dart.
None of these change the model, the 342-dim features or the 30-frame window.
"""

# ── Window (must match training) ───────────────────────────────────────────
WINDOW_FRAMES = 30          # model input length (fixed by the trained model)
# Rate the 30-frame window represents. The bulk of the training data
# (AMBULANCE, CALL, HE, QUICKLY, SHE, UNCONSCIOUS: 174 windows each) was
# recorded at ~30 fps (900 frames / 30 s), so one window ~= 1 s of motion.
# Live frames are resampled onto this grid from their timestamps, so the
# window spans the same real time whatever the live frame rate is.
WINDOW_FPS = 30.0
RESAMPLE = True             # False = legacy "last 30 received frames"

# ── When to run the model ──────────────────────────────────────────────────
INFER_EVERY_N_FRAMES = 1    # legacy: 3
MIN_ACTIVE_FRACTION = 0.5   # legacy: 15/30 window samples must contain a hand

# ── Smoothing / decision ───────────────────────────────────────────────────
CONFIDENCE_THRESHOLD = 0.55  # legacy: 0.55
VOTE_HISTORY = 4             # legacy: 5 predictions
VOTES_TO_EMIT = 3            # legacy: 3 of 5
# After an emission, keep only the newest fraction of the window so the next
# decision needs fresh motion. legacy: keep last 15 of 30 frames.
FLUSH_KEEP_FRACTION = 0.5
# Same sign may be emitted again after this long (legacy: never twice in a row).
REPEAT_COOLDOWN_S = 1.5
# Clear the displayed sign after this long without hands (legacy: 60 frames).
NO_HAND_CLEAR_S = 2.0

# ── Frame pipeline ─────────────────────────────────────────────────────────
# VIDEO mode is ~25% faster (32 vs 43 ms/frame) but shifts features 0.3-1.3
# training-std vs IMAGE mode (all training data) and flips hand presence on
# 5-9% of frames (tools/compare_mp_modes.py). Enable only after re-recording
# training data in VIDEO mode.
MEDIAPIPE_VIDEO_MODE = False
# Overlay coordinates are rounded to this many decimals in responses.
OVERLAY_DECIMALS = 4
