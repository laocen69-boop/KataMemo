library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../activity_log.dart' show writeSearchHistoryWithLog;
import '../version.dart' show kAiChat;
import '../widgets/ai_widgets.dart' show AiAskChip, openGeneralAi;
import '../widgets/copy_text.dart';
import '../models.dart';
import '../widgets/memory_ring.dart' show MemoryRing, memoryBandColor;
import '../widgets/quota_dialog.dart';
import '../widgets/speak_button.dart' show SpeakButton, kSpeakGreen;
import '../widgets/word_search.dart';
import '../perf_log.dart';
import '../widgets/word_tile.dart';
import 'scan_screen.dart';
import 'select_screen.dart';
import 'word_detail_screen.dart';

const int kSearchHistoryMax = 20;

const int kSearchLimit = 300;

const String kSearchHistoryKey = 'search_history';
const String kSearchHistoryBookKey = 'search_history_book';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();

  int _tab = 0;

  String _query = '';
  bool _searching = false;

  String _filter = 'all';
  String _sort = 'relevance';

  List<WordCard> _results = const [];
  List<BookNode> _bookHits = const [];
  List<BookNode> _books = const [];

  List<String> _history = const [];

  Map<String, WordCard> _histCards = const {};

  SrsLevelMap _levels = const {};
  Set<String> _planned = const {};

  final Set<String> _sel = {};

  Timer? _debounce;

  int _seq = 0;

  bool _recorded = false;

  static const kLiveSearchDelay = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _loadStatic();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      _reset();
      return;
    }

    if (_ctl.value.composing.isValid && !_ctl.value.composing.isCollapsed) {
      return;
    }
    _debounce = Timer(kLiveSearchDelay, () => _run(v, record: false));
  }

  void _onSubmitted(String v) {
    _debounce?.cancel();
    _run(v);
  }

  void _recordQuery() {
    if (_recorded || _query.isEmpty) return;
    _recorded = true;
    _pushHistory(_query);
  }

  Future<void> _loadStatic() async {
    final app = context.read<AppState>();
    final books = await app.repo.loadBooks();
    final hist = await _readHistory(app);
    if (!mounted) return;
    setState(() {
      _books = books;
      _history = hist;
    });
    await _resolveHistory();
  }

  String get _histKey => _tab == 0 ? kSearchHistoryKey : kSearchHistoryBookKey;

  Future<List<String>> _readHistory(AppState app) async {
    final raw = await app.db.metaGet(_histKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List))
          if (e.toString().trim().isNotEmpty) e.toString(),
      ];
    } catch (_) {

      return const [];
    }
  }

  Future<void> _writeHistory(List<String> h) async {
    await context.read<AppState>().db.metaSet(_histKey, jsonEncode(h));
  }

  Future<void> _reloadHistory() async {
    final app = context.read<AppState>();
    final h = await _readHistory(app);
    if (!mounted) return;
    setState(() {
      _history = h;
      _histCards = const {};
    });
    await _resolveHistory();
  }

  Future<void> _resolveHistory() async {

    if (_tab == 1 || _history.isEmpty) return;
    final app = context.read<AppState>();
    final m = <String, WordCard>{};
    for (final t in _history) {
      final c = await app.db.searchWords(t);
      if (c != null) m[t] = c;
    }
    if (!mounted) return;
    setState(() => _histCards = m);
    await _loadMeta(m.values.toList());
  }

  Future<void> _loadMeta(List<WordCard> cards) async {
    if (cards.isEmpty) return;
    final app = context.read<AppState>();
    final lv = await loadLevels(app.db, cards);
    final planned = await app.db.plannedIds([for (final c in cards) c.id]);
    if (!mounted) return;
    setState(() {
      _levels = lv;
      _planned = planned;
    });
  }

  bool _enrolledOf(WordCard w) =>
      wordEnrolled(w.id, w.enabled, planned: _planned, levels: _levels);

  Future<void> _togglePlan(WordCard w) async {
    final app = context.read<AppState>();
    final was = _enrolledOf(w);
    if (was) {
      await app.forget([w.id]);
    } else {
      await app.remember([w.id]);
    }
    if (!mounted) return;
    setState(() {
      _planned = {..._planned};
      if (was) {
        _planned.remove(w.id);
      } else {
        _planned.add(w.id);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            was ? '已把 ${w.word} 移出记忆，不再进入学习队列' : '已把 ${w.word} 加入记忆，下一组队列生效')));
  }

  Future<void> _pushHistory(String term) async {
    final h = [
      term,
      ..._history.where((x) => x != term),
    ];
    final cut =
        h.length > kSearchHistoryMax ? h.sublist(0, kSearchHistoryMax) : h;
    final db = context.read<AppState>().db;
    setState(() => _history = cut);

    await writeSearchHistoryWithLog(db, _histKey, cut, _tab == 0 ? term : null);
  }

  Future<void> _clearHistory() async {
    setState(() {
      _history = const [];
      _histCards = const {};
    });
    await _writeHistory(const []);
  }

  void _reset() {
    _debounce?.cancel();
    _seq++;
    _recorded = false;
    _ctl.clear();
    setState(() {
      _query = '';
      _results = const [];
      _bookHits = const [];
      _searching = false;
      _sel.clear();
    });
  }

  void _setTab(int i) {
    if (_tab == i) return;
    setState(() => _tab = i);

    _reloadHistory();

    if (_query.isNotEmpty) _run(_query, record: false);
  }

  Future<void> _run(String v, {bool record = true}) async {
    final q = v.trim();
    if (q.isEmpty) return;
    final seq = ++_seq;
    if (q != _query) _recorded = false;
    setState(() {
      _query = q;
      _searching = true;
    });
    final app = context.read<AppState>();
    if (_tab == 0) {
      final sw = Stopwatch()..start();
      final r = await app.db.searchAll(q, limit: kSearchLimit);
      final tQuery = sw.elapsedMilliseconds;
      final lv = await loadLevels(app.db, r);
      final planned = await app.db.plannedIds([for (final e in r) e.id]);
      perfLog('search', sw, 'q=$q n=${r.length} query=${tQuery}ms');
      if (!mounted || seq != _seq) return;
      final ids = {for (final e in r) e.id};
      setState(() {
        _results = r;
        _levels = lv;
        _planned = planned;
        _searching = false;

        _sel.removeWhere((id) => !ids.contains(id));
      });
    } else {
      final hits = _matchBooks(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _bookHits = hits;
        _searching = false;
      });
    }
    if (!record || _recorded) return;
    _recorded = true;
    await _pushHistory(q);

    if (_tab == 0 && _histCards[q] == null) {
      final c = await app.db.searchWords(q);
      if (c != null && mounted) {
        setState(() => _histCards = {..._histCards, q: c});
      }
    }
  }

  List<BookNode> _matchBooks(String q) {
    final k = q.toLowerCase();
    int rankOf(BookNode b) {
      final n = b.name.toLowerCase();
      if (n == k) return 0;
      if (n.startsWith(k)) return 1;
      return 2;
    }

    return _books.where((b) => b.name.toLowerCase().contains(k)).toList()
      ..sort((a, b) {
        final r = rankOf(a).compareTo(rankOf(b));
        return r != 0 ? r : b.count.compareTo(a.count);
      });
  }

  void _openBook(BookNode b) {
    _recordQuery();
    final kids = _books.where((x) => x.parent == b.id).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => kids.isNotEmpty
            ? BookChildrenScreen(parent: b, children: kids)
            : WordListScreen(book: b),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      backgroundColor: context.k.nBg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _tabs(),
            Expanded(
              child: _query.isEmpty
                  ? _historyView()
                  : (_tab == 0 ? _wordResults() : _bookResults()),
            ),

            if (_tab == 0) _bottomPill(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 14, 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: context.k.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.k.g300),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 19, color: context.k.nFaint2),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _ctl,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _onSubmitted,
                        onChanged: _onChanged,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '请输入单词或词本名称',
                          hintStyle: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),

                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctl,
                      builder: (_, v, __) => v.text.isEmpty
                          ? const SizedBox.shrink()
                          : Tooltip(
                              message: '复制搜索词',
                              child: InkWell(
                                onTap: () =>
                                    copyText(context, v.text, label: '已复制搜索词'),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.copy,
                                      size: 18, color: context.k.g400),
                                ),
                              ),
                            ),
                    ),
                    if (_query.isNotEmpty)
                      InkWell(
                        onTap: _reset,
                        child:
                            Icon(Icons.cancel, size: 18, color: context.k.g400),
                      ),
                  ],
                ),
              ),
            ),

            IconButton(
              icon: Icon(Icons.photo_camera_outlined,
                  size: 22, color: context.k.t2),
              tooltip: '拍照抓词',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              ),
            ),
          ],
        ),
      );

  Widget _tabs() => Container(
        color: context.k.surface,
        child: Row(
          children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: InkWell(
                  onTap: () => _setTab(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _tab == i ? kSpeakGreen : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      i == 0 ? '单词' : '词书',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            _tab == i ? FontWeight.w700 : FontWeight.w400,
                        color: _tab == i ? kSpeakGreen : context.k.nT2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _historyView() {
    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            _tab == 0
                ? '输入印尼语或中文开始搜索。\n想找卡组 / 主题就切到「词书」那一栏。'
                : '输入卡组 / 主题名开始搜索。\n比如「金融银行」「交通出行」。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.k.nFaint2),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
          child: Row(
            children: [
              Text('历史记录',
                  style: TextStyle(fontSize: 13.5, color: context.k.nT2)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: context.k.nFaint2),
                tooltip: '清空历史',
                onPressed: _clearHistory,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [for (final t in _history) _historyRow(t)],
          ),
        ),
      ],
    );
  }

  Widget _searchStatusChip(bool enrolled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: enrolled
            ? context.k.brand.withValues(alpha: 0.12)
            : context.k.nFaint2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(enrolled ? '已在记忆' : '未加入',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: enrolled ? context.k.brand : context.k.nT2)),
    );
  }

  Widget _historyRow(String term) {
    final book = _tab == 1;
    final c = book ? null : _histCards[term];

    final enrolled = c != null && _enrolledOf(c);
    final disabled = c != null && !enrolled;
    final st = c == null || !enrolled ? null : strengthOf(_levels, c.id);

    final label = c?.word ?? term;
    final initial =
        label.characters.isEmpty ? '?' : label.characters.first.toUpperCase();
    final sub = c == null ? (book ? '词书' : '搜过的词') : null;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 6),
      minVerticalPadding: 8,
      leading: MemoryRing(
        strength: st,
        size: 38,
        child: Text(
          initial,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: disabled ? context.k.nT2 : context.k.brand),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: context.k.text)),
          ),
          if (c != null && enrolled) ...[
            const SizedBox(width: 7),
            _searchStatusChip(true),
            if (st != null) ...[
              const SizedBox(width: 5),
              Text(st.shortLabel,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: memoryBandColor(context, st.band))),
            ],
          ],
        ],
      ),

      subtitle: c == null
          ? Text(sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 14.5, height: 1.35, color: context.k.nT2))
          : SearchMeaningLine(
              card: c,
              book: context.read<AppState>().book,
              highlightQuery: term,
              wordClass: c.wordClassLabelsCombined,
              zh: c.zhClean,
            ),
      trailing: c == null
          ? Icon(Icons.chevron_right, size: 20, color: context.k.g400)
          : SpeakButton(card: c, iconSize: 22),

      onTap: () {
        _ctl.text = term;
        _run(term, record: false);
      },
      onLongPress: c == null ? null : () => _togglePlan(c),
    );
  }

  List<WordCard> _visibleResults() {
    final list = <WordCard>[
      for (final w in _results)
        if (_filter == 'all' ||
            (_filter == 'new' ? !_enrolledOf(w) : _enrolledOf(w)))
          w,
    ];
    if (_sort == 'freq') {
      list.sort((a, b) {
        final ra = a.rank ?? (1 << 30);
        final rb = b.rank ?? (1 << 30);
        final c = ra.compareTo(rb);
        return c != 0
            ? c
            : a.word.toLowerCase().compareTo(b.word.toLowerCase());
      });
    } else if (_sort == 'alpha') {
      list.sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
    }
    return list;
  }

  void _setFilter(String f) {
    if (_filter == f) return;
    setState(() {
      _filter = f;
      _sel.clear();
    });
  }

  String get _sortLabel => switch (_sort) {
        'freq' => '语料排名',
        'alpha' => '字母',
        _ => '相关度',
      };

  Widget _filterChip(String id, String label) {
    final on = _filter == id;
    return GestureDetector(
      key: Key('search.filter.$id'),
      onTap: () => _setFilter(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? context.k.tint : context.k.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? context.k.tint : context.k.line, width: 0.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? context.k.deep : context.k.t2)),
      ),
    );
  }

  Widget _sortButton() {
    return PopupMenuButton<String>(
      key: const Key('search.sort'),
      initialValue: _sort,
      tooltip: '排序',
      color: context.k.surface,
      onSelected: (v) {
        if (v != _sort) setState(() => _sort = v);
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'relevance', child: Text('相关度（默认）')),
        PopupMenuItem(value: 'freq', child: Text('语料排名（高频在前）')),
        PopupMenuItem(value: 'alpha', child: Text('字母（A→Z）')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.k.line, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort, size: 15, color: context.k.t2),
            const SizedBox(width: 4),
            Text(_sortLabel,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.k.t2)),
            Icon(Icons.expand_more, size: 14, color: context.k.t2),
          ],
        ),
      ),
    );
  }

  Widget _wordResults() {

    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '没找到「$_query」。\n可以试试：只输词根（搜 makanan 试 makan）、'
                '或改用中文（搜「吃」）。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.k.nT2),
              ),

              if (kAiChat) ...[
                const SizedBox(height: 16),
                AiAskChip(
                  key: const ValueKey('search.askAi'),
                  label: '问 AI「${_query.length > 12 ? '${_query.substring(0, 12)}…' : _query}」',
                  onTap: () => openGeneralAi(context,
                      draft: RegExp(r'[一-鿿]').hasMatch(_query)
                          ? '「$_query」用印尼语怎么说？给出常用说法和例句。'
                          : '「$_query」是什么意思？如果是口语、缩写或拼写变体，请说明标准写法，并给例句。'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final visible = _visibleResults();

    final truncated = _results.length >= kSearchLimit;
    final total = truncated ? '前 ${_results.length} 个' : '${_results.length} 个';
    final head = _filter != 'all'
        ? '显示 ${visible.length} / $total'
        : (truncated ? '显示前 ${_results.length} 个' : '命中 ${_results.length} 个');
    return Column(
      children: [

        SizedBox(
          height: 2,
          child: _searching
              ? LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: context.k.brand)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: head),
                    if (truncated)
                      TextSpan(
                          text: ' · 输入更完整可缩小范围',
                          style: TextStyle(color: context.k.nFaint2)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: context.k.nT2),
                ),
              ),
              _sortButton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),

          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', '全部'),
                  const SizedBox(width: 7),
                  _filterChip('new', '未加入'),
                  const SizedBox(width: 7),
                  _filterChip('enrolled', '已在记忆'),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _filter == 'new'
                          ? '这 ${_results.length} 个结果都已加入记忆'
                          : '这 ${_results.length} 个结果都还没加入记忆',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: context.k.nT2),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final w = visible[i];
                    final enrolled = _enrolledOf(w);
                    return WordTile(
                      card: w,
                      book: context.read<AppState>().book,
                      highlightQuery: _query,
                      hint: matchHint(w, _query),
                      strength: strengthOf(_levels, w.id),
                      enrolled: enrolled,

                      searchLayout: true,

                      member: enrolled,

                      selectMode: true,
                      selected: _sel.contains(w.id),
                      selectable: !enrolled,
                      onSelectTap: () => _toggleSel(w),
                      onTap: () {
                        _recordQuery();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => WordDetailScreen(cardId: w.id)),
                        );
                      },
                      onLongPress: () => _togglePlan(w),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _toggleSel(WordCard w) {
    if (_sel.contains(w.id)) {
      setState(() => _sel.remove(w.id));
      return;
    }

    final quota = context.read<AppState>().dailyQuota;
    if (_sel.length >= quota) {
      _showOverQuota(quota);
      return;
    }
    setState(() => _sel.add(w.id));
  }

  Future<void> _showOverQuota(int quota) async {
    final changed =
        await showOverQuotaDialog(context, context.read<AppState>(), quota);
    if (changed && mounted) setState(() {});
  }

  Widget _bottomPill() {
    final quota = context.select<AppState, int>((a) => a.dailyQuota);
    final n = _sel.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 190,
              height: 42,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kSpeakGreen,

                  foregroundColor: context.k.onbrand,

                  disabledBackgroundColor: context.k.alt,
                  disabledForegroundColor: context.k.nT2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(21)),
                ),
                onPressed: n == 0 ? null : _applySelection,
                child: Text('加入记忆 $n/$quota',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applySelection() async {
    final app = context.read<AppState>();
    final byId = {for (final w in _results) w.id: w};
    final ids = [
      for (final id in _sel)
        if (byId[id] != null && !_enrolledOf(byId[id]!)) id,
    ];
    if (ids.isEmpty) {
      setState(_sel.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1600),
          content: Text('勾上的都已经在记忆里了')));
      return;
    }
    await app.remember(ids);
    if (!mounted) return;
    setState(() {
      _planned = {..._planned, ...ids};
      _sel.clear();
    });
    final scope = app.book;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text(scope == null
          ? '已加入记忆 ${ids.length} 个，会排进下一组学习队列'
          : '已加入记忆 ${ids.length} 个 · 当前学习范围是「${scope.name}」，'
              '不含它们就不会出现在队列里'),
    ));
  }

  Widget _bookResults() {
    if (_bookHits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '没找到叫「$_query」的词书。\n可以搜「金融银行」「交通出行」这类卡组 / 主题名。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.k.nT2),
          ),
        ),
      );
    }
    final app = context.read<AppState>();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _bookHits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final b = _bookHits[i];
        final hasChildren = _books.any((x) => x.parent == b.id);
        return BookCard(
          book: b,
          dailyQuota: app.dailyQuota,
          isCurrent: app.book?.id == b.id,
          hasChildren: hasChildren,
          onTap: () => _openBook(b),
        );
      },
    );
  }
}
