"""Problem B: does the overlay land on the person, and how jittery are raw landmarks?

1. Mapping check. Takes a frame from a video (person in view), emulates the
   phone: rotates the upright image into the camera sensor's orientation
   (front: sensorOrientation 270, back: 90), sends it through the real
   routes.websocket.process_frame (rotation header -> cv2.rotate -> MediaPipe
   IMAGE mode -> compact JSON), then draws the returned points the way
   HolisticNodePainter does (front camera: x' = 1 - x on the mirrored preview).
   Writes PNGs to --out for visual inspection.

2. Jitter. Runs the video at --fps through the same path and measures, in
   preview pixels (360 px wide portrait preview), the frame-to-frame noise of
   raw landmarks (residual vs. a centred 3-frame mean) and what an EMA does to
   noise and lag.

    cd backend && venv\\Scripts\\python tools/overlay_check.py videos/GO.mp4 --out ../docs/overlay_check
"""
import argparse
import os
import struct
import sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from sim_client import load_frames  # noqa: E402
from routes import websocket as ws  # noqa: E402

HAND = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11),
        (11, 12), (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (0, 17), (17, 18), (18, 19), (19, 20)]
POSE = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24)]


def to_sensor(upright, sensor_orientation):
    """Raw camera buffer R such that rotating R clockwise by sensorOrientation gives upright."""
    if sensor_orientation == 270:
        return cv2.rotate(upright, cv2.ROTATE_90_CLOCKWISE)
    if sensor_orientation == 90:
        return cv2.rotate(upright, cv2.ROTATE_90_COUNTERCLOCKWISE)
    return upright


def send(st, raw, rotation):
    h, w, _ = raw.shape
    msg = struct.pack(">iii", rotation, w, h) + np.ascontiguousarray(raw).tobytes()
    return ws.process_frame(st, msg, 0.0, None)


def draw(preview, out, mirror):
    H, W = preview.shape[:2]
    img = preview.copy()

    def P(n):
        x, y = n
        return int(round(((1 - x) if mirror else x) * W)), int(round(y * H))

    for key, conns, col in (("left_hand", HAND, (255, 255, 255)), ("right_hand", HAND, (0, 255, 255)),
                            ("pose", POSE, (0, 200, 0))):
        pts = out.get(key) or []
        for a, b in conns:
            if a < len(pts) and b < len(pts):
                cv2.line(img, P(pts[a]), P(pts[b]), col, 1)
        for i, p in enumerate(pts):
            if key != "pose" or i in (0, 11, 12, 13, 14, 15, 16):
                cv2.circle(img, P(p), 2, col, -1)
    for p in (out.get("face") or [])[::12]:
        cv2.circle(img, P(p), 1, (255, 0, 255), -1)
    return img


def jitter(frames, fps, src_fps=30.0):
    st = ws.ConnState()
    st.is_recording_mode = True          # landmarks only, no decoder
    st.recording_state = "idle"
    step = max(1, int(round(src_fps / fps)))
    seq = []
    for f in frames[::step]:
        out = send(st, to_sensor(f, 270), 270)
        seq.append(out)
    W = 360.0                              # portrait preview width in px
    H = W * frames[0].shape[0] / frames[0].shape[1]
    res = {}
    for key in ("right_hand", "left_hand", "pose", "face"):
        tracks = [np.array(o[key]) if key in o else None for o in seq]
        resid, ema_resid, ema_lag = [], [], []
        for alpha in (0.5,):
            prev = None
            emas = []
            for t in tracks:
                if t is None:
                    prev = None
                    emas.append(None)
                    continue
                prev = t if prev is None or prev.shape != t.shape else prev + alpha * (t - prev)
                emas.append(prev)
        for i in range(1, len(tracks) - 1):
            a, b, c = tracks[i - 1], tracks[i], tracks[i + 1]
            if a is None or b is None or c is None or not (a.shape == b.shape == c.shape):
                continue
            mid = (a + c) / 2
            scale = np.array([W, H])
            resid.append(np.median(np.linalg.norm((b - mid) * scale, axis=1)))
            if emas[i] is not None:
                ema_lag.append(np.median(np.linalg.norm((emas[i] - b) * scale, axis=1)))
            e0, e1, e2 = emas[i - 1], emas[i], emas[i + 1]
            if e0 is not None and e1 is not None and e2 is not None:
                ema_resid.append(np.median(np.linalg.norm((e1 - (e0 + e2) / 2) * scale, axis=1)))
        present = sum(t is not None for t in tracks) / len(tracks)
        res[key] = (present, np.median(resid) if resid else np.nan,
                    np.median(ema_resid) if ema_resid else np.nan,
                    np.median(ema_lag) if ema_lag else np.nan)
    return res


def static_jitter(frame, n=20, sigma=3.0):
    """Same frame + fresh sensor-like noise each time = a perfectly still person.
    Spread of the returned landmarks is pure detection jitter (preview px)."""
    st = ws.ConnState()
    st.is_recording_mode = True
    st.recording_state = "idle"
    rng = np.random.default_rng(0)
    W = 360.0
    H = W * frame.shape[0] / frame.shape[1]
    got = {}
    for _ in range(n):
        noisy = np.clip(frame.astype(np.float32) + rng.normal(0, sigma, frame.shape), 0, 255).astype(np.uint8)
        out = send(st, to_sensor(noisy, 270), 270)
        for key in ("right_hand", "left_hand", "pose", "face"):
            if key in out:
                got.setdefault(key, []).append(np.array(out[key]))
    res = {}
    for key, arrs in got.items():
        a = np.stack([x for x in arrs if x.shape == arrs[0].shape]) * np.array([W, H])
        dev = np.linalg.norm(a - a.mean(0), axis=2)          # (n, points)
        res[key] = (len(arrs) / n, float(np.median(dev)), float(np.percentile(dev, 95)))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--out", default="../docs/overlay_check")
    ap.add_argument("--fps", type=float, default=10.0)
    a = ap.parse_args()
    frames = load_frames([a.video], 320)
    os.makedirs(a.out, exist_ok=True)
    st = ws.ConnState()
    st.is_recording_mode = True
    st.recording_state = "idle"
    picks = [len(frames) // 3, len(frames) // 2]
    for k in picks:
        up = frames[k]
        for cam, so in (("front", 270), ("back", 90)):
            out = send(st, to_sensor(up, so), so)
            mirror = cam == "front"
            preview = cv2.flip(up, 1) if mirror else up   # CameraPreview mirrors the front camera
            img = draw(preview, out, mirror)
            path = os.path.join(a.out, f"overlay_{cam}_{k:04d}.png")
            big = cv2.resize(img, (img.shape[1] * 2, img.shape[0] * 2), interpolation=cv2.INTER_NEAREST)
            cv2.imwrite(path, cv2.cvtColor(big, cv2.COLOR_RGB2BGR))
            print(f"{path}: frame {up.shape[1]}x{up.shape[0]}  keys={sorted(k2 for k2 in out if isinstance(out[k2], list))}")
    print(f"\nraw landmark jitter @ {a.fps:g} fps, preview 360 px wide (median px per point)")
    print(f"{'part':<12}{'present':>8}{'raw noise':>11}{'EMA0.5 noise':>14}{'EMA lag':>9}")
    for key, (p, r, e, lag) in jitter(frames, a.fps).items():
        print(f"{key:<12}{p * 100:7.0f}%{r:11.1f}{e:14.1f}{lag:9.1f}")
    print("(moving hand: 'raw noise' includes real motion, not only jitter)")
    print("\nstatic person (frame %d + sensor noise sigma 3, 20 runs): detection jitter, preview px" % picks[1])
    print(f"{'part':<12}{'detected':>9}{'median':>8}{'p95':>8}")
    for key, (p, med, p95) in static_jitter(frames[picks[1]]).items():
        print(f"{key:<12}{p * 100:8.0f}%{med:8.1f}{p95:8.1f}")


if __name__ == "__main__":
    main()
