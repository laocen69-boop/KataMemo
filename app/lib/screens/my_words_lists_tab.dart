part of 'my_words_screen.dart';

class WordListsTab extends StatefulWidget {

  final VoidCallback? onChanged;

  const WordListsTab({super.key, this.onChanged});

  @override
  State<WordListsTab> createState() => _WordListsTabState();
}

class _WordListsTabState extends State<WordListsTab> {
  List<WordListStat> _lists = const [];
  bool _loading = true;
  String _query = '';
  final _ctl = TextEditingController();
  String _sort = 'recent';
  bool _hintDismissed = false;
  int? _swipeOpenId;

  @override
  void initState() {
    super.initState();
    _loadHint();
    _reload();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _loadHint() async {
    final app = context.read<AppState>();
    final v = await app.db.metaGet('word_list_swipe_hint');
    if (!mounted) return;
    setState(() => _hintDismissed = v == '1');
  }

  Future<void> _dismissHint() async {
    final app = context.read<AppState>();
    await app.db.metaSet('word_list_swipe_hint', '1');
    if (!mounted) return;
    setState(() => _hintDismissed = true);
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    final ls = await app.db.wordListStats();
    if (!mounted) return;
    setState(() {
      _lists = ls;
      _loading = false;
    });
    widget.onChanged?.call();
  }

  List<WordListStat> get _visible {
    final q = _query.trim().toLowerCase();
    final out = [
      for (final l in _lists)
        if (q.isEmpty || l.name.toLowerCase().contains(q)) l
    ];
    switch (_sort) {
      case 'name':
        out.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'count':
        out.sort((a, b) {
          final c = b.count.compareTo(a.count);
          return c != 0
              ? c
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      default:
        break;
    }
    return out;
  }

  int get _totalWords => _lists.fold(0, (a, b) => a + b.count);

  Future<void> _openSort() async {
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
            Text('词单排序',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ctx.k.nT2)),
            const SizedBox(height: 4),
            for (final m in const [
              ('recent', '最近创建'),
              ('name', '名称 A→Z'),
              ('count', '词数 多→少'),
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
    setState(() => _sort = v);
  }

  Future<void> _openActions(WordListStat s) async {
    final r = await showWordListActionsSheet(
      context,
      db: context.read<AppState>().db,
      id: s.id,
      name: s.name,
    );
    if (!mounted) return;
    if (r == WordListActionOutcome.changed ||
        r == WordListActionOutcome.deleted) {
      await _reload();
    }
  }

  Future<void> _openDetail(WordListStat s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => WordListDetailScreen(listId: s.id, title: s.name)),
    );
    if (mounted) await _reload();
  }

  Future<void> _createList() async {
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建词单'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.k.alt,
            hintText: '词单名字',
            hintStyle: TextStyle(color: context.k.faint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.brand, width: 1.4),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: ctl.clear, child: const Text('重置')),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('创建')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final app = context.read<AppState>();
    final id = await app.db.createWordList(name, const []);
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2200),
        content: Text('已有叫「$name」的词单，换个名字'),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 1600),
      content: Text('已创建词单「$name」'),
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final visible = _visible;
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          Column(children: [
            if (_lists.isNotEmpty) _searchRow(),
            if (_lists.isNotEmpty) _sectionHead(),
            Expanded(
              child: _lists.isEmpty
                  ? _emptyAll()
                  : visible.isEmpty
                      ? _emptySearch()
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if ((n is ScrollStartNotification ||
                                    n is UserScrollNotification) &&
                                _swipeOpenId != null) {
                              setState(() => _swipeOpenId = null);
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                            child: Container(
                              decoration: BoxDecoration(
                                color: k.surface,
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    Border.all(color: k.line, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                for (var i = 0; i < visible.length; i++) ...[
                                  if (i > 0)
                                    Container(height: 1, color: k.line),
                                  _row(visible[i]),
                                ],
                              ]),
                            ),
                          ),
                        ),
            ),
          ]),
        Positioned(
          right: 18,
          bottom: 30,
          child: GestureDetector(
            key: const Key('wordlist.fab'),
            behavior: HitTestBehavior.opaque,
            onTap: _createList,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: kSpeakGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 28, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchRow() {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
      child: Row(children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: k.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: k.line, width: 0.5),
            ),
            child: TextField(
              controller: _ctl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索词单',
                hintStyle: TextStyle(fontSize: 12.5, color: k.nFaint2),
                prefixIcon: Icon(Icons.search, size: 18, color: k.nFaint2),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                suffixIcon: _ctl.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _ctl.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(Icons.close, size: 16, color: k.nFaint2),
                      ),
              ),
            ),
          ),
        ),
        TextButton(
          key: const Key('wordlist.sort'),
          onPressed: _openSort,
          style: TextButton.styleFrom(foregroundColor: k.deep),
          child: const Text('排序', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  Widget _sectionHead() {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Row(children: [
        Text('${_lists.length} 个词单 · 共 $_totalWords 词',
            style: TextStyle(fontSize: 11.5, color: k.nT3)),
        const Spacer(),
        if (!_hintDismissed)
          Row(children: [
            Icon(Icons.swipe_left, size: 12, color: k.nFaint2),
            const SizedBox(width: 3),
            Text('左滑可管理',
                style: TextStyle(fontSize: 10.5, color: k.nFaint2)),
            GestureDetector(
              key: const Key('wordlist.hint.close'),
              onTap: _dismissHint,
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: k.g300, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Text('×',
                    style: TextStyle(fontSize: 10, color: k.nFaint2)),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _row(WordListStat s) {
    final k = context.k;
    return SwipeRevealRow(
      height: 66,
      enabled: true,
      open: _swipeOpenId == s.id,
      actionWidth: 96,
      actionLabel: '管理',
      actionKey: Key('wordlist.action-${s.id}'),
      onOpenChanged: (open) => setState(() {
        _swipeOpenId = open ? s.id : (_swipeOpenId == s.id ? null : _swipeOpenId);
      }),
      onAction: () {
        setState(() => _swipeOpenId = null);
        _openActions(s);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(s),
        onLongPress: () => _openActions(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(children: [
            Container(
              width: 35,
              height: 35,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: k.tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.name.characters.isEmpty ? '?' : s.name.characters.first,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: k.deep),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                      '${s.count} 词 · ${s.joined} 已加入 · ${s.learned} 已学',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: k.nT3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${s.joined}/${s.count}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: s.joined > 0 ? k.deep : k.nFaint2)),
                const SizedBox(height: 1),
                Text('已加入',
                    style: TextStyle(fontSize: 9.5, color: k.nFaint2)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: k.g400),
          ]),
        ),
      ),
    );
  }

  Widget _emptyAll() {
    final k = context.k;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                  color: k.tint, borderRadius: BorderRadius.circular(26)),
              child: Icon(Icons.playlist_add_outlined,
                  size: 36, color: k.deep),
            ),
            const SizedBox(height: 18),
            const Text('还没有词单',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('把想学的词先收进一张清单，\n再决定什么时候把它们加入记忆。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: k.nT3, height: 1.7)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: k.brand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: const Text('去词库挑词',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                onPressed: _createList,
                style: OutlinedButton.styleFrom(
                  foregroundColor: k.nT1,
                  side: BorderSide(color: k.g300, width: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                child: const Text('新建空词单',
                    style: TextStyle(fontSize: 13.5)),
              ),
            ),
            const SizedBox(height: 12),
            Text('词单只是待学清单\n不影响任何已经学过的进度',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: k.nFaint2, height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _emptySearch() {
    final k = context.k;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('没有匹配「$_query」的词单',
              style: TextStyle(fontSize: 13, color: k.nT2)),
          TextButton(
            onPressed: () {
              _ctl.clear();
              setState(() => _query = '');
            },
            child: const Text('清除搜索'),
          ),
        ],
      ),
    );
  }
}
