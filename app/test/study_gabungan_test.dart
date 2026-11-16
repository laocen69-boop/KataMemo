import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/study_screen.dart';

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

  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
  }

  testWidgets('词组搭配默认 4 个，展开全部 / 收起', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final built = (await tester.runAsync(() async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;

    final card = WordCard(
      id: 'objek',
      word: 'objek',
      wordClass: 'n',
      zh: '对象；客体；宾语；物镜',
      gabunganKata: const [
        'objek afektif',
        'objek akses data',
        'objek alam',
        'objek amatan',
        'objek budaya',
        'objek dakwah',
      ],
    );

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: StudyScreen(previewCard: card),
      ),
    ));
    await settle(tester);

    await tester.tap(find.text('点一下，看答案'));
    await tester.pump();
    await settle(tester, rounds: 2);

    expect(find.text('词组搭配'), findsOneWidget);
    expect(find.text('展开全部 6 个搭配'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('study.gk.objek afektif')), findsOneWidget);

    expect(find.byKey(const ValueKey('study.gk.objek budaya')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('study.gkToggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('study.gk.objek budaya')), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('study.gkToggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('study.gk.objek budaya')), findsNothing);
    expect(find.text('展开全部 6 个搭配'), findsOneWidget);

    await tester.runAsync(() => built.db.close());
  });
}
