library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../clitic.dart';
import '../fsrs.dart';
import '../models.dart';
import '../passive.dart';
import '../derived_form.dart';
import '../spacing.dart';
import '../version.dart' show kAiChat;
import 'affix_section.dart';
import 'ai_chat_sheet.dart' show showAiChatSheet;
import 'ai_widgets.dart' show AiAppBarButton;
import 'clitic_section.dart';
import 'derivation_section.dart';
import 'grammar_note_section.dart';
import 'homograph_hint.dart';
import 'speak_button.dart';
import 'tappable_text.dart';
import 'word_copy.dart';

typedef OpenWordDetail = void Function(String cardId);

Future<void> showWordSheet(BuildContext context, String query,
    {OpenWordDetail? onOpenDetail, String? kbbiDef, String? kbbiZh}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: WordSheet(
          query: query,
          onOpenDetail: onOpenDetail,
          kbbiDef: kbbiDef,
          kbbiZh: kbbiZh),
    ),
  );
}

class WordSheet extends StatefulWidget {
  final String query;
  final OpenWordDetail? onOpenDetail;
  final String? kbbiDef;
  final String? kbbiZh;

  const WordSheet(
      {super.key,
      required this.query,
      this.onOpenDetail,
      this.kbbiDef,
      this.kbbiZh});

  @override
  State<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<WordSheet> {
  WordCard? _card;
  FsrsState? _srs;

  CliticParse? _clitic;

  PassiveParse? _passive;

  SpacingParse? _spacing;

  DerivedParse? _derived;

  bool _enrolled = false;
  bool _loading = true;
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();

    final found = await app.db.searchWordWithMorph(widget.query);
    final card = found.card;
    final parse = found.clitic;
    final passive = found.passive;
    final spacing = found.spacing;
    final derived = found.derived;
    final srs = card == null ? null : await app.db.getSrs(card.id);
    final planned = card == null ? false : await app.db.isPlanned(card.id);
    if (!mounted) return;
    setState(() {
      _card = card;
      _clitic = parse;
      _passive = passive;
      _spacing = spacing;
      _derived = derived;
      _srs = srs;
      _enrolled = card != null && card.enabled && (planned || srs != null);
      _loading = false;
    });
  }

  bool get _learned => (_srs?.reps ?? 0) > 0;

  Future<void> _remember() async {
    final card = _card;
    if (card == null) return;
    final app = context.read<AppState>();
    final learned = _learned;
    await app.remember([card.id]);
    if (!mounted) return;
    setState(() => _enrolled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(learned
            ? '已加入记忆 · ${card.word} 已在复习计划里，到期会出现在复习队列'
            : '已加入记忆 · ${card.word} 会排进下一组学习队列'),
      ),
    );
  }

  Future<void> _forget() async {
    final card = _card;
    if (card == null) return;
    final app = context.read<AppState>();
    await app.forget([card.id]);
    if (!mounted) return;
    setState(() => _enrolled = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1800),
        content: Text('已移出记忆 · ${card.word} 不再进入学习队列'
            '（学习进度保留，加回来接着学）')));
  }

  String get _statusText {
    final s = _srs;
    if (s == null || s.reps == 0) return '尚未学习';
    final base = switch (s.state) {
      FsrsState.learning => '学习中',
      FsrsState.relearning => '重学中',
      FsrsState.review => '复习中',
      _ => '学习中',
    };
    return '$base · 下次复习 ${Fsrs.nextLabel(s, _lastRatingGuess, elapsedDays: _elapsedDays)}';
  }

  static const _lastRatingGuess = Fsrs.ratingKnow;

  double get _elapsedDays {
    final lr = _srs?.lastReview;
    if (lr == null) return 0.0;
    return DateTime.now().difference(lr).inHours / 24.0;
  }

  List<Widget> _senses(WordCard card) {
    final list = card.senses.take(3).toList();
    const st = TextStyle(fontSize: 14, height: 1.5);
    return [
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${i + 1}. ', style: st),
              Expanded(
                child: TappableIdText(
                    text: list[i].def,
                    style: st,
                    onOpenDetail: widget.onOpenDetail),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _spacingBanner(SpacingParse p) {
    final note = TextStyle(fontSize: 12, color: context.k.g700, height: 1.45);
    const word = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final glue = TextStyle(fontSize: 14, color: context.k.nT2);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: kSpeakGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(p.clicked, style: word),
              Text(' = ', style: glue),
              Text(p.prefix, style: word),
              Text(' + ', style: glue),
              Text(p.rest, style: word),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            p.phraseCard
                ? '这个词常连写；词库里显示的是规范短语「${p.phrase}」。'
                : '这个词常连写；词库里没有「${p.phrase}」这条短语卡，'
                    '显示的是内容词「${p.rest}」。',
            style: note,
          ),
        ],
      ),
    );
  }

  Widget _derivedBanner(DerivedParse p) {
    final note = TextStyle(fontSize: 12, color: context.k.g700, height: 1.45);
    const word = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final glue = TextStyle(fontSize: 14, color: context.k.nT2);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: kSpeakGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(p.clicked, style: word),
              Text(' = ', style: glue),
              Text(p.root, style: word),
              Text(' + -${p.suffix}', style: glue),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '这是「${p.root}」加 -${p.suffix} 的派生形；词库里显示的是词根卡。',
            style: note,
          ),
        ],
      ),
    );
  }

  Widget _cliticBanner(CliticParse p, WordCard card) {
    final note = TextStyle(fontSize: 12, color: context.k.g700, height: 1.45);

    final oddClass = (card.wordClass ?? '').isNotEmpty &&
        !kCliticBaseClasses.contains(card.wordClass);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: kSpeakGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(p.form,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(' = ', style: TextStyle(fontSize: 14, color: context.k.nT2)),
              Text(p.base,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (oddClass)
                Text('（${card.wordClassLabel}）',
                    style: TextStyle(fontSize: 12, color: context.k.nT2)),
              Text(' + ', style: TextStyle(fontSize: 14, color: context.k.nT2)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showWordSheet(context, p.host,
                    onOpenDetail: widget.onOpenDetail),
                child: Text(p.clitic,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.k.hl2,
                        decoration: TextDecoration.underline)),
              ),
            ],
          ),
          Text(
              '这个词形词库里没有单独的卡，上面显示的是原词。'
              '点带下划线的 ${p.clitic} 可以看它的用法。'
              '${oddClass ? '原词是${card.wordClassLabel}，这里 ${p.clitic} 把它当名词用。' : ''}',
              style: note),
        ],
      ),
    );
  }

  Widget _passiveBanner(PassiveParse p, WordCard card) {
    final note = TextStyle(fontSize: 12, color: context.k.g700, height: 1.45);
    const word = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    final glue = TextStyle(fontSize: 14, color: context.k.nT2);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: kSpeakGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(p.form, style: word),
              Text(' = ', style: glue),
              const Text('di-', style: word),
              Text(' + ', style: glue),
              Text(p.stem, style: word),
              Text('（被动形）', style: glue),
            ],
          ),
          Text(
              '主动形式是 ${p.active}，上面显示的就是它。'
              '${p.strippedParticle ? '（你点的 ${p.clicked} 先去掉 ${p.particle}）' : ''}'
              '${p.ownCard.isEmpty ? '词库里没有 ${p.form} 的独立卡片。' : '这个词形自己也有卡片，见下。'}',
              style: note),
          if (p.ownCard.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showWordSheet(context, p.ownCard,
                  onOpenDetail: widget.onOpenDetail),
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('看这个词形自己的卡片 →',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.k.hl2,
                        decoration: TextDecoration.underline)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.72;
    if (_loading) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final card = _card;
    if (card == null) {
      final def = widget.kbbiDef;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(widget.query,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            if (def != null && def.isNotEmpty) ...[

              Text('KBBI 释义',
                  style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
              const SizedBox(height: 6),
              TappableIdText(
                  text: def,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                  onOpenDetail: widget.onOpenDetail),

              if ((widget.kbbiZh ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(widget.kbbiZh!,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
              ],
              const SizedBox(height: 10),
              Text(
                  '（这是派生词形，词库里没有它的独立卡片，'
                  '所以不计入学习进度）',
                  style: TextStyle(fontSize: 11.5, color: context.k.nFaint2)),
            ] else ...[
              Text('词库未收录这个词',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: context.k.nT2)),
              const SizedBox(height: 4),
              Text('（例句里的专有名词、缩写或非标准拼写可能查不到）',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: context.k.nFaint2)),
            ],
            const SizedBox(height: 16),
            Center(
                child: SpeakButton(
                    word: widget.query, filled: true, iconSize: 22)),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),

      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_spacing != null) _spacingBanner(_spacing!),
          if (_derived != null) _derivedBanner(_derived!),
          if (_clitic != null) _cliticBanner(_clitic!, card),
          if (_passive != null) _passiveBanner(_passive!, card),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(card.word,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w700)),
                    ),
                    if (card.phonetic != null)
                      Text(card.phonetic!,
                          style: TextStyle(fontSize: 13, color: context.k.nT2)),

                    if (card.affixType != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('${card.affixType} · ${card.word}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB26A00))),
                      ),
                    if (card.fullName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('简写专名 · ${card.fullName}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6A7AD8))),
                      ),
                  ],
                ),
              ),

              if (kAiChat)
                AiAppBarButton(
                  key: const ValueKey('sheet.askAi'),
                  tooltip: '问 AI 这个词',
                  onTap: () => showAiChatSheet(context, card),
                ),

              Tooltip(
                message: _copied ? '已复制' : '复制单词和释义',
                child: IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_outlined,
                    color: _copied ? kSpeakGreen : context.k.nT2,
                  ),
                  onPressed: () async {

                    final text = wordCopyText(card);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    _copyTimer?.cancel();
                    _copyTimer = Timer(const Duration(milliseconds: 1200), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                ),
              ),
              SpeakButton(card: card, filled: true, iconSize: 22),
              const SizedBox(width: 2),

              if (widget.onOpenDetail != null)
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.open_in_full),
                  tooltip: '查看完整卡片',
                  color: context.k.nT2,
                  onPressed: () {
                    final open = widget.onOpenDetail!;
                    Navigator.pop(context);
                    open(card.id);
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (card.zhClean != null)
            Text(card.zhClean!,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [

              if (card.wordClassLabelsCombined.isNotEmpty)
                _Chip(card.wordClassLabelsCombined),
              if (card.originLabel != null) _Chip('借自${card.originLabel}'),

              if (card.properKindLabel != null) _Chip(card.properKindLabel!),

              if (card.isFreqBand && const {'t1', 't2'}.contains(card.tier))
                _Chip(card.tierLabel),
              if (card.rank != null) _Chip('语料排名 #${card.rank}'),
            ],
          ),

          HomographHint(
              key: ValueKey('hg-${card.id}'),
              card: card,
              onOpenDetail: widget.onOpenDetail),

          const SizedBox(height: 16),
          _MemoryBar(
            status: card.enabled
                ? _statusText
                : 'KBBI 词条 · 供查阅（不进学习队列）',
            enrolled: _enrolled,
            joinable: card.enabled,
            onRemember: _remember,
            onForget: _forget,
          ),

          if (card.clitics.isNotEmpty) ...[
            const SizedBox(height: 16),
            CliticSection(
                clitics: card.clitics, onOpenDetail: widget.onOpenDetail),
          ],

          if (card.senses.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _Label('释义（KBBI）'),
            const SizedBox(height: 6),
            ..._senses(card),
          ],

          if (card.examples.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _Label('例句'),
            const SizedBox(height: 6),
            for (final e in card.examples.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    TappableIdText(
                        text: e.text,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                        onOpenDetail: widget.onOpenDetail),
                    if (e.zh != null && e.zh!.isNotEmpty)
                      Text(e.zh!,
                          style: TextStyle(
                              fontSize: 12, color: context.k.nT2, height: 1.4)),
                  ],
                ),
              ),
          ],

          if (card.mnemonicShown != null && card.mnemonicShown!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Label(card.showsDefaultMnemonic
                ? '助记（${card.mnemonicDefaultKind}，可改）'
                : '助记'),
            const SizedBox(height: 6),
            Text(card.mnemonicShown!,
                style: const TextStyle(fontSize: 14, height: 1.5)),
            if (widget.onOpenDetail != null)
              Text('在完整卡片里可以改或加图',
                  style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
          ],

          if (GrammarNoteSection.has(context, card)) ...[
            const SizedBox(height: 12),
            _Label(card.grammarFunctionLabel == null
                ? GrammarNoteSection.label(card)
                : '${GrammarNoteSection.label(card)} · ${card.grammarFunctionLabel}'),
            const SizedBox(height: 6),
            GrammarNoteSection(
              notes: card.grammarNotes,
              limit: 2,
              wordId: card.id,
              onOpenDetail: widget.onOpenDetail,
            ),
          ],

          if (AffixSection.has(card)) ...[
            const SizedBox(height: 8),
            const _Label('词根词缀'),
            const SizedBox(height: 4),
            AffixSection(
              card: card,
              onOpenDetail: widget.onOpenDetail,
              breakdownSize: 16,
            ),
          ],

          if (card.derivations.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _Label('派生词形（点词可继续查）'),
            const SizedBox(height: 2),
            DerivationList(
              derivations: card.derivations,
              limit: 8,
              onTapDerivation: (d) => showWordSheet(context, d.form,
                  onOpenDetail: widget.onOpenDetail,
                  kbbiDef: d.def,
                  kbbiZh: d.gloss),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryBar extends StatelessWidget {
  final String status;
  final bool enrolled;

  final bool joinable;

  final VoidCallback onRemember;
  final VoidCallback onForget;

  const _MemoryBar({
    required this.status,
    required this.enrolled,
    required this.joinable,
    required this.onRemember,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: kSpeakGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes, size: 16, color: kSpeakGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(status,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          if (!joinable) ...[
            Icon(Icons.menu_book_outlined, size: 16, color: context.k.nT2),
            const SizedBox(width: 4),
            Text('仅查阅',
                style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
          ] else if (enrolled) ...[
            TextButton(
              onPressed: onForget,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: context.k.nT2,
              ),

              child: const Text('移出记忆', style: TextStyle(fontSize: 12.5)),
            ),
            Icon(Icons.check_circle, size: 18, color: kSpeakGreen),
            const SizedBox(width: 4),
            Text('已加入记忆',
                style: TextStyle(fontSize: 12.5, color: kSpeakGreen)),
          ] else
            FilledButton.icon(
              onPressed: onRemember,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('加入记忆', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: kSpeakGreen,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: 12.5, color: context.k.nT2));
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.k.nFaint2.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5)),
      );
}
