"""Verifies that packed-YUV420 frames decode to exactly the RGB the app's Dart
converter produces (so features cannot shift).

    cd sign_translator && dart run tool/yuv_dump.dart <dir>
    cd backend && python tools/check_yuv_packing.py <dir>
"""
import glob
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from frame_codec import packed_yuv420_to_rgb  # noqa: E402


def main(d):
    ok = True
    for txt in sorted(glob.glob(os.path.join(d, "case*.txt"))):
        base = txt[:-4]
        w, h, ow, oh = map(int, open(txt).read().split())
        ref = np.frombuffer(open(base + ".rgb", "rb").read(), np.uint8).reshape(oh, ow, 3)
        got = packed_yuv420_to_rgb(open(base + ".packed", "rb").read(), w, h)
        same = got.shape == ref.shape and np.array_equal(got, ref)
        ok &= same
        print(f"{os.path.basename(base)} {w}x{h}: {'IDENTICAL' if same else 'MISMATCH'}"
              + ("" if same else f" max|diff|={np.abs(got.astype(int) - ref.astype(int)).max()}"))
    print("ALL IDENTICAL" if ok else "FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1])
