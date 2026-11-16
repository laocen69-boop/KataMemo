library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';
import '../models.dart';
import 'speak_button.dart';
import 'word_sheet.dart';

class AffixSection extends StatelessWidget {
  const AffixSection({
    super.key,
    required this.card,
    this.onOpenDetail,
    this.breakdownSize = 18,
    this.bare = false,
  });

  final WordCard card;

  final OpenWordDetail? onOpenDetail;

  final double breakdownSize;

  final bool bare;

  static bool has(WordCard c) => c.affixBase != null || c.baseWord != null;

  @override
  Widget build(BuildContext context) {
    if (!has(card)) return const SizedBox.shrink();
    final root = card.affixBase ?? card.baseWord!;
    return Container(
      width: double.infinity,
      padding: bare ? EdgeInsets.zero : const EdgeInsets.all(12),
      decoration: bare
          ? null
          : BoxDecoration(
              color: kSpeakGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          if (card.affixes.isNotEmpty) ...[

            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final seg in card.affixBreakdown.split('-'))
                  if (seg.isEmpty)
                    Text('-',
                        style: TextStyle(
                            fontSize: breakdownSize,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            color: context.k.nFaint2))
                  else
                    GestureDetector(
                      onTap: () => showWordSheet(context, seg,
                          onOpenDetail: onOpenDetail),
                      child: Text(seg,
                          style: TextStyle(
                              fontSize: breakdownSize,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              letterSpacing: 1)),
                    ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _rootLine(context, root),
          if (card.affixes.isNotEmpty) const SizedBox(height: 4),
          for (final a in card.affixes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  GestureDetector(
                    onTap: () => showWordSheet(context, a.morph,
                        onOpenDetail: onOpenDetail),
                    child: Text(a.morph,
                        style: TextStyle(
                            fontSize: breakdownSize - 5,
                            height: 1.4,
                            color: kSpeakGreen,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(' ${a.name}：${a.meaning}',
                        style: TextStyle(
                            fontSize: breakdownSize - 5, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rootLine(BuildContext context, String root) {
    final fs = breakdownSize - 4;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('词根：', style: TextStyle(fontSize: fs, color: context.k.g700)),
        Flexible(
          child: GestureDetector(
            onTap: () =>
                showWordSheet(context, root, onOpenDetail: onOpenDetail),
            child: Text(root,
                style: TextStyle(
                  fontSize: fs,
                  color: kSpeakGreen,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: kSpeakGreen.withValues(alpha: 0.4),
                )),
          ),
        ),
      ],
    );
  }
}
