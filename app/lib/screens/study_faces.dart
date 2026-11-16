part of 'study_screen.dart';

extension _StudyFaces on _StudyScreenState {

  Widget _buildFront(WordCard card, {required bool spelling}) {
    if (spelling) {
      final qs = clozeQuestions(card.examples, card.id);
      if (qs.isNotEmpty) return _buildSpellingFront(card, qs);
    }
    return Container(
      key: const ValueKey('front'),

      color: Colors.transparent,

      child: _FrontHint(onTap: _flip),
    );
  }

  Widget _buildSpellingFront(WordCard card, List<ClozeQuestion> qs) {
    return Container(
      key: const ValueKey('front'),

      alignment: Alignment.topLeft,
      color: Colors.transparent,
      child: _SpellingFront(
          card: card, questions: qs, revealed: _typeCorrect == false),
    );
  }

  String _kbbiStripText(WordCard card) {
    final all = card.senses;
    if (all.isEmpty) return '（本词暂无 KBBI 释义）';
    const kStripLimit = 4;
    final shown = all.take(kStripLimit).toList();
    final buf = StringBuffer();
    for (var i = 0; i < shown.length; i++) {
      if (i > 0) buf.write('\n');
      buf.write('${i + 1}. ${shown[i].def}');
    }
    if (all.length > shown.length) {
      buf.write('\n（共 ${all.length} 条，完整见下方「释义（KBBI）」）');
    }
    return buf.toString();
  }

  Widget _sensesBody(WordCard card) {
    final expanded = _sensesShownFor == card.id;
    return _SensesBody(
      card: card,
      expanded: expanded,
      onToggle: () =>
          _setState(() => _sensesShownFor = expanded ? null : card.id),
    );
  }

  Widget _nonStdBody(WordCard card) => _NonStdBody(card: card);

  Widget _mnemonicBody(WordCard card) =>
      _MnemonicBody(card: card, onAdd: () => _editCard(card, only: 'mn'));

  Widget _exampleBlock(WordCard card, WordExample e, {bool inset = false}) =>
      _ExampleItem(card: card, example: e, inset: inset);

  Iterable<WordExample> _shownExamples(WordCard card) => _showAllEx
      ? card.examples
      : card.examples.take(_StudyScreenState._exLimit);

  List<Widget> _backExBlockOf(WordCard card) => [
        if (card.examples.isNotEmpty) ...[
          const SizedBox(height: 11),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: _SectionLabel(
              '例句',

              hint: _showExHint ? '点句中任意单词可查词' : null,
              expandable: card.examples.length > _StudyScreenState._exLimit,
              expanded: _showAllEx,
              onToggle: () => _setState(() => _showAllEx = !_showAllEx),
              onEdit: () => _editCard(card, only: 'ex'),
            ),
          ),
          const SizedBox(height: 6),
          _newBlock(
            context,
            hasLabel: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in _shownExamples(card))
                  _exampleBlock(card, e, inset: false),
              ],
            ),
          ),
        ],
      ];

  List<Widget> _backMnBlockOf(WordCard card) => [
        const SizedBox(height: 11),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: _SectionLabel(
            card.showsDefaultMnemonic
                ? '助记 · ${card.mnemonicDefaultKind}（可改）'
                : '助记',
            onEdit: () => _editCard(card, only: 'mn'),
          ),
        ),
        const SizedBox(height: 6),

        _newBlock(context,
            hasLabel: false, tint: context.k.mntint, child: _mnemonicBody(card)),
      ];

  Widget _gabunganBody(WordCard card) => _GabunganBody(
        card: card,
        showAll: _showAllGk,
        onToggle: () => _setState(() => _showAllGk = !_showAllGk),
      );

  Widget _buildBack(WordCard card, {required bool isNew}) {

    final userOrdered = card.userWord && (card.cardOrder ?? '').isNotEmpty;
    return Container(
      key: const ValueKey('back'),

      alignment: Alignment.topLeft,
      color: Colors.transparent,

      child: ListView(
        controller: _scroll,

        padding:
            const EdgeInsets.fromLTRB(0, kOpenStudyLayout ? 0 : 12, 0, 20),
        children: _lazyBackChildren([

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: HomographHint(
                key: ValueKey('hg-${card.id}'),
                card: card,
                onOpenDetail: detailOpener(context)),
          ),

          if (userOrdered) ...[
            for (final seg in card.cardOrder!.split(',')) ...[
              if (seg == 'ex') ..._backExBlockOf(card),
              if (seg == 'mn') ..._backMnBlockOf(card),
              if (seg.startsWith('b'))
                ..._backUserBlockOf(card, int.parse(seg.substring(1))),
            ],
          ] else ...[

            if (card.examples.isNotEmpty) ...[
              const SizedBox(height: 11),
              _newBlock(
                context,
                hasLabel: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                      '例句',
                      hint: '点句中任意单词可查词',
                      expandable:
                          card.examples.length > _StudyScreenState._exLimit,
                      expanded: _showAllEx,
                      onToggle: () => _setState(() => _showAllEx = !_showAllEx),
                      onEdit: () => _editCard(card, only: 'ex'),
                    ),
                    const SizedBox(height: 4),
                    for (final e in _shownExamples(card))
                      _exampleBlock(card, e, inset: true),
                  ],
                ),
              ),
            ],

            ..._backSection(
              label: card.showsDefaultMnemonic
                  ? '助记 · ${card.mnemonicDefaultKind}（可改）'
                  : '助记',
              hint: card.hasOwnMnemonic ? '点右上角可改 / 加图' : '点右上角写一条或加张图',
              onEdit: () => _editCard(card, only: 'mn'),
              body: _mnemonicBody(card),
            ),

            if (card.derivations.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: _SectionLabel(
                  '派生词',
                  hint: '点一下查词',
                  expandable:
                      card.derivations.length > _StudyScreenState._dvLimit,
                  expanded: _showAllDv,
                  onToggle: () => _setState(() => _showAllDv = !_showAllDv),
                  onEdit: () => _editCard(card, only: 'dv'),
                ),
              ),
              const SizedBox(height: 6),
              _newBlock(
                context,
                hasLabel: false,
                child: DerivationList(
                  derivations: card.derivations,

                  limit: _showAllDv ? null : _StudyScreenState._dvLimit,
                  onTapDerivation: (d) => showWordSheet(context, d.form,
                      onOpenDetail: detailOpener(context),
                      kbbiDef: d.def,
                      kbbiZh: d.gloss),
                ),
              ),
            ],

            if (card.gabunganKata.isNotEmpty)
              ..._backSection(
                label: '词组搭配',
                hint: '点搭配可查词',
                tint: context.k.mntint,
                body: _gabunganBody(card),
              ),

            if (AffixSection.has(card))
              ..._backSection(
                label: '词根词缀',
                hint: '点词根可查它自己的卡片',
                body: AffixSection(
                    bare: true,
                    card: card,
                    onOpenDetail: detailOpener(context)),
              ),

            if (GrammarNoteSection.has(context, card))
              ..._backSection(
                label: GrammarNoteSection.label(card),
                hint: card.grammarNotes.isEmpty
                    ? card.grammarFunctionLabel
                    : card.grammarFunctionLabel == null
                        ? '点句中的词可查词'
                        : '${card.grammarFunctionLabel} · 点句中的词可查词',
                body: GrammarNoteSection(
                  bare: true,
                  notes: card.grammarNotes,
                  limit: 3,
                  onOpenDetail: detailOpener(context),

                  wordId: card.id,
                ),
              ),

            if (kKbbiLocal && card.senses.isNotEmpty)
              ..._backSection(
                label: '释义（KBBI）',
                hint: '点释义里的单词可查词',
                body: _sensesBody(card),
              ),

            if (card.clitics.isNotEmpty) ...[
              const SizedBox(height: 11),
              _newBlock(
                context,
                hasLabel: false,
                child: CliticSection(
                    bare: true,
                    clitics: card.clitics,
                    onOpenDetail: detailOpener(context)),
              ),
            ],

            if (card.nonStandardForms.isNotEmpty)
              ..._backSection(
                label: '非正式写法',
                hint: '点一下查词',
                body: _nonStdBody(card),
              ),
            if (_histDays.isNotEmpty) ...[
              const SizedBox(height: 13),
              _newBlock(
                context,
                hasLabel: false,
                child: ReviewHistory(
                  key: ValueKey('review-history-${card.id}'),
                  cardId: card.id,
                  days: _histDays,
                  logs: _histLogs,
                  today: _histToday,
                ),
              ),
            ],

            if (kAiChat) ...[
              const SizedBox(height: 13),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: AiAskCard(
                  onTap: () =>
                      showAiChatSheet(context, card, onCardChanged: _reloadCard),
                ),
              ),
            ],

            const SizedBox(height: 11),
            Center(
              child: Text('点单词查词 · 右滑撤销上一张',
                  style: TextStyle(fontSize: 11, color: context.k.g400)),
            ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _backSection({
    required String label,
    String? hint,
    VoidCallback? onEdit,
    required Widget body,
    Color? tint,
    double top = 11,
  }) =>
      [
        SizedBox(height: top),
        _newBlock(
          context,
          hasLabel: true,
          tint: tint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label, hint: hint, onEdit: onEdit),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: body,
              ),
            ],
          ),
        ),
      ];

  List<Widget> _lazyBackChildren(List<Widget> blocks) => [
        for (final w in blocks)
          Align(alignment: AlignmentDirectional.topStart, child: w),
      ];

  List<Widget> _backUserBlockOf(WordCard card, int i) {
    final b = card.userBlocks[i];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: _SectionLabel(b.label,
            hint: '点右上角可改',
            onEdit: () => _editCard(card, only: 'ex')),
      ),
      const SizedBox(height: 6),
      _newBlock(
        context,
        hasLabel: false,
        child: b.type == 'text'
            ? Text(b.text ?? '',
                style: const TextStyle(fontSize: 14.5, height: 1.5))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in b.lines)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('· $l',
                            style:
                                const TextStyle(fontSize: 14.5, height: 1.4))),
                ],
              ),
      ),
    ];
  }
}
