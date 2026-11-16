part of 'my_words_screen.dart';

class _MyWordsTabState extends State<MyWordsTab> {
  String _query = '';
  final _ctl = TextEditingController();
  List<WordCard> _items = const [];
  bool _loading = true;
  SrsLevelMap _levels = const {};
  Set<String> _planned = const {};

  String _sort = 'created';

  int _total = 0;

  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    final items = await app.db.userWords(q: _query, sort: _sort);
    final total = await app.db.countUserWords();
    final lv = await loadLevels(app.db, items);
    final planned = await app.db.plannedIds([for (final w in items) w.id]);
    if (!mounted) return;
    setState(() {
      _items = items;
      _total = total;
      _truncated = items.length >= 2000;
      _levels = lv;
      _planned = planned;
      _loading = false;
    });
    widget.onChanged?.call();
  }

  String get _sortLabel => switch (_sort) {
        'alpha' => '按词形 A→Z',
        'alphaDesc' => '按词形 Z→A',
        'class' => '按词性',
        _ => '按创建时间',
      };

  Future<void> _openSortSheet() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.k.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text('排序方式',
                  style: TextStyle(fontSize: 12, color: context.k.nT2)),
            ),
            for (final m in const [
              MapEntry('created', '按创建时间（新的在前）'),
              MapEntry('alpha', '按词形 A → Z'),
              MapEntry('alphaDesc', '按词形 Z → A'),
              MapEntry('class', '按词性（同类聚在一起）'),
            ])
              GestureDetector(
                onTap: () => Navigator.pop(ctx, m.key),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: _sort == m.key ? context.k.catTint : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(m.value,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: _sort == m.key
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color:
                                  _sort == m.key ? context.k.catDeep : null)),
                    ),
                    if (_sort == m.key)
                      Icon(Icons.check, size: 17, color: context.k.catMid),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    await _reload();
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
        duration: const Duration(milliseconds: 1600),
        content: Text(was ? '「${w.word}」已移出记忆' : '「${w.word}」已加入记忆，会占今日卡量')));
  }

  Future<void> _openForm({WordCard? existing}) async {
    await openUserWordForm(context, existing: existing);
    if (mounted) await _reload();
  }

  bool _selecting = false;
  final Set<String> _selected = {};

  void _enterSelect(String id) {
    setState(() {
      _selecting = true;
      _selected.add(id);
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);

      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _batchPlan(bool add) async {
    final app = context.read<AppState>();
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (add) {
      await app.remember(ids);
    } else {
      await app.forget(ids);
    }
    if (!mounted) return;
    final n = ids.length;
    _exitSelect();
    await _reload();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1600),
        content: Text(add ? '$n 个词已加入记忆，会占今日卡量' : '$n 个词已移出记忆')));
  }

  Future<void> _batchDelete() async {
    final n = _selected.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 $n 个自建词？'),
        content: const Text('这些词和它们导入的音频会被永久删除，不能撤销。\n'
            '已经在记忆里的进度也会一并消失。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = context.read<AppState>();
    final ids = _selected.toList();

    for (final id in ids) {
      await app.db.deleteUserWord(id);
    }
    if (!mounted) return;
    _exitSelect();
    await _reload();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1600),
        content: Text('已删除 $n 个自建词')));
  }

  Widget _batchBtn(String label, bool? add) {
    final danger = add == null;
    final enabled = _selected.isNotEmpty;
    return GestureDetector(
      onTap: !enabled
          ? null
          : () {
              if (danger) {
                _batchDelete();
              } else {
                _batchPlan(add);
              }
            },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: enabled && !danger && add == true ? context.k.catMid : null,
          border: Border.all(
              color: danger ? context.k.red : context.k.catMid, width: 0.5),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: danger
                    ? context.k.redDeep
                    : (enabled && add == true
                        ? Colors.white
                        : context.k.catDeep))),
      ),
    );
  }

  Widget _batchBar() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: SizedBox(
            height: 46,
            child: Row(children: [
              Text('已选 ${_selected.length} 个',
                  style: TextStyle(fontSize: 12.5, color: context.k.g700)),
              const Spacer(),
              GestureDetector(
                onTap: _exitSelect,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('取消',
                      style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
                ),
              ),
              const SizedBox(width: 6),
              _batchBtn('加入记忆', true),
              const SizedBox(width: 6),
              _batchBtn('移出记忆', false),
              const SizedBox(width: 6),
              _batchBtn('删除', null),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    final app = context.read<AppState>();
    final items = await app.db.userWords(limit: 100000);
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1600),
          content: Text('还没有自建词，没什么可导出的')));
      return;
    }
    final data = <String, Object?>{
      'app': 'KataMemo',
      'kind': 'user_words',
      'exported_at': DateTime.now().toIso8601String(),
      'count': items.length,
      'note': '这里只有文字内容；音频是你导入时的源文件，不在此文件中',
      'words': [
        for (final w in items)
          {
            'word': w.word,
            'zh': w.zh,
            'class': w.wordClass,
            'mnemonic': w.mnemonic,

            'audio': [
              w.audioArdi,
              w.audioGadis,
              w.audioHuman,
            ].whereType<String>().where((a) => a.startsWith('user:')).toList(),
          }
      ],
    };
    String outPath;
    try {
      final dir = await exportBaseDir();
      final out = Directory(p.join(dir.path, 'exports'));
      if (!await out.exists()) await out.create(recursive: true);
      final stamp =
          DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
      final f = File(p.join(out.path, 'katamemo-user-words-$stamp.json'));
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      outPath = f.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 2600),
            content: Text('导出失败：$e')));
      }
      return;
    }
    if (!mounted) return;

    await Clipboard.setData(ClipboardData(text: outPath));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 3600),
        content: Text('已导出 ${items.length} 条，${exportWhereHint(outPath)}')));
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: context.k.g300, width: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: context.k.catMid),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12.5, color: context.k.catDeep)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: WordSearchBar(
                    controller: _ctl,
                    query: _query,
                    onSubmit: (v) async {
                      setState(() => _query = v.trim());
                      await _reload();
                    },
                    onClear: () {
                      _ctl.clear();
                      setState(() => _query = '');
                      _reload();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
                  child: Row(children: [

                    Expanded(
                      child: Text(
                        _query.isEmpty
                            ? (_total == 0 ? '' : '共 $_total 个')
                            : '匹配 ${_items.length} 个',
                        style: TextStyle(fontSize: 12.5, color: context.k.nT2),
                      ),
                    ),
                    if (_total > 0) ...[
                      _toolBtn(
                        icon: Icons.file_upload_outlined,
                        label: '导出',
                        onTap: _export,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _toolBtn(
                      icon: Icons.swap_vert,
                      label: _sortLabel,
                      onTap: _openSortSheet,
                    ),
                  ]),
                ),

                if (_truncated)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: context.k.yellowTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '自建词已达 2000 个上限，列表只显示最新的这些。'
                        '建议用搜索查看，或先清理不用的词。',
                        style:
                            TextStyle(fontSize: 11.5, color: context.k.brown),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _reload,
                    child: _items.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 60),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _query.isEmpty
                                      ? '还没有自建词。\n\n'
                                          '点下面那个绿条建一个，\n'
                                          '建完加进记忆就能学。\n\n'
                                          '想背库里已经有的词？\n'
                                          '去「词库」页点搜索框右边的「筛选」\n'
                                          '挑一批，存成词单（在上一个 Tab）。'
                                      : '没有匹配「$_query」的自建词。\n\n'
                                          '换个关键词，或者\n'
                                          '直接建一个「$_query」。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 13, color: context.k.nT2),
                                ),
                              ),
                            ),
                          ])
                        : ListView.builder(

                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: _items.length,
                            itemBuilder: (ctx, i) {
                              final w = _items[i];
                              return WordTile(
                                card: w,
                                strength: strengthOf(_levels, w.id),
                                enrolled: _enrolledOf(w),

                                selectMode: _selecting,
                                selected: _selected.contains(w.id),
                                onTap: _selecting
                                    ? () => _toggleSelect(w.id)
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => WordDetailScreen(
                                                  cardId: w.id)),
                                        ),

                                onEdit: () => _openForm(existing: w),
                                onLongPress: () => _enterSelect(w.id),
                                onTogglePlan: () => _togglePlan(w),
                              );
                            },
                          ),
                  ),
                ),

                if (_selecting) _batchBar() else _newButton(),
              ],
            ),
    );
  }

  Widget _newButton() {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: GestureDetector(
            onTap: () => _openForm(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kSpeakGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 19, color: Colors.white),
                  SizedBox(width: 6),
                  Text('新建一个词',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
