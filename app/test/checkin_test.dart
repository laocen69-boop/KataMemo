import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<AppDb> seed({List<String> ids = const ['w0', 'w1', 'w2']}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (final id in ids)
        {
          'id': id,
          'word': id,
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
    await db.setDataVersion(kDataVersion);
    return db;
  }

  Future<void> seedDoneToday(AppDb db, String id, DateTime now) async {
    final raw = await db.db;
    final t =
        dayStart(now).add(const Duration(hours: 10)).millisecondsSinceEpoch;
    await raw.insert('srs', {
      'card_id': id,
      'stability': 1.0,
      'difficulty': 5.0,
      'due': t + const Duration(days: 1).inMilliseconds,
      'last_review': t,
      'reps': 1,
      'lapses': 0,
      'state': 2,
      'step': 0,
      'first_seen': t,
    });
  }

  Future<void> seedPendingToday(AppDb db, String id, DateTime now) async {
    final raw = await db.db;
    final t =
        dayStart(now).add(const Duration(hours: 10)).millisecondsSinceEpoch;
    await raw.insert('srs', {
      'card_id': id,
      'stability': 0.5,
      'difficulty': 5.0,
      'due': t + const Duration(hours: 8).inMilliseconds,
      'last_review': t,
      'reps': 1,
      'lapses': 0,
      'state': 1,
      'step': 0,
      'first_seen': t,
    });
  }

  group('自动签到（todayPlan 的副作用）', () {
    test('签到判据：taskLeft==0 且 taskTotal>0；没做完不签；幂等', () async {
      final db = await seed();
      final now = DateTime.now();
      final todayKey = AppDb.checkinKey(now);

      await db.todayPlan(dailyQuota: 20, now: now);
      expect(await db.metaGet(todayKey), isNull, reason: '今天没有任务，谈不上「完成」');

      await seedDoneToday(db, 'w0', now);
      await seedPendingToday(db, 'w1', now);
      await db.todayPlan(dailyQuota: 2, now: now);
      expect(await db.metaGet(todayKey), isNull, reason: '只学了没做完，不冒充打卡');

      final raw = await db.db;
      await raw.update(
          'srs',
          {
            'due': dayStart(now)
                .add(const Duration(days: 2))
                .millisecondsSinceEpoch
          },
          where: 'card_id = ?',
          whereArgs: ['w1']);
      await db.todayPlan(dailyQuota: 2, now: now);
      expect(await db.metaGet(todayKey), isNotNull, reason: '全部任务彻底过完的那一刻自动签到');

      final v = await db.metaGet(todayKey);
      await db.todayPlan(dailyQuota: 2, now: now);
      expect(await db.metaGet(todayKey), v, reason: '签到时刻取第一次完成那刻');

      expect(await db.isSignedDay(now), isTrue);
      await db.close();
    });

    test('额度 0：没学过不签；先学完再调 0 照签（任务确实完成了）', () async {
      final db = await seed();
      final now = DateTime.now();

      await db.todayPlan(dailyQuota: 0, now: now);
      expect(await db.metaGet(AppDb.checkinKey(now)), isNull,
          reason: '额度 0 = 今天不排卡，没有「任务」可言');

      await seedDoneToday(db, 'w0', now);
      await seedDoneToday(db, 'w1', now);
      await db.todayPlan(dailyQuota: 0, now: now);
      expect(await db.metaGet(AppDb.checkinKey(now)), isNotNull,
          reason: '先学后调 0：完成是既成事实，签到成立');
      await db.close();
    });
  });

  group('历史回填（ensureCheckinBackfill）', () {
    test('「碰过词数 ≥ 额度」的历史天补签到；不足的不补；今天不补', () async {
      final db = await seed(ids: const ['a', 'b', 'c']);
      final raw = await db.db;
      final now = DateTime.now();
      const quota = 2;
      await db.metaSet('new_quota', '$quota');

      final d3 = dayStart(now).subtract(const Duration(days: 3));
      final d1 = dayStart(now).subtract(const Duration(days: 1));

      for (var i = 0; i < 4; i++) {
        await raw.insert('study_log', {
          'card_id': 'a',
          'rating': 2,
          'ts': d3.add(Duration(hours: 10 + i)).millisecondsSinceEpoch
        });
      }
      await raw.insert('study_log', {
        'card_id': 'b',
        'rating': 2,
        'ts': d3.add(const Duration(hours: 11)).millisecondsSinceEpoch
      });
      await raw.insert('study_log', {
        'card_id': 'c',
        'rating': 2,
        'ts': d3.add(const Duration(hours: 12)).millisecondsSinceEpoch
      });

      await raw.insert('study_log', {
        'card_id': 'a',
        'rating': 2,
        'ts': d1.add(const Duration(hours: 10)).millisecondsSinceEpoch
      });

      await db.ensureCheckinBackfill();
      expect(await db.isSignedDay(d3), isTrue, reason: '3 词 ≥ 额度 2 ⇒ 补签');
      expect(await db.isSignedDay(d1), isFalse, reason: '1 词 < 额度 ⇒ 不补（宁可报少）');
      expect(await db.isSignedDay(now), isFalse, reason: '「今天」永远由实时判据管，不回填');

      await db.ensureCheckinBackfill();
      expect(await db.isSignedDay(d3), isTrue);
      expect(await db.isSignedDay(d1), isFalse);
      await db.close();
    });
  });

  group('连续打卡 = 连续签到天（streakDays 新口径）', () {
    test('连续签到往下数；今天没签不断签；中间断一天就重置', () async {
      final db = await seed(ids: const ['x']);
      final now = DateTime.now();

      await db.metaSet(
          AppDb.checkinKey(now.subtract(const Duration(days: 1))), '0');
      await db.metaSet(
          AppDb.checkinKey(now.subtract(const Duration(days: 2))), '0');
      expect(await db.streakDays(), 2);

      await db.metaSet(AppDb.checkinKey(now), '0');
      expect(await db.streakDays(), 3);

      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db2 = AppDb(dbPath: inMemoryDatabasePath);
      await db2.setDataVersion(kDataVersion);
      await db2.metaSet(
          AppDb.checkinKey(now.subtract(const Duration(days: 1))), '0');
      await db2.metaSet(
          AppDb.checkinKey(now.subtract(const Duration(days: 3))), '0');
      expect(await db2.streakDays(), 1, reason: '-2 没签到 ⇒ 连续在 -1 处断掉（-3 不接上）');
      await db2.close();
      await db.close();
    });
  });

  group('monthView（翻看之前月份的数据源）', () {
    test('按天给「去重词数 / 作答次数 / 签到」，回填自动先跑', () async {
      final db = await seed(ids: const ['a', 'b', 'c']);
      final raw = await db.db;
      final now = DateTime.now();
      final prev = DateTime(now.year, now.month, 1)
          .subtract(const Duration(days: 1));
      await db.metaSet('new_quota', '2');

      for (var i = 0; i < 5; i++) {
        await raw.insert('study_log', {
          'card_id': ['a', 'b', 'c', 'a', 'b'][i],
          'rating': 2,
          'ts': prev.add(Duration(hours: 10 + i)).millisecondsSinceEpoch,
        });
      }
      final view = await db.monthView(prev.year, prev.month);
      final key = '${prev.year}-${prev.month.toString().padLeft(2, '0')}-'
          '${prev.day.toString().padLeft(2, '0')}';
      expect(view[key], isNotNull, reason: '上月最后一天有数据');
      expect(view[key]!.words, 3, reason: 'a/b/c 三个去重词（5 次作答折叠）');
      expect(view[key]!.answers, 5);
      expect(view[key]!.signed, isTrue,
          reason: '3 词 ≥ 额度 2 ⇒ monthView 先跑回填再标记');

      final cur = await db.monthView(now.year, now.month);
      expect(cur[key], isNull);
      final far = await db.monthView(now.year - 2, 1);
      expect(far, isEmpty);
      await db.close();
    });
  });

  final widgetTheme =
      ThemeData(useMaterial3: true, splashFactory: InkRipple.splashFactory);

  group('「我的」页界面：翻月 + 弹窗签到行', () {
    Future<(AppDb, AppState)> seedFull() async {
      final db = await seed();
      await db.metaSet('new_quota', '2');
      final raw = await db.db;
      final now = DateTime.now();
      final prevDay =
          DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));
      for (var i = 0; i < 3; i++) {
        await raw.insert('study_log', {
          'card_id': ['a', 'b', 'c'][i],
          'rating': 2,
          'ts': prevDay.add(Duration(hours: 10 + i)).millisecondsSinceEpoch,
        });
      }
      final app = AppState(db);
      await app.init();
      return (db, app);
    }

    Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(() async =>
            Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pump();
      }
    }

    testWidgets('点 ‹ 翻到上个月：标题跟着变、数据在（上月最后一天那天有学习）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final built = (await tester.runAsync(seedFull))!;
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: built.$2,
        child: MaterialApp(theme: widgetTheme, home: const ProfileScreen()),
      ));
      await settle(tester);

      final now = DateTime.now();
      final prev =
          DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));

      expect(find.text('${now.year} 年 ${now.month} 月'), findsOneWidget,
          reason: '初始标题是当月');
      await tester.tap(find.byTooltip('上一月'));
      await settle(tester, rounds: 8);
      expect(find.text('${prev.year} 年 ${prev.month} 月'), findsOneWidget,
          reason: '翻到上个月');
      expect(find.textContaining('实心圆 = 当天完成全部学习任务'), findsOneWidget,
          reason: '口径说明要跟着新判据走');

      await tester.tap(find.byTooltip('下一月'));
      await settle(tester, rounds: 8);
      expect(find.textContaining('${now.year} 年 ${now.month} 月'), findsWidgets);

      final nextBtn = find.ancestor(
          of: find.byTooltip('下一月'), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(nextBtn).onPressed, isNull,
          reason: '已在当月 ⇒ 下一月禁用');
    });

    testWidgets('点已签到的那天：弹窗里写「完成了全部学习任务」', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final built = (await tester.runAsync(seedFull))!;
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: built.$2,
        child: MaterialApp(theme: widgetTheme, home: const ProfileScreen()),
      ));
      await settle(tester);

      final now = DateTime.now();
      final prevDay =
          DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));

      await tester.tap(find.byTooltip('上一月'));
      await settle(tester, rounds: 8);
      await tester.tap(find.text('${prevDay.day}').first);
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester, rounds: 6);
      expect(find.textContaining('完成了全部学习任务'), findsOneWidget,
          reason: '有签到记录的那天，弹窗里要说清「签到」是什么意思');
    });
  });
}
