"""Turns a stream of per-frame 342-dim features into emitted signs.

Pure numpy; the model is injected as `predict(window[30,342]) -> probs`, so the
same code runs live (routes/websocket.py) and offline (tools/*). Constants come
from live_config.py.
"""
from collections import deque

import numpy as np

import live_config as C


def resample_window(times, feats, t_end, n, fps):
    """Resample irregular frames onto n samples ending at t_end, spaced 1/fps.

    Element-wise linear interpolation between the bracketing frames; where
    either neighbour has a missing landmark (exact 0.0, as produced by
    extract_342_features) the nearest frame is used instead, so a hand that
    appears/disappears is never blended with zeros.
    Returns None if the history does not cover the window.
    """
    dt = 1.0 / fps
    targets = t_end - dt * np.arange(n - 1, -1, -1)
    times = np.asarray(times)
    # Allow the window to start up to one sample before the oldest frame.
    if len(times) == 0 or targets[0] < times[0] - dt:
        return None, None
    idx = np.searchsorted(times, targets, side="right") - 1  # frame at/before target
    idx = np.clip(idx, 0, len(times) - 1)
    nxt = np.clip(idx + 1, 0, len(times) - 1)
    a = feats[idx]
    b = feats[nxt]
    span = times[nxt] - times[idx]
    w = np.where(span > 0, (targets - times[idx]) / np.where(span > 0, span, 1), 0.0)
    w = np.clip(w, 0.0, 1.0)[:, None]
    lerp = a + (b - a) * w
    nearest = np.where(w >= 0.5, b, a)
    both = (a != 0) & (b != 0)
    out = np.where(both, lerp, nearest)
    return out, (idx, nxt, w[:, 0])


class LiveDecoder:
    def __init__(self, predict, classes, cfg=C):
        self.predict = predict
        self.classes = classes
        self.cfg = cfg
        horizon = cfg.WINDOW_FRAMES / cfg.WINDOW_FPS
        self.keep_s = horizon + 1.0
        self.frames = deque()          # (t, features, has_hands)
        self.history = deque(maxlen=cfg.VOTE_HISTORY)
        self.frame_count = 0
        self.eligible_count = 0        # frames that passed the active-hand check
        self.min_t = -np.inf           # frames before this are ignored (post-emit flush)
        self.last_hand_t = None
        self.display_sign = None
        self.display_conf = 0.0
        self.last_emit = {}            # sign -> time
        self.event_id = 0
        self.last_event = None         # (id, sign, t)
        self.last_probs = None
        self.vote_confs = deque(maxlen=cfg.VOTE_HISTORY)  # top prob per history entry
        # Why the last push() did not emit (debug readout; see DECISION_REASONS).
        self.last_reason = "init"

    def reset(self):
        # Event ids stay monotonic for the lifetime of the connection: the
        # client only appends a word when eid > its last seen eid, so restarting
        # at 1 after START (reset) silently dropped the first words.
        event_id = self.event_id
        self.__init__(self.predict, self.classes, self.cfg)
        self.event_id = event_id

    # ------------------------------------------------------------------
    def _window(self, t_now):
        cfg = self.cfg
        fr = [f for f in self.frames if f[0] >= self.min_t]
        if not fr:
            return None, None
        times = np.array([f[0] for f in fr])
        feats = np.stack([f[1] for f in fr])
        hands = np.array([f[2] for f in fr])
        if cfg.RESAMPLE:
            win, meta = resample_window(times, feats, t_now, cfg.WINDOW_FRAMES, cfg.WINDOW_FPS)
            if win is None:
                return None, None
            idx, nxt, w = meta
            active = np.where(w >= 0.5, hands[nxt], hands[idx])
            return win, active
        if len(fr) < cfg.WINDOW_FRAMES:
            return None, None
        return feats[-cfg.WINDOW_FRAMES:], hands[-cfg.WINDOW_FRAMES:]

    def push(self, t, features, has_hands):
        """Add one frame (t in seconds). Returns the emitted sign or None."""
        cfg = self.cfg
        self.frames.append((t, np.asarray(features, dtype=np.float32), bool(has_hands)))
        while self.frames and self.frames[0][0] < t - self.keep_s:
            self.frames.popleft()
        if not cfg.RESAMPLE:
            while len(self.frames) > cfg.WINDOW_FRAMES:
                self.frames.popleft()
        self.frame_count += 1

        if has_hands:
            self.last_hand_t = t
        elif self.last_hand_t is None or t - self.last_hand_t > cfg.NO_HAND_CLEAR_S:
            self.display_sign = None
            self.display_conf = 0.0
            self.history.clear()

        win, active = self._window(t)
        if win is None:
            self.last_reason = "window_not_full"
            return None
        n_active = int(active.sum())
        if n_active < cfg.MIN_ACTIVE_FRACTION * cfg.WINDOW_FRAMES:
            self.history.clear()
            self.vote_confs.clear()
            self.display_sign = None
            self.display_conf = 0.0
            self.last_reason = f"few_active {n_active}/{cfg.WINDOW_FRAMES}"
            return None
        n = self.eligible_count
        self.eligible_count += 1
        if n % cfg.INFER_EVERY_N_FRAMES != 0:
            self.last_reason = "skip_frame"
            return None

        probs = self.predict(win)
        self.last_probs = probs
        k = int(np.argmax(probs))
        conf = float(probs[k])
        self.history.append(k if conf >= cfg.CONFIDENCE_THRESHOLD else -1)
        self.vote_confs.append(conf)
        top_s = f"{self.classes[k]} {conf:.2f}"
        if len(self.history) < cfg.VOTE_HISTORY:
            self.last_reason = (f"below_conf {top_s}" if conf < cfg.CONFIDENCE_THRESHOLD
                                else f"vote_filling {len(self.history)}/{cfg.VOTE_HISTORY} {top_s}")
            return None
        valid = [x for x in self.history if x != -1]
        if len(valid) < cfg.VOTES_TO_EMIT:
            self.last_reason = f"below_conf {top_s} ({len(valid)}/{cfg.VOTE_HISTORY} confident)"
            return None
        counts = np.bincount(valid)
        top = int(np.argmax(counts))
        if counts[top] < cfg.VOTES_TO_EMIT:
            self.last_reason = f"vote_not_reached {int(counts[top])}/{cfg.VOTES_TO_EMIT} {top_s}"
            return None

        sign = self.classes[top]
        self.display_sign = sign
        # Mean model probability of the winning class over its votes (was a
        # constant 1.0, which made the badge read 100% for every decision).
        self.display_conf = float(np.mean([c for x, c in zip(self.history, self.vote_confs) if x == top]))
        # Flush: next decision needs fresh frames.
        horizon = cfg.WINDOW_FRAMES / cfg.WINDOW_FPS
        if cfg.RESAMPLE:
            self.min_t = t - horizon * cfg.FLUSH_KEEP_FRACTION
        else:
            keep = int(cfg.WINDOW_FRAMES * cfg.FLUSH_KEEP_FRACTION)
            while len(self.frames) > keep:
                self.frames.popleft()
        self.history.clear()
        self.vote_confs.clear()

        if getattr(cfg, "REPEAT_POLICY", "cooldown") == "differ_from_last":
            # legacy client behaviour: never the same word twice in a row
            if self.last_event and self.last_event[1] == sign:
                self.last_reason = f"repeat_blocked {sign}"
                return None
        else:
            last = self.last_emit.get(sign)
            if last is not None and t - last < cfg.REPEAT_COOLDOWN_S:
                self.last_reason = f"cooldown {sign} {t - last:.1f}/{cfg.REPEAT_COOLDOWN_S}s"
                return None
        self.last_emit[sign] = t
        self.event_id += 1
        self.last_event = (self.event_id, sign, t)
        self.last_reason = f"emit {sign} #{self.event_id}"
        return sign
