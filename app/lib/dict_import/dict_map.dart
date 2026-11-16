import 'dict_model.dart';

ImportResult mapRecords(
  List<Map<String, Object?>> records,
  Map<ImportField, String> mapping, {
  DictImportOptions options = const DictImportOptions(),
}) {
  final lemmaCol = mapping[ImportField.lemma];
  if (lemmaCol == null || lemmaCol.isEmpty) {
    throw ArgumentError('必须映射词头（lemma）');
  }

  if (records.isNotEmpty) {
    final keys = <String>{for (final r in records) ...r.keys};
    for (final entry in mapping.entries) {
      if (entry.value.isNotEmpty && !keys.contains(entry.value)) {
        throw ArgumentError('映射的列「${entry.value}」（${entry.key.name}）在文件中不存在');
      }
    }
  }

  final guardDefCol = mapping[ImportField.definition];
  if (guardDefCol != null && guardDefCol.isNotEmpty && guardDefCol == lemmaCol) {
    throw ArgumentError('释义列和词头列是同一列——这样导出来的释义会和词头一模一样。'
        '请把「释义」指到真正的释义列（比如 makna / 释义 / Arti）。');
  }

  final issues = <ImportIssue>[];
  final order = <String>[];
  final builders = <String, _Builder>{};
  final homCol = mapping[ImportField.homograph];
  final posCol = mapping[ImportField.pos];
  final defCol = mapping[ImportField.definition];
  final exCol = mapping[ImportField.example];
  final trCol = mapping[ImportField.translation];
  final pronCol = mapping[ImportField.pronunciation];
  final sep = options.multiSeparator;

  for (var r = 0; r < records.length; r++) {
    final rec = records[r];
    final row = r + 1;

    final lemma = dictTidy(_single(rec, lemmaCol));
    if (lemma.isEmpty) {
      issues.add(ImportIssue(row: row, message: '词头为空，已跳过'));
      continue;
    }
    if (lemma.length > options.maxLemmaLength) {
      issues.add(ImportIssue(row: row, message: '词头超过 ${options.maxLemmaLength} 字符，已跳过'));
      continue;
    }

    var hom = 1;
    if (homCol != null && homCol.isNotEmpty) {
      final h = int.tryParse(_single(rec, homCol).trim());
      if (h == null || h < 1) {
        issues.add(ImportIssue(row: row, message: '同形序号无效，按 1 处理'));
      } else {
        hom = h;
      }
    }

    final defRaw = _split(rec, defCol, sep);
    final posRaw = _split(rec, posCol, sep);
    final exRaw = _split(rec, exCol, sep);
    final trRaw = _split(rec, trCol, sep);
    final pron = _single(rec, pronCol).trim();

    final n = defRaw.length;
    final posList = _posFor(n, posRaw, row, issues);
    final exBySense = _examplesFor(n, exRaw, trRaw, row, issues, options);

    final senses = <ImportSense>[];
    for (var i = 0; i < n; i++) {
      final def = dictTidy(defRaw[i]);
      if (def.isEmpty) {
        issues.add(ImportIssue(row: row, message: '第 ${i + 1} 个释义为空，已跳过'));
        continue;
      }
      senses.add(ImportSense(pos: posList[i], definition: def, examples: exBySense[i]));
    }

    final key = '${dictFold(lemma)}\u0000$hom';
    final b = builders[key];
    if (b == null) {
      order.add(key);
      builders[key] = _Builder(
        lemma: lemma,
        homographIndex: hom,
        pronunciation: pron.isEmpty ? null : pron,
        firstRow: row,
        senses: senses,
      );
    } else {
      if (homCol == null || homCol.isEmpty) {
        issues.add(ImportIssue(
          row: row,
          message: '词头「$lemma」在多行出现，已合并为同一条目（如是不同的词，请映射同形序号列）',
          warning: false,
        ));
      }
      b.senses.addAll(senses);
      b.pronunciation ??= pron.isEmpty ? null : pron;
    }
  }

  final entries = <ImportEntry>[];
  for (final key in order) {
    final b = builders[key]!;
    var senses = b.senses;
    if (senses.length > options.maxSensesPerEntry) {
      issues.add(ImportIssue(
        row: b.firstRow,
        message: '「${b.lemma}」的释义超过 ${options.maxSensesPerEntry} 条，多出的已舍弃',
      ));
      senses = senses.sublist(0, options.maxSensesPerEntry);
    }

    if (senses.isEmpty) {
      issues.add(ImportIssue(
        row: b.firstRow,
        message: '「${b.lemma}」没有可导入的释义或例句，已跳过',
      ));
      continue;
    }
    entries.add(ImportEntry(
      lemma: b.lemma,
      homographIndex: b.homographIndex,
      pronunciation: b.pronunciation,
      senses: senses,
      firstRow: b.firstRow,
    ));
  }
  return ImportResult(entries: entries, issues: issues);
}

enum AlignStatus { matched, ambiguous, unmatched }

class AlignedEntry {
  const AlignedEntry({required this.entry, required this.status, this.candidateIds = const []});

  final ImportEntry entry;
  final AlignStatus status;

  final List<String> candidateIds;
}

List<AlignedEntry> alignEntries(
  List<ImportEntry> entries,
  List<String> Function(String foldedLemma) lookup,
) {
  return [
    for (final e in entries)
      () {
        final cands = lookup(dictFold(e.lemma));
        if (cands.isEmpty) {
          return AlignedEntry(entry: e, status: AlignStatus.unmatched);
        }
        if (cands.length == 1) {
          return AlignedEntry(
              entry: e, status: AlignStatus.matched, candidateIds: cands);
        }
        return AlignedEntry(
            entry: e, status: AlignStatus.ambiguous, candidateIds: cands);
      }(),
  ];
}

class _Builder {
  _Builder({
    required this.lemma,
    required this.homographIndex,
    required this.pronunciation,
    required this.firstRow,
    required this.senses,
  });

  final String lemma;
  final int homographIndex;
  String? pronunciation;
  final int firstRow;
  final List<ImportSense> senses;
}

String _single(Map<String, Object?> rec, String? col) {
  if (col == null || col.isEmpty) return '';
  final v = rec[col];
  if (v == null) return '';
  if (v is List) return v.isEmpty ? '' : v.first?.toString() ?? '';
  return v.toString();
}

List<String> _split(Map<String, Object?> rec, String? col, String sep) {
  if (col == null || col.isEmpty) return const [];
  final v = rec[col];
  if (v == null) return const [];
  if (v is List) {
    return [for (final x in v) (x?.toString() ?? '').trim()];
  }
  final s = v.toString();
  if (s.trim().isEmpty) return const [];
  return s.split(sep).map((x) => x.trim()).toList();
}

List<String?> _posFor(int n, List<String> posRaw, int row, List<ImportIssue> issues) {
  String? nz(String s) => s.isEmpty ? null : s;
  if (posRaw.isEmpty) return List<String?>.filled(n, null);
  if (posRaw.length == 1) return List<String?>.filled(n, nz(posRaw[0]));
  if (posRaw.length == n) return posRaw.map(nz).toList();
  issues.add(ImportIssue(
    row: row,
    message: '词性数量（${posRaw.length}）与释义数量（$n）不一致，词性未对应，已忽略',
  ));
  return List<String?>.filled(n, null);
}

List<List<ImportExample>> _examplesFor(
  int n,
  List<String> exRaw,
  List<String> trRaw,
  int row,
  List<ImportIssue> issues,
  DictImportOptions options,
) {
  final out = List<List<ImportExample>>.generate(n, (_) => <ImportExample>[]);
  if (exRaw.isEmpty) return out;
  if (n == 0) {
    issues.add(ImportIssue(row: row, message: '有例句但没有释义，例句未导入'));
    return out;
  }

  final List<int> owner;
  if (n == 1) {
    owner = List<int>.filled(exRaw.length, 0);
  } else if (exRaw.length == n) {
    owner = [for (var i = 0; i < n; i++) i];
  } else {
    issues.add(ImportIssue(
      row: row,
      message: '例句数量（${exRaw.length}）与释义数量（$n）不一致，例句未导入。'
          '请把每个释义的例句放到单独的行，或让数量一致',
    ));
    return out;
  }

  final trOk = trRaw.isEmpty || trRaw.length == exRaw.length;
  if (!trOk) {
    issues.add(ImportIssue(
      row: row,
      message: '译文数量（${trRaw.length}）与例句数量（${exRaw.length}）不一致，译文已忽略',
    ));
  }

  for (var e = 0; e < exRaw.length; e++) {
    final text = exRaw[e];
    if (text.isEmpty) continue;
    final tr = (trOk && trRaw.isNotEmpty && trRaw[e].isNotEmpty) ? trRaw[e] : null;
    final list = out[owner[e]];
    if (list.length >= options.maxExamplesPerSense) {
      issues.add(ImportIssue(
        row: row,
        message: '某个释义的例句超过 ${options.maxExamplesPerSense} 条，多出的已舍弃',
      ));
      continue;
    }
    list.add(ImportExample(text: text, translation: tr));
  }
  return out;
}
