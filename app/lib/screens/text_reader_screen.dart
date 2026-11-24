/// 跨端粘贴文章阅读与生词高亮页（Android + Web PWA 通用，零 `dart:io` 依赖）。
///
/// 功能闭环：粘贴任意印尼语新闻/课文 → 词库+词形还原分析 → 原文按「生词 / 学习中 / 已掌握」
/// 实时高亮并计算覆盖率 → 点词弹出 [showWordSheet] 速览或切到「生词清单」批量加入记忆。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:provider/provider.dart';

import '../ai_chat.dart' show AiChatContext, aiReadingContext;
import '../app_state.dart';
import '../models.dart';
import '../text_reader.dart';
import '../theme/k_colors.dart';
import '../version.dart' show kAiChat;
import '../widgets/ai_chat_sheet.dart' show showAiChat;
import '../widgets/ai_widgets.dart' show AiContextHub;
import '../widgets/quota_dialog.dart';
import '../widgets/word_search.dart' show SrsLevelMap, loadLevels, strengthOf;
import '../widgets/word_sheet.dart';
import '../widgets/word_tile.dart';
import 'select_screen.dart' show wordEnrolled;
import 'word_detail_screen.dart';

class TextReaderScreen extends StatefulWidget {
  final String? initialText;

  const TextReaderScreen({super.key, this.initialText});

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  final _ctl = TextEditingController();
  bool _analyzing = false;
  TextReaderResult? _result;
  SrsLevelMap _levels = const {};
  Set<String> _planned = const {};
  final Set<String> _sel = {};

  /// 0 = 原文高亮，1 = 生词清单
  int _viewTab = 0;

  /// 清单过滤：'unknown' = 仅生词，'all' = 全部命中
  String _listFilter = 'unknown';

  @override
  void initState() {
    super.initState();
    if (kAiChat) AiContextHub.push(this, _aiContext);
    final init = widget.initialText?.trim();
    if (init != null && init.isNotEmpty) {
      _ctl.text = init;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyze();
      });
    }
  }

  @override
  void dispose() {
    if (kAiChat) AiContextHub.pop(this);
    _ctl.dispose();
    super.dispose();
  }

  AiChatContext _aiContext() {
    final txt = _ctl.text.trim();
    final res = _result;
    final unknownWords = res == null
        ? const <String>[]
        : [
            for (final c in res.uniqueCards)
              if ((res.statusById[c.id] ?? ReaderWordStatus.unknown) ==
                  ReaderWordStatus.unknown)
                c.word,
          ];
    final coveragePct = res?.coveragePct.round();
    return aiReadingContext(
      text: txt.isEmpty ? '（尚未粘贴文章）' : txt,
      unknownWords: unknownWords,
      coveragePct: coveragePct,
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (txt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板里没有文本')),
      );
      return;
    }
    _ctl.text = txt;
    await _analyze();
  }

  Future<void> _analyze() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _analyzing) return;
    final db = context.read<AppState>().db;
    setState(() {
      _analyzing = true;
      _sel.clear();
    });
    try {
      final res = await analyzeReadingText(db, text);
      final ids = res.uniqueCards.map((c) => c.id).toList();
      final levels = await loadLevels(db, res.uniqueCards);
      final planned = await db.plannedIds(ids);
      if (!mounted) return;
      setState(() {
        _result = res;
        _levels = levels;
        _planned = planned;
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分析失败：$e')),
      );
    }
  }

  Future<void> _refreshStatus() async {
    final res = _result;
    if (res == null) return;
    final db = context.read<AppState>().db;
    final ids = res.uniqueCards.map((c) => c.id).toList();
    final levels = await loadLevels(db, res.uniqueCards);
    final planned = await db.plannedIds(ids);
    if (!mounted) return;
    final statusById = <String, ReaderWordStatus>{
      for (final id in ids) id: readerStatusOf(id, levels, planned),
    };
    var known = 0;
    var learning = 0;
    var unknown = 0;
    final paras = <List<ReaderToken>>[];
    for (final p in res.paragraphs) {
      final nextP = <ReaderToken>[];
      for (final tok in p) {
        if (tok.card == null) {
          nextP.add(tok);
        } else {
          final st = statusById[tok.card!.id] ?? ReaderWordStatus.unknown;
          switch (st) {
            case ReaderWordStatus.known:
              known++;
            case ReaderWordStatus.learning:
              learning++;
            case ReaderWordStatus.unknown:
              unknown++;
            case ReaderWordStatus.plain:
              break;
          }
          nextP.add(ReaderToken(tok.raw, card: tok.card, status: st));
        }
      }
      paras.add(nextP);
    }
    final sortedCards = [...res.uniqueCards]..sort((a, b) {
        final sa = statusById[a.id] ?? ReaderWordStatus.unknown;
        final sb = statusById[b.id] ?? ReaderWordStatus.unknown;
        final cmp = sa.index.compareTo(sb.index);
        return cmp != 0 ? cmp : (a.rank ?? 999999).compareTo(b.rank ?? 999999);
      });
    setState(() {
      _levels = levels;
      _planned = planned;
      _result = TextReaderResult(
        paragraphs: paras,
        uniqueCards: sortedCards,
        statusById: statusById,
        totalWords: res.totalWords,
        knownCount: known,
        learningCount: learning,
        unknownCount: unknown,
      );
    });
  }

  bool _enrolledOf(WordCard w) =>
      wordEnrolled(w.id, w.enabled, planned: _planned, levels: _levels);

  Future<void> _openWord(WordCard card) async {
    await showWordSheet(
      context,
      card.id,
      onOpenDetail: (id) async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: id)),
        );
      },
    );
    if (mounted) await _refreshStatus();
  }

  Future<void> _enrollSelected() async {
    if (_sel.isEmpty) return;
    final app = context.read<AppState>();
    final ids = _sel.toList();
    await app.remember(ids);
    _sel.clear();
    await _refreshStatus();
    if (!mounted) return;
    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    if (!mounted) return;
    if (plan.newPlan == 0 && plan.taskLeft == 0) {
      await showQuotaDialog(context, app);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将 ${ids.length} 个词加入记忆计划')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(
        title: const Text('文章生词高亮阅读'),
        actions: [
          if (kAiChat && _result != null)
            IconButton(
              tooltip: '问 AI 这篇文章',
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              onPressed: () => showAiChat(context, _aiContext()),
            ),
          if (_result != null)
            TextButton.icon(
              onPressed: _analyzing
                  ? null
                  : () => setState(() {
                        _result = null;
                        _sel.clear();
                      }),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('换一篇'),
            ),
        ],
      ),
      body: _analyzing
          ? const Center(child: CircularProgressIndicator())
          : _result == null
              ? _buildInputBody(k)
              : _buildReadingBody(k, _result!),
      bottomNavigationBar: _result != null && _viewTab == 1 && _sel.isNotEmpty
          ? SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: k.surface,
                  border: Border(top: BorderSide(color: k.border)),
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _enrollSelected,
                  child: Text('加入记忆（已选 ${_sel.length} 个）'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInputBody(KColors k) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: k.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: k.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_stories_rounded, color: k.brand, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '粘贴印尼语文章或新闻',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: k.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '自动对照你的 FSRS 记忆库标出生词，支持短语匹配、附着词（-ku/-mu/-nya）和被动形还原，点词即可查释义并加入记忆。',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: k.t2),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ctl,
                maxLines: 10,
                minLines: 6,
                style: TextStyle(fontSize: 14, height: 1.5, color: k.text),
                decoration: InputDecoration(
                  hintText: '在此粘贴印尼语段落…',
                  hintStyle: TextStyle(color: k.t3),
                  filled: true,
                  fillColor: k.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: k.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: k.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: k.tint,
                      foregroundColor: k.deep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, size: 17),
                    label: const Text('粘贴剪贴板'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: k.deep),
                    onPressed: () {
                      _ctl.text =
                          'Pemerintah Indonesia terus mendorong transformasi digital di berbagai daerah.\n'
                          'Banyak pelajar mulai belajar bahasa baru setiap hari agar lebih siap menghadapi tantangan kerja sama internasional.';
                    },
                    child: const Text('填入示例'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: k.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _analyze,
                  icon: const Icon(Icons.highlight_rounded, size: 18),
                  label: const Text(
                    '开始高亮阅读',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadingBody(KColors k, TextReaderResult res) {
    final pct = res.coveragePct.toStringAsFixed(0);
    final unknownCards = res.uniqueCards
        .where((c) => res.statusById[c.id] == ReaderWordStatus.unknown)
        .toList();
    final listCards =
        _listFilter == 'unknown' ? unknownCards : res.uniqueCards;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: k.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: k.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '词汇覆盖率 $pct%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: k.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '已掌握 ${res.knownCount} · 学习中 ${res.learningCount} · 生词 ${res.unknownCount}',
                    style: TextStyle(fontSize: 12, color: k.t2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: res.totalWords == 0 ? 0 : res.coveragePct / 100.0,
                  minHeight: 6,
                  backgroundColor: k.border,
                  valueColor: AlwaysStoppedAnimation(k.brand),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _LegendPill(
                    label: '生词',
                    bg: const Color(0x28E67E22),
                    fg: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFB35300),
                  ),
                  const SizedBox(width: 8),
                  _LegendPill(
                    label: '学习中',
                    bg: k.tint,
                    fg: k.deep,
                  ),
                  const Spacer(),
                  SegmentedButton<int>(
                    segments: [
                      const ButtonSegment(value: 0, label: Text('原文')),
                      ButtonSegment(
                          value: 1,
                          label: Text('清单(${unknownCards.length})')),
                    ],
                    selected: {_viewTab},
                    onSelectionChanged: (s) =>
                        setState(() => _viewTab = s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _viewTab == 0
              ? _buildParagraphList(k, res)
              : _buildCardList(k, listCards, unknownCards.length),
        ),
      ],
    );
  }

  Widget _buildParagraphList(KColors k, TextReaderResult res) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unknownBg =
        dark ? const Color(0x33F39C12) : const Color(0x28E67E22);
    final unknownFg =
        dark ? const Color(0xFFFFCC80) : const Color(0xFFA84300);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: res.paragraphs.length,
      itemBuilder: (_, idx) {
        final tokens = res.paragraphs[idx];
        if (tokens.isEmpty) return const SizedBox(height: 10);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 16, height: 1.75, color: k.text),
              children: [
                for (final tok in tokens)
                  if (tok.card == null || tok.status == ReaderWordStatus.known)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: tok.card == null
                          ? Text(
                              tok.raw,
                              style: TextStyle(
                                  fontSize: 16, height: 1.75, color: k.text),
                            )
                          : GestureDetector(
                              onTap: () => _openWord(tok.card!),
                              child: Text(
                                tok.raw,
                                style: TextStyle(
                                    fontSize: 16, height: 1.75, color: k.text),
                              ),
                            ),
                    )
                  else
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => _openWord(tok.card!),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: tok.status == ReaderWordStatus.unknown
                              ? BoxDecoration(
                                  color: unknownBg,
                                  borderRadius: BorderRadius.circular(5),
                                )
                              : BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: k.brand, width: 1.8),
                                  ),
                                ),
                          child: Text(
                            tok.raw,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              fontWeight:
                                  tok.status == ReaderWordStatus.unknown
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                              color: tok.status == ReaderWordStatus.unknown
                                  ? unknownFg
                                  : k.deep,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardList(
      KColors k, List<WordCard> cards, int unknownTotal) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              ChoiceChip(
                label: Text('仅生词 ($unknownTotal)'),
                selected: _listFilter == 'unknown',
                onSelected: (_) => setState(() => _listFilter = 'unknown'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text('全部命中 (${_result!.uniqueCards.length})'),
                selected: _listFilter == 'all',
                onSelected: (_) => setState(() => _listFilter = 'all'),
              ),
              const Spacer(),
              if (cards.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      final unEnrolled = cards
                          .where((c) => !_enrolledOf(c))
                          .map((c) => c.id)
                          .toList();
                      if (_sel.length == unEnrolled.length &&
                          unEnrolled.isNotEmpty) {
                        _sel.clear();
                      } else {
                        _sel
                          ..clear()
                          ..addAll(unEnrolled);
                      }
                    });
                  },
                  child: const Text('全选未加入'),
                ),
            ],
          ),
        ),
        Expanded(
          child: cards.isEmpty
              ? Center(
                  child: Text('这篇内容里没有生词，覆盖率很高！',
                      style: TextStyle(color: k.t2)),
                )
              : ListView.builder(
                  itemCount: cards.length,
                  itemBuilder: (_, i) {
                    final card = cards[i];
                    final enrolled = _enrolledOf(card);
                    return WordTile(
                      card: card,
                      selectMode: true,
                      selected: _sel.contains(card.id),
                      selectable: !enrolled,
                      member: enrolled,
                      enrolled: enrolled,
                      strength: strengthOf(_levels, card.id),
                      onTap: () {
                        if (!enrolled) {
                          setState(() {
                            if (!_sel.add(card.id)) _sel.remove(card.id);
                          });
                        } else {
                          _openWord(card);
                        }
                      },
                      onLongPress: () => _openWord(card),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LegendPill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _LegendPill({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
