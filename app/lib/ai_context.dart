library;

import 'dart:convert';

import 'ai_chat.dart';

enum AiCtxTier { auto, economy, balanced, long, max, full }

const List<AiCtxTier> kAiCtxUiTiers = [AiCtxTier.auto, AiCtxTier.economy];

AiCtxTier aiCtxTierFromName(String? s) =>
    AiCtxTier.values.firstWhere((t) => t.name == s, orElse: () => AiCtxTier.auto);

String aiCtxLabel(AiCtxTier t) => switch (t) {
      AiCtxTier.auto => '自动（推荐）',
      AiCtxTier.economy => '省钱优先',
      AiCtxTier.balanced => '均衡 · 32K',
      AiCtxTier.long => '长任务 · 64K',
      AiCtxTier.max => '超长 · 128K',
      AiCtxTier.full => '按模型上限',
    };

String aiCtxDesc(AiCtxTier t) => switch (t) {
      AiCtxTier.auto => '按所选模型各自的最大安全上下文（窗口 75%，1M 模型约 750K），不额外人为卡上限',
      AiCtxTier.economy => '更积极地触发同会话压缩与新会话提示，工具返回也更精简，适合严格控费',
      AiCtxTier.balanced => '日常对话和三五步的小任务',
      AiCtxTier.long => '整理错题、批量建词单这类十几步的任务；每次请求更贵',
      AiCtxTier.max => '很长的任务或很长的对话；只适合窗口大的模型，费用很高',
      AiCtxTier.full => '用到模型窗口的 3/4（1M 的模型约 750K）。对话越长，每次提问越贵、越慢',
    };

class AiModelWindow {
  final int tokens;
  final String source;
  const AiModelWindow(this.tokens, this.source);
}

const int kAiUnknownWindow = 32000;

AiModelWindow aiModelWindow(String model, {int? detected}) {
  if (detected != null && detected >= 2048) {
    return AiModelWindow(detected, '服务商的模型列表');
  }
  final m = model.toLowerCase();
  final k = RegExp(r'(?:^|[-_.])(\d{1,4})k(?:$|[-_.])').firstMatch(m);
  if (k != null) {
    return AiModelWindow(int.parse(k.group(1)!) * 1000, '按型号名估计');
  }
  final m1 = RegExp(r'(?:^|[-_.])(\d)m(?:$|[-_.])').firstMatch(m);
  if (m1 != null) {
    return AiModelWindow(int.parse(m1.group(1)!) * 1000000, '按型号名估计');
  }
  const table = <(String, int)>[
    ('qwen-long', 1000000),
    ('qwen3.5-flash', 1000000),
    ('qwen3.5-35b', 262144),
    ('qwen3.5-9b', 262144),
    ('qwen', 1000000),
    ('deepseek', 1000000),
    ('gemini', 1000000),
    ('gemma-4-31b', 256000),
    ('gemma-4-26b', 256000),
    ('gemma-4', 128000),
    ('gemma', 128000),
    ('claude', 200000),
    ('minimax', 200000),
    ('doubao', 256000),
    ('seed', 256000),
    ('glm', 200000),
    ('kimi', 256000),
    ('moonshot', 128000),
    ('gpt', 400000),
    ('mimo', 128000),
  ];
  for (final (key, n) in table) {
    if (m.contains(key)) return AiModelWindow(n, '按型号名估计');
  }
  return const AiModelWindow(kAiUnknownWindow, '未识别，按 32K 计');
}

class AiBudget {
  final AiCtxTier tier;
  final AiModelWindow window;
  final int input;
  final int rounds;
  final bool capped;

  final int toolChars;
  const AiBudget(this.tier, this.window, this.input, this.rounds,
      {this.capped = false, this.toolChars = 6000});
}

const kAiAutoExtends = 4;

const kAiTurnSpendMul = 100;

const kAiStallRounds = 3;

AiBudget aiBudgetFor(AiCtxTier tier, AiModelWindow w, {bool forTools = false}) {

  final (want, rounds) = switch (tier) {
    AiCtxTier.auto => ((w.tokens * 0.75).round(), forTools ? 80 : 60),
    AiCtxTier.economy => forTools
        ? ((w.tokens * 0.5).round().clamp(12000, 48000), 45)
        : (16000, 30),
    AiCtxTier.balanced => (32000, 40),
    AiCtxTier.long => (64000, 60),
    AiCtxTier.max => (128000, 80),
    AiCtxTier.full => ((w.tokens * 0.75).round(), 80),
  };
  final ceiling = (w.tokens * 0.75).round();
  final input = want > ceiling ? ceiling : want;
  final r = rounds > 0 ? rounds : (input >= 40000 ? 60 : 40);
  final chars = tier == AiCtxTier.economy
      ? (forTools ? 4000 : 3000)
      : (input <= 16000 ? 3000 : (input <= 48000 ? 6000 : 12000));
  return AiBudget(tier, w, input < 4000 ? 4000 : input, r,
      capped: want > ceiling, toolChars: chars);
}

String aiTokensShort(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M'
    : '${(n / 1000).round()}K';

int aiEstimateTokens(String s) {
  var wide = 0, narrow = 0;
  for (final r in s.runes) {
    if (r >= 0x2E80) {
      wide++;
    } else {
      narrow++;
    }
  }
  return wide + (narrow / 3.6).ceil();
}

int aiMessageTokens(AiMessage m) {
  var n = 6 + aiEstimateTokens(m.content);
  for (final c in m.toolCalls) {
    n += 10 + aiEstimateTokens(c.name) + aiEstimateTokens(c.args);
  }
  if (m.imageB64 != null) n += 1200;
  return n;
}

int aiMessagesTokens(Iterable<AiMessage> ms) =>
    ms.fold(0, (s, m) => s + aiMessageTokens(m));

int aiToolSpecsTokens(List<AiToolSpec> specs) => specs.isEmpty
    ? 0
    : aiEstimateTokens(jsonEncode([
        for (final t in specs)
          {'n': t.name, 'd': t.description, 'p': t.parameters},
      ]));

String aiClip(String s, int max) => s.length <= max
    ? s
    : '${s.substring(0, max)}…〔已截断：原文 ${s.length} 字，只保留前 $max 字〕';

class AiPacked {
  final List<AiMessage> msgs;
  final int tokens;

  final int droppedTurns;
  final int shrunk;
  final bool over;
  const AiPacked(this.msgs, this.tokens,
      {this.droppedTurns = 0, this.shrunk = 0, this.over = false});
}

AiMessage _withContent(AiMessage m, String c) => AiMessage(m.role, c,
    toolCalls: m.toolCalls,
    toolCallId: m.toolCallId,
    toolName: m.toolName,
    imageB64: m.imageB64,
    imageMime: m.imageMime,
    label: m.label);

AiPacked aiPackHistory(List<AiMessage> history,
    {required int budget, int keepFull = 4, int toolChars = 6000}) {
  if (history.isEmpty) return const AiPacked([], 0);
  final lastUser = history.lastIndexWhere((m) => m.role == 'user');
  if (lastUser < 0) return const AiPacked([], 0);

  var cur = [
    for (final m in history.sublist(lastUser))
      m.role == 'tool' ? _withContent(m, aiClip(m.content, toolChars)) : m,
  ];
  var shrunk = 0;
  var tok = aiMessagesTokens(cur);
  final toolIdx = [for (var i = 0; i < cur.length; i++) if (cur[i].role == 'tool') i];
  final older = toolIdx.length > keepFull
      ? toolIdx.sublist(0, toolIdx.length - keepFull)
      : const <int>[];
  final newest = toolIdx.sublist(older.length);
  for (final (ids, max) in [(older, 600), (older, 160), (newest, 1500)]) {
    if (tok <= budget) break;
    for (final i in ids) {
      if (tok <= budget) break;
      final c = cur[i].content;
      if (c.length <= max) continue;
      final before = aiMessageTokens(cur[i]);
      cur[i] = _withContent(cur[i], aiClip(c, max));
      tok += aiMessageTokens(cur[i]) - before;
      shrunk++;
    }
  }

  var room = budget - tok;
  var start = lastUser;
  final prior = <List<AiMessage>>[];
  var turnsBefore = 0;
  for (var i = 0; i < lastUser; i++) {
    if (history[i].role == 'user') turnsBefore++;
  }
  var depth = 0;
  while (start > 0) {
    var prev = start - 1;
    while (prev > 0 && history[prev].role != 'user') {
      prev--;
    }
    if (history[prev].role != 'user') break;
    final max = depth == 0 ? 1500 : 300;
    final turn = [
      for (final m in history.sublist(prev, start))
        m.role == 'tool' ? _withContent(m, aiClip(m.content, max)) : m,
    ];
    final t = aiMessagesTokens(turn);
    if (t > room) break;
    room -= t;
    prior.insert(0, turn);
    start = prev;
    depth++;
  }
  final out = [for (final t in prior) ...t, ...cur];
  return AiPacked(out, budget - room,
      droppedTurns: turnsBefore - prior.length, shrunk: shrunk, over: tok > budget);
}

({int start, int end})? aiCompactRangeTokens(List<AiMessage> msgs,
    {required int budget, int? from, double trigger = 0.6, double keepTail = 0.3}) {
  final lastUser = msgs.lastIndexWhere((m) => m.role == 'user');
  if (lastUser < 0) return null;
  final base = from == null || from <= lastUser ? lastUser + 1 : from;
  if (base >= msgs.length) return null;
  if (aiMessagesTokens(msgs.sublist(base)) <= budget * trigger) return null;
  var tail = msgs.length;
  var kept = 0;
  while (tail > base) {
    final t = aiMessageTokens(msgs[tail - 1]);
    if (msgs.length - tail >= 2 && kept + t > budget * keepTail) break;
    kept += t;
    tail--;
  }
  while (tail < msgs.length && msgs[tail].role == 'tool') {
    tail++;
  }
  if (tail <= base || tail >= msgs.length) return null;
  return (start: base, end: tail);
}

({int start, int end, int turns})? aiSessionCompactRange(List<AiMessage> msgs,
    {required int budget,
    int from = 0,
    int keepRecentTurns = 2,
    double trigger = 0.6,
    int? maxTokens,
    bool force = false}) {
  final start = from.clamp(0, msgs.length);
  final userIdx = <int>[
    for (var i = start; i < msgs.length; i++)
      if (msgs[i].role == 'user') i,
  ];
  if (userIdx.length <= keepRecentTurns) return null;
  final end = userIdx[userIdx.length - keepRecentTurns];
  if (end <= start) return null;
  if (!force) {
    final tok = aiMessagesTokens(msgs.sublist(start));
    final limit = maxTokens == null
        ? (budget * trigger)
        : (budget * trigger < maxTokens ? budget * trigger : maxTokens.toDouble());
    if (tok <= limit) return null;
  }
  return (start: start, end: end, turns: userIdx.length - keepRecentTurns);
}

const int kAiMemoryMaxChars = 500;

String aiClipMemory(String s) {
  final t = s.trim();
  if (t.length <= kAiMemoryMaxChars) return t;
  return t.substring(0, kAiMemoryMaxChars).trimRight();
}

List<AiMessage> aiFlattenTools(List<AiMessage> history, {int maxChars = 2500}) {
  final out = <AiMessage>[];
  for (final m in history) {
    AiMessage x;
    if (m.role == 'tool') {
      x = AiMessage('user',
          '〔工具结果 · ${m.toolName ?? '工具'}〕\n${aiClip(m.content, maxChars)}');
    } else if (m.role == 'assistant' && m.toolCalls.isNotEmpty) {
      x = AiMessage('assistant', [
        if (m.content.trim().isNotEmpty) m.content.trim(),
        for (final c in m.toolCalls) '〔调用工具 ${c.name} ${aiClip(c.args, 200)}〕',
      ].join('\n'));
    } else {
      x = m;
    }
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        last.role == x.role &&
        last.imageB64 == null &&
        x.imageB64 == null) {
      out[out.length - 1] = AiMessage(x.role, '${last.content}\n\n${x.content}');
    } else {
      out.add(x);
    }
  }
  return out;
}

class AiDiag {
  AiDiag._();
  static bool enabled = false;
  static const int cap = 400;
  static final List<String> lines = [];

  static void log(String s) {
    if (!enabled) return;
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    lines.add('${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)} $s');
    if (lines.length > cap) lines.removeRange(0, lines.length - cap);
  }

  static String dump() => lines.join('\n');
  static void clear() => lines.clear();
}
