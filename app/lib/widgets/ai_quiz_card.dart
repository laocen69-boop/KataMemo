/// AI 回复内嵌的可点击互动练习卡（柔和边框 + 即时判对错 + 一键加词）。
library;

import 'package:flutter/material.dart';

import '../ai_quiz.dart';
import '../theme/k_colors.dart';

class AiQuizCard extends StatefulWidget {
  final List<AiQuizItem> items;
  final void Function(String wordId)? onAddWord;

  const AiQuizCard({super.key, required this.items, this.onAddWord});

  @override
  State<AiQuizCard> createState() => _AiQuizCardState();
}

class _AiQuizCardState extends State<AiQuizCard> {
  final Map<int, int> _picked = {};
  final Set<String> _added = {};

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildItem(context, k, i, widget.items[i]),
        ],
      ],
    );
  }

  Widget _buildItem(BuildContext context, KColors k, int idx, AiQuizItem item) {
    final picked = _picked[idx];
    final answered = picked != null;
    final isCorrect = picked == item.answerIndex;
    const labels = ['A', 'B', 'C', 'D', 'E', 'F'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.items.length > 1 ? '${idx + 1}. ${item.question}' : item.question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: k.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (var j = 0; j < item.options.length; j++) ...[
            if (j > 0) const SizedBox(height: 6),
            _optionTile(
              k: k,
              label: j < labels.length ? labels[j] : '${j + 1}',
              text: item.options[j],
              answered: answered,
              isPicked: picked == j,
              isCorrectOption: j == item.answerIndex,
              onTap: answered
                  ? null
                  : () => setState(() => _picked[idx] = j),
            ),
          ],
          if (answered) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isCorrect ? k.brand.withValues(alpha: 0.08) : k.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isCorrect ? '回答正确' : '再想想 · 正确答案是 ${labels[item.answerIndex]}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isCorrect ? k.brand : k.danger,
                    ),
                  ),
                  if (item.explanation.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.explanation,
                      style: TextStyle(fontSize: 12.5, color: k.t2, height: 1.45),
                    ),
                  ],
                  if (item.wordId != null && widget.onAddWord != null) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _added.contains(item.wordId)
                          ? null
                          : () {
                              setState(() => _added.add(item.wordId!));
                              widget.onAddWord!(item.wordId!);
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _added.contains(item.wordId) ? k.bg : k.tint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _added.contains(item.wordId) ? '已加入记忆' : '+ 把 ${item.wordId} 加入记忆',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _added.contains(item.wordId) ? k.t3 : k.deep,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionTile({
    required KColors k,
    required String label,
    required String text,
    required bool answered,
    required bool isPicked,
    required bool isCorrectOption,
    required VoidCallback? onTap,
  }) {
    Color bg = k.bg;
    Color border = k.border;
    Color fg = k.text;

    if (answered) {
      if (isCorrectOption) {
        bg = k.brand.withValues(alpha: 0.12);
        border = k.brand.withValues(alpha: 0.45);
        fg = k.deep;
      } else if (isPicked) {
        bg = k.danger.withValues(alpha: 0.10);
        border = k.danger.withValues(alpha: 0.45);
        fg = k.danger;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: answered && isCorrectOption ? k.brand : k.surface,
                shape: BoxShape.circle,
                border: Border.all(color: answered && isCorrectOption ? k.brand : k.border),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: answered && isCorrectOption ? Colors.white : k.t2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13.5, color: fg, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
