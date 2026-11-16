part of 'study_screen.dart';

extension _StudyHeader on _StudyScreenState {

  bool _spellingOf(AppState app, WordCard card) =>
      app.studyMode == 'zh2id' &&
      clozeQuestions(card.examples, card.id).isNotEmpty;

  Widget _studyHeader(
      AppState app, WordCard card, ({WordCard card, bool isNew}) item,
      {required bool spelling}) {
    final zh2id = app.studyMode == 'zh2id';
    final promptFront = spelling && !_flipped;
    final mainText = promptFront
        ? null
        : (zh2id && !_flipped ? (card.zhClean ?? card.word) : card.word);
    final showPhonetic = !zh2id || _flipped;

    final kbbiOn =
        _flipped && card.senses.isNotEmpty && _stripKbbiFor == card.id;
    final String? stripText = promptFront
        ? _StudyScreenState.quizHeaderOf(card)
        : (_flipped
            ? (kbbiOn
                ? _kbbiStripText(card)
                : (card.zhClean == null
                    ? (kKbbiLocal ? '（暂无中文释义，见下方 KBBI 释义）' : '（暂无中文释义）')

                    : (card.zhPosLabeled ??
                        (card.posCodePrefix != null
                            ? '${card.posCodePrefix}. ${card.zhClean}'
                            : card.zhClean!))))
            : null);

    final bool canToggleKbbi =
        _flipped && (!kKbbiLocal || card.senses.isNotEmpty);
    final String measureText = stripText == null
        ? ''
        : (canToggleKbbi
            ? '$stripText  ${kbbiOn ? '看中文' : '看KBBI'}'
            : stripText);
    final int mlines = stripText == null
        ? 0
        : _meaningLineCount(context, measureText,
            fontSize: kbbiOn ? 15.5 : 18, rightInset: 25);

    final k = context.k;

    final double scrH = MediaQuery.sizeOf(context).height;
    final double stripMaxH = scrH - 380 < 120 ? 120 : scrH - 380;

    final double lineH =
        kbbiOn ? 15.5 * 1.45 : (mlines > 3 ? 16 * 1.35 : 18 * 1.3);
    final bool stripScrolls = stripText != null && mlines * lineH > stripMaxH;
    final Widget stripBody = SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: stripText ?? '',
                children: [
                  if (canToggleKbbi)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          if (!kKbbiLocal) {

                            final ok = await openKbbiOfficial(card.word);
                            if (!ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('打不开浏览器，请稍后再试')),
                              );
                            }
                            return;
                          }
                          _setState(
                              () => _stripKbbiFor = kbbiOn ? null : card.id);
                        },

                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(kbbiOn ? '看中文' : '看KBBI',
                              key: const Key('study.kbbiToggle'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: TextStyle(

                                  fontSize:
                                      kbbiOn ? 9.5 : (mlines > 3 ? 10 : 11),
                                  fontWeight: FontWeight.w400,
                                  height: 1.0,
                                  color: k.deep,
                                  decoration: TextDecoration.underline,
                                  decorationColor: k.deep,
                                  decorationThickness: 1)),
                        ),
                      ),
                    ),
                ],
              ),
              style: kbbiOn

                  ? TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: k.text,
                      height: 1.45)

                  : TextStyle(
                      fontSize: mlines > 3 ? 16 : 18,
                      fontWeight:
                          mlines > 3 ? FontWeight.w600 : FontWeight.w700,
                      color: k.text,
                      height: mlines > 3 ? 1.35 : 1.3),
            ),
          ),

          SizedBox(
            width: 25,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editCard(card, only: promptFront ? 'qz' : 'zh'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _PenIcon(size: 17, color: k.bandFaint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Container(
          key: const Key('study.band'),

          decoration: kOpenStudyLayout
              ? null
              : BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [k.bandGradTop, k.bandGradBottom],
                  ),
                  border: Border(
                    bottom: BorderSide(color: k.bandLine, width: 0.5),
                  ),
                ),

          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  key: const Key('study.newProgressRow'),
                  children: [
                    Text('复习 ${_plan.reviewDone}/${_plan.reviewShown}',
                        style: TextStyle(fontSize: 11, color: k.bandText)),
                    const SizedBox(width: 10),
                    Text('新学 ${_plan.newDone}/${_plan.newPlan}',
                        style: TextStyle(fontSize: 11, color: k.bandText)),
                    const Spacer(),
                    if (card.rank != null)
                      Text('语料排名 #${card.rank}',
                          style: TextStyle(fontSize: 11, color: k.bandText)),
                  ],
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15).copyWith(top: 5),
                child: _planBar(),
              ),

              _collapsibleHead(card, mainText ?? card.word, Padding(

                padding:
                    const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          Expanded(
                            child: card.wordClassLabels.isEmpty
                                ? const SizedBox.shrink()

                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: _PosChipRow(
                                      labels: card.wordClassLabels,
                                      color: k.bandChipText,
                                      bg: k.bandChipBg,
                                    ),
                                  ),
                          ),
                          Visibility(
                            visible: _flipped,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,

                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _HeaderIcon(
                                  icon: Icons.track_changes,
                                  tooltip: '调整今日卡量',
                                  color: k.bandFaint,
                                  size: 19,
                                  padding: const EdgeInsets.all(8),
                                  onTap: () => showQuotaDialog(context, app),
                                ),
                                _HeaderIcon(
                                  icon: Icons.edit_outlined,
                                  tooltip: '编辑中文 / 例句 / 助记',
                                  color: k.bandFaint,
                                  size: 19,
                                  padding: const EdgeInsets.all(8),
                                  onTap: () => _editCard(card),
                                ),
                                _HeaderIcon(
                                  icon: Icons.article_outlined,
                                  tooltip: '看完整词条',
                                  color: k.bandFaint,
                                  size: 19,
                                  padding: const EdgeInsets.all(8),
                                  onTap: _goDetail,
                                ),
                                _HeaderIcon(
                                  icon: Icons.more_vert,
                                  tooltip: '详情 / 设置',
                                  color: k.bandFaint,
                                  size: 19,
                                  padding: const EdgeInsets.all(8),
                                  onTap: () => _showCardMenu(card),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (promptFront)
                      SizedBox(

                        key: const Key('study.promptBlock'),
                        height: 68,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,

                          onTap: () => _typeFocus.requestFocus(),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: k.surface,
                              border: Border.all(color: k.brand, width: 0.8),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [

                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 12),

                                  child: ValueListenableBuilder<
                                      TextEditingValue>(
                                    valueListenable: _typeCtl,
                                    builder: (_, v, __) => LetterSlots(
                                        key: const Key('study.letterSlots'),
                                        target: _slotTarget(card, v.text),
                                        typed: v.text,
                                        verdict: _typeCorrect == false,
                                        tile: 19),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('先想想这个词怎么拼',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 14,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        color: k.deep)),
                                const SizedBox(height: 1),
                                Text('一格一个字母',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12, color: k.bandText)),
                              ],
                            ),
                          ),
                        ),
                      )
                    else

                      _SpeakWord(
                        card: card,
                        text: mainText ?? card.word,

                        canSpeak: showPhonetic,
                      ),
                    if (promptFront) const SizedBox(height: 30),
                  ],
                ),
              )),

              if (stripText != null)
                Container(
                  key: const Key('study.meaningStrip'),

                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.fromLTRB(18, 9, 14, 9),
                  child: ConstrainedBox(

                    constraints: BoxConstraints(maxHeight: stripMaxH),
                    child: stripScrolls

                        ? ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (rect) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: const [
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [
                                0,
                                (rect.height - 12) / rect.height,
                                1,
                              ],
                            ).createShader(rect),
                            child: stripBody,
                          )
                        : stripBody,
                  ),
                ),

              SizedBox(height: stripText == null ? 12 : 0),
            ],
          ),
        ),
      ],
    );
  }

  Widget _collapsibleHead(WordCard card, String word, Widget full) {
    final k = context.k;
    return ValueListenableBuilder<bool>(
      valueListenable: _hdrCollapsed,
      builder: (context, collapsed, _) => AnimatedCrossFade(
        duration: const Duration(milliseconds: 180),
        sizeCurve: Curves.easeOut,
        crossFadeState: (_flipped && collapsed)
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: full,

        secondChild: SizedBox(
          key: const Key('study.headCompact'),
          height: 40,
          child: !(_flipped && collapsed) ? null : Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _speakCard(context, card),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(word,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: k.bandInk,
                          letterSpacing: -0.3)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCardMenu(WordCard card) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('看完整词条'),
            onTap: () {
              Navigator.pop(ctx);
              _goDetail();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ]),
      ),
    );
  }

  Widget _rateBar(AppState app,
      {required bool isNew, required bool easyDisabled}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AnimatedBuilder(
        animation: _flashCtrl,
        builder: (context, child) => Container(
          key: const Key('study.rateBar'),
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.k.bandLine, width: 1),
            gradient: _rateBarGradient(
              _flashIndex == null
                  ? 0
                  : Curves.easeInOutCubic.transform(
                      (_flashCtrl.value / 0.80).clamp(0.0, 1.0)),
              _flashIndex,
              dark ? 0.34 : 0.28,
            ),
          ),
          child: child,
        ),
        child: Row(
          children: [
            _RateBarButton(
              label: '轻松',
              color: kRatingEasy,
              enabled: !_busy && !easyDisabled,
              dim: _flashing && _flashIndex != 0,
              hint: easyDisabled
                  ? '—'
                  : (app.showIntervals
                      ? Fsrs.nextLabel(_curSrs, Fsrs.ratingEasy,
                          elapsedDays: _elapsedDays)
                      : null),
              onTap: () => _rateWithFlash(Fsrs.ratingEasy, 0),
            ),
            _RateBarButton(
              label: isNew ? '认识' : '记得',
              color: kRatingKnow,
              primary: true,
              enabled: !_busy,
              dim: _flashing && _flashIndex != 1,
              hint: app.showIntervals
                  ? Fsrs.nextLabel(_curSrs, Fsrs.ratingKnow,
                      elapsedDays: _elapsedDays)
                  : null,
              onTap: () => _rateWithFlash(Fsrs.ratingKnow, 1),
            ),
            _RateBarButton(
              label: '模糊',
              color: kRatingFuzzy,
              enabled: !_busy,
              dim: _flashing && _flashIndex != 2,
              hint: app.showIntervals
                  ? Fsrs.nextLabel(_curSrs, Fsrs.ratingFuzzy,
                      elapsedDays: _elapsedDays)
                  : null,
              onTap: () => _rateWithFlash(Fsrs.ratingFuzzy, 2),
            ),
            _RateBarButton(
              label: '困难',
              color: kRatingForget,
              enabled: !_busy,
              dim: _flashing && _flashIndex != 3,
              hint: app.showIntervals
                  ? Fsrs.nextLabel(_curSrs, Fsrs.ratingForget,
                      elapsedDays: _elapsedDays)
                  : null,
              onTap: () => _rateWithFlash(Fsrs.ratingForget, 3),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _rateBarGradient(double t, int? idx, double baseAlpha) {
    const colors = [kRatingEasy, kRatingKnow, kRatingFuzzy, kRatingForget];
    const baseStops = [0.125, 0.375, 0.625, 0.875];
    const peakStops = [0.0, 0.5, 1.0, 1.0];
    final from = [for (final c in colors) c.withValues(alpha: baseAlpha)];
    if (idx == null) return LinearGradient(colors: from, stops: baseStops);

    final to = [for (final _ in colors) colors[idx].withValues(alpha: 0.52)];
    final cs = <Color>[];
    final st = <double>[];
    for (var i = 0; i < colors.length; i++) {
      cs.add(Color.lerp(from[i], to[i], t)!);
      st.add(baseStops[i] + (peakStops[i] - baseStops[i]) * t);
    }
    return LinearGradient(colors: cs, stops: st);
  }

  Widget _controls(AppState app, WordCard card,
      {required bool isNew, required bool spelling}) {

    final easyDisabled = _curSrs != null &&
        (_curSrs!.state == FsrsState.learning ||
            _curSrs!.state == FsrsState.relearning);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spelling && !_flipped)
          _spellBar(card)
        else

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: (!_flipped && !_busy) ? _flip : null,
            child: SizedBox(height: _flipped ? 8 : 34, width: double.infinity),
          ),

        AnimatedSize(

          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _flipped
              ? (kOpenStudyLayout

                  ? _rateBar(app, isNew: isNew, easyDisabled: easyDisabled)

                  : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),

                  child: Row(
                    children: [

                      _RateButton(
                        label: '轻松',
                        color: kRatingEasy,
                        icon: Icons.bolt,
                        enabled: !_busy && !easyDisabled,
                        disabledBg: context.k.ring,
                        disabledFg: context.k.faint,

                        hint: easyDisabled
                            ? '—'
                            : (app.showIntervals
                                ? Fsrs.nextLabel(_curSrs, Fsrs.ratingEasy,
                                    elapsedDays: _elapsedDays)
                                : null),
                        onTap: () => _rate(Fsrs.ratingEasy),
                      ),
                      const SizedBox(width: 9),
                      _RateButton(
                        label: isNew ? '认识' : '记得',
                        color: kRatingKnow,
                        icon: Icons.check,
                        enabled: !_busy,
                        hint: app.showIntervals
                            ? Fsrs.nextLabel(_curSrs, Fsrs.ratingKnow,
                                elapsedDays: _elapsedDays)
                            : null,
                        onTap: () => _rate(Fsrs.ratingKnow),
                      ),
                      const SizedBox(width: 9),
                      _RateButton(
                        label: '模糊',
                        color: kRatingFuzzy,
                        icon: Icons.help_outline,
                        enabled: !_busy,
                        hint: app.showIntervals
                            ? Fsrs.nextLabel(_curSrs, Fsrs.ratingFuzzy,
                                elapsedDays: _elapsedDays)
                            : null,
                        onTap: () => _rate(Fsrs.ratingFuzzy),
                      ),
                      const SizedBox(width: 9),
                      _RateButton(
                        label: '困难',
                        color: kRatingForget,
                        icon: Icons.close,
                        enabled: !_busy,

                        hint: app.showIntervals
                            ? Fsrs.nextLabel(_curSrs, Fsrs.ratingForget,
                                elapsedDays: _elapsedDays)
                            : null,
                        onTap: () => _rate(Fsrs.ratingForget),
                      ),
                    ],
                  ),
                ))
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

Future<void> _speakCard(BuildContext context, WordCard card) async {
  final r = await AudioService.instance.playCard(
    audio: card.audio,
    parts: card.audioParts,
    word: card.word,
  );
  if (r == PlayOutcome.none && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('这个词没有配音（内置音频没有，你也没导入音频）'),
      duration: Duration(seconds: 2),
    ));
  }
}

class _SpeakWord extends StatefulWidget {
  final WordCard card;
  final String text;
  final bool canSpeak;

  const _SpeakWord(
      {required this.card, required this.text, required this.canSpeak});

  @override
  State<_SpeakWord> createState() => _SpeakWordState();
}

class _SpeakWordState extends State<_SpeakWord>
    with SingleTickerProviderStateMixin {

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _tap() {
    _pulse.forward(from: 0);
    _speakCard(context, widget.card);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final word = SizedBox(
      height: 38,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(widget.text,
              key: const Key('study.word'),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: k.bandInk,
                  letterSpacing: -0.7)),
        ),
      ),
    );
    final below = SizedBox(
      height: 30,
      child: !widget.canSpeak
          ? null
          : Column(
              children: [
                const SizedBox(height: 3),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = math.sin(_pulse.value * math.pi);
                    return Container(
                      key: const Key('study.speakLine'),
                      width: 22 + 30 * t,
                      height: 3,
                      decoration: BoxDecoration(
                        color: k.brand.withValues(alpha: 0.55 + 0.45 * t),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 5),
                if (widget.card.phonetic != null)
                  Text(widget.card.phonetic!,
                      style: TextStyle(
                          fontSize: 11.5, height: 1.2, color: k.bandText)),
              ],
            ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [word, below],
    );
    if (!widget.canSpeak) return body;
    return Tooltip(
      message: '点单词发音',
      child: GestureDetector(
        key: const Key('study.speakWord'),
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: body,
      ),
    );
  }
}
