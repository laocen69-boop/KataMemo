import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  TodayPlan plan({
    int quota = 20,
    int newDone = 0,
    int reviewDone = 0,
    int newPending = 0,
    int reviewPending = 0,
    int reviewBacklog = 0,
    int poolLeft = 0,
  }) =>
      todayPlanOf(
          quota: quota,
          newDone: newDone,
          reviewDone: reviewDone,
          newPending: newPending,
          reviewPending: reviewPending,
          reviewBacklog: reviewBacklog,
          poolLeft: poolLeft);

  test('复习分母夹在额度内：积压 550 张时显示 20，不是 565', () {
    final p =
        plan(quota: 20, reviewDone: 13, reviewPending: 2, reviewBacklog: 550);
    expect(p.reviewPlan, 565, reason: 'reviewPlan 含积压：13 + 2 + 550');
    expect(p.reviewShown, 20,
        reason: '今天真正会排的复习张数 = min(565, 额度 20) —— 界面上要显示这个');

    final q = plan(quota: 100, reviewDone: 3, reviewBacklog: 10);
    expect(q.reviewShown, 13, reason: '13 < 100 ⇒ 分母就是 13');
  });

  group('todayPlanOf：分母不跳、分子不重复', () {
    test('新词点「困难」回队：分母和角标都不动，只有过了才动', () {

      final a = plan(newPending: 1, poolLeft: 9);

      final b = plan(newDone: 1, poolLeft: 9);

      expect(a.newPlan, 10, reason: '开学的卡不进池子了，但仍然是今天的任务');
      expect(b.newPlan, 10, reason: '★ 答一张只把 x 往上推，y 不许动');
      expect(a.finished, 0, reason: '困难没过关，进度分子不涨');
      expect(b.finished, 1);
      expect(a.taskLeft, 10);
      expect(b.taskLeft, 9, reason: '只有「彻底过了」才让角标掉一格');
    });

    test('复习积压吃掉额度：新学名额 0，角标只到额度（「复习超过了也不行」）', () {
      final p = plan(quota: 50, reviewBacklog: 200, poolLeft: 30);
      expect(p.reviewPlan, 200);
      expect(p.newPlan, 0, reason: '复习优先占额度，新词拿剩下的 = 0');
      expect(p.taskTotal, 50, reason: '角标不能写 200——今天最多答 50 张');
      expect(p.taskLeft, 50);

      final q =
          plan(quota: 50, reviewDone: 50, reviewBacklog: 150, poolLeft: 30);
      expect(q.finished, 50);
      expect(q.taskTotal, 50);
      expect(q.taskLeft, 0, reason: '额度内的活干完了，角标该消失');
    });

    test('池子空了 ≠ 额度不够：今天真清完了 taskLeft 归 0', () {

      final p = plan(quota: 100, newDone: 2);
      expect(p.newPlan, 2, reason: '今天的新学任务不超过真有得学的词数');
      expect(p.taskTotal, 2, reason: '不是 100——额度不是任务');
      expect(p.taskLeft, 0);
    });

    test('额度 0：一张都不排（复习也不行）', () {
      final p = plan(quota: 0, reviewBacklog: 7, poolLeft: 7);
      expect(p.reviewPlan, 7, reason: '积压还在，只是今天不排');
      expect(p.taskTotal, 0);
      expect(p.taskLeft, 0);
      expect(p.newPlan, 0);
    });

    test('不变式：任何分子都不许大于自己的分母（含「当天把额度往低调」）', () {

      final p = plan(
          quota: 5, newDone: 8, reviewDone: 5, reviewBacklog: 30, poolLeft: 40);
      expect(p.finished, 13);
      expect(p.quota, 5, reason: '额度原值还在，界面上别拿它当分母');
      expect(p.quotaShown, 13, reason: '★ 分母抬到已经过掉的数量');
      expect(p.newPlan, greaterThanOrEqualTo(p.newDone));
      expect(p.reviewPlan, greaterThanOrEqualTo(p.reviewDone));
      expect(p.taskTotal, greaterThanOrEqualTo(p.finished));
      expect(p.taskLeft, 0, reason: '额度早已用尽，今天不再排卡');

      for (final q in [0, 1, 5, 20, 500, 9999]) {
        for (final r in [0, 3, 12, 60]) {
          for (final n in [0, 2, 9]) {
            final s = plan(
                quota: q,
                newDone: n,
                reviewDone: r,
                newPending: 1,
                reviewPending: 2,
                reviewBacklog: r,
                poolLeft: n * 3);
            expect(s.finished, lessThanOrEqualTo(s.quotaShown),
                reason: 'quota=$q reviewDone=$r newDone=$n');
            expect(s.newDone, lessThanOrEqualTo(s.newPlan));
            expect(s.reviewDone, lessThanOrEqualTo(s.reviewPlan));
            expect(s.taskLeft, lessThanOrEqualTo(s.taskTotal));
            expect(s.taskTotal, lessThanOrEqualTo(s.quotaShown));
          }
        }
      }
    });
  });

  Map<String, Object?> row(int i) => {
        'id': 'w$i',
        'word': 'w$i',
        'tier': 'core',
        'rank': i,
        'zh': '释义$i',
        'enabled': 1,
        'favorite': 0,
      };

  Future<AppDb> seed(int n) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([for (var i = 1; i <= n; i++) row(i)]);
    await db.setDataVersion(kDataVersion);
    await db.planWord([for (var i = 1; i <= n; i++) 'w$i']);
    return db;
  }

  Future<void> put(AppDb db, String id,
      {required DateTime firstSeen,
      DateTime? lastReview,
      required DateTime due}) async {
    final s = FsrsState(
        state: FsrsState.review, reps: 3, lastReview: lastReview, due: due);
    await db.saveSrs(id, s);
    final d = await db.db;
    await d.update('srs', {'first_seen': firstSeen.millisecondsSinceEpoch},
        where: 'card_id = ?', whereArgs: [id]);
  }

  DateTime daysAgo(int n) =>
      DateTime.now().subtract(Duration(days: n, hours: 1));
  DateTime inDays(int n) => DateTime.now().add(Duration(days: n));

  DateTime dueStillToday() {
    final n = DateTime.now();
    final endOfDay = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
    final soon = n.add(const Duration(minutes: 10));
    return soon.isBefore(endOfDay) ? soon : endOfDay;
  }

  test('五个桶互斥：每张卡只落一处，进度不会重复涨', () async {
    final db = await seed(6);
    final t = DateTime.now();

    await put(db, 'w1', firstSeen: t, due: inDays(2), lastReview: t);

    await put(db, 'w2', firstSeen: t, due: dueStillToday(), lastReview: t);

    await put(db, 'w3', firstSeen: daysAgo(30), due: inDays(4), lastReview: t);

    await put(db, 'w4',
        firstSeen: daysAgo(30),
        due: t.subtract(const Duration(minutes: 5)),
        lastReview: t);

    await put(db, 'w5',
        firstSeen: daysAgo(30), due: t.subtract(const Duration(hours: 2)));

    await put(db, 'w6',
        firstSeen: daysAgo(30), due: inDays(7), lastReview: daysAgo(10));

    final p = await db.todayPlan(dailyQuota: 100);
    expect(p.newDone, 1);
    expect(p.newPending, 1);
    expect(p.reviewDone, 1);
    expect(p.reviewPending, 1);
    expect(p.reviewBacklog, 1);
    expect(p.finished, 2, reason: 'w1 + w3：今天彻底过了的两张');
    expect(p.reviewPlan, 3, reason: 'w3 + w4 + w5');
    expect(p.newPlan, 2, reason: 'w1 + w2，池子里已经没有未开学的词了');
    expect(p.taskTotal, 5);
    expect(p.taskLeft, 3, reason: '5 张任务 − 2 张已过');

    await db.close();
  });

  test('同一张卡今天答三次，只算一张进度（作答张数会算成三张）', () async {
    final db = await seed(3);
    const id = 'w1';

    FsrsState? prev = await db.getSrs(id);
    for (final r in [Fsrs.ratingForget, Fsrs.ratingForget, Fsrs.ratingKnow]) {
      final next = Fsrs.apply(prev, r);
      await db.saveSrs(id, next);
      await db.logRating(id, r);
      prev = next;
    }

    expect(await db.todayLogCount(), 3, reason: '作答了 3 次');
    final p = await db.todayPlan(dailyQuota: 10);
    expect(p.finished, lessThanOrEqualTo(1),
        reason: '★ 进度只按「这张卡过了没有」算，一次都不许多算');
    expect(p.newDone + p.newPending + p.reviewDone + p.reviewPending, 1,
        reason: '它只在一个桶里（学步没毕业就留在 np，毕业了就进 nd）');
    expect(p.newDone + p.newPending, lessThanOrEqualTo(p.newPlan));
    expect(p.finished, lessThanOrEqualTo(p.quotaShown),
        reason: '用户报的「y 大于 x」在这里钉死');

    await db.close();
  });

  test('点「困难」不会让「今天还有多少复习」跳（旧口径在这里跳）', () async {

    final db = await seed(1);
    await put(db, 'w1',
        firstSeen: daysAgo(30),
        due: DateTime.now().subtract(const Duration(hours: 1)));

    final before = await db.todayPlan(dailyQuota: 10);
    expect(before.reviewPlan, 1);
    expect(before.taskLeft, 1);

    final s = (await db.getSrs('w1'))!;
    s.due = dueStillToday();
    s.lastReview = DateTime.now();
    await db.saveSrs('w1', s);

    final after = await db.todayPlan(dailyQuota: 10);
    expect(after.reviewPlan, 1, reason: '★ 分母不动');
    expect(after.taskLeft, 1, reason: '★ 角标不动（今天它仍然欠着一次作答）');
    expect(after.finished, 0, reason: '没过关就不许涨进度');
    expect(after.reviewPlan - after.reviewDone, 1,
        reason: '★ 「今天还有多少复习」= 1：旧 dueCount 的口径在这里会跳成 0，'
            '而它唯一的出口现在是 TodayPlan');

    await db.close();
  });

  test('乙：今天晚些到点的卡，上午就排得进来（队列与 TodayPlan 同一条切线）', () async {
    final db = await seed(2);

    final late = dueStillToday();
    await put(db, 'w1', firstSeen: daysAgo(5), due: late);
    expect(late.isAfter(DateTime.now()), isTrue,
        reason: '前提：它此刻还没到点，否则这条用例测不到东西');

    final plan = await db.todayPlan(dailyQuota: 10);
    expect(plan.reviewPlan, 1, reason: 'TodayPlan 一直把「今天之内到期」算进任务');

    final q = await db.buildSessionQueue(dailyQuota: 10);
    expect(q.due.map((w) => w.id), contains('w1'),
        reason: '★ 队列必须也取得到它 —— 旧判据（`due <= 此刻`）下这里是空的，'
            '完成页会据此说「今天没有到期复习」');

    await db.close();
  });

  test('复习积压超过额度：新学分母被压到 0，角标封顶在额度', () async {
    final db = await seed(9);

    for (var i = 1; i <= 3; i++) {
      await put(db, 'w$i',
          firstSeen: daysAgo(20),
          due: DateTime.now().subtract(const Duration(hours: 1)));
    }
    final p = await db.todayPlan(dailyQuota: 2);
    expect(p.reviewPlan, 3);
    expect(p.newPlan, 0, reason: '额度 2 全给复习，新词一张都不排');
    expect(p.taskTotal, 2, reason: '积压 3 张也不许把角标撑到 3');
    expect(p.taskLeft, 2);

    for (final id in ['w1', 'w2']) {
      final s = (await db.getSrs(id))!;
      s.due = inDays(3);
      s.lastReview = DateTime.now();
      await db.saveSrs(id, s);
      await db.logRating(id, Fsrs.ratingKnow);
    }
    final q = await db.todayPlan(dailyQuota: 2);
    expect(q.finished, 2);
    expect(q.taskLeft, 0);
    expect(q.newPlan, 0, reason: '额度已经用尽，新词还是没有名额');

    await db.close();
  });
}
