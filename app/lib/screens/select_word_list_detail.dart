part of 'select_screen.dart';

class WordListDetailScreen extends StatefulWidget {
  final int listId;
  final String title;
  const WordListDetailScreen(
      {super.key, required this.listId, required this.title});

  @override
  State<WordListDetailScreen> createState() => _WordListDetailScreenState();
}

class _WordListDetailScreenState extends State<WordListDetailScreen>
    with _PagedScroll<WordListDetailScreen> {
  static const int _pageSize = 200;

  late String _title;
  List<String> _ids = const [];
  final List<WordCard> _words = [];
  int _loaded = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  WordListStat? _stat;

  SrsLevelMap _levels = const {};
  Set<String> _planned = const {};
  final Map<String, bool> _enabledOverride = {};

  final Set<String> _selection = {};
  final Set<String> _collapsed = {};
  bool _managing = false;
  bool _seqActive = false;

  String _filter = 'all';
  String _sort = 'list';
  String _query = '';
  final _ctl = TextEditingController();
  Timer? _searchDebounce;
  int _searchSeq = 0;

  final _scroll = ScrollController();
  String? _notice;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _noticeTimer?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final app = context.read<AppState>();
    final stat = await app.db.wordListStat(widget.listId);
    final raw = await app.db.wordListIds(widget.listId);
    final seen = <String>{};
    final ids = [
      for (final id in raw)
        if (seen.add(id)) id
    ];
    if (!mounted) return;
    setState(() {
      _ids = ids;
      _words.clear();
      _loaded = 0;
      _hasMore = ids.isNotEmpty;
      _levels = const {};
      _planned = const {};
      _enabledOverride.clear();
      _selection.clear();
      _managing = false;
      _seqActive = false;
      _autoFill = true;
      _stat = stat;
      if (stat != null) _title = stat.name;
    });
    if (ids.isNotEmpty) await _loadMore(first: true);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadMore({bool first = false}) async {
    if (_loadingMore || (!_hasMore && !first)) return;
    if (first) {
      _words.clear();
      _loaded = 0;
    }
    setState(() => _loadingMore = true);
    final app = context.read<AppState>();
    final part = _ids.skip(_loaded).take(_pageSize).toList();
    if (part.isEmpty) {
      if (mounted) {
        setState(() {
          _hasMore = false;
          _loadingMore = false;
        });
      }
      return;
    }
    final ws = await app.db.wordsByIds(part);
    final lv = await app.db.srsLevels([for (final w in ws) w.id]);
    final planned = await app.db.plannedIds([for (final w in ws) w.id]);
    if (!mounted) return;
    setState(() {
      _words.addAll(ws);
      _levels = {..._levels, ...lv};
      _planned = {..._planned, ...planned};
      _loaded += part.length;
      _hasMore = _loaded < _ids.length;
      _loadingMore = false;
    });
    _scheduleFill();
  }

  Future<void> _loadAll() async {
    while (mounted && _hasMore) {

      if (_loadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        continue;
      }
      await _loadMore();
    }
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
  double get _pageThreshold => 400;

  @override
  bool get _autoFillBlocked => _query.isNotEmpty;

  bool _enrolledOf(WordCard w) {
    final enabled = _enabledOverride[w.id] ?? w.enabled;
    return wordEnrolled(w.id, enabled, planned: _planned, levels: _levels);
  }

  bool _learnedOf(WordCard w) =>
      _enrolledOf(w) && _levels.containsKey(w.id);

  List<WordCard> get _visible {
    final q = _query.trim().toLowerCase();
    final out = <WordCard>[];
    for (final w in _words) {
      if (q.isNotEmpty &&
          !w.word.toLowerCase().contains(q) &&
          !(w.zh ?? '').toLowerCase().contains(q)) {
        continue;
      }
      switch (_filter) {
        case 'unadded':
          if (_enrolledOf(w)) continue;
        case 'joined':
          if (!_enrolledOf(w)) continue;
        case 'learned':
          if (!_learnedOf(w)) continue;
        default:
          break;
      }
      out.add(w);
    }
    if (_sort == 'alpha') {
      out.sort(
          (a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
    } else if (_sort == 'rank') {
      out.sort((a, b) {
        final ra = a.rank, rb = b.rank;
        if (ra == null && rb == null) return a.word.compareTo(b.word);
        if (ra == null) return 1;
        if (rb == null) return -1;
        final c = ra.compareTo(rb);
        return c != 0 ? c : a.word.compareTo(b.word);
      });
    }
    return out;
  }

  static String _letterKey(String word) {
    if (word.isEmpty) return '#';
    final c = word[0];
    return RegExp(r'[A-Za-z]').hasMatch(c) ? c.toUpperCase() : '#';
  }

  bool _lettersNonDecreasing(List<WordCard> list) {
    String? prev;
    for (final w in list) {
      final k = _letterKey(w.word);
      if (prev != null && k.compareTo(prev) < 0) return false;
      prev = k;
    }
    return true;
  }

  bool get _byLetter =>
      _sort == 'alpha' ||
      (_sort == 'list' && _lettersNonDecreasing(_visible));

  bool get _byTier => _sort == 'rank';

  List<Object> get _entries {
    final list = _visible;
    if (list.isEmpty) return const [];
    if (!_byLetter && !_byTier) return List<Object>.from(list);
    final out = <Object>[];
    String? cur;
    for (final w in list) {
      final key = _byLetter ? _letterKey(w.word) : w.tierLabel;
      if (key != cur) {
        cur = key;
        out.add(key);
      }
      if (!_collapsed.contains(key)) out.add(w);
    }
    return out;
  }

  List<WordCard> _rowsOf(String key) => [
        for (final w in _visible)
          if ((_byLetter ? _letterKey(w.word) : w.tierLabel) == key) w
      ];

  void _onQuery(String v, {bool immediate = false}) {
    _searchDebounce?.cancel();
    final seq = ++_searchSeq;
    Future<void> run() async {
      final q = v.trim();
      if (q.isNotEmpty && _hasMore) await _loadAll();
      if (!mounted || seq != _searchSeq) return;
      setState(() => _query = q);
    }

    if (immediate) {
      run();
    } else {
      _searchDebounce = Timer(const Duration(milliseconds: 250), run);
    }
  }

  Future<void> _openSortSheet() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.k.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('排序方式',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ctx.k.nT2)),
            const SizedBox(height: 4),
            for (final m in const [
              ('list', '词单顺序'),
              ('alpha', '字母 A→Z'),
              ('rank', '语料排名 高→低'),
            ])
              ListTile(
                dense: true,
                title: Text(m.$2, style: const TextStyle(fontSize: 13.5)),
                trailing: _sort == m.$1
                    ? Icon(Icons.check, size: 18, color: ctx.k.deep)
                    : null,
                onTap: () => Navigator.pop(ctx, m.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (v == null || v == _sort || !mounted) return;
    setState(() {
      _sort = v;
      _collapsed.clear();
      _autoFill = true;
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      _seqActive = false;
      if (!_selection.remove(id)) _selection.add(id);
    });
  }

  void _toggleGroupSel(List<WordCard> rows) {
    if (rows.isEmpty) return;
    final allOn = rows.every((w) => _selection.contains(w.id));
    setState(() {
      _seqActive = false;
      for (final w in rows) {
        if (allOn) {
          _selection.remove(w.id);
        } else {
          _selection.add(w.id);
        }
      }
    });
  }

  Future<void> _selectAll() async {
    if (_hasMore) await _loadAll();
    if (!mounted) return;
    setState(() {
      _seqActive = false;
      _selection
        ..clear()
        ..addAll([for (final w in _visible) w.id]);
    });
  }

  Future<void> _sequentialPick() async {
    if (_seqActive) {
      setState(() {
        _selection.clear();
        _seqActive = false;
      });
      _showNotice('已取消顺选，勾选已清空');
      return;
    }
    final app = context.read<AppState>();
    final done = await app.db.todayAnsweredWords();
    final remain = app.dailyQuota - done;
    final n = remain > 0 ? remain : 100;
    while (_hasMore) {
      if (_loadingMore) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        continue;
      }
      final left = _visible.where((w) => !_enrolledOf(w)).length;
      if (left >= n) break;
      await _loadMore();
    }
    if (!mounted) return;
    final ids = [
      for (final w in _visible)
        if (!_enrolledOf(w)) w.id
    ].take(n).toList();
    if (ids.isEmpty) {
      _showNotice('当前范围里没有可加入记忆的词');
      return;
    }
    setState(() {
      _selection
        ..clear()
        ..addAll(ids);
      _seqActive = true;
    });
    _showNotice('已按当前顺序勾上 ${ids.length} 个词，点「加入记忆」确认');
  }

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
      _enabledOverride[w.id] = !was;
      _planned = was
          ? ({..._planned}..remove(w.id))
          : ({..._planned}..add(w.id));
    });
    _showNotice(was
        ? '「${w.word}」已移出记忆，进度保留'
        : '「${w.word}」已加入记忆');
    await _refreshStat();
  }

  Future<void> _refreshStat() async {
    final s = await context.read<AppState>().db.wordListStat(widget.listId);
    if (!mounted) return;
    if (s == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _stat = s;
      _title = s.name;
    });
  }

  Future<void> _addWords() async {
    final picked = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
          builder: (_) => WordPickScreen(existingIds: _ids.toSet())),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final app = context.read<AppState>();
    await app.db.updateWordListIds(widget.listId, [..._ids, ...picked]);
    if (!mounted) return;
    _showNotice('已添加 ${picked.length} 个词');
    await _load();
  }

  Future<void> _removeSelected() async {
    final ids = _selection.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('把勾选的 ${ids.length} 个词移出词单？'),
        content: const Text('只动这张清单，不影响学习进度或记忆状态。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移出',
                  style: TextStyle(color: Color(0xFFD96A5A)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final drop = ids.toSet();
    final remain = [
      for (final id in _ids)
        if (!drop.contains(id)) id
    ];
    await context.read<AppState>().db.updateWordListIds(widget.listId, remain);
    if (!mounted) return;
    _showNotice('已把 ${ids.length} 个词移出词单（不影响学习进度）');
    await _load();
  }

  Future<void> _addSelected() async {
    final byId = {for (final w in _words) w.id: w};
    final ids = [
      for (final id in _selection)
        if (byId[id] != null && !_enrolledOf(byId[id]!)) id
    ];
    if (ids.isEmpty) {
      _showNotice('勾选里没有还没加入记忆的词');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('把这 ${ids.length} 个词加入记忆？'),
        content: const Text('加入后按每天的卡量排队，不会一次塞进今天的学习。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('加入记忆')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().remember(ids);
    if (!mounted) return;
    setState(() {
      for (final id in ids) {
        _enabledOverride[id] = true;
      }
      _planned = {..._planned, ...ids};
      _selection.clear();
      _managing = false;
    });
    _showNotice('已加入 ${ids.length} 个词，按每天的卡量排队');
    await _refreshStat();
  }

  void _showNotice(String msg) {
    _noticeTimer?.cancel();
    setState(() => _notice = msg);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final entries = _entries;
    final stat = _stat;
    final total = stat?.count ?? _ids.length;
    final joined = stat?.joined ?? 0;
    final learned = stat?.learned ?? 0;
    final unadded = (total - joined).clamp(0, total);
    final byId = {for (final w in _words) w.id: w};
    final nAdd = [
      for (final id in _selection)
        if (byId[id] != null && !_enrolledOf(byId[id]!)) id
    ].length;
    _scheduleFill();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(_title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: k.tint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$total',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: k.deep)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '词单管理',
            onPressed: () async {
              final r = await showWordListActionsSheet(
                context,
                db: context.read<AppState>().db,
                id: widget.listId,
                name: _title,
              );
              if (!mounted || !context.mounted) return;
              if (r == WordListActionOutcome.deleted) {
                Navigator.pop(context);
              } else if (r == WordListActionOutcome.changed) {
                await _load();
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (_managing)
                _selectionBar()
              else ...[
                _summaryCard(total, joined, learned, unadded),
                _searchBar(),
              ],
              _filterRow(total, joined, learned, unadded),
              Expanded(
                child: _ids.isEmpty
                    ? _emptyView(
                        title: '这个词单还是空的',
                        desc: '把想学的词先收进来，再决定什么时候加入记忆。',
                        action: '添加单词',
                        onAction: _addWords,
                      )
                    : entries.isEmpty
                        ? _emptyView(
                            title: _query.isEmpty && _filter == 'all'
                                ? '词单里的词都不在词库了'
                                : '没有匹配的词',
                            desc: _query.isEmpty && _filter == 'all'
                                ? '这些 id 可能来自旧版本或被删掉的词。'
                                : '换个关键词或筛选条件试试。',
                            action: '清除筛选',
                            onAction: () {
                              _ctl.clear();
                              setState(() {
                                _query = '';
                                _filter = 'all';
                              });
                            },
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: entries.length,
                            itemBuilder: (ctx, i) {
                              final e = entries[i];
                              if (e is String) {
                                return _groupHead(e, _rowsOf(e));
                              }
                              final w = e as WordCard;
                              final first =
                                  i == 0 || entries[i - 1] is String;
                              final last = i == entries.length - 1 ||
                                  entries[i + 1] is String;
                              return _rowShell(
                                first: first,
                                last: last,
                                child: _wordRow(w),
                              );
                            },
                          ),
              ),
              _noticeBar(),
              _bottomBar(nAdd),
            ]),
    );
  }

  Widget _summaryCard(int total, int joined, int learned, int unadded) {
    final k = context.k;
    final joinedNotLearned = (joined - learned).clamp(0, joined);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: k.line, width: 0.5),
        boxShadow: kCardShadow(context),
      ),
      child: Column(children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$total',
                style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('词 · 待学清单',
                  style: TextStyle(fontSize: 11, color: k.nT3)),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(TextSpan(
                  text: '$joined',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: k.deep),
                  children: [
                    TextSpan(
                        text: ' 已加入',
                        style: TextStyle(
                            fontSize: 11, color: k.nT2, fontWeight: FontWeight.w400)),
                  ],
                )),
                const SizedBox(height: 2),
                Text('$learned 已学 · $unadded 未加入',
                    style: TextStyle(fontSize: 10.5, color: k.nT3)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final lw = total == 0 ? 0.0 : w * learned / total;
          final jw = total == 0
              ? 0.0
              : w * joinedNotLearned / total;
          return ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: k.nPanel3)),
                if (lw > 0)
                  Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: lw,
                      child: ColoredBox(color: k.deep)),
                if (jw > 0)
                  Positioned(
                      left: lw,
                      top: 0,
                      bottom: 0,
                      width: jw,
                      child: ColoredBox(color: k.brand)),
              ]),
            ),
          );
        }),
        const SizedBox(height: 9),
        Row(children: [
          _legend(k.deep, '已学 $learned'),
          const SizedBox(width: 14),
          _legend(k.brand, '已加入未学 $joinedNotLearned'),
          const SizedBox(width: 14),
          _legend(k.nFaint2.withValues(alpha: 0.45), '未加入 $unadded'),
        ]),
      ]),
    );
  }

  Widget _legend(Color color, String text) => Row(children: [
        Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(fontSize: 10, color: context.k.nT3)),
      ]);

  Widget _searchBar() {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: k.line, width: 0.5),
        ),
        child: TextField(
          controller: _ctl,
          textInputAction: TextInputAction.search,
          onChanged: _onQuery,
          onSubmitted: (v) => _onQuery(v, immediate: true),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: '在词单里搜索',
            hintStyle: TextStyle(fontSize: 12.5, color: k.nFaint2),
            prefixIcon: Icon(Icons.search, size: 18, color: k.nFaint2),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 44, minHeight: 44),
            suffixIcon: _ctl.text.isEmpty
                ? null
                : GestureDetector(
                    onTap: () {
                      _ctl.clear();
                      _onQuery('', immediate: true);
                    },
                    child: Icon(Icons.close, size: 16, color: k.nFaint2),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _selectionBar() {
    final k = context.k;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: k.tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCDE6D9), width: 0.5),
      ),
      child: Row(children: [
        GestureDetector(
          key: const Key('wordlist.manage.close'),
          onTap: () => setState(() {
            _managing = false;
            _selection.clear();
            _seqActive = false;
          }),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 20,
            height: 20,
            decoration:
                const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('×',
                style: TextStyle(fontSize: 13, color: k.deep)),
          ),
        ),
        const SizedBox(width: 8),
        Text('已选 ${_selection.length} 个',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: k.deep)),
        const Spacer(),
        GestureDetector(
          key: const Key('wordlist.selectAll'),
          onTap: _selectAll,
          behavior: HitTestBehavior.opaque,
          child: Text('全选当前 ${_visible.length} 个',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: k.deep)),
        ),
      ]),
    );
  }

  Widget _filterRow(int total, int joined, int learned, int unadded) {
    final k = context.k;
    Widget chip(String label, String value, int n) {
      final on = _filter == value;
      return GestureDetector(
        key: Key('wordlist.filter-$value'),
        onTap: () => setState(() => _filter = value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? k.tint : k.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: on ? k.brand : k.g200,
                width: on ? 1 : 0.5),
          ),
          child: Text('$label $n',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  color: on ? k.deep : k.nT2)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip('全部', 'all', total),
              const SizedBox(width: 6),
              chip('未加入', 'unadded', unadded),
              const SizedBox(width: 6),
              chip('已加入', 'joined', joined),
              const SizedBox(width: 6),
              chip('已学', 'learned', learned),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          key: const Key('wordlist.sort'),
          onTap: _openSortSheet,
          behavior: HitTestBehavior.opaque,
          child: Row(children: [
            Text(_sort == 'list'
                ? '词单顺序'
                : _sort == 'alpha'
                    ? '字母'
                    : '语料排名',
                style: TextStyle(fontSize: 10.5, color: k.nT3)),
            const SizedBox(width: 2),
            Icon(Icons.unfold_more, size: 13, color: k.nFaint2),
          ]),
        ),
      ]),
    );
  }

  Widget _groupHead(String key, List<WordCard> rows) {
    final k = context.k;
    final title = _byLetter ? (key == '#' ? '其他' : key) : key;
    final open = !_collapsed.contains(key);
    final allOn =
        rows.isNotEmpty && rows.every((w) => _selection.contains(w.id));
    return GestureDetector(
      onTap: () => setState(() {
        if (_collapsed.remove(key)) {
          _autoFill = true;
        } else {
          _collapsed.add(key);
          _autoFill = false;
        }
      }),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 42,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: k.nPanel1,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          if (_managing) ...[
            RingCheck(
              selected: allOn,
              size: 22,
              onTap: () => _toggleGroupSel(rows),
            ),
            const SizedBox(width: 4),
          ],
          Icon(open ? Icons.expand_more : Icons.chevron_right,
              size: 18, color: k.nFaint2),
          const SizedBox(width: 3),
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: k.g700)),
          const SizedBox(width: 6),
          Text('${rows.length} 词',
              style: TextStyle(fontSize: 10.5, color: k.nFaint2)),
          const Spacer(),
          Text(open ? '折叠' : '展开',
              style: TextStyle(fontSize: 10, color: k.nFaint2)),
        ]),
      ),
    );
  }

  Widget _rowShell(
      {required bool first, required bool last, required Widget child}) {

    return Material(
      color: context.k.surface,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(first ? 14 : 0),
        bottom: Radius.circular(last ? 14 : 0),
      ),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: context.k.line, width: 0.5)),
        ),
        child: child,
      ),
    );
  }

  Widget _wordRow(WordCard w) {
    final enrolled = _enrolledOf(w);
    return WordTile(
      key: Key('wordlist.word-${w.id}'),
      card: w,
      book: context.read<AppState>().book,
      highlightQuery: _query.isNotEmpty ? _query : null,
      strength: strengthOf(_levels, w.id),
      enrolled: enrolled,
      selectMode: _managing,
      selected: _selection.contains(w.id),
      member: enrolled,
      selectable: true,
      onSelectTap: () => _toggleSelection(w.id),
      onTap: () {
        if (_managing) {
          _toggleSelection(w.id);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: w.id)),
        ).then((_) {

          if (mounted) _load();
        });
      },
      onLongPress: () {
        if (_managing) {
          _toggleSelection(w.id);
        } else {
          _togglePlan(w);
        }
      },
      onTogglePlan: _managing ? null : () => _togglePlan(w),
    );
  }

  Widget _emptyView({
    required String title,
    required String desc,
    required String action,
    required VoidCallback onAction,
  }) {
    final k = context.k;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: k.tint, borderRadius: BorderRadius.circular(24)),
              child: Icon(Icons.playlist_add_outlined,
                  size: 34, color: k.deep),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(desc,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: k.nT3, height: 1.6)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: k.brand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: Text(action,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
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
              key: const Key('wordlist.notice'),
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
                            fontSize: 11.5,
                            color: Colors.white,
                            height: 1.3)),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _bottomBar(int nAdd) {
    final k = context.k;
    if (!_managing) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: k.surface,
            border: Border(top: BorderSide(color: k.line, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _managing = true;
                  _selection.clear();
                  _seqActive = false;
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: k.nT1,
                  side: BorderSide(color: k.g300, width: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: const Text('管理', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: _addWords,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('添加单词',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: k.onbrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: k.surface,
          border: Border(top: BorderSide(color: k.line, width: 0.5)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
                '加入记忆会按每天的卡量排队；移出词单只动清单，不动学习进度。',
                style: TextStyle(fontSize: 9.5, color: k.nT3)),
          ),
          Row(children: [
            SizedBox(
              height: 40,
              width: 70,
              child: FilledButton(
                onPressed: _sequentialPick,
                style: FilledButton.styleFrom(
                  backgroundColor: k.nPanel3,
                  foregroundColor: k.deep,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                ),
                child: const Text('顺选', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: _selection.isEmpty ? null : _removeSelected,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD96A5A),
                    side: BorderSide(
                        color: _selection.isEmpty
                            ? k.g300
                            : const Color(0xFFEFCFCB)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  child: Text('移出词单 ${_selection.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: nAdd == 0 ? null : _addSelected,
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: k.onbrand,
                    disabledBackgroundColor:
                        k.brand.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                  child: Text('加入记忆 $nAdd',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
