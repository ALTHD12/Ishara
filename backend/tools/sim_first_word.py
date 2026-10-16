"""Problem A simulator: is the first word after START / reconnect lost or late?

Replays recorded sessions (data/training_data, rebuilt into 30 fps streams like
tools/sim_decoder.py) through the real LiveDecoder at the phone's send rate and
models the client exactly as sign_classifier_service.dart does it:

    if eid > lastEventId: lastEventId = eid; append word

Scenarios, each a list of signs separated by 1 s of idle (hands removed):
  cold         fresh backend connection, START, sign
  restart      ... STOP, START (client sends {"action":"reset"}), sign again
  reconnect    ... socket drops and reconnects (server builds a new ConnState)

Two variants are run:
  as-shipped   decoder.reset() / new connection restart event ids at 1,
               client keeps lastEventId (code at HEAD e56b7ce)
  fixed        event ids stay monotonic across reset; client zeroes
               lastEventId when a new socket opens

NOTE: sessions are training data -> accuracy is optimistic; this measures the
plumbing (lost/late events), not the model.

    cd backend && venv\\Scripts\\python tools/sim_first_word.py [--fps 10]
"""
import argparse
import json
import os
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sim_decoder import SRC_FPS, has_hands, load_predict, rebuild_sessions  # noqa: E402
from live_decoder import LiveDecoder  # noqa: E402

SIGN_S = 2.5   # seconds of each recorded session played per sign
IDLE_S = 1.0


def build_signs(classes):
    """One continuous clip per class: SIGN_S seconds starting at the first hand frame."""
    clips = {}
    for label in classes:
        p = f"data/training_data/{label}.npy"
        if not os.path.exists(p):
            continue
        s = max(rebuild_sessions(p), key=len)
        hands = [i for i, f in enumerate(s) if has_hands(f)]
        start = hands[0] if hands else 0
        clips[label] = s[start:start + int(SIGN_S * SRC_FPS)]
    return clips


class Client:
    def __init__(self, fixed):
        self.fixed = fixed
        self.last_eid = 0
        self.words = []          # (t, sign)
        self.dropped_dup = 0

    def on_open(self):
        if self.fixed:
            self.last_eid = 0

    def on_result(self, t, out):
        eid = out.get("eid")
        if eid is None:
            return
        if eid > self.last_eid:
            self.last_eid = eid
            self.words.append((t, out["esign"]))
        elif out.get("_new"):
            self.dropped_dup += 1   # server emitted, client ignored it


class Server:
    """Mirrors the per-connection part of routes/websocket.py."""

    def __init__(self, predict, classes, fixed):
        self.predict, self.classes, self.fixed = predict, classes, fixed
        self.new_conn()

    def new_conn(self):
        self.dec = LiveDecoder(self.predict, self.classes)

    def reset(self):
        eid = self.dec.event_id
        self.dec.reset()
        # as-shipped: reset() re-ran __init__, so ids restarted at 0.
        self.dec.event_id = eid if self.fixed else 0

    def frame(self, t, f):
        before = self.dec.event_id
        self.dec.push(t, f, has_hands(f))
        out = {}
        if self.dec.last_event:
            out["eid"], out["esign"], _ = self.dec.last_event
            out["_new"] = self.dec.event_id != before
        return out


def play(server, client, clips, order, t0, fps, log):
    """Play signs in `order`; returns end time and per-sign (onset, first word t, word)."""
    period = 1.0 / fps
    t = t0
    res = []
    for label in order:
        idle = clips[label][0].copy()
        idle[90:] = 0
        stream = [idle] * int(IDLE_S * SRC_FPS) + list(clips[label])
        onset = t + IDLE_S
        n_words = len(client.words)
        emitted_before = server.dec.event_id
        k = 0.0
        while k * SRC_FPS < len(stream):
            f = stream[int(k * SRC_FPS)]
            client.on_result(t + k, server.frame(t + k, f))
            if log is not None and server.dec.last_probs is not None and "first_window" not in log:
                log["first_window"] = t + k - (t0 + IDLE_S)   # from first sign onset
            k += period
        t += len(stream) / SRC_FPS
        # words whose decision happened after this sign's onset (earlier ones
        # are the previous sign's tail, emitted during the idle gap)
        new = [w for w in client.words[n_words:] if w[0] >= onset]
        emitted = server.dec.event_id - emitted_before
        res.append((label, onset, new[0] if new else None, emitted))
    return t, res


def scenario(predict, classes, clips, fixed, fps, order):
    server = Server(predict, classes, fixed)
    client = Client(fixed)
    client.on_open()
    rows = []
    t = 0.0
    for phase in ("cold", "restart", "reconnect"):
        if phase == "restart":
            server.reset()                 # START sends {"action":"reset"}
        elif phase == "reconnect":
            server.new_conn()              # new socket -> new ConnState
            client.on_open()
        log = {}
        start = t
        t, res = play(server, client, clips, order, t, fps, log)
        for label, onset, word, emitted in res:
            rows.append((phase, label, onset, word, emitted))
        rows.append((phase, "_first_window_s", log.get("first_window"), None, None))
        _ = start
    return rows, client


def summarize(name, rows, client):
    print(f"\n== {name} ==")
    print(f"{'phase':<10}{'sign':<13}{'server emitted':>15}{'client word':>14}{'onset->word s':>15}")
    per_phase = Counter()
    lost = Counter()
    for phase, label, onset, word, emitted in rows:
        if label == "_first_window_s":
            print(f"{phase:<10}first sign onset -> first model call: {onset:.2f} s")
            continue
        shown = word[1] if word else "-"
        dt = f"{word[0] - onset:.2f}" if word else "LOST" if emitted else "none"
        per_phase[phase] += 1
        if emitted and not word:
            lost[phase] += 1
        print(f"{phase:<10}{label:<13}{emitted:>15}{shown:>14}{dt:>15}")
    print("signs whose server word never reached the word list:",
          {p: f"{lost[p]}/{per_phase[p]}" for p in per_phase})
    print("server events ignored by client (eid <= lastEventId):", client.dropped_dup)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fps", type=float, default=10.0, help="phone effective send rate")
    ap.add_argument("--signs", default="CALL,AMBULANCE,HE,UNCONSCIOUS,QUICKLY")
    a = ap.parse_args()
    classes = json.load(open("ai/label_encoder_classes.json"))
    clips = build_signs(classes)
    order = [s for s in a.signs.split(",") if s in clips]
    predict = load_predict()
    print(f"fps={a.fps} signs={order} sign={SIGN_S}s idle={IDLE_S}s")
    for fixed in (False, True):
        rows, client = scenario(predict, classes, clips, fixed, a.fps, order)
        summarize("fixed" if fixed else "as-shipped (HEAD)", rows, client)


if __name__ == "__main__":
    main()
