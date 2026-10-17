"""Replay a recording through the LIVE inference path and compare its feature
windows with data/training_data/*.npy. Report only - changes nothing.

Live path reproduced: frames reduced like the phone (~320px, nearest
subsample) -> MediaPipe IMAGE mode -> extract_342_features -> LiveDecoder
windows (timestamp-resampled to 30 fps, >= 50% active-hand frames).

    python tools/replay_compare.py videos/GO.mp4 --label GO [--fps 12] [--mirror]
    python tools/replay_compare.py C:/frames_dir --src-fps 10     # PNGs from ISL_DEBUG_SAVE_FRAMES

Reports per block: presence rate, mean shift (in training std units), std
ratio, NaN counts, left/right hand-slot usage (swaps) and the side of the body
the hands are on (mirroring).
"""
import argparse
import glob
import os
import sys
import types

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import live_config  # noqa: E402
from features import extract_342_features, BLOCKS  # noqa: E402
from live_decoder import LiveDecoder  # noqa: E402
from sim_client import subsample_like_phone  # noqa: E402

DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "training_data")


def read_frames(src, src_fps, side=320):
    if os.path.isdir(src):
        files = sorted(glob.glob(os.path.join(src, "*.png")))
        frames = [cv2.cvtColor(cv2.imread(f), cv2.COLOR_BGR2RGB) for f in files]
        return frames, src_fps
    cap = cv2.VideoCapture(src)
    fps = cap.get(cv2.CAP_PROP_FPS) or src_fps
    frames = []
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        h, w = bgr.shape[:2]
        s = side / max(h, w)
        if s < 1:
            bgr = cv2.resize(bgr, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
        frames.append(subsample_like_phone(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
    return frames, fps


def live_windows(frames, src_fps, live_fps, mirror):
    from ai.mediapipe_model import mp_service
    cfg = types.SimpleNamespace(**{k: getattr(live_config, k) for k in dir(live_config) if k.isupper()})
    cfg.VOTE_HISTORY = 10 ** 9  # never "emit" -> no flush; we only collect windows
    wins = []

    def collect(w):
        wins.append(np.array(w))
        return np.zeros(1)

    dec = LiveDecoder(collect, ["_"], cfg)
    per_frame = []
    step = max(1, int(round(src_fps / live_fps)))
    for i in range(0, len(frames), step):
        img = frames[i][:, ::-1].copy() if mirror else frames[i]
        lm = mp_service.process_image(img)
        f = extract_342_features(lm)
        per_frame.append(f)
        dec.push(i / src_fps, f, bool(lm.get("left_hand") or lm.get("right_hand")))
    return np.array(wins), np.array(per_frame)


def block_stats(frames):
    """Per block: presence rate, per-dim mean/std over frames where present."""
    out = {}
    for name, sl in BLOCKS.items():
        x = frames[:, sl]
        present = np.any(x != 0, axis=1)
        xs = x[present]
        out[name] = (present.mean(), xs.mean(0) if len(xs) else None, xs.std(0) if len(xs) else None)
    return out


def hand_side(frames):
    """Mean x (nose-relative, shoulder-scaled) of each hand slot's wrist: tells
    which side of the body the 'left'/'right' slots sit on (mirroring)."""
    res = {}
    for name, sl in (("l_hand", BLOCKS["l_hand"]), ("r_hand", BLOCKS["r_hand"])):
        wx = frames[:, sl.start]  # wrist x
        present = np.any(frames[:, sl] != 0, axis=1)
        res[name] = float(np.mean(wx[present])) if present.any() else float("nan")
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="video file or directory of PNG frames")
    ap.add_argument("--label", help="compare against data/training_data/<LABEL>.npy too")
    ap.add_argument("--fps", type=float, default=12, help="live send rate to emulate")
    ap.add_argument("--src-fps", type=float, default=25)
    ap.add_argument("--mirror", action="store_true", help="also replay horizontally flipped")
    args = ap.parse_args()

    train_all = np.concatenate([np.load(f).reshape(-1, 342) for f in glob.glob(os.path.join(DATA, "*.npy"))])
    refs = [("ALL training", train_all)]
    if args.label:
        refs.append((f"{args.label}.npy", np.load(os.path.join(DATA, f"{args.label}.npy")).reshape(-1, 342)))

    frames, src_fps = read_frames(args.src, args.src_fps)
    variants = [("replay", False)] + ([("replay MIRRORED", True)] if args.mirror else [])
    for vname, mirror in variants:
        wins, per_frame = live_windows(frames, src_fps, args.fps, mirror)
        print(f"\n=== {vname}: {len(per_frame)} frames @~{args.fps:g} fps, {len(wins)} live windows "
              f"(classified), NaN in windows: {int(np.isnan(wins).sum()) if len(wins) else 0}")
        rep = wins.reshape(-1, 342) if len(wins) else per_frame
        rs = block_stats(rep)
        for rname, ref in refs:
            ts = block_stats(ref)
            std_all = ref.std(0) + 1e-6
            print(f"  vs {rname}:")
            print(f"    {'block':<14}{'present tr':>11}{'present rp':>11}{'|dmean|/std':>12}{'std ratio':>10}")
            for name in BLOCKS:
                pt, mt, st = ts[name]
                pr, mr, sr = rs[name]
                if mt is None or mr is None:
                    dm = sratio = float("nan")
                else:
                    sl = BLOCKS[name]
                    dm = float(np.mean(np.abs(mr - mt) / std_all[sl]))
                    sratio = float(np.mean((sr + 1e-6) / (st + 1e-6)))
                print(f"    {name:<14}{pt:11.2f}{pr:11.2f}{dm:12.2f}{sratio:10.2f}")
            ht, hr = hand_side(ref), hand_side(rep)
            print(f"    hand-slot wrist x (nose-relative): training L={ht['l_hand']:+.2f} R={ht['r_hand']:+.2f}"
                  f" | replay L={hr['l_hand']:+.2f} R={hr['r_hand']:+.2f}"
                  "  (opposite signs => mirrored / L-R swapped)")
        if len(wins):
            active = np.any(wins[:, :, 90:216] != 0, axis=2).sum(1)
            print(f"    live windows: active-hand samples per window p50={np.median(active):.0f}/30")


if __name__ == "__main__":
    main()
