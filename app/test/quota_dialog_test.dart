import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/widgets/quota_dialog.dart';

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
        'id': 'w1',
        'word': 'w1',
        'tier': 'core',
        'rank': 1,
        'zh': '释义-1',
        'enabled': 1,
        'favorite': 0,
      }
    ]);
    return db;
  }

  Future<void> drain(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
  }

  testWidgets('滑轨量程 = kMaxDailyQuota（9999），拖到最右端能取到 9999', (tester) async {
    late AppDb db;
    late AppState app;
    await tester.runAsync(() async {
      db = await seed();
      app = AppState(db);
      await app.init();
    });

    await tester.pumpWidget(MaterialApp(

      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showQuotaDialog(ctx, app),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));

    await drain(tester);
    await tester.pumpAndSettle();

    expect(find.text('设置今日卡量'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0);
    expect(slider.max, AppState.kMaxDailyQuota.toDouble(),
        reason: '量程要等于上限 9999；写死 1000 时这条会红（用户报的正是这个）');

    final box = tester.getRect(find.byType(Slider));
    await tester.dragFrom(
        Offset(box.center.dx, box.center.dy), Offset(box.width, 0));
    await tester.pumpAndSettle();

    final after = tester.widget<Slider>(find.byType(Slider));
    expect(after.value, AppState.kMaxDailyQuota.toDouble(),
        reason: '拖到最右端必须能取到 9999');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '${AppState.kMaxDailyQuota}',
        reason: '大号数字框要同步显示 9999');

    await tester.runAsync(() async => db.close());
  });

  testWidgets('键盘直接输 9999 能生效（超上限则夹回）', (tester) async {
    late AppDb db;
    late AppState app;
    await tester.runAsync(() async {
      db = await seed();
      app = AppState(db);
      await app.init();
    });

    await tester.pumpWidget(MaterialApp(

      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showQuotaDialog(ctx, app),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await drain(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '9999');
    await tester.pumpAndSettle();
    final s = tester.widget<Slider>(find.byType(Slider));
    expect(s.value, 9999, reason: '键盘输入 9999 要同步到滑轨');

    await tester.tap(find.text('确定'));
    await drain(tester);

    late int quota;
    await tester.runAsync(() async {
      final app2 = AppState(db);
      await app2.init();
      quota = app2.dailyQuota;
    });
    expect(quota, 9999, reason: '9999 要能持久化');

    await tester.runAsync(() async => db.close());
  });
}
