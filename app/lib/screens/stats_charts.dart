part of 'stats_screen.dart';

class _MemoryCurveChart extends StatelessWidget {
  final double targetRetention;

  final double? actualRecall;

  final double? medianS;

  const _MemoryCurveChart({
    required this.targetRetention,
    required this.actualRecall,
    required this.medianS,
  });

  static const _maxDays = 30;

  @override
  Widget build(BuildContext context) {
    final s = medianS;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: _maxDays.toDouble(),
        minY: 0,
        maxY: 1,
        lineBarsData: [
          if (s != null)
            LineChartBarData(
              spots: [
                for (var t = 0; t <= _maxDays; t++)
                  FlSpot(t.toDouble(), Fsrs.retrievability(t.toDouble(), s)),
              ],
              isCurved: true,
              color: context.k.q4,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: context.k.q4.withValues(alpha: 0.12),
              ),
            ),

          LineChartBarData(
            spots: [
              FlSpot(0, targetRetention),
              FlSpot(_maxDays.toDouble(), targetRetention),
            ],
            color: context.k.orange.withValues(alpha: 0.7),
            barWidth: 1.2,
            dashArray: [5, 4],
            dotData: const FlDotData(show: false),
          ),
        ],

        extraLinesData: actualRecall == null
            ? const ExtraLinesData()
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: actualRecall!,
                  color: kSpeakGreen,
                  strokeWidth: 2,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) =>
                        '实际 ${(actualRecall! * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: kSpeakGreen),
                  ),
                ),
              ]),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, meta) => _percentTitle(context, v, meta),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              getTitlesWidget: (v, meta) => _dayTitle(context, v, meta),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (_) => FlLine(
              color: context.k.nFaint2.withValues(alpha: 0.15), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  static Widget _percentTitle(BuildContext context, double v, TitleMeta meta) {
    return Text('${(v * 100).round()}%',
        style: TextStyle(fontSize: 10, color: context.k.nFaint2));
  }

  static Widget _dayTitle(BuildContext context, double v, TitleMeta meta) {
    final d = v.round();
    if (d < 0 || d > _maxDays) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child:
          Text('$d天', style: TextStyle(fontSize: 10, color: context.k.nFaint2)),
    );
  }
}

class _ForgetCurveChart extends StatelessWidget {
  final List<ForgetBin> data;
  const _ForgetCurveChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final b in data)
        if (statBinVisible(b.reviews)) b
    ];
    if (shown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '复习记录还太少：每个间隔档要满 $statBinMinReviews 次复习才画得出来'
            '（现在一共 ${data.fold<int>(0, (a, b) => a + b.reviews)} 次）。\n'
            '多学几天再回来看。',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.k.nFaint2, fontSize: 12),
          ),
        ),
      );
    }

    final maxRate =
        shown.fold(0.0, (a, b) => math.max(a, b.forgets / b.reviews));
    final step = statPctStep(maxRate);
    final maxY = statAxisMax(maxRate, step);

    final hidden = [
      for (final b in data)
        if (b.reviews > 0 && !statBinVisible(b.reviews)) b
    ].length;

    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final i = group.x.toInt();
                    if (i < 0 || i >= shown.length) return null;
                    final b = shown[i];
                    final pct = (b.forgets / b.reviews * 100).round();
                    return BarTooltipItem(
                      '间隔 ${b.label} 天\n困难率 $pct%\n'
                      '${b.reviews} 次复习 / ${b.words} 个词',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: step,
                    getTitlesWidget: (v, meta) {
                      final p = (v / step).round();
                      if ((v - p * step).abs() > 1e-9) {
                        return const SizedBox.shrink();
                      }
                      return Text('${(v * 100).round()}%',
                          style: TextStyle(
                              fontSize: 10, color: context.k.nFaint2));
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= shown.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(shown[i].label,
                            style: TextStyle(
                                fontSize: 10, color: context.k.nFaint2)),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: context.k.nFaint2.withValues(alpha: 0.15), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < shown.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: shown[i].forgets / shown[i].reviews,
                      width: 22,

                      color: statBinSolid(shown[i].reviews)
                          ? kRatingForget
                          : kRatingForget.withValues(alpha: 0.35),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '横轴：距上次复习的天数'
          '${hidden > 0 ? ' ｜ 另有 $hidden 个档复习不足 $statBinMinReviews 次，未画' : ''}'
          ' ｜ 浅色柱 = 不足 $statBinSolidReviews 次',
          style: TextStyle(fontSize: 10.5, color: context.k.nFaint2),
        ),
      ],
    );
  }
}

class _TrendModeSwitch extends StatelessWidget {
  final int mode;
  final void Function(int) onChanged;
  const _TrendModeSwitch({required this.mode, required this.onChanged});

  static const _labels = ['30 天', '30 周', '30 月'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _labels.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: i == mode
                    ? kSpeakGreen
                    : context.k.nFaint2.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_labels[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == mode ? FontWeight.w600 : FontWeight.w400,
                      color: i == mode ? Colors.white : context.k.nT2)),
            ),
          ),
      ],
    );
  }
}

class _Bucket {
  final String label;
  final int easy, know, fuzzy, forget;

  final DateTime day;
  const _Bucket(
      this.label, this.easy, this.know, this.fuzzy, this.forget, this.day);
  int get total => easy + know + fuzzy + forget;
}

class _TrendChart extends StatelessWidget {

  final Map<String, ({int easy, int know, int fuzzy, int forget})> daily;
  final int mode;
  const _TrendChart({required this.daily, required this.mode, this.onTapDay});

  final void Function(DateTime day)? onTapDay;

  static const _zero = (easy: 0, know: 0, fuzzy: 0, forget: 0);

  static String _key(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<_Bucket> _series() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _Bucket bucket(String label, List<DateTime> days, DateTime tapDay) {
      var e = 0, k = 0, f = 0, g = 0;
      for (final d in days) {
        final v = daily[_key(d)] ?? _zero;
        e += v.easy;
        k += v.know;
        f += v.fuzzy;
        g += v.forget;
      }
      return _Bucket(label, e, k, f, g, tapDay);
    }

    final out = <_Bucket>[];
    if (mode == 0) {
      for (var i = 29; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        out.add(bucket('${d.month}/${d.day}', [d], d));
      }
    } else if (mode == 1) {
      for (var i = 29; i >= 0; i--) {
        final end = today.subtract(Duration(days: 7 * i));
        final start = end.subtract(const Duration(days: 6));
        out.add(bucket(
            '${start.month}/${start.day}',
            [for (var j = 0; j < 7; j++) end.subtract(Duration(days: j))],
            end));
      }
    } else {
      for (var i = 29; i >= 0; i--) {

        final m = DateTime(now.year, now.month - i, 1);
        final next = DateTime(m.year, m.month + 1, 1);
        final lastDay = next.subtract(const Duration(days: 1));

        final tap = lastDay.isAfter(today) ? today : lastDay;
        out.add(bucket(
            '${m.month}月',
            [
              for (var d = m;
                  d.isBefore(next);
                  d = d.add(const Duration(days: 1)))
                d
            ],
            tap));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final data = _series();
    final maxV = data.fold(0, (a, e) => math.max(a, e.total));
    final step = statIntStep(maxV);
    final maxY = statAxisMax(maxV, step);

    final labelEvery = mode == 2 ? 6 : 5;

    LineChartBarData line(List<int> values, Color color,
            {bool dots = true, double width = 1.6, bool area = false}) =>
        LineChartBarData(
          spots: [
            for (var i = 0; i < data.length; i++)
              FlSpot(i.toDouble(), values[i].toDouble()),
          ],
          isCurved: false,
          color: color,
          barWidth: width,
          dotData: FlDotData(
            show: dots,

            checkToShowDot: (spot, barData) => spot.y > 0,
            getDotPainter: (spot, percent, bar, index) =>
                FlDotCirclePainter(radius: 2, color: color, strokeWidth: 0),
          ),
          belowBarData: BarAreaData(
              show: area, color: color.withValues(alpha: 0.06)),
        );

    return Column(
      children: [
        _legend(context, data),
        const SizedBox(height: 6),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (data.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineTouchData: LineTouchData(
                enabled: true,

                touchCallback: (event, resp) {
                  if (onTapDay == null) return;
                  if (event is! FlTapUpEvent) return;
                  final spots = resp?.lineBarSpots;
                  if (spots == null || spots.isEmpty) return;
                  final i = spots.first.spotIndex;
                  if (i < 0 || i >= data.length) return;
                  onTapDay!(data[i].day);
                },
                touchTooltipData: LineTouchTooltipData(

                  getTooltipItems: (spots) {
                    if (spots.isEmpty) return const [];
                    final b = data[spots.first.spotIndex];
                    final unit = mode == 0 ? '当天' : (mode == 1 ? '这一周' : '这个月');
                    return [
                      LineTooltipItem(
                        '${b.label}\n$unit ${b.total} 个词\n'
                        '轻松 ${b.easy} ｜ 记得 ${b.know} ｜ '
                        '模糊 ${b.fuzzy} ｜ 困难 ${b.forget}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      null,
                      null,
                      null,
                      null,
                    ];
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: step,
                    getTitlesWidget: (v, meta) => _intTick(context, v, meta),
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= data.length) {
                        return const SizedBox.shrink();
                      }
                      if (i % labelEvery != 0 && i != data.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(data[i].label,
                            style: TextStyle(
                                fontSize: 10, color: context.k.nFaint2)),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: context.k.nFaint2.withValues(alpha: 0.15),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [

                line([for (final b in data) b.total],
                    context.k.nT2.withValues(alpha: 0.35),
                    dots: false, width: 1, area: true),
                line([for (final b in data) b.easy], kRatingEasy),
                line([for (final b in data) b.know], kRatingKnow),
                line([for (final b in data) b.fuzzy], kRatingFuzzy),
                line([for (final b in data) b.forget], kRatingForget),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, List<_Bucket> data) {
    final total = data.fold(
        (easy: 0, know: 0, fuzzy: 0, forget: 0),
        (a, b) => (
              easy: a.easy + b.easy,
              know: a.know + b.know,
              fuzzy: a.fuzzy + b.fuzzy,
              forget: a.forget + b.forget
            ));
    final counts = [total.easy, total.know, total.fuzzy, total.forget];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (var i = 0; i < kRatingLegend.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: kRatingLegend[i].color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text('${kRatingLegend[i].label} ${counts[i]}',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: counts[i] == 0
                          ? context.k.g400
                          : context.k.g700)),
            ],
          ),
      ],
    );
  }

  static Widget _intTick(BuildContext context, double v, TitleMeta meta) {
    final i = v.round();
    if ((v - i).abs() > 1e-9) return const SizedBox.shrink();
    return Text('$i', style: TextStyle(fontSize: 10, color: context.k.nFaint2));
  }
}

class _Sparkline extends StatelessWidget {
  final List<int> series;
  const _Sparkline({required this.series});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    return CustomPaint(
      painter: _SparklinePainter(
        series: series,
        line: kSpeakGreen,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.series, required this.line});

  final List<int> series;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final maxV = series.reduce(math.max);

    if (maxV <= 0) {
      final p = Paint()
        ..color = line.withValues(alpha: 0.25)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(0, size.height - 1), Offset(size.width, size.height - 1), p);
      return;
    }
    final n = series.length;
    final dx = n <= 1 ? 0.0 : size.width / (n - 1);

    final usable = size.height - 4;
    Offset at(int i) => Offset(
          n <= 1 ? size.width / 2 : dx * i,
          size.height - 1 - (series[i] / maxV) * usable,
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = line.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series || old.line != line;
}

class _RecallRateChart extends StatelessWidget {
  final Map<String, ({int easy, int know, int fuzzy, int forget})> daily;
  final int mode;
  const _RecallRateChart({required this.daily, required this.mode});

  List<({String label, double? rate})> _series() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    ({String label, double? rate}) one(String label, List<DateTime> days) {
      var e = 0, k = 0, f = 0, g = 0;
      for (final d in days) {
        final v = daily[key(d)] ?? (easy: 0, know: 0, fuzzy: 0, forget: 0);
        e += v.easy;
        k += v.know;
        f += v.fuzzy;
        g += v.forget;
      }
      final total = e + k + f + g;
      return (label: label, rate: total == 0 ? null : (e + k) / total);
    }

    final out = <({String label, double? rate})>[];
    if (mode == 0) {
      for (var i = 29; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        out.add(one('${d.month}/${d.day}', [d]));
      }
    } else if (mode == 1) {
      for (var i = 29; i >= 0; i--) {
        final end = today.subtract(Duration(days: 7 * i));
        out.add(one('${end.month}/${end.day}',
            [for (var j = 0; j < 7; j++) end.subtract(Duration(days: j))]));
      }
    } else {
      for (var i = 29; i >= 0; i--) {
        final m = DateTime(now.year, now.month - i, 1);
        final next = DateTime(m.year, m.month + 1, 1);
        out.add(one('${m.month}月', [
          for (var d = m; d.isBefore(next); d = d.add(const Duration(days: 1)))
            d
        ]));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final data = _series();
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++)
        if (data[i].rate != null) FlSpot(i.toDouble(), data[i].rate!),
    ];
    if (spots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('这段时间还没有作答记录，切到「词数」看看，或先学几个词。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.k.nFaint2, fontSize: 12)),
        ),
      );
    }
    final labelEvery = mode == 2 ? 6 : 5;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: 1,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: kSpeakGreen,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: kSpeakGreen.withValues(alpha: 0.10),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 0.25,
              getTitlesWidget: (v, meta) => Text('${(v * 100).round()}%',
                  style: TextStyle(fontSize: 10, color: context.k.nFaint2)),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                if (i % labelEvery != 0 && i != data.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(data[i].label,
                      style: TextStyle(fontSize: 10, color: context.k.nFaint2)),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (_) => FlLine(
              color: context.k.nFaint2.withValues(alpha: 0.15), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
