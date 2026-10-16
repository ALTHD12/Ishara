"""Decoding of the packed-YUV420 frame payload (header flag 0x40000).

Applies exactly the integer math of CameraUtils.yuvConverter (Dart) so the
RGB image is bit-identical to what the phone used to send:
    r = Y + ((1436*V') >> 10)
    g = Y - ((352*U' + 731*V') >> 10)
    b = Y + ((1814*U') >> 10)          U' = U-128, V' = V-128, clamp 0..255
Verified by tools/check_yuv_packing.py.
"""
import numpy as np


def packed_yuv420_to_rgb(buf, width, height):
    cw, ch = (width + 1) // 2, (height + 1) // 2
    n_y = width * height
    n_c = cw * ch
    a = np.frombuffer(buf, dtype=np.uint8, count=n_y + 2 * n_c)
    y = a[:n_y].reshape(height, width).astype(np.int32)
    u = a[n_y:n_y + n_c].reshape(ch, cw).astype(np.int32) - 128
    v = a[n_y + n_c:].reshape(ch, cw).astype(np.int32) - 128
    # chroma sample for pixel (row, col) is at (row // 2, col // 2)
    u = np.repeat(np.repeat(u, 2, axis=0), 2, axis=1)[:height, :width]
    v = np.repeat(np.repeat(v, 2, axis=0), 2, axis=1)[:height, :width]
    r = y + ((1436 * v) >> 10)
    g = y - ((352 * u + 731 * v) >> 10)
    b = y + ((1814 * u) >> 10)
    return np.clip(np.stack([r, g, b], axis=-1), 0, 255).astype(np.uint8)
