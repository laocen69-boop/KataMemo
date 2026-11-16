part of 'select_screen.dart';

class _ChildrenSearchEntry {
  const _ChildrenSearchEntry();
}

class _ChildrenTextEntry {
  final String text;
  const _ChildrenTextEntry(this.text);
}

class _ChildrenEmptyEntry {
  const _ChildrenEmptyEntry();
}

class _ChildrenLabelEntry {
  final String text;
  const _ChildrenLabelEntry(this.text);
}

class BookChildrenScreen extends StatefulWidget {
  final BookNode parent;
  final List<BookNode> children;
  const BookChildrenScreen(
      {super.key, required this.parent, required this.children});

  @override
  State<BookChildrenScreen> createState() => _BookChildrenScreenState();
}

class _BookChildrenScreenState extends State<BookChildrenScreen> {
  Map<String, BookProgress> _prog = {};

  Map<String, List<BookNode>> _kidsByParent = const {};

  int _loadSeq = 0;

  final _topicSearchCtl = TextEditingController();
  String _topicQuery = '';

  String? _swipeOpenId;
  void _closeSwipe() {
    if (_swipeOpenId != null) setState(() => _swipeOpenId = null);
  }

  List<String>? _wordTopics;
  bool _topicSearching = false;

  int _topicSeq = 0;

  bool get _isTopicRoot => widget.parent.id == 'top';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topicSearchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final app = context.read<AppState>();

    final all = await app.repo.loadBooks();
    if (!mounted || seq != _loadSeq) return;
    final kids = <String, List<BookNode>>{};
    for (final b in all) {
      final p = b.parent;
      if (p == null) continue;
      (kids[p] ??= <BookNode>[]).add(b);
    }
    setState(() => _kidsByParent = kids);

    final items = <BookNode>[widget.parent, ...widget.children];
    const chunk = 12;
    for (var i = 0; i < items.length; i += chunk) {
      final end = (i + chunk) > items.length ? items.length : i + chunk;
      final prog = await loadBookProgress(app, items.sublist(i, end));
      if (!mounted || seq != _loadSeq) return;
      setState(() => _prog = {..._prog, ...prog});
    }
  }

  List<BookNode> _kidsOf(String id) => _kidsByParent[id] ?? const [];

  Future<void> _runTopicSearch(String v) async {
    final q = v.trim();
    if (q.isEmpty) {
      _topicSeq++;
      setState(() {
        _topicQuery = '';
        _wordTopics = null;
        _topicSearching = false;
      });
      return;
    }
    final seq = ++_topicSeq;
    setState(() {
      _topicQuery = q;
      _topicSearching = true;
    });
    final app = context.read<AppState>();
    final hits = await app.db.topicsOfWord(q);

    if (!mounted || seq != _topicSeq) return;
    setState(() {
      _wordTopics = hits;
      _topicSearching = false;
    });
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: context.k.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: kCardShadow(context),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(Icons.search, size: 20, color: context.k.t3),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _topicSearchCtl,
                textInputAction: TextInputAction.search,
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 15, color: context.k.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: _isTopicRoot ? '搜卡组 / 单词' : '搜卡组',
                  hintStyle: TextStyle(fontSize: 15, color: context.k.t3),
                ),
              ),
            ),
            if (_topicQuery.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: context.k.t3),
                onPressed: () {
                  _topicSearchCtl.clear();
                  _onSearchChanged('');
                },
              )
            else
              const SizedBox(width: 12),
          ]),
        ),
      );

  void _onSearchChanged(String v) {
    if (_isTopicRoot) {
      _runTopicSearch(v);
    } else {
      setState(() => _topicQuery = v.trim());
    }
  }

  void _openChild(BookNode b) {
    final kids = _kidsOf(b.id);
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => kids.isEmpty
              ? WordListScreen(book: b)
              : BookChildrenScreen(parent: b, children: kids)),
    ).then((_) => _load());
  }

  Widget _childRow(BookNode b, String? currentBookId) {
    final row = BookRow(
      book: b,
      isCurrent: currentBookId == b.id,
      hasChildren: _kidsOf(b.id).isNotEmpty,
      progress: _prog[b.id],
      finished: isBookFinished(_prog[b.id]),
      onTap: () => _openChild(b),
      newStyle: true,
    );
    if (!b.clickable) return row;
    final isTarget = currentBookId == b.id;
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

      },
      child: row,
    );
  }

  Widget _childrenCard(List<BookNode> items, String? currentBookId) {
    if (items.isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: kCardShadow(context),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          color: context.k.surface,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Container(height: 1, color: context.k.line),
                _childRow(items[i], currentBookId),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final currentBookId =
        context.select<AppState, String?>((a) => a.book?.id);

    final q = _topicQuery.toLowerCase();
    final hitTopics =
        (q.isNotEmpty ? (_wordTopics ?? const <String>[]) : const <String>[]);
    final hitSet = hitTopics.toSet();
    final shown = q.isEmpty
        ? widget.children
        : [

            for (final b in widget.children)
              if (hitSet.contains(b.name)) b,

            for (final b in widget.children)
              if (!hitSet.contains(b.name) && b.matchesBookQuery(q)) b,
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.parent.name),
        titleTextStyle: mainAppBarTitleStyle(context),
        actions: [

          if (widget.parent.clickable)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.k.deep),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => WordListScreen(book: widget.parent)),
              ).then((_) => _load()),
              child: const Text('本组全部'),
            ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification || n is UserScrollNotification) {
            _closeSwipe();
          }
          return false;
        },

        child: Builder(builder: (ctx) {
          final entries = <Object>[

            const _ChildrenSearchEntry(),
            if (_isTopicRoot && q.isNotEmpty && _wordTopics != null)
              _ChildrenTextEntry(_wordTopics!.isEmpty
                  ? '没有主题卡组收录「$q」（它可能不在主题轴里）'
                  : '「$q」已收录在以下 ${_wordTopics!.length} 个卡组：'),
            if (q.isNotEmpty && shown.isEmpty && !_topicSearching)
              const _ChildrenEmptyEntry(),

            for (final seg in groupBySegment(shown)) ...[
              if (seg.key.isNotEmpty) _ChildrenLabelEntry(seg.key),
              seg.value,
            ],
          ];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              if (e is _ChildrenSearchEntry) return _searchBar();
              if (e is _ChildrenTextEntry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(e.text,
                      style:
                          TextStyle(fontSize: 12.5, color: context.k.g700)),
                );
              }
              if (e is _ChildrenEmptyEntry) {
                return Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('没有匹配「$q」的卡组',
                        style: TextStyle(color: context.k.nFaint2)),
                  ),
                );
              }
              if (e is _ChildrenLabelEntry) {
                return segmentLabel(context, e.text);
              }
              return _childrenCard(e as List<BookNode>, currentBookId);
            },
          );
        }),
      ),
    );
  }
}
