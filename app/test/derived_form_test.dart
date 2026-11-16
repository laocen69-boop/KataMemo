library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/derived_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('derivedParses（纯函数）', () {
    test('-kan 优先于 -i；词根与后缀拆对', () {
      final p = derivedParses('tiriskan');
      expect(p, hasLength(1));
      expect(p.single.root, 'tiris');
      expect(p.single.suffix, 'kan');
      expect(p.single.equation, 'tiriskan = tiris + -kan');
    });

    test('-i 形式', () {
      final p = derivedParses('taburi');
      expect(p.single.root, 'tabur');
      expect(p.single.suffix, 'i');
    });

    test('短词根 / 不以后缀结尾 → 空', () {
      expect(derivedParses('kan'), isEmpty);
      expect(derivedParses('ini'), isEmpty);
      expect(derivedParses('makan'), isEmpty);
    });
  });

  group('searchWordWithMorph（查库）', () {
    Future<AppDb> seed() async {
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await db.upsertWords([
        for (final id in ['tiris', 'tabur', 'makan'])
          {
            'id': id,
            'word': id,
            'tier': 't5',
            'rank': 1,
            'frequency': 1,
            'word_class': 'v',
            'zh': '义$id',
            'senses': 'def=$id',
            'enabled': 1,
            'favorite': 0,
          },
      ]);
      await db.setDataVersion(kDataVersion);
      return db;
    }

    test('tiriskan → tiris（-kan）', () async {
      final db = await seed();
      final r = await db.searchWordWithMorph('tiriskan');
      expect(r.card?.id, 'tiris');
      expect(r.derived?.suffix, 'kan');
      await db.close();
    });

    test('taburi → tabur（-i）', () async {
      final db = await seed();
      final r = await db.searchWordWithMorph('taburi');
      expect(r.card?.id, 'tabur');
      expect(r.derived?.suffix, 'i');
      await db.close();
    });

    test('词根不在库时不瞎拆（matahari）', () async {
      final db = await seed();
      final r = await db.searchWordWithMorph('matahari');
      expect(r.card, isNull);
      expect(r.derived, isNull);
      await db.close();
    });
  });
}
