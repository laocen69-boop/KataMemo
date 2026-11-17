library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../ocr_scan.dart';
import '../platform/io_shim.dart';
import '../theme/k_colors.dart';
import '../widgets/quota_dialog.dart';
import '../widgets/word_search.dart' show SrsLevelMap, loadLevels, strengthOf;
import '../widgets/word_sheet.dart';
import '../widgets/word_tile.dart';
import 'select_screen.dart' show wordEnrolled;

import 'my_words_screen.dart' show openUserWordForm;
import 'word_detail_screen.dart';

enum _Phase { idle, recognizing, done, error }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MlKitOcrEngine _engine = MlKitOcrEngine();

  _Phase _phase = _Phase.idle;
  String _imagePath = '';
  String _err = '';
  ScanOutcome? _outcome;

  bool _fromText = false;

  final Set<String> _sel = {};
  SrsLevelMap _levels = const {};
  Set<String> _planned = const {};

  String _filter = 'all';

  bool _enrolledOf(WordCard w) =>
      wordEnrolled(w.id, w.enabled, planned: _planned, levels: _levels);

  Future<void> _pick(bool camera) async {
    final app = context.read<AppState>();
    final XFile? x;
    try {
      x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,

        maxWidth: 2048,
        imageQuality: 85,
      );
    } catch (e) {

      _fail('打不开${camera ? '相机' : '相册'}：$e');
      return;
    }
    if (x == null) return;

    final imgPath = x.path;
    setState(() {
      _phase = _Phase.recognizing;
      _imagePath = imgPath;
      _fromText = false;
      _sel.clear();
      _err = '';
    });
    await _runMatch(() async => matchScan(app.db, await _engine.recognize(imgPath)));
  }

  Future<void> _runMatch(Future<ScanOutcome> Function() job) async {
    try {
      final outcome = await job();
      if (!mounted) return;
      await _loadMeta(outcome);
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _phase = _Phase.done;
      });
    } on PlatformException catch (e) {
      _fail(e.message ?? '识别失败');
    } catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _err = msg;
    });
  }

  Future<void> _pasteText() async {
    final app = context.read<AppState>();
    String initial = '';
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      initial = (data?.text ?? '').trim();
    } catch (_) {

    }
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => PasteTextDialog(initial: initial),
    );
    final src = (text ?? '').trim();
    if (src.isEmpty || !mounted) return;
    setState(() {
      _phase = _Phase.recognizing;
      _imagePath = '';
      _fromText = true;
      _sel.clear();
      _err = '';
    });
    await _runMatch(() => matchPastedText(app.db, src));
  }

  Future<void> _loadMeta(ScanOutcome outcome) async {
    final app = context.read<AppState>();
    final cards = [for (final m in outcome.matched) m.card];
    if (cards.isEmpty) {
      _levels = const {};
      _planned = const {};
      return;
    }
    final lv = await loadLevels(app.db, cards);
    final planned = await app.db.plannedIds([for (final c in cards) c.id]);
    if (!mounted) return;
    setState(() {
      _levels = lv;
      _planned = planned;
    });
  }

  void _toggleSel(WordCard w) {

    if (!w.enabled) return;
    if (_sel.contains(w.id)) {
      setState(() => _sel.remove(w.id));
      return;
    }
    final quota = context.read<AppState>().dailyQuota;
    if (_sel.length >= quota) {
      _showOverQuota(quota);
      return;
    }
    setState(() => _sel.add(w.id));
  }

  Future<void> _showOverQuota(int quota) async {
    final changed =
        await showOverQuotaDialog(context, context.read<AppState>(), quota);
    if (changed && mounted) setState(() {});
  }

  Future<void> _applySelection() async {
    final app = context.read<AppState>();
    final byId = {
      for (final m in (_outcome?.matched ?? const <ScanMatch>[])) m.card.id: m,
    };
    final ids = [
      for (final id in _sel)
        if (byId[id] != null &&
            byId[id]!.card.enabled &&
            !_enrolledOf(byId[id]!.card))
          id,
    ];
    if (ids.isEmpty) {
      setState(_sel.clear);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 1600),
          content: Text('勾上的都已经在记忆里了')));
      return;
    }
    await app.remember(ids);
    if (!mounted) return;
    setState(() {
      _planned = {..._planned, ...ids};
      _sel.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text(scopeHint(app, ids.length)),
    ));
  }

  static String scopeHint(AppState app, int n) {
    final scope = app.book;
    return scope == null
        ? '已加入记忆 $n 个，会排进下一组学习队列'
        : '已加入记忆 $n 个 · 当前学习范围是「${scope.name}」，'
            '不含它们就不会出现在队列里';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.k.nBg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _body()),
            if (_phase == _Phase.done && (_outcome?.matched.isNotEmpty ?? false))
              _bottomPill(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 14, 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
            ),
            const Text('拍照抓词',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return _idleView();
      case _Phase.recognizing:
        return _recognizingView();
      case _Phase.error:
        return _errorView();
      case _Phase.done:
        return _doneView();
    }
  }

  Widget _idleView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.document_scanner,
                  size: 64, color: context.k.brand.withValues(alpha: 0.85)),
              const SizedBox(height: 18),
              const Text('拍下书本或笔记上的生词',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('识别印尼语单词和旁边的中文释义，也可以粘贴文本：\n词库里的直接加入记忆，没收录的一键建卡。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.k.nT2)),
              const SizedBox(height: 26),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.k.brand,
                  foregroundColor: context.k.onbrand,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                ),
                onPressed: () => _pick(true),
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                label: const Text('拍照扫描',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _pick(false),
                icon: Icon(Icons.photo_library_outlined,
                    size: 18, color: context.k.nT2),
                label:
                    Text('从相册选择', style: TextStyle(color: context.k.nT2)),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pasteText,
                icon: Icon(Icons.content_paste_outlined,
                    size: 18, color: context.k.brand),
                label: Text('粘贴文本抓词',
                    style: TextStyle(
                        color: context.k.brand, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  Widget _recognizingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_imagePath.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: buildFileImage(File(_imagePath),
                    width: 190, height: 190, fit: BoxFit.cover),
              )
            else
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: context.k.alt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.text_snippet_outlined,
                    size: 64, color: context.k.brand),
              ),
            const SizedBox(height: 20),
            const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6)),
            const SizedBox(height: 14),
            Text(_fromText ? '正在解析文本…' : '正在识别（Latin + 中文各跑一遍）…',
                style: TextStyle(fontSize: 13, color: context.k.nT2)),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: context.k.nT2),
              const SizedBox(height: 12),
              Text(_err,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: context.k.nT2)),
              const SizedBox(height: 18),
              OutlinedButton(
                  onPressed: _repick,
                  child: Text(_fromText ? '重新输入' : '重新拍一张')),
            ],
          ),
        ),
      );

  void _repick() {
    setState(() {
      _phase = _Phase.idle;
      _outcome = null;
      _err = '';
      _imagePath = '';
      _fromText = false;
    });
  }

  Widget _doneView() {
    final o = _outcome!;
    if (o.matched.isEmpty && o.missed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 44, color: context.k.nT2),
              const SizedBox(height: 12),
              Text(_fromText ? '这段文本没认出可用的词' : '这一页没认出可用的词',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_fromText ? '换一段包含印尼语单词或课文的文本试试。' : '试试离近一点、光线足一点再拍一次。',
                  style: TextStyle(fontSize: 13, color: context.k.nT2)),
              const SizedBox(height: 18),
              OutlinedButton(
                  onPressed: _repick,
                  child: Text(_fromText ? '重新输入' : '重新拍一张')),
            ],
          ),
        ),
      );
    }
    final visible = _filter == 'new'
        ? [
            for (final m in o.matched)
              if (m.card.enabled && !_enrolledOf(m.card)) m,
          ]
        : o.matched;
    final miss = o.missed;
    return Column(
      children: [
        _statsBar(o),
        if (o.matched.isNotEmpty) _filterBar(o),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: visible.length + (miss.isEmpty ? 0 : miss.length + 1),
            itemBuilder: (ctx, i) {
              if (i < visible.length) return _matchRow(visible[i]);
              final j = i - visible.length;
              if (j == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Text('未收录（可建卡）· ${miss.length}',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: context.k.nT2)),
                );
              }
              return _missRow(miss[j - 1]);
            },
          ),
        ),
      ],
    );
  }

  Widget _statsBar(ScanOutcome o) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_fromText ? '解析' : '识别'} ${o.rowcount} 行 · 命中 ${o.matched.length} 词'
                '${o.missed.isEmpty ? '' : ' · 未收录 ${o.missed.length}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: context.k.nT2),
              ),
            ),
            TextButton(
                onPressed: _repick,
                child: Text(_fromText ? '重新输入' : '重拍')),
          ],
        ),
      );

  Widget _filterBar(ScanOutcome o) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Row(
          children: [
            _chip('all', '全部 ${o.matched.length}'),
            const SizedBox(width: 7),
            _chip('new', '未加入'),
          ],
        ),
      );

  Widget _chip(String value, String label) {
    final on = _filter == value;
    return GestureDetector(
      onTap: () => setState(() {
        _filter = value;
        _sel.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? context.k.brand.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: on ? context.k.brand : context.k.g300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? context.k.brand : context.k.nT2)),
      ),
    );
  }

  Widget _matchRow(ScanMatch m) {
    final w = m.card;
    final enrolled = _enrolledOf(w);

    final canJoin = w.enabled;
    return WordTile(
      card: w,

      hint: !canJoin
          ? '仅可查阅'
          : (m.morph
              ? '拍到 ${m.form}，跳到原形'
              : (m.hits > 1 ? '本页 ×${m.hits}' : null)),
      strength: strengthOf(_levels, w.id),
      enrolled: enrolled,
      searchLayout: true,
      member: enrolled,
      selectMode: canJoin,
      selected: _sel.contains(w.id),
      selectable: canJoin && !enrolled,
      onSelectTap: canJoin ? () => _toggleSel(w) : null,
      onTap: () => showWordSheet(context, m.form, onOpenDetail: (id) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: id)));
      }),
      onLongPress: () => _togglePlan(w),
    );
  }

  Future<void> _togglePlan(WordCard w) async {
    if (!w.enabled) return;
    final app = context.read<AppState>();
    if (_enrolledOf(w)) {
      await app.forget([w.id]);
      if (mounted) {
        setState(() => _planned = {..._planned}..remove(w.id));
      }
    } else {
      await app.remember([w.id]);
      if (mounted) {
        setState(() => _planned = {..._planned, w.id});
      }
    }
  }

  Widget _missRow(ScanMiss m) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 6,
      leading: Icon(Icons.add_circle_outline, size: 22, color: context.k.nT2),
      title: Text(m.form,
          style: const TextStyle(
              fontSize: 15.5, fontWeight: FontWeight.w600)),
      subtitle: m.zh.isEmpty
          ? null
          : Text(
              '${m.weakZh ? '（下一行猜测）' : ''}$m.zh',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: context.k.nT2)),
      trailing: TextButton(
        onPressed: () => openUserWordForm(context,
            initialWord: m.form, initialZh: m.weakZh ? '' : m.zh),
        child: const Text('建卡'),
      ),
    );
  }

  Widget _bottomPill() {
    final quota = context.select<AppState, int>((a) => a.dailyQuota);
    final n = _sel.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: 190,
              height: 42,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.k.brand,
                  foregroundColor: context.k.onbrand,
                  disabledBackgroundColor: context.k.alt,
                  disabledForegroundColor: context.k.nT2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(21)),
                ),
                onPressed: n == 0 ? null : _applySelection,
                child: Text('加入记忆 $n/$quota',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PasteTextDialog extends StatefulWidget {
  const PasteTextDialog({super.key, this.initial = ''});

  final String initial;

  @override
  State<PasteTextDialog> createState() => _PasteTextDialogState();
}

class _PasteTextDialogState extends State<PasteTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴文本抓词'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          decoration: InputDecoration(
            filled: true,
            fillColor: context.k.alt,
            hintText: '每行一个词，或直接粘贴整段课文；词后跟中文释义也可以。',
            hintStyle: TextStyle(color: context.k.faint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.k.brand, width: 1.4),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('识别')),
      ],
    );
  }
}
