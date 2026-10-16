"""Live response size per overlay face mode, on real frames with a face.

Crops each video frame to a portrait region around the person (so the face is
large enough for the face landmarker, like a phone at ~0.5-1 m), sends it
through routes.websocket.process_frame in LIVE mode and reports the JSON size
of the response for:
  full-json  : all 478 face points as JSON floats (as before the trim)
  light      : OVERLAY_FACE_POINTS subset (27 points, JSON)
  full-q     : all 478 points, int16 x/y quantized, base64 ("face_q")
Also reports the quantization error in preview pixels (360 px wide).

    cd backend && venv\\Scripts\\python tools/overlay_response_size.py videos/GO.mp4 videos/YOU.mp4
"""
import argparse
import base64
import json
import os
import struct
import sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from routes import websocket as ws  # noqa: E402
import live_config as LC  # noqa: E402


def portrait_frames(video, step=3):
    cap = cv2.VideoCapture(video)
    out, i = [], 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        i += 1
        if i % step:
            continue
        h, w = bgr.shape[:2]
        cw = int(h * 3 / 4 * 0.75)
        ch = int(h * 0.75)
        x0 = (w - cw) // 2
        crop = bgr[0:ch, x0:x0 + cw]
        out.append(cv2.cvtColor(cv2.resize(crop, (240, 320), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB))
    return out


def run(frames, mode, face_points):
    st = ws.ConnState()
    st.face_mode = mode
    old = LC.OVERLAY_FACE_POINTS
    LC.OVERLAY_FACE_POINTS = face_points
    sizes, outs = [], []
    try:
        for f in frames:
            msg = struct.pack(">iii", 0, 240, 320) + f.tobytes()
            out = ws.process_frame(st, msg, 0.0, None)
            if "face" in out or "face_q" in out:
                sizes.append(len(json.dumps(out)))
                outs.append(out)
    finally:
        LC.OVERLAY_FACE_POINTS = old
    return sizes, outs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("videos", nargs="+")
    a = ap.parse_args()
    frames = [f for v in a.videos for f in portrait_frames(v)]
    res = {}
    for name, mode, pts in (("full-json", "light", None), ("light", "light", LC.OVERLAY_FACE_POINTS),
                            ("full-q", "full", LC.OVERLAY_FACE_POINTS)):
        res[name] = run(frames, mode, pts)
    n = len(res["full-json"][0])
    print(f"frames={len(frames)}  frames with a face={n}")
    print(f"{'mode':<10}{'face pts':>9}{'resp KB p50':>12}{'p95':>7}")
    for name, (sizes, outs) in res.items():
        k = 478 if name != "light" else len(LC.OVERLAY_FACE_POINTS)
        if sizes:
            print(f"{name:<10}{k:>9}{np.median(sizes) / 1024:12.2f}{np.percentile(sizes, 95) / 1024:7.2f}")
    # quantization error: decode face_q and compare with the JSON floats (4 decimals)
    errs = []
    for oj, oq in zip(res["full-json"][1], res["full-q"][1]):
        if "face" in oj and "face_q" in oq:
            q = np.frombuffer(base64.b64decode(oq["face_q"]), "<i2").reshape(-1, 2) / LC.OVERLAY_Q_SCALE
            j = np.array(oj["face"])
            errs.append(np.abs(q - j).max() * 360)
    if errs:
        print(f"quantization error vs 4-decimal JSON: max {max(errs):.3f} px (360 px preview)")


if __name__ == "__main__":
    main()
