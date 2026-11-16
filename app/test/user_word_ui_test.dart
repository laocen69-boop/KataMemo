import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/my_words_screen.dart';
import 'package:katamemo/screens/word_detail_screen.dart';
import 'package:katamemo/version.dart' show kAiChat;
import 'package:katamemo/widgets/word_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> settleDb(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
  }

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.setDataVersion(kDataVersion);
    await db.createUserWord(
      word: 'rumah sakit',
      zh: '医院',
      examples: const [
        (i: 'Saya ke rumah sakit.', z: '我去医院。'),
        (i: 'Dia di rumah sakit.', z: '他在医院。'),
      ],
      mnemonic: 'sakit = 痛，rumah = 家 ⇒ 痛的地方 = 医院',
    );
    return db;
  }

  test('多条例句能存下来（例句数量不再固定两条）', () async {
    final db = await seed();
    final card = await db.getWord('rumah sakit');
    expect(card!.examples.length, 2);

    await db.updateUserWord('rumah sakit',
        word: 'rumah sakit',
        zh: '医院',
        examples: const [
          (i: 'e1', z: '一'),
          (i: 'e2', z: '二'),
          (i: 'e3', z: '三'),
          (i: 'e4', z: '四'),
        ]);
    final again = await db.getWord('rumah sakit');
    expect(again!.examples.length, 4, reason: '想加几条就加几条');
    expect(again.examples.last.text, 'e4');
    await db.close();
  });

  testWidgets('我的词库列表：每行有看得见的「改」按钮（不再只靠长按）', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,

      child: const MaterialApp(home: MyWordsTab()),
    ));
    await settleDb(tester);
    expect(find.text('rumah sakit'), findsOneWidget);
    expect(find.byTooltip('改这条卡（词形/中文/例句/助记/发音）'), findsOneWidget);
  });

  testWidgets('自建词的卡片详情：有看得见的「改」入口 + 助记显示出来', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: WordDetailScreen(cardId: 'rumah sakit')),
    ));
    await settleDb(tester);
    expect(find.byTooltip('改这条自建词（词形 / 中文 / 例句 / 助记 / 发音）'), findsOneWidget);
    expect(find.textContaining('痛的地方 = 医院'), findsOneWidget,
        reason: '新建时写的助记必须在详情页显示');
  });

  testWidgets('详情页 P0：section 计数、头部单处查词提示、不再用 Material Chip', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: WordDetailScreen(cardId: 'rumah sakit')),
    ));
    await settleDb(tester);

    expect(find.text('例句'), findsNWidgets(2));
    expect(find.text('2 条'), findsOneWidget);

    expect(find.text('点句中单词可查词'), kAiChat ? findsNothing : findsOneWidget);
    expect(find.byKey(const ValueKey('detail.askAiChip')),
        kAiChat ? findsOneWidget : findsNothing);

    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('详情页 P1：加入记忆写 plan、状态切换；内容索引按 section 生成', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: MaterialApp(

        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const WordDetailScreen(cardId: 'rumah sakit'),
      ),
    ));
    await settleDb(tester);

    expect(find.byKey(const ValueKey('detail-enroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-index-mnemonic')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-index-examples')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-enroll')));
    await settleDb(tester);

    expect(find.byKey(const ValueKey('detail-enrolled')), findsOneWidget);
    final planned =
        await tester.runAsync(() => built.db.isPlanned('rumah sakit'));
    expect(planned, isTrue, reason: '详情页的加入记忆必须落 plan 表');
  });

  testWidgets('速览弹窗也显示助记（用户报「详情界面不显示」的另一半）', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(
          home: Scaffold(body: WordSheet(query: 'rumah sakit'))),
    ));
    await settleDb(tester);
    expect(find.text('助记'), findsOneWidget);
    expect(find.textContaining('痛的地方 = 医院'), findsOneWidget);
  });

  testWidgets('列表页：底部通栏「新建一个词」在，右下角 FAB 已撤掉', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: MyWordsTab()),
    ));
    await settleDb(tester);

    expect(find.text('新建一个词'), findsOneWidget,
        reason: '第五十六轮改成底部通栏，文案是「新建一个词」');

    expect(find.byType(FloatingActionButton), findsNothing,
        reason: '右下角 FAB 已撤销（会盖住列表末尾）');

    expect(find.text('按创建时间'), findsOneWidget);
  });

  testWidgets('搜索无结果时给出可执行的下一步（不是干巴巴一句「没有」）', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: MyWordsTab()),
    ));
    await settleDb(tester);

    await tester.enterText(find.byType(TextField).first, 'zzzz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleDb(tester);
    expect(find.textContaining('没有匹配「zzzz」'), findsOneWidget);

    expect(find.textContaining('直接建一个「zzzz」'), findsOneWidget);
  });

  testWidgets('表单：新建态「导入音频文件」按钮**可点**（不再是一行灰字）', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: MyWordsTab()),
    ));
    await settleDb(tester);

    await tester.tap(find.text('新建一个词'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('新建自建词'), findsOneWidget);

    expect(find.text('导入音频文件'), findsOneWidget,
        reason: '第五十六轮：新建态也能导音频（点它会先落一张草稿卡）');

    expect(find.text('保存'), findsOneWidget);
    await tester.runAsync(() async => built.db.close());
  });

  testWidgets('表单：词形输入即查重（不用等到点保存）', (tester) async {
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: MyWordsTab()),
    ));
    await settleDb(tester);

    await tester.tap(find.text('新建一个词'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    final wordField = find.ancestor(
        of: find.text('印尼语或词组，例如：rumah sakit'),
        matching: find.byType(TextField));
    await tester.enterText(wordField, 'rumah sakit');

    await tester.pump(const Duration(milliseconds: 400));
    await settleDb(tester, rounds: 8);
    expect(find.textContaining('词库里已经有「rumah sakit」'), findsOneWidget,
        reason: '第五十六轮：实时查重，不用等保存');
    expect(find.text('去看'), findsOneWidget);
    await tester.runAsync(() async => built.db.close());
  });
}
