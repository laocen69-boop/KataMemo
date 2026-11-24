library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart';
import '../version.dart';
import '../ai_chat.dart' show aiVendorNames;
import '../widgets/ai_widgets.dart' show openGeneralAi;
import '../widgets/day_stats_sheet.dart';
import '../widgets/first_notice.dart';
import '../widgets/postpone_sheet.dart';
import '../widgets/speak_button.dart' show kSpeakGreen;
import 'ai_settings_screen.dart' show openAiSettings;
import 'favorites_screen.dart';
import 'grammar/grammar_hub_screen.dart';
import 'home_shell.dart' show HomeTabs;
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'text_reader_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.focusTick});

  final ValueNotifier<int>? focusTick;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _streak = 0;

  int _bestStreak = 0;
  int _todayCount = 0;

  late int _viewYear;
  late int _viewMonth;
  bool get _atCurrentMonth =>
      _viewYear == DateTime.now().year && _viewMonth == DateTime.now().month;

  Map<String, MonthDay> _monthData = {};

  int _studySeconds = 0;

  int _inMemory = 0;
  int _startedWords = 0;
  int _mastered = 0;

  int _wordLists = 0;
  int _wordListCards = 0;

  ({String value, String label}) get _studyTime {
    if (_studySeconds >= 3600) {
      return (
        value: (_studySeconds / 3600).toStringAsFixed(1),
        label: '学习总时长（小时）',
      );
    }
    return (value: '${(_studySeconds / 60).round()}', label: '学习总时长（分）');
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
    _load();
    widget.focusTick?.addListener(_load);
  }

  @override
  void dispose() {
    widget.focusTick?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final streak = await app.db.streakDays();
    final best = await app.db.bestStreakDays();
    final today = await app.db.todayLogCount();
    final studySeconds = await app.db.totalStudySeconds();
    final todaySigned = await app.db.isSignedDay(DateTime.now());
    final month = await app.db.monthView(_viewYear, _viewMonth);
    final overall = await app.db.bookProgress(null);
    final lists = await app.db.listWordLists();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _bestStreak = best;
      _todayCount = today;
      _studySeconds = studySeconds;
      _todaySigned = todaySigned;
      _monthData = month;
      _inMemory = overall.total;
      _startedWords = overall.started;
      _mastered = overall.bands.mastered;
      _wordLists = lists.length;
      _wordListCards = [for (final l in lists) l.$3].fold(0, (a, b) => a + b);
    });
  }

  bool _todaySigned = false;

  ({int signed, int words, int answers}) get _monthSummary {
    var signed = 0;
    var words = 0;
    var answers = 0;
    _monthData.forEach((_, day) {
      if (day.signed) signed++;
      words += day.words;
      answers += day.answers;
    });
    return (signed: signed, words: words, answers: answers);
  }

  Future<void> _shiftMonth(int delta) async {
    final next = DateTime(_viewYear, _viewMonth + delta, 1);
    final now = DateTime.now();

    if (next.isAfter(DateTime(now.year, now.month + 1, 1))) return;
    setState(() {
      _viewYear = next.year;
      _viewMonth = next.month;
    });
    final app = context.read<AppState>();
    final month = await app.db.monthView(_viewYear, _viewMonth);
    if (!mounted) return;
    setState(() => _monthData = month);
  }

  Future<void> _showDayStats(DateTime day) => showDayStatsSheet(context, day);

  @override
  Widget build(BuildContext context) {

    final aiReady = context.select<AppState, bool>((a) => a.aiReady);
    final aiName = context.select<AppState, String>((a) => a.aiProvider.name);
    return Scaffold(
      backgroundColor: context.k.nBg,
      appBar: AppBar(
        title: const Text('我的'),
        titleTextStyle: mainAppBarTitleStyle(context),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [

          _ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_streak',
                            style: TextStyle(
                                fontSize: 40,
                                height: 1.0,
                                fontWeight: FontWeight.w800,
                                color: context.k.deep,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(height: 5),
                        Text('天 · 历史最长 $_bestStreak 天',
                            style: TextStyle(
                                fontSize: 11.5, color: context.k.nT3)),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [

                        if (_todaySigned || _todayCount > 0)
                          Chip(
                            label: Text(_todaySigned ? '今日已签到' : '任务进行中',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            backgroundColor:
                                _todaySigned ? kSpeakGreen : context.k.nFaint2,
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '上一月',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Text('$_viewYear 年 $_viewMonth 月',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '下一月',
                      icon: const Icon(Icons.chevron_right),

                      onPressed: _atCurrentMonth ? null : () => _shiftMonth(1),
                    ),
                  ],
                ),
                _MonthCalendar(
                  year: _viewYear,
                  month: _viewMonth,
                  data: _monthData,
                  onDayTap: _showDayStats,
                ),
                const SizedBox(height: 8),

                Text(
                    '实心圆 = 当天完成全部学习任务（自动签到）；浅色 = 有学习但未完成。'
                    '点任意一天看那天的学习数据',
                    style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ProfileCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('$_viewMonth 月小结',
                      style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _MonthSummaryCell(
                        value: '${_monthSummary.signed}', label: '签到（天）'),
                    const _SummaryDivider(),
                    _MonthSummaryCell(
                        value: '${_monthSummary.words}', label: '学习（词）'),
                    const _SummaryDivider(),
                    _MonthSummaryCell(
                        value: '${_monthSummary.answers}', label: '作答（次）'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('学习概况',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('截至今天',
                        style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _ProfileStat(value: '$_inMemory', label: '在学（词）'),
                    _ProfileStat(value: '$_startedWords', label: '已学（词）'),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _ProfileStat(value: '$_mastered', label: '已掌握（词）'),

                    _ProfileStat(
                        value: _studyTime.value, label: _studyTime.label),
                  ],
                ),
                const SizedBox(height: 14),

                Text(
                    '在学 = 已加入记忆；已学 = 答过至少一次；'
                    '已掌握 = 记忆稳定性 ≥ 180 天。\n'
                    '时长按作答间隔累计，停顿超 1 分钟不计（估算）',
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: context.k.nT1)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ProfileCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2, left: 2),
                  child: Text('学习工具',
                      style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
                ),
                _ProfileTile(
                  icon: Icons.star_border,
                  title: '我的收藏',
                  subtitle: _wordLists > 0
                      ? '$_wordLists 个词单 · $_wordListCards 张卡'
                      : '在单词详情页点星标收藏',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                ),
                _ProfileTile(
                  icon: Icons.account_tree_outlined,
                  title: '语法',
                  subtitle: '词缀 / 易混辨析 / 重叠、否定等跨词类专题',

                  onTap: () => HomeTabs.maybeOf(context)?.select(2),
                ),

                _ProfileTile(
                  key: const ValueKey('profile-writing'),
                  icon: Icons.edit_note,
                  title: '写作',
                  subtitle: '书信、通知、简历等常用文体 · 常用句型',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GrammarHubScreen(writing: true)),
                  ),
                ),
                _ProfileTile(
                  icon: Icons.auto_stories_outlined,
                  title: '文章生词高亮阅读',
                  subtitle: '粘贴印尼语新闻/课文，标出生词并一键加入记忆',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TextReaderScreen()),
                  ),
                ),
                _ProfileTile(
                  icon: Icons.document_scanner_outlined,
                  title: '拍照 / 粘贴抓词',
                  subtitle: '拍书本或粘贴段落，自动匹配词库加词',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  ),
                ),
                _ProfileTile(
                  icon: Icons.event_repeat_rounded,
                  title: '断签温和顺延',
                  subtitle: '逾期积压较多时，按稳定度温和分摊复习',
                  onTap: () async {
                    final app = context.read<AppState>();
                    final overdue = await app.db.overdueReviewCount();
                    if (!context.mounted) return;
                    final moved = await showPostponeSheet(
                      context,
                      app,
                      overdueCount: overdue,
                    );
                    if (moved != null && moved > 0 && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已将 $moved 张逾期复习卡温和顺延')),
                      );
                    }
                  },
                ),

                if (kAiChat)
                  _ProfileTile(
                    key: const ValueKey('profile-ai'),
                    icon: Icons.auto_awesome,
                    title: 'AI 助手',
                    subtitle: aiReady
                        ? '$aiName · 翻译、批改、情景对话、考今天的词'
                        : '连接 ${aiVendorNames(max: 3, sep: ' / ')}，问词、批改、陪练',
                    onTap: () => aiReady
                        ? openGeneralAi(context)
                        : openAiSettings(context),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _ProfileCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: _ProfileTile(
              icon: Icons.info_outline,
              iconTint: context.k.nT1,
              tileBg: context.k.nFaint2.withValues(alpha: 0.10),
              title: '关于',
              subtitle: '$kAppName v$kAppVersion ($kBuildNumber) · '
                  'FSRS-6 记忆算法 · 音标参考 KBBI',
              onTap: () => _showAbout(context),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('数据来源：本机学习记录 · 音标参考 KBBI（本版不含 KBBI 释义）',
                style: TextStyle(fontSize: 11.5, color: context.k.nFaint)),
          ),
        ],
      ),
    );
  }
}

void _showAbout(BuildContext context) {

  final g = context.read<AppState>().grammar;
  final sourceNote = g.ready && g.doc.about.isNotEmpty
      ? g.doc.about

      : '语法与写作部分的讲解由本应用整理编写，例句经过逐条核对；'
          '拼写规则依据印尼官方正字法（EYD），释义参考 KBBI。';
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('关于 $kAppName${kIsWeb ? '（网页版）' : ''}'),
      content: SingleChildScrollView(
        child: Column(
          key: const ValueKey('about-note'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'v$kAppVersion · build $kBuildNumber'
                '${kIsWeb ? ' · Web / PWA' : ''}',
                style: TextStyle(fontSize: 13, color: ctx.k.t2)),
            const SizedBox(height: 10),
            const Text('记忆算法：FSRS-6。音标参考 KBBI（印尼语大词典）；本版不含 KBBI 释义。',
                style: TextStyle(fontSize: 13.5, height: 1.6)),
            const SizedBox(height: 10),
            Text(sourceNote, style: const TextStyle(fontSize: 13.5, height: 1.6)),
          ],
        ),
      ),
      actions: [
        TextButton(
            key: const ValueKey('about-notice'),
            onPressed: () {
              Navigator.of(ctx).pop();
              showFirstNotice(context);
            },
            child: const Text('使用须知')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: const Text('知道了')),
      ],
    ),
  );
}

class _ProfileCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _ProfileCard({required this.child, this.padding});

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

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [

          Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: context.k.nT1)),
        ],
      ),
    );
  }
}

class _MonthSummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _MonthSummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 30,
      color: Colors.black.withValues(alpha: 0.08),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  final Color? iconTint;
  final Color? tileBg;
  const _ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.iconTint,
    this.tileBg,
  });

  @override
  Widget build(BuildContext context) {
    final tint = iconTint ?? context.k.deep;
    final bg = tileBg ?? context.k.brand.withValues(alpha: 0.12);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: context.k.nFaint),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final int year;
  final int month;
  final Map<String, MonthDay> data;

  final void Function(DateTime day)? onDayTap;

  const _MonthCalendar({
    required this.year,
    required this.month,
    required this.data,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = first.weekday - 1;
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: [
            for (final w in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leading; i++) const SizedBox(),
            for (var d = 1; d <= daysInMonth; d++) ...[
              Builder(builder: (_) {
                final key =
                    '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
                final day = data[key] ?? const MonthDay(words: 0, answers: 0);
                final signed = day.signed;
                final studied = day.words > 0;
                final isToday = today.year == year &&
                    today.month == month &&
                    today.day == d;

                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDayTap == null
                        ? null
                        : () => onDayTap!(DateTime(year, month, d)),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: signed
                            ? kSpeakGreen
                            : studied
                                ? kSpeakGreen.withValues(alpha: 0.18)
                                : (isToday
                                    ? kSpeakGreen.withValues(alpha: 0.12)
                                    : Colors.transparent),
                        border: !signed && isToday
                            ? Border.all(
                                color: kSpeakGreen, width: studied ? 1.0 : 1.5)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$d',
                        style: TextStyle(
                          fontSize: 13,
                          color: signed
                              ? Colors.white
                              : (studied || isToday
                                  ? kSpeakGreen
                                  : context.k.text),
                          fontWeight: signed || studied || isToday
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ],
    );
  }
}
