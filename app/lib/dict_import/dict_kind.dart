library;

import 'dict_model.dart';

enum DictKind {
  kbbi,
  other;

  String get storage => name;
  String get label => this == DictKind.kbbi ? 'KBBI' : '其它词典';
}

class DictKindInfo {
  const DictKindInfo({
    required this.kind,
    required this.byUser,
    this.evidence = const <String>[],
  });

  final DictKind kind;
  final bool byUser;
  final List<String> evidence;

  bool get isKbbi => kind == DictKind.kbbi;
  String get label => kind.label;

  Map<String, Object?> toMap() => {
        'kind': kind.storage,
        'by': byUser ? 'user' : 'auto',
        if (evidence.isNotEmpty) 'evidence': evidence,
      };

  static DictKindInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final k = raw['kind'];
    final kind = k == 'kbbi' ? DictKind.kbbi : DictKind.other;
    return DictKindInfo(
      kind: kind,
      byUser: raw['by'] == 'user',
      evidence: [
        for (final e in (raw['evidence'] as List<Object?>?) ?? const <Object?>[])
          if (e is String) e,
      ],
    );
  }

  DictKindInfo copyWith({DictKind? kind, bool? byUser, List<String>? evidence}) =>
      DictKindInfo(
        kind: kind ?? this.kind,
        byUser: byUser ?? this.byUser,
        evidence: evidence ?? this.evidence,
      );
}

class DictKindGuess {
  const DictKindGuess({
    required this.kind,
    required this.confident,
    required this.evidence,
  });

  final DictKind kind;
  final bool confident;
  final List<String> evidence;
}

final RegExp _kbbiPosTag = RegExp(
    r'(?:<i>\s*(?:n|v|a|adv|adj|pron|num|p|cak|ark|ki|kl|kp)\s*</i>'
    r'|^\s*(?:n|v|a|adv|adj|pron|num|p|cak|ark|ki|kl|kp)\s*[:.)])',
    caseSensitive: false);

final RegExp _homographTail = RegExp(r'\(\d+\)\s*$');

final RegExp _syllableDot = RegExp(r'[A-Za-z]\.[A-Za-z]');

bool _nameSaysKbbi(String name) {
  final base = name
      .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-]+'), ' ');
  return base.contains('kbbi') ||
      base.contains('kamus besar bahasa indonesia') ||
      base.contains('kamus besar');
}

DictKindGuess guessDictKind({
  required String name,
  required List<ImportEntry> sample,
  int? totalEntries,
}) {
  final ev = <String>[];

  if (_nameSaysKbbi(name)) {
    ev.add('文件名写明「KBBI / Kamus Besar Bahasa Indonesia」');
    return DictKindGuess(
        kind: DictKind.kbbi, confident: true, evidence: ev);
  }

  var signals = 0;
  final n = sample.length;

  if (n >= 30) {
    final dotted = sample.where((e) => _syllableDot.hasMatch(e.lemma)).length;
    final ratio = dotted / n;
    if (ratio >= 0.20) {
      signals++;
      ev.add('抽样 $n 条里 ${(ratio * 100).round()}% 词头带分音节点（如 te.man）');
    }

    final homo = sample.where((e) => _homographTail.hasMatch(e.lemma)).length;
    final homoRatio = homo / n;
    if (homoRatio >= 0.01) {
      signals++;
      ev.add('${(homoRatio * 100).toStringAsFixed(1)}% 词头带同形词编号（如 ma.kan (1)）');
    }

    final senses = [
      for (final e in sample)
        for (final s in e.senses) s.definition,
    ];
    if (senses.isNotEmpty) {
      final tagged = senses.where((d) => _kbbiPosTag.hasMatch(d)).length;
      final tagRatio = tagged / senses.length;
      if (tagRatio >= 0.10) {
        signals++;
        ev.add('${(tagRatio * 100).round()}% 释义带 KBBI 词性标记（n / v / a / <i>n</i> 等）');
      }
    }
  }

  if (totalEntries != null && totalEntries >= 30000) {
    signals++;
    ev.add('共 $totalEntries 条，接近 KBBI 全本规模');
  }

  if (ev.isEmpty) ev.add('文件名与词条结构都没有 KBBI 特征');
  if (signals >= 2) {
    return DictKindGuess(
        kind: DictKind.kbbi, confident: true, evidence: ev);
  }
  if (signals == 1) {
    ev.add('只命中一条弱信号：标为「疑似」，不自动优先，可在词典页手动指定');
  }
  return DictKindGuess(
      kind: DictKind.other, confident: signals == 0, evidence: ev);
}
