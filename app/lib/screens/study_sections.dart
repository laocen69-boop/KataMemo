part of 'study_screen.dart';

class _PosChipRow extends StatelessWidget {
  const _PosChipRow({
    required this.labels,
    required this.color,
    required this.bg,
  });

  final List<String> labels;
  final Color color;
  final Color bg;

  static const double _fontSize = 11;
  static const double _height = 20;
  static const double _padH = 7;
  static const double _gap = 4;

  Widget _chip(String text) => Container(
        height: _height,
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Align(
          widthFactor: 1,
          child: Text(text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: _fontSize,
                  height: 1.0,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {

      final style = DefaultTextStyle.of(context).style.merge(const TextStyle(
          fontSize: _fontSize, height: 1.0, fontWeight: FontWeight.w600));
      final scaler = MediaQuery.textScalerOf(context);
      double widthOf(String t) {
        final tp = TextPainter(
          text: TextSpan(text: t, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        return tp.width + 2 * _padH;
      }

      final ws = [for (final l in labels) widthOf(l)];
      double sumFirst(int k) {
        var s = 0.0;
        for (var i = 0; i < k; i++) {
          s += ws[i] + (i > 0 ? _gap : 0);
        }
        return s;
      }

      var shown = labels.length;
      if (sumFirst(shown) > c.maxWidth) {

        shown = 1;
        for (var k = labels.length - 1; k >= 1; k--) {
          final more = widthOf('+${labels.length - k}');
          if (sumFirst(k) + _gap + more <= c.maxWidth) {
            shown = k;
            break;
          }
        }
      }
      final hidden = labels.length - shown;
      return ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < shown; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Flexible(child: _chip(labels[i])),
            ],
            if (hidden > 0) ...[
              const SizedBox(width: _gap),
              Tooltip(
                key: const Key('study.posMore'),
                message: labels.join(' · '),
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 3),
                child: _chip('+$hidden'),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _FrontHint extends StatelessWidget {
  const _FrontHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(

        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Text('点一下，看答案',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: context.k.nFaint2)),
          ],
        ),
      ),
    );
  }
}

class _SpellingFront extends StatelessWidget {
  const _SpellingFront({
    required this.card,
    required this.questions,
    this.revealed = false,
  });

  final WordCard card;
  final List<ClozeQuestion> questions;

  final bool revealed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('例句', hint: revealed ? '已揭晓' : '在下方输入这个空'),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final q in questions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(

                          child: _ClozeText(
                              key: ValueKey('cloze-${q.index}'),
                              question: q,
                              showAnswer: revealed),
                        ),
                        const SizedBox(width: 6),

                        SpeakButton(card: card, iconSize: 21),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SensesBody extends StatelessWidget {
  const _SensesBody({
    required this.card,
    required this.expanded,
    required this.onToggle,
  });

  final WordCard card;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final all = card.senses;
    final limited = all.length > 4;
    final shown = (limited && !expanded) ? all.take(4).toList() : all;
    final hidden = all.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i + 1}. ',
                  style: const TextStyle(fontSize: 14, height: 1.5)),

              SizedBox(
                width: 44,
                child: shown[i].pos == null
                    ? null
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('${shown[i].pos}.',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: context.k.t3)),
                      ),
              ),
              Expanded(
                child: TappableIdText(
                  text: shown[i].def,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  onOpenDetail: detailOpener(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (limited)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(expanded ? '收起' : '展开 +$hidden',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.k.deep)),
            ),
          ),
      ],
    );
  }
}

class _NonStdBody extends StatelessWidget {
  const _NonStdBody({required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in card.nonStandardForms.take(20))
              GestureDetector(
                onTap: () => showWordSheet(context, s,
                    onOpenDetail: detailOpener(context)),
                child: _Pill(text: s),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('这些写法不规范，认识即可，正式场合请用上面的写法',
            style: TextStyle(fontSize: 10.5, color: context.k.nFaint2)),
      ],
    );
  }
}

class _MnemonicBody extends StatelessWidget {
  const _MnemonicBody({required this.card, required this.onAdd});

  final WordCard card;

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (card.mnemonicShown != null && card.mnemonicShown!.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: context.k.star),
              const SizedBox(width: 6),
              Expanded(
                child: Text(card.mnemonicShown!,
                    style: const TextStyle(fontSize: 13, height: 1.5)),
              ),
            ],
          ),
        if (card.mnemonicImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          MnemonicImagesRow(relPaths: card.mnemonicImages),
        ],
        if (card.mnemonicShown == null && card.mnemonicImages.isEmpty)

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: context.k.mntint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.k.mnDash, width: 1),
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, size: 15, color: context.k.hl),
                const SizedBox(width: 5),
                Text('添加记忆线索',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.k.hl)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _ExampleItem extends StatelessWidget {
  const _ExampleItem({
    required this.card,
    required this.example,
    this.inset = false,
  });

  final WordCard card;
  final WordExample example;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final e = example;
    return Padding(
      padding: inset
          ? const EdgeInsets.only(left: 11, right: 11, bottom: 13)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TappableIdText(
            text: e.text,
            style:
                TextStyle(fontSize: 15.5, height: 1.5, color: context.k.ink3),

            highlight: {card.id, card.word},

            highlightColor: context.k.hl,
            onOpenDetail: detailOpener(context),
          ),
          if (e.zh != null && e.zh!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(e.zh!,
                  style: TextStyle(
                      fontSize: 15, color: context.k.ink3, height: 1.45)),
            ),

          if (!inset) const SizedBox(height: 13),
        ],
      ),
    );
  }
}

class _GabunganBody extends StatelessWidget {
  const _GabunganBody({
    required this.card,
    required this.showAll,
    required this.onToggle,
  });

  final WordCard card;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final items = showAll
        ? card.gabunganKata
        : card.gabunganKata.take(_StudyScreenState._gkLimit).toList();
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in items)
              GestureDetector(
                key: ValueKey('study.gk.$g'),
                behavior: HitTestBehavior.opaque,
                onTap: () => showWordSheet(context, g,
                    onOpenDetail: detailOpener(context)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: k.alt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: k.line, width: 0.5),
                  ),
                  child: Text(g,
                      style:
                          TextStyle(fontSize: 12, height: 1.1, color: k.text)),
                ),
              ),
          ],
        ),
        if (card.gabunganKata.length > _StudyScreenState._gkLimit) ...[
          const SizedBox(height: 8),
          GestureDetector(
            key: const ValueKey('study.gkToggle'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: k.tint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(showAll ? '收起' : '展开全部 ${card.gabunganKata.length} 个搭配',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: k.deep)),
                  const SizedBox(width: 4),
                  Icon(showAll ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: k.deep),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
