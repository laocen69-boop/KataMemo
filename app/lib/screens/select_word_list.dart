part of 'select_screen.dart';

enum _PickMode { none, sequential, random }

class WordListScreen extends StatefulWidget {
  final BookNode book;

  final bool fromStudy;

  const WordListScreen({super.key, required this.book, this.fromStudy = false});

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen>
    with _PagedScroll<WordListScreen> {
  List<WordCard> _words = [];
  bool _loading = true;
  final Map<String, bool> _selection = {};
  _PickMode _pickMode = _PickMode.none;

  static const _pageSize = 200;
  static const _pageStep = 200;

  static const _weakPageSize = 2000;

  bool _hasMore = true;
  bool _loadingMore = false;
  final _scroll = ScrollController();

  final _searchCtl = TextEditingController();
  String _query = '';
  List<WordCard> _results = [];
  bool _searching = false;

  SrsLevelMap _levels = {};
  bool _onlyWeak = false;

  Set<String> _planned = {};

  final Set<String> _dropped = {};

  int _todayDone = 0;

  String _scope = 'unselected';

  String get _scopeForDb => _scope == 'selected' ? 'enrolled' : _scope;

  final Set<String> _collapsed = {};

  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String msg) {
    _noticeTimer?.cancel();
    setState(() => _notice = msg);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Map<String, int> _gcounts = const {};

  bool _countsReady = false;

  bool _searchOpen = false;

  BookProgress? _progress;

  String _groupModeOf(String sort) =>
      sort.startsWith('alpha') ? 'letter' : 'tier';

  static String letterKeyOf(String word) {
    if (word.isEmpty) return '#';
    final c = word[0];
    return RegExp(r'[A-Za-z]').hasMatch(c) ? c.toUpperCase() : '#';
  }

  int? _scopeTotal() {
    if (_onlyWeak || !_countsReady) return null;
    return _gcounts.values.fold<int>(0, (a, b) => a + b);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  ScrollController get _pageScroll => _scroll;
  @override
  bool get _pageHasMore => _hasMore;
  @override
  bool get _pageLoadingMore => _loadingMore;
  @override
  Future<void> _pageLoadMore() => _loadMore();
  @override
  double get _pageThreshold => 600;
  @override
  bool get _scrollLoadBlocked => _onlyWeak || _query.isNotEmpty;

  @override
  bool get _autoFillBlocked =>
      _onlyWeak || _query.isNotEmpty || _scopeTotal() == 0;

  List<WordCard> _applyBookOrder(List<WordCard> list, String sort) {
    final ord = widget.book.order;
    if (ord.isEmpty || sort != 'rank' || list.length < 2) return list;
    final pos = <String, int>{};
    for (var i = 0; i < ord.length; i++) {
      pos[ord[i]] = i;
    }

    final keyed = <MapEntry<int, WordCard>>[];
    for (var i = 0; i < list.length; i++) {
      keyed.add(MapEntry(pos[list[i].id] ?? (ord.length + i), list[i]));
    }
    keyed.sort((a, b) => a.key.compareTo(b.key));
    return [for (final e in keyed) e.value];
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final app = context.read<AppState>();
    final more = await app.db.wordsByFilter(widget.book.filter,
        limit: _pageStep, offset: _words.length, sort: app.librarySort);
    final lv = await loadLevels(app.db, more);
    final planned = await app.db.plannedIds([for (final w in more) w.id]);
    if (!mounted) return;
    setState(() {
      _words = _applyBookOrder([..._words, ...more], app.librarySort);
      _levels = {..._levels, ...lv};
      _planned = {..._planned, ...planned};
      _hasMore = more.length >= _pageStep;
      _loadingMore = false;
    });
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final size = _onlyWeak ? _weakPageSize : _pageSize;
    var page = await app.db
        .wordsByFilter(widget.book.filter, limit: size, sort: app.librarySort);
    final prog = await app.db.bookProgress(widget.book.filter);

    final lv = await loadLevels(app.db, page);

    final planned = await app.db.plannedIds([for (final w in page) w.id]);
    final todayDone = await app.db.todayAnsweredWords();

    final counts = await app.db.groupCounts(widget.book.filter,
        mode: _groupModeOf(app.librarySort), scope: _scopeForDb);
    if (!mounted) return;
    if (_onlyWeak) {

      page = [
        for (final w in page)
          if (strengthOf(lv, w.id).band != MemoryBand.mastered) w
      ];
    }

    page = _applyBookOrder(page, app.librarySort);
    setState(() {
      _words = page;
      _autoFill = true;
      _progress = prog;
      _levels = lv;
      _planned = planned;
      _todayDone = todayDone;
      _gcounts = counts;
      _countsReady = true;
      _dropped.clear();
      _loading = false;
      _hasMore = !_onlyWeak && page.length >= size;
    });
  }

  Future<void> _loadCounts() async {
    final app = context.read<AppState>();
    final c = await app.db.groupCounts(widget.book.filter,
        mode: _groupModeOf(app.librarySort), scope: _scopeForDb);
    if (!mounted) return;
    setState(() {
      _gcounts = c;
      _countsReady = true;
    });
  }

  Widget _searchBar() => WordSearchBar(
        controller: _searchCtl,
        query: _query,
        scope: widget.book.name,
        autofocus: _searchOpen,
        onSubmit: _runSearch,
        onClear: () {
          _searchCtl.clear();

          _autoFill = true;
          setState(() {
            _query = '';
            _results = [];
          });
        },
      );

  Future<void> _runSearch(String v) async {
    final q = v.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    final app = context.read<AppState>();
    final r = await app.db.searchAll(q, filter: widget.book.filter, limit: 300);

    final lv = await loadLevels(app.db, r);
    if (!mounted) return;
    setState(() {
      _query = q;
      _results = r;
      _levels = {..._levels, ...lv};
      _searching = false;
    });
  }

  String? get _bookId => context.select<AppState, String?>((a) => a.book?.id);
  int get _quota => context.select<AppState, int>((a) => a.dailyQuota);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final searching = _query.isNotEmpty;

    final shown = searching ? _results : _visibleRows();

    final byLetter = _groupModeOf(app.librarySort) == 'letter';
    final groups = <String, List<WordCard>>{};
    final gorder = <String>[];
    if (!searching) {
      for (final w in shown) {
        final k = _groupKey(w, byLetter);
        final g = groups[k];
        if (g == null) {
          groups[k] = [w];
          gorder.add(k);
        } else {
          g.add(w);
        }
      }
    }

    final entries = <Object>[];
    for (final k in gorder) {
      entries.add(k);
      if (!_collapsed.contains(k)) entries.addAll(groups[k]!);
    }

    final byId = {
      for (final w in _words) w.id: w,
      for (final w in _results) w.id: w,
    };
    var nAdd = 0;
    for (final id in _selection.keys) {
      final w = byId[id];
      if (w == null || !_enrolledOf(w)) nAdd++;
    }
    _scheduleFill();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,

        leadingWidth: widget.fromStudy ? 100 : null,
        leading: widget.fromStudy
            ? Padding(
                padding: const EdgeInsets.only(left: 8, top: 12, bottom: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kSpeakGreen,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('返回学习页面',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                ),
              )
            : null,

        title: Text(widget.book.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
        actions: [

          IconButton(
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            tooltip: _searchOpen ? '收起搜索' : '搜索',
            onPressed: _toggleSearch,
          ),

          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onPressed: _openMoreSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                if (_searchOpen || searching) _searchBar(),

                if (!searching) ...[
                  _progressStrip(app),
                  _statStrip(nAdd),
                ],
                if (searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _searching
                            ? '搜索中…'
                            : '「$_query」命中 ${_results.length} 个'
                                '${_results.length >= 300 ? '（已截断，请加关键词缩小范围）' : ''}',
                        style: TextStyle(fontSize: 12.5, color: context.k.nT2),
                      ),
                    ),
                  ),

                if (!searching && widget.book.id == 'nofreq') _noFreqNotice(),
                Expanded(

                  child: !searching && shown.isEmpty && _scopeTotal() == 0
                      ? _scopeEmptyView()
                      : searching && _results.isEmpty && !_searching
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  '没找到「$_query」。\n'
                                  '可以试试：只输词根（搜 makanan 试 makan）、'
                                  '或改用中文（搜「吃」）。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13, color: context.k.nT2),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,

                              itemCount:
                                  searching ? shown.length : entries.length + 1,
                              itemBuilder: (ctx, i) {
                                if (!searching && i >= entries.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                    child: Center(
                                      child: _loadingMore
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : Text(
                                              _hasMore
                                                  ? '— 已显示 ${shown.length} 词，继续下滑加载 —'
                                                  : '— 共 ${shown.length} 词 —',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: context.k.nFaint2)),
                                    ),
                                  );
                                }

                                if (searching) {
                                  final w = shown[i];
                                  return _wordRow(w,
                                      hint: matchHint(w, _query));
                                }
                                final e = entries[i];
                                if (e is WordCard) return _wordRow(e);
                                final key = e as String;
                                return _groupHeader(key, groups[key]!);
                              },
                            ),
                ),

                _noticeBar(),
                _bottomBar(nAdd, _removeCount()),
              ],
            ),
    );
  }

  Widget _noFreqNotice() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: context.k.nEdge, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'wordfreq 与牌组语料都没有收录这些词，无法按词频排序；它们仍可正常学习，'
          '按意义去词性/主题里找。词仍在原来的层里，这里只是多一个入口。',
          style: TextStyle(fontSize: 12, height: 1.45, color: context.k.nT2),
        ),
      ),
    );
  }

  Widget _noticeBar() {
    final msg = _notice;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      transitionBuilder: (c, a) => SizeTransition(
          sizeFactor: a, child: FadeTransition(opacity: a, child: c)),
      child: msg == null
          ? const SizedBox(width: double.infinity)
          : GestureDetector(
              key: ValueKey(msg),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _notice = null),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.k.nInk,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(msg,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.white, height: 1.3)),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _progressStrip(AppState app) {
    final p = _progress;
    final isCurrent = _bookId == widget.book.id;
    final started = p?.started ?? 0;
    final inMemory = p?.total ?? widget.book.count;
    final left = (inMemory - started).clamp(0, inMemory);

    final days = BookCard.estimateDays((
      all: p?.all ?? widget.book.count,
      total: inMemory,
      started: started,
      due: p?.due ?? 0,
      bands: p?.bands ?? kEmptyBands
    ), _quota);

    final tiny = TextStyle(fontSize: 11, color: context.k.nFaint);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '在记忆 $inMemory / ${p?.all ?? widget.book.count} 词 · '
                  '已学 $started${(p?.due ?? 0) > 0 ? ' · 待复习 ${p!.due}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tiny,
                ),
              ),
              if (isCurrent)
                TextButton(
                  onPressed: () => requestClearTarget(context, app),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 24),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text('取消目标',
                      style: TextStyle(fontSize: 11.5, color: kSpeakGreen)),
                )
              else

                GestureDetector(
                  key: const Key('book.setTarget'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => requestSetTarget(context, app, widget.book),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: context.k.tint,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: context.k.brand, width: 0.8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.flag_outlined, size: 14, color: context.k.deep),
                      const SizedBox(width: 4),
                      Text('设为学习目标',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: context.k.deep)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          MemorySegmentBar(
              counts: progressBarCounts(p?.bands ?? kEmptyBands,
                  (p?.all ?? widget.book.count) - inMemory),
              height: 4,
              radius: 2),
          const SizedBox(height: 4),
          Text(

            inMemory == 0
                ? '还没有词加入记忆'
                : left == 0
                ? '本库已全部学过'
                : days == null
                    ? '还剩 $left 词未学'
                        '${_quota <= 0 ? '（今日卡量为 0，今天不排新卡）' : ''}'
                    : '还剩 $left 词未学 · 按每天 $_quota 张约 $days 天完成',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tiny,
          ),
        ],
      ),
    );
  }

  List<WordCard> _visibleRows() => _scope == 'all'
      ? _words
      : [
          for (final w in _words)
            if ((_scope == 'selected') == _enrolledOf(w)) w
        ];

  List<WordCard> _selectableRows() => [
        for (final w in (_query.isNotEmpty ? _results : _visibleRows()))
          if (_selectable(w)) w
      ];

  Widget _statStrip(int nAdd) {
    final p = _progress;
    final all = p?.all ?? widget.book.count;
    final total = (p?.total ?? 0).clamp(0, all);
    final unselected = all - total;
    final pct = pctLabel(total, all);
    Widget cell(String key, String value, String label,
        {bool active = false, bool green = false, VoidCallback? onTap}) {
      return Expanded(
        child: InkWell(
          key: Key(key),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: active ? context.k.nPanel2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: green ? kSpeakGreen : context.k.nInk2)),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, color: context.k.nFaint2)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        cell('cell-unselected', '$unselected', '未选',
            active: _scope == 'unselected',
            green: _scope == 'unselected',
            onTap: () => _setScope('unselected')),
        cell('cell-selected', pct, '已选',
            active: _scope == 'selected',
            green: _scope == 'selected',
            onTap: () => _setScope('selected')),
        cell('cell-all', '$all', '全部',
            active: _scope == 'all',
            green: _scope == 'all',
            onTap: () => _setScope('all')),

        cell('cell-today', '$nAdd', '今日待选', green: true),
      ]),
    );
  }

  Future<void> _setScope(String s) async {
    if (_scope == s) return;

    _autoFill = true;
    setState(() => _scope = s);
    await _loadCounts();
  }

  Widget _scopeEmptyView() {
    final all = _progress?.all ?? widget.book.count;
    String msg;
    (String, String)? jump;
    if (all == 0) {
      msg = '这个卡组里还没有词';
      jump = null;
    } else if (_scope == 'unselected') {
      msg = '这个范围里的词都已加入记忆了';
      jump = ('查看已加入的词', 'selected');
    } else if (_scope == 'selected') {
      msg = '还没有词加入记忆';
      jump = ('查看全部词汇', 'all');
    } else {
      msg = '这个卡组里没有词';
      jump = null;
    }
    final j = jump;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: context.k.g400),
            const SizedBox(height: 10),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.k.nT2)),
            if (j != null)
              TextButton(onPressed: () => _setScope(j.$2), child: Text(j.$1)),
          ],
        ),
      ),
    );
  }

  String _groupKey(WordCard w, bool byLetter) =>
      byLetter ? letterKeyOf(w.word) : w.tier;

  void _toggleGroup(String key) {
    final box = _headerAnchor[key]?.currentContext?.findRenderObject();
    final before = box is RenderBox ? box.localToGlobal(Offset.zero).dy : null;
    setState(() {
      if (_collapsed.contains(key)) {
        _collapsed.remove(key);
        _autoFill = true;
      } else {
        _collapsed.add(key);
        _autoFill = false;
      }
    });
    if (before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final rb = _headerAnchor[key]?.currentContext?.findRenderObject();
      if (rb is! RenderBox) return;
      final delta = rb.localToGlobal(Offset.zero).dy - before;
      if (delta.abs() < 0.5) return;
      final pos = _scroll.position;

      _anchorJump = true;
      try {
        _scroll.jumpTo((pos.pixels + delta).clamp(0.0, pos.maxScrollExtent));
      } finally {
        _anchorJump = false;
      }
    });
  }

  final Map<String, GlobalKey> _headerAnchor = {};

  Widget _groupHeader(String key, List<WordCard> rows) {
    final byLetter =
        _groupModeOf(context.read<AppState>().librarySort) == 'letter';
    final checking = [
      for (final w in rows)
        if (_selectable(w)) w
    ];
    final allOn =
        checking.isNotEmpty && checking.every((w) => _selection[w.id] ?? false);
    final open = !_collapsed.contains(key);
    final title = byLetter ? (key == '#' ? '其他' : key) : rows.first.tierLabel;
    final count = _onlyWeak ? rows.length : (_gcounts[key] ?? rows.length);
    return Container(
      key: _headerAnchor.putIfAbsent(key, () => GlobalKey()),
      height: 46,
      color: context.k.nPanel1,
      child: InkWell(
        onTap: () => _toggleGroup(key),
        child: Row(children: [
          const SizedBox(width: 8),
          RingCheck(
            size: 24,
            selected: allOn,
            enabled: checking.isNotEmpty,
            onTap: () => setState(() {
              for (final w in checking) {
                if (allOn) {
                  _selection.remove(w.id);
                } else {
                  _selection[w.id] = true;
                }
              }
            }),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.k.g700)),
          ),
          Text('$count',
              style: TextStyle(fontSize: 13.5, color: context.k.nFaint2)),
          Icon(open ? Icons.expand_less : Icons.expand_more,
              size: 20, color: context.k.nFaint2),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }

  Widget _wordRow(WordCard w, {String? hint}) => WordTile(
        card: w,
        book: widget.book,
        highlightQuery: _query.isNotEmpty ? _query : null,
        selectMode: true,
        chevron: true,

        markNotEnrolled: hint != null || _scope != 'unselected',

        selectable: true,
        member: _enrolledOf(w),
        selected: _selection[w.id] ?? false,
        hint: hint,
        strength: strengthOf(_levels, w.id),
        enrolled: _enrolledOf(w),
        onSelectTap: () => _toggleCheck(w),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: w.id))),
        onLongPress: () => _togglePlan(w),
      );

  void _toggleCheck(WordCard w) {
    setState(() {

      _pickMode = _PickMode.none;

      if (_selection.remove(w.id) != true) _selection[w.id] = true;
    });
  }

  void _toggleSearch() {
    if (_searchOpen) {
      _searchCtl.clear();

      _autoFill = true;
      setState(() {
        _searchOpen = false;
        _query = '';
        _results = [];
        _searching = false;
      });
    } else {
      setState(() => _searchOpen = true);
    }
  }

  int _removeCount() {
    final byId = {
      for (final w in _words) w.id: w,
      for (final w in _results) w.id: w,
    };
    var n = 0;
    for (final id in _selection.keys) {
      final w = byId[id];
      if (w != null && _enrolledOf(w)) n++;
    }
    return n;
  }

  Widget _sheetCell(BuildContext ctx, String label, String value,
      {bool enabled = true, bool danger = false, bool highlight = false}) {
    return GestureDetector(

      onTap: enabled ? () => Navigator.pop(ctx, value) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: highlight ? context.k.catTint : null,
          border: Border.all(
            color: highlight
                ? context.k.catMid
                : (enabled ? context.k.g300 : context.k.g200),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w500 : FontWeight.w400,
              color: !enabled
                  ? context.k.g400
                  : danger
                      ? context.k.redDeep
                      : highlight
                          ? context.k.catDeep
                          : context.k.g800,
            )),
      ),
    );
  }

  Future<void> _openMoreSheet() async {
    final sort = context.read<AppState>().librarySort;
    final nRemove = _removeCount();
    final canSelAll = _selectableRows().isNotEmpty;
    final canSelEnrolled = _enrolledVisibleRows().isNotEmpty;
    final hasSel = _selection.isNotEmpty;
    final hasOrder = widget.book.order.isNotEmpty;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.k.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 10),
              Row(children: [
                for (final m in const [
                  MapEntry('rank', '语料排名 ↓'),
                  MapEntry('rankDesc', '语料排名 ↑'),
                  MapEntry('alpha', 'A→Z'),
                  MapEntry('alphaDesc', 'Z→A'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, m.key),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: sort == m.key ? context.k.catTint : null,
                          border: Border.all(
                            color: sort == m.key
                                ? context.k.catMid
                                : context.k.g300,
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(m.value,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: sort == m.key
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: sort == m.key
                                  ? context.k.catDeep
                                  : context.k.g700,
                            )),
                      ),
                    ),
                  ),
              ]),
              if (hasOrder) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                      color: context.k.catTint,
                      borderRadius: BorderRadius.circular(5)),
                  child: Text('此词书有固定次序：按「词频」排序时按自身顺序展示',
                      style: TextStyle(fontSize: 11, color: context.k.catMid)),
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _sheetCell(
                      ctx,
                      context.read<AppState>().book?.id == widget.book.id
                          ? '取消学习目标'
                          : '设为学习目标',
                      'target',
                      highlight:
                          context.read<AppState>().book?.id != widget.book.id),
                ),
                Expanded(
                  child: _sheetCell(
                      ctx, _onlyWeak ? '显示全部词汇' : '只看没掌握的', 'weak',
                      highlight: _onlyWeak),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child:
                        _sheetCell(ctx, '全选未加入', 'selAll', enabled: canSelAll)),
                Expanded(
                    child: _sheetCell(ctx, '全选已加入', 'selEnrolled',
                        enabled: canSelEnrolled)),
                Expanded(
                    child:
                        _sheetCell(ctx, '清空勾选', 'selClear', enabled: hasSel)),
              ]),
              const Divider(height: 14, thickness: 0.5),
              Row(children: [
                Expanded(
                    child: _sheetCell(ctx, '移出勾选（$nRemove）', 'rmChecked',
                        enabled: nRemove > 0, danger: true)),
                Expanded(
                    child: _sheetCell(ctx, '全部加入本词库', 'all', danger: true)),
                Expanded(
                    child: _sheetCell(ctx, '全部移出本词库', 'none', danger: true)),
              ]),
              const SizedBox(height: 4),
              Text('带「全部」的两项与移出会影响整库成员，点完还有二次确认',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: context.k.nFaint2)),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await _onMenu(picked);
  }

  Future<void> _onMenu(String v) async {
    if (AppDb.kSortModes.contains(v)) {
      await context.read<AppState>().setLibrarySort(v);
      if (!mounted) return;

      setState(_collapsed.clear);
      await _load();
      return;
    }
    switch (v) {
      case 'target':

        final app = context.read<AppState>();
        if (app.book?.id == widget.book.id) {
          await requestClearTarget(context, app);
        } else {
          await requestSetTarget(context, app, widget.book);
        }
        return;
      case 'selAll':

        setState(() {
          _pickMode = _PickMode.none;
          for (final w in _selectableRows()) {
            _selection[w.id] = true;
          }
        });
      case 'selEnrolled':

        setState(() {
          _pickMode = _PickMode.none;
          for (final w in _enrolledVisibleRows()) {
            _selection[w.id] = true;
          }
        });
      case 'selClear':
        setState(() {
          _pickMode = _PickMode.none;
          _selection.clear();
        });
      case 'rmChecked':
        await _removeChecked();
      default:
        await _bulk(v);
    }
  }

  List<WordCard> _enrolledVisibleRows() => [
        for (final w in (_query.isNotEmpty ? _results : _visibleRows()))
          if (_enrolledOf(w)) w
      ];

  Future<void> _removeChecked() async {
    final app = context.read<AppState>();
    final byId = {
      for (final w in _words) w.id: w,
      for (final w in _results) w.id: w,
    };
    final ids = [
      for (final id in _selection.keys)
        if (byId[id] == null || _enrolledOf(byId[id]!)) id
    ];
    if (ids.isEmpty) {
      _showNotice('勾选里没有已加入记忆的词（没加入的直接点绿钮加入即可）');
      return;
    }
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('把勾选的 ${ids.length} 个词移出记忆？'),
        content: const Text('这些词将不再进入学习队列。已学过的进度会保留，'
            '重新加入就能接着学。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('移出')),
        ],
      ),
    );
    if (r != true) return;
    if (!mounted) return;
    await app.forget(ids);
    if (!mounted) return;
    _showNotice('已把 ${ids.length} 个词移出记忆（进度保留，加回来接着学）');
    setState(() {
      _pickMode = _PickMode.none;
      _selection.clear();
      _loading = true;
    });
    await _load();
  }

  Widget _bottomBar(int nAdd, int nRemove) {
    final k = context.k;
    final count = _selection.length;
    final quotaText = _remainQuota > 0 ? '今日还能学 $_remainQuota 张' : '今日卡量已满';
    final summary = count == 0 ? '还没勾选 · $quotaText' : '已勾选 $count 个 · $quotaText';
    final removeOnly = nAdd == 0 && nRemove > 0;
    final both = nAdd > 0 && nRemove > 0;

    Widget modeTab(String label, _PickMode mode, VoidCallback onTap) {
      final on = _pickMode == mode;
      return Expanded(
        child: SizedBox(
          height: 34,
          child: FilledButton(
            key: Key('wordlist.mode.${mode.name}'),
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: on ? k.surface : Colors.transparent,
              foregroundColor: on ? k.text : k.nT2,
              side: on
                  ? BorderSide(color: k.line, width: 0.5)
                  : BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: k.surface,
          border: Border(top: BorderSide(color: k.line, width: 0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Text(summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: k.nT2)),
            ),
            if (count > 0)
              GestureDetector(
                key: const Key('wordlist.clear'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _selection.clear();
                  _pickMode = _PickMode.none;
                }),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
                  child: Text('清空',
                      style: TextStyle(fontSize: 11, color: k.deep)),
                ),
              ),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
              flex: 10,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: k.nPanel3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  modeTab('顺选', _PickMode.sequential, _sequentialPick),
                  const SizedBox(width: 2),
                  modeTab('随机', _PickMode.random, _randomPick),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 11,
              child: SizedBox(
                height: 44,
                child: both
                    ? Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: FilledButton(
                                key: const Key('wordlist.addBtn'),
                                onPressed: () => _applySelection(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: kSpeakGreen,
                                  foregroundColor: k.onbrand,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                ),
                                child: Text('加入 $nAdd',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                key: const Key('wordlist.removeBtn'),
                                onPressed: () => _removeChecked(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: k.danger,
                                  side: BorderSide(color: k.danger),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6),
                                ),
                                child: Text('移出 $nRemove',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      )
                    : FilledButton(
                        key: Key(removeOnly
                            ? 'wordlist.removeBtn'
                            : 'wordlist.addBtn'),
                        onPressed: removeOnly
                            ? () => _removeChecked()
                            : (nAdd == 0 ? null : () => _applySelection()),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              removeOnly ? k.danger : kSpeakGreen,
                          foregroundColor: k.onbrand,
                          disabledBackgroundColor:
                              kSpeakGreen.withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                            removeOnly ? '移出记忆 $nRemove' : '加入记忆 $nAdd',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _sequentialPick() async {
    if (_pickMode == _PickMode.sequential) {
      setState(() {
        _pickMode = _PickMode.none;
        _selection.clear();
      });
      _showNotice('已取消顺选，勾选已清空');
      return;
    }
    final app = context.read<AppState>();
    final ids = await app.db.selectableIdsByFilter(widget.book.filter,
        limit: _pickCount,
        sort: app.librarySort,
        exclude: const []);
    if (!mounted) return;
    if (ids.isEmpty) {
      setState(() {
        _pickMode = _PickMode.none;
        _selection.clear();
      });
      _showNotice('这个范围里已经没有可勾选的词了（剩下的都已经在记忆里了）');
      return;
    }
    setState(() {
      _pickMode = _PickMode.sequential;
      _selection
        ..clear()
        ..addAll({for (final id in ids) id: true});
    });
    _showNotice('已按当前顺序勾上 ${ids.length} 个词，'
        '点右下「加入记忆」确认${_remainQuota > 0 ? '（今日还能学 $_remainQuota 张）' : '（今日卡量已满）'}'
        '；再点「顺选」取消');
  }

  int get _remainQuota => context.read<AppState>().dailyQuota - _todayDone;

  int get _pickCount => _remainQuota > 0 ? _remainQuota : 100;

  Future<void> _randomPick() async {
    if (_pickMode == _PickMode.random) {
      setState(() {
        _pickMode = _PickMode.none;
        _selection.clear();
      });
      _showNotice('已取消随机，勾选已清空');
      return;
    }
    final app = context.read<AppState>();
    final ids = await app.db.randomSelectableIds(widget.book.filter, _pickCount,
        exclude: const []);
    if (!mounted) return;
    if (ids.isEmpty) {
      setState(() {
        _pickMode = _PickMode.none;
        _selection.clear();
      });
      _showNotice('这个范围里已经没有可勾选的词了（剩下的都已经在记忆里了）');
      return;
    }
    setState(() {
      _pickMode = _PickMode.random;
      _selection
        ..clear()
        ..addAll({for (final id in ids) id: true});
    });
    _showNotice('已随机勾上 ${ids.length} 个词，点右下「加入记忆」确认'
        '${_remainQuota > 0 ? '（今日还能学 $_remainQuota 张）' : '（今日卡量已用完，明天接着学）'}'
        '；再点「随机」取消');
  }

  Future<void> _togglePlan(WordCard w) async {
    final app = context.read<AppState>();
    final wasEnrolled = _enrolledOf(w);
    if (wasEnrolled) {
      await app.forget([w.id]);
    } else {
      await app.remember([w.id]);
    }
    if (!mounted) return;
    setState(() {
      if (wasEnrolled) {
        _dropped.add(w.id);
        _planned.remove(w.id);
      } else {
        _dropped.remove(w.id);
        _planned.add(w.id);
        _selection.remove(w.id);
      }
    });
    _showNotice(
        wasEnrolled ? '「${w.word}」已移出记忆，不再进入学习队列（进度保留）' : '「${w.word}」已加入记忆');
  }

  bool _enrolledOf(WordCard w) => wordEnrolled(w.id, w.enabled,
      dropped: _dropped, planned: _planned, levels: _levels);

  bool _selectable(WordCard w) => !_enrolledOf(w);

  Future<void> _applySelection() async {
    final app = context.read<AppState>();
    final byId = {
      for (final w in _words) w.id: w,
      for (final w in _results) w.id: w
    };
    final ids = _selection.keys.where((id) {
      final w = byId[id];

      if (w == null) return true;
      return !_enrolledOf(w);
    }).toList();
    if (ids.isEmpty) {
      if (!mounted) return;
      _showNotice('勾上的都已经在记忆里了');
      return;
    }
    await app.remember(ids);
    if (!mounted) return;
    _showNotice('已把 ${ids.length} 个词加入记忆，会排进下一组学习队列');
    setState(() {
      _pickMode = _PickMode.none;
      _selection.clear();
      _loading = true;
    });
    await _load();
  }

  Future<void> _bulk(String action) async {
    final app = context.read<AppState>();
    if (action == 'weak') {
      setState(() {
        _onlyWeak = !_onlyWeak;
        _loading = true;
      });
      await _load();
      return;
    }

    final join = action == 'all';

    if (!await _confirmBulk(join)) return;
    if (!mounted) return;
    final n = join
        ? await app.db.planByFilter(widget.book.filter)
        : await app.db.unenrollByFilter(widget.book.filter);
    if (!mounted) return;
    _showNotice(join ? '已把本词库 $n 个未加入的词加入记忆' : '已把本词库 $n 个词移出记忆（进度保留，加回来接着学）');
    setState(() {
      _loading = true;
      _pickMode = _PickMode.none;
      _selection.clear();
    });
    await _load();
  }

  Future<bool> _confirmBulk(bool join) async {
    final scope = widget.book.name;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(join ? '把「$scope」全部加入记忆？' : '把「$scope」全部移出记忆？'),
        content: Text(join
            ? '该范围里所有还没加入记忆的词都会被点名，之后按每天的卡量排队学。'
                '词很多时这会占满后面很多天的队列。'
            : '这些词将不再进入学习队列。已学过的进度会保留，'
                '重新加入就能接着学。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(join ? '全部加入' : '全部移出')),
        ],
      ),
    );
    return r ?? false;
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }
}
