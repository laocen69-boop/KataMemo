library;

import 'package:flutter/material.dart';

import '../audio.dart';
import '../theme/k_colors.dart';
import '../models.dart';

Color get kSpeakGreen => KColors.current.brand;

class SpeakButton extends StatelessWidget {
  final WordCard? card;
  final String? word;
  final double iconSize;
  final bool filled;

  final Color? color;

  const SpeakButton({
    super.key,
    this.card,
    this.word,
    this.iconSize = 20,
    this.filled = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? kSpeakGreen;
    final icon = Icon(Icons.volume_up_rounded, size: iconSize, color: tint);

    return Tooltip(
      message: '朗读',
      child: InkResponse(
        onTap: () async {
          final text = card?.word ?? word ?? '';
          if (text.isEmpty) return;

          final r = await AudioService.instance.playCard(
            audio: card?.audio,
            parts: card?.audioParts ?? const [],
            word: text,
          );

          if (r == PlayOutcome.none && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('这个词没有配音（内置音频没有，你也没导入音频）'),
              duration: Duration(seconds: 2),
            ));
          }
        },
        radius: iconSize * 1.2,
        child: filled
            ? Container(
                padding: EdgeInsets.all(iconSize * 0.42),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: icon,
              )
            : Padding(padding: const EdgeInsets.all(6), child: icon),
      ),
    );
  }
}
