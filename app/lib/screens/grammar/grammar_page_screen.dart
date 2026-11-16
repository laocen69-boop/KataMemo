library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

import '../../ai_chat.dart' show AiChatContext, aiGrammarContext;
import '../../app_state.dart';
import '../../grammar/grammar_copy.dart';
import '../../grammar/grammar_edit.dart';
import '../../grammar/grammar_models.dart';
import '../../grammar/grammar_repo.dart';
import '../../theme/k_colors.dart';
import '../../version.dart' show kAiChat;
import '../../widgets/ai_chat_sheet.dart' show showAiChat;
import '../../widgets/ai_widgets.dart' show AiAppBarButton, AiContextHub;
import '../../widgets/copy_text.dart';
import '../../widgets/grammar/g_blocks.dart';
import '../../widgets/grammar/g_edit_sheet.dart';
import 'drill_runner_screen.dart';

Future<void> openGrammarPage(BuildContext context, GrammarRepo repo, String pageId) {
  final p = repo.pageById[pageId];
  if (p == null) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GrammarPageScreen(repo: repo, page: p)));
}

Future<Set<String>> loadSeenPages(BuildContext context) async {
  try {
    final all = await context.read<AppState>().db.allGrammarProgress();
    return {
      for (final e in all.entries)
        if (e.value.seenAt != null) e.key
    };
  } catch (_) {
    return {};
  }
}

class GrammarPageListScreen extends StatefulWidget {
  const GrammarPageListScreen({
    super.key,
    required this.repo,
    required this.title,
    required this.groups,
    this.subtitle = '',
    this.numbered = false,
  });

  factory GrammarPageListScreen.section(GrammarRepo repo, GSection s) =>
      GrammarPageListScreen(
        repo: repo,
        title: s.title,
        subtitle: s.subtitle,
        groups: s.groups,
      );

  factory GrammarPageListScreen.path(GrammarRepo repo) =>
      GrammarPageListScreen(
        repo: repo,
        title: '学习路线',
        subtitle: '从零开始，按这个顺序读一遍就能搭起整体框架。',
        groups: [GGroup(pages: repo.doc.path)],
        numbered: true,
      );

  final GrammarRepo repo;
  final String title;
  final String subtitle;
  final List<GGroup> groups;
  final bool numbered;

  @override
  State<GrammarPageListScreen> createState() => _GrammarPageListScreenState();
}

class _GrammarPageListScreenState extends State<GrammarPageListScreen> {
  Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final s = await loadSeenPages(context);
    if (mounted) setState(() => _seen = s);
  }

  Future<void> _open(GPage p) async {
    await openGrammarPage(context, widget.repo, p.id);
    if (mounted) unawaited(_reload());
  }

  List<GQuiz> get _allQuiz => [
        for (final g in widget.groups)
          for (final id in g.pages) ...?widget.repo.quizByPage[id],
      ];

  @override
  Widget build(BuildContext context) {
    final quiz = _allQuiz;
    var no = 0;
    return Scaffold(
      backgroundColor: context.k.bg,
      appBar: AppBar(
        backgroundColor: context.k.bg,
        elevation: 0,
        title: Text(widget.title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: context.k.text)),
        actions: [
          if (quiz.isNotEmpty)
            TextButton(
              key: const ValueKey('gram-list-quiz'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DrillRunnerScreen(
                      drills: quiz, title: '练习 · ${widget.title}'))),
              child: Text('练习 ${quiz.length}',
                  style: TextStyle(fontSize: 13, color: context.k.deep)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
        children: [
          if (widget.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(widget.subtitle,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: context.k.t2)),
            ),
          for (final g in widget.groups) ...[
            if (g.title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 10, 0, 6),
                child: Text(g.title,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.k.sec)),
              ),
            Container(
              decoration: BoxDecoration(
                color: context.k.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.k.nEdge, width: 0.5),
              ),
              child: Column(
                children: [
                  for (final (i, p) in widget.repo.pagesOf(g.pages).indexed) ...[
                    if (i > 0)
                      Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 14,
                          color: context.k.nEdge),
                    _row(context, p, widget.numbered ? ++no : null),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, GPage p, int? no) {
    final seen = _seen.contains(p.id);
    return InkWell(
      key: ValueKey('gram-row-${p.id}'),
      onTap: () => _open(p),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            if (no != null)
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: seen ? context.k.brand : context.k.tint,
                  shape: BoxShape.circle,
                ),
                child: Text('$no',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: seen ? context.k.onbrand : context.k.deep)),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: context.k.text)),
                  if (p.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(p.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.4, color: context.k.t2)),
                    ),
                ],
              ),
            ),
            if (seen && no == null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.check, size: 16, color: context.k.brand),
              ),
            Icon(Icons.chevron_right, size: 18, color: context.k.nT3),
          ],
        ),
      ),
    );
  }
}

class GrammarPageScreen extends StatefulWidget {
  const GrammarPageScreen({
    super.key,
    required this.repo,
    required this.page,
    this.dwell = const Duration(seconds: 3),
  });

  final GrammarRepo repo;
  final GPage page;

  final Duration dwell;

  @override
  State<GrammarPageScreen> createState() => _GrammarPageScreenState();
}

class _GrammarPageScreenState extends State<GrammarPageScreen> {
  static const double _indexHeight = 46;

  Timer? _dwellTimer;
  final Map<int, GlobalKey> _headKeys = {};
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<int> _activeSection = ValueNotifier<int>(0);
  List<GlobalKey> _indexedKeys = const [];
  bool _jumping = false;

  GEffectivePage? _eff;
  bool _hasEdits = false;
  late final String _scope;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final db = context.read<AppState>().db;
    final id = widget.page.id;
    _scope = identical(widget.repo, context.read<AppState>().grammar)
        ? kGScopeGrammar
        : kGScopeWriting;
    _dwellTimer = Timer(widget.dwell, () => db.markGrammarSeen(id));

    if (_scope == kGScopeGrammar) {
      unawaited(db.setGrammarLastCard(id));
    }

    if (kAiChat) AiContextHub.push(this, _aiContext);
    unawaited(_reloadEdits());
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _activeSection.dispose();
    AiContextHub.pop(this);
    _dwellTimer?.cancel();
    super.dispose();
  }

  Future<void> _reloadEdits() async {
    final rows =
        await context.read<AppState>().db.grammarEdits(_scope, widget.page.id);
    if (!mounted) return;
    setState(() {
      _hasEdits = rows.isNotEmpty;
      _eff = applyGrammarEdits(widget.page, rows);
    });
  }

  Future<void> _resetPage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置本页'),
        content: const Text(
          '将该页恢复为初始默认内容，撤销本页的所有块修改、删除、排序与笔记。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('重置', style: TextStyle(color: context.k.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().db.resetGrammarPage(_scope, widget.page.id);
    await _reloadEdits();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已重置为默认内容'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  List<Map<String, dynamic>> get _entries =>
      [for (final e in (_eff?.entries ?? const [])) Map<String, dynamic>.from(e)];

  Future<void> _saveLayout(List<Map<String, dynamic>> entries) async {
    await context.read<AppState>().db.saveGrammarEdit(GEditRow(
        scope: _scope,
        pageId: widget.page.id,
        blockKey: kGLayoutKey,
        kind: kGKindLayout,
        payload: jsonEncode(entries),
        ts: _now));
    await _reloadEdits();
  }

  Future<void> _saveSingleBlock(int i, GBlock parsedBlock,
      {bool reload = true}) async {
    final eff = _eff;
    if (eff == null) return;
    final added = eff.added[i];
    final key = eff.keys[i];
    final json = gBlockToJson(parsedBlock);
    if (added) {
      final es = _entries;
      es[i] = {'a': json};
      await _saveLayout(es);
      return;
    }
    await context.read<AppState>().db.saveGrammarEdit(GEditRow(
        scope: _scope,
        pageId: widget.page.id,
        blockKey: key,
        kind: kGKindOverride,
        payload: jsonEncode(json),
        ts: _now));
    if (reload) await _reloadEdits();
  }

  Future<void> _editBlock(int i, {int? pairedBodyIndex}) async {
    final eff = _eff;
    if (eff == null) return;
    if (pairedBodyIndex != null) {
      final hBlock = eff.blocks[i] as GHeadingBlock;
      final bodyBlock = eff.blocks[pairedBodyIndex];
      final hKey = eff.keys[i];
      final bKey = eff.keys[pairedBodyIndex];
      final hAdded = eff.added[i];
      final bAdded = eff.added[pairedBodyIndex];
      final canReset = hAdded ||
          bAdded ||
          eff.editedKeys.contains(hKey) ||
          eff.editedKeys.contains(bKey);
      final res = await showGBlockEditSheet(
        context,
        pageTitle: widget.page.title,
        headingBlock: hBlock,
        block: bodyBlock,
        canReset: canReset,
      );
      if (res == null || !mounted) return;
      final db = context.read<AppState>().db;
      if (res.reset) {
        if (!hAdded) await db.deleteGrammarEdit(_scope, widget.page.id, hKey);
        if (!bAdded) await db.deleteGrammarEdit(_scope, widget.page.id, bKey);
        if (hAdded || bAdded) {
          final es = _entries;
          if (bAdded) es.removeAt(pairedBodyIndex);
          if (hAdded) es.removeAt(i);
          await _saveLayout(es);
        } else {
          await _reloadEdits();
        }
        return;
      }
      var changed = false;
      final newH = (res.headingText ?? '').trim();
      if (newH.isNotEmpty && newH != hBlock.text) {
        await _saveSingleBlock(i, GHeadingBlock(newH), reload: false);
        changed = true;
      }
      final parsed = gParseBlock(gBlockTypeOf(bodyBlock), res.text!);
      if (parsed.ok) {
        await _saveSingleBlock(pairedBodyIndex, parsed.block!, reload: false);
        changed = true;
      }
      if (changed) await _reloadEdits();
      return;
    }

    final added = eff.added[i];
    final key = eff.keys[i];
    final res = await showGBlockEditSheet(context,
        pageTitle: widget.page.title,
        block: eff.blocks[i],
        canReset: added || eff.editedKeys.contains(key));
    if (res == null || !mounted) return;
    final db = context.read<AppState>().db;
    if (res.reset) {
      if (added) {
        await _saveLayout(_entries..removeAt(i));
      } else {
        await db.deleteGrammarEdit(_scope, widget.page.id, key);
        await _reloadEdits();
      }
      return;
    }
    final parsed = gParseBlock(gBlockTypeOf(eff.blocks[i]), res.text!);
    if (!parsed.ok) return;
    await _saveSingleBlock(i, parsed.block!);
  }

  Future<void> _moveBlock(int i, int delta, {int count = 1}) async {
    final es = _entries;
    if (count == 1) {
      final j = i + delta;
      if (j < 0 || j >= es.length) return;
      final t = es[i];
      es[i] = es[j];
      es[j] = t;
      await _saveLayout(es);
      return;
    }
    if (delta < 0 && i > 0) {
      final slice = es.sublist(i, i + count);
      es.removeRange(i, i + count);
      es.insertAll(i - 1, slice);
      await _saveLayout(es);
    } else if (delta > 0 && i + count < es.length) {
      final slice = es.sublist(i, i + count);
      es.removeRange(i, i + count);
      es.insertAll(i + 1, slice);
      await _saveLayout(es);
    }
  }

  Future<void> _deleteBlock(int i, {int count = 1}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count > 1 ? '删除小节' : '删除块'),
        content: Text(count > 1
            ? '删掉这一页上的这个小节（含小标题与内容）。只影响本机显示，可点右上角「重置本页」或在「我的修改与笔记」整页恢复。'
            : '删掉这一页上的这个块。只影响本机显示，可点右上角「重置本页」或在「我的修改与笔记」整页恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除',
                  style: TextStyle(color: Color(0xFFD8574B)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final es = _entries..removeRange(i, i + count);
    await _saveLayout(es);
  }

  Future<void> _addBlock() async {
    final type =
        await showGBlockTypePicker(context, pageTitle: widget.page.title);
    if (type == null || !mounted) return;
    final res = await showGBlockEditSheet(context,
        pageTitle: widget.page.title,
        block: gTemplateBlock(type),
        canReset: false);
    if (res == null || res.reset || !mounted) return;
    final parsed = gParseBlock(type, res.text!);
    if (!parsed.ok) return;
    await _saveLayout(_entries..add({'a': gBlockToJson(parsed.block!)}));
  }

  Future<void> _addNote() async {
    final text = await showGNoteEditSheet(context, isNew: true);
    if (text == null || !mounted) return;
    final ts = _now;
    await context.read<AppState>().db.saveGrammarEdit(GEditRow(
        scope: _scope,
        pageId: widget.page.id,
        blockKey: 'note:$ts',
        kind: kGKindNote,
        payload: gNotePayload(text),
        ts: ts));
    await _reloadEdits();
  }

  Future<void> _editNote(GEditRow n) async {
    final text = await showGNoteEditSheet(context,
        initial: gNoteText(n.payload), isNew: false);
    if (text == null || !mounted) return;
    await context.read<AppState>().db.saveGrammarEdit(GEditRow(
        scope: _scope,
        pageId: widget.page.id,
        blockKey: n.blockKey,
        kind: kGKindNote,
        payload: gNotePayload(text),
        ts: _now));
    await _reloadEdits();
  }

  Future<void> _deleteNote(GEditRow n) async {
    await context
        .read<AppState>()
        .db
        .deleteGrammarEdit(_scope, widget.page.id, n.blockKey);
    await _reloadEdits();
  }

  String get _effectiveText {
    final p = widget.page;
    final eff = _eff;
    final base = grammarPagePlainText(eff == null
        ? p
        : GPage(
            id: p.id,
            title: p.title,
            titleId: p.titleId,
            summary: p.summary,
            blocks: eff.blocks));
    if (eff == null || eff.notes.isEmpty) return base;
    final b = StringBuffer(base);
    for (final n in eff.notes) {
      b.writeln();
      b.writeln('【我的笔记】');
      b.writeln(gNoteText(n.payload));
    }
    return b.toString();
  }

  AiChatContext _aiContext() => aiGrammarContext(
      id: widget.page.id,
      title: widget.page.title,
      text: _effectiveText);

  void _onScroll() {
    if (_jumping) return;
    if (!_scroll.hasClients || _indexedKeys.isEmpty) return;
    final top = _scroll.position.pixels + _indexHeight + 8;
    var active = 0;
    for (var i = 0; i < _indexedKeys.length; i++) {
      final ctx = _indexedKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final off =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      if (off <= top) {
        active = i;
      } else {
        break;
      }
    }
    if (active != _activeSection.value) _activeSection.value = active;
  }

  void _jump(int blockIndex) {
    final key = _headKeys[blockIndex];
    final c = key?.currentContext;
    if (c == null) return;
    final box = c.findRenderObject();
    if (_scroll.hasClients && box is RenderBox && box.hasSize) {
      final raw =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset -
              _indexHeight;
      final to = raw.clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
      final idx = _indexedKeys.indexOf(key!);
      _jumping = true;
      _scroll
          .animateTo(to,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic)
          .whenComplete(() => _jumping = false);
      if (idx >= 0 && idx != _activeSection.value) _activeSection.value = idx;
      return;
    }
    Scrollable.ensureVisible(c,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        alignment: 0.02);
  }

  Widget _badge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: context.k.tint,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('已改',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: context.k.deep)),
      );

  Widget _penBtn(int i, {int? pairedBodyIndex}) => SizedBox(
        width: 22,
        height: 22,
        child: InkWell(
          key: ValueKey('g-edit-$i'),
          onTap: () => _editBlock(i, pairedBodyIndex: pairedBodyIndex),
          child: Icon(Icons.edit_outlined, size: 16, color: context.k.faint),
        ),
      );

  Widget _moreBtn(int i, {int count = 1}) => SizedBox(
        width: 22,
        height: 22,
        child: PopupMenuButton<String>(
          key: ValueKey('g-more-$i'),
          padding: EdgeInsets.zero,
          tooltip: count > 1 ? '小节操作' : '块操作',
          icon: Icon(Icons.more_vert, size: 16, color: context.k.faint),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'up', child: Text('上移')),
            const PopupMenuItem(value: 'down', child: Text('下移')),
            PopupMenuItem(
                value: 'del', child: Text(count > 1 ? '删除小节' : '删除块')),
          ],
          onSelected: (v) {
            switch (v) {
              case 'up':
                unawaited(_moveBlock(i, -1, count: count));
              case 'down':
                unawaited(_moveBlock(i, 1, count: count));
              case 'del':
                unawaited(_deleteBlock(i, count: count));
            }
          },
        ),
      );

  Widget _wrapPairedSection(int i, GHeadingBlock h, GBlock body) {
    final eff = _eff;
    final hKey = eff?.keys[i];
    final bKey = eff?.keys[i + 1];
    final edited = (hKey != null && (eff?.editedKeys.contains(hKey) ?? false)) ||
        (bKey != null && (eff?.editedKeys.contains(bKey) ?? false));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            GBlockView(block: h),
            Positioned(
                top: 8,
                right: 0,
                child: _penBtn(i, pairedBodyIndex: i + 1)),
            Positioned(top: 8, right: 24, child: _moreBtn(i, count: 2)),
            if (edited) Positioned(top: 7, right: 48, child: _badge()),
          ],
        ),
        const SizedBox(height: 6),
        GBlockView(block: body),
      ],
    );
  }

  Widget _wrapBlock(int i, GBlock b) {
    final eff = _eff;
    final key = eff?.keys[i];
    final edited = key != null && (eff?.editedKeys.contains(key) ?? false);
    final view = GBlockView(block: b);

    if (b is GTextBlock) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (edited) _badge(),
          _moreBtn(i),
          _penBtn(i),
        ]),
        view,
      ]);
    }
    final isH = b is GHeadingBlock;
    return Stack(children: [
      view,
      Positioned(top: isH ? 8 : 6, right: isH ? 0 : 6, child: _penBtn(i)),
      Positioned(top: isH ? 8 : 6, right: isH ? 24 : 30, child: _moreBtn(i)),
      if (edited)
        Positioned(top: 7, right: isH ? 48 : 56, child: _badge()),
    ]);
  }

  Widget _noteCard(GEditRow n) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: context.k.mntint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.k.mnDash),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('我的笔记',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.k.deep)),
            ),
            InkWell(
              key: ValueKey('g-note-edit-${n.blockKey}'),
              onTap: () => _editNote(n),
              child: Icon(Icons.edit_outlined, size: 14, color: context.k.t3),
            ),
            const SizedBox(width: 8),
            InkWell(
              key: ValueKey('g-note-del-${n.blockKey}'),
              onTap: () => _deleteNote(n),
              child: Icon(Icons.delete_outline, size: 14, color: context.k.t3),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(gNoteText(n.payload),
                style: TextStyle(fontSize: 13.5, height: 1.6, color: context.k.text)),
          ),
        ]),
      );

  Widget _dashBtn(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.k.nEdge, width: 0.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add, size: 16, color: context.k.t2),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: context.k.t2)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final section = widget.repo.sectionById[p.section];
    final quiz = widget.repo.quizByPage[p.id] ?? const <GQuiz>[];
    final eff = _eff;
    final blocks = eff?.blocks ?? p.blocks;
    final heads = [
      for (final (i, b) in blocks.indexed)
        if (b is GHeadingBlock) (i, b.text)
    ];
    _indexedKeys = [
      for (final (i, _) in heads) _headKeys.putIfAbsent(i, GlobalKey.new),
    ];
    final see = widget.repo.pagesOf(p.see);
    return Scaffold(
      backgroundColor: context.k.bg,
      appBar: AppBar(
        backgroundColor: context.k.bg,
        elevation: 0,
        title: Text(section?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: context.k.t2)),
        actions: [
          if (_hasEdits)
            IconButton(
              key: const ValueKey('grammar.resetPage'),
              tooltip: '重置本页',
              icon: const Icon(Icons.restart_alt, size: 20),
              onPressed: () => unawaited(_resetPage()),
            ),

          if (kAiChat)
            AiAppBarButton(
              key: const ValueKey('grammar.askAi'),
              tooltip: '问 AI 这一页',
              onTap: () => showAiChat(context, _aiContext()),
            ),
          IconButton(
            tooltip: '复制本文',
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () =>
                copyText(context, _effectiveText, label: '已复制本文'),
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      style: TextStyle(
                          fontSize: 20,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: context.k.text)),
                  if (p.titleId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(p.titleId,
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: context.k.nT3)),
                    ),
                  if (p.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(p.summary,
                          style: TextStyle(
                              fontSize: 13, height: 1.5, color: context.k.t2)),
                    ),
                ],
              ),
            ),
          ),
          if (heads.length >= 2)
            SliverPersistentHeader(
              pinned: true,
              delegate: _GrammarIndexBarDelegate(
                entries: heads,
                active: _activeSection,
                onTap: (idx) => _jump(heads[idx].$1),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    if (blocks[i] is GHeadingBlock &&
                        i + 1 < blocks.length &&
                        blocks[i + 1] is! GHeadingBlock) ...[
                      Padding(
                        key: _headKeys.putIfAbsent(i, GlobalKey.new),
                        padding: const EdgeInsets.only(top: 12),
                        child: _wrapPairedSection(
                          i,
                          blocks[i] as GHeadingBlock,
                          blocks[i + 1],
                        ),
                      ),

                      if (() {
                        i++;
                        return false;
                      }())
                        const SizedBox.shrink(),
                    ] else
                      Padding(
                        key: blocks[i] is GHeadingBlock
                            ? _headKeys.putIfAbsent(i, GlobalKey.new)
                            : null,
                        padding: const EdgeInsets.only(top: 12),
                        child: _wrapBlock(i, blocks[i]),
                      ),
                  ],
                  if (eff != null)
                    for (final n in eff.notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _noteCard(n),
                      ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(children: [
                      Expanded(
                          child: _dashBtn('添加块', () => unawaited(_addBlock()))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _dashBtn('添加笔记', () => unawaited(_addNote()))),
                    ]),
                  ),
                  if (see.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('相关知识点',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.k.sec)),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final s in see)
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () =>
                                openGrammarPage(context, widget.repo, s.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: context.k.nEdge, width: 0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text('${s.title} ›',
                                  style: TextStyle(
                                      fontSize: 12.5, color: context.k.t2)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: quiz.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    key: const ValueKey('gram-page-quiz'),
                    style: FilledButton.styleFrom(
                        backgroundColor: context.k.brand,
                        foregroundColor: context.k.onbrand),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            DrillRunnerScreen(drills: quiz, title: '练习 · ${p.title}'))),
                    child: Text('做练习 · ${quiz.length} 题',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
    );
  }
}

class _GrammarIndexBarDelegate extends SliverPersistentHeaderDelegate {
  final List<(int, String)> entries;
  final ValueListenable<int> active;
  final ValueChanged<int> onTap;

  _GrammarIndexBarDelegate({
    required this.entries,
    required this.active,
    required this.onTap,
  });

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _GrammarIndexBar(
      entries: entries,
      active: active,
      onTap: onTap,
    );
  }

  @override
  bool shouldRebuild(covariant _GrammarIndexBarDelegate old) =>
      old.entries != entries || old.active != active;
}

class _GrammarIndexBar extends StatefulWidget {
  final List<(int, String)> entries;
  final ValueListenable<int> active;
  final ValueChanged<int> onTap;

  const _GrammarIndexBar({
    required this.entries,
    required this.active,
    required this.onTap,
  });

  @override
  State<_GrammarIndexBar> createState() => _GrammarIndexBarState();
}

class _GrammarIndexBarState extends State<_GrammarIndexBar> {
  final ScrollController _tocScroll = ScrollController();
  List<GlobalKey> _pillKeys = const [];

  @override
  void initState() {
    super.initState();
    _syncKeys();
    widget.active.addListener(_onActiveChanged);
  }

  @override
  void didUpdateWidget(covariant _GrammarIndexBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      oldWidget.active.removeListener(_onActiveChanged);
      widget.active.addListener(_onActiveChanged);
    }
    if (oldWidget.entries.length != widget.entries.length) {
      _syncKeys();
    }
  }

  @override
  void dispose() {
    widget.active.removeListener(_onActiveChanged);
    _tocScroll.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _pillKeys = List.generate(widget.entries.length, (_) => GlobalKey());
  }

  void _onActiveChanged() {
    if (!mounted || widget.entries.isEmpty) return;
    final idx = widget.active.value.clamp(0, widget.entries.length - 1).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || idx >= _pillKeys.length || !_tocScroll.hasClients) return;
      final ctx = _pillKeys[idx].currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final vp = RenderAbstractViewport.maybeOf(box);
      if (vp == null) return;
      final target = vp
          .getOffsetToReveal(box, 0.5)
          .offset
          .clamp(0.0, _tocScroll.position.maxScrollExtent)
          .toDouble();
      if ((target - _tocScroll.offset).abs() < 1.0) return;
      _tocScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.active,
      builder: (context, value, _) {
        final current = widget.entries.isEmpty
            ? 0
            : value.clamp(0, widget.entries.length - 1).toInt();
        return Container(
          key: const ValueKey('gram-toc'),
          decoration: BoxDecoration(
            color: context.k.bg,
            border:
                Border(bottom: BorderSide(color: context.k.nEdge, width: 0.5)),
          ),
          child: SingleChildScrollView(
            controller: _tocScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < widget.entries.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Builder(builder: (ctx) {
                    final (_, label) = widget.entries[i];
                    final on = i == current;
                    return Center(
                      key: _pillKeys[i],
                      child: GestureDetector(
                        key: ValueKey('gram-index-$i'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onTap(i),
                        child: Semantics(
                          button: true,
                          selected: on,
                          label: label,
                          child: Container(
                            height: 29,
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            decoration: BoxDecoration(
                              color: on ? context.k.tint : context.k.surface,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: on ? context.k.tint : context.k.nEdge,
                                  width: 0.5),
                            ),
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight:
                                      on ? FontWeight.w700 : FontWeight.w600,
                                  color: on ? context.k.deep : context.k.t2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}