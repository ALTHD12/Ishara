// Overlay draw-cost benchmark (host). Paints LandmarkOverlay with a full
// 478-point face mesh, two hands and pose for 300 frames while the points move,
// and prints paint() cost per frame (Dart-side recording; JIT debug build on the
// laptop, so the phone release build is usually faster per op but has a slower
// CPU). Real device numbers: DEBUG READOUT "draw:" line.
//
//   flutter test tool/overlay_bench_test.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/sign_classifier_service.dart';
import '../lib/widgets/landmark_overlay.dart';

String faceQ(Random r, double jitter) {
  final bd = ByteData(478 * 4);
  for (var i = 0; i < 478; i++) {
    final a = i / 478 * 2 * pi;
    final x = 0.5 + 0.12 * cos(a * 7) * (i % 13) / 13 + jitter * r.nextDouble();
    final y = 0.3 + 0.15 * sin(a * 5) * (i % 11) / 11 + jitter * r.nextDouble();
    bd.setInt16(i * 4, (x * 16384).round(), Endian.little);
    bd.setInt16(i * 4 + 2, (y * 16384).round(), Endian.little);
  }
  return base64Encode(bd.buffer.asUint8List());
}

List<List<double>> pts(Random r, int n, double cx, double cy, double s) =>
    [for (var i = 0; i < n; i++) [cx + s * (r.nextDouble() - .5), cy + s * (r.nextDouble() - .5)]];

void main() {
  for (final full in [true, false]) {
    testWidgets('overlay paint cost, face ${full ? 'FULL' : 'LIGHT'}', (tester) async {
      final svc = SignClassifierService();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 240,
            height: 320,
            child: LandmarkOverlay(
              service: svc,
              mirror: true,
              faceColor: const Color(0xFFFF3B5C),
              leftHandColor: const Color(0xFFFFD600),
              rightHandColor: const Color(0xFFFF6A4D),
              poseColor: Colors.white,
            ),
          ),
        ),
      ));
      final r = Random(0);
      final times = <double>[];
      for (var f = 0; f < 300; f++) {
        if (f % 5 == 0) {
          // a new result every 5 display frames (~12 Hz at 60 fps)
          svc.debugInjectResult({
            'pose': pts(r, 33, .5, .6, .4),
            if (full) 'face_q': faceQ(r, .01) else 'face': pts(r, 27, .5, .3, .2),
            'left_hand': pts(r, 21, .3, .6, .15),
            'right_hand': pts(r, 21, .7, .6, .15),
          });
        }
        final sw = Stopwatch()..start();
        await tester.pump(const Duration(milliseconds: 16));
        times.add(sw.elapsedMicroseconds / 1000.0);
      }
      // ignore: avoid_print
      print('face=${full ? 'FULL' : 'LIGHT'}  ${OverlayPerf.summary()}  '
          '(pump incl. layout p50 ${(times..sort())[150].toStringAsFixed(2)} ms)');
      svc.dispose();
    });
  }
}
