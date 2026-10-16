// Writes random strided YUV420 frames plus (a) the RGB produced by the app's
// CameraUtils.yuvConverter and (b) YuvPacker's packed payload, for
// backend/tools/check_yuv_packing.py to verify bit-exact reconstruction.
//
//   dart run tool/yuv_dump.dart <out_dir>
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../lib/utils/camera_utils.dart';

void main(List<String> args) {
  final outDir = args.isNotEmpty ? args[0] : '.';
  final rnd = Random(42);
  final cases = [
    [320, 240, 320, 2], // typical Android: NV21-like interleaved, pixelStride 2
    [320, 240, 384, 2], // padded rows
    [176, 144, 176, 1], // planar I420, pixelStride 1
    [299, 201, 320, 2], // odd dimensions
  ];
  var k = 0;
  for (final c in cases) {
    final w = c[0], h = c[1], yStride = c[2], ps = c[3];
    final cw = (w + 1) ~/ 2, ch = (h + 1) ~/ 2;
    final uvStride = ps == 2 ? yStride : cw + 3;
    final y = Uint8List(yStride * h)..setAll(0, List.generate(yStride * h, (_) => rnd.nextInt(256)));
    final uvLen = (ch - 1) * uvStride + (cw - 1) * ps + 1;
    final u = Uint8List(uvLen)..setAll(0, List.generate(uvLen, (_) => rnd.nextInt(256)));
    final v = Uint8List(uvLen)..setAll(0, List.generate(uvLen, (_) => rnd.nextInt(256)));
    final data = {
      'formatName': 'yuv420', 'width': w, 'height': h, 'planes': [y, u, v],
      'yRowStride': yStride, 'uvRowStride': uvStride, 'uvPixelStride': ps,
    };
    final rgb = CameraUtils.yuvConverter(data)!;
    final packed = YuvPacker.pack(data)!;
    File('$outDir/case$k.rgb').writeAsBytesSync(rgb['bytes'] as Uint8List);
    File('$outDir/case$k.packed').writeAsBytesSync(packed['bytes'] as Uint8List);
    File('$outDir/case$k.txt').writeAsStringSync('$w $h ${rgb['width']} ${rgb['height']}');
    k++;
  }
  print('wrote $k cases to $outDir');
}
