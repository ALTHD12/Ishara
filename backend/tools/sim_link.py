"""Problem C: RTT, throughput and time-to-word over an emulated bad link.

Drives the real backend over a WebSocket like the phone does (packed YUV420,
320x240 = 115 KB/frame, capture timestamp header, one frame in flight, camera
at 30 fps, send-rate cap) and emulates the link on the client side:
    uplink:   sleep(one_way_ms + frame_bytes / bandwidth) before the frame is sent
    downlink: sleep(one_way_ms + response_bytes / bandwidth) after it returns
So RTT = 2*one_way + serialization both ways + server time.

Then estimates time-to-word: replays recorded sessions (tools/sim_decoder.py)
through LiveDecoder on the SAME send schedule the link produced (frame
timestamps = measured send times, decision visible one RTT later).

    start backend:  set ISL_PORT=8766 & set ISL_ADB_TUNNEL=0 & venv\\Scripts\\python main.py
    cd backend && venv\\Scripts\\python tools/sim_link.py --url ws://127.0.0.1:8766/ videos/GO.mp4
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim_client import pct  # noqa: E402

HDR_TS, HDR_YUV = 0x10000, 0x40000
PROFILES = {   # name: (one-way delay ms, bandwidth Mbit/s, jitter ms)
    "lan":      (2, 100.0, 0),
    "wifi-ok":  (10, 20.0, 5),
    "wifi-bad": (40, 6.0, 20),
    "hotspot":  (80, 3.0, 40),
}


def yuv_frames(video, n=300):
    cap = cv2.VideoCapture(video)
    out = []
    while len(out) < n:
        ok, bgr = cap.read()
        if not ok:
            break
        bgr = cv2.resize(bgr, (320, 240), interpolation=cv2.INTER_AREA)
        out.append(cv2.cvtColor(bgr, cv2.COLOR_BGR2YUV_I420).tobytes())   # Y, U, V planes
    return out


class Adaptive:
    """Same rule as SignClassifierService._adaptSendRate."""

    def __init__(self, cap, low, hi_ms, lo_ms, recover_s):
        self.cap, self.low, self.hi, self.lo, self.recover = cap, low, hi_ms, lo_ms, recover_s
        self.ewma, self.low_mode, self.good_since = 0.0, False, None

    def update(self, rtt, now):
        self.ewma = rtt if self.ewma == 0 else self.ewma * 0.8 + rtt * 0.2
        if not self.low_mode and self.ewma > self.hi:
            self.low_mode, self.good_since = True, None
        elif self.low_mode:
            if self.ewma < self.lo:
                self.good_since = self.good_since or now
                if now - self.good_since > self.recover:
                    self.low_mode = False
            else:
                self.good_since = None

    @property
    def fps(self):
        return min(self.cap, self.low) if self.low_mode else self.cap


async def stream(url, frames, seconds, cap_fps, profile, adaptive=None, seed=0):
    one_way, mbps, jit = PROFILES[profile]
    bps = mbps * 1e6 / 8
    rng = np.random.default_rng(seed)
    period = 1 / 30.0
    rtts, sends, bytes_up, bytes_dn, timeouts = [], [], 0, 0, 0
    async with websockets.connect(url, max_size=None) as ws:
        t0 = time.perf_counter()
        last_send = -1e9
        i = 0
        while time.perf_counter() - t0 < seconds:
            target = t0 + i * period
            d = target - time.perf_counter()
            if d > 0:
                await asyncio.sleep(d)
            i += 1
            now = time.perf_counter()
            cap = adaptive.fps if adaptive else cap_fps
            if now - last_send < 1 / cap:
                continue
            last_send = now
            payload = frames[i % len(frames)]
            t_cap = now - t0
            hdr = struct.pack(">iiiq", HDR_TS | HDR_YUV, 320, 240, int(t_cap * 1e6))
            await asyncio.sleep((one_way + abs(rng.normal(0, jit))) / 1000 + len(payload) / bps)
            await ws.send(hdr + payload)
            try:
                msg = await asyncio.wait_for(ws.recv(), 0.8 + 2 * len(payload) / bps)
            except asyncio.TimeoutError:
                timeouts += 1
                continue
            await asyncio.sleep((one_way + abs(rng.normal(0, jit))) / 1000 + len(msg) / bps)
            rtt = (time.perf_counter() - now) * 1000
            rtts.append(rtt)
            sends.append((t_cap, rtt))
            bytes_up += len(payload) + 20
            bytes_dn += len(msg)
            if adaptive:
                adaptive.update(rtt, time.perf_counter() - t0)
            # camera frames that arrived while we waited are skipped (phone behaviour)
            i = max(i, int((time.perf_counter() - t0) / period))
        el = time.perf_counter() - t0
    return {"rtt": rtts, "sends": sends, "fps": len(rtts) / el,
            "kBps_up": bytes_up / el / 1024, "kBps_dn": bytes_dn / el / 1024, "timeouts": timeouts}


def time_to_word(sends, predict, classes, streams):
    """Replay sessions on the measured send schedule; decision shows one RTT later."""
    from live_decoder import LiveDecoder
    from sim_decoder import SRC_FPS, has_hands
    gaps = np.diff([s[0] for s in sends])
    rtt = np.array([s[1] for s in sends]) / 1000
    lat, onsets, hits = [], 0, 0
    k = 0
    for label, frames in streams:
        idle = frames[0].copy()
        idle[90:] = 0
        stream = [idle] * 30 + list(frames)
        dec = LiveDecoder(predict, classes)
        hands = np.array([has_hands(f) for f in stream])
        on, gap = [], 0
        for i, h in enumerate(hands):
            if h and gap >= 9:
                on.append(i / SRC_FPS)
            gap = 0 if h else gap + 1
        events, t = [], 0.0
        while t * SRC_FPS < len(stream):
            f = stream[int(t * SRC_FPS)]
            if dec.push(t, f, has_hands(f)) is not None:
                events.append(t + rtt[k % len(rtt)])
            t += gaps[k % len(gaps)]
            k += 1
        for j, o in enumerate(on):
            nxt = on[j + 1] if j + 1 < len(on) else 1e9
            hit = [e for e in events if o <= e < nxt]
            onsets += 1
            if hit:
                hits += 1
                lat.append(hit[0] - o)
    return (np.median(lat) if lat else np.nan, np.percentile(lat, 90) if lat else np.nan,
            hits / max(onsets, 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--url", default="ws://127.0.0.1:8766/")
    ap.add_argument("--seconds", type=float, default=12)
    ap.add_argument("--profiles", default="lan,wifi-ok,wifi-bad,hotspot")
    ap.add_argument("--caps", default="12,8,6,adaptive")
    ap.add_argument("--no-words", action="store_true")
    a = ap.parse_args()
    frames = yuv_frames(a.video)
    predict = classes = streams = None
    if not a.no_words:
        import glob
        from sim_decoder import load_predict, rebuild_sessions
        classes = json.load(open("ai/label_encoder_classes.json"))
        predict = load_predict()
        streams = []
        for p in sorted(glob.glob("data/training_data/*.npy")):
            lab = os.path.splitext(os.path.basename(p))[0]
            if lab in classes:
                streams += [(lab, s) for s in rebuild_sessions(p)]
    print(f"{'profile':<10}{'cap':>9}{'fps':>6}{'RTT p50':>9}{'p95':>7}{'up KB/s':>9}{'dn KB/s':>9}"
          f"{'t/o':>5}{'word p50':>10}{'p90':>6}{'hit%':>6}")
    for prof in a.profiles.split(","):
        for cap in a.caps.split(","):
            ad = Adaptive(12, 6, 250, 150, 2.0) if cap == "adaptive" else None
            r = asyncio.run(stream(a.url, frames, a.seconds, 12 if ad else float(cap), prof, ad))
            w = time_to_word(r["sends"], predict, classes, streams) if streams else (np.nan,) * 3
            print(f"{prof:<10}{cap:>9}{r['fps']:6.1f}{pct(r['rtt'], .5):9.0f}{pct(r['rtt'], .95):7.0f}"
                  f"{r['kBps_up']:9.0f}{r['kBps_dn']:9.1f}{r['timeouts']:5d}{w[0]:10.2f}{w[1]:6.2f}{w[2] * 100:6.0f}",
                  flush=True)


if __name__ == "__main__":
    main()
