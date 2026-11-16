import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/screens/home_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> backdate(AppDb db, String id, int ts,
      {required bool alsoLastReview}) async {
    final d = await db.db;
    await d.update(
        'srs',
        {
          'first_seen': ts,
          if (alsoLastReview) 'last_review': ts,
        },
        where: 'card_id = ?',
        whereArgs: [id]);
  }

  Future<AppState> seed({int due = 0, int done = 0, int quota = 20}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (var i = 0; i < due + done; i++)
        {
          'id': 'w$i',
          'word': 'w$i',
          'tier': 't1',
          'rank': i + 1,
          'frequency': 100 - i,
          'word_class': 'n',
          'zh': '词$i',
          'enabled': 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    final app = AppState(db);
    await app.init();
    await app.setQuota(quota);
    await app.setAutoSpeak(false);
    final fiveDaysAgo =
        DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch;
    for (var i = 0; i < due; i++) {
      final s = Fsrs.apply(null, Fsrs.ratingKnow);
      s.due = DateTime.now().subtract(const Duration(days: 1));
      await db.saveSrs('w$i', s);
      await backdate(db, 'w$i', fiveDaysAgo, alsoLastReview: true);
    }
    for (var i = due; i < due + done; i++) {

      await db.saveSrs('w$i', Fsrs.apply(null, Fsrs.ratingKnow));
      await backdate(db, 'w$i', fiveDaysAgo, alsoLastReview: false);
    }
    return app;
  }

  Future<void> pumpShell(WidgetTester tester, AppState app) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: HomeShell()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('五个 Tab 都在、顺序对，且没有 M3 的胶囊指示块', (tester) async {
    final app = (await tester.runAsync(() => seed()))!;
    await pumpShell(tester, app);

    Finder navLabel(String t) => find.byWidgetPredicate(
        (w) => w is Text && w.data == t && w.style?.fontSize == 10.5);
    const labels = ['学习', '词库', '语法', '统计', '我的'];
    for (final label in labels) {
      expect(navLabel(label), findsOneWidget, reason: '底部应有「$label」');
    }

    final xs = [for (final l in labels) tester.getCenter(navLabel(l)).dx];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]),
          reason: '底栏顺序应是 学习·词库·语法·统计·我的（「${labels[i]}」跑到前面了）');
    }

    expect(find.byType(NavigationBar), findsNothing,
        reason: '参考设计稿应是自绘的扁平导航，不是 Material 3 的 NavigationBar');
  });

  testWidgets('角标 = 今天还欠着要作答的张数', (tester) async {

    final app = (await tester.runAsync(() => seed(due: 3)))!;
    await pumpShell(tester, app);
    expect(find.text('3'), findsWidgets, reason: '三张都欠着一次作答');
  });

  testWidgets('彻底过了的那几张不再占角标', (tester) async {

    final app = (await tester.runAsync(() => seed(due: 1, done: 2)))!;
    await pumpShell(tester, app);
    expect(find.text('1'), findsWidgets, reason: '★ 已过的不占角标');
    expect(find.text('3'), findsNothing, reason: '角标不是「今天一共几张任务」，是「还欠几张」');
  });

  testWidgets('清完了角标就消失', (tester) async {
    final app = (await tester.runAsync(() => seed(done: 2)))!;
    await pumpShell(tester, app);
    expect(find.text('0'), findsNothing, reason: '没有欠账时不显示 0');
  });

  testWidgets('复习积压超过额度：角标只到额度，多出来的不显示', (tester) async {

    final app = (await tester.runAsync(() => seed(due: 5, quota: 2)))!;
    await pumpShell(tester, app);
    expect(find.text('2'), findsWidgets, reason: '「总数不能超过额度，复习超过了也不行」');
    expect(find.text('5'), findsNothing);
  });

  int shellTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find
          .descendant(
              of: find.byType(HomeShell), matching: find.byType(IndexedStack))
          .first)
      .index!;

  testWidgets('新用户（一张卡都没加入）：开屏落在词库 Tab，学习页写「还没有要学的词」', (tester) async {
    final app = (await tester.runAsync(() => seed()))!;
    await pumpShell(tester, app);

    final empty = find.text('还没有要学的词', skipOffstage: false);
    for (var i = 0; i < 30 && empty.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    expect(shellTab(tester), 1, reason: '没加入过词 → 先看到能挑词的「词库」');
    expect(find.text('还没有要学的词', skipOffstage: false), findsOneWidget,
        reason: '学习页不能再说「今日任务已全部完成」');
    expect(find.text('今日任务已全部完成！', skipOffstage: false), findsNothing);
    expect(find.text('返回词库', skipOffstage: false), findsNothing,
        reason: '没设学习目标时主按钮已经是去词库，不再重复一个「返回词库」');
  });

  testWidgets('老用户（有在记忆里的卡）：开屏仍是学习 Tab', (tester) async {
    final app = (await tester.runAsync(() => seed(due: 1)))!;
    await pumpShell(tester, app);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump();
    expect(shellTab(tester), 0);
  });
}
