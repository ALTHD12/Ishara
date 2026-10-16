"""Compare 342-dim features from MediaPipe IMAGE mode (how training data was
recorded) vs VIDEO mode (live inference) on the same frames.

    python tools/compare_mp_modes.py videos/GO.mp4 videos/WHERE.mp4 videos/YOU.mp4 --fps 12

Reports hand-presence agreement and, where both modes see a block, the mean
absolute difference in units of the training-data per-dimension std.
"""
import argparse
import glob
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from features import extract_342_features, BLOCKS  # noqa: E402
from sim_client import load_frames  # noqa: E402
from ai.mediapipe_model import MediaPipeService  # noqa: E402


def training_std():
    arrs = [np.load(f, mmap_mode="r").reshape(-1, 342) for f in glob.glob("data/training_data/*.npy")]
    allf = np.concatenate(arrs)
    return allf.std(axis=0) + 1e-6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("videos", nargs="+")
    ap.add_argument("--fps", type=float, default=12, help="live frame rate to emulate for VIDEO mode")
    ap.add_argument("--src-fps", type=float, default=25)
    args = ap.parse_args()

    frames = load_frames(args.videos, 320)
    step = max(1, int(round(args.src_fps / args.fps)))
    frames = frames[::step]
    svc = MediaPipeService()
    std = training_std()

    img_f, vid_f = [], []
    t_ms = 0.0
    for fr in frames:
        img_f.append(extract_342_features(svc.process_image(fr)))
        t_ms += 1000.0 / args.fps
        vid_f.append(extract_342_features(svc.process_video_frame(fr, t_ms)))
    A, B = np.array(img_f), np.array(vid_f)
    print(f"frames={len(frames)} (every {step}th source frame, ~{args.fps:g} fps)")
    print(f"{'block':<14}{'present IMG':>12}{'present VID':>12}{'agree':>8}{'MAD/std (both)':>16}{'p95':>8}")
    for name, sl in BLOCKS.items():
        pa = np.any(A[:, sl] != 0, axis=1)
        pb = np.any(B[:, sl] != 0, axis=1)
        both = pa & pb
        if both.any():
            d = np.abs(A[both][:, sl] - B[both][:, sl]) / std[sl]
            mad, p95 = d.mean(), np.percentile(d, 95)
        else:
            mad = p95 = float("nan")
        print(f"{name:<14}{pa.mean():12.2f}{pb.mean():12.2f}{(pa == pb).mean():8.2f}{mad:16.3f}{p95:8.3f}")


if __name__ == "__main__":
    main()
