"""Test 4: the recording output must be byte-identical to HEAD.

Loads routes/websocket.py from git HEAD (`git show HEAD:backend/routes/websocket.py`)
and the working-tree version, drives both through a full 30 s continuous
recording with the same frames (packed-YUV, rotation 270, like the phone), each
writing into its own scratch TRAIN_DIR, then compares the .npy files byte for
byte. Also checks extract_342_features is unchanged vs HEAD.

    cd backend && venv\\Scripts\\python tools/check_recording_npy.py videos/GO.mp4 --scratch <dir>
"""
import argparse
import hashlib
import importlib.util
import os
import struct
import subprocess
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cv2  # noqa: E402
import numpy as np  # noqa: E402


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def frames_yuv(video, n):
    cap = cv2.VideoCapture(video)
    out = []
    while len(out) < n:
        ok, bgr = cap.read()
        if not ok:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue
        up = cv2.resize(bgr, (240, 320), interpolation=cv2.INTER_AREA)       # upright portrait
        raw = cv2.rotate(up, cv2.ROTATE_90_CLOCKWISE)                        # sensor 270
        out.append(cv2.cvtColor(raw, cv2.COLOR_BGR2YUV_I420).tobytes())
    return out


def record(mod, frames, train_dir, fps=10.0):
    mod.TRAIN_DIR = train_dir
    os.makedirs(train_dir, exist_ok=True)
    st = mod.ConnState()
    st.recording_label = "CHECK"
    st.continuous_buffer = []
    st.recording_state = "continuous_recording"
    st.is_recording_mode = True
    # fake clock: recording ends after 30 "seconds" of frames at `fps`
    real_time = time.time
    t0 = real_time()
    k = [0]
    mod.time.time = lambda: t0 + k[0] / fps
    st.recording_start_time = t0
    try:
        for i, f in enumerate(frames):
            k[0] = i + 1
            hdr = struct.pack(">iii", 270 | mod.HDR_FLAG_YUV420, 320, 240)
            mod.process_frame(st, hdr + f, 0.0, None)
            if not st.is_recording_mode:
                break
    finally:
        mod.time.time = real_time
    return os.path.join(train_dir, "CHECK.npy")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--scratch", required=True)
    a = ap.parse_args()

    feat_diff = subprocess.run(["git", "diff", "--stat", "HEAD", "--", "features.py"],
                               capture_output=True, text=True).stdout.strip()
    print("features.py vs HEAD:", feat_diff or "identical")

    head_src = subprocess.run(["git", "show", "HEAD:backend/routes/websocket.py"],
                              capture_output=True, text=True, check=True).stdout
    os.makedirs(a.scratch, exist_ok=True)
    head_path = os.path.join(a.scratch, "websocket_head.py")
    with open(head_path, "w") as f:
        f.write(head_src)
    cur = load_module("ws_current", "routes/websocket.py")
    head = load_module("ws_head", head_path)

    frames = frames_yuv(a.video, 310)
    p_head = record(head, frames, os.path.join(a.scratch, "head"))
    p_cur = record(cur, frames, os.path.join(a.scratch, "current"))
    hh = hashlib.sha1(open(p_head, "rb").read()).hexdigest()
    hc = hashlib.sha1(open(p_cur, "rb").read()).hexdigest()
    shape = np.load(p_cur).shape
    print(f"HEAD    .npy {shape} sha1 {hh}")
    print(f"current .npy {shape} sha1 {hc}")
    print("IDENTICAL" if hh == hc else "DIFFERENT")
    sys.exit(0 if hh == hc else 1)


if __name__ == "__main__":
    main()
