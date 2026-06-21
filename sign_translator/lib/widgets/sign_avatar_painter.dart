import 'package:flutter/material.dart';

class SignAvatarPainter extends CustomPainter {
  final ThemeData theme;

  SignAvatarPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    
    // Matte-grey 3D effect base paint
    final Paint bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.grey.shade400, Colors.grey.shade800],
        center: const Alignment(-0.3, -0.3),
        radius: 0.8,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // High visibility hands (slightly lighter grey with a hint of accent)
    final Paint handPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.grey.shade300, Colors.grey.shade700],
        center: const Alignment(-0.2, -0.2),
        radius: 0.6,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // Drop shadow paint for 3D depth
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    // Torso / Shoulders
    final torsoPath = Path()
      ..moveTo(center - size.width * 0.35, size.height)
      ..quadraticBezierTo(center - size.width * 0.3, size.height * 0.45, center - size.width * 0.1, size.height * 0.45)
      ..lineTo(center + size.width * 0.1, size.height * 0.45)
      ..quadraticBezierTo(center + size.width * 0.3, size.height * 0.45, center + size.width * 0.35, size.height)
      ..close();
      
    // Draw Torso Shadow
    canvas.drawPath(torsoPath.shift(const Offset(0, 10)), shadowPaint);
    // Draw Torso
    canvas.drawPath(torsoPath, bodyPaint);

    // Neck
    final neckRect = Rect.fromCenter(center: Offset(center, size.height * 0.4), width: size.width * 0.15, height: size.height * 0.15);
    canvas.drawRect(neckRect, bodyPaint);

    // Head
    final headCenter = Offset(center, size.height * 0.25);
    final headRadius = size.width * 0.18;
    canvas.drawCircle(headCenter.translate(0, 5), headRadius, shadowPaint);
    canvas.drawCircle(headCenter, headRadius, bodyPaint);

    // Left Hand (Articulated representation)
    final leftHandCenter = Offset(center - size.width * 0.25, size.height * 0.65);
    final handRadius = size.width * 0.12;
    canvas.drawCircle(leftHandCenter.translate(0, 5), handRadius, shadowPaint);
    canvas.drawCircle(leftHandCenter, handRadius, handPaint);
    // Draw simple fingers for articulation
    for(int i = -1; i <= 1; i++) {
       canvas.drawLine(
         leftHandCenter, 
         leftHandCenter.translate(i * 15.0, -25.0), 
         Paint()..color=Colors.grey.shade400..strokeWidth=8..strokeCap=StrokeCap.round
       );
    }
    
    // Right Hand
    final rightHandCenter = Offset(center + size.width * 0.25, size.height * 0.65);
    canvas.drawCircle(rightHandCenter.translate(0, 5), handRadius, shadowPaint);
    canvas.drawCircle(rightHandCenter, handRadius, handPaint);
    // Fingers
    for(int i = -1; i <= 1; i++) {
       canvas.drawLine(
         rightHandCenter, 
         rightHandCenter.translate(i * 15.0, -25.0), 
         Paint()..color=Colors.grey.shade400..strokeWidth=8..strokeCap=StrokeCap.round
       );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
