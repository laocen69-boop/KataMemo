library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../grammar/grammar_edit.dart';
import '../../grammar/grammar_models.dart';
import '../../grammar/grammar_repo.dart';
import '../../theme/k_colors.dart';
import 'grammar_edits_screen.dart';
import 'grammar_page_screen.dart';
import 'grammar_search_screen.dart';

class GrammarHubScreen extends StatefulWidget {
  const GrammarHubScreen({super.key, this.writing = false});

  final bool writing;

  @override
  State<GrammarHubScreen> createState() => _GrammarHubScreenState();
}

class _GrammarHubScreenState extends State<GrammarHubScreen> {
  String? _last;
  Set<String> _seen = {};
  bool _scheduled = false;

  GrammarRepo get _repo {
    final app = context.read<AppState>();
    return widget.writing ? app.writing : app.grammar;
  }

  @override
  void initState() {
    super.initState();
    if (widget.writing) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_repo.ensureLoaded()));
    }
  }

  void _maybeLoad(GrammarRepo repo) {
    if (!repo.ready || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final db = context.read<AppState>().db;
    final last = widget.writing ? null : await db.grammarLastCard();
    if (!mounted) return;
    final seen = await loadSeenPages(context);
    if (!mounted) return;
    setState(() {
      _last = last;
      _seen = seen;
    });
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) unawaited(_reload());
  }

  Future<void> _openPage(String id) async {
    await openGrammarPage(context, _repo, id);
    if (mounted) unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {

    final repo = _repo;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        _maybeLoad(repo);
        return Scaffold(
          backgroundColor: context.k.bg,
          appBar: AppBar(
            title: Text(widget.writing ? '写作' : '语法'),
            titleTextStyle: mainAppBarTitleStyle(context),
            actions: [
              IconButton(
                key: const ValueKey('gram-my-edits'),
                tooltip: '我的修改与笔记',
                icon: Icon(Icons.edit_note_outlined,
                    size: 22, color: context.k.deep),
                onPressed: () => _push(GrammarEditsScreen(
                    repo: repo,
                    scope:
                        widget.writing ? kGScopeWriting : kGScopeGrammar)),
              ),
            ],
          ),
          body: _body(context, repo),
        );
      },
    );
  }

  Widget _body(BuildContext context, GrammarRepo repo) {
    if (repo.error != null && !repo.ready) return _fail(context, repo);
    if (!repo.ready) {

      return Center(
        child: Text('内容加载中…', style: TextStyle(fontSize: 13, color: context.k.nT3)),
      );
    }
    final d = repo.doc;
    final last = _last == null ? null : repo.pageById[_last];
    final hot = repo.pagesOf(d.hot);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _searchBar(context, repo),
        if (last != null) ...[
          const SizedBox(height: 12),
          _continueCard(context, last),
        ],
        if (hot.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label(context, '常查'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final p in hot)
                InkWell(
                  key: ValueKey('gram-hot-${p.id}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _openPage(p.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: context.k.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.k.nEdge, width: 0.5),
                    ),
                    child: Text(p.title,
                        style: TextStyle(fontSize: 12.5, color: context.k.deep)),
                  ),
                ),
            ],
          ),
        ],
        if (d.path.isNotEmpty) ...[
          const SizedBox(height: 16),
          _pathCard(context, repo),
        ],
        const SizedBox(height: 16),
        _label(context, '全部分区'),
        const SizedBox(height: 8),
        for (final s in d.sections) ...[
          _sectionCard(context, repo, s),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _label(BuildContext context, String t) => Text(t,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: context.k.sec));

  Widget _fail(BuildContext context, GrammarRepo repo) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 30, color: context.k.nT3),
              const SizedBox(height: 10),
              Text('内容加载失败',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.k.text)),
              const SizedBox(height: 6),
              Text('内容随 App 一起发布，这次没读到。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: context.k.t2)),
              const SizedBox(height: 12),
              TextButton(onPressed: repo.retry, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _searchBar(BuildContext context, GrammarRepo repo) => InkWell(
        key: const ValueKey('gram-search'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _push(GrammarSearchScreen(repo: repo)),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.k.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.k.nEdge, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: context.k.nT3),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.writing ? '搜文体 / 句型' : '搜语法点，如 me-kan、重叠、yang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.k.nT3)),
              ),
            ],
          ),
        ),
      );

  Widget _continueCard(BuildContext context, GPage p) => InkWell(
        key: const ValueKey('gram-continue'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPage(p.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: context.k.tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 20, color: context.k.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('上次看到', style: TextStyle(fontSize: 11, color: context.k.deep)),
                    const SizedBox(height: 2),
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: context.k.text)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.k.nT3),
            ],
          ),
        ),
      );

  Widget _pathCard(BuildContext context, GrammarRepo repo) {
    final ids = repo.doc.path;
    final done = ids.where(_seen.contains).length;
    return InkWell(
      key: const ValueKey('gram-path'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _push(GrammarPageListScreen.path(repo)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 12, 12),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.k.nEdge, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.route_outlined, size: 20, color: context.k.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('学习路线',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.k.text)),
                  const SizedBox(height: 2),
                  Text('第一次学按这个顺序读 ${ids.length} 页',
                      style: TextStyle(fontSize: 12, color: context.k.t2)),
                ],
              ),
            ),
            Text('$done / ${ids.length}',
                style: TextStyle(fontSize: 12, color: context.k.nT3)),
            Icon(Icons.chevron_right, size: 18, color: context.k.nT3),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, GrammarRepo repo, GSection s) {
    final ids = s.pageIds;
    final done = ids.where(_seen.contains).length;
    return InkWell(
      key: ValueKey('gram-sec-${s.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _push(GrammarPageListScreen.section(repo, s)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 10, 12),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.k.nEdge, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: context.k.text)),
                  if (s.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(s.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.4, color: context.k.t2)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(done > 0 ? '$done / ${ids.length}' : '${ids.length} 页',
                style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
            Icon(Icons.chevron_right, size: 18, color: context.k.nT3),
          ],
        ),
      ),
    );
  }
}
