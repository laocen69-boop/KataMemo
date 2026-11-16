library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/study_screen.dart';
import 'package:katamemo/theme/k_colors.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const double kMin = 4.5;

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

  Future<AppState> seed({bool spelling = false}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'karo',
        'word': 'karo',
        'tier': 't1',
        'rank': 42,
        'frequency': 80,
        'word_class': 'n',
        'zh': '卡洛语',
        if (spelling)
          'examples': WordCard.encodeMaps([
            {'i': 'Dia menulis surat itu kemarin.', 'q': 'menulis'},
          ]),
        'enabled': 1,
        'favorite': 0,
      },
    ]);
    await db.setDataVersion(kDataVersion);
    await db.planWord(['karo']);
    final app = AppState(db);
    await app.init();
    await app.setAutoSpeak(false);
    if (spelling) await app.setStudyMode('zh2id');
    return app;
  }

  Widget wrap(AppState app, KColors colors) =>
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(
            brightness:
                colors == KColors.dark ? Brightness.dark : Brightness.light,
            splashFactory: NoSplash.splashFactory,
            extensions: <ThemeExtension<dynamic>>[colors],
          ),
          home: Builder(
            builder: (_) => const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                padding: EdgeInsets.only(top: 40),
                viewPadding: EdgeInsets.only(top: 40),
              ),
              child: StudyScreen(),
            ),
          ),
        ),
      );

  Future<AppState> pumpStudy(
      WidgetTester tester, KColors colors, {bool spelling = false}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = (await tester.runAsync(() => seed(spelling: spelling)))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(app, colors));
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return app;
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.runAsync(() async {
      await tester.tap(f);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(milliseconds: 120));

    await tester.runAsync(() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  List<Color> bandBgs(WidgetTester tester) {

    final box =
        tester.widget<Container>(find.byKey(const Key('study.band')));

    if (box.decoration == null) {
      final page = tester
          .widget<DecoratedBox>(find.byKey(const Key('study.pageGradient')));
      final g = (page.decoration as BoxDecoration).gradient as LinearGradient;
      return g.colors.take(2).toList();
    }
    final deco = box.decoration as BoxDecoration;
    return (deco.gradient as LinearGradient).colors;
  }

  double minContrast(Color fg, List<Color> bgs) => bgs
      .map((bg) => contrast(fg, bg))
      .reduce((a, b) => a < b ? a : b);

  Finder textOf(String data, double size) => find.byWidgetPredicate(
      (w) => w is Text && w.data == data && w.style?.fontSize == size);

  void expectFrontReadable(WidgetTester tester, {required String label}) {
    final bgs = bandBgs(tester);

    final word = textOf('karo', 30);
    expect(word, findsOneWidget, reason: '$label：没找到正面单词（30px）');
    final wordColor = tester.widget<Text>(word).style!.color!;
    expect(minContrast(wordColor, bgs), greaterThanOrEqualTo(kMin),
        reason: '$label：单词 ${wordColor.toARGB32().toRadixString(16)} 对 band 渐变'
            '两端的对比度 ${minContrast(wordColor, bgs).toStringAsFixed(2)} < $kMin'
            '（夜间看不见就是这个）');

    final rowTexts = find.descendant(
        of: find.byKey(const Key('study.newProgressRow')),
        matching: find.byType(Text));
    expect(rowTexts, findsNWidgets(3),
        reason: '$label：进度行应有 复习 / 新学 / 词频 三段文字');
    for (final el in rowTexts.evaluate()) {
      final t = el.widget as Text;
      final c = t.style?.color;
      expect(c, isNotNull, reason: '$label：「${t.data}」没有显式颜色');
      expect(minContrast(c!, bgs), greaterThanOrEqualTo(kMin),
          reason: '$label：「${t.data}」对比度 '
              '${minContrast(c, bgs).toStringAsFixed(2)} < $kMin');
    }
    expect(find.textContaining('语料排名'), findsOneWidget,
        reason: '$label：这张卡有 rank，词频行应显示');
  }

  testWidgets('夜间：正面单词 / 进度行 / 词频 对 band 底色 ≥ 4.5', (tester) async {
    await pumpStudy(tester, KColors.dark);

    expectFrontReadable(tester, label: '夜间');
  });

  testWidgets('夜间：翻面后释义条文字 ≥ 4.5', (tester) async {
    await pumpStudy(tester, KColors.dark);
    await tapAndSettle(tester, find.text('点一下，看答案'));

    final bgs = bandBgs(tester);

    final meaning = find.byWidgetPredicate((w) {
      if (w is! Text) return false;
      final s = w.data ?? w.textSpan?.toPlainText() ?? '';
      return s.contains('卡洛语') &&
          (w.style?.fontSize == 18 || w.style?.fontSize == 16);
    });
    expect(meaning, findsOneWidget, reason: '翻面后 band 里应有中文释义（18px）');
    final c = tester.widget<Text>(meaning).style!.color!;
    expect(minContrast(c, bgs), greaterThanOrEqualTo(kMin),
        reason: '夜间释义条对比度 ${minContrast(c, bgs).toStringAsFixed(2)} < $kMin');
  });

  testWidgets('浅色：正面单词 / 进度行 / 词频仍然 ≥ 4.5（防止改反）', (tester) async {
    await pumpStudy(tester, KColors.light);
    expectFrontReadable(tester, label: '浅色');
  });

  testWidgets('夜间：拼写题正面的提示框文字 ≥ 4.5', (tester) async {
    await pumpStudy(tester, KColors.dark, spelling: true);

    final surface = KColors.dark.surface;
    for (final t in ['先想想这个词怎么拼', '一格一个字母']) {
      final f = find.text(t);
      expect(f, findsOneWidget, reason: '拼写正面应有「$t」');
      final c = tester.widget<Text>(f).style!.color!;
      expect(contrast(c, surface), greaterThanOrEqualTo(kMin),
          reason: '夜间「$t」对比度 ${contrast(c, surface).toStringAsFixed(2)} < $kMin');
    }
  });

  testWidgets('夜间：完成页标题 ≥ 4.5', (tester) async {
    await pumpStudy(tester, KColors.dark);

    await tapAndSettle(tester, find.text('点一下，看答案'));
    await tapAndSettle(tester, find.text('认识'));

    const titles = [
      '今日卡量是 0',
      '今日卡量已用完',
      '这一组学完了',
      '还没有要学的词',
      '今天没有要学的卡',
      '已加入的词都学完了',
      '今日任务已全部完成！',
    ];
    final title = find.byWidgetPredicate(
        (w) => w is Text && titles.contains(w.data) && w.style?.fontSize == 17);
    expect(title, findsOneWidget, reason: '答完唯一一张卡后应停在完成页');
    final c = tester.widget<Text>(title).style!.color!;
    final surface = KColors.dark.surface;
    expect(contrast(c, surface), greaterThanOrEqualTo(kMin),
        reason: '夜间完成页标题对比度 ${contrast(c, surface).toStringAsFixed(2)} < $kMin');
  });
}
