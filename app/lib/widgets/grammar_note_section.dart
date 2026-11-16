

library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../grammar/grammar_models.dart';
import '../theme/k_colors.dart';
import '../models.dart';
import '../screens/grammar/grammar_page_screen.dart';
import 'speak_button.dart' show kSpeakGreen;
import 'tappable_text.dart';
import 'word_sheet.dart';

class GrammarNoteSection extends StatelessWidget {
  final List<GrammarNote> notes;

  final int? limit;

  final bool bare;

  final OpenWordDetail? onOpenDetail;

  final String? wordId;

  const GrammarNoteSection({
    super.key,
    required this.notes,
    this.limit = 4,
    this.onOpenDetail,
    this.bare = false,
    this.wordId,
  });

  static bool has(BuildContext context, WordCard card) {
    if (card.grammarNotes.isNotEmpty) return true;
    final g = context.read<AppState>().grammar;
    return g.ready && g.pagesForWord(card.id).isNotEmpty;
  }

  static String label(WordCard card) => card.grammarNotes.isEmpty ? '语法' : '用法';

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return _buildLinkOnly(context);
    final shown = limit == null ? notes : notes.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final n in shown) _buildOne(context, n),
        if (notes.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('还有 ${notes.length - shown.length} 条用法，见详情页',
                style: TextStyle(fontSize: 11.5, color: context.k.nFaint2)),
          ),

        _buildGrammarLink(context),
      ],
    );
  }

  Widget _buildGrammarLink(BuildContext context) {
    final id = wordId;
    if (id == null) return const SizedBox.shrink();
    final grammar = context.read<AppState>().grammar;
    if (!grammar.ready) return const SizedBox.shrink();
    final hits = grammar.pagesForWord(id);
    if (hits.isEmpty) return const SizedBox.shrink();
    final page = _firstGrammarPage(hits);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          key: const ValueKey('grammar-note-link'),
          borderRadius: BorderRadius.circular(6),
          onTap: () => openGrammarPage(context, grammar, page.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Text('查看语法 ›',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: context.k.deep)),
          ),
        ),
      ),
    );
  }

  Widget _buildLinkOnly(BuildContext context) {
    final id = wordId;
    if (id == null) return const SizedBox.shrink();
    final grammar = context.read<AppState>().grammar;
    if (!grammar.ready) return const SizedBox.shrink();
    final hits = grammar.pagesForWord(id);
    if (hits.isEmpty) return const SizedBox.shrink();
    final page = _firstGrammarPage(hits);
    return InkWell(
      key: const ValueKey('grammar-note-link'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => openGrammarPage(context, grammar, page.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: context.k.deep),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '语法讲解：',
                      style: TextStyle(fontSize: 12.5, color: context.k.t2)),
                  TextSpan(
                      text: page.title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.k.deep)),
                  if (hits.length > 1)
                    TextSpan(
                        text: ' 等 ${hits.length} 页',
                        style: TextStyle(fontSize: 12, color: context.k.nT3)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.k.nT3),
          ],
        ),
      ),
    );
  }

  static const _sectionRank = ['wordclass', 'affix', 'contrast', 'cross'];

  static GPage _firstGrammarPage(List<GPage> hits) {
    int rank(GPage p) {
      final i = _sectionRank.indexOf(p.section);
      return i < 0 ? _sectionRank.length : i;
    }

    var best = hits.first;
    var bestRank = rank(best);
    for (final c in hits.skip(1)) {
      final r = rank(c);
      if (r < bestRank) {
        best = c;
        bestRank = r;
      }
    }
    return best;
  }

  Widget _buildOne(BuildContext context, GrammarNote n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: bare
          ? null
          : BoxDecoration(
              color: kSpeakGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                    color: kSpeakGreen.withValues(alpha: 0.55), width: 3),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (n.zh.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                if (n.tag.isNotEmpty && n.tag != '用法') ...[
                  Text(n.tag,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D62))),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(n.zh,
                      style: const TextStyle(fontSize: 13.5, height: 1.45)),
                ),
              ],
            ),
          for (final e in n.examples) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· ',
                    style: TextStyle(fontSize: 13, color: context.k.nFaint2)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      TappableIdText(
                        text: e.text,
                        style: const TextStyle(fontSize: 13, height: 1.4),
                        onOpenDetail: onOpenDetail,
                      ),
                      if (e.zh != null && e.zh!.isNotEmpty)
                        Text(e.zh!,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: context.k.nT2)),
                    ],
                  ),
                ),
              ],
            ),
          ],

        ],
      ),
    );
  }
}
