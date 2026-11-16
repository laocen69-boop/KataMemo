import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/select_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  Future<(AppDb, List<String>)> seedDb({required int a, required int b}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    final ids = [
      for (var i = 1; i <= a; i++) 'a${i.toString().padLeft(3, '0')}',
      for (var i = 1; i <= b; i++) 'b${i.toString().padLeft(3, '0')}',
    ];
    await db.upsertWords([
      for (var i = 0; i < ids.length; i++)
        {
          'id': ids[i],
          'word': ids[i],
          'tier': 't1',
          'rank': i + 1,
          'zh': '词${i + 1}',
          'enabled': 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    return (db, ids);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 7; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpHome(WidgetTester tester, AppState app, Widget home) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: home,
      ),
    ));
    await settle(tester);
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('词单详情：折叠分组后不自动续页（与卡组词表同口径）', (tester) async {

    final r = (await tester.runAsync(() async {
      final (db, ids) = await seedDb(a: 200, b: 50);
      final id = (await db.createWordList('长词单', ids))!;
      return (AppState(db), id);
    }))!;
    final app = r.$1;

    await pumpHome(tester, app, WordListDetailScreen(listId: r.$2, title: '长词单'));
    expect(find.text('200 词'), findsOneWidget, reason: '首屏只取了第一页（A 组）');
    expect(find.text('B'), findsNothing, reason: '第二页还没取');

    await tester.tap(find.text('折叠'));
    await settle(tester);
    expect(find.text('展开'), findsOneWidget);

    expect(find.text('B'), findsNothing,
        reason: '折叠后自动续页把第二页灌了回来 = 第 36 轮修过的「折叠闪动」');
    expect(find.byKey(const Key('wordlist.word-b001')), findsNothing);

    await tester.tap(find.text('展开'));
    await settle(tester);
    for (var i = 0; i < 40 && find.text('B').evaluate().isEmpty; i++) {

      await tester.dragFrom(const Offset(400, 420), const Offset(0, -3000));
      await settle(tester);
    }
    expect(find.text('B'), findsWidgets, reason: '展开 + 滚动后第二页要能取到');

    await disposeTree(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('记忆分档：超过一页时滚到底续完，不重复取', (tester) async {
    final r = (await tester.runAsync(() async {
      final (db, ids) = await seedDb(a: 250, b: 0);
      await db.planWord(ids);
      return AppState(db);
    }))!;

    await pumpHome(tester, r, const MemoryBandScreen(band: 4, count: 250));
    expect(find.text('— 共 250 词 —'), findsNothing);

    for (var i = 0; i < 40 && find.text('— 共 250 词 —').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
    }
    expect(find.text('— 共 250 词 —'), findsOneWidget,
        reason: '两页合计 250；多取或漏取都会让这行数字对不上');

    await disposeTree(tester);
    await tester.runAsync(() => r.db.close());
  });
}
