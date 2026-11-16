import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/backup_pack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _schema = [
  'CREATE TABLE words (id TEXT PRIMARY KEY, word TEXT, user_word INTEGER DEFAULT 0, favorite INTEGER DEFAULT 0, enabled INTEGER DEFAULT 1, zh TEXT)',
  'CREATE TABLE srs (card_id TEXT PRIMARY KEY, stability REAL DEFAULT 0, difficulty REAL DEFAULT 5, due INTEGER, last_review INTEGER, reps INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0, state INTEGER DEFAULT 0, step INTEGER DEFAULT 0, first_seen INTEGER)',
  'CREATE TABLE study_log (id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT, rating INTEGER, ts INTEGER)',
  'CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT)',
  'CREATE TABLE plan (card_id TEXT PRIMARY KEY, ts INTEGER NOT NULL)',
  'CREATE TABLE user_edit (card_id TEXT NOT NULL, field TEXT NOT NULL, value TEXT, ts INTEGER, PRIMARY KEY (card_id, field))',
  'CREATE TABLE word_list (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, ids_json TEXT NOT NULL, created_at INTEGER)',

  'CREATE TABLE grammar_progress (card_id TEXT PRIMARY KEY, seen_at INTEGER, starred INTEGER NOT NULL DEFAULT 0, drill_ok INTEGER NOT NULL DEFAULT 0, drill_total INTEGER NOT NULL DEFAULT 0)',

  'CREATE TABLE grammar_edit (scope TEXT NOT NULL, page_id TEXT NOT NULL, block_key TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, ts INTEGER NOT NULL, PRIMARY KEY (scope, page_id, block_key))',
];

Future<Database> _mk(String tag) async {
  final path = '${Directory.systemTemp.path}'
      '/km_backup_${tag}_${DateTime.now().microsecondsSinceEpoch}.db';
  final db = await databaseFactoryFfi.openDatabase(path);
  addTearDown(() => databaseFactoryFfi.deleteDatabase(path));
  for (final s in _schema) {
    await db.execute(s);
  }
  for (var i = 1; i <= 5; i++) {
    await db.insert('words', {'id': 'w$i', 'word': 'kata$i'});
  }
  return db;
}

void main() {
  sqfliteFfiInit();
  test('导出→过 JSON→合并导入：规则、幂等、孤儿、拒绝新版本', () async {
    final a = await _mk('a'), b = await _mk('b');
    await a.insert(
        'words', {'id': 'u1', 'word': 'saya', 'user_word': 1, 'zh': '我'});
    await a.update('words', {'favorite': 1}, where: "id='w2'");
    for (final r in [
      ['w1', 5, 4, 9000, 5000, 3, 0, 2, 0, 1000],
      ['w2', 2, 5, 8000, 4000, 2, 1, 2, 0, 900],
      ['u1', 1, 5, 7000, 3000, 1, 0, 1, 1, 3000],
      ['ghost', 1, 5, 1, 1, 1, 0, 2, 0, 1],
    ]) {
      await a.insert('srs', {
        'card_id': r[0],
        'stability': r[1],
        'difficulty': r[2],
        'due': r[3],
        'last_review': r[4],
        'reps': r[5],
        'lapses': r[6],
        'state': r[7],
        'step': r[8],
        'first_seen': r[9],
      });
    }
    for (final r in [
      ['w1', 2, 1000],
      ['w1', 3, 5000],
      ['w2', 0, 900],
      ['u1', 1, 3000],
      ['ghost', 2, 1]
    ]) {
      await a
          .insert('study_log', {'card_id': r[0], 'rating': r[1], 'ts': r[2]});
    }
    await a.insert('plan', {'card_id': 'w3', 'ts': 777});
    await a.insert(
        'user_edit', {'card_id': 'w1', 'field': 'zh', 'value': '旧', 'ts': 100});
    await a.insert(
        'user_edit', {'card_id': 'w2', 'field': 'zh', 'value': '甲', 'ts': 50});
    await a.insert(
        'word_list', {'name': '清单', 'ids_json': '["w1"]', 'created_at': 1});
    for (final m in [
      ['new_quota', '40'],
      ['checkin:2026-10-01', '1'],
      ['onboard_seen', '1'],
      ['fsrs_w', '[1]']
    ]) {
      await a.insert('meta', {'k': m[0], 'v': m[1]});
    }
    final pack = jsonDecode(jsonEncode(await BackupPack.export(a,
        schemaVersion: 17,
        dataVersion: 64,
        appVersion: 't'))) as Map<String, Object?>;

    await b.insert('srs', {
      'card_id': 'w1',
      'stability': 9,
      'difficulty': 3,
      'due': 99999,
      'last_review': 6000,
      'reps': 4,
      'lapses': 0,
      'state': 2,
      'step': 0,
      'first_seen': 2000
    });
    await b.insert('study_log', {'card_id': 'w1', 'rating': 3, 'ts': 5000});
    await b.insert(
        'user_edit', {'card_id': 'w1', 'field': 'zh', 'value': '新', 'ts': 200});
    await b.insert(
        'word_list', {'name': '清单', 'ids_json': '["w5"]', 'created_at': 2});
    await b.insert('meta', {'k': 'new_quota', 'v': '10'});

    final rep = await b
        .transaction((t) => BackupPack.import(t, pack, localSchemaVersion: 17));
    expect(rep.unmatchedSample, ['ghost']);

    expect(
        (await b.rawQuery(
                "SELECT stability, first_seen FROM srs WHERE card_id='w1'"))
            .first,
        {'stability': 9, 'first_seen': 1000});
    expect(
        (await b.rawQuery(
                "SELECT COUNT(*) c FROM study_log WHERE card_id='w1'"))
            .first['c'],
        2);
    expect(
        (await b.rawQuery("SELECT value FROM user_edit WHERE card_id='w1'"))
            .first['value'],
        '新');
    expect(
        (await b.rawQuery("SELECT v FROM meta WHERE k='new_quota'")).first['v'],
        '40');
    expect(
        (await b.rawQuery("SELECT COUNT(*) c FROM meta WHERE k='onboard_seen'"))
            .first['c'],
        0);
    expect(
        (await b.rawQuery('SELECT COUNT(*) c FROM word_list')).first['c'], 2);

    final before =
        (await b.rawQuery('SELECT COUNT(*) c FROM study_log')).first['c'];
    final rep2 = await b
        .transaction((t) => BackupPack.import(t, pack, localSchemaVersion: 17));
    expect(rep2.logAdded, 0);
    expect(rep2.listAdded, 0);
    expect((await b.rawQuery('SELECT COUNT(*) c FROM study_log')).first['c'],
        before);

    pack['schemaVersion'] = 99;
    expect(
        () => b.transaction(
            (t) => BackupPack.import(t, pack, localSchemaVersion: 17)),
        throwsA(isA<PackException>()));
  });
}
