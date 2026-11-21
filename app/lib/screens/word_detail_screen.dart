library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport, RenderBox;
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../models.dart';
import '../version.dart' show kAiChat;
import '../widgets/affix_section.dart';
import '../ai_chat.dart' show aiWordContext;
import '../widgets/ai_chat_sheet.dart';
import '../widgets/ai_widgets.dart'
    show AiAppBarButton, AiAskChip, AiContextHub;
import '../widgets/clitic_section.dart';
import '../widgets/copy_text.dart';
import '../widgets/derivation_section.dart';
import '../widgets/grammar_note_section.dart';
import '../widgets/homograph_hint.dart';
import '../widgets/mnemonic_section.dart';
import '../widgets/mnemonic_templates.dart';
import '../widgets/speak_button.dart';
import '../widgets/tappable_text.dart';
import '../widgets/word_copy.dart';
import '../widgets/word_sheet.dart';
import 'my_words_screen.dart' show openUserWordForm;

Future<void> openWordDetail(BuildContext context, String cardId) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: cardId)),
  );
}

OpenWordDetail detailOpener(BuildContext context) =>
    (id) => openWordDetail(context, id);

class WordDetailScreen extends StatefulWidget {
  final String cardId;
  const WordDetailScreen({super.key, required this.cardId});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  WordCard? _card;
  bool _loading = true;

  bool _showAllDerivations = false;

  bool _showAllGabungan = false;

  bool _enrolled = false;
  bool _learned = false;
  bool _enrolling = false;

  static const double _indexHeight = 46;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};
  List<GlobalKey> _indexedKeys = const [];

  final ValueNotifier<int> _activeSection = ValueNotifier<int>(0);
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    AiContextHub.pop(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _activeSection.dispose();
    super.dispose();
  }

  GlobalKey _sectionKey(String id) =>
      _sectionKeys.putIfAbsent(id, () => GlobalKey());

  Future<void> _load() async {
    final app = context.read<AppState>();
    final card = await app.db.getWord(widget.cardId);
    final srs = card == null ? null : await app.db.getSrs(card.id);
    final planned = card == null ? false : await app.db.isPlanned(card.id);
    if (!mounted) return;
    setState(() {
      _card = card;
      _loading = false;
      _enrolled = card != null && card.enabled && (planned || srs != null);
      _learned = (srs?.reps ?? 0) > 0;
    });

    if (kAiChat && card != null) AiContextHub.push(this, () => aiWordContext(card));
  }

  Future<void> _remember(WordCard card) async {
    if (_enrolling) return;
    setState(() => _enrolling = true);
    final learned = _learned;
    try {
      await context.read<AppState>().remember([card.id]);
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
    if (!mounted) return;
    setState(() => _enrolled = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 1600),
      content: Text(learned
          ? '已加入记忆 · ${card.word} 会继续排在复习队列'
          : '已加入记忆 · ${card.word} 会排进下一组学习队列'),
    ));
  }

  void _onScroll() {

    if (_jumping) return;
    if (!_scroll.hasClients || _indexedKeys.isEmpty) return;

    final top = _scroll.position.pixels + _indexHeight + 8;
    var active = 0;
    for (var i = 0; i < _indexedKeys.length; i++) {
      final ctx = _indexedKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final off =
          RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      if (off <= top) {
        active = i;
      } else {
        break;
      }
    }
    if (active != _activeSection.value) _activeSection.value = active;
  }

  void _jumpToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null || !_scroll.hasClients) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final raw =
        RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset -
            _indexHeight;
    final to = raw.clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    final i = _indexedKeys.indexOf(key);
    _jumping = true;
    _scroll
        .animateTo(to,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic)
        .whenComplete(() => _jumping = false);
    if (i >= 0 && i != _activeSection.value) _activeSection.value = i;
  }

  Future<void> _editMnemonic(WordCard card) async {

    final ctl = TextEditingController(text: card.mnemonicShown ?? '');

    final initial = ctl.text;

    final app = context.read<AppState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('助记 · ${card.word}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              maxLines: 4,
              maxLength: 200,
              decoration: const InputDecoration(

                hintText: 'makanan = makan（吃）+ -an → 吃的东西\n'
                    'kantor（办公室）← 荷兰语 kantoor\n'
                    'dokter（医生）≈ 英语 doctor',
                hintMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),

            MnemonicTemplates(controller: ctl),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => ctl.text = initial,
            child: const Text('重置'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      await app.db.saveMnemonic(card.id, result);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final card = _card;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('未找到该单词')),
      );
    }
    final meta = _metaItems(card);
    final entries = _indexEntries(card);
    _indexedKeys = [for (final e in entries) e.key];
    return Scaffold(
      appBar: AppBar(

        title: Text(card.word, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [

          if (kAiChat)
            AiAppBarButton(
              key: const ValueKey('detail.askAi'),
              tooltip: '问一问（AI 讲解 / 造句批改）',
              onTap: () => showAiChatSheet(context, card, onCardChanged: _load),
            ),
          IconButton(
            tooltip: '复制完整词条（释义与例句）',
            icon: const Icon(Icons.copy_outlined),

            onPressed: () => copyText(
              context,
              wordCopyText(card, withExamples: true),
              label: '已复制完整词条',
            ),
          ),

          if (card.userWord)
            IconButton(
              tooltip: '改这条自建词（词形 / 中文 / 例句 / 助记 / 发音）',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final changed = await openUserWordForm(context, existing: card);

                if (!context.mounted || changed != true) return;

                final again =
                    await context.read<AppState>().db.getWord(widget.cardId);
                if (!context.mounted) return;
                if (again == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('词形改了，主键跟着换 —— 这是那条新卡')));
                  Navigator.pop(context);
                } else {
                  setState(() => _card = again);
                }
              },
            ),
          IconButton(
            icon: Icon(card.favorite ? Icons.star : Icons.star_border,
                color: card.favorite ? const Color(0xFFFFA940) : null),
            onPressed: () async {
              await context.read<AppState>().db.toggleFavorite(card.id);
              await _load();
            },
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _CardBox(
                padding: const EdgeInsets.fromLTRB(17, 16, 17, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(

                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(card.word,
                                maxLines: 1,
                                style: const TextStyle(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SpeakButton(card: card, filled: true, iconSize: 24),
                      ],
                    ),
                    if (card.phonetic != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(card.phonetic!,
                            style:
                                TextStyle(color: context.k.t2, fontSize: 14)),
                      ),

                    if (card.affixType != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '${card.affixType} · 不是单词，是词缀（${card.word}）',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.k.gWarn)),
                      ),
                    if (card.zhClean != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(card.zhClean!,
                            style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                height: 1.35)),
                      ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: meta,
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(height: 0.5, color: context.k.line),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          if (_enrolled)
                            Container(
                              key: const ValueKey('detail-enrolled'),
                              height: 34,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: context.k.tint,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 16, color: context.k.deep),
                                  const SizedBox(width: 5),
                                  Text('已在记忆中',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: context.k.deep)),
                                ],
                              ),
                            )
                          else
                            SizedBox(
                              height: 34,
                              child: FilledButton.icon(
                                key: const ValueKey('detail-enroll'),
                                onPressed:
                                    _enrolling ? null : () => _remember(card),
                                icon: _enrolling
                                    ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: context.k.onbrand),
                                      )
                                    : const Icon(Icons.add, size: 16),
                                label: Text(_enrolling ? '加入中…' : '加入记忆',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: context.k.brand,
                                  foregroundColor: context.k.onbrand,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9)),
                                ),
                              ),
                            ),
                          const Spacer(),

                          if (kAiChat)
                            AiAskChip(
                              key: const ValueKey('detail.askAiChip'),
                              dense: true,
                              label: '问 AI 这个词',
                              onTap: () => showAiChatSheet(context, card,
                                  onCardChanged: _load),
                            )
                          else
                            Text('点句中单词可查词',
                                style: TextStyle(
                                    fontSize: 11.5, color: context.k.t3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(

              child: HomographHint(
                  card: card, onOpenDetail: detailOpener(context)),
            ),
          ),

          if (entries.length > 1) ...[

            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _IndexBarDelegate(
                entries: entries,
                active: _activeSection,
                onTap: (i) => _jumpToSection(entries[i].key),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Column(children: [

                _Section(
                  key: _sectionKey('mnemonic'),
                  title: '助记',
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '编辑助记文字',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: () => _editMnemonic(card),
                  ),

                  background: context.k.mntint,
                  borderColor: context.k.mnDash.withValues(alpha: 0.55),
                  child: MnemonicSection(card: card, onChanged: _load),
                ),

                if (AffixSection.has(card))
                  _Section(
                    key: _sectionKey('affix'),
                    title: '词根词缀拆解',
                    hint: '点词根可查它自己的卡片',
                    child: AffixSection(
                      card: card,
                      onOpenDetail: detailOpener(context),
                      breakdownSize: 20,
                    ),
                  ),

                if (GrammarNoteSection.has(context, card))
                  _Section(
                    key: _sectionKey('usage'),
                    title: GrammarNoteSection.label(card),
                    hint: card.grammarFunctionLabel,
                    child: GrammarNoteSection(
                      notes: card.grammarNotes,
                      limit: null,
                      wordId: card.id,
                      onOpenDetail: detailOpener(context),
                    ),
                  ),

                if (card.examples.isNotEmpty)
                  _Section(
                    key: _sectionKey('examples'),
                    title: '例句',
                    count: '${card.examples.length} 条',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < card.examples.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child:
                                  Container(height: 0.5, color: context.k.line),
                            ),
                          TappableIdText(
                            text: card.examples[i].text,
                            style: const TextStyle(fontSize: 15, height: 1.55),

                            highlight: {card.id},
                            highlightColor: context.k.brand,
                            onOpenDetail: detailOpener(context),
                          ),
                          if (card.examples[i].zh != null &&
                              card.examples[i].zh!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.only(left: 9),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                        color: context.k.brand
                                            .withValues(alpha: 0.35),
                                        width: 2),
                                  ),
                                ),

                                child: Text(card.examples[i].zh!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: context.k.t2,
                                        height: 1.5)),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),

                if (card.senses.isNotEmpty)
                  _Section(
                    key: _sectionKey('senses'),
                    title: '释义（KBBI 官方）',
                    count: '${card.senses.length} 条',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < card.senses.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child:
                                  Container(height: 0.5, color: context.k.line),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 16,
                                child: Text('${i + 1}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: context.k.t3)),
                              ),

                              SizedBox(
                                width: 38,
                                child: card.senses[i].pos == null
                                    ? null
                                    : Text('${card.senses[i].pos}.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.k.t3)),
                              ),
                              Expanded(
                                child: TappableIdText(
                                  text: card.senses[i].def,
                                  style: const TextStyle(
                                      fontSize: 14.5, height: 1.6),
                                  onOpenDetail: detailOpener(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                if (card.derivations.isNotEmpty)
                  _Section(
                    key: _sectionKey('derivations'),
                    title: '派生词形',
                    count: '${card.derivations.length} 个',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DerivationList(
                          derivations: card.derivations,

                          limit: _showAllDerivations ? null : 8,
                          onTapDerivation: (d) => showWordSheet(context, d.form,
                              onOpenDetail: detailOpener(context)),
                        ),
                        if (card.derivations.length > 8) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => setState(() =>
                                _showAllDerivations = !_showAllDerivations),
                            child: Container(
                              height: 37,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.k.alt,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      _showAllDerivations
                                          ? '收起'
                                          : '展开全部 ${card.derivations.length} 个词形',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.k.deep)),
                                  const SizedBox(width: 4),
                                  Icon(
                                      _showAllDerivations
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 16,
                                      color: context.k.deep),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (card.gabunganKata.isNotEmpty)
                  _Section(
                    key: _sectionKey('gabungan'),
                    title: '词组搭配（KBBI）',
                    count: '${card.gabunganKata.length} 个',
                    hint: '点搭配可查词',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final g in _showAllGabungan
                                ? card.gabunganKata
                                : card.gabunganKata.take(12))
                              GestureDetector(
                                onTap: () => showWordSheet(context, g,
                                    onOpenDetail: detailOpener(context)),
                                child: Chip(
                                  label: Text(g,
                                      style: const TextStyle(fontSize: 13)),
                                  backgroundColor: context.k.alt,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                        if (card.gabunganKata.length > 12) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => setState(
                                () => _showAllGabungan = !_showAllGabungan),
                            child: Container(
                              height: 37,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.k.alt,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      _showAllGabungan
                                          ? '收起'
                                          : '展开全部 '
                                              '${card.gabunganKata.length} 个搭配',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.k.deep)),
                                  const SizedBox(width: 4),
                                  Icon(
                                      _showAllGabungan
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 16,
                                      color: context.k.deep),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (card.clitics.isNotEmpty)
                  _Section(
                    key: _sectionKey('clitics'),
                    title: '附着词用法',
                    child: CliticSection(
                        clitics: card.clitics,
                        onOpenDetail: detailOpener(context)),
                  ),

                if (card.nonStandardForms.isNotEmpty)
                  _Section(
                    key: _sectionKey('nonstd'),
                    title: '非正式写法',
                    count: '${card.nonStandardForms.length} 个',
                    hint: '点一下查词',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in card.nonStandardForms)
                              GestureDetector(
                                onTap: () => showWordSheet(context, s,
                                    onOpenDetail: detailOpener(context)),
                                child: Chip(
                                  label: Text(s,
                                      style: const TextStyle(fontSize: 13)),
                                  backgroundColor:
                                      context.k.nFaint2.withValues(alpha: 0.12),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('这些写法不规范，认识即可，正式场合请用本词条的写法',
                            style:
                                TextStyle(fontSize: 12, color: context.k.nT2)),
                      ],
                    ),
                  ),

                if (card.nonStandard != null || card.variants.isNotEmpty)
                  _Section(
                    key: _sectionKey('variants'),
                    title: '变体',
                    child: Text([
                      if (card.nonStandard != null) '非标准：${card.nonStandard}',
                      if (card.variants.isNotEmpty)
                        '变体：${card.variants.join(', ')}',
                    ].join('\n')),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _metaItems(WordCard card) {
    final out = <Widget>[];
    if (card.wordClassLabelsCombined.isNotEmpty) {
      out.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.k.tint,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(card.wordClassLabelsCombined,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.k.deep)),
      ));
    }
    final texts = <String>[
      if (card.rank != null)
        '${card.tierLabel} · 语料排名 #${card.rank}'
      else
        card.tierLabel,
      if (card.originLabel != null) '借自${card.originLabel}',
      if (card.properKindLabel != null) card.properKindLabel!,
      if (card.phraseKindLabel != null) card.phraseKindLabel!,
      if (card.fullName != null) '简写专名 · ${card.fullName}',
    ];
    for (var i = 0; i < texts.length; i++) {
      if (i > 0) out.add(const _MetaDot());
      out.add(
          Text(texts[i], style: TextStyle(fontSize: 12, color: context.k.t3)));
    }
    return out;
  }

  List<_IndexEntry> _indexEntries(WordCard card) => [
        _IndexEntry('mnemonic', '助记', null, _sectionKey('mnemonic')),
        if (AffixSection.has(card))
          _IndexEntry('affix', '词根', null, _sectionKey('affix')),
        if (GrammarNoteSection.has(context, card))
          _IndexEntry('usage', GrammarNoteSection.label(card), null,
              _sectionKey('usage')),
        if (card.examples.isNotEmpty)
          _IndexEntry('examples', '例句', '${card.examples.length}',
              _sectionKey('examples')),
        if (card.senses.isNotEmpty)
          _IndexEntry(
              'senses', '释义', '${card.senses.length}', _sectionKey('senses')),
        if (card.derivations.isNotEmpty)
          _IndexEntry('derivations', '派生', '${card.derivations.length}',
              _sectionKey('derivations')),
        if (card.gabunganKata.isNotEmpty)
          _IndexEntry('gabungan', '搭配', '${card.gabunganKata.length}',
              _sectionKey('gabungan')),
        if (card.clitics.isNotEmpty)
          _IndexEntry('clitics', '附着词', null, _sectionKey('clitics')),
        if (card.nonStandardForms.isNotEmpty)
          _IndexEntry('nonstd', '非正式', '${card.nonStandardForms.length}',
              _sectionKey('nonstd')),
        if (card.nonStandard != null || card.variants.isNotEmpty)
          _IndexEntry('variants', '变体', null, _sectionKey('variants')),
      ];
}

class _CardBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? background;
  final Color? borderColor;

  const _CardBox({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? context.k.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? context.k.line, width: 0.5),
      ),
      child: child,
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: context.k.faint, shape: BoxShape.circle),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;

  final String? hint;

  final String? count;
  final Widget child;
  final Widget? trailing;
  final Color? background;
  final Color? borderColor;
  const _Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.hint,
    this.count,
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _CardBox(
        background: background,
        borderColor: borderColor,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.k.text)),
                if (hint != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(hint!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: context.k.t3)),
                  ),
                ] else
                  const Spacer(),
                if (count != null)
                  Text(count!,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.k.t3)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _IndexEntry {
  final String id;
  final String label;
  final String? count;
  final GlobalKey key;
  _IndexEntry(this.id, this.label, this.count, this.key);
}

class _IndexBarDelegate extends SliverPersistentHeaderDelegate {
  final List<_IndexEntry> entries;
  final ValueListenable<int> active;
  final ValueChanged<int> onTap;

  _IndexBarDelegate({
    required this.entries,
    required this.active,
    required this.onTap,
  });

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ValueListenableBuilder<int>(
      valueListenable: active,
      builder: (context, value, _) {
        final current =
            entries.isEmpty ? 0 : value.clamp(0, entries.length - 1).toInt();
        return Container(
          decoration: BoxDecoration(
            color: context.k.surface,
            border:
                Border(bottom: BorderSide(color: context.k.line, width: 0.5)),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (ctx, i) {
              final e = entries[i];
              final on = i == current;
              return Center(
                child: GestureDetector(
                  key: ValueKey('detail-index-${e.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Semantics(
                    button: true,
                    selected: on,
                    label: e.count == null ? e.label : '${e.label} ${e.count}',
                    child: Container(
                      height: 29,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: on ? context.k.tint : context.k.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: on ? context.k.tint : context.k.line,
                            width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.label,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight:
                                      on ? FontWeight.w700 : FontWeight.w600,
                                  color: on ? context.k.deep : context.k.t2)),
                          if (e.count != null) ...[
                            const SizedBox(width: 5),
                            Text(e.count!,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: on ? context.k.deep : context.k.t3)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _IndexBarDelegate old) => true;
}
