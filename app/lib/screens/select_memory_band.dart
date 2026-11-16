part of 'select_screen.dart';

class MemoryBandScreen extends StatefulWidget {

  final int band;

  final int count;

  final Map<String, dynamic>? filter;

  final String scope;

  const MemoryBandScreen(
      {super.key,
      required this.band,
      required this.count,
      this.filter,
      this.scope = '全部词汇'});

  @override
  State<MemoryBandScreen> createState() => _MemoryBandScreenState();
}

class _MemoryBandScreenState extends State<MemoryBandScreen>
    with _PagedScroll<MemoryBandScreen> {
  static const _pageStep = 200;

  List<WordCard> _words = [];
  SrsLevelMap _levels = {};
  Set<String> _planned = {};

  final Set<String> _dropped = {};

  bool _loading = true;
  bool _hasMore = true;
  bool _loadingMore = false;
  final _scroll = ScrollController();

  static const _bandNote = [
    '记住 180 天以上 —— 半年不碰也还记得',
    '记住 60~180 天',
    '记住 7~60 天',
    '记住不到 7 天',
    '已加入记忆，但一次都还没学过',
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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

  Future<void> _load() async {
    final app = context.read<AppState>();
    final page = await app.db
        .wordsByBand(widget.band, limit: _pageStep, filter: widget.filter);
    final lv = await loadLevels(app.db, page);
    final planned = await app.db.plannedIds([for (final w in page) w.id]);
    if (!mounted) return;
    setState(() {
      _words = page;
      _levels = lv;
      _planned = planned;
      _dropped.clear();
      _loading = false;
      _hasMore = page.length >= _pageStep;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final app = context.read<AppState>();
    final more = await app.db.wordsByBand(widget.band,
        limit: _pageStep, offset: _words.length, filter: widget.filter);
    final lv = await loadLevels(app.db, more);
    final planned = await app.db.plannedIds([for (final w in more) w.id]);
    if (!mounted) return;
    setState(() {
      _words = [..._words, ...more];
      _levels = {..._levels, ...lv};
      _planned = {..._planned, ...planned};
      _loadingMore = false;
      _hasMore = more.length >= _pageStep;
    });
  }

  bool _enrolledOf(WordCard w) => wordEnrolled(w.id, w.enabled,
      dropped: _dropped, planned: _planned, levels: _levels);

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
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Text(wasEnrolled
            ? '「${w.word}」已移出记忆，不再进入学习队列（进度保留）'
            : '「${w.word}」已加入记忆')));
  }

  String _footNote() {
    final n = _words.length;
    if (n < widget.count) return '— 已加载最前 $n / ${widget.count} 词 —';
    return '— 共 $n 词 —';
  }

  @override
  Widget build(BuildContext context) {
    final seg = kMemorySegmentsOf(context)[widget.band];
    _scheduleFill();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: seg.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(seg.label),
            const SizedBox(width: 8),

            Expanded(
              child: Text('${widget.count} 词 · ${widget.scope}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                      color: context.k.nFaint2)),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_bandNote[widget.band],
                        style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
                  ),
                ),
                Expanded(
                  child: _words.isEmpty
                      ? Center(
                          child: Text('这一档还没有词',
                              style: TextStyle(
                                  color: context.k.nFaint2, fontSize: 13)),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          itemCount: _words.length + 1,
                          itemBuilder: (ctx, i) {
                            if (i >= _words.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                child: Center(

                                  child: _loadingMore
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : Text(_footNote(),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: context.k.nFaint2)),
                                ),
                              );
                            }
                            final w = _words[i];
                            return WordTile(
                              card: w,
                              selectMode: false,
                              selected: false,
                              strength: strengthOf(_levels, w.id),
                              enrolled: _enrolledOf(w),
                              onTogglePlan: () => _togglePlan(w),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        WordDetailScreen(cardId: w.id)),
                              ),
                              onLongPress: () => _togglePlan(w),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
