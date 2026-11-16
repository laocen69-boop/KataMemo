import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/ocr_scan.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('数据库读写 + AppState 初始化', () async {
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'makan',
        'word': 'makan',
        'tier': 'core',
        'rank': 10,
        'frequency': 100,
        'word_class': 'v',
        'zh': '吃',
        'senses': 'def=test',
        'enabled': 1,
        'favorite': 0,
      },
    ]);
    final cnt = await db.wordCount();
    expect(cnt, 1);
    final due = await db.dueCards();
    expect(due, isEmpty);

    expect(await db.newWords(limit: 5), isEmpty, reason: 'makan 还没加入记忆，不该被派发');
    await db.planWord(['makan']);
    final fresh = await db.newWords(limit: 5);
    expect(fresh.length, 1);
    expect(fresh.first.word, 'makan');

    await db.setDataVersion(kDataVersion);

    final app = AppState(db);
    await app.init();
    expect(app.ready, true);
    await db.close();
  });

  test('粘贴文本抓词：词库命中 + 同行中文配对', () async {
    final db = AppDb(dbPath: inMemoryDatabasePath);
    Map<String, Object?> row(String id, String word, String tier) => {
          'id': id,
          'word': word,
          'tier': tier,
          'rank': 10,
          'frequency': 100,
          'word_class': 'n',
          'zh': '释义',
          'senses': '',
          'enabled': 1,
          'favorite': 0,
        };
    await db.upsertWords([
      row('makan', 'makan', 't2'),
      row('toko buku', 'toko buku', 'phrase'),
    ]);
    final outcome = await matchPastedText(db, 'makan 吃\ntoko buku 书店');
    expect(outcome.matched.map((m) => m.card.id).toList(),
        containsAll(['makan', 'toko buku']));
    expect(outcome.missed, isEmpty);
    expect(outcome.rowcount, 2);
    await db.close();
  });

  test('词单 ids_json 坏一行只当空词单，不炸整页（第四十四轮全量检测补）', () async {
    final db = AppDb(dbPath: inMemoryDatabasePath);
    final d = await db.db;

    Future<void> insert(String name, String ids) => d.insert(
        'word_list',
        {
          'name': name,
          'ids_json': ids,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    await insert('好的词单', jsonEncode(['makan', 'minum']));
    await insert('坏的词单', '{不是 JSON');
    await insert('空词单', jsonEncode([]));

    final lists = await db.listWordLists();
    expect(lists.length, 3, reason: '三行都在——坏行不删，只是词数按 0 报');
    final byName = {for (final l in lists) l.$2: l};
    expect(byName['好的词单']!.$3, 2);
    expect(byName['坏的词单']!.$3, 0, reason: '坏 JSON 当 0 词，不抛异常');
    expect(byName['空词单']!.$3, 0);
    expect(await db.wordListIds(byName['坏的词单']!.$1), isEmpty,
        reason: '坏词单详情页显示空态，而不是整页崩掉');
    await db.close();
  });

  test('今日前 n 张的构成：按首次作答时间取，复习/新学分桶', () async {
    final db = AppDb(dbPath: inMemoryDatabasePath);
    final d = await db.db;
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    final rows = [
      ('old1', start - 86400000, start + 3600000),
      ('old2', start - 86400000, start + 3900000),
      ('new1', start + 600000, start + 4200000),
      ('new2', start + 600000, start + 4500000),
    ];
    for (final (id, firstSeen, ts) in rows) {
      await d.insert('srs', {
        'card_id': id,
        'first_seen': firstSeen,
        'last_review': ts,
        'due': ts + 86400000,
        'reps': 1,
      });
      await d.insert('study_log', {'card_id': id, 'rating': 3, 'ts': ts});
    }

    expect(await db.todayFirstComposition(3), (review: 2, newCount: 1));

    expect(await db.todayFirstComposition(2), (review: 2, newCount: 0));

    expect(await db.todayFirstComposition(0), (review: 0, newCount: 0));

    expect(await db.todayFirstComposition(99), (review: 2, newCount: 2));

    await db.close();
  });

  test('短语词频筛选轴：phraseTier 只命中对应档，单字不受影响', () async {
    Map<String, Object?> row(String id, String word, String tier,
            {String? pt}) =>
        {
          'id': id,
          'word': word,
          'tier': tier,
          'rank': null,
          'frequency': 0,
          'zh': '测试',
          'enabled': 1,
          'favorite': 0,
          'phrase_tier': pt,
        };

    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      row('p_akan_tetapi', 'akan tetapi', 'phrase', pt: 'p1'),
      row('p_makan_siang', 'makan siang', 'phrase', pt: 'p2'),
      row('p_entah_apa', 'entah apa', 'phrase', pt: 'p3'),
      row('p_kosong', 'tanpa freq', 'phrase'),
      row('w_makan', 'makan', 't2'),
    ]);

    expect(await db.countByFilter({'phraseTier': ['p1']}), 1);
    expect(await db.countByFilter({'phraseTier': ['p2']}), 1);
    expect(await db.countByFilter({'phraseTier': ['p1', 'p3']}), 2);
    expect(await db.countByFilter({'phraseTier': ['p0']}), 0,
        reason: 'p0 没有单独节点，靠「词频未知」走 noFreq');

    final hits = await db.wordsByFilter({'phraseTier': ['p1', 'p2']});
    expect(hits.map((w) => w.id).toSet(), {'p_akan_tetapi', 'p_makan_siang'});

    await db.close();
  });
}
