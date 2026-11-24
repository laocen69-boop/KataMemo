/// 跨端粘贴文章阅读与生词高亮分析（纯 Dart，零 `dart:io` 依赖）。
///
/// 复用词库 `wordsByIds` 批量匹配（1–4 词短语贪心消费）+ 去重 `searchWordWithMorph`
/// 形态还原（附着词 / 被动 / 连写介词），并结合 `srsLevels` + `plannedIds` 标出
/// 「已掌握 / 学习中 / 生词」状态与文章词汇覆盖率。
library;

import 'dart:math' as math;

import 'db.dart';
import 'models.dart';

enum ReaderWordStatus { plain, unknown, learning, known }

class ReaderToken {
  final String raw;
  final WordCard? card;
  final ReaderWordStatus status;

  const ReaderToken(
    this.raw, {
    this.card,
    this.status = ReaderWordStatus.plain,
  });
}

class TextReaderResult {
  final List<List<ReaderToken>> paragraphs;
  final List<WordCard> uniqueCards;
  final Map<String, ReaderWordStatus> statusById;
  final int totalWords;
  final int knownCount;
  final int learningCount;
  final int unknownCount;

  const TextReaderResult({
    required this.paragraphs,
    required this.uniqueCards,
    required this.statusById,
    required this.totalWords,
    required this.knownCount,
    required this.learningCount,
    required this.unknownCount,
  });

  double get coveragePct =>
      totalWords == 0 ? 0 : (knownCount + learningCount) * 100 / totalWords;
}

/// 匹配印尼语单词或连字符叠词（如 `orang-orang`、`tiba-tiba`）。
final RegExp _wordRe = RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:-[A-Za-zÀ-ÖØ-öø-ÿ]+)*");

/// 归一化查找键：保留连字符与字母数字，转小写并折叠空白。
String _foldToken(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// 把一段纯文本拆成「普通分隔段 / 可匹配词段」的线性序列。
typedef _Seg = ({String raw, bool isWord, String fold});

List<_Seg> _tokenizeParagraph(String line) {
  final segs = <_Seg>[];
  var cursor = 0;
  for (final m in _wordRe.allMatches(line)) {
    if (m.start > cursor) {
      segs.add((raw: line.substring(cursor, m.start), isWord: false, fold: ''));
    }
    final raw = m.group(0)!;
    segs.add((raw: raw, isWord: true, fold: _foldToken(raw)));
    cursor = m.end;
  }
  if (cursor < line.length) {
    segs.add((raw: line.substring(cursor), isWord: false, fold: ''));
  }
  return segs;
}

/// 判断词条当前的阅读掌握档位（仅将实际学过 `reps > 0` 的词算入学习中/已掌握，
/// 避免仅「加入计划」但从未学过的词虚高覆盖率）。
ReaderWordStatus readerStatusOf(
  String cardId,
  Map<String, ({int state, double stability, int reps, int lapses})> levels,
  Set<String> planned,
) {
  final lv = levels[cardId];
  if (lv != null && lv.reps > 0) {
    if (lv.stability >= 7.0 || (lv.state == 2 && lv.reps >= 2)) {
      return ReaderWordStatus.known;
    }
    return ReaderWordStatus.learning;
  }
  return ReaderWordStatus.unknown;
}

/// 分析粘贴的印尼语文章，返回分段高亮令牌与统计。
///
/// 性能保护：
///   - `wordsByIds` 500 个一批批量查；
///   - `searchWordWithMorph` 先按词形去重，最多解析前 200 个不重复未命中词，
///     避免 3,000+ 词长文阻塞 UI。
Future<TextReaderResult> analyzeReadingText(AppDb db, String text) async {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final paraSegs = <List<_Seg>>[
    for (final line in lines) _tokenizeParagraph(line),
  ];

  // 提取每段词索引，生成 1..4 词短语候选（相邻词之间仅隔空白才组成短语）
  final candidateFolds = <String>{};
  for (final segs in paraSegs) {
    final wordIndices = <int>[
      for (var i = 0; i < segs.length; i++)
        if (segs[i].isWord) i,
    ];
    for (var wi = 0; wi < wordIndices.length; wi++) {
      final buf = StringBuffer();
      for (var span = 1; span <= 4 && wi + span - 1 < wordIndices.length; span++) {
        final curIdx = wordIndices[wi + span - 1];
        if (span > 1) {
          final prevIdx = wordIndices[wi + span - 2];
          // 中间只允许纯空白分隔，跨标点不拼短语
          var gapOk = true;
          for (var g = prevIdx + 1; g < curIdx; g++) {
            if (segs[g].raw.trim().isNotEmpty) {
              gapOk = false;
              break;
            }
          }
          if (!gapOk) break;
          buf.write(' ');
        }
        buf.write(segs[curIdx].fold);
        candidateFolds.add(buf.toString());
      }
    }
  }

  // 批量查 exact 词卡（每批 500 个）
  final byId = <String, WordCard>{};
  final allCand = candidateFolds.toList();
  for (var i = 0; i < allCand.length; i += 500) {
    final part = allCand.sublist(i, math.min(i + 500, allCand.length));
    final cards = await db.wordsByIds(part);
    for (final c in cards) {
      byId[c.id] = c;
    }
  }

  // 收集单字未命中去重集合，走一次词形还原兜底
  final missWords = <String>{};
  for (final segs in paraSegs) {
    for (final s in segs) {
      if (s.isWord && !byId.containsKey(s.fold)) {
        missWords.add(s.fold);
      }
    }
  }
  final morphMap = <String, WordCard>{};
  var morphBudget = 200;
  for (final w in missWords) {
    if (morphBudget <= 0) break;
    morphBudget--;
    try {
      final r = await db.searchWordWithMorph(w);
      if (r.card != null) {
        morphMap[w] = r.card!;
      }
    } catch (_) {}
  }

  // 第一遍贪心消费，收集全篇命中的所有 cardId 以便一次批量查 SRS 与 plan
  final matchedCards = <String, WordCard>{};
  final rawRunsByPara = <List<({String raw, WordCard? card})>>[];

  for (final segs in paraSegs) {
    final runs = <({String raw, WordCard? card})>[];
    final wordPosBySeg = <int, int>{};
    final wordIndices = <int>[];
    for (var i = 0; i < segs.length; i++) {
      if (segs[i].isWord) {
        wordPosBySeg[i] = wordIndices.length;
        wordIndices.add(i);
      }
    }

    var i = 0;
    while (i < segs.length) {
      final seg = segs[i];
      if (!seg.isWord) {
        runs.add((raw: seg.raw, card: null));
        i++;
        continue;
      }

      final wi = wordPosBySeg[i]!;
      WordCard? hit;
      var matchedEndSeg = i;

      // 优先尝试 4..2 词短语（仅跨空白）
      for (var span = math.min(4, wordIndices.length - wi); span >= 2; span--) {
        final endSegIdx = wordIndices[wi + span - 1];
        var gapOk = true;
        final foldParts = <String>[];
        for (var k = 0; k < span; k++) {
          final idxK = wordIndices[wi + k];
          foldParts.add(segs[idxK].fold);
          if (k > 0) {
            final prevK = wordIndices[wi + k - 1];
            for (var g = prevK + 1; g < idxK; g++) {
              if (segs[g].raw.trim().isNotEmpty) {
                gapOk = false;
                break;
              }
            }
          }
          if (!gapOk) break;
        }
        if (!gapOk) continue;
        final phraseKey = foldParts.join(' ');
        final c = byId[phraseKey];
        if (c != null) {
          hit = c;
          matchedEndSeg = endSegIdx;
          break;
        }
      }

      if (hit != null) {
        final rawPhrase = [
          for (var j = i; j <= matchedEndSeg; j++) segs[j].raw,
        ].join();
        matchedCards[hit.id] = hit;
        runs.add((raw: rawPhrase, card: hit));
        i = matchedEndSeg + 1;
      } else {
        final single = byId[seg.fold] ?? morphMap[seg.fold];
        if (single != null) matchedCards[single.id] = single;
        runs.add((raw: seg.raw, card: single));
        i++;
      }
    }
    rawRunsByPara.add(runs);
  }

  final cardIds = matchedCards.keys.toList();
  final levels = await db.srsLevels(cardIds);
  final planned = await db.plannedIds(cardIds);
  final statusById = <String, ReaderWordStatus>{
    for (final id in cardIds) id: readerStatusOf(id, levels, planned),
  };

  var totalWords = 0;
  var knownCount = 0;
  var learningCount = 0;
  var unknownCount = 0;
  final paragraphs = <List<ReaderToken>>[];

  for (final runs in rawRunsByPara) {
    final tokens = <ReaderToken>[];
    for (final r in runs) {
      if (r.card == null) {
        if (_wordRe.hasMatch(r.raw) && r.raw.trim().length >= 2) {
          totalWords++;
          unknownCount++;
        }
        tokens.add(ReaderToken(r.raw));
      } else {
        final st = statusById[r.card!.id] ?? ReaderWordStatus.unknown;
        totalWords++;
        switch (st) {
          case ReaderWordStatus.known:
            knownCount++;
          case ReaderWordStatus.learning:
            learningCount++;
          case ReaderWordStatus.unknown:
            unknownCount++;
          case ReaderWordStatus.plain:
            break;
        }
        tokens.add(ReaderToken(r.raw, card: r.card, status: st));
      }
    }
    paragraphs.add(tokens);
  }

  // 生词清单排序：未学排最前，其次学习中，最后已掌握
  final uniqueCards = matchedCards.values.toList()
    ..sort((a, b) {
      final sa = statusById[a.id] ?? ReaderWordStatus.unknown;
      final sb = statusById[b.id] ?? ReaderWordStatus.unknown;
      final order = sa.index.compareTo(sb.index);
      if (order != 0) return order;
      return (a.rank ?? 999999).compareTo(b.rank ?? 999999);
    });

  return TextReaderResult(
    paragraphs: paragraphs,
    uniqueCards: uniqueCards,
    statusById: statusById,
    totalWords: totalWords,
    knownCount: knownCount,
    learningCount: learningCount,
    unknownCount: unknownCount,
  );
}
