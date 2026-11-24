part of 'stats_screen.dart';

/// 记忆曲线：预测保留率（横线）+ 实际回忆率（大圆点）
class _MemoryCurveChart extends StatelessWidget {
  final double targetRetention;

  /// 总回忆率；null = 还没有作答记录，不画这条线
  final double? actualRecall;

  /// 已学词的中位稳定性；null = 还没学过东西，只画坐标轴
  final double? medianS;

  /// 全量已学词的稳定度集合（非空时用混合期望 `1/N ∑ R(t, S_i)` 替代中位数代入）
  final List<double> stabilities;

  const _MemoryCurveChart({
    required this.targetRetention,
    required this.actualRecall,
    required this.medianS,
    this.stabilities = const [],
  });

  /// 横轴天数范围。
  ///
  /// 原先是 `maxX: 6` 且点按 `t = 0..6` **天**算，横轴标签却写
  /// `i * 5` → 「0/5/10/…/30天」，**差了 5 倍**：曲线的形状是 6 天内的衰减，
  /// 却被标成 30 天。这里统一到 30 天，标签与计算一致。
  static const _maxDays = 30;

  double _expectedRecallAt(int day, double fallbackS) {
    if (stabilities.isEmpty) {
      return Fsrs.retrievability(day.toDouble(), fallbackS);
    }
    var sum = 0.0;
    final t = day.toDouble();
    for (final st in stabilities) {
      sum += Fsrs.retrievability(t, st);
    }
    return sum / stabilities.length;
  }

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
          if (s != null || stabilities.isNotEmpty)
            LineChartBarData(
              spots: [
                for (var t = 0; t <= _maxDays; t++)
                  FlSpot(t.toDouble(), _expectedRecallAt(t, s ?? 1.0)),
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
          // 目标保留率参考线
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
        // 实际回忆率横线。门槛就是这条线本身有没有数据——
        // 原先用「今天有没有复习」当门槛，而线画的是全时段的回忆率，两者不同源。
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
              interval: 5, // 每 5 天一个刻度，与 _dayTitle 的取值一致
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

  /// 横轴是「距上次复习的天数」，与曲线点的算法同一口径。
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

/// 遗忘曲线：按「距上次复习的天数」分档的**实测**困难率柱状图。
///
/// 用户 2026-09-21：「忘记率的表格设计也不合理」。旧版三处不合理，这里逐条改掉：
///   ① **横轴是幸存者偏差**（按每个词**当前**的 `srs.reps` 分组）⇒ 换成按
///      **当时那次复习的间隔**分档，早早忘掉的词落在短间隔档，不会被漏掉；
///   ② **20 档每档几个词也照画** ⇒ 固定 8 档 + 样本门槛（`statBinVisible` /
///      `statBinSolid`），分母太小的档不画、偏小的画浅色；
///   ③ **颜色按 30% 阈值变色** ⇒ 单一色 `kRatingForget`（和评分按钮上的
///      「困难」是同一个红，用户不用重新学一遍配色），浓度只表示样本量。
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
    // Y 轴按**数据实际范围**取刻度。原来写死 maxY: 1.0（0–100%），
    // 而困难率天然偏低（常在个位数到 30%）——柱子全挤在底部，等于没有坐标可读。
    final maxRate =
        shown.fold(0.0, (a, b) => math.max(a, b.forgets / b.reviews));
    final step = statPctStep(maxRate);
    final maxY = statAxisMax(maxRate, step);
    // 只数「**有**复习、但样本不够没画」的档：空的档（用户还没在那么长的
    // 间隔上复习过）不值得报，报「另有 7 个档」只会让人以为数据丢了。
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
                      // 浓度 = 样本量，不是好坏：浅色只是说「这几根别太当真」。
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

/// 集成趋势图的档位切换（30 天 / 30 周 / 30 月）。
///
/// 做成一行圆角小按键，选中填品牌色。
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

/// 一个柱子：某个时间窗（天/周/月）里过过的词数，按四档拆分。
class _Bucket {
  final String label;
  final int easy, know, fuzzy, forget;

  /// 这根柱子点击后要打开的**那一天**（日档 = 当天；周/月档 = 窗口最后一天）。
  final DateTime day;
  const _Bucket(
      this.label, this.easy, this.know, this.fuzzy, this.forget, this.day);
  int get total => easy + know + fuzzy + forget;
}

/// 集成趋势图：**一个点 = 一天 / 一周 / 一月**里「过过的词数」，
/// 四条折线分别是 **轻松／记得／模糊／困难**，浅灰面积是总量。
///
/// 口径 = 用户 2026-09-20 说清的那版（前几版都不是他要的，别按印象改回去）：
/// > 统计所有当天过的单词，且统计用户在**第一次**遇到这个单词时点的是什么，
/// > 一个单词统计一次就够了，总数等于当日的复习加新学，颜色分层还是有的。
/// 落到代码上三条：
///   · 只数**词**：一个词一天答 5 次也只算 1 个（不是作答条数）；
///   · 取**第一次**作答的评分定档（SQL 里 `MIN(id)`，见 `AppDb.dailyWordRatingCounts`）；
///   · 四档之和 == 当天过过的去重词数 == 「今日学习」卡的 复习 + 新学
///     （`stats_screen_test` 钉着这条勾稽）。
///
/// 2026-11-02：补上第四条「轻松」——`rating 3` 曾被 SQL 折叠丢掉，
/// 这条线一整条是空的，总数也比「今日学习」少。
///
/// 周/月档 = 各天的数字**相加**（不是「窗口内再取一次」）：一天一天地数才和日档
/// 对得上，用户切档时看到的就是同一条线放大缩小。代价是同一个词在一周里被记了
/// 两天会算两次——说明文字里写了「各天之和」。
///
/// 「一周」= 最近 7 天为一段往前推 30 段（滚动窗口；按自然周对齐的话，
/// 今天所在的半周会显得莫名其妙地矮）；「一月」按自然月。
class _TrendChart extends StatelessWidget {
  /// 按天统计的「当天第一次作答」的词数 × 四档，键是 `yyyy-MM-dd`。
  final Map<String, ({int easy, int know, int fuzzy, int forget})> daily;
  final int mode; // 0 = 30 天 ｜ 1 = 30 周 ｜ 2 = 30 月
  const _TrendChart({required this.daily, required this.mode, this.onTapDay});

  /// 点某根柱子 → 打开那一天（周/月档取窗口**最后一天**）的详情。
  final void Function(DateTime day)? onTapDay;

  static const _zero = (easy: 0, know: 0, fuzzy: 0, forget: 0);

  static String _key(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 生成 30 根柱子（标签 + 四档词数）。
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
        // 自然月：月份往前推 i 个（`DateTime` 自己处理跨年）
        final m = DateTime(now.year, now.month - i, 1);
        final next = DateTime(m.year, m.month + 1, 1);
        final lastDay = next.subtract(const Duration(days: 1));
        // 当月取「今天」（未来还没过），历史月取月末
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
    // 30 根柱子每根都标会挤成一团：每 5 根标一个（30 个月时每 6 个）
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
            // 0 值不画点：30 个点全挤在底线上会糊成一条粗线。
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
                // 点线 → 打开那一天（周/月取窗口最后一天）。与旧柱图同一手势。
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
                  // 五条线共用同一个 tooltip：只让总量那条（第一个）出字。
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
                // 总量只做浅灰背景，不抢四档的读数；四档各一条细线。
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

  /// 图例：四档各自在当前窗口内的合计。
  ///
  /// 样式照词库页「已选单词」卡的图例（圆点 9px + `名 数`）——两个图例
  /// 长得不一样又要用户重新学一遍。数字也放进来，不只给颜色块：
  /// 「区分」如果只能靠比对颜色深浅，看图还是得猜。
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

  /// Y 轴整数刻度（浮点抖动靠 round 差值挡掉）。
  static Widget _intTick(BuildContext context, double v, TitleMeta meta) {
    final i = v.round();
    if ((v - i).abs() > 1e-9) return const SizedBox.shrink();
    return Text('$i', style: TextStyle(fontSize: 10, color: context.k.nFaint2));
  }
}

/// 迷你趋势线（sparkline）：一条填充面积 + 折线，**无坐标轴、无网格**。
///
/// 摘要头「近 30 天学习时长」用。手绘而不用 fl_chart：这一条只有 34px 高、
/// 没有刻度没有交互，`LineChart` 在这点空间里光内边距就吃掉一半，
/// 而且它的 `LineChartData` 每帧都要重新算 axis，30 个点的收益为负。
///
/// ⚠️ **不要用 `InkWell` / 任何带 ripple 的组件**：测试环境缺
/// `shaders/ink_sparkle.frag`，一点就抛 `Asset not found`（项目铁律）。
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
    // 全 0（一条记录都没有）：画一条贴底的直线，不留白——高度才不会跳
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
    // 顶部留 4px，免得最高点贴着上边被切掉
    final usable = size.height - 4;
    Offset at(int i) => Offset(
          n <= 1 ? size.width / 2 : dx * i,
          size.height - 1 - (series[i] / maxV) * usable,
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    // 填充：折线 + 底边闭合
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

/// 趋势图的**回忆率**模式：每个窗口一个「第一次作答就是记得或轻松」的占比。
///
/// 用户 2026-10-09：「只有量没有率」。柱高只说明过了多少词，看不出过得好不好。
///
/// ## 口径（必须与量模式同源，否则两条线互相打架）
///   · 分子 = 该窗口内**第一次作答就是「记得」或「轻松」**的词数之和；
///   · 分母 = 该窗口内**过过的词数**（四档之和）；
///   · 都取自 `_daily`（`dailyWordRatingCounts` 的当天第一次作答折叠），
///     所以「率」与「量」是同一批数据的两个视角，不是两套统计。
///
/// 2026-11-02：`rating 3`（轻松）之前被 SQL 折叠漏掉，分子分母同时少一块；
/// 现在补回来，且「轻松」比「记得」更牢，当然算记得。
///
/// 缺点也写在这里：这个率**偏低**于 [AppState] 里的「总体回忆率」——
/// 后者是（轻松+记得+模糊）/ 全部作答，把「模糊」也算成记得；这里按词算、
/// 模糊不算记得。界面上的说明文字已经写明，别为了「看着好看」偷改分子。
///
/// 分母为 0 的窗口**不画点**（`FlSpot` 会画成 0%，那是最难看的一种错）——
/// 用 `nullY` 断开折线，而不是补 0。
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
