library;

import 'package:flutter/material.dart';

import '../../grammar/grammar_edit.dart';
import '../../grammar/grammar_models.dart';
import '../../theme/k_colors.dart';
import '../pair_list_editor.dart';
import 'g_blocks.dart';
import 'g_structured_editors.dart';

class GEditSheetResult {
  const GEditSheetResult({
    this.text,
    this.headingText,
    this.reset = false,
  });

  final String? text;

  final String? headingText;
  final bool reset;
}

Future<GEditSheetResult?> showGBlockEditSheet(
  BuildContext context, {
  required String pageTitle,
  required GBlock block,
  GHeadingBlock? headingBlock,
  required bool canReset,
}) {
  return showModalBottomSheet<GEditSheetResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.k.surface,
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (_) => _GBlockEditSheet(
      pageTitle: pageTitle,
      block: block,
      headingBlock: headingBlock,
      canReset: canReset,
    ),
  );
}

class _GBlockEditSheet extends StatefulWidget {
  const _GBlockEditSheet({
    required this.pageTitle,
    required this.block,
    this.headingBlock,
    required this.canReset,
  });

  final String pageTitle;
  final GBlock block;
  final GHeadingBlock? headingBlock;
  final bool canReset;

  @override
  State<_GBlockEditSheet> createState() => _GBlockEditSheetState();
}

class _GBlockEditSheetState extends State<_GBlockEditSheet> {
  late final TextEditingController _ctl;
  TextEditingController? _headCtl;
  late final String _type;
  late bool _preview;
  bool _rawMode = false;
  GParseResult _parsed = const GParseResult(null);

  static const _structuredTypes = {
    'table',
    'ex',
    'steps',
    'pit',
    'words',
    'vs',
    'tree',
  };

  @override
  void initState() {
    super.initState();
    _type = gBlockTypeOf(widget.block);
    _ctl = TextEditingController(text: gBlockToText(widget.block));
    if (widget.headingBlock != null) {
      _headCtl = TextEditingController(text: widget.headingBlock!.text);
    }
    _preview = !const {'text', 'h', 'lead'}.contains(_type);
    _reparse();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _headCtl?.dispose();
    super.dispose();
  }

  void _reparse() {
    setState(() => _parsed = gParseBlock(_type, _ctl.text));
  }

  bool get _canSave {
    if (!_parsed.ok) return false;
    if (_headCtl != null && _headCtl!.text.trim().isEmpty) return false;
    return true;
  }

  Widget _buildBodyEditor() {
    if (!_rawMode && _structuredTypes.contains(_type)) {
      switch (_type) {
        case 'table':
          return GTableEditor(controller: _ctl, onChanged: _reparse);
        case 'ex':
          return PairListEditor(
            controller: _ctl,
            firstHint: '印尼语例句',
            secondHint: '中文翻译',
            addLabel: '添加一句例句',
            onChanged: _reparse,
          );
        case 'steps':
          return GLineListEditor(
            controller: _ctl,
            hasTitle: true,
            itemLabel: '步骤',
            itemHint: '输入这一步的内容',
            addLabel: '添加一步',
            onChanged: _reparse,
          );
        case 'pit':
          return GLineListEditor(
            controller: _ctl,
            hasTitle: false,
            itemLabel: '提醒',
            itemHint: '输入容易写错或混淆的点',
            addLabel: '添加一条提醒',
            onChanged: _reparse,
          );
        case 'words':
          return GLineListEditor(
            controller: _ctl,
            hasTitle: true,
            itemLabel: '词条 ID',
            itemHint: '如：makan',
            addLabel: '添加一个词',
            onChanged: _reparse,
          );
        case 'vs':
          return GVsEditor(controller: _ctl, onChanged: _reparse);
        case 'tree':
          return GTreeEditor(controller: _ctl, onChanged: _reparse);
      }
    }
    final k = context.k;
    return TextField(
      controller: _ctl,
      onChanged: (_) => _reparse(),
      minLines: 4,
      maxLines: 8,
      style: TextStyle(fontSize: 14, height: 1.6, color: k.text),
      decoration: softFieldDeco(
        context,
        hint: '在这里编辑内容…',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final hasStructured = _structuredTypes.contains(_type);
    final headLabel = widget.headingBlock != null
        ? '改小节 · ${widget.pageTitle}'
        : '改${kGBlockTypeNames[_type]} · ${widget.pageTitle}';
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(headLabel,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: k.nSlate2,
                    side: BorderSide(color: k.g300),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _canSave
                      ? () => Navigator.pop(
                            context,
                            GEditSheetResult(
                              text: _ctl.text,
                              headingText: _headCtl?.text.trim(),
                            ),
                          )
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: k.onbrand,
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
            if (_headCtl != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _headCtl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: k.text),
                decoration: softFieldDeco(
                  context,
                  hint: '输入小标题（同时显示在页内目录）',
                  labelText: '小标题',
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Text(kGBlockTypeNames[_type]!,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (hasStructured)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _rawMode = !_rawMode),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: k.tint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _rawMode ? '切回表单编辑' : '纯文本模式',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: k.deep),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              (!_rawMode && hasStructured)
                  ? '直接按格填写或增减行，无需手动打分隔符。只存本机，不改词库。'
                  : (kGBlockTypeHelp[_type] ?? ''),
              style: TextStyle(fontSize: 12, height: 1.5, color: k.faint),
            ),
            const SizedBox(height: 8),
            _buildBodyEditor(),
            const SizedBox(height: 10),
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _preview = !_preview),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: k.tint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_preview ? '预览 开' : '预览 关',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: k.deep)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('保存前先看渲染结果，约定写错会在这里露出来',
                      style: TextStyle(fontSize: 11, color: k.faint)),
                ),
              ],
            ),
            if (_preview) ...[
              const SizedBox(height: 6),
              if (_parsed.ok)
                GBlockView(block: _parsed.block!)
              else
                Text(_parsed.error ?? '',
                    style: TextStyle(fontSize: 12, color: k.gWarn)),
            ],
            if (widget.canReset)
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(
                      context, const GEditSheetResult(reset: true)),
                  child: Text('恢复默认（删掉我的修改）',
                      style: TextStyle(fontSize: 13, color: k.danger)),
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }
}

Future<String?> showGNoteEditSheet(
  BuildContext context, {
  String initial = '',
  required bool isNew,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.k.surface,
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
    builder: (_) => _GNoteSheet(initial: initial, isNew: isNew),
  );
}

class _GNoteSheet extends StatefulWidget {
  const _GNoteSheet({required this.initial, required this.isNew});
  final String initial;
  final bool isNew;

  @override
  State<_GNoteSheet> createState() => _GNoteSheetState();
}

class _GNoteSheetState extends State<_GNoteSheet> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final ok = _ctl.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.isNew ? '添加笔记' : '我的笔记',
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: k.nSlate2,
                    side: BorderSide(color: k.g300),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: ok
                      ? () => Navigator.pop(context, _ctl.text.trim())
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: k.onbrand,
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('只存本机，显示在这一页末尾；换词库重导不丢。',
                style: TextStyle(fontSize: 12, height: 1.5, color: k.faint)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctl,
              onChanged: (_) => setState(() {}),
              minLines: 3,
              maxLines: 8,
              autofocus: widget.isNew,
              style: TextStyle(fontSize: 14, height: 1.6, color: k.text),
              decoration: InputDecoration(
                filled: true,
                fillColor: k.g100,
                hintText: '如：老师课上补充…',
                hintStyle: TextStyle(color: k.faint),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: k.g300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: k.g300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: k.brand),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

Future<String?> showGBlockTypePicker(
  BuildContext context, {
  required String pageTitle,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.k.surface,
    constraints:
        BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
    builder: (ctx) {
      final k = ctx.k;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('添加块 · $pageTitle',
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: k.nSlate2,
                    side: BorderSide(color: k.g300),
                  ),
                  child: const Text('取消'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('选一种类型，插入空模板到页尾（笔记前），之后可 ⋯ 移序。',
                style: TextStyle(fontSize: 12, height: 1.5, color: k.faint)),
            for (final e in kGBlockTypeNames.entries)
              InkWell(
                onTap: () => Navigator.pop(ctx, e.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(e.value,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(kGBlockTypeHelp[e.key] ?? '',
                            style:
                                TextStyle(fontSize: 11.5, color: k.faint)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      );
    },
  );
}