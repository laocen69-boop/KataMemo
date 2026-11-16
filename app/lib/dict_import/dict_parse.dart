import 'dart:convert';

enum DictFormat { csv, tsv, txt, json }

DictFormat? detectDictFormat(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.csv')) return DictFormat.csv;
  if (lower.endsWith('.tsv')) return DictFormat.tsv;
  if (lower.endsWith('.txt')) return DictFormat.txt;
  if (lower.endsWith('.json')) return DictFormat.json;
  return null;
}

List<List<String>> parseDelimited(
  String input, {
  required String delimiter,
  int? maxRows,
}) {
  assert(delimiter.length == 1, 'delimiter 必须是单个字符');
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(c);
      i++;
      continue;
    }
    if (c == '"' && field.isEmpty) {
      inQuotes = true;
      i++;
      continue;
    }
    if (c == delimiter) {
      endField();
      i++;
      continue;
    }
    if (c == '\r') {
      i++;
      continue;
    }
    if (c == '\n') {
      endRow();
      if (maxRows != null && rows.length > maxRows) {
        throw FormatException('记录数超过上限 $maxRows');
      }
      i++;
      continue;
    }
    field.write(c);
    i++;
  }
  if (inQuotes) {
    throw const FormatException('文件中有未闭合的双引号，已拒绝导入');
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endRow();
  }
  return rows;
}

List<Map<String, Object?>> delimitedToRecords(List<List<String>> rows,
    {bool hasHeader = true}) {
  if (rows.isEmpty) return const [];

  if (!hasHeader) {
    final width = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final names = noHeaderColumnNames(width);
    return [
      for (final r in rows)
        if (!r.every((v) => v.trim().isEmpty))
          {for (var c = 0; c < names.length; c++) names[c]: c < r.length ? r[c] : ''},
    ];
  }
  final header = rows.first.map((h) => h.trim()).toList();
  if (header.every((h) => h.isEmpty)) {
    throw const FormatException('表头为空');
  }
  final seen = <String>{};
  for (final h in header) {
    if (h.isEmpty) continue;
    if (!seen.add(h)) {
      throw FormatException('表头列名重复：「$h」，请先在表格中改成不同的名字');
    }
  }
  final records = <Map<String, Object?>>[];
  for (final r in rows.skip(1)) {
    if (r.every((v) => v.trim().isEmpty)) continue;
    final rec = <String, Object?>{};
    for (var c = 0; c < header.length; c++) {
      final name = header[c];
      if (name.isEmpty) continue;
      rec[name] = c < r.length ? r[c] : '';
    }
    records.add(rec);
  }
  return records;
}

List<Map<String, Object?>> parseJsonRecords(String text, {int? maxRecords}) {
  final decoded = jsonDecode(stripBom(text));
  final List<Object?> list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map && decoded['entries'] is List) {
    list = decoded['entries'] as List<Object?>;
  } else {
    throw const FormatException('JSON 顶层必须是对象数组，或包含 entries 数组的对象');
  }
  if (maxRecords != null && list.length > maxRecords) {
    throw FormatException('记录数超过上限 $maxRecords');
  }
  final records = <Map<String, Object?>>[];
  for (var k = 0; k < list.length; k++) {
    final item = list[k];
    if (item is! Map) {
      throw FormatException('第 ${k + 1} 条不是对象');
    }
    final rec = <String, Object?>{};
    item.forEach((key, value) {
      final name = key.toString();
      if (value is Map) {
        throw FormatException('第 ${k + 1} 条的「$name」是对象，不支持嵌套结构');
      }
      if (value is List) {
        for (final v in value) {
          if (v is Map || v is List) {
            throw FormatException('第 ${k + 1} 条的「$name」含有嵌套结构，不支持');
          }
        }
      }
      rec[name] = value;
    });
    records.add(rec);
  }
  return records;
}

String stripBom(String s) =>
    s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF ? s.substring(1) : s;

List<String> noHeaderColumnNames(int width) =>
    [for (var i = 1; i <= width; i++) '第$i列'];

String sniffDelimiter(String text, {String fallback = ','}) {
  const candidates = [',', '\t', ';', '|'];
  final lines = <String>[];
  for (final l in stripBom(text).split('\n')) {
    if (l.trim().isEmpty) continue;
    lines.add(l);
    if (lines.length >= 30) break;
  }
  if (lines.isEmpty) return fallback;

  int countOutsideQuotes(String line, String d) {
    var n = 0;
    var inQ = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') inQ = !inQ;
      if (!inQ && c == d) n++;
    }
    return n;
  }

  String? best;
  var bestScore = 0;
  for (final d in candidates) {
    final counts = [for (final l in lines) countOutsideQuotes(l, d)];
    final minC = counts.reduce((a, b) => a < b ? a : b);
    final maxC = counts.reduce((a, b) => a > b ? a : b);
    if (minC == 0) continue;

    final score = minC == maxC ? minC * 1000 : minC;
    if (score > bestScore) {
      bestScore = score;
      best = d;
    }
  }
  return best ?? fallback;
}
