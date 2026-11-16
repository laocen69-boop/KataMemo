import 'dict_map.dart';
import 'dict_model.dart';
import 'dict_parse.dart';

List<Map<String, Object?>> readDictRecords(
  DictFormat format,
  String text,
  DictImportOptions options,
) {
  switch (format) {
    case DictFormat.csv:
    case DictFormat.tsv:
    case DictFormat.txt:

      return delimitedToRecords(parseDelimited(text,
          delimiter: dictDelimiterFor(format, text), maxRows: options.maxRecords));
    case DictFormat.json:
      return parseJsonRecords(text, maxRecords: options.maxRecords);
  }
}

List<String> dictHeaders(List<Map<String, Object?>> records) {
  final seen = <String>[];
  final set = <String>{};
  for (final r in records) {
    for (final k in r.keys) {
      if (set.add(k)) seen.add(k);
    }
  }
  return seen;
}

const Map<ImportField, List<String>> _synonyms = {
  ImportField.lemma: [
    'lemma', 'word', 'headword', 'entry', '词', '词条', '词头', '单词', '印尼语', 'lema', 'kata',
  ],
  ImportField.definition: [
    'definition', 'meaning', 'def', 'gloss', '释义', '定义', '解释', '意思', '中文', 'makna', 'arti',
  ],
  ImportField.pos: ['pos', 'part_of_speech', 'partofspeech', '词性', '词类'],
  ImportField.example: ['example', 'examples', 'sentence', '例句', '用例', 'contoh'],
  ImportField.translation: ['translation', 'translate', '译文', '例句翻译', '翻译'],
  ImportField.pronunciation: ['pronunciation', 'pron', 'ipa', '发音', '音标', 'pelafalan'],
  ImportField.homograph: ['homograph', 'homograph_index', '同形', '同形序号', '序号'],
};

Map<ImportField, String> guessDictMapping(List<String> headers) {
  final out = <ImportField, String>{};
  final normalized = {for (final h in headers) h.trim().toLowerCase(): h};
  for (final entry in _synonyms.entries) {
    for (final alias in entry.value) {
      final hit = normalized[alias.toLowerCase()];
      if (hit != null) {
        out[entry.key] = hit;
        break;
      }
    }
  }
  return out;
}

String dictFormatLabel(DictFormat f) => switch (f) {
      DictFormat.csv => 'CSV',
      DictFormat.tsv => 'TSV',
      DictFormat.txt => 'TXT',
      DictFormat.json => 'JSON',
    };

String dictDisplayName(String path) {
  final slash = path.lastIndexOf(RegExp(r'[\\/]'));
  final base = slash < 0 ? path : path.substring(slash + 1);
  final m = RegExp(r'^pick_\d+_(.+)$').firstMatch(base);
  return m == null ? base : m.group(1)!;
}

String dictDelimiterFor(DictFormat format, String text) => switch (format) {
      DictFormat.tsv => sniffDelimiter(text, fallback: '\t'),
      _ => sniffDelimiter(text, fallback: ','),
    };

String dictDelimiterLabel(String d) => switch (d) {
      ',' => '逗号',
      '\t' => '制表符',
      ';' => '分号',
      '|' => '竖线',
      _ => '「$d」',
    };

enum _CellKind { empty, cjk, latinShort, latinLong, number, other }

final _cjk = RegExp(r'[㐀-䶿一-鿿]');
final _latinWord = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ'’\-]+$");

String _cellText(Object? v) =>
    v is List ? [for (final x in v) (x ?? '').toString()].join(' ') : (v ?? '').toString();

_CellKind _kindOf(String s) {
  final s0 = s.trim();
  if (s0.isEmpty) return _CellKind.empty;
  if (_cjk.hasMatch(s0)) return _CellKind.cjk;
  if (RegExp(r'^[\d.,\s]+$').hasMatch(s0)) return _CellKind.number;
  final words = s0.split(RegExp(r'\s+'));
  final latin = words.where((w) => _latinWord.hasMatch(w.replaceAll(RegExp(r'[.,!?;:"()]'), ''))).length;
  if (latin >= words.length * 0.7) {
    return words.length >= 4 ? _CellKind.latinLong : _CellKind.latinShort;
  }
  return _CellKind.other;
}

const _posValues = {
  'n', 'v', 'a', 'adj', 'adv', 'pron', 'num', 'prep', 'conj', 'interj', 'part', 'p',
  'vt', 'vi', 'n.', 'v.', 'a.', 'adj.', 'adv.', 'pron.', 'num.', 'prep.', 'conj.',
  'nomina', 'verba', 'adjektiva', 'adverbia',
  '名', '动', '形', '副', '代', '数', '量', '介', '连', '叹', '助',
  '名词', '动词', '形容词', '副词', '代词', '数词', '量词', '介词', '连词', '叹词', '助词',
};

bool _posLike(String s) {
  final s0 = s.trim().toLowerCase();
  if (s0.isEmpty || s0.length > 12) return false;
  return s0.split(RegExp(r'[|/,;、\s]+')).where((x) => x.isNotEmpty).every(_posValues.contains);
}

bool _pronLike(String s) {
  final s0 = s.trim();
  if (s0.isEmpty || _cjk.hasMatch(s0)) return false;
  return RegExp(r'^[/\[].*[/\]]$').hasMatch(s0) || RegExp(r'^[A-Za-zé]+(\.[A-Za-zé]+)+$').hasMatch(s0);
}

bool guessHasHeader(List<List<String>> rows) {
  if (rows.length < 2) return true;
  final first = rows.first;
  if (guessDictMapping([for (final h in first) h.trim()]).isNotEmpty) return true;
  final sample = rows.skip(1).take(10).toList();
  for (var c = 0; c < first.length; c++) {
    final counts = <_CellKind, int>{};
    for (final r in sample) {
      final k = _kindOf(c < r.length ? r[c] : '');
      counts[k] = (counts[k] ?? 0) + 1;
    }
    if (counts.isEmpty) continue;
    final major = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    if (_kindOf(first[c]) != major) return true;
  }
  return false;
}

Map<ImportField, String> guessDictMappingFromContent(
  List<String> headers,
  List<Map<String, Object?>> records, {
  Map<ImportField, String> known = const {},
}) {
  final out = Map<ImportField, String>.of(known);
  final used = known.values.toSet();
  final sample = records.take(300).toList();
  if (sample.isEmpty) return out;

  double ratio(String h, bool Function(String) test) {
    var hit = 0;
    for (final r in sample) {
      final s = _cellText(r[h]).trim();
      if (s.isEmpty) continue;
      if (test(s)) hit++;
    }
    return hit / sample.length;
  }

  double avgLen(String h) {
    var sum = 0, n = 0;
    for (final r in sample) {
      final s = _cellText(r[h]).trim();
      if (s.isEmpty) continue;
      sum += s.length;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  String? pick(double Function(String h) score, double min) {
    String? best;
    var bestScore = min;
    for (final h in headers) {
      if (used.contains(h)) continue;
      final s = score(h);
      if (s > bestScore) {
        bestScore = s;
        best = h;
      }
    }
    if (best != null) used.add(best);
    return best;
  }

  void take(ImportField f, String? h) {
    if (h != null) out[f] = h;
  }

  if (!out.containsKey(ImportField.pos)) {
    take(ImportField.pos, pick((h) => ratio(h, _posLike), 0.6));
  }
  if (!out.containsKey(ImportField.pronunciation)) {
    take(ImportField.pronunciation, pick((h) => ratio(h, _pronLike), 0.6));
  }
  if (!out.containsKey(ImportField.lemma)) {
    take(ImportField.lemma,
        pick((h) => ratio(h, (s) => _kindOf(s) == _CellKind.latinShort), 0.6));
  }
  final cjkCols = [
    for (final h in headers)
      if (!used.contains(h) && ratio(h, (s) => _kindOf(s) == _CellKind.cjk) >= 0.5) h,
  ]..sort((a, b) => avgLen(a).compareTo(avgLen(b)));

  if (!out.containsKey(ImportField.definition)) {
    if (cjkCols.isNotEmpty) {
      final pickDef = cjkCols.removeAt(0);
      out[ImportField.definition] = pickDef;
      used.add(pickDef);
    } else {
      final longs = [
        for (final h in headers)
          if (!used.contains(h) && ratio(h, (s) => _kindOf(s) == _CellKind.latinLong) >= 0.5) h,
      ]..sort((a, b) => avgLen(b).compareTo(avgLen(a)));
      if (longs.isNotEmpty) {
        out[ImportField.definition] = longs.first;
        used.add(longs.first);
      }
    }
  }
  if (!out.containsKey(ImportField.example)) {
    take(ImportField.example,
        pick((h) => ratio(h, (s) => _kindOf(s) == _CellKind.latinLong), 0.5));
  }
  if (!out.containsKey(ImportField.translation) &&
      out.containsKey(ImportField.example) &&
      cjkCols.isNotEmpty) {
    out[ImportField.translation] = cjkCols.removeLast();
  }
  return out;
}

class DictPreview {
  const DictPreview({
    required this.delimiter,
    required this.hasHeaderGuess,
    required this.headersWith,
    required this.headersWithout,
    required this.samplesWith,
    required this.samplesWithout,
    required this.mappingWith,
    required this.mappingWithout,
    required this.countWith,
    required this.countWithout,
  });

  final String? delimiter;
  final bool hasHeaderGuess;
  final List<String> headersWith;
  final List<String> headersWithout;

  final Map<String, List<String>> samplesWith;
  final Map<String, List<String>> samplesWithout;
  final Map<ImportField, String> mappingWith;
  final Map<ImportField, String> mappingWithout;
  final int countWith;
  final int countWithout;

  List<String> headers(bool hasHeader) => hasHeader ? headersWith : headersWithout;
  Map<String, List<String>> samples(bool hasHeader) => hasHeader ? samplesWith : samplesWithout;
  Map<ImportField, String> mapping(bool hasHeader) => hasHeader ? mappingWith : mappingWithout;
  int count(bool hasHeader) => hasHeader ? countWith : countWithout;
}

Map<String, List<String>> _samplesOf(List<String> headers, List<Map<String, Object?>> records) {
  final out = <String, List<String>>{};
  for (final h in headers) {
    final vals = <String>[];
    for (final r in records) {
      final s = _cellText(r[h]).trim();
      if (s.isEmpty) continue;
      vals.add(s.length > 16 ? '${s.substring(0, 16)}…' : s);
      if (vals.length >= 2) break;
    }
    out[h] = vals;
  }
  return out;
}

Map<ImportField, String> _fullGuess(List<String> headers, List<Map<String, Object?>> records) =>
    guessDictMappingFromContent(headers, records, known: guessDictMapping(headers));

DictPreview buildDictPreview(DictFormat format, String text, DictImportOptions options) {
  if (format == DictFormat.json) {
    final recs = parseJsonRecords(text, maxRecords: options.maxRecords);
    final hs = dictHeaders(recs);
    final m = _fullGuess(hs, recs);
    final s = _samplesOf(hs, recs);
    return DictPreview(
      delimiter: null,
      hasHeaderGuess: true,
      headersWith: hs,
      headersWithout: hs,
      samplesWith: s,
      samplesWithout: s,
      mappingWith: m,
      mappingWithout: m,
      countWith: recs.length,
      countWithout: recs.length,
    );
  }
  final d = dictDelimiterFor(format, text);
  final rows = parseDelimited(text, delimiter: d, maxRows: options.maxRecords);
  final withH = delimitedToRecords(rows);
  final withoutH = delimitedToRecords(rows, hasHeader: false);
  final hsWith = dictHeaders(withH.isEmpty ? [{for (final h in rows.first) h.trim(): ''}] : withH)
      .where((h) => h.isNotEmpty)
      .toList();
  final hsWithout = rows.isEmpty ? <String>[] : noHeaderColumnNames(
      rows.fold<int>(0, (m, r) => r.length > m ? r.length : m));
  return DictPreview(
    delimiter: d,
    hasHeaderGuess: guessHasHeader(rows),
    headersWith: hsWith,
    headersWithout: hsWithout,
    samplesWith: _samplesOf(hsWith, withH),
    samplesWithout: _samplesOf(hsWithout, withoutH),
    mappingWith: _fullGuess(hsWith, withH),
    mappingWithout: _fullGuess(hsWithout, withoutH),
    countWith: withH.length,
    countWithout: withoutH.length,
  );
}

ImportResult importDictText(
  DictFormat format,
  String text,
  bool hasHeader,
  Map<ImportField, String> mapping,
  DictImportOptions options,
) {
  final List<Map<String, Object?>> records;
  if (format == DictFormat.json) {
    records = parseJsonRecords(text, maxRecords: options.maxRecords);
  } else {
    final d = dictDelimiterFor(format, text);
    records = delimitedToRecords(
        parseDelimited(text, delimiter: d, maxRows: options.maxRecords),
        hasHeader: hasHeader);
  }
  return mapRecords(records, mapping, options: options);
}
