library;

import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'db.dart';
import 'models.dart';
import 'native_channel.dart';

class OcrRun {
  final String text;
  final Rect box;
  final bool cjk;

  const OcrRun(this.text, this.box, {this.cjk = false});
}

class MlKitOcrEngine {
  static const MethodChannel _ch = kNativeChannel;

  Future<List<OcrRun>> recognize(String path) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('ocr', {'path': path});
    if (raw == null) return const [];
    final out = <OcrRun>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final text = (m['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      out.add(OcrRun(
        text,
        Rect.fromLTRB(
          (m['l'] as num? ?? 0).toDouble(),
          (m['t'] as num? ?? 0).toDouble(),
          (m['r'] as num? ?? 0).toDouble(),
          (m['b'] as num? ?? 0).toDouble(),
        ),
        cjk: (m['cjk'] as num? ?? 0) == 1,
      ));
    }
    return out;
  }
}

class ScanRow {
  final List<OcrRun> runs;

  ScanRow(List<OcrRun> input)
      : runs = (input.toList()..sort((a, b) => a.box.left.compareTo(b.box.left)));

  String get latinText => [
        for (final r in runs)
          if (!r.cjk) r.text,
      ].join(' ').trim();

  String get cjkText => [
        for (final r in runs)
          if (r.cjk) r.text,
      ].join('；');
}

final _cjkChar = RegExp(r'[\u3400-\u9fff]');

List<OcrRun> runsFromPastedText(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <OcrRun>[];
  var y = 0.0;
  for (final raw in lines) {
    var line = raw.trim();

    line = line
        .replaceFirst(RegExp(r'^(?:\d+[.)、]|[①-⑳]|[-•·])\s*'), '')
        .trim();
    if (line.isEmpty) continue;
    final m = _cjkChar.firstMatch(line);
    final latin = (m == null ? line : line.substring(0, m.start)).trim();
    final zh = (m == null ? '' : line.substring(m.start)).trim();
    if (latin.isNotEmpty) {
      out.add(OcrRun(latin, Rect.fromLTRB(0, y, 400, y + 60)));
    }
    if (zh.isNotEmpty) {
      out.add(OcrRun(zh, Rect.fromLTRB(500, y, 1000, y + 60), cjk: true));
    }
    y += 100;
  }
  return out;
}

List<ScanRow> mergeRows(List<OcrRun> runs) {
  if (runs.isEmpty) return const [];
  final sorted = [...runs]..sort((a, b) {
      final dy = a.box.top - b.box.top;
      if (dy.abs() > 4) return a.box.top.compareTo(b.box.top);
      return a.box.left.compareTo(b.box.left);
    });
  final rows = <ScanRow>[];
  var cur = <OcrRun>[];
  double top = 0, bottom = 0;
  void flush() {
    if (cur.isNotEmpty) rows.add(ScanRow(cur));
    cur = <OcrRun>[];
  }

  for (final r in sorted) {
    if (cur.isEmpty) {
      cur = [r];
      top = r.box.top;
      bottom = r.box.bottom;
      continue;
    }
    final overlap = math.min(bottom, r.box.bottom) - math.max(top, r.box.top);
    final minH = math.min(bottom - top, r.box.bottom - r.box.top).abs();
    if (overlap > 0.3 * (minH == 0 ? 1 : minH)) {
      cur.add(r);
      top = math.min(top, r.box.top);
      bottom = math.max(bottom, r.box.bottom);
    } else {
      flush();
      cur = [r];
      top = r.box.top;
      bottom = r.box.bottom;
    }
  }
  flush();
  return rows;
}

class ScanPair {
  final String latin;
  final String zh;

  final bool weak;

  const ScanPair(this.latin, this.zh, this.weak);
}

String cleanZh(String s) => s
    .trim()
    .replaceFirst(RegExp(r'^[\s0-9０-９①-⑳.、,，)）:：\-—·「『"]+'), '')
    .replaceAll(RegExp(r'[\s.。,，;；、:：]+$'), '')
    .trim();

List<ScanPair> pairDefinitions(List<ScanRow> rows) {
  final out = <ScanPair>[];
  for (var i = 0; i < rows.length; i++) {
    final latin = rows[i].latinText;
    if (latin.isEmpty) continue;
    final zh = cleanZh(rows[i].cjkText);
    if (zh.isNotEmpty) {
      out.add(ScanPair(latin, zh, false));
      continue;
    }
    if (i + 1 < rows.length && rows[i + 1].latinText.isEmpty) {
      final zh2 = cleanZh(rows[i + 1].cjkText);
      if (zh2.isNotEmpty) {
        out.add(ScanPair(latin, zh2, true));
        continue;
      }
    }
    out.add(ScanPair(latin, '', false));
  }
  return out;
}

class ScanSpan {
  final int start;
  final int end;
  final List<String> toks;

  const ScanSpan(this.start, this.end, this.toks);

  String get form => toks.join(' ');
  String get fold => AppDb.fold(form);
  int get width => end - start;

  @override
  String toString() => 'ScanSpan($form)';
}

List<ScanSpan> rowCandidates(String latinText) {
  final toks = <String>[];
  for (final raw in latinText.split(RegExp(r'\s+'))) {
    final f = AppDb.fold(raw);
    if (f.isEmpty || f.length < 2) continue;
    if (!RegExp(r'[a-z]').hasMatch(f)) continue;
    toks.add(f);
  }
  final n = toks.length;
  final spans = <ScanSpan>[];
  for (var w = math.min(5, n); w >= 1; w--) {
    for (var s = 0; s + w <= n; s++) {
      spans.add(ScanSpan(s, s + w, toks.sublist(s, s + w)));
    }
  }
  return spans;
}

List<ScanSpan> resolveRow(List<ScanSpan> spans, bool Function(String fold) hit,
    {required int tokenCount}) {
  final used = List<bool>.filled(tokenCount, false);
  final out = <ScanSpan>[];
  for (final s in spans) {
    var free = true;
    for (var i = s.start; i < s.end; i++) {
      if (used[i]) {
        free = false;
        break;
      }
    }
    if (!free || !hit(s.fold)) continue;
    out.add(s);
    for (var i = s.start; i < s.end; i++) {
      used[i] = true;
    }
  }
  return out;
}

class ScanMatch {
  final WordCard card;
  final String form;

  final int hits;

  final bool morph;

  const ScanMatch(this.card, this.form, {this.hits = 1, this.morph = false});
}

class ScanMiss {
  final String form;
  final String zh;

  final bool weakZh;

  const ScanMiss(this.form, this.zh, {this.weakZh = false});
}

class ScanOutcome {
  final List<ScanMatch> matched;
  final List<ScanMiss> missed;

  final int rowcount;

  const ScanOutcome(this.matched, this.missed, this.rowcount);
}

int _tierRank(String t) => switch (t) {
      't1' => 1,
      't2' => 2,
      't3' => 3,
      't4' => 4,
      't5' => 5,
      't6' => 6,
      't7' => 7,
      'phrase' => 8,
      'proper' => 9,
      'derived' => 10,
      'redup' => 11,
      _ => 12,
    };

Future<ScanOutcome> matchScan(AppDb db, List<OcrRun> runs,
    {int morphCap = 60}) async {
  final rows = mergeRows(runs);
  final pairs = pairDefinitions(rows);

  final spansByRow = <List<ScanSpan>>[];
  final folds = <String>{};
  for (final p in pairs) {
    final spans = rowCandidates(p.latin);
    spansByRow.add(spans);
    for (final s in spans) {
      folds.add(s.fold);
    }
  }

  final byId = <String, WordCard>{};
  final list = folds.take(800).toList(growable: false);
  for (var i = 0; i < list.length; i += 500) {
    final chunk = list.sublist(i, math.min(i + 500, list.length));
    for (final c in await db.wordsByIds(chunk)) {
      byId[c.id] = c;
    }
  }

  final matched = <String, ScanMatch>{};
  final missTokens = <String>[];
  final missZhByForm = <String, ScanMiss>{};
  final seenToken = <String>{};
  for (var r = 0; r < pairs.length; r++) {
    final spans = spansByRow[r];
    if (spans.isEmpty) continue;

    var n = 0;
    for (final s in spans) {
      if (s.end > n) n = s.end;
    }
    final hits = resolveRow(spans, (f) => byId.containsKey(f), tokenCount: n);
    for (final h in hits) {
      final card = byId[h.fold]!;
      final prev = matched[card.id];
      if (prev == null) {
        matched[card.id] = ScanMatch(card, h.form);
      } else {
        matched[card.id] = ScanMatch(card, prev.form, hits: prev.hits + 1);
      }
    }
    final hitForms = {for (final h in hits) h.fold};

    for (final s in spans.where((s) => s.width == 1)) {
      if (hitForms.contains(s.fold)) continue;

      final covered = hits.any((h) => s.start >= h.start && s.end <= h.end);
      if (covered) continue;
      if (seenToken.add(s.fold)) missTokens.add(s.fold);
      final zh = pairs[r].zh;
      final weak = pairs[r].weak;
      if (zh.isNotEmpty &&
          (missZhByForm[s.fold] == null || (!weak && missZhByForm[s.fold]!.weakZh))) {
        missZhByForm[s.fold] = ScanMiss(s.fold, zh, weakZh: weak);
      }
    }
  }

  final morphMiss = <String>[];
  var morphTried = 0;
  for (final t in missTokens) {
    if (matched.length + morphMiss.length >= 400) break;
    if (matched.containsKey(t)) continue;

    if (morphTried >= morphCap) {
      morphMiss.add(t);
      continue;
    }
    morphTried++;
    try {
      final r = await db.searchWordWithMorph(t);
      final card = r.card;
      if (card != null && card.id != t) {
        if (!matched.containsKey(card.id)) {
          matched[card.id] = ScanMatch(card, t, morph: true);
        }
        continue;
      }
      if (card != null && card.id == t) {

        if (!matched.containsKey(card.id)) {
          matched[card.id] = ScanMatch(card, t);
        }
        continue;
      }
    } catch (_) {

    }
    morphMiss.add(t);
  }

  final missed = [
    for (final t in morphMiss)
      missZhByForm[t] ?? ScanMiss(t, ''),
  ];

  final sorted = matched.values.toList()
    ..sort((a, b) {
      final byTier = _tierRank(a.card.tier).compareTo(_tierRank(b.card.tier));
      if (byTier != 0) return byTier;
      final byMorph = (a.morph ? 1 : 0).compareTo(b.morph ? 1 : 0);
      if (byMorph != 0) return byMorph;
      return a.card.id.compareTo(b.card.id);
    });
  return ScanOutcome(sorted, missed, pairs.length);
}

Future<ScanOutcome> matchPastedText(AppDb db, String text,
        {int morphCap = 60}) =>
    matchScan(db, runsFromPastedText(text), morphCap: morphCap);
