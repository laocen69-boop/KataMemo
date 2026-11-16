part of 'study_screen.dart';

extension _StudyEdit on _StudyScreenState {

  Future<void> _editCard(WordCard card, {String? only}) async {

    if (tapGuarded) return;
    final app = context.read<AppState>();

    _editZhCtl.text = card.zh ?? '';
    _editExCtl.text = _StudyScreenState._examplesToText(card.examples);
    _editDvCtl.text = _StudyScreenState._dvsToText(card.derivations);

    _editMnCtl.text = card.mnemonicShown ?? '';

    _editQzCtl.text = card.quizZh ?? questionZhOf(card.zhClean) ?? '';

    final initZh = _editZhCtl.text;
    final initQz = _editQzCtl.text;
    final initEx = _editExCtl.text;
    final initDv = _editDvCtl.text;
    final initMn = _editMnCtl.text;

    const titles = {
      'zh': '中文释义',
      'ex': '例句',
      'dv': '派生词形',
      'mn': '助记',
      'qz': '拼写题面',
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,

      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        only == null
                            ? '编辑 · ${card.word}'
                            : '改${titles[only] ?? ''} · ${card.word}',
                        style: const TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w700)),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.k.nSlate2,
                      side: BorderSide(color: context.k.g300),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.k.brand,
                      foregroundColor: context.k.onbrand,
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (only == null || only == 'zh')
                _editField(
                  icon: Icons.translate,
                  label: '中文释义',
                  help: '学习时卡片背面显示的中文',
                  hint: '如：缺席；缺勤',
                  ctl: _editZhCtl,
                  autofocus: only == 'zh',
                  onReset: () => _editZhCtl.text = initZh,
                ),
              if (only == null || only == 'qz')
                _editField(
                  icon: Icons.spellcheck,
                  label: '拼写题面',
                  help: '拼写模式正面显示的中文（默认自动摘掉释义里的印尼语举例）；'
                      '清空保存 = 回到自动',
                  hint: '如：在…里；在…中；深',
                  ctl: _editQzCtl,
                  autofocus: only == 'qz',
                  onReset: () => _editQzCtl.text = initQz,
                ),
              if (only == null || only == 'ex') ...[
                _structuredPairSection(
                  icon: Icons.format_quote,
                  label: '例句',
                  help: '分开填写印尼语与中文，不用手打 |。在句子里原样写上这个词，这句才能当拼写题',
                  firstHint: 'Dia absen dari kelas.',
                  secondHint: '他缺课了。',
                  firstLabel: '印尼语例句',
                  secondLabel: '中文翻译',
                  addLabel: '添加一句例句',
                  textHint: 'Dia absen dari kelas. | 他缺课了。',
                  ctl: _editExCtl,
                  onReset: () => _editExCtl.text = initEx,
                ),
              ],
              if (only == null || only == 'dv')
                _structuredPairSection(
                  icon: Icons.account_tree_outlined,
                  label: '派生词形',
                  help: '分开填写派生词形与中文释义，不用手打 |',
                  firstHint: 'makanan',
                  secondHint: '食物',
                  firstLabel: '词形',
                  secondLabel: '中文释义',
                  addLabel: '添加一个派生词',
                  textHint: 'makanan | 食物\nmemakan | 吃（动词）',
                  stacked: false,
                  ctl: _editDvCtl,
                  onReset: () => _editDvCtl.text = initDv,
                ),
              if (only == null || only == 'mn')
                _editField(
                  icon: Icons.lightbulb_outline,
                  label: '助记',

                  help: '编一个自己的联想最牢：拆词缀 / 荷语·葡语·英语同源 / 画面',
                  hint: 'makanan = makan（吃）+ -an → 吃的东西\n'
                      'kantor（办公室）← 荷兰语 kantoor\n'
                      'dokter（医生）≈ 英语 doctor',
                  ctl: _editMnCtl,
                  lines: 3,
                  hintMaxLines: 3,

                  footer: MnemonicTemplates(controller: _editMnCtl),
                  autofocus: only == 'mn',
                  onReset: () => _editMnCtl.text = initMn,
                ),

              if (only == null || only == 'mn') ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.image_outlined, size: 16, color: context.k.nT2),
                    const SizedBox(width: 6),
                    const Text('助记图',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('点图放大看；在这里就能加图',
                    style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
                const SizedBox(height: 8),
                MnemonicImageEditor(
                  card: card,

                  onChanged: () => _reloadCard(),
                ),
              ],
              const SizedBox(height: 10),
              Text('修改保存在本机，换词库重导也不会丢',
                  style: TextStyle(fontSize: 10.5, color: context.k.nFaint2)),
            ],
          ),
        ),
      ),
      ),
    );

    final ok = saved == true;
    final zhText = _editZhCtl.text.trim();
    final qzText = _editQzCtl.text.trim();
    final exText = _editExCtl.text;
    final dvText = _editDvCtl.text;
    final mnText = _editMnCtl.text.trim();
    if (!ok) return;
    final db = app.db;

    if (only == null || only == 'zh') {
      if (zhText != (card.zh ?? '')) await db.saveEdit(card.id, 'zh', zhText);
    }
    if (only == null || only == 'qz') {

      final auto = card.quizZh ?? questionZhOf(card.zhClean) ?? '';
      if (qzText != auto) await db.saveEdit(card.id, 'quiz_zh', qzText);
    }
    if (only == null || only == 'ex') {
      final cur = _StudyScreenState._textToExamples(exText);
      if (!examplesUnchanged(card.examples, cur)) {
        await db.saveExamples(card.id, mergeExamples(card.examples, cur));
      }
    }
    if (only == null || only == 'dv') {
      final cur = _StudyScreenState._textToDvs(dvText);
      if (!dvsUnchanged(card.derivations, cur)) {
        await db.saveEdit(
            card.id,
            'derivations',
            WordCard.encodeMaps(
                [for (final d in mergeDvs(card.derivations, cur)) d.toMap()]));
      }
    }
    if (only == null || only == 'mn') {
      if (mnText != (card.mnemonicShown ?? '')) {
        await db.saveMnemonic(card.id, mnText);
      }
    }
    await _reloadCard();
  }

  Widget _structuredPairSection({
    required IconData icon,
    required String label,
    required String help,
    required String firstHint,
    required String secondHint,
    required String firstLabel,
    required String secondLabel,
    required String addLabel,
    required String textHint,
    required TextEditingController ctl,
    bool stacked = true,
    VoidCallback? onReset,
  }) {
    var rawMode = false;
    return StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: ctx.k.nT2),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setLocal(() => rawMode = !rawMode),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: ctx.k.tint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(rawMode ? '表单模式' : '纯文本',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: ctx.k.deep)),
                  ),
                ),
                if (onReset != null) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: onReset,
                    style: TextButton.styleFrom(
                      foregroundColor: ctx.k.nT2,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                    child: const Text('重置', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              rawMode ? '每行一条，用 | 分隔' : help,
              style: TextStyle(fontSize: 11, color: ctx.k.nFaint2),
            ),
            const SizedBox(height: 8),
            if (rawMode)
              TextField(
                controller: ctl,
                maxLines: 5,
                style: const TextStyle(fontSize: 13, height: 1.4),
                decoration: InputDecoration(
                  hintText: textHint,
                  hintStyle: TextStyle(fontSize: 12.5, color: ctx.k.faint),
                  filled: true,
                  fillColor: ctx.k.alt,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ctx.k.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: ctx.k.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: kSpeakGreen, width: 1.5)),
                ),
              )
            else
              PairListEditor(
                controller: ctl,
                firstHint: firstHint,
                secondHint: secondHint,
                firstLabel: firstLabel,
                secondLabel: secondLabel,
                addLabel: addLabel,
                stacked: stacked,
              ),
          ],
        ),
      ),
    );
  }

  Widget _editField({
    required IconData icon,
    required String label,
    required String help,
    required String hint,
    required TextEditingController ctl,
    int lines = 3,

    int? hintMaxLines,

    Widget? footer,

    VoidCallback? onReset,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: context.k.nT2),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onReset != null)
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    foregroundColor: context.k.nT2,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  child: const Text('重置', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(help, style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
          const SizedBox(height: 6),
          TextField(
            controller: ctl,
            maxLines: lines,
            autofocus: autofocus,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: InputDecoration(

              hintText: hint,
              hintMaxLines: hintMaxLines,
              hintStyle: TextStyle(fontSize: 12.5, color: context.k.g400),
              filled: true,
              fillColor: context.k.nFaint2.withValues(alpha: 0.07),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: kSpeakGreen, width: 1.5)),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer,
          ],
        ],
      ),
    );
  }

  Future<void> _reloadCard() async {
    if (_queue.isEmpty || _index >= _queue.length) return;
    final app = context.read<AppState>();
    final fresh = await app.db.getWord(_queue[_index].id);
    if (!mounted || fresh == null) return;
    _setState(() => _cards[fresh.id] = fresh);
  }
}
