library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart';
import '../fsrs.dart';
import '../models.dart' show MemoryBands, kEmptyBands;
import '../ratings.dart';
import '../widgets/day_stats_sheet.dart';
import '../widgets/memory_ring.dart'
    show kMemorySegmentsOf, MemorySegmentBar, memoryBandCounts;
import '../widgets/speak_button.dart' show kSpeakGreen;

part 'stats_charts.dart';

const TextStyle kStatTitle =
    TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
const TextStyle kStatBig = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()]);
const TextStyle kStatBody = TextStyle(fontSize: 13);
const double kStatCaptionSize = 11.5;

TextStyle statCaption(BuildContext context) => TextStyle(
    fontSize: kStatCaptionSize, color: context.k.nFaint2, height: 1.4);

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.k.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.black.withValues(alpha: 0.06), width: 0.5),
      ),
      child: child,
    );
  }
}

double statStep(num max, List<double> candidates) {
  for (final s in candidates) {
    if (max / s <= 4) return s;
  }
  return candidates.last;
}

double statIntStep(num max) =>
    statStep(max, [1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000, 2000, 5000]);

double statPctStep(num max) => statStep(max, [0.05, 0.1, 0.2, 0.25, 0.5, 1.0]);

bool statBinVisible(int reviews) => reviews >= statBinMinReviews;
bool statBinSolid(int reviews) => reviews >= statBinSolidReviews;

const int statBinMinReviews = 10;

const int statBinSolidReviews = 30;

double statAxisMax(num max, double step) {
  if (max <= 0) return step;
  return step * (max / step).ceil();
}

String statDayLabel(DateTime d) => '${d.month}/${d.day}';

String _trendHint(int mode) => switch (mode) {
      0 => '每个点 = 当天过过的词数：一个词一天只算 1 次，按它「第一次作答」'
          '时的评分分四条折线（轻松／记得／模糊／困难，见下方图例），浅灰面积是总量',
      1 => '每个点 = 这 7 天的「当天过过词数」之和（今天往前滚动取 30 段），'
          '四条折线分别对应四档，浅灰面积是总量',
      _ => '每个点 = 该自然月里各天「过过词数」之和，四条折线分别对应四档，浅灰面积是总量',
    };

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.focusTick});

  final ValueNotifier<int>? focusTick;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen>
    with TickerProviderStateMixin {

  late final TabController _tab = TabController(length: 4, vsync: this);

  Map<String, int> _today = {};
  int _streak = 0;
  List<ForgetBin> _forgetCurve = [];

  int get _forgetReviews => _forgetCurve.fold(0, (a, b) => a + b.reviews);

  Map<String, ({int easy, int know, int fuzzy, int forget})> _daily = {};

  int _trendMode = 0;

  int _trendUnit = 0;

  double? _medianS;

  double? _recallRate;

  Map<String, int> _dailySeconds = {};

  MemoryBands _bands = kEmptyBands;
  int _memTotal = 0;

  List<({String topic, int total, int started, MemoryBands bands})> _topics =
      [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.focusTick?.addListener(_load);
  }

  @override
  void dispose() {
    widget.focusTick?.removeListener(_load);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final today = await app.db.todayStats();
    final streak = await app.db.streakDays();
    final recall = await app.db.overallRecallRate();
    final medianS = await app.db.medianStability();
    final forgetCurve = await app.db.forgetRateByInterval();

    final daily = await app.db.dailyWordRatingCounts(days: 950);

    final seconds = await app.db.dailyStudySeconds(days: 90);
    final progress = await app.db.bookProgress(null);
    final topics = await app.db.topicProgress(top: 8);
    if (!mounted) return;
    setState(() {
      _today = today;
      _streak = streak;
      _recallRate = recall;
      _medianS = medianS;
      _forgetCurve = forgetCurve;
      _daily = daily;
      _dailySeconds = seconds;
      _bands = progress.bands;
      _memTotal = progress.total;
      _topics = topics;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.k.nBg,
      appBar: AppBar(
        title: const Text('统计'),
        titleTextStyle: mainAppBarTitleStyle(context),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tab,

          labelColor: context.k.deep,
          unselectedLabelColor: context.k.nT2,
          indicatorColor: kSpeakGreen,

          dividerColor: context.k.line,
          dividerHeight: 0.5,
          labelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: '总览'),
            Tab(text: '主题'),
            Tab(text: '趋势'),
            Tab(text: '模型'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [

                _page([
                  _summaryHeader(),
                  const SizedBox(height: 12),
                  _sectionLabel('掌握情况'),
                  const SizedBox(height: 8),
                  _masteryCard(),
                  const SizedBox(height: 20),
                  Center(
                    child: Text('数据来源：本机学习记录 · 音标参考 KBBI（本版不含 KBBI 释义）',
                        style: TextStyle(
                            fontSize: kStatCaptionSize,
                            color: context.k.nFaint2)),
                  ),
                ]),

                _page([
                  _topicMapCard(),
                  const SizedBox(height: 20),
                  Center(
                    child: Text('数据来源：本机学习记录 · 音标参考 KBBI（本版不含 KBBI 释义）',
                        style: TextStyle(
                            fontSize: kStatCaptionSize,
                            color: context.k.nFaint2)),
                  ),
                ]),

                _trendPage(context),

                _page([
                  _memoryCurveCard(),
                  const SizedBox(height: 12),
                  _forgetCurveCard(),
                ]),
              ],
            ),
    );
  }

  Widget _page(List<Widget> children) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: children,
        ),
      );

  Widget _trendPage(BuildContext context) {
    const source = '数据来源：本机学习记录 · 音标参考 KBBI（本版不含 KBBI 释义）';
    return LayoutBuilder(
      builder: (context, box) {
        final h = math.max(360.0, box.maxHeight - 74);
        return RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            child: Column(
              children: [
                SizedBox(height: h, child: _trendCard()),
                const SizedBox(height: 20),
                Center(
                  child: Text(source,
                      style: TextStyle(
                          fontSize: kStatCaptionSize,
                          color: context.k.nFaint2)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.k.g700)),
      );

  String _headline() {
    final todayWords = (_today['new'] ?? 0) + (_today['review'] ?? 0);
    if (todayWords == 0) {
      return _streak > 0 ? '今天还没开始，连续 $_streak 天的记录别断在这儿' : '今天还没开始，先过几个词吧';
    }
    if (_streak >= 2) return '今天已过 $todayWords 个词，连续 $_streak 天';
    return '今天已过 $todayWords 个词';
  }

  Widget _summaryHeader() {
    final newW = _today['new'] ?? 0;
    final revW = _today['review'] ?? 0;
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 17, color: kSpeakGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_headline(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _QuadCell(
                value: '$newW',
                label: '今日新学',
                color: kSpeakGreen,
              ),
              _QuadCell(
                value: '$revW',
                label: '今日复习',
                color: context.k.q2,
              ),
              _QuadCell(
                value: '$_streak',
                label: '连续天数',
                color: context.k.q3,
              ),
              _QuadCell(
                value: _recallRate == null
                    ? '—'
                    : '${(_recallRate! * 100).round()}%',
                label: '总体回忆率',
                color: context.k.q4,
              ),
            ],
          ),
          const SizedBox(height: 12),

          Divider(height: 1, thickness: 0.5, color: context.k.line),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('近 30 天学习时长',
                  style: TextStyle(fontSize: 12, color: context.k.nT2)),
              const Spacer(),
              Text(_recentSecondsLabel(),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: _Sparkline(series: _last30Seconds()),
          ),
        ],
      ),
    );
  }

  String _recentSecondsLabel() {
    final list = _last30Seconds();
    final total = list.fold<int>(0, (a, b) => a + b);
    if (total < 60) return '共 $total 秒';
    if (total < 3600) return '共 ${(total / 60).round()} 分钟';
    return '共 ${(total / 3600).toStringAsFixed(1)} 小时';
  }

  List<int> _last30Seconds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return [
      for (var i = 29; i >= 0; i--)
        _dailySeconds[key(today.subtract(Duration(days: i)))] ?? 0
    ];
  }

  Widget _masteryCard() {
    final counts = memoryBandCounts(_bands);

    final segs = kMemorySegmentsOf(context);
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('记忆分布', style: kStatTitle),
              const Spacer(),

              Text('在记忆 $_memTotal 词',
                  style: TextStyle(fontSize: 12, color: context.k.nT2)),
            ],
          ),
          const SizedBox(height: 12),
          MemorySegmentBar(counts: counts, height: 10, radius: 5),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (var i = 0; i < segs.length; i++)
                _LegendDot(
                  color: segs[i].color,
                  label: segs[i].label,
                  value: counts[i],
                  total: _memTotal,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topicMapCard() {
    if (_topics.isEmpty) {
      return StatCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主题地图', style: kStatTitle),
            const SizedBox(height: 10),
            Text('还没有加入记忆的词，先选几个词库开始学。', style: statCaption(context)),
          ],
        ),
      );
    }
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('主题地图', style: kStatTitle),
          const SizedBox(height: 4),
          Text('每个主题里「记得住」的词占该主题的比例（条越长越牢）', style: statCaption(context)),
          const SizedBox(height: 12),
          for (final t in _topics) ...[
            _TopicBar(topic: t.topic, total: t.total, bands: t.bands),
            const SizedBox(height: 9),
          ],
          Text(
            '一个词可以同时属于多个主题，各主题的词数加起来会大于总词数，'
            '所以这里只能横着比，不能加起来算。',
            style: statCaption(context),
          ),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final chart = _trendUnit == 0
        ? _TrendChart(daily: _daily, mode: _trendMode, onTapDay: _openDay)
        : _RecallRateChart(daily: _daily, mode: _trendMode);
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text('学习趋势', style: kStatTitle),
              _TrendModeSwitch(
                mode: _trendMode,
                onChanged: (m) => setState(() => _trendMode = m),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _UnitSwitch(
            unit: _trendUnit,
            onChanged: (u) => setState(() => _trendUnit = u),
          ),
          const SizedBox(height: 8),
          Text(
            _trendUnit == 0
                ? _trendHint(_trendMode)
                : '每个点 = 该窗口内「第一次作答就是记得或轻松」的词占全部过词的比例。'
                    '分子分母都取自同一天的第一次作答（与量模式同一份数据）。',
            style: statCaption(context),
          ),
          const SizedBox(height: 12),
          Expanded(child: chart),
        ],
      ),
    );
  }

  void _openDay(DateTime day) => showDayStatsSheet(context, day);

  Widget _memoryCurveCard() {
    final app = context.read<AppState>();
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('记忆曲线', style: kStatTitle),
              const Spacer(),
              Text('目标保留率 ${(app.retention * 100).round()}%',
                  style: TextStyle(fontSize: 12, color: context.k.nT2)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _medianS == null
                ? '还没有足够的复习数据。曲线按记忆稳定性 S 绘制，'
                    'S 是你的已学词的中位稳定性，学一段时间后这里会变成你自己的曲线。'
                : '曲线 = 你的已学词在「距上次复习 N 天」时的预测回忆率'
                    '（中位稳定性 S = ${_medianS!.toStringAsFixed(1)} 天）。'
                    '实际回忆率 =（轻松+记得+模糊）/ 全部作答。',
            style: statCaption(context),
          ),
          const SizedBox(height: 12),
          SizedBox(
              height: 170,
              child: _MemoryCurveChart(
                targetRetention: app.retention,
                actualRecall: _recallRate,
                medianS: _medianS,
              )),
        ],
      ),
    );
  }

  Widget _forgetCurveCard() {
    return StatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('困难率（按复习间隔）', style: kStatTitle),
              const Spacer(),
              Text('共 $_forgetReviews 次复习',
                  style: TextStyle(fontSize: 12, color: context.k.nT2)),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            '每根柱子 = 距上次复习的天数落在该档时，复习答「困难」'
            '的比例。\n'
            '分母是该档的**复习次数**：一个词一天只算一次、'
            '取当天第一次作答，第一次出现的那天算新学不算复习。\n'
            '同一档里忘得早的词不会被漏掉——'
            '这就是你自己实测出来的遗忘曲线。',
            style: statCaption(context),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 172, child: _ForgetCurveChart(data: _forgetCurve)),
        ],
      ),
    );
  }
}

class _QuadCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _QuadCell(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 3,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(value, style: kStatBig),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: kStatCaptionSize, color: context.k.nT2)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  final int total;
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0 : (value / total * 100).round();
    final dim = value == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: dim ? color.withValues(alpha: 0.35) : color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text('$label $value',
            style: TextStyle(
                fontSize: 12.5,
                color: dim ? context.k.g400 : context.k.g800,
                fontWeight: dim ? FontWeight.w400 : FontWeight.w600)),
        if (!dim && total > 0) ...[
          const SizedBox(width: 3),
          Text('$pct%',
              style: TextStyle(fontSize: 11.5, color: context.k.nFaint2)),
        ],
      ],
    );
  }
}

class _TopicBar extends StatelessWidget {
  final String topic;
  final int total;
  final MemoryBands bands;
  const _TopicBar(
      {required this.topic, required this.total, required this.bands});

  @override
  Widget build(BuildContext context) {
    final solid = bands.mastered + bands.familiar;
    final frac = total <= 0 ? 0.0 : (solid / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
            Text('$solid / $total',
                style: TextStyle(
                    fontSize: 11.5,
                    color: context.k.nT2,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 4),

        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            color: context.k.nFaint2.withValues(alpha: 0.12),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac,
              child: Container(color: kSpeakGreen),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnitSwitch extends StatelessWidget {
  final int unit;
  final void Function(int) onChanged;
  const _UnitSwitch({required this.unit, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = ['词数', '回忆率'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: context.k.nFaint2.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: i == unit ? context.k.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                i == unit ? FontWeight.w700 : FontWeight.w400,
                            color: i == unit
                                ? Colors.black87
                                : context.k.nT2)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
