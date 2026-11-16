library;

import 'package:flutter/material.dart';

class DottedLine extends StatelessWidget {

  final double? width;
  final Color color;
  final double dotSize;
  final double gap;
  final double thickness;

  const DottedLine({
    super.key,
    this.width,
    required this.color,
    this.dotSize = 2,
    this.gap = 4,
    this.thickness = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      painter: _DottedLinePainter(
          color: color, dotSize: dotSize, gap: gap, thickness: thickness),
      size: width == null ? Size.infinite : Size(width!, thickness),
    );
    if (width != null) return painter;
    return SizedBox(height: thickness, width: double.infinity, child: painter);
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;
  final double dotSize;
  final double gap;
  final double thickness;

  _DottedLinePainter({
    required this.color,
    required this.dotSize,
    required this.gap,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final y = (size.height - thickness) / 2;
    for (double x = 0; x + dotSize <= size.width; x += dotSize + gap) {
      canvas.drawRect(Rect.fromLTWH(x, y, dotSize, thickness), paint);
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter old) =>
      old.color != color ||
      old.dotSize != dotSize ||
      old.gap != gap ||
      old.thickness != thickness;
}
