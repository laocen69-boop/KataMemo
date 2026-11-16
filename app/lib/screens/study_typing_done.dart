part of 'study_screen.dart';

extension _StudyTypingDone on _StudyScreenState {

  ClozeQuestion? _spellQ(WordCard card) {
    final qs = clozeQuestions(card.examples, card.id);
    return qs.isEmpty ? null : qs.first;
  }

  Future<void> _checkTyping(WordCard card) async {
    final q = _spellQ(card);
    if (q == null || _busy || _typeCorrect != null) return;
    if (foldCloze(_typeCtl.text).isEmpty) return;
    final ok = clozeAnswerOk(_typeCtl.text,
        cardId: card.id, cardWord: card.word, answer: q.answer);
    if (ok) {
      _autoPlayCard(card);
      _typeCtl.clear();
      await _rate(Fsrs.ratingKnow);
      return;
    }
    _setState(() => _typeCorrect = false);
    _autoPlayCard(card);
  }

  void _peekTyping(WordCard card) {
    if (_spellQ(card) == null || _busy || _typeCorrect != null) return;
    _setState(() => _typeCorrect = false);
    _autoPlayCard(card);
  }

  Future<void> _continueAfterReveal() async {
    if (_busy || _typeCorrect != false) return;
    _setState(() => _typeCorrect = null);
    _typeCtl.clear();
    await _rate(Fsrs.ratingForget);
  }

  String _slotTarget(WordCard card, String typed) {
    final q = _spellQ(card);
    final ans = q?.answer ?? card.word;
    final x = foldCloze(typed);
    if (x.isNotEmpty && x != foldCloze(ans) && x == foldCloze(card.word)) {
      return card.word;
    }
    return ans;
  }

  Widget _spellBar(WordCard card) {
    final q = _spellQ(card)!;
    final revealed = _typeCorrect == false;
    final k = context.k;
    if (revealed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cancel, size: 18, color: kRatingForget),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('没拼对 · 正确答案：${q.answer}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kRatingForget)),
                ),
                SpeakButton(card: card, iconSize: 22, color: k.nSlate),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 46,
              child: FilledButton(
                key: const Key('spell-verify'),
                onPressed: _busy ? null : _continueAfterReveal,
                style: FilledButton.styleFrom(
                  backgroundColor: k.brand,
                  foregroundColor: k.onbrand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23)),
                ),
                child: const Text('继续（记为困难）',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('spell-input'),
                  controller: _typeCtl,
                  focusNode: _typeFocus,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    _checkTyping(card);

                    _typeFocus.requestFocus();
                  },
                  style: const TextStyle(fontSize: 17),
                  decoration: InputDecoration(
                    hintText: '输入印尼语，回车提交',
                    hintStyle: TextStyle(fontSize: 13.5, color: k.g400),
                    isDense: true,
                    filled: true,
                    fillColor: k.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide(color: k.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide(color: k.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide(color: k.brand, width: 1.4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton.filled(
                  key: const Key('spell-verify'),
                  tooltip: '提交',
                  onPressed: _busy ? null : () => _checkTyping(card),
                  style: IconButton.styleFrom(
                      backgroundColor: k.brand, foregroundColor: k.onbrand),
                  icon: const Icon(Icons.check_rounded, size: 24),
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                key: const Key('spell-give-up'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy ? null : () => _peekTyping(card),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Center(
                      child: Text('不会',
                          style: TextStyle(fontSize: 14, color: k.t2)),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              SpeakButton(card: card, iconSize: 22, color: k.nSlate),
            ],
          ),
        ],
      ),
    );
  }

  ({
    String title,
    String hint,
    Color tone,
    IconData icon,
    bool zero,
    bool quotaOut,
    bool moreGroup,
    bool nothingToLearn,
    bool empty,
  }) _doneCopy() {
    final app = context.read<AppState>();
    final quota = app.dailyQuota;

    final reviewOwe = _plan.reviewPlan - _plan.reviewDone;
    final parts = <String>[
      if (reviewOwe > 0) '$reviewOwe 张复习',
      if (_plan.poolLeft > 0) '${_plan.poolLeft} 个生词',
    ];
    final stop = studyStopOf(_plan);
    final zero = stop == StudyStop.zero;
    final quotaOut = stop == StudyStop.quotaOut;

    final moreGroup = stop == StudyStop.moreGroup;
    final nothingToLearn = stop == StudyStop.nothingToLearn;

    final empty = nothingToLearn && _neverEnrolled;
    final tone = zero
        ? context.k.q4
        : quotaOut
            ? context.k.star
            : kSpeakGreen;
    final title = zero
        ? '今日卡量是 0'
        : quotaOut
            ? '今日卡量已用完'
            : moreGroup
                ? '这一组学完了'
                : empty
                    ? '还没有要学的词'

                    : _plan.finished == 0
                        ? '今天没有要学的卡'

                        : _plan.finished < _plan.quotaShown
                            ? '已加入的词都学完了'
                            : '今日任务已全部完成！';
    final hint = empty
        ? '先去词库挑一些词「加入记忆」，这里才会有卡片。\n'
            '加多少都行，每天学几张由卡量决定。'
        : zero
            ? '卡量 0 = 今天一张都不排（复习和新词都占卡量）。'
                '想学就把它调高${parts.isNotEmpty ? '：今天其实还有 ${parts.join('、')}' : ''}'
            : quotaOut
                ? '还有 ${parts.join('、')} 没排上。明天会优先复习；'
                    '急着清就调高卡量（复习积压多时当天可能清不完）'
                : moreGroup
                    ? '还有 ${parts.join('、')}，今日卡量还剩 '
                        '${(quota - _plan.finished).clamp(0, quota)} 张 '
                        '→ 点「再学一组」接着排'
                    : nothingToLearn

                        ? (_plan.finished < _plan.quotaShown
                            ? '「已加入记忆」的新词不够了：今天还差 '
                                '${_plan.quotaShown - _plan.finished} 张才够卡量。'
                                '点下面去词库添加卡片，回来接着学'
                            : '今天的卡都过完了，词库里也没有「已加入记忆」的新词了。'
                                '去词库挑些词加入记忆才能继续学')
                        : '';
    return (
      title: title,
      hint: hint,
      tone: tone,
      icon: zero
          ? Icons.pause_circle_outline
          : quotaOut
              ? Icons.hourglass_bottom
              : moreGroup
                  ? Icons.skip_next_outlined
                  : (empty || _plan.finished == 0)
                      ? Icons.auto_stories_outlined
                      : Icons.check_circle_outline,
      zero: zero,
      quotaOut: quotaOut,
      moreGroup: moreGroup,
      nothingToLearn: nothingToLearn,
      empty: empty,
    );
  }

  void _goLibraryTab() {
    final tabs = HomeTabs.maybeOf(context);
    if (tabs != null) {
      tabs.select(1);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openAddCards(AppState app) async {
    final target = app.book;
    if (target == null && HomeTabs.maybeOf(context) != null) {
      _goLibraryTab();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => target != null
            ? WordListScreen(book: target, fromStudy: true)
            : const SelectScreen(),
      ),
    );
  }

  Widget _buildDone() {
    final app = context.read<AppState>();
    final c = _doneCopy();
    return Scaffold(
      backgroundColor: context.k.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: kStudyNewCard(context),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: Column(
                    children: [

                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                            color: context.k.tint, shape: BoxShape.circle),
                        child: Icon(c.icon,
                            size: 32,
                            color: c.zero || c.quotaOut
                                ? context.k.t3
                                : context.k.brand),
                      ),
                      const SizedBox(height: 12),
                      Text(c.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: context.k.text)),

                      if (!c.empty) ...[
                        const SizedBox(height: 10),
                        _doneRow(
                            '复习', '${_plan.reviewDone}/${_plan.reviewShown}'),
                        _doneRow('新学', '${_plan.newDone}/${_plan.newPlan}'),
                        _doneRow('今日', '${_plan.finished}/${_plan.quotaShown}'),
                      ],
                      if (_plan.newPending + _plan.reviewPending > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                            '另有 ${_plan.newPending + _plan.reviewPending} 张答了但今天还要再考'
                            '（困难/模糊 会回队，不算「彻底过了」）',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11, color: context.k.faint)),
                      ],
                      if (c.hint.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(c.hint,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 11.5, color: context.k.t3)),
                      ],

                      if (_plan.taskTotal > 0 && _plan.taskLeft == 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: context.k.tint,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  size: 15, color: context.k.deep),
                              const SizedBox(width: 5),
                              Text('已自动签到 · 打卡日历今天标记为完成',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.k.deep)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: c.nothingToLearn
                            ? () async {

                                await _openAddCards(app);
                                if (mounted) await _load(newSession: true);
                              }
                            : (c.zero || c.quotaOut)
                                ? () => showQuotaDialog(context, app)
                                : _load,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.k.brand,
                          foregroundColor: context.k.onbrand,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(
                            c.nothingToLearn
                                ? (c.empty ? '去词库挑词' : '去词库选词')
                                : (c.zero || c.quotaOut ? '修改卡量' : '再学一组'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),

                    if (!(c.nothingToLearn && app.book == null)) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _goLibraryTab,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.k.text,
                            side: BorderSide(color: context.k.border, width: 1),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                          ),
                          child: const Text('返回词库',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                if (app.book == null)
                  Center(
                    child: TextButton.icon(
                      key: const Key('done.pickTarget'),
                      onPressed: () async {
                        await showTargetPicker(context, app);
                        if (mounted) await _load(newSession: true);
                      },
                      icon: Icon(Icons.flag_outlined,
                          size: 16, color: context.k.deep),
                      label: Text('选一个学习目标',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: context.k.deep)),
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => showQuotaDialog(context, app),
                      child: Text('调整卡量',
                          style: TextStyle(fontSize: 13, color: context.k.t3)),
                    ),
                    Text('·',
                        style: TextStyle(fontSize: 13, color: context.k.t3)),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen())),
                      child: Text('更多设置',
                          style: TextStyle(fontSize: 13, color: context.k.t3)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13.5, color: context.k.t3)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.k.text)),
          ],
        ),
      );
}
