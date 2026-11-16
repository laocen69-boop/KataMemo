library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';
import '../models.dart';
import 'speak_button.dart' show kSpeakGreen;
import 'tappable_text.dart';
import 'word_sheet.dart';

class CliticSection extends StatelessWidget {
  final List<Clitic> clitics;

  final OpenWordDetail? onOpenDetail;

  final bool bare;

  final bool showTitle;

  const CliticSection(
      {super.key,
      required this.clitics,
      this.onOpenDetail,
      this.bare = false,
      this.showTitle = true});

  @override
  Widget build(BuildContext context) {
    if (clitics.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text('附着词用法',
              style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
          const SizedBox(height: 6),
        ],
        for (final c in clitics) _buildOne(context, c),
      ],
    );
  }

  Widget _buildOne(BuildContext context, Clitic c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: bare
          ? const EdgeInsets.only(bottom: 2)
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(c.form,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E7D62))),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.zh,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (c.rule.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(c.rule, style: TextStyle(fontSize: 12, color: context.k.nT2)),
          ],
          if (c.examples.isNotEmpty) ...[
            const SizedBox(height: 7),
            for (final e in c.examples)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('· ',
                        style: TextStyle(
                            fontSize: 13.5, color: context.k.nFaint2)),

                    Expanded(
                      child: TappableIdText(
                        text: e.text,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w500),
                        onOpenDetail: onOpenDetail,
                      ),
                    ),
                    if (e.zh != null && e.zh!.isNotEmpty) ...[
                      Text(' = ',
                          style:
                              TextStyle(fontSize: 13, color: context.k.g400)),
                      Expanded(
                        child: Text(e.zh!,
                            style:
                                TextStyle(fontSize: 13, color: context.k.g700)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
          if (c.note != null && c.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(c.note!,
                style: TextStyle(
                    fontSize: 12, height: 1.5, color: context.k.g700)),
          ],
        ],
      ),
    );
  }
}
