import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/db.dart';
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

    await db.upsertWords([
      for (final id in ['w-alfa', 'w-beta'])
        {
          'id': id,
          'word': id == 'w-alfa' ? 'Tesalfa' : 'tesbeta',
          'tier': 't1',
          'rank': 1,
          'frequency': 100,
          'word_class': 'n',
          'zh': '词$id',
          'senses': 'def=x',
          'enabled': 1,
          'favorite': 0,
          'user_word': 0,
        },
    ]);
    addTearDown(() => db.close());
    return db;
  }

  Future<int> _wordCount(AppDb db) async {
    final d = await db.db;
    final r = await d.rawQuery('SELECT COUNT(*) AS c FROM words');
    return r.first['c'] as int;
  }

  List<ImportEntry> sampleEntries() => const [
        ImportEntry(
          lemma: 'tesalfa',
          pronunciation: 'te-sal-fa',
          senses: [
            ImportSense(
              pos: 'n',
              definition: '测试义项甲',
              examples: [ImportExample(text: '例句一', translation: '译一')],
            ),
          ],
        ),
        ImportEntry(
          lemma: 'tesgamma',
          homographIndex: 2,
          senses: [ImportSense(definition: '义丙')],
        ),
      ];

  group('释义序列化', () {
    test('编码后再解码，内容不变（含译文为空的例句）', () {
      const senses = [
        ImportSense(
          pos: 'v',
          definition: '义甲',
          examples: [
            ImportExample(text: 'ex1', translation: '译1'),
            ImportExample(text: 'ex2'),
          ],
        ),
        ImportSense(definition: '义乙'),
      ];
      final back = decodeDictSenses(encodeDictSenses(senses));
      expect(back.length, 2);
      expect(back[0].pos, 'v');
      expect(back[0].examples[0].translation, '译1');
      expect(back[0].examples[1].translation, isNull);
      expect(back[1].pos, isNull);
      expect(back[1].definition, '义乙');
    });

    test('格式不对的 JSON 抛 FormatException，不会静默返回空', () {
      expect(() => decodeDictSenses('{"x":1}'), throwsA(isA<FormatException>()));
      expect(() => decodeDictSenses('[1,2]'), throwsA(isA<FormatException>()));
    });
  });

  group('导入、查词、启用与删除', () {
    test('写入后能列出词典，并按折叠后的词头查到条目', () async {
      final db = await openDb();
      final sid = await db.dictWriteImport(
        name: 'test.csv',
        format: 'CSV',
        entries: sampleEntries(),
      );
      final sources = await db.dictSources();
      expect(sources.length, 1);
      expect(sources.first.id, sid);
      expect(sources.first.entryCount, 2);
      expect(sources.first.enabled, isTrue);

      final hits = await db.dictLookup(dictFold('TesAlfa'));
      expect(hits.length, 1);
      expect(hits.first.sourceName, 'test.csv');
      expect(hits.first.entry.senses.first.definition, '测试义项甲');
      expect(hits.first.entry.senses.first.examples.first.translation, '译一');
      expect(hits.first.entry.pronunciation, 'te-sal-fa');
    });

    test('同形序号保存下来', () async {
      final db = await openDb();
      await db.dictWriteImport(name: 'h.csv', format: 'CSV', entries: sampleEntries());
      final hits = await db.dictLookup('tesgamma');
      expect(hits.single.entry.homographIndex, 2);
    });

    test('停用后查词不返回；重新启用后恢复', () async {
      final db = await openDb();
      final sid = await db.dictWriteImport(
        name: 'a.json',
        format: 'JSON',
        entries: sampleEntries(),
      );
      await db.dictSetEnabled(sid, false);
      expect(await db.dictLookup('tesalfa'), isEmpty);
      expect((await db.dictSources()).first.enabled, isFalse);

      await db.dictSetEnabled(sid, true);
      expect((await db.dictLookup('tesalfa')).length, 1);
    });

    test('删除只删本词典的条目，其它词典与 words 表不受影响', () async {
      final db = await openDb();
      final wordsBefore = await _wordCount(db);
      final a = await db.dictWriteImport(name: 'a', format: 'CSV', entries: sampleEntries());
      await db.dictWriteImport(
        name: 'b',
        format: 'CSV',
        entries: const [ImportEntry(lemma: 'tesalfa', senses: [ImportSense(definition: '另一个义')])],
      );

      await db.dictDelete(a);
      final left = await db.dictSources();
      expect(left.map((s) => s.name), ['b']);

      final hits = await db.dictLookup('tesalfa');
      expect(hits.length, 1);
      expect(hits.first.sourceName, 'b');
      expect(await db.dictLookup('tesgamma'), isEmpty);
      expect(await _wordCount(db), wordsBefore);
    });
  });

  group('映照（只读）', () {
    test('能把折叠词头对应到 words 表的 id；没有的词头不出现', () async {
      final db = await openDb();
      final map = await db.dictAlignWordIds(['tesalfa', 'tesbeta', 'tesnone']);
      expect(map['tesalfa'], ['w-alfa']);
      expect(map['tesbeta'], ['w-beta']);
      expect(map.containsKey('tesnone'), isFalse);
    });

    test('映照不写入任何数据', () async {
      final db = await openDb();
      await db.dictAlignWordIds(['tesalfa']);
      expect(await db.dictSources(), isEmpty);
    });

    test('词头超过 2000 个走整表对照，结果与分块查一致（2026-11-06）', () async {
      final db = await openDb();
      final many = ['tesalfa', 'tesbeta', for (var i = 0; i < 3000; i++) 'none$i'];
      final map = await db.dictAlignWordIds(many);
      expect(map['tesalfa'], ['w-alfa']);
      expect(map['tesbeta'], ['w-beta']);
      expect(map.length, 2);
    });
  });

  group('大词典（2026-11-06：导入不限条数）', () {
    test('5000 条分块写入：一条不少，事务整体提交', () async {
      final db = await openDb();
      final entries = [
        for (var i = 0; i < 5000; i++)
          ImportEntry(lemma: 'big$i', senses: [ImportSense(definition: '义$i')]),
      ];
      await db.dictWriteImport(name: 'big.csv', format: 'CSV', entries: entries);
      final d = await db.db;
      final n = (await d.rawQuery('SELECT COUNT(*) AS c FROM dict_entry')).first['c'];
      expect(n, 5000);
      expect((await db.dictSources()).single.entryCount, 5000);
      expect((await db.dictLookup('big4999')).single.entry.senses.single.definition,
          '义4999');
    });
  });
}
