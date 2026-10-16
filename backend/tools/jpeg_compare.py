"""Problem C: would JPEG frames change the model's input? (evaluation only)

Paired comparison on the same frames:
  current : RGB -> YUV420 (phone camera) -> frame_codec.packed_yuv420_to_rgb
  jpeg qN : current RGB -> JPEG quality N -> decode
Both -> MediaPipe IMAGE mode -> extract_342_features. Reports payload size,
per-block feature shift in training-std units, hand-presence flips, model
top-class agreement and probability shift on 30-frame windows, and encode /
decode time on this laptop. Optionally dumps PNGs of both variants so
tools/replay_compare.py can be run on each (--dump DIR).

    cd backend && venv\\Scripts\\python tools/jpeg_compare.py videos/GO.mp4 videos/YOU.mp4 videos/WHERE.mp4
"""
import argparse
import glob
import os
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from features import BLOCKS, extract_342_features  # noqa: E402
from frame_codec import packed_yuv420_to_rgb  # noqa: E402
from replay_compare import read_frames  # noqa: E402


def current_rgb(rgb):
    h, w = rgb.shape[:2]
    h, w = h - h % 2, w - w % 2
    yuv = cv2.cvtColor(np.ascontiguousarray(rgb[:h, :w]), cv2.COLOR_RGB2YUV_I420).tobytes()
    return packed_yuv420_to_rgb(yuv, w, h), len(yuv)


def jpeg_rgb(rgb, q):
    t = time.perf_counter()
    ok, enc = cv2.imencode(".jpg", cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, q])
    t_enc = time.perf_counter() - t
    t = time.perf_counter()
    dec = cv2.cvtColor(cv2.imdecode(enc, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    return dec, len(enc), t_enc, time.perf_counter() - t


def noise_rgb(rgb, sigma, rng=np.random.default_rng(0)):
    """Control: imperceptible sensor-like noise, the natural frame-to-frame variation."""
    return np.clip(rgb.astype(np.float32) + rng.normal(0, sigma, rgb.shape), 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("videos", nargs="+")
    ap.add_argument("--qualities", default="95,85,75,60")
    ap.add_argument("--fps", type=float, default=10)
    ap.add_argument("--dump", help="write PNGs to DIR/current and DIR/jpeg<q>")
    ap.add_argument("--noise", type=float, default=1.0, help="sigma of the noise control row")
    a = ap.parse_args()
    from ai.mediapipe_model import mp_service
    from routes.websocket import predict_window

    train = np.concatenate([np.load(f).reshape(-1, 342) for f in glob.glob("data/training_data/*.npy")])
    std = train.std(0) + 1e-6
    qs = [int(q) for q in a.qualities.split(",")] + [-1]   # -1 = noise control

    base, var = [], {q: [] for q in qs}
    sizes = {"yuv": [], **{q: [] for q in qs}}
    t_enc = {q: [] for q in qs}
    t_dec = {q: [] for q in qs}
    for v in a.videos:
        frames, src_fps = read_frames(v, 25)
        step = max(1, int(round(src_fps / a.fps)))
        for i, f in enumerate(frames[::step]):
            cur, n = current_rgb(f)
            sizes["yuv"].append(n)
            base.append(extract_342_features(mp_service.process_image(cur)))
            if a.dump:
                os.makedirs(os.path.join(a.dump, "current"), exist_ok=True)
                cv2.imwrite(os.path.join(a.dump, "current", f"{os.path.basename(v)}_{i:04d}.png"),
                            cv2.cvtColor(cur, cv2.COLOR_RGB2BGR))
            for q in qs:
                j, n, te, td = jpeg_rgb(cur, q) if q > 0 else (noise_rgb(cur, a.noise), sizes["yuv"][-1], 0.0, 0.0)
                sizes[q].append(n)
                t_enc[q].append(te * 1000)
                t_dec[q].append(td * 1000)
                var[q].append(extract_342_features(mp_service.process_image(j)))
                if a.dump:
                    d = os.path.join(a.dump, f"jpeg{q}")
                    os.makedirs(d, exist_ok=True)
                    cv2.imwrite(os.path.join(d, f"{os.path.basename(v)}_{i:04d}.png"), cv2.cvtColor(j, cv2.COLOR_RGB2BGR))
    base = np.array(base, np.float32)
    print(f"frames={len(base)}  current packed-YUV payload={np.mean(sizes['yuv']) / 1024:.1f} KB")

    def windows(x):
        return np.stack([x[i:i + 30] for i in range(0, len(x) - 30, 5)]) if len(x) > 30 else np.zeros((0, 30, 342))

    pb = [predict_window(w) for w in windows(base)]
    print(f"\n{'variant':<9}{'KB':>6}{'x smaller':>10}{'enc ms':>8}{'dec ms':>8}  "
          + "".join(f"{n[:9]:>10}" for n in BLOCKS) + f"{'hand flip':>10}{'top agree':>10}{'|dp| max':>9}")
    for q in qs:
        x = np.array(var[q], np.float32)
        cells = []
        for name, sl in BLOCKS.items():
            both = np.any(base[:, sl] != 0, 1) & np.any(x[:, sl] != 0, 1)
            d = np.abs(base[both, sl] - x[both, sl]) / std[sl] if both.any() else np.array([np.nan])
            cells.append(np.mean(d))
        hb = np.any(base[:, 90:216] != 0, 1)
        hx = np.any(x[:, 90:216] != 0, 1)
        lb = np.any(base[:, 90:153] != 0, 1) != np.any(x[:, 90:153] != 0, 1)
        rb = np.any(base[:, 153:216] != 0, 1) != np.any(x[:, 153:216] != 0, 1)
        flips = np.mean(lb | rb | (hb != hx))
        px = [predict_window(w) for w in windows(x)]
        agree = np.mean([np.argmax(p) == np.argmax(r) for p, r in zip(pb, px)]) if pb else np.nan
        dp = max((np.abs(p - r).max() for p, r in zip(pb, px)), default=np.nan)
        name = f"jpeg q{q}" if q > 0 else f"noise{a.noise:g}"
        print(f"{name:<9}{np.mean(sizes[q]) / 1024:6.1f}{np.mean(sizes['yuv']) / np.mean(sizes[q]):10.1f}"
              f"{np.median(t_enc[q]):8.2f}{np.median(t_dec[q]):8.2f}  " + "".join(f"{c:10.3f}" for c in cells)
              + f"{flips * 100:9.1f}%{agree * 100:9.0f}%{dp:9.3f}")
    print("\nblock cells = mean |feature shift| / training std over frames where both detect the block")


if __name__ == "__main__":
    main()
