import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db.dart';
import 'dict_kind.dart';
import 'dict_model.dart';

const String kDictSourceDdl = '''
CREATE TABLE IF NOT EXISTS dict_source (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  format TEXT NOT NULL,
  entry_count INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  added_at INTEGER NOT NULL
)''';

const String kDictEntryDdl = '''
CREATE TABLE IF NOT EXISTS dict_entry (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL,
  lemma TEXT NOT NULL,
  fold TEXT NOT NULL,
  fold_loose TEXT NOT NULL DEFAULT '',
  homograph INTEGER NOT NULL DEFAULT 1,
  pronunciation TEXT,
  senses_json TEXT NOT NULL
)''';

const List<String> kDictIndexDdl = [
  'CREATE INDEX IF NOT EXISTS idx_dict_entry_fold ON dict_entry(fold)',

  'CREATE INDEX IF NOT EXISTS idx_dict_entry_fold_loose ON dict_entry(fold_loose)',
  'CREATE INDEX IF NOT EXISTS idx_dict_entry_source ON dict_entry(source_id)',
];

Future<void> createDictTables(Database db) async {
  await db.execute(kDictSourceDdl);
  await db.execute(kDictEntryDdl);
  for (final s in kDictIndexDdl) {
    await db.execute(s);
  }
}

String encodeDictSenses(List<ImportSense> senses) => jsonEncode([
      for (final s in senses)
        {
          'pos': s.pos,
          'def': s.definition,
          'ex': [
            for (final e in s.examples) {'t': e.text, 'tr': e.translation},
          ],
        },
    ]);

List<ImportSense> decodeDictSenses(String json) {
  final raw = jsonDecode(json);
  if (raw is! List) throw const FormatException('释义数据格式不对');
  final out = <ImportSense>[];
  for (final item in raw) {
    if (item is! Map) throw const FormatException('释义数据格式不对');
    final exRaw = (item['ex'] as List<Object?>?) ?? const <Object?>[];
    out.add(ImportSense(
      pos: item['pos'] as String?,
      definition: (item['def'] as String?) ?? '',
      examples: [
        for (final e in exRaw)
          if (e is Map)
            ImportExample(
              text: (e['t'] as String?) ?? '',
              translation: e['tr'] as String?,
            ),
      ],
    ));
  }
  return out;
}

class DictSourceRow {
  const DictSourceRow({
    required this.id,
    required this.name,
    required this.format,
    required this.entryCount,
    required this.enabled,
    required this.addedAt,
  });

  final int id;
  final String name;
  final String format;
  final int entryCount;
  final bool enabled;
  final int addedAt;
}

class DictHit {
  const DictHit({
    required this.sourceId,
    required this.sourceName,
    required this.entry,
    this.isKbbi = false,
  });

  final int sourceId;
  final String sourceName;
  final ImportEntry entry;
  final bool isKbbi;
}

const String kDictKindsMetaKey = 'dict_kinds';

extension AppDbDict on AppDb {

  Future<Map<int, DictKindInfo>> dictKinds() async {
    final raw = await metaGet(kDictKindsMetaKey);
    if (raw == null || raw.isEmpty) return <int, DictKindInfo>{};
    final out = <int, DictKindInfo>{};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        for (final e in m.entries) {
          final id = int.tryParse('${e.key}');
          final info = DictKindInfo.fromMap(e.value);
          if (id != null && info != null) out[id] = info;
        }
      }
    } on FormatException {
      return <int, DictKindInfo>{};
    }
    return out;
  }

  Future<void> dictSetKind(int id, DictKindInfo info) async {
    final all = await dictKinds();
    all[id] = info;
    await metaSet(kDictKindsMetaKey, jsonEncode({
          for (final e in all.entries) '${e.key}': e.value.toMap(),
        }));
  }

  Future<DictKindInfo> dictAutoKind(
    int id, {
    required String name,
    required List<ImportEntry> sample,
    int? totalEntries,
  }) async {
    final existing = (await dictKinds())[id];
    if (existing != null && existing.byUser) return existing;
    final g = guessDictKind(
        name: name, sample: sample, totalEntries: totalEntries);
    final info = DictKindInfo(
      kind: g.confident ? g.kind : DictKind.other,
      byUser: false,
      evidence: g.evidence,
    );
    await dictSetKind(id, info);
    return info;
  }

  Future<List<DictSourceRow>> dictSources() async {
    final d = await db;
    final rows = await d.query('dict_source', orderBy: 'added_at DESC, id DESC');
    return [
      for (final r in rows)
        DictSourceRow(
          id: r['id'] as int,
          name: r['name'] as String,
          format: r['format'] as String,
          entryCount: r['entry_count'] as int,
          enabled: (r['enabled'] as int) == 1,
          addedAt: r['added_at'] as int,
        ),
    ];
  }

  Future<int> dictWriteImport({
    required String name,
    required String format,
    required List<ImportEntry> entries,
  }) async {
    final d = await db;
    return d.transaction<int>((txn) async {
      final sid = await txn.insert('dict_source', {
        'name': name,
        'format': format,
        'entry_count': entries.length,
        'enabled': 1,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });

      const chunk = 2000;
      for (var i = 0; i < entries.length; i += chunk) {
        final end = i + chunk > entries.length ? entries.length : i + chunk;
        final batch = txn.batch();
        for (final e in entries.sublist(i, end)) {
        batch.insert('dict_entry', {
          'source_id': sid,
          'lemma': e.lemma,
          'fold': dictFold(e.lemma),
          'fold_loose': dictFoldLoose(e.lemma),
          'homograph': e.homographIndex,
          'pronunciation': e.pronunciation,
          'senses_json': encodeDictSenses(e.senses),
        });
        }
        await batch.commit(noResult: true);
      }
      return sid;
    });
  }

  Future<void> dictSetEnabled(int id, bool enabled) async {
    final d = await db;
    await d.update(
      'dict_source',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> dictDelete(int id) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('dict_entry', where: 'source_id = ?', whereArgs: [id]);
      await txn.delete('dict_source', where: 'id = ?', whereArgs: [id]);
    });

    final all = await dictKinds()..remove(id);
    await metaSet(kDictKindsMetaKey, jsonEncode({
          for (final e in all.entries) '${e.key}': e.value.toMap(),
        }));
  }

  Future<List<DictHit>> dictLookup(String foldedLemma) async {
    final d = await db;
    final loose = dictFoldLoose(foldedLemma);
    final rows = await d.rawQuery('''
      SELECT e.source_id, s.name, e.lemma, e.homograph, e.pronunciation, e.senses_json,
             CASE WHEN e.fold = ? THEN 1 ELSE 0 END AS exact_hit
      FROM dict_entry e JOIN dict_source s ON s.id = e.source_id
      WHERE (e.fold = ? OR e.fold_loose = ?) AND s.enabled = 1
      ORDER BY exact_hit DESC, s.added_at DESC, e.homograph
      ''', [foldedLemma, foldedLemma, loose]);
    final kinds = await dictKinds();
    final out = <DictHit>[];
    for (final r in rows) {
      final sid = r['source_id'] as int;
      out.add(DictHit(
        sourceId: sid,
        sourceName: r['name'] as String,
        isKbbi: kinds[sid]?.isKbbi ?? false,
        entry: ImportEntry(
          lemma: r['lemma'] as String,
          homographIndex: r['homograph'] as int,
          pronunciation: r['pronunciation'] as String?,
          senses: decodeDictSenses(r['senses_json'] as String),
        ),
      ));
    }

    return [
      ...out.where((h) => h.isKbbi),
      ...out.where((h) => !h.isKbbi),
    ];
  }

  Future<Map<String, List<String>>> dictAlignWordIds(Iterable<String> foldedLemmas) async {
    final d = await db;
    final list = foldedLemmas.toSet().toList();
    final out = <String, List<String>>{};

    if (list.length > 2000) {
      final wanted = list.toSet();
      final rows = await d.rawQuery('SELECT id, word FROM words');
      for (final r in rows) {
        final f = dictFold(r['word'] as String);
        if (!wanted.contains(f)) continue;
        out.putIfAbsent(f, () => <String>[]).add(r['id'] as String);
      }
      return out;
    }
    const chunk = 400;
    for (var i = 0; i < list.length; i += chunk) {
      final end = i + chunk > list.length ? list.length : i + chunk;
      final part = list.sublist(i, end);
      final wanted = part.toSet();
      final marks = List.filled(part.length, '?').join(',');
      final rows = await d.rawQuery(
        'SELECT id, word FROM words WHERE LOWER(TRIM(word)) IN ($marks)',
        part,
      );
      for (final r in rows) {
        final f = dictFold(r['word'] as String);
        if (!wanted.contains(f)) continue;
        out.putIfAbsent(f, () => <String>[]).add(r['id'] as String);
      }
    }
    return out;
  }
}
