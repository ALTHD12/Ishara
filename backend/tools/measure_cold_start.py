"""Cold-start timings of the live path (Problem A investigation).

Measures, in a fresh process, what the first frame after backend start pays:
  - routes.websocket import (MediaPipe landmarker creation + model load + the
    existing tf.function trace/warm-up at load time)
  - a tf.function trace WITHOUT warm-up (what the first model call would cost
    if load_ml_model() did not warm up)
  - first vs. steady-state predict_window()
  - first vs. steady-state MediaPipe IMAGE-mode call

    cd backend && venv\\Scripts\\python tools/measure_cold_start.py
"""
import os
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np  # noqa: E402

t0 = time.perf_counter()
import tensorflow as tf  # noqa: E402
t_tf = time.perf_counter()
from ai.mediapipe_model import mp_service  # noqa: E402
t_mp = time.perf_counter()
from routes import websocket as ws  # noqa: E402  (loads + warms model)
t_ws = time.perf_counter()

print(f"import tensorflow            {1000 * (t_tf - t0):8.0f} ms")
print(f"MediaPipe landmarkers        {1000 * (t_mp - t_tf):8.0f} ms")
print(f"routes.websocket (model+warm){1000 * (t_ws - t_mp):8.0f} ms")

win = np.zeros((30, 342), np.float32)
for i in range(3):
    t = time.perf_counter(); ws.predict_window(win); print(f"predict_window call {i + 1}        {1000 * (time.perf_counter() - t):8.1f} ms")

# What the first call costs when nothing warmed the graph up.
m = ws.model


@tf.function(input_signature=[tf.TensorSpec([1, 30, 342], tf.float32)])
def cold(x):
    return m(x, training=False)


t = time.perf_counter(); cold(tf.constant(win[None])); print(f"un-warmed tf.function 1st    {1000 * (time.perf_counter() - t):8.1f} ms")
t = time.perf_counter(); cold(tf.constant(win[None])); print(f"un-warmed tf.function 2nd    {1000 * (time.perf_counter() - t):8.1f} ms")
t = time.perf_counter(); m(win[None], training=False); print(f"eager Keras call             {1000 * (time.perf_counter() - t):8.1f} ms")

img = (np.random.default_rng(0).random((300, 225, 3)) * 255).astype(np.uint8)
for i in range(3):
    t = time.perf_counter(); mp_service.process_image(img); print(f"MediaPipe IMAGE call {i + 1}       {1000 * (time.perf_counter() - t):8.1f} ms")
