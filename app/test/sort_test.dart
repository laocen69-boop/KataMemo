import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/data_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await DataRepo(db).ensureImported();
    return db;
  }

  test('四种排序都真的换序，且总数一致', () async {
    final db = await seed();
    const n = 40;
    final alpha = await db.wordsByFilter(null, limit: n, sort: 'alpha');
    final alphaDesc = await db.wordsByFilter(null, limit: n, sort: 'alphaDesc');
    final rank = await db.wordsByFilter(null, limit: n, sort: 'rank');
    final rankDesc = await db.wordsByFilter(null, limit: n, sort: 'rankDesc');

    for (final l in [alpha, alphaDesc, rank, rankDesc]) {
      expect(l.length, n, reason: '每种排序都该取满 $n 条');
    }

    final aWords = [for (final w in alpha) w.word.toLowerCase()];
    final dWords = [for (final w in alphaDesc) w.word.toLowerCase()];
    expect(aWords, orderedEquals(List.of(aWords)..sort()),
        reason: 'alpha 应为字典序升序');
    expect(dWords, orderedEquals((List.of(dWords)..sort()).reversed.toList()),
        reason: 'alphaDesc 应为字典序降序');

    final rUp = [
      for (final w in rank)
        if (w.rank != null) w.rank!
    ];
    final rDown = [
      for (final w in rankDesc)
        if (w.rank != null) w.rank!
    ];
    expect(rUp, orderedEquals(List.of(rUp)..sort()), reason: 'rank 应为升序（高频在前）');
    expect(rDown, orderedEquals((List.of(rDown)..sort()).reversed.toList()),
        reason: 'rankDesc 应为降序（低频在前）');

    expect(rank.first.rank, lessThanOrEqualTo(rank.last.rank ?? 1 << 30));

    final bogus =
        await db.wordsByFilter(null, limit: n, sort: "x'; DROP TABLE words;--");
    expect(bogus.length, n, reason: '非法排序值必须被兜底，不能拼进 SQL');
    expect([for (final w in bogus) w.id], [for (final w in rank) w.id],
        reason: '非法值应等价于默认排序');

    final all = await db.wordsByFilter(null, limit: 1 << 30, sort: 'alpha');
    final all2 = await db.wordsByFilter(null, limit: 1 << 30, sort: 'rankDesc');
    expect(all.length, all2.length, reason: '换序不该改变总条数');
  });
}
