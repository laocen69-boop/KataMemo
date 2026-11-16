library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'db.dart';

const String kLogSearchKey = 'log.search';
const String kLogGrammarWrongKey = 'log.grammar_wrong';
const int kLogSearchCap = 300;
const int kLogGrammarWrongCap = 200;

final Map<String, List<Map<String, dynamic>>> _cache = {};

List<Map<String, dynamic>> _decode(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    return [
      for (final e in jsonDecode(raw) as List)
        if (e is Map<String, dynamic>) e,
    ];
  } catch (_) {
    return [];
  }
}

void primeActivityLogs(Map<String, String> meta) {
  for (final k in [kLogSearchKey, kLogGrammarWrongKey]) {
    _cache[k] = _decode(meta[k]);
  }
}

void resetActivityLogCache() => _cache.clear();

Future<List<Map<String, dynamic>>> _read(AppDb db, String key) async {
  final hit = _cache[key];
  if (hit != null) return hit;
  try {
    return _cache[key] = _decode(await db.metaGet(key));
  } catch (_) {
    return _cache[key] = [];
  }
}

List<Map<String, dynamic>> _push(
    List<Map<String, dynamic>> list, Map<String, dynamic> row, int cap) {
  final next = [...list, row];
  return next.length > cap ? next.sublist(next.length - cap) : next;
}

Future<void> writeSearchHistoryWithLog(
    AppDb db, String historyKey, List<String> history, String? term,
    {int? at}) async {
  final d = await db.db;
  final b = d.batch()
    ..insert('meta', {'k': historyKey, 'v': jsonEncode(history)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  final t = term?.trim() ?? '';
  if (t.isNotEmpty && _cache.containsKey(kLogSearchKey)) {
    final next = _push(_cache[kLogSearchKey]!,
        {'t': t, 'ts': at ?? DateTime.now().millisecondsSinceEpoch}, kLogSearchCap);
    _cache[kLogSearchKey] = next;
    b.insert('meta', {'k': kLogSearchKey, 'v': jsonEncode(next)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await b.commit(noResult: true);
}

Future<void> logSearch(AppDb db, String term, {int? at}) async {
  final t = term.trim();
  if (t.isEmpty) return;
  try {
    final next = _push(await _read(db, kLogSearchKey),
        {'t': t, 'ts': at ?? DateTime.now().millisecondsSinceEpoch}, kLogSearchCap);
    _cache[kLogSearchKey] = next;
    await db.metaSet(kLogSearchKey, jsonEncode(next));
  } catch (_) {}
}

Future<void> logGrammarWrong(
  AppDb db, {
  required String quizId,
  required String page,
  required String question,
  required List<String> options,
  required int picked,
  required int answer,
  String why = '',
  int? at,
}) async {
  try {
    final next = _push(
        await _read(db, kLogGrammarWrongKey),
        {
          'id': quizId,
          'page': page,
          'q': question,
          'opts': options,
          'pick': picked,
          'ans': answer,
          'why': why,
          'ts': at ?? DateTime.now().millisecondsSinceEpoch,
        },
        kLogGrammarWrongCap);
    _cache[kLogGrammarWrongKey] = next;
    await db.metaSet(kLogGrammarWrongKey, jsonEncode(next));
  } catch (_) {}
}

Future<List<String>> searchesSince(AppDb db, DateTime since) async {
  final from = since.millisecondsSinceEpoch;
  final seen = <String>{};
  final out = <String>[];
  for (final r in (await _read(db, kLogSearchKey)).reversed) {
    if (((r['ts'] as num?) ?? 0) < from) continue;
    final t = '${r['t']}';
    if (seen.add(t.toLowerCase())) out.add(t);
  }
  return out;
}

Future<List<Map<String, dynamic>>> grammarWrongSince(
    AppDb db, DateTime since) async {
  final from = since.millisecondsSinceEpoch;
  return [
    for (final r in (await _read(db, kLogGrammarWrongKey)).reversed)
      if (((r['ts'] as num?) ?? 0) >= from) r,
  ];
}
