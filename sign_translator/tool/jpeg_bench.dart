// Problem C evaluation: cost of JPEG-encoding a 240x320 frame in Dart with the
// `image` package (already a dependency), vs. the current packed-YUV copy.
// Runs on the laptop's Dart VM; a phone CPU is typically 2-4x slower.
//
//   dart compile exe tool/jpeg_bench.dart -o <scratch>/jpeg_bench.exe && <scratch>/jpeg_bench.exe
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() {
  const w = 240, h = 320;
  final rnd = Random(1);
  // Smooth-ish synthetic scene (random noise would be unrealistically hard to compress).
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 3;
      rgb[i] = (x + rnd.nextInt(8)) & 255;
      rgb[i + 1] = (y + rnd.nextInt(8)) & 255;
      rgb[i + 2] = ((x + y) ~/ 2 + rnd.nextInt(8)) & 255;
    }
  }
  final image = img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);
  for (final q in [95, 85, 75]) {
    final times = <double>[];
    var size = 0;
    for (var k = 0; k < 40; k++) {
      final sw = Stopwatch()..start();
      final out = img.encodeJpg(image, quality: q);
      times.add(sw.elapsedMicroseconds / 1000.0);
      size = out.length;
    }
    times.sort();
    print('q$q: ${(size / 1024).toStringAsFixed(1)} KB  encode p50 ${times[20].toStringAsFixed(1)} ms'
        '  p95 ${times[37].toStringAsFixed(1)} ms');
  }
  final yuv = Uint8List(w * h * 3 ~/ 2);
  final sw = Stopwatch()..start();
  for (var k = 0; k < 100; k++) {
    yuv.setRange(0, yuv.length, rgb);
  }
  print('packed-YUV copy (current): ${(sw.elapsedMicroseconds / 100000).toStringAsFixed(2)} ms, '
      '${(yuv.length / 1024).toStringAsFixed(1)} KB');
}
