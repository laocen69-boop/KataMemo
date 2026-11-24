library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../ai_chat.dart';
import '../ai_history.dart';
import '../ai_quiz.dart';
import '../ai_roleplay.dart';
import '../ai_tools.dart';
import '../ai_tts.dart';
import '../app_state.dart';
import '../models.dart';
import '../screens/ai_history_screen.dart';
import '../screens/ai_settings_screen.dart';
import '../screens/text_reader_screen.dart';
import '../theme/k_colors.dart';
import 'ai_markdown.dart';
import 'ai_quiz_card.dart';
import 'ai_roleplay_sheet.dart';
import 'ai_widgets.dart';
import 'copy_text.dart';

const String _kContinuePrompt = '继续完成剩下的步骤。';

Future<void> showAiChat(
  BuildContext context,
  AiChatContext ctx, {
  String? draft,
  VoidCallback? onCardChanged,
  int? convId,
}) =>
    aiOpenGuarded(() => presentAiChat(context, ctx,
        draft: draft, onCardChanged: onCardChanged, convId: convId));

bool _aiOpening = false;

bool get aiChatOpening => _aiOpening;

Future<void> aiOpenGuarded(Future<void> Function() body) async {
  if (_aiOpening) return;
  _aiOpening = true;
  AiContextHub.sheetsOpen.value++;
  try {
    await body();
  } finally {
    AiContextHub.sheetsOpen.value--;
    _aiOpening = false;
  }
}

Future<void> presentAiChat(
  BuildContext context,
  AiChatContext ctx, {
  String? draft,
  VoidCallback? onCardChanged,
  int? convId,
}) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: AiChatSheet(
            context: ctx,
            draft: draft,
            onCardChanged: onCardChanged,
            convId: convId),
      ),
    ),
  );
}

Future<AiChatContext> aiContextForConv(AppState app, AiConvSummary c,
    {String system = ''}) async {
  if (c.key.startsWith('word:')) {
    final card = await app.db.getWord(c.key.substring(5));
    if (card != null) return aiWordContext(card);
  }
  if (c.key == 'general') return aiGeneralContext();
  var sys = system;
  if (sys.isEmpty) {
    final full = await app.db.aiChatGet(c.id);
    sys = full?.system ?? '';
  }
  return AiChatContext(
    key: c.key,
    title: c.title,
    subtitle: c.subtitle,
    system: sys,
    quick: c.key.startsWith('grammar:') ? kAiGrammarQuick : const [],
  );
}

Future<void> showAiChatSheet(BuildContext context, WordCard card,
        {VoidCallback? onCardChanged}) =>
    showAiChat(context, aiWordContext(card), onCardChanged: onCardChanged);

typedef AiDebugTurn = Stream<String> Function(
    List<AiMessage> history, void Function(List<AiToolCall>) onCalls);

class AiChatSheet extends StatefulWidget {
  final AiChatContext context;
  final String? draft;
  final VoidCallback? onCardChanged;
  final AiDebugTurn? debugTurn;

  final int? convId;

  const AiChatSheet({
    super.key,
    required this.context,
    this.draft,
    this.onCardChanged,
    this.debugTurn,
    this.convId,
  });

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  late final List<AiMessage> _msgs;

  String? _digest;
  int? _foldEnd;
  int _foldUser = -1;

  String? _sessionDigest;
  int? _sessionFoldEnd;
  bool _compacting = false;
  bool _nudgeDismissed = false;
  int _lastMemSyncLen = 0;

  List<AiPlanStep> _plan = const [];
  int _planBaseDone = -1;

  bool _capped = false;

  int _round = 0;

  final Map<String, (String, int)> _seen = {};

  final Map<String, int> _toolFailStreak = {};
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _partial = '';
  bool _busy = false;
  bool _thinking = false;
  bool _stop = false;
  AiException? _error;

  bool _toolsOff = false;

  (AiPendingAction, Completer<bool>)? _pending;

  final List<AiNavAction> _navQueue = [];
  final Map<AiMessage, AiNavAction> _offers = {};

  String? _imgB64;
  Uint8List? _imgBytes;
  final Map<AiMessage, Uint8List> _imgCache = {};

  late AiChatContext _ctxNow = widget.context;
  AiChatContext get _ctx => _ctxNow;
  bool get _debug => widget.debugTurn != null;

  late final AppState _app;

  int? _convId;

  Future<void> _saving = Future<void>.value();

  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _paintEvery = Duration(milliseconds: 90);

  final Map<AiMessage, Widget> _bubbleCache = {};
  Object? _bubbleSig;
  final AiTtsPlayer _tts = AiTtsPlayer();
  List<String> _roleplayTargets = const [];

  void _onTtsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickRoleplay() async {
    final curId = _ctx.key.startsWith('roleplay:') ? _ctx.key.substring(9) : null;
    final sel = await showAiRoleplaySheet(context, _app, currentScenarioId: curId);
    if (sel == null || !mounted) return;
    AiSessionCache.put(_ctx.key, _msgs);
    unawaited(_persist());
    final nextCtx = aiRoleplayContext(sel.scenario, targetWords: sel.targetWords);
    final cached = AiSessionCache.get(nextCtx.key);
    if (cached.isEmpty) {
      cached.add(AiMessage(
        'assistant',
        '**${sel.scenario.openerId}**\n（${sel.scenario.openerZh}）',
      ));
    }
    setState(() {
      _ctxNow = nextCtx;
      _roleplayTargets = sel.targetWords;
      _msgs = cached;
      _convId = AiSessionCache.idOf(nextCtx.key);
      _offers.clear();
      _bubbleCache.clear();
      _plan = const [];
      _error = null;
      _capped = false;
    });
    AiSessionCache.put(_ctx.key, _msgs);
    unawaited(_persist());
    _toBottom();
  }

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _tts.addListener(_onTtsChanged);
    _msgs = AiSessionCache.get(_ctx.key);
    _convId = AiSessionCache.idOf(_ctx.key);
    _toolsOff = !_app.aiTools;
    if (widget.draft != null) _input.text = widget.draft!;
    if (_msgs.isNotEmpty) _toBottom();
    if (widget.convId != null) {
      unawaited(_loadConv(widget.convId!));
    } else if (_msgs.isEmpty) {
      unawaited(_restoreLatest());
    }
  }

  Future<void> _restoreLatest() async {
    if (!_app.db.isOpen) return;
    try {
      final c = await _app.db.aiChatLatestForKey(_ctx.key);
      if (c == null || !mounted || _msgs.isNotEmpty || _busy) return;
      setState(() {
        _msgs.addAll(c.msgs);
        _convId = c.head.id;
      });
      AiSessionCache.setId(_ctx.key, _convId);
      _toBottom();
    } catch (_) {}
  }

  Future<void> _loadConv(int id) async {
    try {
      final c = await _app.db.aiChatGet(id);
      if (c == null || !mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(c.msgs);
        _offers.clear();
        _bubbleCache.clear();
        _convId = c.head.id;
        _error = null;
      });
      AiSessionCache.put(_ctx.key, _msgs);
      AiSessionCache.setId(_ctx.key, _convId);
      _toBottom();
    } catch (_) {}
  }

  Future<void> _persist() {
    final ctx = _ctx;
    final snapshot = List<AiMessage>.of(_msgs);
    _saving = _saving.then((_) async {
      if (!_app.db.isOpen) return;
      try {
        final id = await _app.db.aiChatSave(
          id: _convId,
          key: ctx.key,
          title: ctx.title,
          subtitle: ctx.subtitle,
          system: ctx.system,
          msgs: snapshot,
        );
        _convId = id;
        AiSessionCache.setId(ctx.key, id);
      } catch (_) {

      }
    });
    return _saving;
  }

  @override
  void dispose() {
    _stop = true;
    _tts.removeListener(_onTtsChanged);
    _tts.dispose();
    _pending?.$2.complete(false);
    AiSessionCache.put(_ctx.key, _msgs);
    unawaited(_persist());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
      }
    });
  }

  Future<bool> _confirmPrivacy(AppState app) async {
    if (app.aiNoticeSeen || _debug) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('发送前说明'),
        content: Text(
          '你的提问，以及当前话题的资料（单词释义、例句或语法页内容），'
          '会发送给「${app.aiProvider.name}」生成回答，并按该服务商的规则计费和处理。\n\n'
          'AI 还能帮你查学习记录、整理词单、打开页面；凡是会改动数据的操作，都会先在对话里请你确认。\n\n'
          '${app.aiSearchReady ? '已启用按需联网搜索（${app.aiSearchProvider!.name}）：词库和知识库里没有答案时，AI 会把必要搜索词发给该服务商查网页作参考，并按其规则计费（可在设置中随时关闭）。\n\n' : ''}'
          'AI 的回答可能出错，学习时请以词典为准。对话保存在本机，可以在「对话历史」里查看和删除。',
          style: const TextStyle(height: 1.55),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('知道了，发送')),
        ],
      ),
    );
    if (ok == true) await app.markAiNoticeSeen();
    return ok == true;
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if ((t.isEmpty && _imgB64 == null) || _busy) return;
    final app = context.read<AppState>();
    if (!await _confirmPrivacy(app)) return;
    if (!mounted) return;
    final m = AiMessage('user', t, imageB64: _imgB64);
    setState(() {
      if (_imgBytes != null) _imgCache[m] = _imgBytes!;
      _msgs.add(m);
      _input.clear();
      _imgB64 = null;
      _imgBytes = null;
    });
    await _ask();
  }

  Future<bool> _confirm(AiPendingAction a) {
    final c = Completer<bool>();
    setState(() => _pending = (a, c));
    _toBottom();
    return c.future;
  }

  void _resolvePending(bool ok) {
    final p = _pending;
    if (p == null) return;
    setState(() => _pending = null);
    p.$2.complete(ok);
  }

  String _systemFor({bool tools = true, String extra = ''}) {
    final b = StringBuffer('${_ctx.system}\n\n${aiLevelRule(_app.aiLevel)}');
    if (tools && !_toolsOff) {
      b.write('\n\n$kAiAgentRules');
      if (_app.aiSearchReady) b.write('\n\n$kAiSearchRules');
    }
    final mem = _app.aiMemoryEnabled ? _app.aiLearningMemory.trim() : '';
    if (mem.isNotEmpty) {
      b.write('\n\n【学生长期学习记忆】\n$mem');
    }
    if (extra.isNotEmpty) b.write('\n\n$extra');
    if (_plan.isNotEmpty) b.write('\n\n【任务清单】\n${aiPlanText(_plan)}');
    if (_digest != null) b.write('\n\n【任务进展（自动压缩）】\n$_digest');
    final n = DateTime.now();
    b.write('\n今天是 ${n.year}-${n.month.toString().padLeft(2, '0')}'
        '-${n.day.toString().padLeft(2, '0')}。');
    return b.toString();
  }

  List<AiMessage> get _source {
    final lastUser = _msgs.lastIndexWhere((m) => m.role == 'user');
    final sfe = _sessionFoldEnd;
    final sd = _sessionDigest;
    final fe = _foldEnd;
    final hasTurnFold = fe != null && lastUser >= 0 && fe > lastUser && fe <= _msgs.length;
    if (sd != null && sfe != null && sfe > 0 && sfe <= _msgs.length) {
      final tail = hasTurnFold && sfe <= lastUser
          ? [..._msgs.sublist(sfe, lastUser + 1), ..._msgs.sublist(fe)]
          : _msgs.sublist(sfe);
      return [
        AiMessage('user', '【前情摘要（同会话已压缩）】\n$sd'),
        const AiMessage('assistant', '明白，我会接着上面的进度继续。'),
        ...tail,
      ];
    }
    if (!hasTurnFold) return _msgs;
    return [..._msgs.sublist(0, lastUser + 1), ..._msgs.sublist(fe)];
  }

  int _msgBudget(AiBudget b, String system, List<AiToolSpec> tools) {
    final n = b.input - aiEstimateTokens(system) - aiToolSpecsTokens(tools) - 200;
    return n < 2500 ? 2500 : n;
  }

  void _newTurn() {
    final lastUser = _msgs.lastIndexWhere((m) => m.role == 'user');
    if (lastUser == _foldUser) return;
    _foldUser = lastUser;
    _foldEnd = null;
    _seen.clear();
    _toolFailStreak.clear();
    if (!_capped) {
      _digest = null;
      _plan = const [];
    }
  }

  Future<void> _maybeCompact(AiConfig cfg, AiBudget budget, int msgBudget) async {
    if (_debug) return;
    final lastUser = _msgs.lastIndexWhere((m) => m.role == 'user');
    if (lastUser < 0) return;
    final r = aiCompactRangeTokens(_msgs, budget: msgBudget, from: _foldEnd);
    if (r == null) return;
    final input = [
      _msgs[lastUser],
      if (_digest != null) AiMessage('assistant', '（之前的进展）\n$_digest'),
      ..._msgs.sublist(r.start, r.end),
    ];
    final sw = Stopwatch()..start();
    final buf = StringBuffer();
    try {
      await for (final piece in aiChatStream(
          config: cfg,
          system: kAiCompactSystem,
          history: input,
          budget: msgBudget.clamp(2000, (budget.input * 0.8).round()),
          toolChars: 1500)) {
        buf.write(piece);
      }
    } on AiException catch (e) {
      AiDiag.log('  压缩失败：${e.message}');
      return;
    }
    final text = buf.toString().trim();
    if (text.isEmpty || !mounted) return;
    setState(() {
      _digest = aiClip(text, 1500);
      _foldEnd = r.end;
    });
    AiDiag.log('  压缩：折叠 ${r.end - r.start} 条 → 进展 ${text.length} 字 · '
        '${sw.elapsedMilliseconds}ms');
  }

  Future<void> _autoUpdateMemory(List<AiMessage> snapshot) async {
    final app = _app;
    final cfg = app.aiConfig;
    if (!app.aiMemoryEnabled || _debug || !cfg.ready) return;
    if (snapshot.length == _lastMemSyncLen) return;
    final userTurns = snapshot.where((m) => m.role == 'user').length;
    if (userTurns < 2) return;
    _lastMemSyncLen = snapshot.length;
    final recent = snapshot.where((m) => m.role == 'user' || (m.role == 'assistant' && m.content.trim().isNotEmpty)).toList();
    if (recent.length < 2) return;
    final tail = recent.length > 12 ? recent.sublist(recent.length - 12) : recent;
    final existing = app.aiLearningMemory.trim();
    final prompt = <AiMessage>[
      if (existing.isNotEmpty) AiMessage('user', '【已有记忆】\n$existing'),
      ...tail,
    ];
    try {
      final buf = StringBuffer();
      await for (final piece in aiChatStream(
          config: cfg,
          system: kAiMemoryExtractSystem,
          history: prompt,
          budget: 8000,
          toolChars: 600,
          trim: false)) {
        buf.write(piece);
      }
      final out = buf.toString().trim();
      if (out.isEmpty || out.toUpperCase() == 'NONE') return;
      await app.setAiLearningMemory(out);
      AiDiag.log('  自动更新跨会话记忆：${out.length} 字');
    } catch (_) {}
  }

  Future<bool> _maybeCompactSession(AiConfig cfg, AiBudget budget, {bool manual = false}) async {
    if (_debug || _compacting) return false;
    final maxTok = _app.aiCtxTier == AiCtxTier.economy ? 12000 : 24000;
    final r = aiSessionCompactRange(_msgs,
        budget: budget.input,
        from: _sessionFoldEnd ?? 0,
        keepRecentTurns: 2,
        maxTokens: maxTok,
        force: manual);
    if (r == null) return false;
    setState(() => _compacting = true);
    final input = <AiMessage>[
      if (_sessionDigest != null) AiMessage('user', '【前情摘要】\n$_sessionDigest'),
      ..._msgs.sublist(r.start, r.end),
    ];
    final sw = Stopwatch()..start();
    final buf = StringBuffer();
    try {
      await for (final piece in aiChatStream(
          config: cfg,
          system: kAiSessionCompactSystem,
          history: input,
          budget: (budget.input * 0.8).round(),
          toolChars: 1200,
          trim: false)) {
        buf.write(piece);
      }
    } on AiException catch (e) {
      AiDiag.log('  同会话压缩失败：${e.message}');
      if (mounted) setState(() => _compacting = false);
      return false;
    }
    final text = buf.toString().trim();
    if (!mounted) return false;
    if (text.isEmpty) {
      setState(() => _compacting = false);
      return false;
    }
    setState(() {
      _sessionDigest = aiClip(text, 1200);
      _sessionFoldEnd = r.end;
      _compacting = false;
      _nudgeDismissed = true;
    });
    AiDiag.log('  同会话压缩：折叠 ${r.turns} 轮 → ${text.length} 字 · ${sw.elapsedMilliseconds}ms');
    return true;
  }

  Future<String> _stream(Stream<String> s, {String prefix = ''}) async {
    _partial = prefix;
    await for (final piece in s) {
      if (_stop || !mounted) break;
      _partial += piece;
      final now = DateTime.now();
      if (now.difference(_lastPaint) >= _paintEvery) {
        _lastPaint = now;
        setState(() {});
        _toBottom();
      }
    }
    if (mounted) setState(() {});
    return _partial;
  }

  Future<String> _continueTruncated(
      AiConfig cfg, String system, List<AiMessage> sent, String text) async {
    var full = text;
    for (var k = 0; k < 2 && !_stop && mounted; k++) {
      AiStreamInfo? info;
      AiDiag.log('  回答被截断，自动接着写（第 ${k + 1} 次）');
      try {
        full = await _stream(
            aiChatStream(
                config: cfg,
                system: system,
                history: [
                  ...sent,
                  AiMessage('assistant', full),
                  const AiMessage('user', kAiContinueAsk),
                ],
                trim: false,
                maxOutput: context.read<AppState>().aiMaxOutput,
                onDone: (i) => info = i),
            prefix: full);
      } on AiException catch (e) {
        AiDiag.log('  接着写失败：${e.message}');
        break;
      }
      if (info?.truncated != true) break;
    }
    _partial = '';
    return full.trim();
  }

  Future<bool> _runTools(List<AiToolCall> calls, AiToolbox toolbox) async {
    final outs = List<AiToolOutcome?>.filled(calls.length, null);
    final repeated = List<bool>.filled(calls.length, false);
    final reads = <Future<void>>[];
    for (var i = 0; i < calls.length; i++) {
      final c = calls[i];
      if (aiToolKind(c.name) != AiToolKind.read) continue;
      final key = '${c.name}|${_canon(c.argMap)}';
      final seen = _seen[key];
      if (seen != null && c.name != 'task_plan') {
        _seen[key] = (seen.$1, seen.$2 + 1);
        outs[i] = _repeatOutcome(c, seen.$1, seen.$2 + 1);
        repeated[i] = true;
        AiDiag.log('  工具 ${c.name} 重复第 ${seen.$2 + 1} 次，未执行');
        continue;
      }
      final sw = Stopwatch()..start();
      reads.add(toolbox.run(c, confirm: _confirm).then((o) {
        outs[i] = o;
        if (c.name != 'task_plan') _seen[key] = (o.result, 1);
        AiDiag.log('  工具 ${c.name} ${aiClip(c.args, 60)} → ${o.result.length} 字 · '
            '${sw.elapsedMilliseconds}ms');
      }));
    }
    await Future.wait(reads);
    for (var i = 0; i < calls.length; i++) {
      if (outs[i] != null || _stop || !mounted) continue;
      final c = calls[i];
      outs[i] = await toolbox.run(c, confirm: _confirm);
      AiDiag.log('  工具 ${c.name} → ${outs[i]!.label}');
    }
    if (!mounted) return false;
    var progressed = false;
    setState(() {
      for (var i = 0; i < calls.length; i++) {
        final c = calls[i];
        final o = outs[i] ??
            AiToolOutcome(jsonEncode({'error': '学生中止了这一步'}), '${c.name}：已中止');
        var resultText = o.result;
        var emptyOrErr = o.result.startsWith('{"error":');
        var streak = 0;
        if (!repeated[i] && c.name != 'task_plan') {
          emptyOrErr = _isEmptyOrErrorToolResult(resultText);
          if (emptyOrErr) {
            streak = (_toolFailStreak[c.name] ?? 0) + 1;
            _toolFailStreak[c.name] = streak;
            if (streak >= 2) {
              resultText = _injectDoomLoopHint(resultText, c.name, streak);
              AiDiag.log('  工具 ${c.name} 连续 $streak 次无有效结果，已注入纠偏提示');
            }
          } else {
            _toolFailStreak.remove(c.name);
          }
        }

        if (!repeated[i] && !o.result.startsWith('{"error":') && streak < 3) {
          progressed = true;
        }
        final m = AiMessage('tool', resultText,
            toolCallId: c.id, toolName: c.name, label: o.label);
        _msgs.add(m);
        if (o.plan != null) {
          _plan = o.plan!;
          if (_planBaseDone < 0) {
            _planBaseDone = _plan.where((s) => s.done).length;
          }
        }
        if (o.nav != null) {
          if (aiToolKind(c.name) == AiToolKind.nav) {
            _navQueue.add(o.nav!);
          } else {
            _offers[m] = o.nav!;
          }
        }
      }
    });
    _toBottom();
    return progressed;
  }

  static bool _isEmptyOrErrorToolResult(String raw) {
    if (raw.startsWith('{"error":')) return true;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return false;
      if (j.containsKey('error')) return true;
      for (final k in const ['hits', 'pages', 'results', 'items', 'matches']) {
        final v = j[k];
        if (v is List && v.isEmpty) return true;
      }
      if (j['count'] == 0) return true;
    } catch (_) {}
    return false;
  }

  static String _injectDoomLoopHint(String raw, String toolName, int streak) {
    final hint = '你已连续 $streak 次调用 $toolName 未拿到有效结果，请停止用同一思路反复检索，'
        '改用其他工具或直接基于已有信息向学生作答。';
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        return jsonEncode({...j, 'doom_loop_hint': hint});
      }
    } catch (_) {}
    return '$raw\n[系统提示：$hint]';
  }

  static String _canon(Map<String, dynamic> a) =>
      jsonEncode(Map.fromEntries(a.entries.toList()..sort((x, y) => x.key.compareTo(y.key))));

  AiToolOutcome _repeatOutcome(AiToolCall c, String prev, int n) {
    Object? r;
    try {
      r = jsonDecode(prev);
    } catch (_) {
      r = prev;
    }
    return AiToolOutcome(
        jsonEncode(n >= 3
            ? {
                'repeat': n,
                'note': '同样的调用已经做了 $n 次，结果不会变。不要再调用它，'
                    '直接用已有结果继续，或向学生说明卡在哪里。',
              }
            : {'repeat': n, 'note': '这个调用本轮已经做过，结果同上；请直接使用，不要重复调用。', 'result': r}),
        '重复调用 ${c.name}（已省略）');
  }

  Future<bool> _summarize(AiConfig cfg, AiBudget budget) async {
    final system = _systemFor(tools: false, extra: kAiSummaryRules);
    final packed = aiPackHistory(_source,
        budget: _msgBudget(budget, system, const []), toolChars: 2500);
    var text = '';
    try {
      text = (await _stream(_debug
              ? widget.debugTurn!(packed.msgs, (_) {})
              : aiChatStream(
                  config: cfg,
                  system: system,
                  history: packed.msgs,
                  trim: false,
                  maxOutput: context.read<AppState>().aiMaxOutput)))
          .trim();
    } on AiException catch (e) {
      AiDiag.log('  收尾失败：${e.message}');
    }
    _partial = '';
    if (!mounted) return false;
    setState(() {
      _msgs.add(AiMessage(
          'assistant',
          text.isNotEmpty
              ? text
              : '（这一轮的步数用完了，先停在这里。点输入框上方的「继续完成」我接着做。）'));
      _capped = true;
    });
    AiDiag.log('步数用完（${budget.rounds}），收尾总结 ${text.length} 字');
    return text.isNotEmpty;
  }

  Future<void> _ask() async {
    final app = context.read<AppState>();
    final cfg = app.aiConfig;
    final toolbox = AiToolbox(app);
    var budget = app.aiBudgetForTurn(forTools: _plan.isNotEmpty);
    final started = DateTime.now();
    _newTurn();
    setState(() {
      _busy = true;
      _thinking = false;
      _partial = '';
      _error = null;
      _stop = false;
      _capped = false;
      _round = 0;
    });
    _navQueue.clear();
    _toBottom();
    AiDiag.log('—— 新一轮 ${cfg.provider.id}/${cfg.model} · ${aiCtxLabel(budget.tier)} · '
        '预算 ${aiTokensShort(budget.input)}（窗口 ${aiTokensShort(budget.window.tokens)}，'
        '${budget.window.source}）· 最多 ${budget.rounds} 步');
    var answered = false;
    try {
      await _maybeCompactSession(cfg, budget);
      if (!mounted || _stop) return;
      var hitCap = false;
      var maxRounds = budget.rounds;
      var extendsUsed = 0;
      var stallRounds = 0;
      var turnInputTokens = 0;
      int? overflowCapTokens;
      var transientRetries = 0;
      var overflowRecovered = false;
      var dropCustomMaxOutput = false;
      var nativeSearchOff = false;
      _planBaseDone = _plan.isEmpty ? -1 : _plan.where((s) => s.done).length;
      while (_round < maxRounds && !_stop) {
        setState(() => _round++);
        final useTools = !_toolsOff;
        final specs = useTools
            ? aiToolSpecsFor(app, contextKey: _ctx.key)
            : const <AiToolSpec>[];
        var system = _systemFor();
        var msgBudget = _msgBudget(budget, system, specs);
        if (overflowCapTokens != null && overflowCapTokens < msgBudget) {
          msgBudget = overflowCapTokens;
        }
        await _maybeCompact(cfg, budget, msgBudget);
        if (!mounted || _stop) break;
        system = _systemFor();
        msgBudget = _msgBudget(budget, system, specs);
        if (overflowCapTokens != null && overflowCapTokens < msgBudget) {
          msgBudget = overflowCapTokens;
        }
        final packed =
            aiPackHistory(_source, budget: msgBudget, toolChars: budget.toolChars);
        final fixed = aiEstimateTokens(system) + aiToolSpecsTokens(specs);
        AiDiag.log('第 $_round 步 · 发 ${packed.msgs.length} 条 · 约 '
            '${aiTokensShort(packed.tokens + fixed)} / ${aiTokensShort(budget.input)}'
            '${packed.shrunk > 0 ? ' · 缩短工具结果 ${packed.shrunk} 条' : ''}'
            '${packed.droppedTurns > 0 ? ' · 没带旧对话 ${packed.droppedTurns} 轮' : ''}'
            '${packed.over ? ' · ⚠ 本轮仍超预算' : ''}');
        var calls = <AiToolCall>[];
        AiStreamInfo? info;
        final sw = Stopwatch()..start();
        final effMaxOutput =
            dropCustomMaxOutput ? aiMaxOutputFor(cfg) : app.aiMaxOutput;
        final enableNativeSearch = !nativeSearchOff &&
            aiShouldEnableNativeSearch(
              cfg,
              searchExplicitlyOff: app.aiSearchExplicitlyOff,
            );
        final stream = _debug
            ? widget.debugTurn!(packed.msgs, (c) => calls = c)
            : aiChatStream(
                config: cfg,
                system: system,
                history: packed.msgs,
                tools: specs,
                trim: false,
                maxOutput: effMaxOutput,
                enableSearch: enableNativeSearch,
                onToolCalls: (c) => calls = c,
                onDone: (i) => info = i,
                onThinking: () {
                  if (mounted) setState(() => _thinking = true);
                },
              );
        var text = '';
        try {
          text = (await _stream(stream)).trim();
          transientRetries = 0;
        } on AiException catch (e) {
          if (_partial.isEmpty &&
              !dropCustomMaxOutput &&
              app.aiCustomMaxOutput != null &&
              (aiIsMaxTokensError(e) || aiIsContextOverflow(e))) {
            dropCustomMaxOutput = true;
            setState(() => _round--);
            AiDiag.log('  自定义 max_tokens 触发越界，回退为跟随模型默认重试');
            continue;
          }
          if (_partial.isEmpty && aiIsContextOverflow(e) && !overflowRecovered) {
            overflowRecovered = true;
            overflowCapTokens =
                (packed.tokens * 0.55).round().clamp(1500, msgBudget);
            setState(() => _round--);
            AiDiag.log('  上下文超限，按实际发送量缩减至 $overflowCapTokens token 并压缩重试');
            continue;
          }
          if (!_debug &&
              _partial.isEmpty &&
              aiIsTransientError(e) &&
              transientRetries < 2) {
            transientRetries++;
            final waitMs = 1200 * transientRetries;
            AiDiag.log('  瞬时错误（${e.statusCode ?? '网络'}），${waitMs}ms 后第 $transientRetries 次自动重试…');
            await _waitRetry(waitMs);
            if (!mounted || _stop) break;
            setState(() => _round--);
            continue;
          }

          if (enableNativeSearch &&
              e.statusCode == 400 &&
              _partial.isEmpty &&
              !aiIsContextOverflow(e) &&
              !aiIsMaxTokensError(e)) {
            nativeSearchOff = true;
            setState(() => _round--);
            AiDiag.log('  原生联网参数被 400 拒，去掉 enable_search 重试');
            continue;
          }

          if (useTools &&
              e.statusCode == 400 &&
              _partial.isEmpty &&
              !aiIsContextOverflow(e) &&
              !aiIsMaxTokensError(e)) {
            _toolsOff = true;
            setState(() => _round--);
            AiDiag.log('  带工具被 400 拒：本窗口改成纯聊天');
            continue;
          }
          rethrow;
        }
        if (!mounted) return;
        _partial = '';
        final i = info;
        AiDiag.log('  回复 ${sw.elapsedMilliseconds}ms · ${text.length} 字'
            '${calls.isEmpty ? '' : ' · 调 ${calls.map((c) => c.name).join('、')}'}'
            '${i?.finish == null ? '' : ' · ${i!.finish}'}'
            '${i == null || i.inputTokens == 0 ? '' : ' · 用量 入${i.inputTokens}'
                '（缓存${i.cachedTokens}）出${i.outputTokens}'}');
        if (_stop || calls.isEmpty) {
          if (!_stop && i?.truncated == true) {
            text = await _continueTruncated(cfg, system, packed.msgs, text);
          }
          if (text.isNotEmpty) {
            _msgs.add(AiMessage('assistant', text));
            answered = true;
          }
          break;
        }

        budget = app.aiBudgetForTurn(forTools: true);
        if (budget.rounds > maxRounds) maxRounds = budget.rounds;
        setState(() => _msgs.add(AiMessage('assistant', text, toolCalls: calls)));
        if (text.isNotEmpty) answered = true;
        final progressed = await _runTools(calls, toolbox);
        if (!mounted) return;
        final stepIn = i == null || i.inputTokens == 0
            ? packed.tokens + fixed
            : i.inputTokens;
        turnInputTokens += stepIn;
        stallRounds = progressed ? 0 : stallRounds + 1;
        if (stallRounds >= kAiStallRounds) {
          AiDiag.log('连续 $stallRounds 步无新进展，提前收尾');
          hitCap = true;
          break;
        }
        if (turnInputTokens >= budget.input * kAiTurnSpendMul) {
          AiDiag.log('本轮累计输入 $turnInputTokens 超过花销上限，暂停收尾');
          hitCap = true;
          break;
        }
        if (_round >= maxRounds) {
          final doneNow = _plan.where((s) => s.done).length;
          if (_plan.any((s) => !s.done) &&
              extendsUsed < kAiAutoExtends &&
              _planBaseDone >= 0 &&
              doneNow > _planBaseDone) {
            extendsUsed++;
            _planBaseDone = doneNow;
            maxRounds += budget.rounds;
            AiDiag.log('任务清单有进展（$doneNow/${_plan.length}），自动续跑第 $extendsUsed 次（上限 $maxRounds 步）');
          } else {
            hitCap = true;
          }
        }
      }
      if (hitCap && !_stop && mounted) {
        if (await _summarize(cfg, budget)) answered = true;
      }
      if (answered && !_debug && app.aiStatusFor(cfg.provider.id).state != AiLinkState.ok) {
        unawaited(app.setAiStatus(
            cfg.provider.id,
            AiStatus(AiLinkState.ok,
                at: DateTime.now().millisecondsSinceEpoch,
                model: cfg.model,
                latencyMs: DateTime.now().difference(started).inMilliseconds)));
      }
    } on AiException catch (e) {
      if (!mounted) return;
      AiDiag.log('  出错：${e.message}');
      _error = e;
      if (_partial.trim().isNotEmpty) {
        _msgs.add(AiMessage('assistant', _partial.trim()));
      } else if (_msgs.isNotEmpty && _msgs.last.role == 'user') {

        final last = _msgs.removeLast();
        _input.text = last.content;
        if (last.imageB64 != null) {
          _imgB64 = last.imageB64;
          _imgBytes = _imgCache[last];
        }
      }
      if (e.linkProblem && !_debug) {
        unawaited(app.setAiStatus(
            cfg.provider.id,
            AiStatus(AiLinkState.fail,
                at: DateTime.now().millisecondsSinceEpoch,
                message: e.message,
                model: cfg.model)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _partial = '';
          _busy = false;
          _thinking = false;
        });
        AiSessionCache.put(_ctx.key, _msgs);
        unawaited(_persist());
      }
    }
    if (mounted && _navQueue.isNotEmpty) _runNav(List.of(_navQueue));
  }

  void _runNav(List<AiNavAction> navs) {
    _navQueue.clear();
    final nav = navs.last;
    final root = kRootNavKey.currentContext;
    if (nav.closeSheet) {
      Navigator.maybePop(context);
      if (root != null) nav.go(root);
    } else {
      nav.go(context);
    }
  }

  Future<void> _waitRetry(int totalMs) async {
    var left = totalMs;
    while (left > 0 && mounted && !_stop) {
      final step = left > 200 ? 200 : left;
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
  }

  void _stopNow() {
    _stop = true;
    _resolvePending(false);
    setState(() {});
  }

  void _retry() {
    final t = _input.text.trim();
    if (t.isNotEmpty || _imgB64 != null) {
      _send(t);
    } else {
      _regenerate();
    }
  }

  void _regenerate() {
    if (_busy) return;
    final lastUser = _msgs.lastIndexWhere((m) => m.role == 'user');
    if (lastUser < 0 || lastUser == _msgs.length - 1) return;
    setState(() {
      _msgs.removeRange(lastUser + 1, _msgs.length);

      _foldUser = -1;
      _capped = false;
    });
    _ask();
  }

  void _resetTask() {
    _digest = null;
    _foldEnd = null;
    _sessionDigest = null;
    _sessionFoldEnd = null;
    _compacting = false;
    _nudgeDismissed = false;
    _lastMemSyncLen = 0;
    _foldUser = -1;
    _plan = const [];
    _capped = false;
    _seen.clear();
  }

  Future<void> _newConversation() async {
    _stop = true;
    final snap = List<AiMessage>.of(_msgs);
    unawaited(_autoUpdateMemory(snap));
    await _persist();
    setState(() {
      _msgs.clear();
      _offers.clear();
      _bubbleCache.clear();
      _partial = '';
      _busy = false;
      _error = null;
      _convId = null;
      _resetTask();
    });
    AiSessionCache.put(_ctx.key, _msgs);
    AiSessionCache.setId(_ctx.key, null);
  }

  Future<void> _openHistory() async {
    if (_busy) return;
    await _persist();
    if (!mounted) return;
    final pick = await pickAiConversation(context, currentId: _convId);
    if (pick == null || !mounted || pick.id == _convId) return;
    final full = await _app.db.aiChatGet(pick.id);
    if (full == null || !mounted) return;
    final ctx = await aiContextForConv(_app, pick, system: full.system);
    if (!mounted) return;
    unawaited(_autoUpdateMemory(List<AiMessage>.of(_msgs)));
    AiSessionCache.put(_ctx.key, _msgs);
    setState(() {
      _ctxNow = ctx;
      _msgs
        ..clear()
        ..addAll(full.msgs);
      _offers.clear();
      _bubbleCache.clear();
      _convId = pick.id;
      _partial = '';
      _error = null;
      _resetTask();
    });
    AiSessionCache.put(ctx.key, _msgs);
    AiSessionCache.setId(ctx.key, pick.id);
    _toBottom();
  }

  Future<void> _pickImage() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              subtitle: const Text('课本、路牌、菜单、作业……'),
              onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选'),
              onTap: () => Navigator.pop(c, ImageSource.gallery)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('能否识图取决于你选的模型；不支持时会显示服务商的报错。',
                style: TextStyle(fontSize: 12, color: context.k.t3)),
          ),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imgBytes = bytes;
        _imgB64 = base64Encode(bytes);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('打不开${src == ImageSource.camera ? '相机' : '相册'}：$e')));
    }
  }

  Future<void> _saveAsMnemonic(String text) async {
    final card = _ctx.card;
    if (card == null) return;
    final app = context.read<AppState>();
    final fresh = await app.db.getWord(card.id) ?? card;
    final old = fresh.hasOwnMnemonic ? fresh.mnemonic!.trim() : '';
    final ctl = TextEditingController(
        text: old.isEmpty ? text.trim() : '$old\n${text.trim()}');
    if (!mounted) return;
    final out = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('存为「${card.word}」的助记'),
        content: TextField(
          controller: ctl,
          maxLines: 8,
          minLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            filled: true,
            fillColor: c.k.alt,
            helperText: '可以先删改，只留最有用的一两句',
            helperStyle: TextStyle(color: c.k.faint),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.k.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.k.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: c.k.brand, width: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    ctl.dispose();
    if (out == null || out.isEmpty) return;
    await app.db.saveMnemonic(card.id, out);
    widget.onCardChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('已存为助记，学习页卡背会显示')));
  }

  Future<void> _bubbleMenu(String text) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制'),
              onTap: () => Navigator.pop(c, 'copy')),
          if (_ctx.card != null)
            ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text('存为助记'),
                onTap: () => Navigator.pop(c, 'mn')),
        ]),
      ),
    );
    if (!mounted) return;
    if (pick == 'copy') await copyText(context, aiPlainText(text), label: '已复制回答');
    if (pick == 'mn') await _saveAsMnemonic(aiPlainText(text));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final app = context.watch<AppState>();
    final ready = app.aiConfig.ready || _debug;
    return Material(
      color: k.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: k.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          _header(context, app),
          Divider(height: 1, color: k.line),
          if (!ready)
            Expanded(child: _setupHint(context, app))
          else ...[
            if (_ctx.key.startsWith('roleplay:')) _roleplayBanner(context),
            Expanded(child: _messages(context)),
            _sessionNudgeBanner(context, app),
            _inputBar(context),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppState app) {
    final k = context.k;
    final cfg = app.aiConfig;
    final sub = _ctx.subtitle.trim();
    final contextLine =
        sub.isEmpty || sub == _ctx.title ? _ctx.title : '${_ctx.title} · $sub';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 8),
      child: Column(
        children: [
          Row(
            children: [
              const AiSpark(size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('问一问',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: k.text)),
                    const SizedBox(height: 1),
                    Text(contextLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: k.t3)),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: Icon(Icons.close, color: k.t2),
                onPressed: () => Navigator.maybePop(context),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('ai.header.status'),
                  onTap: () => openAiSettings(context),
                  child: Row(
                    children: [
                      AiProviderAvatar(provider: cfg.provider, size: 18),
                      const SizedBox(width: 5),
                      AiStatusPill(status: app.aiStatus, configured: cfg.ready),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          cfg.ready ? cfg.model : cfg.provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: k.t3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              TextButton.icon(
                key: const ValueKey('ai.history'),
                onPressed: _busy ? null : _openHistory,
                style: TextButton.styleFrom(
                  foregroundColor: k.t2,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.history, size: 19),
                label: const Text('历史', style: TextStyle(fontSize: 12)),
              ),
              if (_msgs.isNotEmpty)
                IconButton(
                  key: const ValueKey('ai.new'),
                  tooltip: '新对话（当前这段保存在历史里）',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.add_comment_outlined, color: k.t2),
                  onPressed: _busy ? null : _newConversation,
                ),
              IconButton(
                tooltip: 'AI 设置',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.tune, color: k.t2),
                onPressed: () => openAiSettings(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _setupHint(BuildContext context, AppState app) {
    final k = context.k;
    final miss = app.aiConfig.missing;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AiSpark(size: 56),
          const SizedBox(height: 18),
          Text('还没连上 AI',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: k.text)),
          const SizedBox(height: 8),
          Text(
            '支持 ${aiVendorNames()}，以及任意 OpenAI 兼容接口。'
            '填入你自己的 API Key 和模型名就能用，按用量计费，'
            'Key 只存在本机。${miss == null ? '' : '\n（当前：$miss）'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: k.t2),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => openAiSettings(context),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final k = context.k;
    final quick = _ctx.quick;
    final title = _ctx.card != null
        ? '想先了解「${_ctx.title}」哪方面？'
        : _ctx.key.startsWith('grammar:')
            ? '这一页想怎么学？'
            : '今天想练什么？';
    final primary = quick.take(3).toList();
    final more = quick.skip(3).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final contentW = box.maxWidth - 32;
        final chipW = (contentW - 8) / 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 32),
            child: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AiSpark(size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: k.text)),
                            const SizedBox(height: 2),
                            Text('点一条开始，或直接输入问题',
                                style: TextStyle(fontSize: 12.5, color: k.t3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (quick.isEmpty)
                    Text('直接输入问题即可。',
                        style: TextStyle(fontSize: 13, color: k.t3))
                  else ...[
                    _emptySectionLabel(context, '推荐', primary.length),
                    const SizedBox(height: 8),
                    for (final q in primary) ...[
                      _quickCard(context, q),
                      const SizedBox(height: 8),
                    ],
                    if (more.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _emptySectionLabel(context, '更多问法', more.length),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final q in more)
                            SizedBox(
                              width: chipW,
                              height: 34,
                              child: _quickChip(context, q),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptySectionLabel(BuildContext context, String label, int n) {
    final k = context.k;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: k.t3)),
        Text('$n 条', style: TextStyle(fontSize: 12, color: k.t3)),
      ],
    );
  }

  Widget _quickCard(BuildContext context, (String, String) q) {
    final k = context.k;
    final (label, prompt) = q;
    final hint = kAiQuickHints[label];
    return GestureDetector(
      key: ValueKey('ai.quick.$label'),
      onTap: () => label == '情景对话' ? _pickRoleplay() : _send(prompt),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: k.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: k.text)),
                  if (hint != null) ...[
                    const SizedBox(height: 1),
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, height: 1.35, color: k.t3)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: k.t3),
          ],
        ),
      ),
    );
  }

  Widget _quickChip(BuildContext context, (String, String) q) {
    final k = context.k;
    final (label, prompt) = q;
    return GestureDetector(
      key: ValueKey('ai.quick.$label'),
      onTap: () => label == '情景对话' ? _pickRoleplay() : _send(prompt),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: k.line),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: k.text)),
      ),
    );
  }

  Widget _roleplayBanner(BuildContext context) {
    final k = context.k;
    final sc = aiRoleplayById(_ctx.key.substring(9));
    final targets = _roleplayTargets.isNotEmpty
        ? _roleplayTargets
        : (sc?.defaultTargets ?? const <String>[]);
    final used = matchRoleplayTargetWords(
      targets,
      [for (final m in _msgs) if (m.role == 'user') m.content],
    );
    return Container(
      key: const Key('ai.roleplay.banner'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(bottom: BorderSide(color: k.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '任务词 ${used.length}/${targets.length}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: k.t2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final w in targets)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: used.contains(w) ? k.tint : k.bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: used.contains(w)
                                ? k.brand.withValues(alpha: 0.45)
                                : k.border,
                          ),
                        ),
                        child: Text(
                          '${used.contains(w) ? '✓ ' : ''}$w',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: used.contains(w) ? FontWeight.w700 : FontWeight.w400,
                            color: used.contains(w) ? k.deep : k.t2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                key: const Key('ai.roleplay.switch'),
                onTap: _busy ? null : _pickRoleplay,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: k.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: k.border),
                  ),
                  child: Text(
                    '换场景',
                    style: TextStyle(fontSize: 11.5, color: k.t2),
                  ),
                ),
              ),
            ],
          ),
          if (_ctx.quick.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (label, prompt) in _ctx.quick)
                  GestureDetector(
                    onTap: _busy ? null : () => _send(prompt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: k.bg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: k.line),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 11.5, color: k.t2),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionDigestPill(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: InkWell(
          key: const ValueKey('ai.session.digest'),
          borderRadius: BorderRadius.circular(999),
          onTap: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('早期对话摘要'),
              content: SingleChildScrollView(
                child: SelectableText(_sessionDigest ?? ''),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: k.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: k.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.compress, size: 14, color: k.t3),
                const SizedBox(width: 6),
                Text('已压缩早期对话（点击查看摘要）',
                    style: TextStyle(fontSize: 12, color: k.t2)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sessionNudgeBanner(BuildContext context, AppState app) {
    if (_busy || _nudgeDismissed || _msgs.isEmpty) {
      return const SizedBox.shrink();
    }
    final turns = _msgs.where((m) => m.role == 'user').length;
    final activeTok = aiMessagesTokens(_source);
    final economy = app.aiCtxTier == AiCtxTier.economy;
    final turnLimit = economy ? 5 : 8;
    final tokLimit = economy ? 12000 : 24000;
    final planDone = _plan.isNotEmpty && _plan.every((s) => s.done);
    final longChat = turns >= turnLimit || activeTok >= tokLimit;
    if (!planDone && !longChat) return const SizedBox.shrink();
    final canCompact = aiSessionCompactRange(
          _msgs,
          budget: app.aiBudgetForTurn(forTools: _plan.isNotEmpty).input,
          from: _sessionFoldEnd ?? 0,
          keepRecentTurns: 2,
          maxTokens: tokLimit,
          force: true,
        ) !=
        null;
    final k = context.k;
    final text = planDone
        ? '任务已完成，新开会话可节省后续费用'
        : '对话已较长（约 ${aiTokensShort(activeTok)}），可压缩早先内容或新开会话';
    return Container(
      key: const ValueKey('ai.nudge.banner'),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(top: BorderSide(color: k.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined, size: 15, color: k.t3),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: k.t2)),
          ),
          if (canCompact && !_debug)
            TextButton(
              key: const ValueKey('ai.nudge.compact'),
              onPressed: _compacting
                  ? null
                  : () => _maybeCompactSession(
                        app.aiConfig,
                        app.aiBudgetForTurn(forTools: _plan.isNotEmpty),
                        manual: true,
                      ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              child: Text(_compacting ? '压缩中…' : '压缩对话',
                  style: const TextStyle(fontSize: 12)),
            ),
          TextButton(
            key: const ValueKey('ai.nudge.new'),
            onPressed: _newConversation,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('新开会话', style: TextStyle(fontSize: 12)),
          ),
          IconButton(
            key: const ValueKey('ai.nudge.dismiss'),
            tooltip: '关闭提示',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.close, size: 16, color: k.t3),
            onPressed: () => setState(() => _nudgeDismissed = true),
          ),
        ],
      ),
    );
  }

  Widget _messages(BuildContext context) {
    final k = context.k;

    if (_msgs.isEmpty && !_busy && _error == null) {
      return _emptyState(context);
    }
    final lastAnswer = !_busy &&
            _msgs.isNotEmpty &&
            _msgs.last.role == 'assistant' &&
            _msgs.last.content.trim().isNotEmpty
        ? _msgs.last
        : null;

    final sig = (k.surface, k.line, k.text, MediaQuery.sizeOf(context).width);
    if (_bubbleSig != sig) {
      _bubbleSig = sig;
      _bubbleCache.clear();
    }
    final items = <Widget Function()>[
      if (_sessionDigest != null) () => _sessionDigestPill(context),
      for (final m in _msgs)
        if (m.role == 'tool')
          () => _toolLine(context, m)
        else if (m.visible)
          () => _bubbleCache[m] ??= _bubble(context, m),
      if (lastAnswer != null) () => _answerActions(context, lastAnswer.content),
      if (_plan.isNotEmpty && (_busy || _capped)) () => _planCard(context),
      if (_pending != null) () => _confirmCard(context, _pending!.$1),
      if (_busy && _pending == null)
        () => _partial.isEmpty
            ? _thinkingBubble(context)
            : _bubble(context, AiMessage('assistant', _partial)),
      if (_error != null) () => _errorCard(context, _error!),
      if (_msgs.isNotEmpty)
        () => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('AI 生成，仅供参考 · 释义以词典为准',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: k.t3)),
            ),
    ];

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i](),
    );
  }

  Widget _toolLine(BuildContext context, AiMessage m) {
    final k = context.k;
    final offer = _offers[m];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt, size: 15, color: kAiGradB),
            const SizedBox(width: 3),
            Flexible(
              child: Text(m.label ?? m.toolName ?? '',
                  key: const ValueKey('ai.toolLine'),
                  style: TextStyle(fontSize: 12.5, color: k.t2)),
            ),
          ]),
          if (offer != null)
            GestureDetector(
              onTap: () => offer.go(context),
              child: Text('${offer.label} ›',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: k.deep)),
            ),
        ],
      ),
    );
  }

  Widget _confirmCard(BuildContext context, AiPendingAction a) {
    final k = context.k;
    return Container(
      key: const ValueKey('ai.confirm'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAiGradB.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const AiSpark(size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text('AI 想要：${a.title}',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: k.text)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final l in a.lines)
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 2),
              child: Text(l, style: TextStyle(fontSize: 13, height: 1.45, color: k.t2)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  key: const ValueKey('ai.confirm.no'),
                  onPressed: () => _resolvePending(false),
                  child: const Text('取消')),
              const SizedBox(width: 4),
              FilledButton(
                  key: const ValueKey('ai.confirm.yes'),
                  onPressed: () => _resolvePending(true),
                  child: Text(a.confirmLabel)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context) {
    final k = context.k;
    final done = _plan.where((s) => s.done).length;
    return Container(
      key: const ValueKey('ai.plan'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kAiGradB.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('任务清单 · $done/${_plan.length}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: k.text)),
          const SizedBox(height: 6),
          for (final s in _plan)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  s.done
                      ? Icons.check_circle
                      : s.status == 'doing'
                          ? Icons.timelapse
                          : Icons.radio_button_unchecked,
                  size: 16,
                  color: s.done ? const Color(0xFF2E9E6A) : (s.status == 'doing' ? kAiGradA : k.t3),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(s.text,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: s.done ? k.t3 : k.text,
                          decoration: s.done ? TextDecoration.lineThrough : null)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _thinkingBubble(BuildContext context) {
    final k = context.k;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: k.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(
                '${_thinking ? '深度思考中…' : '思考中…'}'
                '${_round > 1 ? ' · 第 $_round 步' : ''}',
                key: const ValueKey('ai.thinking'),
                style: TextStyle(fontSize: 13.5, color: k.t3)),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, AiException e) {
    final k = context.k;
    return Container(
      key: const ValueKey('ai.error'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD9534F).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9534F).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFD9534F)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(e.message,
                  style: TextStyle(fontSize: 13, height: 1.5, color: k.text)),
            ),
          ]),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (e.linkProblem)
                TextButton(
                    onPressed: () => openAiSettings(context),
                    child: const Text('检查设置')),
              TextButton(onPressed: _retry, child: const Text('重试')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _answerActions(BuildContext context, String text) {
    final k = context.k;
    Widget act(IconData icon, String label, VoidCallback onTap, String key) =>
        GestureDetector(
          key: ValueKey(key),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 12, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: k.t3),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(fontSize: 12, color: k.t3)),
            ]),
          ),
        );
    final ttsActive = _tts.isActive('last');
    final idText = extractIndonesianForTts(text);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Wrap(children: [
        act(Icons.copy_outlined, '复制',
            () => copyText(context, aiPlainText(text), label: '已复制回答'), 'ai.act.copy'),
        act(Icons.refresh, '重新回答', _regenerate, 'ai.act.regen'),
        if (_ctx.card != null)
          act(Icons.lightbulb_outline, '存为助记', () => _saveAsMnemonic(aiPlainText(text)),
              'ai.act.mn'),
        if (idText.isNotEmpty)
          act(Icons.auto_stories_outlined, '划词阅读', () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TextReaderScreen(initialText: idText)),
            );
          }, 'ai.act.reader'),
        if (context.watch<AppState>().aiTtsConfigured) ...[
          act(
            ttsActive ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
            ttsActive ? (_tts.loading ? '合成中…' : '停止') : '朗读',
            () async {
              final cfg = context.read<AppState>().aiTtsConfig;
              final err = await _tts.toggleSpeak(
                key: 'last',
                rawText: text,
                config: cfg,
              );
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err)),
                );
              }
            },
            'ai.act.tts',
          ),
          act(
            Icons.speed,
            (_tts.speed - 0.75).abs() < 0.05 ? '0.75×' : '1.0×',
            _tts.toggleSpeed,
            'ai.act.tts_speed',
          ),
        ],
      ]),
    );
  }

  Widget _bubble(BuildContext context, AiMessage m) {
    final k = context.k;
    final mine = m.role == 'user';
    Uint8List? img = _imgCache[m];
    if (img == null && m.imageB64 != null) {
      try {
        img = _imgCache[m] = base64Decode(m.imageB64!);
      } catch (_) {}
    }
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),

      constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (mine ? 0.84 : 0.94)),
      decoration: BoxDecoration(
        gradient: mine
            ? LinearGradient(colors: [
                kAiGradA.withValues(alpha: 0.16),
                kAiGradB.withValues(alpha: 0.16),
              ])
            : null,
        color: mine ? null : k.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: mine ? null : Border.all(color: k.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (img != null)
            Padding(
              padding: EdgeInsets.only(bottom: m.content.isEmpty ? 0 : 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(img, height: 140, fit: BoxFit.cover, cacheHeight: 280),
              ),
            ),
          if (m.content.isNotEmpty)
            mine
                ? Text(m.content,
                    style: TextStyle(fontSize: 14.5, height: 1.6, color: k.text))
                : _assistantContent(context, m.content),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: mine
          ? bubble
          : GestureDetector(
              onLongPress: () => _bubbleMenu(m.content), child: bubble),
    );
  }

  Widget _assistantContent(BuildContext context, String raw) {
    final segs = parseAiChatSegments(raw);
    if (segs.length == 1 && segs.first is AiTextSegment) {
      return AiMarkdown((segs.first as AiTextSegment).markdown);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < segs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          switch (segs[i]) {
            AiTextSegment(:final markdown) => AiMarkdown(markdown),
            AiQuizSegment(:final items) => AiQuizCard(
                items: items,
                onAddWord: (wordId) async {
                  await _app.remember([wordId]);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已将 $wordId 加入记忆')),
                    );
                  }
                },
              ),
          },
        ],
      ],
    );
  }

  Widget _inputBar(BuildContext context) {
    final k = context.k;
    return Container(
      decoration: BoxDecoration(
        color: k.surface,
        border: Border(top: BorderSide(color: k.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              6, 8, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              if (_capped && !_busy)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 2, 8),
                  child: GestureDetector(
                    key: const ValueKey('ai.continue'),
                    onTap: () => _send(_kContinuePrompt),
                    child: Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient:
                            const LinearGradient(colors: [kAiGradA, kAiGradB]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 16, color: Colors.white),
                            SizedBox(width: 2),
                            Text('继续完成',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ]),
                    ),
                  ),
                ),
              if (_imgBytes != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_imgBytes!,
                          width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 128),
                    ),
                    Positioned(
                      right: -8,
                      top: -8,
                      child: GestureDetector(
                        key: const ValueKey('ai.img.remove'),
                        onTap: () => setState(() {
                          _imgBytes = null;
                          _imgB64 = null;
                        }),
                        child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const ValueKey('ai.attach'),
                    tooltip: '拍照 / 选图提问',
                    icon: Icon(Icons.add_photo_alternate_outlined, color: k.t2),
                    onPressed: _busy ? null : _pickImage,
                  ),
                  if (context.watch<AppState>().aiAsrConfigured)
                    IconButton(
                      key: const ValueKey('ai.mic'),
                      tooltip: '语音输入（ASR）',
                      icon: Icon(Icons.mic_none_outlined, color: k.t2),
                      onPressed: _busy
                          ? null
                          : () {
                              final cfg = context.read<AppState>().aiAsrConfig;
                              final label =
                                  cfg.model.isNotEmpty ? cfg.model : cfg.endpoint;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('已接入 ASR（$label），语音输入将在后续版本开放')),
                              );
                            },
                    ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('ai.input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _ctx.card != null
                            ? '问点什么，或发一个句子让它批改'
                            : '提问，或让 AI 帮你整理词单…',
                        isDense: true,
                        filled: true,
                        fillColor: k.bg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    key: const ValueKey('ai.send'),
                    onTap: _busy ? _stopNow : () => _send(_input.text),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: _busy ? null : kAiGradient,
                        color: _busy ? k.alt : null,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_busy ? Icons.stop_rounded : Icons.arrow_upward,
                          color: _busy ? k.t2 : Colors.white, size: 22),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
