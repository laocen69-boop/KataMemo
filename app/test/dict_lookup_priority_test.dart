import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/dict_import/dict_kind.dart';
import 'package:katamemo/dict_import/dict_model.dart';
import 'package:katamemo/dict_import/dict_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> openDb() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    addTearDown(() => db.close());
    return db;
  }

  const entry = [
    ImportEntry(
      lemma: 'tesalfa',
      senses: [ImportSense(definition: '某一条释义')],
    ),
  ];

  test('KBBI 排在更晚导入的普通词典前面', () async {
    final db = await openDb();

    final kbbiId = await db.dictWriteImport(
        name: 'kbbi_v6.csv', format: 'CSV', entries: entry);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await db.dictWriteImport(
        name: '我的笔记.csv', format: 'CSV', entries: entry);
    await db.dictSetKind(
        kbbiId,
        const DictKindInfo(
            kind: DictKind.kbbi, byUser: false, evidence: ['文件名写明 KBBI']));

    final hits = await db.dictLookup('tesalfa');
    expect(hits.length, 2);
    expect(hits.first.sourceName, 'kbbi_v6.csv');
    expect(hits.first.isKbbi, isTrue);
    expect(hits.last.isKbbi, isFalse);
  });

  test('没标过 KBBI 时保持原来的「最近导入在前」', () async {
    final db = await openDb();
    await db.dictWriteImport(
        name: '先导入.csv', format: 'CSV', entries: entry);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await db.dictWriteImport(
        name: '后导入.csv', format: 'CSV', entries: entry);
    final hits = await db.dictLookup('tesalfa');
    expect(hits.first.sourceName, '后导入.csv');
  });

  test('学生手动改判后，自动识别不再覆盖', () async {
    final db = await openDb();
    final id = await db.dictWriteImport(
        name: '随手记.csv', format: 'CSV', entries: entry);
    await db.dictSetKind(
        id,
        const DictKindInfo(
            kind: DictKind.kbbi, byUser: true, evidence: ['学生手动指定']));
    final info = await db.dictAutoKind(
      id,
      name: '随手记.csv',
      sample: entry,
      totalEntries: 1,
    );
    expect(info.kind, DictKind.kbbi);
    expect(info.byUser, isTrue);
  });

  test('自动识别能落盘并被 dictKinds 读回', () async {
    final db = await openDb();
    final id = await db.dictWriteImport(
        name: 'kbbi_edisiIV.csv', format: 'CSV', entries: entry);
    final info = await db.dictAutoKind(
        id, name: 'kbbi_edisiIV.csv', sample: entry, totalEntries: 1);
    expect(info.isKbbi, isTrue);
    expect((await db.dictKinds())[id]!.isKbbi, isTrue);
  });

  test('删除词典时来源标记一起清掉', () async {
    final db = await openDb();
    final id = await db.dictWriteImport(
        name: 'kbbi.csv', format: 'CSV', entries: entry);
    await db.dictAutoKind(id, name: 'kbbi.csv', sample: entry);
    expect((await db.dictKinds())[id], isNotNull);
    await db.dictDelete(id);
    expect((await db.dictKinds())[id], isNull);
  });
}
