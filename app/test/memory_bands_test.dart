import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/widgets/memory_ring.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const unstudied = ['u1', 'u2', 'u3', 'u4', 'u5'];
  const boundary = ['w180', 'w1799', 'w60', 'w599', 'w7', 'w69'];
  const enabledCount = 12;

  const paused = 'paused';
  const notEnrolled = ['off1', 'off2'];

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (final id in [
        ...unstudied,
        ...boundary,
        'legacy',
        paused,
        ...notEnrolled
      ])
        {
          'id': id,
          'word': id,
          'rank': 1,
          'tier': id == paused ? 'redup' : 'core',
          'word_class': 'n',
          'zh': id,
          'enabled': id == paused ? 0 : 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);

    await db.planWord([...unstudied, ...boundary, 'legacy']);
    return db;
  }

  Future<void> rate(AppDb db, String id,
          {required double stability, int reps = 3}) =>
      db.saveSrs(
          id,
          FsrsState(
            stability: stability,
            difficulty: 5,
            due: DateTime.now().add(const Duration(days: 1)),
            reps: reps,
          ));

  test('五段之和恒等于在记忆词数（互斥且全覆盖）', () async {
    final db = await seed();
    await rate(db, 'w180', stability: 180);
    await rate(db, 'w60', stability: 60);
    await rate(db, 'w7', stability: 7);
    await rate(db, 'w1799', stability: 699);

    final b = (await db.bookProgress(null)).bands;
    expect(b.mastered, 2, reason: '180 与 699 都 ≥180');
    expect(b.familiar, 1);
    expect(b.fair, 1);
    expect(b.weak, 0, reason: '不熟只剩「学过但 <7 天」，这里没有这种词');
    expect(b.newSel, unstudied.length + 3, reason: '5 个没学过的 + 剩下 3 个没打分的');
    expect(b.all, enabledCount, reason: '五段之和必须等于在记忆里的总数');

    expect(await db.wordCount(), enabledCount + 1 + notEnrolled.length,
        reason: 'wordCount 数全表：比 bands 多 paused 与 off1/off2');
    final bandIds = <String>{};
    for (var i = 0; i < 5; i++) {
      bandIds
          .addAll([for (final w in await db.wordsByBand(i, limit: 500)) w.id]);
    }
    for (final id in [...notEnrolled, paused]) {
      expect(bandIds, isNot(contains(id)), reason: '$id 没在记忆里，一段都不该出现');
    }

    final prog = await db.bookProgress(null);
    expect(prog.all, enabledCount + notEnrolled.length,
        reason: 'all = 可学词数，包含没加入记忆的');
    expect(prog.total, enabledCount, reason: 'total = 在记忆里的词数');
  });

  test('切线是闭开区间：边界值只落一段，不带重叠', () async {
    final db = await seed();
    await rate(db, 'w180', stability: 180);
    await rate(db, 'w599', stability: 179.9);
    await rate(db, 'w60', stability: 60);
    await rate(db, 'w69', stability: 59.9);
    await rate(db, 'w7', stability: 7);
    await rate(db, 'w1799', stability: 6.9);

    final b = (await db.bookProgress(null)).bands;
    expect(b.mastered, 1, reason: '180 进标熟、179.9 不进——闭开区间的左边');
    expect(b.familiar, 2, reason: '179.9 与 60 都算熟悉');
    expect(b.fair, 2, reason: '59.9 与 7 都算一般');
    expect(b.weak, 1, reason: '只有 6.9 落这一档；没学过的不再算进来');
    expect(b.newSel, unstudied.length + 1, reason: '5 个没学过的 + legacy');
    expect(b.all, enabledCount);
  });

  test('reps = 0 算「未学」：建了 srs 行但没答过题，不进任何已学档', () async {
    final db = await seed();

    await rate(db, 'legacy', stability: 300, reps: 0);

    final b = (await db.bookProgress(null)).bands;
    expect(b.mastered, 0, reason: 'reps = 0 不能算标熟——与 MemoryStrength.of() 同口径');
    expect(b.weak, 0, reason: '也不能算「学过但不熟」——它一次都没学过');
    expect(b.newSel, enabledCount, reason: '全库都是「选了还没学」');
    expect(b.all, enabledCount);
  });

  test('条上的数 = 点进去的词数（两份 SQL 用同一套切线）', () async {
    final db = await seed();
    await rate(db, 'w180', stability: 200);
    await rate(db, 'w599', stability: 120);
    await rate(db, 'w69', stability: 20);
    await rate(db, 'w7', stability: 20);
    await rate(db, 'w1799', stability: 3);
    await rate(db, 'w60', stability: 0.5);

    final b = (await db.bookProgress(null)).bands;
    final counts = memoryBandCounts(b);
    expect(counts, [1, 1, 2, 2, 6],
        reason: '标熟 1 · 熟悉 1 · 一般 2 · 不熟 2（3 天与 0.5 天）· 未学 6');

    for (var i = 0; i < 5; i++) {
      final rows = await db.wordsByBand(i, limit: 500);
      expect(rows.length, counts[i],
          reason: '第 $i 档：条上是 ${counts[i]} 个，点进去 ${rows.length} 个'
              '——两份 SQL 的切线写歪了');
    }

    final fresh =
        (await db.wordsByBand(4, limit: 500)).map((w) => w.id).toSet();
    expect(fresh.containsAll(unstudied), isTrue, reason: '一次没学过的词必须取得到');
    expect(fresh.contains('legacy'), isTrue, reason: 'reps = 0 的残留行也在这一档');
    expect(fresh.contains('w60'), isFalse, reason: '学过（哪怕稳定 0.5 天）就不算未学');

    for (var i = 0; i < 5; i++) {
      final ids = (await db.wordsByBand(i, limit: 500)).map((w) => w.id);
      expect(ids, isNot(contains(paused)));
      expect(ids, isNot(containsAll(notEnrolled)));
    }
  });

  test('单库查询 = 批量查询（「已选单词」卡 vs 下面的词组卡片，逐字段）', () async {

    final db = await seed();
    await rate(db, 'w180', stability: 200);
    await rate(db, 'w7', stability: 10);
    const f = {
      'tier': ['core']
    };

    final one = await db.bookProgress(f);
    final batch =
        (await db.bookProgressBatch([(id: 'core', filter: f)]))['core']!;
    expect(batch.all, one.all, reason: '`all`（整本词数）不同 ⇒ 六段条的淡灰那截就不等长');
    expect(batch.total, one.total, reason: '`total`（在记忆词数）不同 ⇒ 五段之和就不等');
    expect(batch.bands, one.bands);
    expect(batch.started, one.started);

    expect(progressBarCounts(batch.bands, batch.all - batch.total),
        progressBarCounts(one.bands, one.all - one.total));

    expect(one.bands.all, one.total,
        reason: 'bands 的五段之和要与 bookProgress 自己的 total 对得上');
    expect(one.all - one.total, notEnrolled.length,
        reason: '未选 = 可学但没加入记忆的那两个（`paused` 是 redup 查词条目，'
            '既不在 filter 的 tier = core 里、也不满足 listVisibleSql）');
  });

  testWidgets('分段条按计数比例分宽，且高度不为 0', (tester) async {

    const counts = [2, 3, 4, 11, 10];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: MemorySegmentBar(counts: counts, height: 8),
          ),
        ),
      ),
    ));

    final f = find.descendant(
        of: find.byType(MemorySegmentBar), matching: find.byType(ColoredBox));
    expect(f, findsNWidgets(5), reason: '五段各一块色');
    final sizes = [for (var i = 0; i < 5; i++) tester.getSize(f.at(i))];
    for (final s in sizes) {
      expect(s.height, 8, reason: '高度 0 = 看不见（ColoredBox 无子节点时取 smallest）');
    }
    for (var i = 0; i < 5; i++) {
      expect(sizes[i].width, closeTo(300 * counts[i] / 30, 1.5));
    }
  });

  testWidgets('六段条：多出的「未选」在最后一格，且用淡灰而不是深灰', (tester) async {

    final counts = progressBarCounts(
        (mastered: 2, familiar: 3, fair: 4, weak: 1, newSel: 10), 10);
    expect(counts.length, 6);
    expect(counts.last, 10, reason: '第六格 = 未选（可学但没加入记忆）');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: MemorySegmentBar(counts: counts, height: 8),
          ),
        ),
      ),
    ));

    final cols = tester
        .widgetList<ColoredBox>(find.descendant(
            of: find.byType(MemorySegmentBar),
            matching: find.byType(ColoredBox)))
        .toList();
    expect(cols.length, 6);

    final ctx = tester.element(find.byType(MemorySegmentBar));

    expect(cols[0].color, kMemorySegmentsOf(ctx)[0].color, reason: '标熟 = 墨绿');
    expect(cols[1].color, kMemorySegmentsOf(ctx)[1].color, reason: '熟悉 = 绿');
    expect(cols[2].color, kMemorySegmentsOf(ctx)[2].color, reason: '一般 = 黄');
    expect(cols[3].color, kMemorySegmentsOf(ctx)[3].color, reason: '不熟 = 红');
    expect(cols[4].color, kMemorySegmentsOf(ctx)[4].color, reason: '已选未学 = 深灰');
    expect(cols[5].color, kUnselectedColor(ctx), reason: '未选未学 = 淡灰');
    expect(cols[4].color, isNot(cols[5].color),
        reason: '「选了没学」和「没选的」必须是两种灰，否则用户分不出');
  });

  testWidgets('空词库：分段条退化成灰条，不留白也不抛异常', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: MemorySegmentBar(counts: [0, 0, 0, 0, 0]),
          ),
        ),
      ),
    ));
    final f = find.descendant(
        of: find.byType(MemorySegmentBar), matching: find.byType(ColoredBox));
    expect(f, findsNothing, reason: '一个词都没有时不该画彩色段');
    expect(tester.getSize(find.byType(MemorySegmentBar)).height, 6,
        reason: '高度仍要占住（默认 6），否则卡片高度会跳');
  });
}
