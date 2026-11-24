import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/data_repo.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/fsrs_queue_tools.dart';
import 'package:katamemo/screens/home_shell.dart' show cleanLookupText;
import 'package:katamemo/screens/text_reader_screen.dart';
import 'package:katamemo/text_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FSRS 负荷均衡与断签温和顺延', () {
    test('chooseBalancedDays: 短间隔保持原样，长间隔选窗口内最空闲一天', () {
      expect(chooseBalancedDays(1, {1: 50, 2: 0}), 1);
      expect(chooseBalancedDays(3, {3: 40, 2: 0, 4: 0}), 3);

      // rawDays = 20 -> delta = 1 -> 窗口 [19, 21]
      expect(chooseBalancedDays(20, {19: 5, 20: 18, 21: 2}), 21);

      // 平局时选离 rawDays 最近的（优先 20）
      expect(chooseBalancedDays(20, {19: 4, 20: 4, 21: 4}), 20);
    });

    test('planPostpone: 按稳定度从高到低挑选并均匀分散', () {
      final cards = [
        (cardId: 'low', stability: 2.0, dueMs: 100),
        (cardId: 'high', stability: 30.0, dueMs: 100),
        (cardId: 'mid', stability: 12.0, dueMs: 100),
        (cardId: 'highest', stability: 60.0, dueMs: 100),
      ];
      final updates = planPostpone(
        cards,
        postponeDays: 2,
        ratio: 0.5,
        tomorrowStartMs: 1000000,
      );
      expect(updates.map((u) => u.cardId).toList(), ['highest', 'high']);
      expect(updates[0].newDueMs,
          1000000 + 8 * Duration.millisecondsPerHour);
      expect(
          updates[1].newDueMs,
          1000000 +
              Duration.millisecondsPerDay +
              8 * Duration.millisecondsPerHour);
    });

    test('planPostpone: 传入 lastReview 时按当前可提取性 R 从高到低顺延，避免推迟高 S 但已久未复习的危险卡',
        () {
      const day = Duration.millisecondsPerDay;
      const nowMs = 100 * day;
      final cards = [
        // S=30 但 90 天没复习（R 很低，危险，应优先留今天）
        (cardId: 'risky_high_s', stability: 30.0, dueMs: 40 * day),
        // S=20 但 21 天前才复习（R ≈ 89.5%，安全，应优先顺延）
        (cardId: 'safe_mid_s', stability: 20.0, dueMs: 99 * day),
      ];
      final updates = planPostpone(
        cards,
        postponeDays: 2,
        ratio: 0.5,
        tomorrowStartMs: nowMs + day,
        nowMs: nowMs,
        lastReviewByCard: {
          'risky_high_s': 10 * day,
          'safe_mid_s': 79 * day,
        },
      );
      expect(updates.map((u) => u.cardId).toList(), ['safe_mid_s']);
    });

    test('SQLite postponeOverdueReviews: 只改 review 逾期卡 due，不碰学习卡与 last_review',
        () async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      final d = await db.db;

      final todayStart = AppDb.dayStartMs();
      final yesterdayMs = todayStart - Duration.millisecondsPerDay;
      final twoDaysAgoMs = todayStart - 2 * Duration.millisecondsPerDay;

      // 插入测试词条
      for (final w in ['rev_hi', 'rev_lo', 'learn_due', 'today_new']) {
        await d.insert('words', {
          'id': w,
          'word': w,
          'zh': w,
          'tier': 't1',
          'enabled': 1,
          'rank': 1,
        });
      }

      // 两条逾期 review 卡（稳定度高 vs 低）
      await d.insert('srs', {
        'card_id': 'rev_hi',
        'stability': 45.0,
        'difficulty': 4.0,
        'due': yesterdayMs,
        'last_review': twoDaysAgoMs,
        'reps': 5,
        'lapses': 0,
        'state': FsrsState.review,
        'first_seen': twoDaysAgoMs,
        'step': 0,
      });
      await d.insert('srs', {
        'card_id': 'rev_lo',
        'stability': 3.0,
        'difficulty': 6.0,
        'due': yesterdayMs,
        'last_review': twoDaysAgoMs,
        'reps': 2,
        'lapses': 1,
        'state': FsrsState.review,
        'first_seen': twoDaysAgoMs,
        'step': 0,
      });
      // 正在重学步长的卡（绝不能顺延）
      await d.insert('srs', {
        'card_id': 'learn_due',
        'stability': 1.0,
        'difficulty': 5.0,
        'due': yesterdayMs,
        'last_review': twoDaysAgoMs,
        'reps': 1,
        'lapses': 1,
        'state': FsrsState.relearning,
        'first_seen': twoDaysAgoMs,
        'step': 0,
      });
      // 今天刚首次接触的卡（不计入逾期复习）
      await d.insert('srs', {
        'card_id': 'today_new',
        'stability': 2.0,
        'difficulty': 5.0,
        'due': yesterdayMs,
        'last_review': todayStart + 1000,
        'reps': 1,
        'lapses': 0,
        'state': FsrsState.review,
        'first_seen': todayStart + 1000,
        'step': 0,
      });

      expect(await db.overdueReviewCount(), 2);

      final moved = await db.postponeOverdueReviews(postponeDays: 5, ratio: 0.5);
      expect(moved, 1);

      final rows = {
        for (final r in await d.query('srs')) r['card_id'] as String: r,
      };
      // 高稳定度那条被推迟到明天及以后，但 last_review / stability 完全不变
      expect((rows['rev_hi']!['due'] as int) >= todayStart + Duration.millisecondsPerDay,
          isTrue);
      expect(rows['rev_hi']!['last_review'], twoDaysAgoMs);
      expect(rows['rev_hi']!['stability'], 45.0);

      // 低稳定度保留在今天逾期池
      expect(rows['rev_lo']!['due'], yesterdayMs);
      // 重学卡不受影响
      expect(rows['learn_due']!['due'], yesterdayMs);
      await db.close();
    });
  });

  group('Android 划词清洗 & 粘贴文章高亮阅读', () {
    test('cleanLookupText: 去掉首尾标点并保留连字符叠词', () {
      expect(cleanLookupText('  "orang-orang," \n '), 'orang-orang');
      expect(cleanLookupText('（rumah   sakit!）'), 'rumah sakit');
      expect(cleanLookupText('...'), '');
    });

    test('analyzeReadingText: 识别短语、连字符叠词与掌握覆盖率', () async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await DataRepo(db).ensureImported();

      // 把 `rumah sakit` 标为已掌握，把 `orang` 标为学习中
      final now = DateTime.now().millisecondsSinceEpoch;
      final d = await db.db;
      await d.insert('srs', {
        'card_id': 'rumah sakit',
        'stability': 15.0,
        'difficulty': 4.0,
        'due': now + Duration.millisecondsPerDay * 10,
        'last_review': now,
        'reps': 4,
        'lapses': 0,
        'state': FsrsState.review,
        'first_seen': now - Duration.millisecondsPerDay * 20,
        'step': 0,
      });
      await db.planWord(['pergi']);

      final res = await analyzeReadingText(
        db,
        'Banyak orang-orang pergi ke rumah sakit baru.',
      );

      expect(res.uniqueCards.any((c) => c.id == 'rumah sakit'), isTrue);
      expect(res.statusById['rumah sakit'], ReaderWordStatus.known);
      expect(res.statusById['pergi'], ReaderWordStatus.unknown,
          reason: '仅加入计划(reps=0)但未学过的词不应算作已掌握/学习中');
      expect(res.knownCount, greaterThanOrEqualTo(1));
      expect(res.totalWords, greaterThanOrEqualTo(4));
      expect(res.coveragePct, greaterThan(0));
      await db.close();
    });

    testWidgets('TextReaderScreen 可正常渲染输入态与高亮阅读态', (tester) async {
      late AppDb db;
      late AppState app;
      await tester.runAsync(() async {
        await databaseFactory.deleteDatabase(inMemoryDatabasePath);
        db = AppDb(dbPath: inMemoryDatabasePath);
        await DataRepo(db).ensureImported();
        app = AppState(db);
        await app.init();
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(
            home: TextReaderScreen(
              initialText: 'Saya makan nasi di rumah sakit.',
            ),
          ),
        ),
      );
      // 触发 postFrameCallback 里的 _analyze()，再在 runAsync 中等待真实 SQLite 完成
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('文章生词高亮阅读'), findsOneWidget);
      expect(find.textContaining('词汇覆盖率'), findsOneWidget);
      expect(find.text('换一篇'), findsOneWidget);
      await tester.runAsync(() => db.close());
    });
  });
}
