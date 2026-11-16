library;

import 'package:flutter/material.dart';

import '../../grammar/grammar_edit.dart';
import '../../grammar/grammar_models.dart';
import '../../theme/k_colors.dart';
import '../pair_list_editor.dart';

class GLineListEditor extends StatefulWidget {
  const GLineListEditor({
    super.key,
    required this.controller,
    required this.hasTitle,
    required this.itemLabel,
    required this.itemHint,
    required this.addLabel,
    this.titleHint = '可选标题（留空则不显示）',
    this.onChanged,
  });

  final TextEditingController controller;
  final bool hasTitle;
  final String itemLabel;
  final String itemHint;
  final String addLabel;
  final String titleHint;
  final VoidCallback? onChanged;

  @override
  State<GLineListEditor> createState() => _GLineListEditorState();
}

class _GLineListEditorState extends State<GLineListEditor> {
  final TextEditingController _titleCtl = TextEditingController();
  final List<TextEditingController> _items = [];
  String _lastSynced = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_onExt);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExt);
    _titleCtl.dispose();
    for (final c in _items) {
      c.dispose();
    }
    super.dispose();
  }

  void _onExt() {
    if (_syncing) return;
    if (widget.controller.text != _lastSynced) {
      setState(_load);
    }
  }

  void _load() {
    for (final c in _items) {
      c.dispose();
    }
    _items.clear();
    _lastSynced = widget.controller.text;
    var lines = [
      for (final l in _lastSynced.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    var title = '';
    if (widget.hasTitle && lines.isNotEmpty && lines.first.startsWith('标题：')) {
      title = lines.first.substring(3).trim();
      lines = lines.sublist(1);
    }
    _titleCtl.text = title;
    if (lines.isEmpty) {
      _items.add(TextEditingController());
    } else {
      for (final l in lines) {
        _items.add(TextEditingController(
            text: l.startsWith('· ') ? l.substring(2) : l));
      }
    }
  }

  void _sync() {
    final out = <String>[];
    if (widget.hasTitle && _titleCtl.text.trim().isNotEmpty) {
      out.add('标题：${_titleCtl.text.trim()}');
    }
    for (final c in _items) {
      final t = c.text.trim();
      if (t.isNotEmpty) out.add(t);
    }
    final text = out.join('\n');
    _syncing = true;
    _lastSynced = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.hasTitle) ...[
          TextField(
            controller: _titleCtl,
            onChanged: (_) => _sync(),
            style: TextStyle(fontSize: 13.5, color: k.text),
            decoration: softFieldDeco(
              context,
              hint: widget.titleHint,
              labelText: '标题（可选）',
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < _items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _items[i],
                    onChanged: (_) => _sync(),
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13.5, color: k.text),
                    decoration: softFieldDeco(
                      context,
                      hint: widget.itemHint,
                      labelText: '${widget.itemLabel} ${i + 1}',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (_items.length > 1)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: i > 0
                            ? () {
                                setState(() {
                                  final tmp = _items[i];
                                  _items[i] = _items[i - 1];
                                  _items[i - 1] = tmp;
                                });
                                _sync();
                              }
                            : null,
                        child: Icon(Icons.keyboard_arrow_up,
                            size: 16, color: i > 0 ? k.t2 : k.g300),
                      ),
                      InkWell(
                        onTap: i + 1 < _items.length
                            ? () {
                                setState(() {
                                  final tmp = _items[i];
                                  _items[i] = _items[i + 1];
                                  _items[i + 1] = tmp;
                                });
                                _sync();
                              }
                            : null,
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 16,
                            color: i + 1 < _items.length ? k.t2 : k.g300),
                      ),
                    ],
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.close, size: 16, color: k.t3),
                  onPressed: () {
                    setState(() {
                      _items.removeAt(i).dispose();
                      if (_items.isEmpty) _items.add(TextEditingController());
                    });
                    _sync();
                  },
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () =>
                setState(() => _items.add(TextEditingController())),
            icon: const Icon(Icons.add, size: 16),
            label: Text(widget.addLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: k.deep,
              side: BorderSide(color: k.nEdge),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

class GTableEditor extends StatefulWidget {
  const GTableEditor({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<GTableEditor> createState() => _GTableEditorState();
}

class _GTableEditorState extends State<GTableEditor> {
  final TextEditingController _titleCtl = TextEditingController();
  final List<TextEditingController> _cols = [];
  final List<List<TextEditingController>> _rows = [];
  String _lastSynced = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_onExt);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExt);
    _titleCtl.dispose();
    _disposeGrid();
    super.dispose();
  }

  void _disposeGrid() {
    for (final c in _cols) {
      c.dispose();
    }
    _cols.clear();
    for (final r in _rows) {
      for (final c in r) {
        c.dispose();
      }
    }
    _rows.clear();
  }

  void _onExt() {
    if (_syncing) return;
    if (widget.controller.text != _lastSynced) {
      setState(_load);
    }
  }

  void _load() {
    _disposeGrid();
    _lastSynced = widget.controller.text;
    final parsed = gParseBlock('table', _lastSynced);
    if (parsed.block is GTableBlock) {
      final b = parsed.block as GTableBlock;
      _titleCtl.text = b.title;
      final nCols = b.cols.isEmpty ? 2 : b.cols.length;
      for (var i = 0; i < nCols; i++) {
        _cols.add(TextEditingController(
            text: i < b.cols.length ? b.cols[i] : '列${i + 1}'));
      }
      for (final r in b.rows) {
        _rows.add([
          for (var c = 0; c < nCols; c++)
            TextEditingController(text: c < r.length ? r[c] : ''),
        ]);
      }
    } else {
      _titleCtl.text = '';
      _cols.addAll([
        TextEditingController(text: '形式'),
        TextEditingController(text: '用法说明'),
      ]);
      _rows.add([TextEditingController(), TextEditingController()]);
    }
  }

  void _sync() {
    final colTexts = [for (final c in _cols) c.text.trim()];
    final lines = <String>[
      if (_titleCtl.text.trim().isNotEmpty) '标题：${_titleCtl.text.trim()}',
      colTexts.join(' | '),
      for (final r in _rows)
        if (r.any((c) => c.text.trim().isNotEmpty))
          [for (final c in r) c.text.trim()].join(' | '),
    ];
    final text = lines.join('\n');
    _syncing = true;
    _lastSynced = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    widget.onChanged?.call();
  }

  void _addCol() {
    setState(() {
      _cols.add(TextEditingController(text: '列${_cols.length + 1}'));
      for (final r in _rows) {
        r.add(TextEditingController());
      }
    });
    _sync();
  }

  void _removeCol(int c) {
    if (_cols.length <= 1) return;
    setState(() {
      _cols.removeAt(c).dispose();
      for (final r in _rows) {
        if (c < r.length) r.removeAt(c).dispose();
      }
    });
    _sync();
  }

  void _addRow() {
    setState(() {
      _rows.add([for (var i = 0; i < _cols.length; i++) TextEditingController()]);
    });
  }

  void _removeRow(int i) {
    setState(() {
      for (final c in _rows.removeAt(i)) {
        c.dispose();
      }
    });
    _sync();
  }

  void _moveRow(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _rows.length) return;
    setState(() {
      final tmp = _rows[i];
      _rows[i] = _rows[j];
      _rows[j] = tmp;
    });
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtl,
          onChanged: (_) => _sync(),
          style: TextStyle(fontSize: 13.5, color: k.text),
          decoration: softFieldDeco(
            context,
            hint: '可选标题（留空则不显示）',
            labelText: '表格标题（可选）',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('表头列（${_cols.length} 列）',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: k.t2)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addCol,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('加一列', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: k.deep,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var c = 0; c < _cols.length; c++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cols[c],
                    onChanged: (_) {
                      setState(() {});
                      _sync();
                    },
                    style: TextStyle(fontSize: 13, color: k.text),
                    decoration: softFieldDeco(
                      context,
                      hint: '输入第 ${c + 1} 列表头',
                      labelText: '表头 ${c + 1}',
                    ),
                  ),
                ),
                if (_cols.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close, size: 16, color: k.t3),
                    onPressed: () => _removeCol(c),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Text('数据行（${_rows.length} 行）',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: k.t2)),
        const SizedBox(height: 6),
        for (var r = 0; r < _rows.length; r++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
            decoration: BoxDecoration(
              color: k.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: k.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: k.tint,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('第 ${r + 1} 行',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: k.deep)),
                    ),
                    const Spacer(),
                    if (_rows.length > 1) ...[
                      InkWell(
                        onTap: r > 0 ? () => _moveRow(r, -1) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.arrow_upward,
                              size: 15, color: r > 0 ? k.t2 : k.g300),
                        ),
                      ),
                      InkWell(
                        onTap:
                            r + 1 < _rows.length ? () => _moveRow(r, 1) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.arrow_downward,
                              size: 15,
                              color: r + 1 < _rows.length ? k.t2 : k.g300),
                        ),
                      ),
                    ],
                    InkWell(
                      onTap: () => _removeRow(r),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.close, size: 15, color: k.t3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (var c = 0; c < _cols.length; c++) ...[
                  TextField(
                    controller: _rows[r][c],
                    onChanged: (_) => _sync(),
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13, color: k.text),
                    decoration: softFieldDeco(
                      context,
                      hint: '填写该格内容',
                      labelText: _cols[c].text.trim().isEmpty
                          ? '第 ${c + 1} 列'
                          : _cols[c].text.trim(),
                    ),
                  ),
                  if (c + 1 < _cols.length) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加一行'),
            style: OutlinedButton.styleFrom(
              foregroundColor: k.deep,
              side: BorderSide(color: k.nEdge),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}

class GVsEditor extends StatefulWidget {
  const GVsEditor({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<GVsEditor> createState() => _GVsEditorState();
}

class _GVsEditorState extends State<GVsEditor> {
  final _aTitle = TextEditingController();
  final _aText = TextEditingController();
  final _aEx = TextEditingController();
  final _bTitle = TextEditingController();
  final _bText = TextEditingController();
  final _bEx = TextEditingController();
  final _note = TextEditingController();
  String _lastSynced = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_onExt);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExt);
    for (final c in [_aTitle, _aText, _aEx, _bTitle, _bText, _bEx, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onExt() {
    if (_syncing) return;
    if (widget.controller.text != _lastSynced) {
      setState(_load);
    }
  }

  void _load() {
    _lastSynced = widget.controller.text;
    final parsed = gParseBlock('vs', _lastSynced);
    if (parsed.block is GVsBlock) {
      final b = parsed.block as GVsBlock;
      _aTitle.text = b.a.title;
      _aText.text = b.a.text;
      _aEx.text = formatPairLines([
        for (final e in b.a.ex) PairItem(e.i, e.z),
      ]);
      _bTitle.text = b.b.title;
      _bText.text = b.b.text;
      _bEx.text = formatPairLines([
        for (final e in b.b.ex) PairItem(e.i, e.z),
      ]);
      _note.text = b.note;
    }
  }

  void _sync() {
    final out = <String>[
      '[A] ${_aTitle.text.trim()}'.trimRight(),
      if (_aText.text.trim().isNotEmpty) _aText.text.trim(),
      for (final p in parsePairLines(_aEx.text))
        '> ${p.b.isEmpty ? p.a : '${p.a} | ${p.b}'}',
      '[B] ${_bTitle.text.trim()}'.trimRight(),
      if (_bText.text.trim().isNotEmpty) _bText.text.trim(),
      for (final p in parsePairLines(_bEx.text))
        '> ${p.b.isEmpty ? p.a : '${p.a} | ${p.b}'}',
      if (_note.text.trim().isNotEmpty) '[注] ${_note.text.trim()}',
    ];
    final text = out.join('\n');
    _syncing = true;
    _lastSynced = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    widget.onChanged?.call();
  }

  Widget _sideCard(
    BuildContext context, {
    required String tag,
    required TextEditingController titleCtl,
    required TextEditingController textCtl,
    required TextEditingController exCtl,
  }) {
    final k = context.k;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: k.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('对比项 $tag',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: k.deep)),
          const SizedBox(height: 8),
          TextField(
            controller: titleCtl,
            onChanged: (_) => _sync(),
            style: TextStyle(fontSize: 13.5, color: k.text),
            decoration: softFieldDeco(
              context,
              hint: '如：tidak（否定动词/形容词）',
              labelText: '标题',
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: textCtl,
            onChanged: (_) => _sync(),
            minLines: 1,
            maxLines: 4,
            style: TextStyle(fontSize: 13, color: k.text),
            decoration: softFieldDeco(
              context,
              hint: '可选说明文字',
              labelText: '正文说明',
            ),
          ),
          const SizedBox(height: 8),
          PairListEditor(
            controller: exCtl,
            firstHint: '印尼语例句',
            secondHint: '中文翻译',
            addLabel: '添加 $tag 方例句',
            reorderable: false,
            onChanged: _sync,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sideCard(context,
            tag: 'A', titleCtl: _aTitle, textCtl: _aText, exCtl: _aEx),
        _sideCard(context,
            tag: 'B', titleCtl: _bTitle, textCtl: _bText, exCtl: _bEx),
        TextField(
          controller: _note,
          onChanged: (_) => _sync(),
          minLines: 1,
          maxLines: 3,
          style: TextStyle(fontSize: 13, color: k.text),
          decoration: softFieldDeco(
            context,
            hint: '可选底部对比小结',
            labelText: '总结备注（可选）',
          ),
        ),
      ],
    );
  }
}

class _TreeOptCtls {
  _TreeOptCtls({
    String label = '',
    String hint = '',
    String answer = '',
    String rule = '',
    String examples = '',
  })  : label = TextEditingController(text: label),
        hint = TextEditingController(text: hint),
        answer = TextEditingController(text: answer),
        rule = TextEditingController(text: rule),
        examples = TextEditingController(text: examples);

  final TextEditingController label;
  final TextEditingController hint;
  final TextEditingController answer;
  final TextEditingController rule;
  final TextEditingController examples;

  void dispose() {
    label.dispose();
    hint.dispose();
    answer.dispose();
    rule.dispose();
    examples.dispose();
  }
}

class GTreeEditor extends StatefulWidget {
  const GTreeEditor({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onChanged;

  @override
  State<GTreeEditor> createState() => _GTreeEditorState();
}

class _GTreeEditorState extends State<GTreeEditor> {
  final _qCtl = TextEditingController();
  final List<_TreeOptCtls> _opts = [];
  String _lastSynced = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.controller.addListener(_onExt);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExt);
    _qCtl.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  void _onExt() {
    if (_syncing) return;
    if (widget.controller.text != _lastSynced) {
      setState(_load);
    }
  }

  void _load() {
    for (final o in _opts) {
      o.dispose();
    }
    _opts.clear();
    _lastSynced = widget.controller.text;
    final parsed = gParseBlock('tree', _lastSynced);
    if (parsed.block is GTreeBlock) {
      final b = parsed.block as GTreeBlock;
      _qCtl.text = b.q;
      for (final o in b.opts) {
        _opts.add(_TreeOptCtls(
          label: o.label,
          hint: o.hint,
          answer: o.result.answer,
          rule: o.result.rule,
          examples: o.result.examples.join('\n'),
        ));
      }
    }
    if (_opts.isEmpty) {
      _opts.add(_TreeOptCtls());
    }
  }

  void _sync() {
    final out = <String>['[问] ${_qCtl.text.trim()}'];
    for (final o in _opts) {
      final lbl = o.label.text.trim();
      final h = o.hint.text.trim();
      out.add('[选] ${h.isEmpty ? lbl : '$lbl | $h'}');
      if (o.answer.text.trim().isNotEmpty) {
        out.add('答：${o.answer.text.trim()}');
      }
      if (o.rule.text.trim().isNotEmpty) {
        out.add('规则：${o.rule.text.trim()}');
      }
      for (final e in o.examples.text.split('\n')) {
        if (e.trim().isNotEmpty) out.add('例：${e.trim()}');
      }
    }
    final text = out.join('\n');
    _syncing = true;
    _lastSynced = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _qCtl,
          onChanged: (_) => _sync(),
          style: TextStyle(fontSize: 13.5, color: k.text),
          decoration: softFieldDeco(
            context,
            hint: '引导判断的问题，如：后面接什么词性？',
            labelText: '判断问题',
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _opts.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: k.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: k.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('选项 ${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: k.deep)),
                    const Spacer(),
                    if (_opts.length > 1)
                      InkWell(
                        onTap: () {
                          setState(() => _opts.removeAt(i).dispose());
                          _sync();
                        },
                        child: Icon(Icons.close, size: 16, color: k.t3),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _opts[i].label,
                        onChanged: (_) => _sync(),
                        style: TextStyle(fontSize: 13, color: k.text),
                        decoration: softFieldDeco(
                          context,
                          hint: '如：接名词',
                          labelText: '选项名称',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _opts[i].hint,
                        onChanged: (_) => _sync(),
                        style: TextStyle(fontSize: 13, color: k.text),
                        decoration: softFieldDeco(
                          context,
                          hint: '可选简短提示',
                          labelText: '副标题提示',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _opts[i].answer,
                  onChanged: (_) => _sync(),
                  style: TextStyle(fontSize: 13, color: k.text),
                  decoration: softFieldDeco(
                    context,
                    hint: '如：用 bukan',
                    labelText: '结论',
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _opts[i].rule,
                  onChanged: (_) => _sync(),
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: k.text),
                  decoration: softFieldDeco(
                    context,
                    hint: '可选规则解释',
                    labelText: '规则',
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _opts[i].examples,
                  onChanged: (_) => _sync(),
                  minLines: 1,
                  maxLines: 3,
                  style: TextStyle(fontSize: 13, color: k.text),
                  decoration: softFieldDeco(
                    context,
                    hint: '每行一条例子',
                    labelText: '例子（每行一条）',
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _opts.add(_TreeOptCtls())),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加选项'),
            style: OutlinedButton.styleFrom(
              foregroundColor: k.deep,
              side: BorderSide(color: k.nEdge),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}
