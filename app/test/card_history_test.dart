import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'kiri',
        'word': 'kiri',
        'tier': 't1',
        'rank': 1,
        'zh': '左边',
        'enabled': 1,
        'favorite': 0,
      },
    ]);
    await db.setDataVersion(kDataVersion);
    return db;
  }

  Future<int> logAt(AppDb db, String cardId, int rating, DateTime t) async {
    final raw = await db.db;
    return raw.insert('study_log', {
      'card_id': cardId,
      'rating': rating,
      'ts': t.millisecondsSinceEpoch,
    });
  }

  test('一天一条：D 序号按日历走，颜色取当天第一次', () async {
    final db = await seed();
    final now = DateTime.now();

    final anchor = DateTime(now.year, now.month, now.day, 12);
    final d1 = anchor.subtract(const Duration(days: 3));

    await logAt(db, 'kiri', 0, d1);
    await logAt(db, 'kiri', 2, d1.add(const Duration(minutes: 1)));
    await logAt(db, 'kiri', 2, d1.add(const Duration(minutes: 2)));

    await logAt(db, 'kiri', 1, anchor.subtract(const Duration(days: 1)));

    await logAt(db, 'kiri', 2, anchor);
    await logAt(db, 'kiri', 1, anchor.add(const Duration(minutes: 1)));

    final h = await db.cardHistory('kiri');
    expect(h.logs, 6, reason: '表头那句「记忆 N 次」数的是总作答次数');
    expect(h.days.length, 3, reason: '学了三天 → 三格');
    expect(h.days[0].dayNo, 1);
    expect(h.days[0].rating, 0, reason: '第一天第一条是「困难」⇒ 红色');
    expect(h.days[1].dayNo, 3, reason: 'D 序号按日历跳（中间没学的那天不补格）');
    expect(h.days[2].dayNo, 4);
    expect(h.days[2].rating, 2, reason: '今天第一条是「认识」⇒ 绿色');
    expect(h.todayExtra, [1], reason: '今天第 2 次点的是「模糊」⇒ 一个不带标签的方块');

    await db.close();
  });

  test('撤销后这一栏跟着变（勾稽：只认 study_log）', () async {
    final db = await seed();
    final now = DateTime.now();
    final anchor = DateTime(now.year, now.month, now.day, 12);
    await logAt(db, 'kiri', 2, anchor);
    final second =
        await logAt(db, 'kiri', 0, anchor.add(const Duration(minutes: 1)));
    expect((await db.cardHistory('kiri')).todayExtra, [0]);

    await db.deleteLog(second);
    final h = await db.cardHistory('kiri');
    expect(h.todayExtra, isEmpty, reason: '撤掉之后今天只剩第一次，没有小方块');
    expect(h.logs, 1);
    expect(h.days.single.rating, 2, reason: '颜色回到那条「认识」');
    await db.close();
  });

  test('没学过 → 空历史（卡片上整栏不显示）', () async {
    final db = await seed();
    final h = await db.cardHistory('kiri');
    expect(h.days, isEmpty);
    expect(h.logs, 0);
    expect(h.todayExtra, isEmpty);
    await db.close();
  });
}
