import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/screens/stats_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => null,
    );
  });

  group('刻度辅助函数（坐标轴的唯一来源）', () {
    test('statStep：挑 max/step ≤ 4 的最小候选', () {
      expect(statStep(7, const [1, 2, 5, 10]), 2);
      expect(statStep(4, const [1, 2, 5, 10]), 1);
      expect(statStep(0, const [1, 2, 5, 10]), 1);
      expect(statStep(999, const [1, 2, 5, 10]), 10);
      expect(statStep(99999, const [1, 2, 5, 10]), 10);
    });

    test('statIntStep：作答量词数的整数刻度', () {
      expect(statIntStep(3), 1);
      expect(statIntStep(40), 10);
      expect(statIntStep(500), 200);
      expect(statIntStep(0), 1);
    });

    test('statPctStep：困难率不会按 0–100% 画（旧版柱子挤在底部 10%）', () {
      expect(statPctStep(0.08), 0.05);
      expect(statPctStep(0.6), 0.2);
      expect(statPctStep(0.0), 0.05);
    });

    test('statBinVisible / statBinSolid：样本不够的档不画、偏小的画浅色', () {

      expect(statBinVisible(0), isFalse);
      expect(statBinVisible(statBinMinReviews - 1), isFalse);
      expect(statBinVisible(statBinMinReviews), isTrue);
      expect(statBinSolid(statBinSolidReviews - 1), isFalse);
      expect(statBinSolid(statBinSolidReviews), isTrue);

      expect(statBinMinReviews, lessThan(statBinSolidReviews));
    });

    test('statAxisMax：上限是刻度的整数倍，网格与刻度对齐', () {
      expect(statAxisMax(7, 2), 8);
      expect(statAxisMax(40, 10), 40);
      expect(statAxisMax(0, 5), 5);
      expect(statAxisMax(0.08, 0.05), closeTo(0.1, 1e-9));
    });

    test('statDayLabel：同月也带月（30 天窗口跨月是常态）', () {
      expect(statDayLabel(DateTime(2026, 9, 8)), '9/8');
      expect(statDayLabel(DateTime(2026, 12, 31)), '12/31');
    });
  });

  group('统计页整页', () {
    late AppDb db;

    Future<void> seed() async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      db = AppDb(dbPath: inMemoryDatabasePath);
      await db.upsertWords([
        for (var i = 0; i < 6; i++)
          {
            'id': 'w$i', 'word': 'w$i', 'tier': 't1', 'rank': i + 1,
            'frequency': 100 - i, 'word_class': 'n', 'zh': '词$i',
            'enabled': 1, 'favorite': 0,

            if (i % 2 == 0) 'topics': '餐饮食物',
            if (i % 2 == 1) 'topics': '交通出行',
          },
      ]);
      await db.setDataVersion(kDataVersion);

      final d = await db.db;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      int ms(DateTime t) => t.millisecondsSinceEpoch;

      final s0 = Fsrs.apply(null, Fsrs.ratingKnow);
      await d.insert('srs',
          {...s0.toMap('w0'), 'first_seen': ms(today), 'reps': 1, 'lapses': 0});

      final s1 = Fsrs.apply(null, Fsrs.ratingKnow);
      await d.insert('srs', {
        ...s1.toMap('w1'),
        'first_seen': ms(today.subtract(const Duration(days: 3))),
        'reps': 2,
        'lapses': 1,
        'stability': 5.0,
      });

      final s2 = Fsrs.apply(null, Fsrs.ratingKnow);
      await d.insert('srs', {
        ...s2.toMap('w2'),
        'first_seen': ms(today.subtract(const Duration(days: 10))),
        'reps': 3,
        'lapses': 0,
        'stability': 9.0,
      });

      await d.insert('study_log', {
        'card_id': 'w0',
        'rating': 2,
        'ts': ms(today.add(const Duration(hours: 1)))
      });
      await d.insert('study_log', {
        'card_id': 'w1',
        'rating': 1,
        'ts': ms(today.add(const Duration(hours: 2)))
      });
      await d.insert('study_log', {
        'card_id': 'w2',
        'rating': 2,
        'ts': ms(today.add(const Duration(hours: 3)))
      });
      await d.insert('study_log', {
        'card_id': 'w1',
        'rating': 2,
        'ts': ms(today.subtract(const Duration(days: 5))),
      });
    }

    Future<AppState> pumpPage(WidgetTester tester,
        {Size? surface, Future<void> Function()? seedFn}) async {

      await tester.runAsync(() => (seedFn ?? seed)());
      final app = AppState(db);
      await tester.runAsync(() => app.init());
      if (surface != null) {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ChangeNotifierProvider<AppState>.value(
            value: app,

            child: MaterialApp(
              theme: ThemeData(splashFactory: InkRipple.splashFactory),
              home: const StatsScreen(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return app;
    }

    Future<void> tapTab(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> expandModel(WidgetTester tester) async {
      await tapTab(tester, '模型');
    }

    test('学习趋势：一个词一天算一次、按第一次作答分档，总数 = 复习 + 新学', () async {
      await seed();
      final d = await db.db;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      int ms(DateTime t) => t.millisecondsSinceEpoch;
      String key(DateTime t) =>
          '${t.year}-${t.month.toString().padLeft(2, '0')}'
          '-${t.day.toString().padLeft(2, '0')}';
      final todayKey = key(today);
      final oldKey = key(today.subtract(const Duration(days: 5)));

      await d.insert('study_log', {
        'card_id': 'w3',
        'rating': 0,
        'ts': ms(today.add(const Duration(hours: 4)))
      });
      await d.insert('study_log', {
        'card_id': 'w3',
        'rating': 2,
        'ts': ms(today.add(const Duration(hours: 5)))
      });
      await d.insert('study_log', {
        'card_id': 'w4',
        'rating': 2,
        'ts': ms(today.add(const Duration(hours: 6)))
      });
      await d.insert('study_log', {
        'card_id': 'w4',
        'rating': 0,
        'ts': ms(today.add(const Duration(hours: 7)))
      });
      await d.insert('study_log', {
        'card_id': 'w0',
        'rating': 2,
        'ts': ms(today.add(const Duration(hours: 8)))
      });

      await d.insert('srs', {
        ...Fsrs.apply(null, Fsrs.ratingEasy).toMap('w5'),
        'first_seen': ms(today),
        'reps': 1,
        'lapses': 0,
      });
      await d.insert('study_log', {
        'card_id': 'w5',
        'rating': 3,
        'ts': ms(today.add(const Duration(hours: 9)))
      });

      final daily = await db.dailyWordRatingCounts();

      expect(daily[todayKey], (easy: 1, know: 3, fuzzy: 1, forget: 1),
          reason: 'w0/w2/w4 记得 · w1 模糊 · w3 困难 · w5 轻松；'
              'w3 是「先困难后记得」→ 按**第一次**算困难，不是记得');
      expect(daily[oldKey], (easy: 0, know: 1, fuzzy: 0, forget: 0),
          reason: '跨日的日志不能串到今天那根柱子上');

      final t = daily[todayKey]!;
      expect(t.easy + t.know + t.fuzzy + t.forget, 6,
          reason: '今天过过 6 个词（去重，含 1 个「轻松」）');

      expect(await db.todayLogCount(), 9, reason: '今天的作答条数（第二十九轮起它只作对账，不扣额度）');
      expect(t.easy + t.know + t.fuzzy + t.forget, isNot(await db.todayLogCount()),
          reason: '柱高不是作答次数');

      expect(await db.todayAnsweredWords(), 6, reason: '趋势柱高 == 额度的扣减依据');

      final stats = await db.todayStats();
      expect(stats['new'], 2, reason: '今天新学 = first_seen 是今天的（w0、w5）');
      expect(t.easy + t.know + t.fuzzy + t.forget,
          (stats['new'] ?? 0) + (stats['review'] ?? 0),
          reason: '「总数等于当日的复习加新学」——趋势图与今日概况必须同口径');

      expect(stats['easy'], 1, reason: '今天有 1 条「轻松」（w5），不能漏掉');
      expect(
          (stats['easy'] ?? 0) +
              (stats['know'] ?? 0) +
              (stats['fuzzy'] ?? 0) +
              (stats['forget'] ?? 0),
          await db.todayLogCount(),
          reason: '四档作答条数之和 == 今天的作答条数');

      final sum = daily.values.fold<int>(
          0, (a, v) => a + v.easy + v.know + v.fuzzy + v.forget);
      final rows = await db.db
          .then((d) => d.rawQuery('SELECT COUNT(*) c FROM study_log'));
      expect(sum, lessThanOrEqualTo(Sqflite.firstIntValue(rows)!));

      await db.close();
    });

    test('遗忘曲线：按「距上次复习的天数」分档，一天一次、首日不算复习', () async {
      await seed();
      final d = await db.db;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      int ms(DateTime t) => t.millisecondsSinceEpoch;

      Future<void> log(String card, int daysAgo, int rating, int hour) async {
        await d.insert('study_log', {
          'card_id': card,
          'rating': rating,
          'ts': ms(today
              .subtract(Duration(days: daysAgo))
              .add(Duration(hours: hour))),
        });
      }

      await d.delete('study_log');

      await log('w0', 9, 2, 0);
      await log('w0', 8, 0, 1);
      await log('w0', 1, 2, 2);

      await log('w1', 10, 2, 0);
      await log('w1', 7, 0, 1);
      await log('w1', 7, 2, 2);

      await log('w2', 40, 2, 0);
      await log('w2', 9, 2, 1);

      await log('w3', 20, 2, 0);
      await log('w3', 8, 0, 1);

      await log('w4', 0, 2, 0);
      await log('w4', 0, 0, 5);

      final bins = await db.forgetRateByInterval();
      final by = {for (final b in bins) b.label: b};

      expect(bins, hasLength(8), reason: '固定 8 档，空的也在（画不画由界面按样本量定）');
      expect(by['1'], (label: '1', reviews: 1, forgets: 1, words: 1),
          reason: 'w0 的 -9→-8：间隔 1 天，答的是「困难」（当天第一次作答）');
      expect(by['3'], (label: '3', reviews: 1, forgets: 1, words: 1),
          reason: 'w1 的 -10→-7：间隔 3 天；同一天答两次只算一次，'
              '取第一次（困难）——算两次或取最后一次都会让这个数变');
      expect(by['4-7'], (label: '4-7', reviews: 1, forgets: 0, words: 1),
          reason: 'w0 的 -8→-1：间隔 7 天');
      expect(by['8-14'], (label: '8-14', reviews: 1, forgets: 1, words: 1),
          reason: 'w3 的 -20→-8：间隔 12 天');
      expect(by['31-90'], (label: '31-90', reviews: 1, forgets: 0, words: 1),
          reason: 'w2 的 -40→-9：间隔 31 天');
      expect(by['2']!.reviews, 0);
      expect(by['15-30']!.reviews, 0);
      expect(by['90+']!.reviews, 0);

      final total = bins.fold<int>(0, (a, b) => a + b.reviews);
      expect(total, 5, reason: 'w0×2 + w1 + w2 + w3 = 5 次复习');
      final logs = await d.rawQuery('SELECT COUNT(*) c FROM study_log');
      expect(total, lessThan(Sqflite.firstIntValue(logs)!),
          reason: '9 条作答里只有 5 次算复习（首日不算、同日折叠）');
      for (final b in bins) {
        expect(b.forgets, lessThanOrEqualTo(b.reviews));
        expect(b.words, lessThanOrEqualTo(b.reviews));
      }

      await db.close();
    });

    testWidgets('集成趋势图：档位切换 + 坐标轴齐全', (tester) async {

      await pumpPage(tester, surface: const Size(390, 3600));

      expect(find.text('今日新学'), findsOneWidget);
      expect(find.text('今日复习'), findsOneWidget);
      expect(find.text('连续天数'), findsOneWidget);
      expect(find.text('总体回忆率'), findsOneWidget);
      expect(find.text('今日学习'), findsNothing, reason: '旧卡的「今日学习」标题已换成摘要头四宫格');

      expect(find.text('1'), findsWidgets);

      await tapTab(tester, '趋势');
      expect(find.text('学习趋势'), findsOneWidget);
      expect(find.text('近 7 天学习趋势'), findsNothing, reason: '旧的两张趋势卡已合并');
      expect(find.text('近 30 天作答量'), findsNothing);

      for (final m in ['30 天', '30 周', '30 月']) {
        expect(find.text(m), findsWidgets, reason: '档位「$m」应在');
      }

      expect(find.textContaining(RegExp(r'^\d{1,2}/\d{1,2}$')), findsWidgets);

      expect(find.textContaining(RegExp(r'^轻松 \d+$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^记得 \d+$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^模糊 \d+$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^困难 \d+$')), findsOneWidget);

      expect(find.text('轻松 0'), findsOneWidget);
      expect(find.text('记得 3'), findsOneWidget);
      expect(find.text('模糊 1'), findsOneWidget);
      expect(find.text('困难 0'), findsOneWidget);

      await tester.tap(find.text('30 月').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining(RegExp(r'^\d{1,2}月$')), findsWidgets,
          reason: '月档的横轴标签应是 N月');
      expect(find.text('每个点 = 该自然月里各天「过过词数」之和，四条折线分别对应四档，浅灰面积是总量'),
          findsOneWidget);

      await tapTab(tester, '模型');
      expect(find.text('困难率（按复习间隔）'), findsOneWidget,
          reason: '旧版叫「困难率分布」（幸存者偏差口径），已换掉');
      expect(find.text('困难率分布'), findsNothing);
    });

    testWidgets('遗忘曲线：样本不足时给说明，不是一根 100% 的柱子', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));
      await expandModel(tester);
      expect(find.textContaining('复习记录还太少'), findsOneWidget);
      expect(find.textContaining('现在一共 1 次'), findsOneWidget,
          reason: 'seed 里只有 w1 的一次复习（今天 − 5 天前），总数要报出来');
    });

    testWidgets('遗忘曲线：够样本的档画柱，不足的档不画', (tester) async {
      Future<void> seedMore() async {
        await seed();

        final today = DateTime.now();
        final day = DateTime(today.year, today.month, today.day);
        int ms(DateTime t) => t.millisecondsSinceEpoch;
        await db.upsertWords([
          for (var i = 0; i < 12; i++)
            {
              'id': 'x$i',
              'word': 'x$i',
              'tier': 't1',
              'rank': i + 1,
              'frequency': 90 - i,
              'word_class': 'n',
              'zh': '词x$i',
              'enabled': 1,
              'favorite': 0,
            },
        ]);
        final d = await db.db;
        for (var i = 0; i < 12; i++) {
          await d.insert('study_log', {
            'card_id': 'x$i',
            'rating': 2,
            'ts': ms(day.subtract(const Duration(days: 1))),
          });
          await d.insert('study_log', {
            'card_id': 'x$i',
            'rating': 0,
            'ts': ms(day.add(const Duration(hours: 1))),
          });
        }
      }

      await pumpPage(tester, surface: const Size(390, 3600), seedFn: seedMore);
      await expandModel(tester);

      expect(find.text('共 13 次复习'), findsOneWidget);
      expect(find.textContaining('横轴：距上次复习的天数'), findsOneWidget);
      expect(find.textContaining('另有 1 个档复习不足 10 次，未画'), findsOneWidget);
      expect(find.textContaining('复习记录还太少'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320×568 窄屏整页不溢出', (tester) async {
      await pumpPage(tester, surface: const Size(320, 568));
      expect(tester.takeException(), isNull);

      await expandModel(tester);
      expect(tester.takeException(), isNull);

      await tapTab(tester, '趋势');
      expect(tester.takeException(), isNull);
    });

    testWidgets('摘要头：结论条 + 四宫格 + 时长 sparkline', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));

      expect(find.text('今日新学'), findsOneWidget);
      expect(find.text('今日复习'), findsOneWidget);
      expect(find.text('连续天数'), findsOneWidget);
      expect(find.text('总体回忆率'), findsOneWidget);

      expect(find.textContaining('今天已过'), findsOneWidget,
          reason: '今天学过（seed 里今天 3 条日志）→ 结论条应说今天过了几个词');

      expect(find.text('近 30 天学习时长'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('掌握情况：五段分布条 + 图例齐全', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));
      expect(find.text('掌握情况'), findsOneWidget);
      expect(find.text('记忆分布'), findsOneWidget);

      for (final s in ['已掌握', '熟悉', '一般', '不熟', '未学']) {
        expect(find.textContaining(RegExp('^$s \\d+\$')), findsWidgets,
            reason: '五段图例应含「$s」');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('主题地图：不可求和的说明在界面上', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));
      await tapTab(tester, '主题');
      expect(find.text('主题地图'), findsOneWidget);
      expect(find.textContaining('一个词可以同时属于多个主题'), findsOneWidget,
          reason: '必须说明各主题词数不可相加，否则用户会以为能求和');
      expect(tester.takeException(), isNull);
    });

    testWidgets('四 Tab：页签齐全 + 导航切换', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));
      for (final t in ['总览', '主题', '趋势', '模型']) {
        expect(find.text(t), findsWidgets, reason: 'Tab「$t」应在 AppBar 下');
      }
      expect(find.text('趋势与模型'), findsNothing, reason: '旧折叠头已被 Tab 顶替，不该再出现');

      await tapTab(tester, '主题');
      expect(find.text('主题地图'), findsOneWidget);
      await tapTab(tester, '趋势');
      expect(find.text('学习趋势'), findsOneWidget);
      await tapTab(tester, '模型');
      expect(find.text('记忆曲线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('趋势图：量 / 率 切换', (tester) async {
      await pumpPage(tester, surface: const Size(390, 3600));
      await tapTab(tester, '趋势');

      expect(find.text('词数'), findsOneWidget);
      expect(find.text('回忆率'), findsWidgets);

      expect(find.text('记得 3'), findsOneWidget);

      await tester.tap(find.text('回忆率').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('第一次作答就是记得'), findsOneWidget,
          reason: '率模式的说明应写明分子口径');
      expect(find.text('记得 3'), findsNothing, reason: '率模式不画三档堆叠图例');
      expect(tester.takeException(), isNull);
    });
  });
}
