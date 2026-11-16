library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';

class PairItem {
  PairItem(this.a, this.b);
  String a;
  String b;
}

List<PairItem> parsePairLines(String text) {
  final out = <PairItem>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final idx = line.indexOf('|');
    if (idx < 0) {
      out.add(PairItem(line, ''));
    } else {
      out.add(PairItem(
        line.substring(0, idx).trim(),
        line.substring(idx + 1).trim(),
      ));
    }
  }
  return out;
}

String formatPairLines(List<PairItem> items) {
  final out = <String>[];
  for (final it in items) {
    final a = it.a.trim();
    final b = it.b.trim();
    if (a.isEmpty && b.isEmpty) continue;
    out.add(b.isEmpty ? a : '$a | $b');
  }
  return out.join('\n');
}

InputDecoration softFieldDeco(
  BuildContext context, {
  required String hint,
  String? labelText,
}) {
  final k = context.k;
  final hasLabel = labelText != null && labelText.isNotEmpty;
  final baseBorder = UnderlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: k.border, width: 1),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: k.alt,
    labelText: labelText,
    labelStyle: TextStyle(fontSize: 12, color: k.t3),
    floatingLabelStyle: TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: k.t3,
    ),
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12.5, color: k.faint),
    contentPadding: EdgeInsets.fromLTRB(
      11,
      hasLabel ? 7 : 10,
      11,
      hasLabel ? 7 : 10,
    ),
    border: baseBorder,
    enabledBorder: baseBorder,
    focusedBorder: UnderlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: k.brand, width: 1.6),
    ),
  );
}

class PairListEditor extends StatefulWidget {
  const PairListEditor({
    super.key,
    required this.controller,
    required this.firstHint,
    required this.secondHint,
    this.firstLabel = '印尼语',
    this.secondLabel = '中文',
    this.addLabel = '添加一条',
    this.stacked = true,
    this.reorderable = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String firstHint;
  final String secondHint;
  final String firstLabel;
  final String secondLabel;
  final String addLabel;
  final bool stacked;
  final bool reorderable;
  final VoidCallback? onChanged;

  @override
  State<PairListEditor> createState() => _PairListEditorState();
}

class _PairListEditorState extends State<PairListEditor> {
  final List<(TextEditingController, TextEditingController)> _rows = [];
  String _lastSynced = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadFromController();
    widget.controller.addListener(_onExternalChange);
  }

  @override
  void didUpdateWidget(covariant PairListEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onExternalChange);
      widget.controller.addListener(_onExternalChange);
      _loadFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalChange);
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  void _onExternalChange() {
    if (_syncing) return;
    if (widget.controller.text != _lastSynced) {
      setState(_loadFromController);
    }
  }

  void _loadFromController() {
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    _rows.clear();
    _lastSynced = widget.controller.text;
    final parsed = parsePairLines(_lastSynced);
    if (parsed.isEmpty) {
      _rows.add((TextEditingController(), TextEditingController()));
    } else {
      for (final p in parsed) {
        _rows.add((
          TextEditingController(text: p.a),
          TextEditingController(text: p.b),
        ));
      }
    }
  }

  void _syncBack() {
    final text = formatPairLines([
      for (final (a, b) in _rows) PairItem(a.text, b.text),
    ]);
    _syncing = true;
    _lastSynced = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _syncing = false;
    widget.onChanged?.call();
  }

  void _addRow() {
    setState(() {
      _rows.add((TextEditingController(), TextEditingController()));
    });
  }

  void _removeRow(int i) {
    setState(() {
      final (a, b) = _rows.removeAt(i);
      a.dispose();
      b.dispose();
      if (_rows.isEmpty) {
        _rows.add((TextEditingController(), TextEditingController()));
      }
    });
    _syncBack();
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _rows.length) return;
    setState(() {
      final tmp = _rows[i];
      _rows[i] = _rows[j];
      _rows[j] = tmp;
    });
    _syncBack();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _rows.length; i++)
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
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: k.deep,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.reorderable && _rows.length > 1) ...[
                      InkWell(
                        onTap: i > 0 ? () => _move(i, -1) : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.arrow_upward,
                            size: 15,
                            color: i > 0 ? k.t2 : k.g300,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap:
                            i + 1 < _rows.length ? () => _move(i, 1) : null,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.arrow_downward,
                            size: 15,
                            color: i + 1 < _rows.length ? k.t2 : k.g300,
                          ),
                        ),
                      ),
                    ],
                    InkWell(
                      onTap: () => _removeRow(i),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(Icons.close, size: 15, color: k.t3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (widget.stacked) ...[
                  TextField(
                    controller: _rows[i].$1,
                    onChanged: (_) => _syncBack(),
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13.5, color: k.text),
                    decoration: softFieldDeco(
                      context,
                      hint: widget.firstHint,
                      labelText: widget.firstLabel,
                    ),
                  ),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _rows[i].$2,
                    onChanged: (_) => _syncBack(),
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13.5, color: k.text),
                    decoration: softFieldDeco(
                      context,
                      hint: widget.secondHint,
                      labelText: widget.secondLabel,
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _rows[i].$1,
                          onChanged: (_) => _syncBack(),
                          style: TextStyle(fontSize: 13.5, color: k.text),
                          decoration: softFieldDeco(
                            context,
                            hint: widget.firstHint,
                            labelText: widget.firstLabel,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: TextField(
                          controller: _rows[i].$2,
                          onChanged: (_) => _syncBack(),
                          style: TextStyle(fontSize: 13.5, color: k.text),
                          decoration: softFieldDeco(
                            context,
                            hint: widget.secondHint,
                            labelText: widget.secondLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 16),
            label: Text(widget.addLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: k.deep,
              side: BorderSide(color: k.nEdge),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}
