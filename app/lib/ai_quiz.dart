/// AI 助手互动练习卡解析器（纯 Dart，零 IO / UI 依赖）。
///
/// 约定格式：
/// ```
/// :::quiz
/// {"question":"...","options":["A...","B...","C..."],"answer":0,"explanation":"...","word_id":"..."}
/// :::
/// ```
/// 任何格式错误、流式半截未闭合或索引越界都无损回退为普通 Markdown 文本，绝不丢内容或抛异常。
library;

import 'dart:convert';

class AiQuizItem {
  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;
  final String? wordId;

  const AiQuizItem({
    required this.question,
    required this.options,
    required this.answerIndex,
    this.explanation = '',
    this.wordId,
  });
}

sealed class AiChatSegment {
  const AiChatSegment();
}

final class AiTextSegment extends AiChatSegment {
  final String markdown;
  const AiTextSegment(this.markdown);
}

final class AiQuizSegment extends AiChatSegment {
  final List<AiQuizItem> items;
  const AiQuizSegment(this.items);
}

final RegExp _reOpenQuiz = RegExp(r'^:::quiz\s*$', multiLine: true);
final RegExp _reCloseQuiz = RegExp(r'^:::\s*$', multiLine: true);

/// 解析 AI 回复文本为「普通 Markdown / 互动练习卡」分段序列。
List<AiChatSegment> parseAiChatSegments(String raw) {
  if (!raw.contains(':::quiz')) return [AiTextSegment(raw)];

  final segments = <AiChatSegment>[];
  var cursor = 0;

  while (cursor < raw.length) {
    final openMatch = _reOpenQuiz.firstMatch(raw.substring(cursor));
    if (openMatch == null) {
      final tail = raw.substring(cursor);
      if (tail.trim().isNotEmpty) segments.add(AiTextSegment(tail));
      break;
    }

    final openStart = cursor + openMatch.start;
    final bodyStart = cursor + openMatch.end;
    final closeMatch = _reCloseQuiz.firstMatch(raw.substring(bodyStart));
    if (closeMatch == null) {
      // 流式输出尚未闭合：整段按普通文本保留
      final rest = raw.substring(cursor);
      if (rest.trim().isNotEmpty) segments.add(AiTextSegment(rest));
      break;
    }

    if (openStart > cursor) {
      final before = raw.substring(cursor, openStart);
      if (before.trim().isNotEmpty) segments.add(AiTextSegment(before));
    }

    final bodyEnd = bodyStart + closeMatch.start;
    final closeEnd = bodyStart + closeMatch.end;
    final jsonText = raw.substring(bodyStart, bodyEnd).trim();
    final items = _tryParseQuizItems(jsonText);

    if (items.isNotEmpty) {
      segments.add(AiQuizSegment(items));
    } else {
      // 格式不合法时无损回退原文本
      segments.add(AiTextSegment(raw.substring(openStart, closeEnd)));
    }
    cursor = closeEnd;
  }

  return segments.isEmpty ? [AiTextSegment(raw)] : segments;
}

List<AiQuizItem> _tryParseQuizItems(String jsonText) {
  if (jsonText.isEmpty) return const [];
  try {
    final decoded = jsonDecode(jsonText);
    final rawList = switch (decoded) {
      List l => l,
      Map m when m['items'] is List => m['items'] as List,
      Map m => [m],
      _ => const <Object?>[],
    };
    final out = <AiQuizItem>[];
    for (final entry in rawList) {
      if (entry is! Map) continue;
      final q = '${entry['question'] ?? ''}'.trim();
      final optsRaw = entry['options'];
      if (q.isEmpty || optsRaw is! List) continue;
      final opts = [
        for (final o in optsRaw)
          if ('$o'.trim().isNotEmpty) '$o'.trim(),
      ];
      if (opts.length < 2 || opts.length > 6) continue;
      final ans = _parseAnswerIndex(entry['answer'], opts.length);
      if (ans == null) continue;
      final exp = '${entry['explanation'] ?? ''}'.trim();
      final wid = '${entry['word_id'] ?? entry['wordId'] ?? ''}'.trim();
      out.add(AiQuizItem(
        question: q,
        options: opts,
        answerIndex: ans,
        explanation: exp,
        wordId: wid.isEmpty ? null : wid,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

int? _parseAnswerIndex(Object? raw, int optionCount) {
  int? idx;
  if (raw is int) {
    idx = raw;
  } else if (raw is num) {
    idx = raw.toInt();
  } else if (raw is String) {
    final s = raw.trim().toUpperCase();
    idx = int.tryParse(s);
    if (idx == null && s.length == 1) {
      final code = s.codeUnitAt(0) - 65; // 'A'..'F' -> 0..5
      if (code >= 0 && code < optionCount) idx = code;
    }
  }
  if (idx == null || idx < 0 || idx >= optionCount) return null;
  return idx;
}
