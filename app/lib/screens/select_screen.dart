library;

import 'dart:async';
import 'dart:math' as m;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart';
import '../models.dart';
import '../widgets/memory_ring.dart';
import '../widgets/quota_dialog.dart';
import '../widgets/speak_button.dart';
import '../widgets/swipe_reveal_row.dart';
import '../widgets/target_actions.dart';
import '../widgets/word_list_actions.dart';
import '../widgets/word_search.dart';
import '../widgets/word_tile.dart';
import 'scan_screen.dart';
import 'search_screen.dart';
import 'study_screen.dart' show studyStopOf, StudyStop;
import 'my_words_screen.dart';
import 'today_words_screen.dart';
import 'word_detail_screen.dart';
import 'word_pick_screen.dart';

part 'select_book_children.dart';
part 'select_word_list_detail.dart';
part 'select_book_row.dart';
part 'select_memory_band.dart';
part 'select_word_list.dart';
part 'select_paging.dart';

typedef BookProgress = ({
  int all,
  int total,
  int started,
  int due,
  MemoryBands bands,
});

const BookProgress kEmptyTarget = (
  all: 0,
  total: 0,
  started: 0,
  due: 0,
  bands: kEmptyBands,
);

Future<Map<String, BookProgress>> loadBookProgress(
    AppState app, List<BookNode> nodes) async {
  final items = [
    for (final b in nodes)
      if (b.clickable) (id: b.id, filter: b.filter),
  ];
  return app.db.bookProgressBatch(items);
}

List<BoxShadow> kCardShadow(BuildContext context) => context.k.shadowOn
    ? const [
        BoxShadow(
            color: Color(0x14153C2D), blurRadius: 3, offset: Offset(0, 1)),
      ]
    : const [
        BoxShadow(
            color: Color(0x73000000), blurRadius: 2, offset: Offset(0, 1)),
      ];

Widget segmentLabel(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 5),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: context.k.nT2)),
    );

List<MapEntry<String, List<BookNode>>> groupBySegment(List<BookNode> nodes) {
  final order = <String>[];
  for (final n in nodes) {
    if (!order.contains(n.group)) order.add(n.group);
  }
  final out = <MapEntry<String, List<BookNode>>>[];
  for (final g in order) {
    final items = nodes.where((b) => b.group == g).toList();
    if (items.isNotEmpty) out.add(MapEntry(g, items));
  }
  return out;
}

bool isBookFinished(BookProgress? p) {
  if (p == null || p.all <= 0) return false;
  return p.total >= p.all && p.bands.newSel == 0;
}

bool wordEnrolled(String id, bool enabled,
        {Set<String> dropped = const {},
        required Set<String> planned,
        required SrsLevelMap levels}) =>
    !dropped.contains(id) &&
    enabled &&
    (planned.contains(id) || levels.containsKey(id));

List<int> todayProgressFlex({
  required int reviewDone,
  required int newDone,
  required int total,
}) {
  if (total <= 0) return const [0, 0, 1000];
  final r = (reviewDone / total).clamp(0.0, 1.0);
  final n = (newDone / total).clamp(0.0, 1.0);
  final rf = (r * 1000).round();
  final nf = (n * 1000).round();
  final done = (rf + nf).clamp(0, 1000);
  return [rf, nf, 1000 - done];
}

String pctLabel(int total, int all) {
  if (all <= 0) return '0%';
  final part = total.clamp(0, all);
  if (part == 0) return '0%';

  final tenth = (part / all * 1000).round() / 10;
  if (tenth <= 0) return '<0.1%';
  return tenth == tenth.roundToDouble()
      ? '${tenth.toStringAsFixed(0)}%'
      : '${tenth.toStringAsFixed(1)}%';
}

class SelectScreen extends StatefulWidget {

  final ValueNotifier<int>? focusTick;

  final VoidCallback? onGoStudy;

  const SelectScreen({super.key, this.focusTick, this.onGoStudy});

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> {
  List<BookNode> _books = [];
  Map<String, BookProgress> _prog = {};

  final Map<String, Set<String>> _filters = {};

  int _filterCount() => _filters.values.fold(0, (a, s) => a + s.length);

  Map<String, dynamic>? filtersToQuery(Map<String, Set<String>> f) {
    final out = <String, dynamic>{};
    for (final e in f.entries) {
      if (e.value.isNotEmpty) out[e.key] = e.value.toList();
    }
    return out.isEmpty ? null : out;
  }

  bool _loading = true;

  TodayPlan _plan = todayPlanOf(
      quota: 0,
      newDone: 0,
      reviewDone: 0,
      newPending: 0,
      reviewPending: 0,
      reviewBacklog: 0,
      poolLeft: 0);

  ({int review, int newCount}) _firstComp = (review: 0, newCount: 0);
  int _firstCompFor = -1;

  BookProgress _target = kEmptyTarget;

  final ScrollController _homeScroll = ScrollController();

  String? _swipeOpenId;
  void _closeSwipe() {
    if (_swipeOpenId != null) setState(() => _swipeOpenId = null);
  }

  final ValueNotifier<bool> _stickyOn = ValueNotifier<bool>(false);

  final GlobalKey _syntheticCardKey = GlobalKey();
  final GlobalKey _homeListKey = GlobalKey();

  double _stickyThreshold = double.infinity;
  bool _measureQueued = false;

  void _scheduleStickyMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      _measureStickyThreshold();
    });
  }

  void _measureStickyThreshold() {
    if (!mounted) return;
    final card = _syntheticCardKey.currentContext?.findRenderObject();
    final list = _homeListKey.currentContext?.findRenderObject();
    if (card is! RenderBox || list is! RenderBox) return;
    if (!card.hasSize || !list.hasSize) return;
    final cardBottom = card.localToGlobal(Offset(0, card.size.height)).dy;
    final listTop = list.localToGlobal(Offset.zero).dy;
    final offset = _homeScroll.hasClients ? _homeScroll.offset : 0.0;
    _stickyThreshold = cardBottom - listTop + offset;
    _onHomeScroll();
  }

  void _onHomeScroll() {
    if (!_homeScroll.hasClients) return;
    final on = _homeScroll.offset > _stickyThreshold;
    if (on != _stickyOn.value) _stickyOn.value = on;
  }

  @override
  void initState() {
    super.initState();
    widget.focusTick?.addListener(_load);
    _homeScroll.addListener(_onHomeScroll);
    _load();
  }

  @override
  void dispose() {
    widget.focusTick?.removeListener(_load);
    _homeScroll.removeListener(_onHomeScroll);
    _homeScroll.dispose();
    _stickyOn.dispose();
    super.dispose();
  }

  bool _reloadQueued = false;
  void _syncQuota() {
    if (_loading || _reloadQueued || _plan.quota == _quota) return;
    _reloadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadQueued = false;
      if (mounted) _load();
    });
  }

  Future<void> _cancelTarget() async {
    final app = context.read<AppState>();

    final changed = await requestClearTarget(context, app);
    if (changed && mounted) await _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final books = await app.repo.loadBooks();
    final roots = books.where((b) => b.parent == null).toList();
    final prog = await loadBookProgress(app, roots);

    if (!mounted || app.db.isClosed) return;

    final quotaNow = app.dailyQuota;
    final TodayPlan plan;
    final ({int review, int newCount}) firstComp;
    final ({
      int all,
      int total,
      int started,
      int due,
      MemoryBands bands
    }) target;
    final bool hasEnrolled;
    try {
      plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);

      firstComp = plan.finished > quotaNow
          ? await app.db.todayFirstComposition(quotaNow)
          : (review: 0, newCount: 0);

      target = await app.db.bookProgress(app.bookFilter);
      hasEnrolled = await app.db.hasEnrolledCards();
    } on Exception {

      if (app.db.isClosed) return;
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      _books = books;
      _prog = prog;
      _plan = plan;
      _firstComp = firstComp;
      _firstCompFor = quotaNow;
      _target = target;
      _hasEnrolled = hasEnrolled;
      _loading = false;
    });
  }

  bool _hasEnrolled = true;

  String get _noTaskLabel =>
      _plan.finished > 0 ? '今日已完成' : (_hasEnrolled ? '今天没有任务' : '还没选词');

  String? get _bookId => context.select<AppState, String?>((a) => a.book?.id);
  int get _quota => context.select<AppState, int>((a) => a.dailyQuota);

  String get _studyMode => context.select<AppState, String>((a) => a.studyMode);

  bool get _onboardSeen => context.select<AppState, bool>((a) => a.onboardSeen);
  bool get _swipeTipOff =>
      context.select<AppState, bool>((a) => a.swipeTipDismissed);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    _syncQuota();

    _scheduleStickyMeasure();
    return Scaffold(

      backgroundColor: context.k.bg,
      appBar: AppBar(

        leading: IconButton(
          icon: Icon(Icons.photo_camera_outlined,
              size: 22, color: context.k.t2),
          tooltip: '拍照抓词',

          onPressed: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ScanScreen()));
            if (mounted) await _load();
          },
        ),
        title: const Text('词库'),
        titleTextStyle: mainAppBarTitleStyle(context),
        actions: [

          TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const MyScreen())),
            child: Text('自建卡片',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: context.k.deep)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                Expanded(
                  child: Stack(
                    children: [
                      RefreshIndicator(
                        backgroundColor: context.k.surface,
                        onRefresh: _load,
                        child: _bookList(app),
                      ),

                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _stickyOn,
                          builder: (_, on, __) =>
                              on ? _stickyBar(app) : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _searchRow({bool padded = true}) => Padding(
        padding: padded
            ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
            : const EdgeInsets.only(top: 8, bottom: 8),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: context.k.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: kCardShadow(context),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SearchScreen())),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 8),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: context.k.t3),
                        const SizedBox(width: 10),
                        Text('搜单词 / 词本',
                            style:
                                TextStyle(fontSize: 15, color: context.k.t3)),
                      ],
                    ),
                  ),
                ),
              ),
              _filterButton(),
            ],
          ),
        ),
      );

  Widget _filterButton() {
    final n = _filterCount();
    final on = n > 0;
    return GestureDetector(
      onTap: _openFilterSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? context.k.catTint : context.k.alt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(on ? '筛选 $n' : '筛选',
            style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? context.k.catDeep : context.k.t2)),
      ),
    );
  }

  Widget _filterChip(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? context.k.catTint : null,
          border: Border.all(
            color: on ? context.k.catMid : context.k.g300,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: on ? context.k.catDeep : context.k.g700)),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final app = context.read<AppState>();
    final draft = <String, Set<String>>{
      for (final e in _filters.entries) e.key: {...e.value},
    };
    var hits = await app.db.countByFilter(filtersToQuery(draft));
    if (!mounted) return;

    final topics = [
      for (final b in _books)
        if (b.parent == 'top') MapEntry(b.name, b.name),
    ];

    const tierItems = [
      MapEntry('t1', '最高频'),
      MapEntry('t2', '高频'),
      MapEntry('t3', '中高频'),
      MapEntry('t4', '中频'),
      MapEntry('t5', '常用'),
      MapEntry('t6', '较少用'),
      MapEntry('t7', '低频'),
    ];
    const classItems = [
      MapEntry('n', '名词'),
      MapEntry('v', '动词'),
      MapEntry('a', '形容词'),
      MapEntry('adv', '副词'),
      MapEntry('num', '数词'),
      MapEntry('pron', '代词'),
      MapEntry('prep', '介词'),
      MapEntry('conj', '连词'),
      MapEntry('interj', '感叹词'),
      MapEntry('part', '助词'),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.k.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) {
        Widget section(
            String title, String key, List<MapEntry<String, String>> items) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 7),
                child: Text(title,
                    style: TextStyle(fontSize: 11.5, color: context.k.nT2)),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final it in items)
                    _filterChip(
                      it.value,
                      draft[key]?.contains(it.key) ?? false,
                      () async {
                        final sel = draft.putIfAbsent(key, () => <String>{});
                        if (!sel.remove(it.key)) sel.add(it.key);
                        if (draft[key]!.isEmpty) draft.remove(key);

                        _safeSheetSet(() {});
                        final n =
                            await app.db.countByFilter(filtersToQuery(draft));
                        _safeSheetSet(() => hits = n);
                      },
                    ),
                ],
              ),
            ],
          );
        }

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            _sheetSet = setSheet;
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.78),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 30,
                          height: 3,
                          decoration: BoxDecoration(
                              color: context.k.g300,
                              borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      section('词频', 'tier', tierItems),
                      section('词性', 'wordClass', classItems),
                      if (topics.isNotEmpty)
                        section('主题（可多选）', 'topicsAny', topics),
                      const Divider(height: 20, thickness: 0.5),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$hits 词',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  _filterSummary(draft) ?? '未选条件（等于全部词汇）',
                                  style: TextStyle(
                                      fontSize: 11, color: context.k.nFaint2),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              draft.clear();
                              _safeSheetSet(() {});
                              final n = await app.db
                                  .countByFilter(filtersToQuery(draft));
                              _safeSheetSet(() => hits = n);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: context.k.g300, width: 0.5),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text('重置',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(width: 6),

                          GestureDetector(
                            onTap: () async {
                              final q = filtersToQuery(draft);
                              if (q == null) return;
                              final name = await _askWordListName(
                                  _filterSummary(draft) ?? '我的词单');
                              if (name == null || name.trim().isEmpty) return;

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);

                              final ws =
                                  await app.db.wordsByFilter(q, limit: 5000);
                              await app.db.saveWordList(
                                  name.trim(), [for (final w in ws) w.id]);
                              if (!mounted) return;

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                      duration: const Duration(seconds: 3),
                                      content: Text(hits > ws.length
                                          ? '已存为词单「${name.trim()}」（命中 $hits 词，'
                                              '词单最多存 5000，已按当前顺序取前 5000）'
                                          : '已存为词单「${name.trim()}」'
                                              '（同名词单会被覆盖）')));
                              await _load();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: context.k.g300, width: 0.5),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text('存为词单',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              final q = filtersToQuery(draft);

                              setState(() {
                                _filters
                                  ..clear()
                                  ..addEntries([
                                    for (final e in draft.entries)
                                      MapEntry(e.key, {...e.value}),
                                  ]);
                              });
                              Navigator.pop(ctx);
                              if (q == null) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WordListScreen(
                                    book: BookNode(
                                      id: 'filter',
                                      name: '筛选结果',
                                      count: hits,
                                      filter: q,
                                      desc: '组合筛选',
                                    ),
                                  ),
                                ),
                              );
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 9),
                              decoration: BoxDecoration(
                                  color: context.k.catMid,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text('查看这 $hits 词',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String? _filterSummary(Map<String, Set<String>> f) {
    if (f.isEmpty) return null;
    const labelOf = {
      't1': '最高频',
      't2': '高频',
      't3': '中高频',
      't4': '中频',
      't5': '常用',
      't6': '较少用',
      't7': '低频',
      'n': '名词',
      'v': '动词',
      'a': '形容词',
      'adv': '副词',
      'num': '数词',
      'pron': '代词',
      'prep': '介词',
      'conj': '连词',
      'interj': '感叹词',
      'part': '助词',
    };
    final parts = <String>[];
    for (final e in f.entries) {
      parts.add(e.value.map((v) => labelOf[v] ?? v).join('/'));
    }
    return parts.join(' · ');
  }

  void Function(VoidCallback)? _sheetSet;

  void _safeSheetSet(VoidCallback fn) {
    try {
      _sheetSet?.call(fn);
    } catch (_) {

    }
  }

  Widget _todayProgressCard(AppState app, {bool padded = true}) {
    final left = _plan.taskLeft;
    final dueLeft = _plan.reviewShown - _plan.reviewDone;
    final newLeft = _plan.newPlan - _plan.newDone;

    final quotaNow = app.dailyQuota;
    final over = _plan.finished > quotaNow;
    final total = quotaNow;

    final planTotal = _plan.reviewShown + _plan.newPlan;

    final compReady = _firstCompFor == quotaNow;
    final rDone = (over && compReady) ? _firstComp.review : _plan.reviewDone;
    final nDone = (over && compReady) ? _firstComp.newCount : _plan.newDone;

    final flex =
        todayProgressFlex(reviewDone: rDone, newDone: nDone, total: total);
    final rFlex = flex[0];
    final nFlex = flex[1];
    final restFlex = flex[2];

    Widget sep() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child:
              Text('·', style: TextStyle(fontSize: 12.5, color: context.k.t3)),
        );

    return Padding(
      padding: padded
          ? const EdgeInsets.fromLTRB(12, 2, 12, 8)
          : const EdgeInsets.only(top: 2, bottom: 8),
      child: Container(

        key: _syntheticCardKey,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow(context),
        ),

        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [

                    Row(
                      children: [
                        GestureDetector(
                          key: const Key('status-left'),
                          onTap: () => _openToday('left'),
                          behavior: HitTestBehavior.opaque,
                          child: left == 0

                              ? Text(_noTaskLabel,
                                  style: TextStyle(
                                      fontSize: 20,
                                      height: 1.0,
                                      fontWeight: FontWeight.w700,
                                      color: context.k.deep))
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('$left',
                                        style: TextStyle(
                                            fontSize: 34,
                                            height: 1.0,
                                            fontWeight: FontWeight.w700,
                                            color: context.k.deep,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures()
                                            ])),
                                    const SizedBox(width: 6),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text('张待作答',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: context.k.t2)),
                                    ),
                                  ],
                                ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          key: const Key('mode-card'),
                          onTap: () async {
                            final to =
                                app.studyMode == 'zh2id' ? 'id2zh' : 'zh2id';
                            await app.setStudyMode(to);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                duration: const Duration(milliseconds: 1400),
                                content: Text(to == 'zh2id'
                                    ? '已切到「中印」：看中文想印尼语'
                                    : '已切到「印中」：看印尼语想中文')));
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            height: 26,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.k.tint,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Text(_studyMode == 'zh2id' ? '中-印尼' : '印尼-中',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: context.k.deep)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 8,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (rFlex > 0)
                              Expanded(
                                  flex: rFlex,
                                  child: ColoredBox(color: context.k.brand)),
                            if (nFlex > 0)
                              Expanded(
                                  flex: nFlex,
                                  child: ColoredBox(color: context.k.catEdge)),
                            if (restFlex > 0)
                              Expanded(
                                  flex: restFlex,
                                  child: ColoredBox(color: context.k.ring)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            key: const Key('status-due'),
                            onTap: () => _openToday('due'),
                            behavior: HitTestBehavior.opaque,
                            child: Text('待复习 ${dueLeft < 0 ? 0 : dueLeft}',
                                style: TextStyle(
                                    fontSize: 12.5, color: context.k.t2)),
                          ),
                          sep(),
                          GestureDetector(
                            key: const Key('status-new'),
                            onTap: () => _openToday('new'),
                            behavior: HitTestBehavior.opaque,
                            child: Text('待新学 ${newLeft < 0 ? 0 : newLeft}',
                                style: TextStyle(
                                    fontSize: 12.5, color: context.k.t2)),
                          ),
                          sep(),
                          GestureDetector(
                            key: const Key('quota-card'),
                            onTap: () => showQuotaDialog(context, app),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [

                                Text(
                                    planTotal < quotaNow
                                        ? '今日卡量 ${app.dailyQuota} · 今日可学 $planTotal'
                                        : '今日卡量 ${app.dailyQuota}',
                                    style: TextStyle(
                                        fontSize: 12.5, color: context.k.t2)),
                                Icon(Icons.chevron_right,
                                    size: 14, color: context.k.t3),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              Builder(builder: (context) {
                final a = _goAction(app);
                return GestureDetector(
                  key: const Key('status-go'),
                  onTap: a.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: context.k.brand,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(a.icon, size: 22, color: context.k.onbrand),
                        const SizedBox(height: 4),
                        Text(a.label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.k.onbrand)),
                        if (a.sub != null) ...[
                          const SizedBox(height: 2),
                          Text(a.sub!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: context.k.onbrand
                                      .withValues(alpha: 0.85))),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  VoidCallback get _goStudy => widget.onGoStudy ?? () => _openToday('left');

  ({IconData icon, String label, String? sub, VoidCallback onTap}) _goAction(
      AppState app) {
    final study = (
      icon: Icons.play_arrow_rounded,
      label: '去学习',
      sub: null as String?,
      onTap: _goStudy,
    );
    if (_plan.taskLeft > 0) return study;
    switch (studyStopOf(_plan)) {
      case StudyStop.moreGroup:
        return study;
      case StudyStop.zero:
        return (
          icon: Icons.tune,
          label: '改卡量',
          sub: '今日为 0',
          onTap: () => showQuotaDialog(context, app),
        );
      case StudyStop.quotaOut:
        final waiting =
            (_plan.reviewPlan - _plan.reviewDone).clamp(0, 1 << 30) +
                _plan.poolLeft;
        return (
          icon: Icons.add_circle_outline,
          label: '加卡量',
          sub: waiting > 0 ? '还有 $waiting 张' : null,
          onTap: () => showQuotaDialog(context, app),
        );
      case StudyStop.nothingToLearn:
        final b = _pickWordsTarget(app);
        return (
          icon: Icons.playlist_add,
          label: '去选词',
          sub: b?.name,
          onTap: b == null ? _goStudy : () => _open(b),
        );
    }
  }

  BookNode? _pickWordsTarget(AppState app) {
    final target = app.book;
    if (target != null && _target.total < _target.all) return target;
    for (final b in _books) {
      if (b.parent != null || b.group != '按词频' || b.id == 'nofreq') continue;
      final p = _prog[b.id];
      if (p == null || p.total < p.all) return b;
    }
    return null;
  }

  Widget _stickyBar(AppState app) {
    final left = _plan.taskLeft;
    final dueLeft = _plan.reviewShown - _plan.reviewDone;
    final newLeft = _plan.newPlan - _plan.newDone;
    return Padding(

      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow(context),
        ),
        child: Row(
          children: [
            Text('$left',
                style: TextStyle(
                    fontSize: 20,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: context.k.deep,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 6),
            Text('张待作答', style: TextStyle(fontSize: 13, color: context.k.t2)),
            const SizedBox(width: 6),

            Expanded(
              child: Text(
                  '· 复习 ${dueLeft < 0 ? 0 : dueLeft} / 新学 ${newLeft < 0 ? 0 : newLeft}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: context.k.t3)),
            ),

            Builder(builder: (context) {
              final a = _goAction(app);
              return GestureDetector(
                key: const Key('sticky-go'),
                onTap: a.onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: context.k.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.icon, size: 13, color: context.k.onbrand),
                      const SizedBox(width: 5),
                      Text(a.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.k.onbrand)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openToday(String which) async {
    final app = context.read<AppState>();
    final dueLeft = _plan.reviewShown - _plan.reviewDone;
    final newLeft = _plan.newPlan - _plan.newDone;
    final String title;
    final List<WordCard> rows;
    final int expected;
    switch (which) {
      case 'due':
        title = '待复习';
        rows = await app.db.dueCards();
        expected = dueLeft < 0 ? 0 : dueLeft;
      case 'new':
        title = '待新学';
        expected = newLeft < 0 ? 0 : newLeft;
        rows =
            expected == 0 ? const [] : await app.db.newWords(limit: expected);
      default:
        title = '今日待作答';
        final due = await app.db.dueCards();
        final nl = newLeft < 0 ? 0 : newLeft;
        final fresh = nl == 0 ? const [] : await app.db.newWords(limit: nl);
        rows = [...due, ...fresh];
        expected = _plan.taskLeft;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TodayWordsScreen(title: title, rows: rows, expected: expected),
      ),
    );
  }

  Widget _bookList(AppState app) {
    final roots = _books.where((b) => b.parent == null).toList();
    final segs = _groupRoots(roots);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification || n is UserScrollNotification) {
          _closeSwipe();
        }
        return false;
      },
      child: ListView(

        key: _homeListKey,
        controller: _homeScroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [

          _searchRow(padded: false),
          _todayProgressCard(app, padded: false),

          if (!_onboardSeen) _onboardBar(app),

          const SizedBox(height: 4),
          _memoryCardNew(app),
          const SizedBox(height: 6),

          Padding(
            padding: const EdgeInsets.only(top: 18, left: 2, right: 2),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                      color: context.k.brand,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text('词库与卡组',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.k.text)),
                if (!_swipeTipOff) ...[
                  const Spacer(),

                  SwipeTargetHint(
                      compact: true, onDismiss: app.dismissSwipeTargetTip),
                ],
              ],
            ),
          ),

          for (var si = 0; si < segs.length; si++) ...[
            if (segs[si].key.isNotEmpty)
              _segmentLabelNew(segs[si].key, first: si == 0),
            _bookGroupCard(segs[si].value),
          ],

          const SizedBox(height: 12),

          GestureDetector(
            onTap: _showLibraryHelp,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 18, left: 2, right: 2),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.k.t3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('词库怎么分？一个词可属于多个库，进度只有一份',
                        style: TextStyle(fontSize: 12.5, color: context.k.t2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentLabelNew(String text, {bool first = false}) => Padding(
        padding: EdgeInsets.fromLTRB(2, first ? 10 : 16, 2, first ? 4 : 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.k.t3)),
      );

  Widget _bookGroupCard(List<BookNode> items) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: kCardShadow(context),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: context.k.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(

          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Container(height: 1, color: context.k.line),
              _bookRow(items[i], newStyle: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bookRow(BookNode b, {required bool newStyle}) {
    final row = BookRow(
      book: b,
      isCurrent: _bookId == b.id,
      hasChildren: _books.any((c) => c.parent == b.id),
      progress: newStyle ? _prog[b.id] : (_bookId == b.id ? _prog[b.id] : null),

      finished: isBookFinished(_prog[b.id]),
      onTap: () => _open(b),
      newStyle: newStyle,
    );

    if (!newStyle || !b.clickable) return row;
    final isTarget = _bookId == b.id;
    return SwipeRevealRow(
      enabled: true,
      open: _swipeOpenId == b.id,
      actionLabel: isTarget ? '取消目标' : '设为学习目标',
      destructive: isTarget,
      actionKey: Key('swipe.action-${b.id}'),
      onOpenChanged: (open) =>
          setState(() => _swipeOpenId = open ? b.id : null),
      onAction: () async {
        _closeSwipe();
        final app = context.read<AppState>();
        if (isTarget) {
          await requestClearTarget(context, app);
        } else {
          await requestSetTarget(context, app, b);
        }
        if (mounted) await _load();
      },
      child: row,
    );
  }

  static const String _libHelpLong = '词库分两条轴：按词类/领域/语域/方言/词源的词典式分类，'
      '以及按使用场景编排的「主题词库」。一个词可以同时属于多个词库，'
      '但每个词的记忆进度只有一份——换库学习不会重复计数。';

  Future<void> _showLibraryHelp() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('词库怎么分？'),
          content: const Text(_libHelpLong),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );

  Widget _memoryCardNew(AppState app) {
    final inMemory = _target.total;
    final unselected = _target.all - inMemory;
    final book = app.book;
    final scope = book?.name ?? '全部词汇';
    final isTarget = _bookId != null && _bookId == book?.id;

    final counts = progressBarCounts(_target.bands, unselected);
    final pct = _target.all == 0 ? 0 : (inMemory * 100 / _target.all).round();
    final days = BookCard.estimateDays(_target, _quota);
    final segs = kProgressSegmentsOf(context);

    Widget legend(int i, int n) {
      final seg = segs[i];
      final item = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: seg.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('${seg.label} $n',
            style: TextStyle(fontSize: 12.5, color: context.k.t2)),
      ]);

      final onTap = (i < 5 && n > 0) ? () => _openBand(i, n) : null;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(opacity: n == 0 ? 0.55 : 1.0, child: item),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.k.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kCardShadow(context),
      ),
      child: GestureDetector(
        key: const Key('selected-words-card'),

        onTap: _openTargetList,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Row(
                children: [
                  Text('已选单词',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.k.text)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('· $scope',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: context.k.t2)),
                  ),
                  if (isTarget) ...[
                    Container(
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        color: context.k.tint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 11, color: context.k.deep),
                          const SizedBox(width: 3),
                          Text('学习目标',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.k.deep)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _cancelTarget(),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Text('取消目标',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.k.deep)),
                      ),
                    ),
                  ],

                  if (!isTarget)
                    GestureDetector(
                      key: const Key('home.pickTarget'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await showTargetPicker(context, app);
                        if (mounted) await _load();
                      },
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: context.k.tint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.k.brand, width: 0.8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.flag_outlined,
                              size: 13, color: context.k.deep),
                          const SizedBox(width: 3),
                          Text('设学习目标',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.k.deep)),
                        ]),
                      ),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '更多',

                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(Icons.more_vert, size: 20, color: context.k.t3),
                    onSelected: (v) async {
                      if (v == 'open') {
                        _openTargetList();
                        return;
                      }
                      if (v == 'pick') {
                        await showTargetPicker(context, app);
                      } else if (v == 'set' && book != null) {

                        await requestSetTarget(context, app, book);
                      } else if (v == 'cancel') {
                        await _cancelTarget();
                        return;
                      }
                      if (mounted) await _load();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('进入词表')),
                      if (book == null)
                        const PopupMenuItem(
                            value: 'pick', child: Text('选一个学习目标…')),
                      if (book != null)
                        PopupMenuItem(
                            value: isTarget ? 'cancel' : 'set',
                            child: Text(isTarget ? '取消学习目标' : '设为学习目标')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(

                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '$inMemory',
                            style: TextStyle(
                                fontSize: 26,
                                height: 1.0,
                                fontWeight: FontWeight.w700,
                                color: context.k.text,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                        TextSpan(
                            text: '/${_target.all} 词',
                            style:
                                TextStyle(fontSize: 13, color: context.k.t2)),
                      ]),
                    ),
                  ),
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.k.tint,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text('$pct%',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.k.deep)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              MemorySegmentBar(counts: counts, height: 10, radius: 5),
              const SizedBox(height: 10),

              if (inMemory == 0)
                Text('还没有加入记忆的单词：点进下面的卡组，用每行末尾的「＋」挑几个',
                    style: TextStyle(fontSize: 12, color: context.k.t3))
              else
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 6; i++) legend(i, counts[i]),
                  ],
                ),

              if (days != null) ...[
                const SizedBox(height: 8),
                Text('预计还需 $days 天完成',
                    style: TextStyle(fontSize: 12, color: context.k.t3)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askWordListName(String suggested) async {
    final ctl = TextEditingController(text: suggested);
    ctl.selection =
        TextSelection(baseOffset: 0, extentOffset: suggested.length);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('存为词单'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 30,
            decoration:
                const InputDecoration(hintText: '给这个词单起个名字', counterText: ''),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctl.text),
                child: const Text('保存')),
          ],
        ),
      );
    } finally {

      ctl.dispose();
    }
  }

  Widget _onboardBar(AppState app) {
    if (app.onboardSeen) return const SizedBox.shrink();
    final t1s = _books.where((b) => b.id == 't1');
    if (t1s.isEmpty) return const SizedBox.shrink();
    final t1 = t1s.first;
    return Padding(

      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: context.k.catTint2,
          border: Border.all(color: context.k.catTint, width: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              '不知道从哪开始？建议先学「${t1.name}」（${t1.count} 词），全是最常用的词',
              style: TextStyle(fontSize: 11.5, color: context.k.catDeep),
            ),
          ),
          GestureDetector(
            onTap: () async {
              await app.markOnboardSeen();
              if (!mounted) return;

              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => WordListScreen(book: t1)));
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('去看看 ›',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: context.k.catMid,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          GestureDetector(
            onTap: () => app.markOnboardSeen(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text('✕',
                  style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
            ),
          ),
        ]),
      ),
    );
  }

  List<MapEntry<String, List<BookNode>>> _groupRoots(List<BookNode> roots) {
    const order = ['按词频', '按分类浏览', '按构词与来源', '其他'];
    final out = <MapEntry<String, List<BookNode>>>[];
    for (final g in order) {
      final items = roots.where((b) => b.group == g).toList();
      if (items.isNotEmpty) out.add(MapEntry(g, items));
    }
    final rest = roots.where((b) => !order.contains(b.group)).toList();
    if (rest.isNotEmpty) out.add(MapEntry('', rest));
    return out;
  }

  void _openTargetList() {
    final book = context.read<AppState>().book;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => WordListScreen(
              book: book ?? const BookNode(id: 'all', name: '全部词汇', count: 0))),
    ).then((_) => _load());
  }

  void _openBand(int band, int n) {
    final app = context.read<AppState>();
    Navigator.push(
      context,
      MaterialPageRoute(

        builder: (_) => MemoryBandScreen(
            band: band,
            count: n,
            filter: app.bookFilter,
            scope: app.book?.name ?? '全部词汇'),
      ),
    );
  }

  void _open(BookNode book) {
    final children = _books.where((b) => b.parent == book.id).toList();
    if (children.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookChildrenScreen(parent: book, children: children),
        ),
      ).then((_) => _load());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WordListScreen(book: book)),
      ).then((_) => _load());
    }
  }
}

class _BookRingPainter extends CustomPainter {
  const _BookRingPainter(this.value, this.track, this.fill);

  final double value;
  final Color track;

  final Color fill;
  static const _stroke = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (m.min(size.width, size.height) - _stroke) / 2;
    if (r <= 0) return;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..isAntiAlias = true
          ..color = track);
    final v = value.clamp(0.0, 1.0).toDouble();
    if (v <= 0) return;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -m.pi / 2,
        2 * m.pi * v,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
          ..color = fill);
  }

  @override
  bool shouldRepaint(_BookRingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}
