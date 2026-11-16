import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/k_colors.dart';
import '../widgets/sense_highlight.dart';
import '../widgets/word_tile.dart' show RingCheck;

class WordPickScreen extends StatefulWidget {
  final Set<String> existingIds;
  const WordPickScreen({super.key, required this.existingIds});

  @override
  State<WordPickScreen> createState() => _WordPickScreenState();
}

class _WordPickScreenState extends State<WordPickScreen> {
  final _ctl = TextEditingController();
  final _selected = <String>{};
  List<WordCard> _results = const [];
  bool _searching = false;
  String _query = '';
  Timer? _debounce;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _runSearch(v);
    });
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final app = context.read<AppState>();
    final r = await app.db.searchAll(q, limit: 50);
    if (!mounted || seq != _seq) return;
    setState(() {
      _query = q;
      _results = r;
      _searching = false;
    });
  }

  void _toggle(WordCard w) {
    if (widget.existingIds.contains(w.id)) return;
    setState(() {
      if (!_selected.remove(w.id)) _selected.add(w.id);
    });
  }

  void _done() => Navigator.pop(context, _selected.toList());

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('添加单词',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _done,
            style: TextButton.styleFrom(foregroundColor: k.deep),
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: k.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: k.line, width: 0.5),
            ),
            child: TextField(
              controller: _ctl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _runSearch,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '搜索印尼语或中文',
                hintStyle: TextStyle(fontSize: 13, color: k.nFaint2),
                prefixIcon:
                    Icon(Icons.search, size: 19, color: k.nFaint2),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                suffixIcon: _ctl.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _ctl.clear();
                          _runSearch('');
                        },
                        child: Icon(Icons.close, size: 17, color: k.nFaint2),
                      ),
              ),
            ),
          ),
        ),
        if (_query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _searching
                    ? '搜索中…'
                    : '「$_query」命中 ${_results.length} 个'
                        '${_results.length >= 50 ? '（已截断，请加关键词）' : ''}',
                style: TextStyle(fontSize: 11, color: k.nT3),
              ),
            ),
          ),
        Expanded(
          child: _searching && _results.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _query.isEmpty
                              ? '输入印尼语或中文，搜到就能加进词单。\n\n'
                                  '已经在这个词单里的词会灰显。'
                              : '没找到「$_query」。\n可以试试只输词根，或改用中文。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: k.nT3,
                              height: 1.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final w = _results[i];
                        return _PickRow(
                          card: w,
                          query: _query,
                          existing: widget.existingIds.contains(w.id),
                          selected: _selected.contains(w.id),
                          onTap: () => _toggle(w),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            decoration: BoxDecoration(
              color: k.surface,
              border: Border(top: BorderSide(color: k.line, width: 0.5)),
            ),
            child: Row(children: [
              Text('已选 ${_selected.length} 个',
                  style: TextStyle(fontSize: 12, color: k.nT2)),
              const Spacer(),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : _done,
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    disabledBackgroundColor: k.brand.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('添加到词单',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PickRow extends StatelessWidget {
  final WordCard card;
  final String query;
  final bool existing;
  final bool selected;
  final VoidCallback onTap;

  const _PickRow({
    required this.card,
    this.query = '',
    required this.existing,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final hl = resolveSenseHighlight(
      card: card,
      zh: card.zhClean,
      query: query,
    );
    final posPrefix = card.wordClassLabelsCombined.isNotEmpty
        ? '${card.wordClassLabelsCombined} · '
        : '';
    return Container(
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(
          bottom: BorderSide(color: k.line, width: 0.5),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: existing ? null : onTap,
        child: Opacity(
          opacity: existing ? 0.62 : 1,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(width: 12),
              RingCheck(
                selected: selected,
                member: existing,
                enabled: !existing,
                size: 24,
                onTap: onTap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(card.word,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (existing) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: k.nFaint2.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('已在词单',
                              style: TextStyle(
                                  fontSize: 9, color: k.nFaint2)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 11, color: k.nT3),
                        children: [
                          if (posPrefix.isNotEmpty) TextSpan(text: posPrefix),
                          if (hl.hasHighlight) ...[
                            TextSpan(
                              text: hl.highlightedPrefix,
                              style: TextStyle(
                                color: k.deep,
                                fontWeight: FontWeight.w600,
                                backgroundColor: k.tint,
                              ),
                            ),
                            if (hl.remainderText.isNotEmpty)
                              TextSpan(text: hl.remainderText),
                          ] else
                            TextSpan(text: hl.fullText),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ]),
          ),
        ),
      ),
    );
  }
}
