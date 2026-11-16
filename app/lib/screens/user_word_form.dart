part of 'my_words_screen.dart';

Future<bool?> openUserWordForm(BuildContext context,
    {WordCard? existing, String? initialWord, String? initialZh}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,

    backgroundColor: Theme.of(context).cardColor,
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _UserWordFormSheet(
        existing: existing, initialWord: initialWord, initialZh: initialZh),
  );
}

class _UserWordFormSheet extends StatefulWidget {
  final WordCard? existing;

  final String? initialWord;
  final String? initialZh;
  const _UserWordFormSheet(
      {this.existing, this.initialWord, this.initialZh});

  @override
  State<_UserWordFormSheet> createState() => _UserWordFormSheetState();
}

class _UserWordFormSheetState extends State<_UserWordFormSheet> {
  late final TextEditingController _word;

  late TextEditingController _zh;

  final List<({TextEditingController i, TextEditingController z})> _exs = [];

  final List<UserBlock> _blocks = [];
  List<String> _layout = ['ex', 'mn'];

  final Map<int, List<TextEditingController>> _blkLineCtls = {};
  final Map<int, TextEditingController> _blkTextCtls = {};

  int? _focusBlockIndex;

  late TextEditingController _mn;
  String? _wordClass;
  String? _audio;
  WordCard? _dup;
  bool _busy = false;
  String _error = '';

  WordCard? _liveDup;
  String? _draftId;

  int _probeSeq = 0;
  Timer? _debounce;

  bool get _isEdit => widget.existing != null || _draftId != null;

  String? get _currentId => _draftId ?? widget.existing?.id;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _word = TextEditingController(
        text: e?.word ?? widget.initialWord ?? '');
    _zh = TextEditingController(
        text: e?.zhClean ?? e?.zh ?? widget.initialZh ?? '');
    _mn = TextEditingController(text: e?.mnemonic ?? '');
    _wordClass = e?.wordClass;
    _audio = e?.audio;
    final ex = e?.examples ?? const [];
    for (final x in ex) {

      _exs.add((
        i: TextEditingController(text: x.text),
        z: TextEditingController(text: x.zh ?? ''),
      ));
    }
    if (_exs.isEmpty) _addExample();

    _blocks.addAll(e?.userBlocks ?? const []);
    if ((e?.cardOrder ?? '').isNotEmpty) {
      _layout = e!.cardOrder!.split(',');
    }
    _rebuildBlkCtls();
    _word.addListener(_onWordChanged);
  }

  void _onWordChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _probe);
  }

  Future<void> _probe() async {
    final raw = _word.text.trim();
    final seq = ++_probeSeq;
    if (raw.isEmpty) {
      if (mounted) setState(() => _liveDup = null);
      return;
    }
    final app = context.read<AppState>();
    final hit = await app.db.searchWords(raw);

    if (!mounted || seq != _probeSeq) return;
    final selfId = _currentId;
    setState(() {

      _liveDup = (hit == null || hit.id == selfId) ? null : hit;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _word.removeListener(_onWordChanged);
    _word.dispose();
    _zh.dispose();
    for (final e in _exs) {
      e.i.dispose();
      e.z.dispose();
    }
    _mn.dispose();
    _disposeBlkCtls();
    super.dispose();
  }

  void _resetAll() {
    final e = widget.existing;
    setState(() {
      _word.text = e?.word ?? '';
      _zh.text = e?.zhClean ?? e?.zh ?? '';
      _mn.text = e?.mnemonic ?? '';
      _wordClass = e?.wordClass;
      _audio = e?.audio;
      for (final x in _exs) {
        x.i.dispose();
        x.z.dispose();
      }
      _exs.clear();
      for (final x in e?.examples ?? const []) {
        _exs.add((
          i: TextEditingController(text: x.text),
          z: TextEditingController(text: x.zh ?? ''),
        ));
      }
      if (_exs.isEmpty) {
        _exs.add((
          i: TextEditingController(),
          z: TextEditingController(),
        ));
      }
      _disposeBlkCtls();
      _blocks
        ..clear()
        ..addAll(e?.userBlocks ?? const []);
      _layout = (e?.cardOrder ?? '').isNotEmpty
          ? e!.cardOrder!.split(',')
          : ['ex', 'mn'];
      _rebuildBlkCtls();
      _liveDup = null;
      _dup = null;
      _error = '';
    });
  }

  void _addExample() {
    setState(() => _exs.add((
          i: TextEditingController(),
          z: TextEditingController(),
        )));
  }

  void _removeExample(int idx) {
    setState(() {
      final gone = _exs.removeAt(idx);
      gone.i.dispose();
      gone.z.dispose();
      if (_exs.isEmpty) _addExample();
    });
  }

  List<({String i, String? z})> _readExamples() => [
        for (final e in _exs)
          if (e.i.text.trim().isNotEmpty || e.z.text.trim().isNotEmpty)
            (
              i: e.i.text.trim(),
              z: e.z.text.trim().isEmpty ? null : e.z.text.trim()
            ),
      ];

  (List<UserBlock>, String) _collectBlocks() {
    final blocks = <UserBlock>[
      for (var i = 0; i < _blocks.length; i++)
        if (_layout.contains('b$i'))
          _blocks[i].type == 'text'
              ? UserBlock(
                  type: _blocks[i].type, text: _blkTextCtls[i]?.text ?? '')
              : UserBlock(
                  type: _blocks[i].type,
                  lines: [
                    for (final c
                        in _blkLineCtls[i] ?? const <TextEditingController>[])
                      if (c.text.trim().isNotEmpty) c.text.trim()
                  ],
                )
    ];
    return (blocks, _layout.join(','));
  }

  void _previewCardFace() {
    final word = _word.text.trim();
    final (blocks, cardOrder) = _collectBlocks();
    final withEx = _layout.contains('ex');
    final withMn = _layout.contains('mn');
    final draft = WordCard(
      id: _currentId ?? AppDb.fold(word),
      word: word.isEmpty ? '（还没填词形）' : word,
      tier: 'common',
      zh: _zh.text.trim().isEmpty ? null : _zh.text.trim(),
      wordClass: _wordClass,
      examples: withEx
          ? [for (final e in _readExamples()) WordExample(text: e.i, zh: e.z)]
          : const [],
      mnemonic: withMn ? _mn.text : null,
      userBlocks: blocks,
      cardOrder: cardOrder,
      userWord: true,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Builder(
        builder: (ctx) {
          return Container(
            height: MediaQuery.sizeOf(ctx).height * 0.82,
            decoration: BoxDecoration(
              color: context.k.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.k.g300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text('卡片效果预览',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Expanded(

                  child: SafeArea(
                    top: false,
                    child: StudyScreen(
                      key: const ValueKey('preview'),
                      previewCard: draft,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _error = '';
      _dup = null;
      _busy = true;
    });
    final db = context.read<AppState>().db;
    final word = _word.text.trim();
    if (word.isEmpty || _zh.text.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = '词形和中文释义都得填。';
      });
      return;
    }
    final id = _currentId;

    final (blocks, cardOrder) = _collectBlocks();
    final withEx = _layout.contains('ex');
    final withMn = _layout.contains('mn');
    final r = id != null
        ? await db.updateUserWord(id,
            word: word,
            zh: _zh.text,
            wordClass: _wordClass,
            examples: withEx ? _readExamples() : const [],
            mnemonic: withMn ? _mn.text : '',
            userBlocks: blocks,
            cardOrder: cardOrder)
        : await db.createUserWord(
            word: word,
            zh: _zh.text,
            wordClass: _wordClass,
            examples: withEx ? _readExamples() : const [],
            mnemonic: withMn ? _mn.text : '',
            userBlocks: blocks,
            cardOrder: cardOrder);
    if (!mounted) return;
    if (r.existed != null) {

      final draft = _draftId;
      if (draft != null && draft != r.existed!.id) {
        await removeUserAudio(_audio);
        await db.deleteUserWord(draft);
        if (!mounted) return;
        setState(() => _draftId = null);
      }

      setState(() {
        _busy = false;
        _dup = r.existed;
        _liveDup = r.existed;
        _error = '';
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final db = context.read<AppState>().db;
    final id = _currentId;
    if (id == null) return;

    await removeUserAudio(_audio);
    await db.deleteUserWord(id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _discardDraft() async {
    final draft = _draftId;
    if (draft == null) return;

    final db = context.read<AppState>().db;
    await removeUserAudio(_audio);
    await db.deleteUserWord(draft);
  }

  Future<bool> _ensureDraft() async {
    if (_currentId != null) return true;
    final word = _word.text.trim();
    final zh = _zh.text.trim();
    if (word.isEmpty || zh.isEmpty) {
      setState(() => _error = '导音频前得先填上「词形」和「中文释义」。');
      return false;
    }
    final db = context.read<AppState>().db;
    final r = await db.createUserWord(
      word: word,
      zh: zh,
      wordClass: _wordClass,
      examples: _readExamples(),
      mnemonic: _mn.text,
    );
    if (!mounted) return false;
    if (r.existed != null) {
      setState(() {
        _dup = r.existed;
        _liveDup = r.existed;
      });
      return false;
    }
    setState(() => _draftId = r.id);
    return true;
  }

  Future<void> _importAudio() async {

    final app = context.read<AppState>();
    if (!await _ensureDraft()) return;
    if (!mounted) return;
    final id = _currentId!;
    try {
      final src = await pickAudioFile();
      if (src == null) return;
      await removeUserAudio(_audio);
      final au = await importUserAudio(id, src);
      final d = await app.db.db;
      await d.update('words', {'audio_ardi': au},
          where: 'id = ?', whereArgs: [id]);
      if (!mounted) return;
      setState(() => _audio = au);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1800),
          content: Text('已导入音频，以后点这张卡的喇叭就用它')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：${e.message ?? e.code}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  void _rebuildBlkCtls() {
    _disposeBlkCtls();
    for (var i = 0; i < _blocks.length; i++) {
      final b = _blocks[i];
      if (b.type == 'text') {
        _blkTextCtls[i] = TextEditingController(text: b.text ?? '');
      } else {
        _blkLineCtls[i] = [
          for (final l in b.lines.isEmpty ? [''] : b.lines)
            TextEditingController(text: l)
        ];
      }
    }
  }

  void _disposeBlkCtls() {
    for (final l in _blkLineCtls.values) {
      for (final c in l) {
        c.dispose();
      }
    }
    _blkLineCtls.clear();
    for (final c in _blkTextCtls.values) {
      c.dispose();
    }
    _blkTextCtls.clear();
  }

  List<TextEditingController> _linesCtl(int i) => _blkLineCtls.putIfAbsent(
      i,
      () => [
            for (final l
                in (_blocks[i].lines.isEmpty) ? [''] : _blocks[i].lines)
              TextEditingController(text: l)
          ]);

  TextEditingController _textCtl(int i) => _blkTextCtls.putIfAbsent(
      i, () => TextEditingController(text: _blocks[i].text ?? ''));

  void _addBlockLine(int i) => setState(() {
        _linesCtl(i).add(TextEditingController());
      });

  void _removeBlockLine(int i, int li) {
    final l = _linesCtl(i);
    if (l.length <= 1) return;
    setState(() {
      l[li].dispose();
      l.removeAt(li);
    });
  }

  void _moveSeg(String seg, int dir) {
    final i = _layout.indexOf(seg);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= _layout.length) return;
    setState(() {
      final t = _layout[i];
      _layout[i] = _layout[j];
      _layout[j] = t;
    });
  }

  void _removeSeg(String seg) {
    setState(() {
      _layout.remove(seg);
      if (seg.startsWith('b')) {
        final i = int.parse(seg.substring(1));
        _blocks.removeAt(i);
        _layout = [
          for (final s in _layout)
            s.startsWith('b') && int.parse(s.substring(1)) > i
                ? 'b${int.parse(s.substring(1)) - 1}'
                : s
        ];
      }
      _rebuildBlkCtls();
    });
  }

  Widget _blockHead(IconData icon, String label, String seg) {
    final i = _layout.indexOf(seg);
    Widget arrow(int dir, IconData ic) => GestureDetector(
          onTap: () => _moveSeg(seg, dir),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(ic,
                size: 15,
                color:
                    (dir < 0 && i == 0) || (dir > 0 && i == _layout.length - 1)
                        ? context.k.g300
                        : context.k.nFaint2),
          ),
        );
    return Row(children: [
      Icon(icon, size: 15, color: context.k.nSlate),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.k.nSlate2)),
      const Spacer(),
      arrow(-1, Icons.keyboard_arrow_up),
      arrow(1, Icons.keyboard_arrow_down),
      const SizedBox(width: 10),
      GestureDetector(
        onTap: () => _removeSeg(seg),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close, size: 16, color: context.k.g400),
        ),
      ),
    ]);
  }

  Widget _blockShell(Widget head, Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
        decoration: BoxDecoration(
          border: Border.all(color: context.k.g200, width: 0.8),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [head, const SizedBox(height: 6), child],
        ),
      );

  Widget _addBlockLineButton(int i) => GestureDetector(
        onTap: () => _addBlockLine(i),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: context.k.catMid, width: 0.8),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 14, color: context.k.catDeep),
            const SizedBox(width: 3),
            Text('加一个',
                style: TextStyle(fontSize: 12, color: context.k.catDeep)),
          ]),
        ),
      );

  void _addBlockMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('添加内容块',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final (t, ic, nm, ds) in const [
            (
              'derivation',
              Icons.call_split,
              '派生词形',
              'men- / per- / -an 这类由本词派生的词形'
            ),
            ('synonym', Icons.swap_horiz, '近义词', '意思相近的词，可加多行'),
            ('antonym', Icons.compare_arrows, '反义词', '意思相反的词，可加多行'),
            ('text', Icons.notes, '自由文本', '想写什么写什么——用法说明、近形辨析、文化背景…'),
          ])
            ListTile(
              leading: Icon(ic, color: context.k.deep),
              title: Text(nm,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              subtitle: Text(ds, style: const TextStyle(fontSize: 11.5)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _blocks.add(UserBlock(type: t));
                  _layout.add('b${_blocks.length - 1}');

                  _focusBlockIndex = _blocks.length - 1;
                  _rebuildBlkCtls();
                });

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _focusBlockIndex = null);
                });
              },
            ),
        ]),
      ),
    );
  }

  Widget _addBlockButton() => GestureDetector(
        onTap: _addBlockMenu,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(
                color: context.k.g300,
                width: 1,
                strokeAlign: BorderSide.strokeAlignInside),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, size: 16, color: context.k.deep),
            const SizedBox(width: 5),
            Text('添加内容块',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.k.deep)),
          ]),
        ),
      );

  IconData _iconOf(String type) => switch (type) {
        'derivation' => Icons.call_split,
        'synonym' => Icons.swap_horiz,
        'antonym' => Icons.compare_arrows,
        _ => Icons.notes,
      };

  String _hintOf(String type) => switch (type) {
        'derivation' => '派生词形，如：men- / -an',
        'synonym' => '近义词',
        'antonym' => '反义词',
        _ => '自由文本',
      };

  Widget _userBlockEditor(int i) {
    final b = _blocks[i];
    final head = _blockHead(_iconOf(b.type), b.label, 'b$i');
    if (b.type == 'text') {
      return _blockShell(
          head,
          TextField(
            controller: _textCtl(i),
            maxLines: 4,
            autofocus: _focusBlockIndex == i,
            decoration: dec('自由文本——想写什么写什么'),
          ));
    }
    final ctls = _linesCtl(i);
    return _blockShell(
        head,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var li = 0; li < ctls.length; li++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: ctls[li],
                        autofocus: _focusBlockIndex == i && li == 0,
                        decoration: dec(_hintOf(b.type)))),
                GestureDetector(
                  onTap: () => _removeBlockLine(i, li),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 15, color: context.k.g400),
                  ),
                ),
              ]),
            ),
          _addBlockLineButton(i),
        ]));
  }

  Widget _exBlock() {
    return _blockShell(
        Row(children: [
          Icon(Icons.format_quote, size: 15, color: context.k.nSlate),
          const SizedBox(width: 6),
          Text('例句',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.k.nSlate2)),
          const Spacer(),
          GestureDetector(
            onTap: _addExample,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: context.k.catMid, width: 0.8),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, size: 14, color: context.k.catDeep),
                const SizedBox(width: 3),
                Text('加一条',
                    style: TextStyle(fontSize: 12, color: context.k.catDeep)),
              ]),
            ),
          ),
          _blockHeadArrows('ex'),
          _blockHeadClose(() => _removeSeg('ex')),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < _exs.length; i++) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
              decoration: BoxDecoration(
                border: Border.all(color: context.k.g200, width: 0.8),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('例句 ${i + 1}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.k.nFaint2)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _removeExample(i),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child:
                            Icon(Icons.close, size: 16, color: context.k.g400),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _exs[i].i,
                    decoration: dec('印尼语'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _exs[i].z,
                    decoration: dec('这句的中文翻译（可空）'),
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text('空着的例句保存时会自动丢掉。',
              style: TextStyle(fontSize: 11.5, color: context.k.nFaint2)),
        ]));
  }

  Widget _mnBlock() => _blockShell(
      _blockHeadRow(Icons.lightbulb_outline, '怎么记住 / 怎么读', 'mn'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _mn,
          maxLines: 2,
          decoration: dec('助记，只给自己看（可空）'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          GestureDetector(
            onTap: _busy ? null : _importAudio,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(
                    color: _audio == null ? context.k.g300 : context.k.catMid,
                    width: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  _audio == null
                      ? Icons.upload_file
                      : Icons.check_circle_outline,
                  size: 16,
                  color: _audio == null ? context.k.nT2 : context.k.catDeep,
                ),
                const SizedBox(width: 5),
                Text(
                  _audio == null ? '导入音频文件' : '已导入，换一个',
                  style: TextStyle(
                      fontSize: 12.5,
                      color:
                          _audio == null ? context.k.g700 : context.k.catDeep),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isEdit ? '用自己的录音代替机器发音' : '会先帮你把这条存下来，再选文件',
              style: TextStyle(fontSize: 11.5, color: context.k.nFaint2),
            ),
          ),
        ]),
      ]));

  Widget _blockHeadIconText(IconData icon, String text) => Row(children: [
        Icon(icon, size: 15, color: context.k.nSlate),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.k.nSlate2)),
      ]);

  Widget _blockHeadArrows(String seg) {
    final i = _layout.indexOf(seg);
    Widget arrow(int dir, IconData ic) => GestureDetector(
          onTap: () => _moveSeg(seg, dir),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(ic,
                size: 15,
                color:
                    (dir < 0 && i == 0) || (dir > 0 && i == _layout.length - 1)
                        ? context.k.g300
                        : context.k.nFaint2),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      arrow(-1, Icons.keyboard_arrow_up),
      arrow(1, Icons.keyboard_arrow_down),
    ]);
  }

  Widget _blockHeadClose(VoidCallback onClose) => GestureDetector(
        onTap: onClose,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.close, size: 16, color: context.k.g400),
        ),
      );

  Widget _blockHeadRow(IconData icon, String label, String seg) => Row(
        children: [
          _blockHeadIconText(icon, label),
          const Spacer(),
          _blockHeadArrows(seg),
          const SizedBox(width: 10),
          _blockHeadClose(() => _removeSeg(seg)),
        ],
      );

  Widget _sectionHead(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 15, color: context.k.nSlate),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.k.nSlate2)),
          ],
        ),
      );

  Widget _classPicker() {
    final items = kUserWordClasses
        .where((e) => e.$1 != null)
        .toList();
    Widget chip(String text, String? value) {
      final on = _wordClass == value;
      return GestureDetector(
        onTap: () => setState(() => _wordClass = value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: on ? context.k.catTint : null,
            border: Border.all(
                color: on ? context.k.catMid : context.k.g300,
                width: on ? 1 : 0.8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? context.k.catDeep : context.k.g700)),
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        chip('不标', null),
        for (final (v, zh) in items) chip(zh, v),
      ],
    );
  }

  InputDecoration dec(String hint) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: context.k.alt,
        hintStyle: TextStyle(color: context.k.faint),
        hintText: hint,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 12.5, color: context.k.nT2);

    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardDraft();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: kb),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.k.g300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        Text(_isEdit ? '编辑自建词' : '新建自建词',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: _resetAll,
                          style: TextButton.styleFrom(
                            foregroundColor: context.k.nT2,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                          ),
                          child: const Text('重置',
                              style: TextStyle(fontSize: 12)),
                        ),
                        if (_isEdit)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 22),
                            tooltip: '删除这条自建词',
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  content: const Text('删掉这条自建词？\n'
                                      '它已加入记忆的进度、作答记录会一起删。'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(d, false),
                                        child: const Text('取消')),
                                    FilledButton(
                                        onPressed: () => Navigator.pop(d, true),
                                        child: const Text('删除')),
                                  ],
                                ),
                              );
                              if (ok == true) await _delete();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    _sectionHead(Icons.spellcheck, '这个词'),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _word,
                      decoration: dec('印尼语或词组，例如：rumah sakit'),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),

                    if (_liveDup != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: context.k.star.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              size: 15, color: context.k.brown),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '词库里已经有「${_liveDup!.word}」了（${_liveDup!.zhClean ?? ''}）',
                              style: TextStyle(
                                  fontSize: 12, color: context.k.brown),
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {

                              final nav = Navigator.of(context);
                              await _discardDraft();
                              if (!mounted) return;
                              nav.pop();
                              await nav.push(MaterialPageRoute(
                                  builder: (_) =>
                                      WordDetailScreen(cardId: _liveDup!.id)));
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: Text('去看',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: context.k.brown)),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('中文释义 *', style: label),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _zh,
                      decoration: dec('例如：医院'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Text('词性（选填）', style: label),
                    const SizedBox(height: 7),
                    _classPicker(),

                    const SizedBox(height: 20),

                    for (final seg in List<String>.from(_layout)) ...[
                      if (seg == 'ex') _exBlock(),
                      if (seg == 'mn') _mnBlock(),
                      if (seg.startsWith('b'))
                        _userBlockEditor(int.parse(seg.substring(1))),
                    ],
                    const SizedBox(height: 14),

                    GestureDetector(
                      onTap: _previewCardFace,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: context.k.tint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility,
                                  size: 16, color: context.k.deep),
                              const SizedBox(width: 5),
                              Text('卡片效果预览（学习页正/背面）',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.k.deep)),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _addBlockButton(),

                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_error,
                          style:
                              TextStyle(fontSize: 12.5, color: context.k.red2)),
                    ],

                    if (_dup != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.k.star.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('词库里已经有「${_dup!.word}」这张卡了（没有再建一份）：',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(_dup!.zhClean ?? _dup!.word,
                                style: TextStyle(
                                    fontSize: 12.5, color: context.k.g700)),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () async {

                                final nav = Navigator.of(context);
                                await _discardDraft();
                                if (!mounted) return;
                                nav.pop();
                                await nav.push(MaterialPageRoute(
                                    builder: (_) =>
                                        WordDetailScreen(cardId: _dup!.id)));
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('去看已有那张'),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: context.k.g200, width: 0.8)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(

                          onPressed: _busy
                              ? null
                              : () async {
                                  final nav = Navigator.of(context);
                                  await _discardDraft();
                                  if (!mounted) return;
                                  nav.pop(false);
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.k.nSlate2,
                            side: BorderSide(color: context.k.g300),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(

                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.k.brand,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_isEdit ? '保存修改' : '保存'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
