library;

import 'package:flutter/material.dart';

import '../db.dart';
import 'speak_button.dart' show kSpeakGreen;
import 'word_sheet.dart';

const _punct = r"""\s.,!?;:'"()\[\]{}<>«»“”‘’„–—…、。「」『』""";
final _edgePunct = RegExp('^[$_punct]+|[$_punct]+\$');

final _idShape = RegExp(r'^[A-Za-z][A-Za-z0-9éêÉÊ\-]*$');

bool isTappableId(String raw) {
  final s = raw.trim().replaceAll(_edgePunct, '');
  if (s.isEmpty) return false;
  return _idShape.hasMatch(s);
}

class TappableIdText extends StatelessWidget {
  final String text;
  final TextStyle style;

  final bool enabled;

  final OpenWordDetail? onOpenDetail;

  final Set<String> highlight;

  final Color? highlightColor;

  const TappableIdText({
    super.key,
    required this.text,
    required this.style,
    this.enabled = true,
    this.onOpenDetail,
    this.highlight = const {},
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {

    final segs = AppDb.segments(text);
    return Wrap(
      spacing: 0,
      runSpacing: 1,
      children: [
        for (final s in segs)
          if (s.isWord)
            _buildWord(context, s.text)
          else
            Text(s.text, style: style),
      ],
    );
  }

  Widget _buildWord(BuildContext context, String raw) {

    final isTarget = highlight.isNotEmpty &&
        highlight.any((h) => h.isNotEmpty && AppDb.fold(h) == AppDb.fold(raw));
    final st = isTarget
        ? style.copyWith(
            color: highlightColor ?? kSpeakGreen, fontWeight: FontWeight.w700)
        : style;

    if (!enabled || !isTappableId(raw)) return Text(raw, style: st);
    return GestureDetector(
      onTap: () => showWordSheet(context, raw, onOpenDetail: onOpenDetail),
      child: Text(raw, style: st),
    );
  }
}
