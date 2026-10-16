"""Per-stage latency instrumentation for the live pipeline.

Enabled with the environment variable ISL_DEBUG_TIMING=1. When disabled every
call is a cheap no-op so production latency is unaffected.
"""
import os
import time
from collections import defaultdict

DEBUG_TIMING = os.environ.get("ISL_DEBUG_TIMING", "0") not in ("", "0", "false", "False")

# Print a rolling summary every N frames.
SUMMARY_EVERY = int(os.environ.get("ISL_TIMING_SUMMARY_EVERY", "60"))


class FrameTimer:
    """Collects named stage durations (ms) for one frame."""

    __slots__ = ("stages", "_last", "t0")

    def __init__(self, t0=None):
        self.t0 = t0 if t0 is not None else time.perf_counter()
        self._last = self.t0
        self.stages = {}

    def mark(self, name):
        now = time.perf_counter()
        self.stages[name] = (now - self._last) * 1000.0
        self._last = now

    def add(self, name, ms):
        self.stages[name] = self.stages.get(name, 0.0) + ms

    def total_ms(self):
        return (time.perf_counter() - self.t0) * 1000.0


class TimingStats:
    """Rolling per-stage stats, printed periodically."""

    def __init__(self, tag="server"):
        self.tag = tag
        self.samples = defaultdict(list)
        self.count = 0

    def record(self, stages):
        if not DEBUG_TIMING:
            return
        for k, v in stages.items():
            self.samples[k].append(v)
        self.count += 1
        if self.count % SUMMARY_EVERY == 0:
            self.print_summary()

    def print_summary(self):
        if not self.samples:
            return
        parts = []
        for k, vals in self.samples.items():
            vals_sorted = sorted(vals)
            p50 = vals_sorted[len(vals_sorted) // 2]
            p95 = vals_sorted[min(len(vals_sorted) - 1, int(len(vals_sorted) * 0.95))]
            parts.append(f"{k}={p50:.1f}/{p95:.1f}")
        print(f"[TIMING {self.tag}] n={self.count} (p50/p95 ms) " + " ".join(parts), flush=True)
        self.samples.clear()
