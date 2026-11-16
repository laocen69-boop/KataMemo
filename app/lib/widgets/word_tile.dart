library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';
import '../models.dart';
import 'memory_ring.dart';
import 'sense_highlight.dart';
import 'speak_button.dart';

class WordTile extends StatelessWidget {
  final WordCard card;
  final bool selectMode;
  final bool selected;

  final bool selectable;

  final bool member;

  final String? hint;

  final MemoryStrength? strength;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  final bool enrolled;

  final VoidCallback? onTogglePlan;

  final VoidCallback? onEdit;

  final VoidCallback? onSelectTap;

  final bool chevron;

  final bool markNotEnrolled;

  final bool searchLayout;

  final BookNode? book;

  final String? highlightQuery;

  const WordTile({
    super.key,
    required this.card,
    required this.onTap,
    required this.onLongPress,
    this.selectMode = false,
    this.selected = false,
    this.selectable = true,
    this.member = false,
    this.hint,
    this.strength,
    this.enrolled = false,
    this.onTogglePlan,
    this.onEdit,
    this.onSelectTap,
    this.chevron = false,
    this.markNotEnrolled = true,
    this.searchLayout = false,
    this.book,
    this.highlightQuery,
  });

  Widget _searchStatusChip(BuildContext context) {
    final pending = selected && !enrolled;
    final on = enrolled || pending;
    final label = enrolled ? '已在记忆' : '待加入';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: on
            ? context.k.brand.withValues(alpha: 0.12)
            : context.k.nFaint2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: on ? context.k.brand : context.k.nT2)),
    );
  }

  Widget _searchTitle(BuildContext context, MemoryStrength? st) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(card.word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: context.k.text)),
              ),
              if (enrolled || selected) ...[
                const SizedBox(width: 7),
                _searchStatusChip(context),
              ],
              if (enrolled && st != null) ...[
                const SizedBox(width: 5),
                Text(st.shortLabel,
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: memoryBandColor(context, st.band))),
              ],
            ],
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Text(hint!,
              maxLines: 1,
              style: TextStyle(fontSize: 10.5, color: context.k.t3)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !enrolled && markNotEnrolled;

    final st = enrolled ? strength : null;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,

      selectedColor: context.k.text,
      selectedTileColor: kSpeakGreen.withValues(alpha: 0.07),
      contentPadding: EdgeInsets.only(left: selectMode ? 6 : 16, right: 6),
      minVerticalPadding: searchLayout ? 8 : 4,
      leading: selectMode
          ? (searchLayout && enrolled

              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MemoryRing(
                      strength: st,
                      size: 38,
                      child: Text(
                        card.word.isEmpty ? '?' : card.word[0].toUpperCase(),
                        style: TextStyle(
                            fontSize: 13,
                            color: context.k.brand,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: context.k.brand,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: context.k.surface, width: 1.5),
                        ),
                        child: Icon(Icons.check,
                            size: 9, color: context.k.onbrand),
                      ),
                    ),
                  ],
                )
              : RingCheck(
                  selected: selected,

                  member: member,
                  enabled: selectable,
                  onTap: onSelectTap ?? onTap,
                ))
          : MemoryRing(

              strength: st,
              size: 38,
              child: Text(
                card.word.isEmpty ? '?' : card.word[0].toUpperCase(),
                style: TextStyle(
                    fontSize: 13,
                    color: disabled ? context.k.nFaint2 : context.k.brand,
                    fontWeight: FontWeight.w600),
              ),
            ),
      title: searchLayout
          ? _searchTitle(context, st)
          : Row(
              children: [
                Flexible(

                  child: Text(card.word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: disabled ? context.k.nFaint2 : null)),
                ),

                ...[
                  if (disabled) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.k.nFaint2.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),

                      child: Text('未加入记忆',
                          style: TextStyle(
                              fontSize: 10, color: context.k.nFaint2)),
                    ),
                  ],

                  if (selectMode && member && !selected) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: kSpeakGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('已在记忆中',
                          style: TextStyle(fontSize: 10, color: kSpeakGreen)),
                    ),
                  ],

                  if (hint != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E8EE0).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(hint!,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF6A6AC4))),
                    ),
                  ],

                  if (st != null && !selectMode && hint == null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(st.shortLabel,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: memoryBandColor(context, st.band))),
                    ),
                  ],
                ],
              ],
            ),

      subtitle: SearchMeaningLine(
          wordClass: card.wordClassLabelsCombined,
          zh: card.zhClean,
          card: card,
          book: book,
          highlightQuery: highlightQuery,
          dim: disabled),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpeakButton(card: card, iconSize: 22),
          if (onEdit != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: '改这条卡（词形/中文/例句/助记/发音）',
                child: InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.edit_outlined,
                        size: 20, color: context.k.nSlate),
                  ),
                ),
              ),
            ),
          if (onTogglePlan != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: enrolled ? '移出记忆' : '加入记忆',
                child: InkWell(
                  onTap: onTogglePlan,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: enrolled ? context.k.brand : context.k.g400,
                        width: 1.4,
                      ),
                      color: enrolled
                          ? kSpeakGreen.withValues(alpha: 0.10)
                          : Colors.transparent,
                    ),

                    child: Icon(
                      enrolled ? Icons.check : Icons.add,
                      size: 19,
                      color: enrolled ? context.k.brand : context.k.nT2,
                    ),
                  ),
                ),
              ),
            ),

          if (chevron)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.chevron_right, size: 20, color: context.k.g400),
            ),
        ],
      ),
    );
  }
}

class RingCheck extends StatelessWidget {
  const RingCheck({
    super.key,
    required this.selected,
    this.enabled = true,
    this.member = false,
    this.onTap,
    this.size = 26,
  });

  final bool selected;

  final bool enabled;

  final bool member;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final checked = selected || member || !enabled;
    final bg = selected
        ? kSpeakGreen
        : (member || !enabled)
            ? context.k.nFaint2
            : Colors.transparent;
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: size,
      child: SizedBox(
        width: size + 12,
        height: size + 12,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: checked
                  ? null
                  : Border.all(color: context.k.g400, width: 1.6),
            ),
            child: checked
                ? Icon(Icons.check, size: 17, color: context.k.onbrand)
                : null,
          ),
        ),
      ),
    );
  }
}

class SearchMeaningLine extends StatelessWidget {
  const SearchMeaningLine({
    super.key,
    required this.wordClass,
    this.zh,
    this.dim = false,
    this.card,
    this.book,
    this.highlightQuery,
  });

  final String wordClass;
  final String? zh;

  final bool dim;

  final WordCard? card;

  final BookNode? book;

  final String? highlightQuery;

  @override
  Widget build(BuildContext context) {
    final cls = wordClass.trim();
    final hl = resolveSenseHighlight(
      card: card,
      zh: zh,
      book: book,
      query: highlightQuery,
    );
    final baseStyle = TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: dim ? context.k.nFaint2 : context.k.text,
    );
    final accentColor =
        dim ? context.k.deep.withValues(alpha: 0.72) : context.k.deep;
    final tintColor =
        dim ? context.k.tint.withValues(alpha: 0.5) : context.k.tint;
    final restColor = dim ? context.k.nFaint2 : context.k.nT2;

    return Row(
      children: [
        if (cls.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: context.k.alt,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(cls,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: context.k.t2)),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: hl.hasHighlight
              ? Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: hl.highlightedPrefix,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                          backgroundColor: tintColor,
                        ),
                      ),
                      if (hl.remainderText.isNotEmpty)
                        TextSpan(
                          text: hl.remainderText,
                          style: TextStyle(
                            color: restColor,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle,
                )
              : Text(hl.fullText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle),
        ),
      ],
    );
  }
}
