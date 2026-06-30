import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SigningPlaybackWidget extends StatefulWidget {
  final String sequenceAsset;
  final bool isPlaying;
  final double speed;
  final VoidCallback? onComplete;

  const SigningPlaybackWidget({
    super.key,
    required this.sequenceAsset,
    required this.isPlaying,
    this.speed = 1.0,
    this.onComplete,
  });

  @override
  State<SigningPlaybackWidget> createState() => _SigningPlaybackWidgetState();
}

class _SigningPlaybackWidgetState extends State<SigningPlaybackWidget>
    with SingleTickerProviderStateMixin {
  List<List<double>>? _frames;
  int _currentFrame = 0;
  late AnimationController _controller;

  // Static anchors to completely eliminate jitter
  double _baseAnchorX = 0.5;
  double _baseAnchorY = 0.35;
  double _baseShoulderWidth = 0.2;

  // ----------------------------------------------------------
  // Layout per frame: 75 points x 3 = 225 floats
  //   [0..9]   Pose (shoulders, elbows, wrists, hips)
  //   [10..29] Face expression (eyebrows, eyes, mouth)
  //   [30..50] Left hand (21 pts)
  //   [51..71] Right hand (21 pts)
  //   [72..74] Head orientation (nose tip, chin, forehead)
  // ----------------------------------------------------------
  static const int _floatsPerFrame = 225;

  // Pose skeleton connections (indices within the pose block 0-9)
  // 0=L.Shoulder  1=R.Shoulder  2=L.Elbow  3=R.Elbow
  // 4=L.Wrist     5=R.Wrist     6=L.Hip    7=R.Hip
  // 8=L.Knee      9=R.Knee
  static const _poseConnections = [
    [0, 1],       // shoulder bar
    [0, 2], [2, 4], // left arm
    [1, 3], [3, 5], // right arm
    [0, 6], [1, 7], // torso
    [6, 7],         // hip bar
  ];

  // Hand skeleton connections (indices 0-20 within each hand block)
  static const _handConnections = [
    [0,1],[1,2],[2,3],[3,4],        // thumb
    [0,5],[5,6],[6,7],[7,8],        // index
    [5,9],[9,10],[10,11],[11,12],   // middle
    [9,13],[13,14],[14,15],[15,16], // ring
    [13,17],[17,18],[18,19],[19,20],// pinky
    [0,17],                         // palm base
  ];

  // Face expression connections (indices within face block 10-29)
  // Left eyebrow: 0,1,2,3,4    Right eyebrow: 5,6,7,8,9
  // Left eye: 10,11,12,13       Right eye: 14,15,16,17
  // Mouth: 18,19
  static const _leftEyebrowConns = [[0,1],[1,2],[2,3],[3,4]];
  static const _rightEyebrowConns = [[5,6],[6,7],[7,8],[8,9]];
  static const _leftEyeConns = [[10,12],[12,11],[11,13],[13,10]]; // loop
  static const _rightEyeConns = [[14,16],[16,15],[15,17],[17,14]];
  static const _mouthConns = [[18,19]]; // mouth corners

  @override
  void initState() {
    super.initState();
    _loadSequence();
    // Duration is set dynamically after loading frames
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // placeholder, overridden in _startPlayback
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete?.call();
        }
      })
      ..addListener(() {
        if (_frames == null) return;
        final newFrame = (_controller.value * (_frames!.length - 1)).round();
        if (newFrame != _currentFrame) {
          setState(() => _currentFrame = newFrame);
        }
      });
  }

  Future<void> _loadSequence() async {
    try {
      final data = await rootBundle.load(widget.sequenceAsset);
      final bytes = data.buffer.asFloat32List();

      final numFrames = bytes.length ~/ _floatsPerFrame;
      if (numFrames == 0) throw Exception("Empty recording");

      final frames = <List<double>>[];
      for (int i = 0; i < numFrames; i++) {
        frames.add(bytes
            .sublist(i * _floatsPerFrame, (i + 1) * _floatsPerFrame)
            .map((f) => f.toDouble())
            .toList());
      }

      if (mounted) {
        // Calculate static stabilization anchors from the first valid frame
        double bx = 0.5;
        double by = 0.35;
        double bw = 0.2;
        for (final f in frames) {
          if (f.length > 5 && f[0] != 0.0 && f[3] != 0.0) {
            bx = (f[0] + f[3]) / 2.0;
            by = (f[1] + f[4]) / 2.0;
            bw = math.sqrt(math.pow(f[0] - f[3], 2) + math.pow(f[1] - f[4], 2));
            break;
          }
        }

        setState(() {
          _frames = frames;
          _baseAnchorX = bx;
          _baseAnchorY = by;
          _baseShoulderWidth = bw;
        });
        if (widget.isPlaying) _startPlayback();
      }
    } catch (e) {
      debugPrint("Error loading ${widget.sequenceAsset}: $e");
      setState(() => _frames = [List.filled(_floatsPerFrame, 0.0)]);
      widget.onComplete?.call();
    }
  }

  void _startPlayback() {
    if (_frames == null || _frames!.isEmpty) return;
    _currentFrame = 0;
    // Real-time duration: numFrames at 30fps
    final durationMs = ((_frames!.length / 30.0) * 1000).round();
    _controller.duration = Duration(milliseconds: durationMs);
    _controller.forward(from: 0.0);
  }

  @override
  void didUpdateWidget(SigningPlaybackWidget old) {
    super.didUpdateWidget(old);
    if (widget.sequenceAsset != old.sequenceAsset) {
      _loadSequence();
    } else if (widget.isPlaying && !old.isPlaying) {
      _startPlayback();
    } else if (!widget.isPlaying && old.isPlaying) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frames == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _SkeletonPainter(
              frame: _frames![_currentFrame],
              theme: Theme.of(context),
              baseAnchorX: _baseAnchorX,
              baseAnchorY: _baseAnchorY,
              baseShoulderWidth: _baseShoulderWidth,
            ),
          );
        },
      ),
    );
  }
}

// ====================================================================
// Humanoid Silhouette Painter
// ====================================================================
class _SkeletonPainter extends CustomPainter {
  final List<double> frame;
  final ThemeData theme;
  final double baseAnchorX;
  final double baseAnchorY;
  final double baseShoulderWidth;

  _SkeletonPainter({
    required this.frame, 
    required this.theme,
    required this.baseAnchorX,
    required this.baseAnchorY,
    required this.baseShoulderWidth,
  });

  Offset _pt(int idx, Size s) {
    final fi = idx * 3;
    if (fi + 2 >= frame.length) return Offset.zero;
    final x = frame[fi];
    final y = frame[fi + 1];
    if (x == 0 && y == 0) return Offset.zero;
    
    // Subtract the fully stabilized static anchor. This forces the shoulders to ALWAYS be at (0,0) mathematically,
    // neutralizing all body swaying and camera shake from the video without introducing per-frame jitter!
    double centeredX = x - baseAnchorX;
    double centeredY = y - baseAnchorY;
    
    // Zoom out so the entire torso, head, and swinging arms fit within the frame width/height.
    double zoom = 1.05; 
    
    // Map to canvas: put the "center" (the shoulders) slightly above the middle of the widget.
    // We multiply both by s.width to maintain a perfect 1:1 aspect ratio!
    return Offset(
      (s.width / 2) + (centeredX * s.width * zoom),
      (s.height * 0.45) + (centeredY * s.width * zoom), 
    );
  }

  /// Draws a "limb" as a thick rounded-cap line segment (gives tube look)
  void _limb(Canvas c, Paint p, Offset a, Offset b, double thickness) {
    if (a == Offset.zero || b == Offset.zero) return;
    c.drawLine(a, b, p..strokeWidth = thickness..strokeCap = StrokeCap.round);
  }

  /// Draws a filled polygon path from a list of offsets
  void _filledPoly(Canvas c, Paint p, List<Offset> pts) {
    final valid = pts.where((o) => o != Offset.zero).toList();
    if (valid.length < 3) return;
    final path = Path()..moveTo(valid.first.dx, valid.first.dy);
    for (int i = 1; i < valid.length; i++) {
      path.lineTo(valid[i].dx, valid[i].dy);
    }
    path.close();
    c.drawPath(path, p);
  }

  void _handWireframe(Canvas c, Paint linePaint, Paint dotPaint, int base, Size s) {
    // Collect all 21 points for the hand
    final pts = List<Offset>.generate(21, (i) => _pt(base + i, s));
    // If the wrist is missing, the whole hand is probably missing
    if (pts[0] == Offset.zero) return;

    // ---- Draw the Palm (Filled Polygon) ----
    // The palm is formed by connecting the wrist (0), thumb base (1,2), and the knuckles (5,9,13,17)
    final palmPts = [pts[0], pts[1], pts[2], pts[5], pts[9], pts[13], pts[17]];
    if (!palmPts.contains(Offset.zero)) {
      final palmPath = Path()..moveTo(palmPts.first.dx, palmPts.first.dy);
      for (int i = 1; i < palmPts.length; i++) {
        palmPath.lineTo(palmPts[i].dx, palmPts[i].dy);
      }
      palmPath.close();
      
      // Fill palm with a semi-transparent version of the line color
      final palmFill = Paint()
        ..color = linePaint.color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      c.drawPath(palmPath, palmFill);
    }

    // ---- Draw Fingers (Thick Capsules) ----
    // We draw fingers slightly thicker than the skeletal lines to look like actual digits
    final fingerPaint = Paint()
      ..color = linePaint.color
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fingers = [
      [2, 3, 4],          // Thumb (starts from joint 2)
      [5, 6, 7, 8],       // Index
      [9, 10, 11, 12],    // Middle
      [13, 14, 15, 16],   // Ring
      [17, 18, 19, 20],   // Pinky
    ];

    for (final finger in fingers) {
      for (int i = 0; i < finger.length - 1; i++) {
        final p1 = pts[finger[i]];
        final p2 = pts[finger[i+1]];
        if (p1 != Offset.zero && p2 != Offset.zero) {
          c.drawLine(p1, p2, fingerPaint);
        }
      }
    }

    // Fingertips glow (dots on the very tips: 4, 8, 12, 16, 20)
    for (final tip in [4, 8, 12, 16, 20]) {
      if (pts[tip] != Offset.zero) {
        c.drawCircle(pts[tip], 3.5, dotPaint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final primary = theme.colorScheme.primary;
    final accent = theme.colorScheme.tertiary;
    final surface = theme.colorScheme.onSurface;

    // ---- Shadow layer (subtle depth) ----
    final shadowPaint = Paint()
      ..color = primary.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    // ---- Limb paint (thick rounded tubes) ----
    final limbPaint = Paint()
      ..color = primary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // ---- Torso fill ----
    final torsoFill = Paint()
      ..color = primary.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    // ---- Joint paint ----
    final jointPaint = Paint()
      ..color = surface.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    // ---- Face paint ----
    final facePaint = Paint()
      ..color = primary.withValues(alpha: 0.8)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // ---- Hand paint ----
    final handLinePaint = Paint()
      ..color = theme.colorScheme.secondary.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final handDotPaint = Paint()
      ..color = theme.colorScheme.secondary
      ..style = PaintingStyle.fill;

    // ========== POSE LANDMARKS ==========
    // 0=L.Shoulder  1=R.Shoulder  2=L.Elbow  3=R.Elbow
    // 4=L.Wrist     5=R.Wrist     6=L.Hip    7=R.Hip
    // 8=L.Knee      9=R.Knee
    final lShoulder = _pt(0, size);
    final rShoulder = _pt(1, size);
    final lElbow    = _pt(2, size);
    final rElbow    = _pt(3, size);
    final lWrist    = _pt(4, size);
    final rWrist    = _pt(5, size);
    final lHip      = _pt(6, size);
    final rHip      = _pt(7, size);

    // ========== HEAD ==========
    final noseTip  = _pt(72, size);
    final chin     = _pt(73, size);
    final forehead = _pt(74, size);

    // Calculate shoulder width for proportional scaling
    // We use the completely stable static shoulder width!
    // Since baseShoulderWidth is normalized, we scale it by screen width and the zoom factor (1.05).
    double shoulderWidth = baseShoulderWidth * size.width * 1.05;
    final unit = shoulderWidth / 4; // proportional unit

    // ---- Draw shadow silhouette first ----
    if (lShoulder != Offset.zero && rShoulder != Offset.zero) {
      // Shadow torso
      _filledPoly(canvas, shadowPaint, [
        lShoulder + const Offset(3, 5),
        rShoulder + const Offset(3, 5),
        rHip != Offset.zero ? rHip + const Offset(3, 5) : rShoulder + Offset(unit * 0.5, unit * 4),
        lHip != Offset.zero ? lHip + const Offset(3, 5) : lShoulder + Offset(-unit * 0.5, unit * 4),
      ]);
    }

    // ---- Draw torso (filled quad) ----
    if (lShoulder != Offset.zero && rShoulder != Offset.zero) {
      final rH = rHip != Offset.zero ? rHip : rShoulder + Offset(unit * 0.5, unit * 4);
      final lH = lHip != Offset.zero ? lHip : lShoulder + Offset(-unit * 0.5, unit * 4);
      _filledPoly(canvas, torsoFill, [lShoulder, rShoulder, rH, lH]);

      // Torso outline
      final torsoOutline = Paint()
        ..color = primary.withValues(alpha: 0.35)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      _limb(canvas, torsoOutline, lShoulder, rShoulder, 2.0);
      _limb(canvas, torsoOutline, lShoulder, lH, 2.0);
      _limb(canvas, torsoOutline, rShoulder, rH, 2.0);
      _limb(canvas, torsoOutline, lH, rH, 2.0);
    }

    // ---- Neck + Head ----
    if (noseTip != Offset.zero && chin != Offset.zero && forehead != Offset.zero) {
      final headCenter = Offset(
        (noseTip.dx + chin.dx + forehead.dx) / 3,
        (noseTip.dy + chin.dy + forehead.dy) / 3,
      );
      final headRadius = (chin - forehead).distance * 0.55;

      // Neck (connect head to shoulder midpoint)
      if (lShoulder != Offset.zero && rShoulder != Offset.zero) {
        final neckBase = Offset((lShoulder.dx + rShoulder.dx) / 2, (lShoulder.dy + rShoulder.dy) / 2);
        final neckTop = Offset(headCenter.dx, headCenter.dy + headRadius * 0.8);
        _limb(canvas, limbPaint, neckBase, neckTop, unit * 0.6);
      }

      // Head shadow
      canvas.drawCircle(headCenter + const Offset(2, 4), headRadius, shadowPaint);
      // Head fill
      canvas.drawCircle(headCenter, headRadius, Paint()
        ..color = primary.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill);
      // Head outline
      canvas.drawCircle(headCenter, headRadius, Paint()
        ..color = primary.withValues(alpha: 0.5)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke);

      // ---- Face features ----
      // Left eyebrow (face indices 10-14, which are 0-4 in face block)
      for (final conn in _SigningPlaybackWidgetState._leftEyebrowConns) {
        final a = _pt(10 + conn[0], size);
        final b = _pt(10 + conn[1], size);
        if (a != Offset.zero && b != Offset.zero) canvas.drawLine(a, b, facePaint);
      }
      // Right eyebrow
      for (final conn in _SigningPlaybackWidgetState._rightEyebrowConns) {
        final a = _pt(10 + conn[0], size);
        final b = _pt(10 + conn[1], size);
        if (a != Offset.zero && b != Offset.zero) canvas.drawLine(a, b, facePaint);
      }
      // Left eye (filled oval illusion)
      for (final conn in _SigningPlaybackWidgetState._leftEyeConns) {
        final a = _pt(10 + conn[0], size);
        final b = _pt(10 + conn[1], size);
        if (a != Offset.zero && b != Offset.zero) canvas.drawLine(a, b, facePaint);
      }
      // Right eye
      for (final conn in _SigningPlaybackWidgetState._rightEyeConns) {
        final a = _pt(10 + conn[0], size);
        final b = _pt(10 + conn[1], size);
        if (a != Offset.zero && b != Offset.zero) canvas.drawLine(a, b, facePaint);
      }
      // Mouth
      final mouthL = _pt(10 + 18, size);
      final mouthR = _pt(10 + 19, size);
      if (mouthL != Offset.zero && mouthR != Offset.zero) {
        canvas.drawLine(mouthL, mouthR, facePaint..strokeWidth = 2.5);
      }
    } else {
      // ---- FALLBACK HEAD ----
      // If the face landmarker failed to detect the face (often happens when zooming out or blurry),
      // we draw a generic head proportional to the shoulders, WITH generic static features so it's not a faceless orb.
      if (lShoulder != Offset.zero && rShoulder != Offset.zero) {
        final neckBase = Offset((lShoulder.dx + rShoulder.dx) / 2, (lShoulder.dy + rShoulder.dy) / 2);
        final headRadius = shoulderWidth * 0.45;
        // Head goes up from the neck. Since y goes down on screen, we subtract.
        final headCenter = Offset(neckBase.dx, neckBase.dy - headRadius * 1.5);

        // Neck
        _limb(canvas, limbPaint, neckBase, headCenter, unit * 0.6);
        
        // Head shadow
        canvas.drawCircle(headCenter + const Offset(2, 4), headRadius, shadowPaint);
        // Head fill
        canvas.drawCircle(headCenter, headRadius, Paint()
          ..color = primary.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill);
        // Head outline
        canvas.drawCircle(headCenter, headRadius, Paint()
          ..color = primary.withValues(alpha: 0.5)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke);

        // --- Generic Static Expression ---
        // Left Eye
        canvas.drawLine(
          Offset(headCenter.dx - headRadius * 0.35, headCenter.dy - headRadius * 0.1),
          Offset(headCenter.dx - headRadius * 0.15, headCenter.dy - headRadius * 0.1),
          facePaint
        );
        // Right Eye
        canvas.drawLine(
          Offset(headCenter.dx + headRadius * 0.15, headCenter.dy - headRadius * 0.1),
          Offset(headCenter.dx + headRadius * 0.35, headCenter.dy - headRadius * 0.1),
          facePaint
        );
        // Mouth (slight generic smile)
        final mouthPath = Path()
          ..moveTo(headCenter.dx - headRadius * 0.25, headCenter.dy + headRadius * 0.3)
          ..quadraticBezierTo(
            headCenter.dx, headCenter.dy + headRadius * 0.5, 
            headCenter.dx + headRadius * 0.25, headCenter.dy + headRadius * 0.3
          );
        canvas.drawPath(mouthPath, facePaint..strokeWidth = 2.0);
      }
    }

    // ---- Arms (thick tapered tubes) ----
    _limb(canvas, limbPaint, lShoulder, lElbow, unit * 0.8);
    _limb(canvas, limbPaint, lElbow, lWrist, unit * 0.6);
    _limb(canvas, limbPaint, rShoulder, rElbow, unit * 0.8);
    _limb(canvas, limbPaint, rElbow, rWrist, unit * 0.6);

    // ---- Joints (circles at key points) ----
    for (final pt in [lShoulder, rShoulder, lElbow, rElbow, lWrist, rWrist]) {
      if (pt != Offset.zero) {
        canvas.drawCircle(pt, unit * 0.2, jointPaint);
      }
    }

    // ---- Hips to Knees (if visible) ----
    _limb(canvas, limbPaint, lHip, _pt(8, size), unit * 0.7);
    _limb(canvas, limbPaint, rHip, _pt(9, size), unit * 0.7);

    // ========== HANDS (detailed wireframe) ==========
    _handWireframe(canvas, handLinePaint, handDotPaint, 30, size);
    _handWireframe(canvas, handLinePaint, handDotPaint, 51, size);
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) => true;
}
