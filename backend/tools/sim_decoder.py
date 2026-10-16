"""Decision-latency simulator: replays recorded sessions through LiveDecoder.

Rebuilds the continuous 30 fps feature stream of each recording session from
data/training_data/<LABEL>.npy (windows overlap with stride 5), prepends idle,
subsamples to the live frame rate and feeds it to LiveDecoder with a given
config. Measures time from sign onset (first frame with hands after >=0.3 s
without) to the first emitted word.

NOTE: these sessions were part of the model's training data, so accuracy here
is optimistic. Use it to compare decision logic (latency, emission rate), not
to judge the model.

    python tools/sim_decoder.py
"""
import glob
import os
import sys
import types

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import live_config  # noqa: E402
from live_decoder import LiveDecoder  # noqa: E402

SRC_FPS = 30.0


def rebuild_sessions(path):
    """Split a .npy of overlapping windows back into continuous frame streams."""
    a = np.load(path)
    sessions, cur = [], [a[0]]
    for i in range(1, len(a)):
        if np.allclose(a[i - 1, 5:], a[i, :25]):
            cur.append(a[i])
        else:
            sessions.append(cur)
            cur = [a[i]]
    sessions.append(cur)
    out = []
    for wins in sessions:
        w = np.stack(wins)
        out.append(np.concatenate([w[:-1, :5].reshape(-1, 342), w[-1]]) if len(w) > 1 else w[0])
    return out


def has_hands(f):
    return bool(np.any(f[90:216] != 0))


def make_cfg(**kw):
    cfg = types.SimpleNamespace(**{k: getattr(live_config, k) for k in dir(live_config) if k.isupper()})
    for k, v in kw.items():
        setattr(cfg, k, v)
    return cfg


def load_predict():
    import tensorflow as tf
    m = tf.keras.models.load_model("ai/isl_model.keras")

    @tf.function(input_signature=[tf.TensorSpec([1, 30, 342], tf.float32)])
    def g(x):
        return m(x, training=False)

    cache = {}

    def predict(w):
        key = np.asarray(w, dtype=np.float32).tobytes()
        if key not in cache:
            cache[key] = g(tf.constant(np.asarray(w, np.float32)[None])).numpy()[0]
        return cache[key]
    return predict


def run(cfg, live_fps, predict, classes, streams, client_extra_frames=0, idle_s=1.0):
    lat, emitted, correct, onsets_hit, onsets = [], 0, 0, 0, 0
    period = 1.0 / live_fps
    total_s = 0.0
    for label, frames in streams:
        # idle prefix: same pose/face as the first frame, hands removed
        idle = frames[0].copy()
        idle[90:] = 0
        stream = [idle] * int(idle_s * SRC_FPS) + list(frames)
        n_src = len(stream)
        dec = LiveDecoder(predict, classes, cfg)
        # onsets on the source timeline
        hands = np.array([has_hands(f) for f in stream])
        on = []
        gap = 0
        for i, h in enumerate(hands):
            if h and gap >= int(0.3 * SRC_FPS):
                on.append(i / SRC_FPS)
            gap = 0 if h else gap + 1
        events = []
        t = 0.0
        while t * SRC_FPS < n_src:
            i = int(t * SRC_FPS)
            f = stream[i]
            sign = dec.push(t, f, has_hands(f))
            if sign is not None:
                events.append((t + client_extra_frames * period, sign))
            t += period
        total_s += n_src / SRC_FPS
        emitted += len(events)
        correct += sum(1 for _, s in events if s == label)
        for k, o in enumerate(on):
            nxt = on[k + 1] if k + 1 < len(on) else 1e9
            hit = [e for e, _ in events if o <= e < nxt]
            onsets += 1
            if hit:
                onsets_hit += 1
                lat.append(hit[0] - o)
    lat = np.array(lat) if lat else np.array([np.nan])
    return {
        "onset->word p50": np.nanmedian(lat),
        "p90": np.nanpercentile(lat, 90),
        "onsets w/ word": onsets_hit / max(onsets, 1),
        "words/min": emitted / total_s * 60,
        "correct": correct / max(emitted, 1),
    }


def main():
    import json
    classes = json.load(open("ai/label_encoder_classes.json"))
    streams = []
    for p in sorted(glob.glob("data/training_data/*.npy")):
        label = os.path.splitext(os.path.basename(p))[0]
        if label not in classes:
            continue
        for s in rebuild_sessions(p):
            streams.append((label, s))
    predict = load_predict()

    legacy = make_cfg(RESAMPLE=False, INFER_EVERY_N_FRAMES=3, VOTE_HISTORY=5, VOTES_TO_EMIT=3,
                      CONFIDENCE_THRESHOLD=0.55, FLUSH_KEEP_FRACTION=0.5, REPEAT_POLICY="differ_from_last",
                      NO_HAND_CLEAR_S=60 / 12.7)
    fps_legacy = float(os.environ.get("LEGACY_FPS", "12.7"))
    fps_new = float(os.environ.get("NEW_FPS", "12"))
    rows = [("legacy (as shipped)", legacy, fps_legacy, 1)]
    for hist, votes in ((4, 3), (3, 2), (5, 3), (3, 3)):
        for conf in (0.55, 0.7):
            rows.append((f"resample h{hist}/v{votes} c{conf}",
                         make_cfg(VOTE_HISTORY=hist, VOTES_TO_EMIT=votes, CONFIDENCE_THRESHOLD=conf),
                         fps_new, 0))
    rows.append(("legacy logic @30fps-resampled", make_cfg(INFER_EVERY_N_FRAMES=3, VOTE_HISTORY=5,
                                                           VOTES_TO_EMIT=3), fps_new, 1))
    print(f"streams={len(streams)}  legacy fps={fps_legacy}  new fps={fps_new}")
    print(f"{'config':<32}{'p50 s':>7}{'p90 s':>7}{'hit%':>7}{'w/min':>7}{'corr%':>7}")
    for name, cfg, fps, extra in rows:
        r = run(cfg, fps, predict, classes, streams, client_extra_frames=extra)
        print(f"{name:<32}{r['onset->word p50']:7.2f}{r['p90']:7.2f}{r['onsets w/ word'] * 100:7.0f}"
              f"{r['words/min']:7.1f}{r['correct'] * 100:7.0f}")


if __name__ == "__main__":
    main()
