import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/settings_screen.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/version.dart';
import 'package:katamemo/widgets/k_switch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    for (final ch in ['katamemo/notifications']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  Future<AppState> seed() async {
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
      },
    ]);
    await db.setDataVersion(kDataVersion);
    final app = AppState(db);
    await app.init();
    return app;
  }

  Widget wrap(AppState app, {Brightness brightness = Brightness.light}) {
    final colors = brightness == Brightness.dark ? KColors.dark : KColors.light;
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          splashFactory: NoSplash.splashFactory,
          extensions: <ThemeExtension<dynamic>>[colors],
        ),
        home: const SettingsScreen(),
      ),
    );
  }

  Future<AppState> pumpSettings(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = (await tester.runAsync(() => seed()))!;
    await tester.pumpWidget(wrap(app, brightness: brightness));
    await tester.pump();
    return app;
  }

  Future<void> drain(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
  }

  Future<void> tapRow(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump();
  }

  testWidgets('开关全是自绘 KSwitch：锁着时 3 个，且没有 Material Switch', (tester) async {
    await pumpSettings(tester);
    expect(find.byType(Switch), findsNothing);

    expect(find.byType(KSwitch), findsNWidgets(3));
  });

  testWidgets('点整行即可切换（不止点开关本身），再点翻回', (tester) async {
    final app = await pumpSettings(tester);

    expect(app.autoSpeak, isTrue);
    await tapRow(tester, '自动朗读');
    expect(app.autoSpeak, isFalse);
    await tapRow(tester, '自动朗读');
    expect(app.autoSpeak, isTrue);

    expect(app.showIntervals, isTrue);
    await tapRow(tester, '按钮显示复习时间');
    expect(app.showIntervals, isFalse);
    await tapRow(tester, '按钮显示复习时间');
    expect(app.showIntervals, isTrue);

    expect(app.reminderOn, isTrue);
    await tapRow(tester, '每日学习提醒');
    expect(app.reminderOn, isFalse);
    await tapRow(tester, '每日学习提醒');
    expect(app.reminderOn, isTrue);

    await drain(tester);
  });

  testWidgets('开关状态落库：重开 AppState 仍保持（杀进程重开的等价验证）',
      (tester) async {
    final app = await pumpSettings(tester);

    await tapRow(tester, '自动朗读');
    await tapRow(tester, '按钮显示复习时间');
    expect(app.autoSpeak, isFalse);
    expect(app.showIntervals, isFalse);

    await drain(tester);

    await tester.runAsync(() async {

      final again = AppState(app.db);
      await again.init();
      expect(again.autoSpeak, isFalse);
      expect(again.showIntervals, isFalse);
    });
  });

  testWidgets('顶栏标题左对齐 x=56（不是居中）', (tester) async {
    await pumpSettings(tester);
    expect(find.text('设置'), findsOneWidget);
    final dx = tester.getTopLeft(find.text('设置')).dx;

    expect(dx, closeTo(56, 1));
  });

  testWidgets('分组卡圆角 16，页面不再用 Card', (tester) async {
    await pumpSettings(tester);
    expect(find.byType(Card), findsNothing);

    final card =
        tester.widget<Container>(find.byKey(const ValueKey('settings.group.学习')));
    final deco = card.decoration! as BoxDecoration;
    expect(deco.borderRadius, BorderRadius.circular(16));
    expect(deco.color, KColors.light.surface);

    final title = tester.widget<Text>(find.text('学习'));
    expect(title.style!.fontSize, 13);
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(title.style!.color, KColors.light.t2);
  });

  testWidgets('今日卡量弹卡量对话框；学习方向选中文→印尼语后 studyMode=zh2id',
      (tester) async {
    final app = await pumpSettings(tester);

    await tester.tap(find.text('今日卡量'));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(find.text('设置今日卡量'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await drain(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('学习方向'));
    await tester.pumpAndSettle();
    expect(find.text('中文 → 印尼语'), findsOneWidget);
    await tester.tap(find.text('中文 → 印尼语'));
    await tester.pumpAndSettle();
    expect(app.studyMode, 'zh2id');
  });

  testWidgets('版本行含 build 号；锁着时不出现「经典 / 新版」字样', (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(
        find.textContaining('build $kBuildNumber'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('build $kBuildNumber'), findsOneWidget);
    expect(find.textContaining('经典'), findsNothing);
    expect(find.textContaining('新版'), findsNothing);
  });

  testWidgets('夜间：文字对比度 ≥4.5，开关关态圆钮/轨道 ≥3', (tester) async {
    await pumpSettings(tester, brightness: Brightness.dark);

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    const k = KColors.dark;

    expect(contrast(k.text, k.bg), greaterThanOrEqualTo(4.5));
    expect(contrast(k.text, k.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(k.t3, k.surface), greaterThanOrEqualTo(4.5));

    expect(contrast(k.knob, k.track), greaterThanOrEqualTo(3.0));

    await tapRow(tester, '自动朗读');

    await drain(tester);
    final container = tester.widget<AnimatedContainer>(
      find
          .descendant(

            of: find.byType(KSwitch).last,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect((container.decoration! as BoxDecoration).color, k.track);
  });

  testWidgets('KSwitch：点击回调取反，Semantics 的 toggled 随 value', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        extensions: const <ThemeExtension<dynamic>>[KColors.light],
      ),
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (ctx, setState) => KSwitch(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));

    final handle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.byType(KSwitch))
          .flagsCollection
          .isToggled
          .toBoolOrNull(),
      isFalse,
    );

    await tester.tap(find.byType(KSwitch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(
      tester
          .getSemantics(find.byType(KSwitch))
          .flagsCollection
          .isToggled
          .toBoolOrNull(),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('设置页不再有经典 / 新版样式开关', (tester) async {
    await pumpSettings(tester);

    expect(find.textContaining('新版'), findsNothing);
    expect(find.textContaining('经典'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });
}
