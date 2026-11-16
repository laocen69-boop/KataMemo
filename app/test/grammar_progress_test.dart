library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/backup_pack.dart';
import 'package:katamemo/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _tmp(String tag) =>
    '${Directory.systemTemp.path}/katamemo_$tag'
    '_${DateTime.now().microsecondsSinceEpoch}.db';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('路径①全新安装（_onCreate）就建得出 grammar_progress', () async {
    final db = AppDb(dbPath: _tmp('new'));
    final d = await db.db;
    final rows = await d.query('grammar_progress');
    expect(rows, isEmpty);
    expect(await db.grammarProgress('c-2.3-1'), isNull);
    await db.close();
  });

  test('路径②18 → 19 升级也建得出（老库只走 _onUpgrade）', () async {
    final path = _tmp('up');

    final db1 = AppDb(dbPath: path);
    final d1 = await db1.db;
    await d1.execute('DROP TABLE IF EXISTS grammar_progress');
    await d1.execute('PRAGMA user_version = 18');
    await db1.close();

    final db2 = AppDb(dbPath: path);
    final d2 = await db2.db;
    await d2.query('grammar_progress');
    await db2.markGrammarSeen('c-2.3-2');
    await db2.flushGrammarWrites();
    expect((await db2.grammarProgress('c-2.3-2'))!.seen, isTrue);
    await db2.close();
  });

  test('路径③重导词库（clearWords）后进度行仍在', () async {
    final db = AppDb(dbPath: _tmp('reimport'));
    await db.upsertWords([
      {'id': 'menulis', 'word': 'menulis', 'tier': 't1', 'enabled': 1},
    ]);
    await db.markGrammarSeen('c-2.3-1');
    await db.setGrammarStarred('c-2.3-1', true);
    await db.flushGrammarWrites();

    await db.clearWords();

    final p = await db.grammarProgress('c-2.3-1');
    expect(p, isNotNull, reason: '清词库不许碰 grammar_progress');
    expect(p!.starred, isTrue);
    expect(p.seenAt, isNotNull);
    await db.close();
  });

  test('读写：markSeen / toggleStar / recordDrill 累计；debounce 由 flush 落盘', () async {
    final db = AppDb(dbPath: _tmp('rw'));
    await db.markGrammarSeen('c-2.3-1', at: 1000);
    await db.setGrammarStarred('c-2.3-1', true);
    await db.recordGrammarDrill('c-2.3-1', true);
    await db.recordGrammarDrill('c-2.3-1', false);
    await db.flushGrammarWrites();
    final p = await db.grammarProgress('c-2.3-1');
    expect(p!.seenAt, 1000);
    expect(p.starred, isTrue);
    expect(p.drillOk, 1);
    expect(p.drillTotal, 2);

    await db.setGrammarStarred('c-2.3-1', false);
    await db.flushGrammarWrites();
    expect((await db.grammarProgress('c-2.3-1'))!.starred, isFalse);

    await db.setGrammarLastCard('c-2.3-5');
    await db.setGrammarFilter('core');
    await db.flushGrammarWrites();
    expect(await db.grammarLastCard(), 'c-2.3-5');
    expect(await db.grammarFilter(), 'core');
    await db.close();
  });

  test('备份：导出再导入 —— seen_at 取大 / starred 取或 / drill_* 取大', () async {
    final a = AppDb(dbPath: _tmp('packA'));
    await a.markGrammarSeen('c-2.3-1', at: 5000);
    await a.setGrammarStarred('c-2.3-1', true);
    await a.recordGrammarDrill('c-2.3-1', true);
    await a.flushGrammarWrites();
    final ad = await a.db;
    final pack = jsonDecode(jsonEncode(await BackupPack.export(ad,
        schemaVersion: kSchemaVersion,
        dataVersion: kDataVersion,
        appVersion: 'test'))) as Map<String, Object?>;
    expect(pack['grammarProgress'], isA<List>());
    await a.close();

    final b = AppDb(dbPath: _tmp('packB'));
    await b.markGrammarSeen('c-2.3-1', at: 9000);
    await b.recordGrammarDrill('c-2.3-1', false);
    await b.flushGrammarWrites();
    final bd = await b.db;
    await bd.transaction((t) =>
        BackupPack.import(t, pack, localSchemaVersion: kSchemaVersion));

    final p = await b.grammarProgress('c-2.3-1');
    expect(p!.seenAt, 9000, reason: 'seen_at 取大 —— 本地更新，不许被包里的旧值盖回去');
    expect(p.starred, isTrue, reason: 'starred 取或');
    expect(p.drillTotal, 1, reason: 'drill_total 取大（本地 1 / 包里 1）');
    expect(p.drillOk, 1, reason: 'drill_ok 取大（本地 0 / 包里 1）');
    await b.close();
  });
}
