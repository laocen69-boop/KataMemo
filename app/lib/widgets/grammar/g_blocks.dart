library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../grammar/grammar_models.dart';
import '../../screens/word_detail_screen.dart';
import '../../theme/k_colors.dart';
import '../tappable_text.dart';
import '../word_sheet.dart';
import 'g_table.dart';
import 'tree_block.dart';

class GBlockView extends StatelessWidget {
  const GBlockView({super.key, required this.block});

  final GBlock block;

  @override
  Widget build(BuildContext context) {
    switch (block) {
      case GLeadBlock(:final text):
        return _Lead(text: text);
      case GHeadingBlock(:final text):
        return GHeading(text: text);
      case GTextBlock(:final text):
        return GRichText(text,
            style: TextStyle(fontSize: 14, height: 1.65, color: context.k.text));
      case GStepsBlock(:final title, :final items):
        return _Steps(title: title, items: items);
      case GPitBlock(:final items):
        return _Pit(items: items);
      case GTableBlock(:final title):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) _SubTitle(title),
            GTable(block: block as GTableBlock),
          ],
        );
      case GExBlock(:final items):
        return _ExList(items: items);
      case GVsBlock():
        return _Vs(block: block as GVsBlock);
      case GWordsBlock(:final title, :final list):
        return _Words(title: title, list: list);
      case GTreeBlock():
        return TreeBlockView(block: block as GTreeBlock);
      case GUnknownBlock(:final t):
        if (kDebugMode) debugPrint('[grammar] 未知块类型，已跳过：$t');
        return const SizedBox.shrink();
    }
  }
}

class GRichText extends StatelessWidget {
  const GRichText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('**');
    if (parts.length == 1) return Text(text, style: style);
    final bold = style.copyWith(fontWeight: FontWeight.w700, color: context.k.deep);
    return Text.rich(TextSpan(children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(text: parts[i], style: i.isOdd ? bold : style),
    ]));
  }
}

class GHeading extends StatelessWidget {
  const GHeading({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 16,
              margin: const EdgeInsets.only(top: 2, right: 8),
              decoration: BoxDecoration(
                  color: context.k.brand, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: context.k.text)),
            ),
          ],
        ),
      );
}

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GRichText(text,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: context.k.sec)),
      );
}

class _Lead extends StatelessWidget {
  const _Lead({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: context.k.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('结论',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: context.k.brand)),
            const SizedBox(height: 3),
            GRichText(text,
                style: TextStyle(fontSize: 14, height: 1.6, color: context.k.deep)),
          ],
        ),
      );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.title, required this.items});
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.k.nEdge, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) _SubTitle(title),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 19,
                      height: 19,
                      margin: const EdgeInsets.only(top: 1, right: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: context.k.tint, shape: BoxShape.circle),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.k.deep)),
                    ),
                    Expanded(
                      child: GRichText(items[i],
                          style: TextStyle(
                              fontSize: 13.5, height: 1.55, color: context.k.text)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _Pit extends StatelessWidget {
  const _Pit({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: context.k.gWarnBg,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: context.k.gWarn, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: context.k.gWarn),
                const SizedBox(width: 5),
                Text('易错',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: context.k.gWarn)),
              ],
            ),
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: GRichText('· $s',
                    style: TextStyle(fontSize: 13, height: 1.55, color: context.k.text)),
              ),
          ],
        ),
      );
}

class GExTile extends StatelessWidget {
  const GExTile({super.key, required this.ex, this.dense = false});

  final GEx ex;

  final bool dense;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TappableIdText(
            text: ex.plain,
            highlight: ex.highlights,
            highlightColor: context.k.deep,
            onOpenDetail: detailOpener(context),
            style: TextStyle(
                fontSize: dense ? 13 : 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: context.k.text),
          ),
          if (ex.z.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(ex.z,
                  style: TextStyle(
                      fontSize: dense ? 12 : 12.5, height: 1.45, color: context.k.t2)),
            ),
        ],
      );
}

class _ExList extends StatelessWidget {
  const _ExList({required this.items});
  final List<GEx> items;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.k.nEdge, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Divider(height: 0.5, thickness: 0.5, color: context.k.nEdge),
                ),
              GExTile(ex: items[i]),
            ],
          ],
        ),
      );
}

class _Vs extends StatelessWidget {
  const _Vs({required this.block});
  final GVsBlock block;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 520;
        final a = _side(context, block.a, context.k.tint, context.k.deep);
        final b = _side(context, block.b, context.k.gSlot2Tint, context.k.gSlot2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 8),
                    Expanded(child: b),
                  ],
                ),
              )
            else ...[
              a,
              const SizedBox(height: 8),
              b,
            ],
            if (block.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: GRichText(block.note,
                    style: TextStyle(fontSize: 12.5, height: 1.55, color: context.k.t2)),
              ),
          ],
        );
      });

  Widget _side(BuildContext context, GVsSide s, Color bg, Color accent) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: accent)),
            if (s.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: GRichText(s.text,
                    style: TextStyle(fontSize: 13, height: 1.55, color: context.k.text)),
              ),
            for (final e in s.ex)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GExTile(ex: e, dense: true),
              ),
          ],
        ),
      );
}

class _Words extends StatelessWidget {
  const _Words({required this.title, required this.list});
  final String title;
  final List<String> list;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) _SubTitle(title),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final w in list)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () =>
                      showWordSheet(context, w, onOpenDetail: detailOpener(context)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.k.alt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(w,
                        style: TextStyle(fontSize: 13, color: context.k.deep)),
                  ),
                ),
            ],
          ),
        ],
      );
}
