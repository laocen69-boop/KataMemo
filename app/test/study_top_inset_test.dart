import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/study_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const double kStatusBar = 40;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    for (final ch in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  Future<AppState> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'tembok',
        'word': 'témbok',
        'tier': 't1',
        'rank': 20,
        'frequency': 90,
        'word_class': 'n',
        'zh': '墙壁',
        'enabled': 1,
        'favorite': 0,
      },
    ]);
    await db.setDataVersion(kDataVersion);
    await db.planWord(['tembok']);
    final app = AppState(db);
    await app.init();
    await app.setAutoSpeak(false);
    return app;
  }

  Widget wrap(AppState app, String ui) =>
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Builder(
            builder: (_) => const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                padding: EdgeInsets.only(top: kStatusBar),
                viewPadding: EdgeInsets.only(top: kStatusBar),
              ),
              child: StudyScreen(),
            ),
          ),
        ),
      );

  Future<AppState> pumpStudy(WidgetTester tester, String ui) async {

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = (await tester.runAsync(() => seed()))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(app, ui));

      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return app;
  }

  testWidgets('进度行只避让一次（dy 在 [40,48]，垫两次会到 80）', (tester) async {
    await pumpStudy(tester, 'new');

    final row = find.byKey(const Key('study.newProgressRow'));
    expect(row, findsOneWidget, reason: '新版顶部应有进度行（Key study.newProgressRow）');
    final dy = tester.getTopLeft(row).dy;
    expect(dy, greaterThanOrEqualTo(kStatusBar - 1), reason: '进度行不能被状态栏压住');
    expect(dy, lessThan(kStatusBar + 8),
        reason: 'dy 应紧贴状态栏下方（[40,48]）；到 80 附近说明状态栏高度被算了两次（顶部空白 bug）');
  });

  testWidgets('最上 40px 内没有 Scaffold 白底露出', (tester) async {
    await pumpStudy(tester, 'new');

    final top = find.byKey(const Key('study.band'));
    expect(top, findsWidgets, reason: '最上层应有顶栏容器覆盖（露出 Scaffold 底色 = P0 的 bug）');
    expect(tester.getTopLeft(top.first).dy, 0,
        reason: '顶栏容器必须贴屏幕最上，否则状态栏后面露出 Scaffold 底色');
    expect(tester.getSize(top.first).height, greaterThan(kStatusBar),
        reason: '顶栏容器至少要盖住整个状态栏区域');
    expect(tester.getSize(top.first).width, 390, reason: 'band 应全宽（两侧不露底色）');
  });
}
