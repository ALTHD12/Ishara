import 'package:flutter/material.dart';

class SignAvatarPainter extends CustomPainter {
  final ThemeData theme;

  SignAvatarPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final borderColor = theme.colorScheme.outline;

    // ── Flat neobrutalism fills — no gradients ────────────────────────────────
    final Paint bodyPaint = Paint()
      ..color = const Color(0xFF9E9E9E) // flat medium grey
      ..style = PaintingStyle.fill;

    final Paint bodyOutline = Paint()
      ..color = borderColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final Paint handPaint = Paint()
      ..color = const Color(0xFFBDBDBD) // flat lighter grey
      ..style = PaintingStyle.fill;

    // Hard offset shadow paint — no blur
    final Paint shadowPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Torso / Shoulders
    final torsoPath = Path()
      ..moveTo(center - size.width * 0.35, size.height)
      ..quadraticBezierTo(center - size.width * 0.3, size.height * 0.45, center - size.width * 0.1, size.height * 0.45)
      ..lineTo(center + size.width * 0.1, size.height * 0.45)
      ..quadraticBezierTo(center + size.width * 0.3, size.height * 0.45, center + size.width * 0.35, size.height)
      ..close();
      
    // Hard shadow for torso (offset, no blur)
    canvas.drawPath(torsoPath.shift(const Offset(4, 4)), shadowPaint);
    // Torso fill
    canvas.drawPath(torsoPath, bodyPaint);
    // Torso outline
    canvas.drawPath(torsoPath, bodyOutline);

    // Neck
    final neckRect = Rect.fromCenter(center: Offset(center, size.height * 0.4), width: size.width * 0.15, height: size.height * 0.15);
    canvas.drawRect(neckRect.shift(const Offset(4, 4)), shadowPaint);
    canvas.drawRect(neckRect, bodyPaint);
    canvas.drawRect(neckRect, bodyOutline);

    // Head
    final headCenter = Offset(center, size.height * 0.25);
    final headRadius = size.width * 0.18;
    // Hard shadow
    canvas.drawCircle(headCenter + const Offset(4, 4), headRadius, shadowPaint);
    // Fill
    canvas.drawCircle(headCenter, headRadius, bodyPaint);
    // Outline
    canvas.drawCircle(headCenter, headRadius, bodyOutline);

    // ── Face features — thick, hand-drawn style ───────────────────────────────
    final facePaint = Paint()
      ..color = borderColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Left Eye (thick dash)
    canvas.drawLine(
      Offset(headCenter.dx - headRadius * 0.35, headCenter.dy - headRadius * 0.1),
      Offset(headCenter.dx - headRadius * 0.15, headCenter.dy - headRadius * 0.1),
      facePaint,
    );
    // Right Eye
    canvas.drawLine(
      Offset(headCenter.dx + headRadius * 0.15, headCenter.dy - headRadius * 0.1),
      Offset(headCenter.dx + headRadius * 0.35, headCenter.dy - headRadius * 0.1),
      facePaint,
    );
    // Mouth (straight line — brutalist, not curved)
    canvas.drawLine(
      Offset(headCenter.dx - headRadius * 0.2, headCenter.dy + headRadius * 0.35),
      Offset(headCenter.dx + headRadius * 0.2, headCenter.dy + headRadius * 0.35),
      facePaint,
    );

    // ── Hands — flat fill with thick outline ──────────────────────────────────
    // Left Hand
    final leftHandCenter = Offset(center - size.width * 0.25, size.height * 0.65);
    final handRadius = size.width * 0.12;
    canvas.drawCircle(leftHandCenter + const Offset(4, 4), handRadius, shadowPaint);
    canvas.drawCircle(leftHandCenter, handRadius, handPaint);
    canvas.drawCircle(leftHandCenter, handRadius, bodyOutline);
    // Thick fingers
    final fingerPaint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final fingerOutlinePaint = Paint()
      ..color = borderColor
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    for (int i = -1; i <= 1; i++) {
      final tip = leftHandCenter.translate(i * 15.0, -25.0);
      canvas.drawLine(leftHandCenter, tip, fingerOutlinePaint);
      canvas.drawLine(leftHandCenter, tip, fingerPaint);
    }
    
    // Right Hand
    final rightHandCenter = Offset(center + size.width * 0.25, size.height * 0.65);
    canvas.drawCircle(rightHandCenter + const Offset(4, 4), handRadius, shadowPaint);
    canvas.drawCircle(rightHandCenter, handRadius, handPaint);
    canvas.drawCircle(rightHandCenter, handRadius, bodyOutline);
    for (int i = -1; i <= 1; i++) {
      final tip = rightHandCenter.translate(i * 15.0, -25.0);
      canvas.drawLine(rightHandCenter, tip, fingerOutlinePaint);
      canvas.drawLine(rightHandCenter, tip, fingerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
