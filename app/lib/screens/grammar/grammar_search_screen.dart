library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../db.dart';
import '../../grammar/grammar_repo.dart';
import '../../theme/k_colors.dart';
import 'grammar_page_screen.dart';

const String kGramRecentKey = 'gram.recent';
const int kGramRecentMax = 8;

Future<List<String>> loadGramRecent(AppDb db) async {
  final raw = await db.metaGet(kGramRecentKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final v = jsonDecode(raw);
    return v is List ? [for (final x in v) x.toString()] : [];
  } catch (_) {
    return [];
  }
}

Future<void> pushGramRecent(AppDb db, String q) async {
  final t = q.trim();
  if (t.isEmpty) return;
  final cur = await loadGramRecent(db);
  final next = [t, ...cur.where((e) => e != t)].take(kGramRecentMax).toList();
  await db.metaSet(kGramRecentKey, jsonEncode(next));
}

class GrammarSearchScreen extends StatefulWidget {
  const GrammarSearchScreen({super.key, required this.repo});

  final GrammarRepo repo;

  @override
  State<GrammarSearchScreen> createState() => _GrammarSearchScreenState();
}

class _GrammarSearchScreenState extends State<GrammarSearchScreen> {
  final _ctl = TextEditingController();
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await loadGramRecent(context.read<AppState>().db);
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _open(String pageId) {
    final q = _ctl.text.trim();
    unawaited(pushGramRecent(context.read<AppState>().db, q));
    _recent = [q, ..._recent.where((e) => e != q)].take(kGramRecentMax).toList();
    openGrammarPage(context, widget.repo, pageId);
  }

  void _useRecent(String q) {
    _ctl.text = q;
    _ctl.selection = TextSelection.collapsed(offset: q.length);
    setState(() {});
  }

  Widget _empty(BuildContext context) {
    if (_recent.isEmpty) {
      return Center(
        child: Text('输入中文或印尼文，如「被动」「ter-」「yang」',
            style: TextStyle(fontSize: 12.5, color: context.k.nT3)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('最近搜索',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: context.k.sec)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final q in _recent)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _useRecent(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.k.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.k.nEdge, width: 0.5),
                  ),
                  child: Text(q, style: TextStyle(fontSize: 12.5, color: context.k.t2)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctl.text.trim();
    final hits = widget.repo.search(q);
    return Scaffold(
      backgroundColor: context.k.bg,
      appBar: AppBar(
        backgroundColor: context.k.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            key: const ValueKey('gram-search-field'),
            controller: _ctl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 14, color: context.k.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜语法点、词缀、术语',
              hintStyle: TextStyle(fontSize: 14, color: context.k.nT3),
              filled: true,
              fillColor: context.k.surface,
              prefixIcon: Icon(Icons.search, size: 18, color: context.k.nT3),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: context.k.nT3),
                      onPressed: () => setState(_ctl.clear),
                    ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.k.nEdge, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.k.nEdge, width: 0.5),
              ),
            ),
          ),
        ),
      ),
      body: q.isEmpty
          ? _empty(context)
          : hits.isEmpty
              ? Center(
                  child: Text('没有找到「$q」',
                      style: TextStyle(fontSize: 13, color: context.k.t2)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: hits.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 0.5, thickness: 0.5, color: context.k.nEdge),
                  itemBuilder: (_, i) {
                    final h = hits[i];
                    final sec = widget.repo.sectionById[h.page.section];
                    return InkWell(
                      key: ValueKey('gram-hit-${h.page.id}'),
                      onTap: () => _open(h.page.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(h.page.title,
                                      style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: context.k.text)),
                                  if (h.page.summary.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(h.page.summary,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              height: 1.4,
                                              color: context.k.t2)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(h.why.isEmpty ? (sec?.title ?? '') : h.why,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 11, color: context.k.nT3)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
