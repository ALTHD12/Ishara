"""Simulated phone client: streams a video through the live WebSocket path.

Emulates the Flutter client: frames arrive at the camera rate, are reduced to
~300px by nearest-neighbour subsampling (same as camera_utils.dart), packed with
the 12-byte header and sent as binary frames. Like the app, at most one frame is
in flight; camera frames that arrive while waiting are dropped.

Run the backend with ISL_DEBUG_TIMING=1 so responses carry server stage timings.

    python tools/sim_client.py --url ws://127.0.0.1:8765/ --seconds 20 videos/GO.mp4 videos/YOU.mp4
"""
import argparse
import asyncio
import json
import os
import struct
import sys
import time

import cv2
import numpy as np
import websockets


def subsample_like_phone(rgb):
    h, w, _ = rgb.shape
    step = max(1, max(w, h) // 300)
    return np.ascontiguousarray(rgb[: (h // step) * step : step, : (w // step) * step : step])


def load_frames(paths, max_side):
    frames = []
    for p in paths:
        cap = cv2.VideoCapture(p)
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            h, w = bgr.shape[:2]
            scale = max_side / max(h, w)
            if scale < 1:
                # Emulate ResolutionPreset.low (~320px long side) before the phone's subsampling.
                bgr = cv2.resize(bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
            frames.append(subsample_like_phone(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
        cap.release()
    return frames


def pct(vals, q):
    if not vals:
        return float("nan")
    s = sorted(vals)
    return s[min(len(s) - 1, int(round((len(s) - 1) * q)))]


async def run(args):
    frames = load_frames(args.videos, args.camera_side)
    if not frames:
        sys.exit("no frames")
    period = 1.0 / args.camera_fps
    min_send_interval = 1.0 / args.max_send_fps if args.max_send_fps > 0 else 0.0

    stats = {"rtt": [], "server_total": [], "network+queue": []}
    server_stages = {}
    signs = []
    sent = dropped = 0
    async with websockets.connect(args.url, max_size=None) as ws:
        t_start = time.perf_counter()
        last_send = 0.0
        i = 0
        while time.perf_counter() - t_start < args.seconds:
            # Next camera frame "arrives"
            target = t_start + i * period
            delay = target - time.perf_counter()
            if delay > 0:
                await asyncio.sleep(delay)
            frame = frames[i % len(frames)]
            i += 1
            now = time.perf_counter()
            if now - last_send < min_send_interval:
                dropped += 1
                continue
            h, w, _ = frame.shape
            await ws.send(struct.pack(">iii", 0, w, h) + frame.tobytes())
            t_sent = time.perf_counter()
            last_send = t_sent
            sent += 1
            msg = await ws.recv()
            rtt = (time.perf_counter() - t_sent) * 1000
            data = json.loads(msg)
            t = data.get("_t", {})
            stats["rtt"].append(rtt)
            if t:
                stats["server_total"].append(t["server_total"])
                stats["network+queue"].append(rtt - t["server_total"])
                for k, v in t.items():
                    server_stages.setdefault(k, []).append(v)
            if data.get("sign"):
                signs.append((round(time.perf_counter() - t_start, 2), data["sign"]))
            # Frames that arrived while we were waiting are dropped (phone behaviour)
            behind = int((time.perf_counter() - t_start) / period) - i
            if behind > 0:
                dropped += behind
                i += behind
        elapsed = time.perf_counter() - t_start

    print(f"sent={sent} dropped={dropped} elapsed={elapsed:.1f}s  effective_fps={sent / elapsed:.1f}")
    for k, v in list(stats.items()) + sorted(server_stages.items()):
        print(f"  {k:<16} p50={pct(v, .5):7.1f}  p95={pct(v, .95):7.1f}  mean={np.mean(v) if v else float('nan'):7.1f}")
    if args.show_signs:
        print("signs:", signs[:40])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("videos", nargs="+")
    ap.add_argument("--url", default="ws://127.0.0.1:8765/")
    ap.add_argument("--seconds", type=float, default=20)
    ap.add_argument("--camera-fps", type=float, default=30)
    ap.add_argument("--camera-side", type=int, default=320, help="long side before subsampling (ResolutionPreset.low ~320)")
    ap.add_argument("--max-send-fps", type=float, default=0, help="0 = uncapped (legacy behaviour)")
    ap.add_argument("--show-signs", action="store_true")
    asyncio.run(run(ap.parse_args()))


if __name__ == "__main__":
    main()
