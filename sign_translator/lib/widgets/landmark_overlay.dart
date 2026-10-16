import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show FrameTiming, PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/sign_classifier_service.dart';

/// Landmark overlay for the live preview (display only; nothing here affects
/// what is sent to the model).
///
/// Look follows the original HolisticNodePainter (commit b4b614d): dense
/// face-mesh dots + face contour lines (oval, eyes, eyebrows, nose, lips),
/// hand skeleton with joint dots - plus an upper-body pose skeleton, softly
/// glowing hand lines and theme colours (face / left hand / right hand).
///
/// Results arrive at ~8-12 Hz and are ~80-100 ms old, so drawing them raw makes
/// points jump every update and blink when a detection drops for one frame.
/// This widget:
///  * eases displayed points toward the latest result every display frame
///    (exponential smoothing in time, [tau]) instead of jumping,
///  * fades a part out over [fadeOut] when it is lost (no blinking),
///  * keeps each hand on its own track by wrist distance (IMAGE-mode
///    handedness labels can swap between frames); a track keeps the colour of
///    the slot it appeared in,
///  * sizes dots/lines relative to the preview width and to the part's own
///    size, so it reads the same at 0.5 m and 1.5 m.
class LandmarkOverlay extends StatefulWidget {
  const LandmarkOverlay({
    super.key,
    required this.service,
    required this.mirror,
    required this.faceColor,
    required this.leftHandColor,
    required this.rightHandColor,
    required this.poseColor,
  });

  final SignClassifierService service;
  /// Front camera: the preview is mirrored, landmarks are not.
  final bool mirror;
  final Color faceColor;
  final Color leftHandColor;
  final Color rightHandColor;
  final Color poseColor;

  static const double tau = 0.05; // s; ~80% of the way to a new result in 80 ms
  static const double fadeIn = 0.08; // s
  static const double fadeOut = 0.35; // s

  @override
  State<LandmarkOverlay> createState() => _LandmarkOverlayState();
}

/// Paint / raster cost of the overlay, for the debug readout.
class OverlayPerf {
  static final List<double> _paintMs = [];
  static final List<double> _rasterMs = [];
  static int facePoints = 0;

  static void addPaint(double ms) {
    _paintMs.add(ms);
    if (_paintMs.length > 120) _paintMs.removeAt(0);
  }

  static void addTimings(List<FrameTiming> t) {
    for (final f in t) {
      _rasterMs.add(f.rasterDuration.inMicroseconds / 1000.0);
    }
    while (_rasterMs.length > 120) {
      _rasterMs.removeAt(0);
    }
  }

  static double _pct(List<double> v, double q) {
    if (v.isEmpty) return double.nan;
    final s = List<double>.of(v)..sort();
    return s[((s.length - 1) * q).round()];
  }

  /// "paint p50/p95 ms, raster p50/p95 ms" over the last ~120 frames.
  static String summary() =>
      'paint ${_pct(_paintMs, .5).toStringAsFixed(2)}/${_pct(_paintMs, .95).toStringAsFixed(2)}ms '
      'raster ${_pct(_rasterMs, .5).toStringAsFixed(1)}/${_pct(_rasterMs, .95).toStringAsFixed(1)}ms '
      'face $facePoints pts';
}

class _Track {
  List<Offset> pos = const [];
  List<Offset> target = const [];
  double opacity = 0;
  bool present = false;
  /// Hand slot this track (re)appeared in: 'left' / 'right' (colour).
  String label = '';

  Offset? get wrist => target.isEmpty ? null : target[0];

  void setTarget(List<Offset> pts, {String label = ''}) {
    if (pts.isEmpty) {
      present = false;
      return;
    }
    // (Re)appearing or changed layout: snap instead of sliding in from elsewhere.
    if (pos.length != pts.length || opacity < 0.05) {
      pos = List.of(pts);
      if (label.isNotEmpty) this.label = label;
    }
    target = pts;
    present = true;
  }

  /// Returns true while still animating.
  bool step(double dt) {
    var moving = false;
    if (pos.length == target.length && target.isNotEmpty) {
      final k = 1 - exp(-dt / LandmarkOverlay.tau);
      final next = List<Offset>.filled(pos.length, Offset.zero);
      for (var i = 0; i < pos.length; i++) {
        final d = target[i] - pos[i];
        next[i] = pos[i] + d * k;
        if (d.distanceSquared > 1e-7) moving = true;
      }
      pos = next;
    }
    final o = present
        ? min(1.0, opacity + dt / LandmarkOverlay.fadeIn)
        : max(0.0, opacity - dt / LandmarkOverlay.fadeOut);
    if (o != opacity) moving = true;
    opacity = o;
    return moving && opacity > 0;
  }
}

class _LandmarkOverlayState extends State<LandmarkOverlay> with SingleTickerProviderStateMixin {
  final _pose = _Track();
  final _face = _Track();
  final _hands = [_Track(), _Track()];
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  int _seenSeq = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.service.addListener(_onResult);
    SchedulerBinding.instance.addTimingsCallback(OverlayPerf.addTimings);
    _onResult();
  }

  @override
  void didUpdateWidget(LandmarkOverlay old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      old.service.removeListener(_onResult);
      widget.service.addListener(_onResult);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_onResult);
    SchedulerBinding.instance.removeTimingsCallback(OverlayPerf.addTimings);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _onResult() {
    final s = widget.service;
    if (s.resultSeq == _seenSeq) return; // pong / status change, not a new result
    _seenSeq = s.resultSeq;
    _pose.setTarget(s.poseNodes);
    _face.setTarget(s.faceNodes);
    _assignHands([
      if (s.leftHandNodes.isNotEmpty) (s.leftHandNodes, 'left'),
      if (s.rightHandNodes.isNotEmpty) (s.rightHandNodes, 'right'),
    ]);
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// Keep each physical hand on the same track (nearest wrist).
  void _assignHands(List<(List<Offset>, String)> incoming) {
    double dist(_Track t, List<Offset> h) =>
        t.opacity > 0 && t.wrist != null ? (t.wrist! - h[0]).distance : 0.5;
    if (incoming.isEmpty) {
      for (final t in _hands) {
        t.setTarget(const []);
      }
    } else if (incoming.length == 1) {
      final (h, label) = incoming[0];
      final i = dist(_hands[0], h) <= dist(_hands[1], h) ? 0 : 1;
      _hands[i].setTarget(h, label: label);
      _hands[1 - i].setTarget(const []);
    } else {
      final a = dist(_hands[0], incoming[0].$1) + dist(_hands[1], incoming[1].$1);
      final b = dist(_hands[0], incoming[1].$1) + dist(_hands[1], incoming[0].$1);
      final swap = b < a;
      final first = incoming[swap ? 1 : 0], second = incoming[swap ? 0 : 1];
      _hands[0].setTarget(first.$1, label: first.$2);
      _hands[1].setTarget(second.$1, label: second.$2);
    }
  }

  void _onTick(Duration now) {
    final dt = _lastTick == Duration.zero ? 1 / 60 : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    var busy = false;
    for (final t in [_pose, _face, ..._hands]) {
      if (t.step(dt.clamp(0.0, 0.1))) busy = true;
    }
    _repaint.value++;
    if (!busy) _ticker.stop(); // idle: no repaint until the next result
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(this, _repaint),
      size: Size.infinite,
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.s, Listenable repaint) : super(repaint: repaint);
  final _LandmarkOverlayState s;

  static const hand = [
    [0, 1], [1, 2], [2, 3], [3, 4], // thumb
    [0, 5], [5, 6], [6, 7], [7, 8], // index
    [5, 9], [9, 10], [10, 11], [11, 12], // middle
    [9, 13], [13, 14], [14, 15], [15, 16], // ring
    [13, 17], [0, 17], [17, 18], [18, 19], [19, 20], // pinky + palm
  ];
  // Upper body: shoulders, arms (MediaPipe pose 11-16).
  static const pose = [[11, 12], [11, 13], [13, 15], [12, 14], [14, 16]];
  static const poseDots = [11, 12, 13, 14, 15, 16];

  // Face-mesh contours (MediaPipe FaceMesh indices) as polylines; closed ones
  // repeat their first index at the end.
  static const faceContours = <List<int>>[
    // oval
    [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152,
      148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109, 10],
    // right eye, left eye
    [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246, 33],
    [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398, 362],
    // eyebrows (upper + lower edge)
    [70, 63, 105, 66, 107], [46, 53, 52, 65, 55],
    [300, 293, 334, 296, 336], [276, 283, 282, 295, 285],
    // nose: bridge, tip to base, nostrils
    [168, 6, 197, 195, 5, 4, 1], [1, 19, 94, 2], [98, 97, 2, 326, 327],
    // lips outer, inner
    [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267, 0, 37, 39, 40, 185, 61],
    [78, 95, 88, 178, 87, 14, 317, 402, 318, 324, 308, 415, 310, 311, 312, 13, 82, 81, 80, 191, 78],
  ];
  // Light mode: server sends these 27 points (backend OVERLAY_FACE_POINTS);
  // first 18 = oval loop.
  static const lightOvalLen = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = Stopwatch()..start();
    final w = s.widget;
    final W = size.width;
    Offset map(Offset n) => Offset((w.mirror ? 1.0 - n.dx : n.dx) * W, n.dy * size.height);

    // Base unit: 1/360 of the preview width (design was tuned on a 360 px wide preview).
    final u = W / 360.0;

    _paintPose(canvas, map, u, w.poseColor);
    _paintFace(canvas, map, u, w.faceColor);
    for (final h in s._hands) {
      _paintHand(canvas, h, map, u, h.label == 'right' ? w.rightHandColor : w.leftHandColor);
    }
    OverlayPerf.addPaint(sw.elapsedMicroseconds / 1000.0);
  }

  void _paintPose(Canvas canvas, Offset Function(Offset) map, double u, Color c) {
    final t = s._pose;
    if (t.opacity <= 0 || t.pos.length < 17) return;
    final p = [for (final n in t.pos) map(n)];
    final path = Path();
    for (final e in pose) {
      path
        ..moveTo(p[e[0]].dx, p[e[0]].dy)
        ..lineTo(p[e[1]].dx, p[e[1]].dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = c.withValues(alpha: 0.55 * t.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * u
          ..strokeCap = StrokeCap.round);
    _dots(canvas, [for (final i in poseDots) p[i]], 3.2 * u, c.withValues(alpha: 0.8 * t.opacity));
  }

  void _paintFace(Canvas canvas, Offset Function(Offset) map, double u, Color c) {
    final f = s._face;
    OverlayPerf.facePoints = f.opacity > 0 ? f.pos.length : 0;
    if (f.opacity <= 0 || f.pos.isEmpty) return;
    final p = [for (final n in f.pos) map(n)];
    final full = p.length >= 468;
    // Scale with face size: inter-ocular distance (full) or oval width (light).
    final span = full
        ? (p[33] - p[263]).distance
        : (p.length >= lightOvalLen ? (p[4] - p[14]).distance * 0.55 : 60 * u);
    final k = (span / (60 * u)).clamp(0.6, 1.6);

    final line = Paint()
      ..color = c.withValues(alpha: 0.55 * f.opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * u * k
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (full) {
      for (final poly in faceContours) {
        path.moveTo(p[poly[0]].dx, p[poly[0]].dy);
        for (final i in poly.skip(1)) {
          path.lineTo(p[i].dx, p[i].dy);
        }
      }
      canvas.drawPath(path, line);
      // Dense mesh: all points in one drawRawPoints call.
      _dots(canvas, p, 0.9 * u * k, c.withValues(alpha: 0.75 * f.opacity));
    } else {
      if (p.length >= lightOvalLen) {
        path.addPolygon(p.sublist(0, lightOvalLen), true);
        canvas.drawPath(path, line);
      }
      _dots(canvas, p.skip(min(lightOvalLen, p.length)).toList(), 2.0 * u * k,
          c.withValues(alpha: 0.8 * f.opacity));
    }
  }

  void _paintHand(Canvas canvas, _Track t, Offset Function(Offset) map, double u, Color c) {
    if (t.opacity <= 0 || t.pos.length < 21) return;
    final p = [for (final n in t.pos) map(n)];
    // Scale with hand size: wrist -> middle-finger knuckle (~45 px at 1 m on a 360 px preview).
    final k = ((p[0] - p[9]).distance / (45 * u)).clamp(0.6, 1.5);
    final path = Path();
    for (final e in hand) {
      path
        ..moveTo(p[e[0]].dx, p[e[0]].dy)
        ..lineTo(p[e[1]].dx, p[e[1]].dy);
    }
    // Soft glow under a crisp line.
    canvas.drawPath(
        path,
        Paint()
          ..color = c.withValues(alpha: 0.35 * t.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * u * k
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * u * k));
    canvas.drawPath(
        path,
        Paint()
          ..color = c.withValues(alpha: 0.95 * t.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * u * k
          ..strokeCap = StrokeCap.round);
    _dots(canvas, p, 3.0 * u * k, Colors.white.withValues(alpha: t.opacity));
    _dots(canvas, p, 1.8 * u * k, c.withValues(alpha: t.opacity));
  }

  /// All dots of a part in a single drawRawPoints call (round caps = circles).
  void _dots(Canvas canvas, List<Offset> pts, double radius, Color c) {
    if (pts.isEmpty) return;
    final xy = Float32List(pts.length * 2);
    for (var i = 0; i < pts.length; i++) {
      xy[2 * i] = pts[i].dx;
      xy[2 * i + 1] = pts[i].dy;
    }
    canvas.drawRawPoints(
        PointMode.points,
        xy,
        Paint()
          ..color = c
          ..strokeWidth = radius * 2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => old.s != s;
}
