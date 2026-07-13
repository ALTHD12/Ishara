import 'package:flutter/material.dart';
import '../theme/app_themes.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// NeoContainer — the workhorse neobrutalism card/panel
// ═══════════════════════════════════════════════════════════════════════════════

class NeoContainer extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool withShadow;
  final double? width;
  final double? height;

  const NeoContainer({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.margin,
    this.withShadow = true,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: withShadow
          ? AppThemes.neoDecoration(theme, color: color)
          : AppThemes.neoDecorationFlat(theme, color: color),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NeoBadge — small floating label (e.g. "LIVE", "76%")
// ═══════════════════════════════════════════════════════════════════════════════

class NeoBadge extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final Widget? leading;

  const NeoBadge({
    super.key,
    required this.text,
    this.backgroundColor,
    this.textColor,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 2.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 5),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1.0,
              color: textColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NeoChip — word chip for gloss sequences
// ═══════════════════════════════════════════════════════════════════════════════

class NeoChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color? activeColor;
  final Color? activeTextColor;
  final VoidCallback? onTap;

  const NeoChip({
    super.key,
    required this.label,
    this.isActive = false,
    this.activeColor,
    this.activeTextColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillColor = isActive
        ? (activeColor ?? theme.colorScheme.onSurface)
        : theme.colorScheme.surface;
    final labelColor = isActive
        ? (activeTextColor ?? theme.colorScheme.surface)
        : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
          border: Border.all(
            color: theme.colorScheme.outline,
            width: AppThemes.borderWidth,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 1.0,
            color: labelColor,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CornerReticlesPainter — bracket marks on camera viewport corners
// ═══════════════════════════════════════════════════════════════════════════════

class CornerReticlesPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double length;
  final double inset;

  CornerReticlesPainter({
    this.color = Colors.white,
    this.strokeWidth = 3.0,
    this.length = 24.0,
    this.inset = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(Offset(inset, inset), Offset(inset + length, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(inset, inset + length), paint);

    // Top-right
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset - length, inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + length), paint);

    // Bottom-left
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset + length, size.height - inset), paint);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset, size.height - inset - length), paint);

    // Bottom-right
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset - length, size.height - inset), paint);
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset, size.height - inset - length), paint);
  }

  @override
  bool shouldRepaint(covariant CornerReticlesPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DotGridPainter — subtle repeating dot pattern for background
// ═══════════════════════════════════════════════════════════════════════════════

class DotGridPainter extends CustomPainter {
  final Color dotColor;
  final double spacing;
  final double radius;

  DotGridPainter({
    this.dotColor = Colors.black,
    this.spacing = 20.0,
    this.radius = 1.2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter oldDelegate) => false;
}

/// A convenience widget that paints the dot grid behind its child.
class DotGridBackground extends StatelessWidget {
  final Widget child;
  final Color? dotColor;

  const DotGridBackground({
    super.key,
    required this.child,
    this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: DotGridPainter(
              dotColor: dotColor ?? Colors.black,
            ),
          ),
        ),
        child,
      ],
    );
  }
}
