"""Report-only audit of data/training_data/*.npy (changes nothing).

For each file: recording sessions, implied recording fps, hand presence,
idle windows (<15 of 30 frames with a hand = what live inference refuses to
classify), NaNs. Then reproduces the training split
(train_test_split(test_size=0.2, random_state=42) over os.listdir order, as in
ai/bilstm_model.py) and measures validation leakage from overlapping windows.

    python tools/analyze_training_data.py [--classes ai/label_encoder_classes.json]
"""
import argparse
import json
import os

import numpy as np
from sklearn.model_selection import train_test_split

DATA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "training_data")
STRIDE, WIDTH = 5, 30


def sessions_of(a):
    """Session index per window: consecutive windows that overlap by 25 frames."""
    sid = np.zeros(len(a), int)
    for i in range(1, len(a)):
        sid[i] = sid[i - 1] + (0 if np.allclose(a[i - 1, STRIDE:], a[i, :WIDTH - STRIDE]) else 1)
    return sid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--classes", help="only use labels listed in this JSON (e.g. the deployed model's)")
    args = ap.parse_args()
    only = set(json.load(open(args.classes))) if args.classes else None

    files = [f for f in os.listdir(DATA) if f.endswith(".npy")]  # same order as training
    X_label, X_file, X_pos, X_sess = [], [], [], []
    print(f"{'file':<16}{'wins':>5}{'sess':>5}{'~fps':>6}{'hand%':>7}{'idle win%':>10}{'NaN':>5}")
    tot_w = tot_idle = 0
    for f in files:
        label = f.split(".")[0]
        if only is not None and label not in only:
            continue
        a = np.load(os.path.join(DATA, f))
        sid = sessions_of(a)
        n_sess = sid.max() + 1
        frames = sum(STRIDE * (np.sum(sid == s) - 1) + WIDTH for s in range(n_sess))
        fps = frames / (30.0 * n_sess)  # each session = 30 real seconds
        hands = np.any(a[:, :, 90:216] != 0, axis=2)  # (N, 30)
        idle = hands.sum(1) < 15
        tot_w += len(a)
        tot_idle += idle.sum()
        print(f"{f:<16}{len(a):5d}{n_sess:5d}{fps:6.1f}{hands.mean() * 100:7.1f}{idle.mean() * 100:10.1f}"
              f"{int(np.isnan(a).sum()):5d}")
        for i in range(len(a)):
            X_label.append(label)
            X_file.append(f)
            X_pos.append(i)
            X_sess.append(sid[i])
    print(f"TOTAL windows={tot_w}  idle windows={tot_idle} ({tot_idle / max(tot_w, 1) * 100:.1f}%)")

    idx = np.arange(len(X_label))
    tr, va = train_test_split(idx, test_size=0.2, random_state=42)
    key = {}
    for i in tr:
        key.setdefault((X_file[i], X_sess[i]), set()).add(X_pos[i])
    any_overlap = share25 = share_all = 0
    for i in va:
        train_pos = key.get((X_file[i], X_sess[i]), set())
        d = [abs(X_pos[i] - p) for p in train_pos]
        if d and min(d) * STRIDE < WIDTH:
            any_overlap += 1
        if d and min(d) == 1:
            share25 += 1
        # every frame of this val window also appears in some train window
        frames = set(range(X_pos[i] * STRIDE, X_pos[i] * STRIDE + WIDTH))
        covered = set()
        for p in train_pos:
            if abs(p - X_pos[i]) * STRIDE < WIDTH:
                covered |= set(range(p * STRIDE, p * STRIDE + WIDTH))
        if frames <= covered:
            share_all += 1
    n = len(va)
    print(f"\nValidation split: {n} windows")
    print(f"  overlap >=5 frames with a train window from the same session: {any_overlap / n * 100:.1f}%")
    print(f"  overlap 25/30 frames (adjacent window in train):              {share25 / n * 100:.1f}%")
    print(f"  every frame also seen in training:                            {share_all / n * 100:.1f}%")
    print("  -> validation accuracy is close to training accuracy by construction; "
          "split by session (or by recording) instead.")


if __name__ == "__main__":
    main()
