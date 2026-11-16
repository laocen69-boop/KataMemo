library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';
import '../models.dart';

Color memoryBandColor(BuildContext context, MemoryBand b) {
  final k = context.k;
  return switch (b) {
    MemoryBand.none => k.mNone,
    MemoryBand.fresh => k.s3,
    MemoryBand.weak => k.mWeak,
    MemoryBand.fair => k.mFair,
    MemoryBand.good => k.s2,
    MemoryBand.strong => k.mStrong,
    MemoryBand.solid => k.s1,
    MemoryBand.mastered => k.s0,
  };
}

List<({String label, Color color})> kMemorySegmentsOf(BuildContext context) {
  final k = context.k;
  return [
    (label: '已掌握', color: k.s0),
    (label: '熟悉', color: k.s1),
    (label: '一般', color: k.s2),
    (label: '不熟', color: k.s3),
    (label: '未学', color: k.s4),
  ];
}

Color kUnselectedColor(BuildContext context) => context.k.nFaint3;

List<({String label, Color color})> kProgressSegmentsOf(BuildContext context) =>
    [
      ...kMemorySegmentsOf(context),
      (label: '未选', color: kUnselectedColor(context)),
    ];

List<int> memoryBandCounts(MemoryBands b) =>
    [b.mastered, b.familiar, b.fair, b.weak, b.newSel];

List<int> progressBarCounts(MemoryBands b, int unselected) =>
    [...memoryBandCounts(b), unselected < 0 ? 0 : unselected];

class MemorySegmentBar extends StatelessWidget {
  const MemorySegmentBar({
    super.key,
    required this.counts,
    this.height = 6,
    this.radius = 3,
  });

  final List<int> counts;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final total = counts.fold(0, (a, b) => a + b);
    if (total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: context.k.g300,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Row(

          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < counts.length; i++)

              if (counts[i] > 0)
                Expanded(
                  flex: counts[i],
                  child:
                      ColoredBox(color: kProgressSegmentsOf(context)[i].color),
                ),
          ],
        ),
      ),
    );
  }
}

class MemoryRing extends StatelessWidget {
  const MemoryRing({
    super.key,
    required this.strength,
    this.size = 40,
    this.strokeWidth = 3,
    this.child,
  });

  final MemoryStrength? strength;
  final double size;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = strength;
    final color =
        s == null ? Colors.transparent : memoryBandColor(context, s.band);

    final fill = s?.fill ?? 0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fill: fill,
          color: color,
          track: context.k.nFaint2.withValues(alpha: 0.25),
          strokeWidth: strokeWidth,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fill,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double fill;
  final Color color;
  final Color track;
  final double strokeWidth;

  late final Paint _trackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..color = track;
  late final Paint _fillPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, r, _trackPaint);
    if (fill <= 0 || color.a == 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * fill.clamp(0.0, 1.0),
      false,
      _fillPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill ||
      old.color != color ||
      old.track != track ||
      old.strokeWidth != strokeWidth;
}

class MemoryStrengthChip extends StatelessWidget {
  const MemoryStrengthChip(
      {super.key, required this.strength, this.compact = false});

  final MemoryStrength? strength;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = strength;
    final color =
        s == null ? context.k.nFaint : memoryBandColor(context, s.band);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MemoryRing(
          strength: s,
          size: compact ? 20 : 26,
          strokeWidth: compact ? 2.5 : 3,
        ),
        const SizedBox(width: 6),
        Text(
          s?.label ?? '记忆程度读取中…',
          style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              color: s == null ? context.k.nFaint2 : color,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
