library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../grammar/grammar_edit.dart';
import '../../grammar/grammar_models.dart';
import '../../grammar/grammar_repo.dart';
import '../../theme/k_colors.dart';
import 'grammar_page_screen.dart';

class GrammarEditsScreen extends StatefulWidget {
  const GrammarEditsScreen({
    super.key,
    required this.repo,
    required this.scope,
  });

  final GrammarRepo repo;
  final String scope;

  @override
  State<GrammarEditsScreen> createState() => _GrammarEditsScreenState();
}

class _GrammarEditsScreenState extends State<GrammarEditsScreen> {
  List<GEditRow> _rows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final rows =
        await context.read<AppState>().db.allGrammarEdits(widget.scope);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loaded = true;
    });
  }

  Future<void> _jump(String pageId) async {
    await openGrammarPage(context, widget.repo, pageId);
    if (mounted) unawaited(_reload());
  }

  Future<void> _delete(GEditRow r) async {
    await context
        .read<AppState>()
        .db
        .deleteGrammarEdit(r.scope, r.pageId, r.blockKey);
    await _reload();
  }

  Future<void> _resetPage(String pageId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('整页恢复 · $title'),
        content: const Text('删掉这一页的全部修改与笔记，回到出厂内容。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复',
                  style: TextStyle(color: Color(0xFFD8574B)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().db.resetGrammarPage(widget.scope, pageId);
    await _reload();
  }

  void _view(GEditRow r) {
    final text = r.kind == kGKindNote
        ? gNoteText(r.payload)
        : gBlockToText(
            GBlock.fromJson(jsonDecode(r.payload) as Map<String, dynamic>));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改内容'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  String _snippet(GEditRow r) {
    final t = r.kind == kGKindNote
        ? gNoteText(r.payload)
        : gBlockToText(
            GBlock.fromJson(jsonDecode(r.payload) as Map<String, dynamic>));
    return t.replaceAll('\n', ' / ');
  }

  String _typeName(GEditRow r) {
    final t =
        (jsonDecode(r.payload) as Map<String, dynamic>)['t'] as String? ?? '';
    return kGBlockTypeNames[t] ?? '块';
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final byPage = <String, List<GEditRow>>{};
    for (final r in _rows) {
      byPage.putIfAbsent(r.pageId, () => []).add(r);
    }
    var nOv = 0, nNote = 0, nOr = 0;
    final groups = <Widget>[];
    for (final e in byPage.entries) {
      final page = widget.repo.pageById[e.key];
      final eff = applyGrammarEdits(
          page ?? GPage(id: e.key, title: e.key), e.value);

      final orphanKeys = {for (final o in eff.orphans) o.blockKey};
      final ov = [
        for (final r in e.value)
          if (r.kind == kGKindOverride && !orphanKeys.contains(r.blockKey)) r
      ];
      nOv += ov.length;
      nNote += eff.notes.length;
      nOr += eff.orphans.length;
      groups.add(_group(context, e.key, page?.title ?? e.key, ov, eff));
    }
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(
        backgroundColor: k.bg,
        elevation: 0,
        title: Text('我的修改与笔记',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: k.text)),
      ),
      body: !_loaded
          ? const SizedBox.shrink()
          : byPage.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('还没有修改或笔记。\n在阅读页点铅笔即可编辑，只存本机。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.6, color: k.faint)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text('${byPage.length} 页 · $nOv 条修改 · $nNote 条笔记 · $nOr 条未套用',
                        style: TextStyle(fontSize: 12, color: k.t2)),
                    ...groups,
                    const SizedBox(height: 14),
                    Text('修改与笔记只存在本机（grammar_edit 表），换词库重导不丢；随备份包导出 / 恢复。',
                        style: TextStyle(fontSize: 11.5, height: 1.6, color: k.faint)),
                  ],
                ),
    );
  }

  Widget _group(BuildContext context, String pageId, String title,
      List<GEditRow> ov, GEffectivePage eff) {
    final k = context.k;
    final rows = <Widget>[
      for (final r in ov)
        _row(context, r, '改·${_typeName(r)}', false,
            jump: () => _jump(pageId), reset: () => _delete(r)),
      for (final r in eff.notes)
        _row(context, r, '笔记', false,
            jump: () => _jump(pageId), reset: () => _delete(r)),
      for (final r in eff.orphans)
        _row(context, r, '未套用', true,
            jump: () => _view(r), reset: () => _delete(r)),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: k.sec)),
          ),
          Text('${rows.length} 条',
              style: TextStyle(fontSize: 11.5, color: k.t3)),
          const SizedBox(width: 8),
          InkWell(
            key: ValueKey('g-reset-page-$pageId'),
            onTap: () => _resetPage(pageId, title),
            child: Text('整页恢复',
                style: TextStyle(fontSize: 11.5, color: k.t3)),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: k.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: k.nEdge, width: 0.5),
          ),
          child: Column(children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Divider(height: 0.5, thickness: 0.5, color: k.line),
              r,
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _row(
    BuildContext context,
    GEditRow r,
    String chip,
    bool orphan, {
    required VoidCallback jump,
    required VoidCallback reset,
  }) {
    final k = context.k;
    return Container(
      color: orphan ? k.yellowTint : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: orphan
                ? const Color(0xFFF5E3C2)
                : (chip == '笔记' ? k.mntint : k.tint),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(chip,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: orphan ? k.brown : k.deep)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_snippet(r),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.5, color: k.text)),
            if (orphan)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('原文已更新，这条修改没对上块；可查看或删除。',
                    style: TextStyle(fontSize: 11, color: k.brown)),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: jump,
          child: Text(orphan ? '查看' : '跳转',
              style: TextStyle(fontSize: 12, color: k.deep)),
        ),
        const SizedBox(width: 10),
        InkWell(
          key: ValueKey('g-del-${r.blockKey}'),
          onTap: reset,
          child: Text(chip == '笔记' || orphan ? '删除' : '恢复',
              style: TextStyle(fontSize: 12, color: k.t3)),
        ),
      ]),
    );
  }
}