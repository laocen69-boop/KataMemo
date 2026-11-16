import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/screens/my_words_screen.dart';
import 'package:katamemo/screens/select_screen.dart';
import 'package:katamemo/screens/word_pick_screen.dart';

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

  Future<AppDb> seedDb() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'makan',
        'word': 'makan',
        'tier': 't1',
        'rank': 1,
        'zh': '吃',
        'enabled': 1,
        'favorite': 0,
      },
      {
        'id': 'minum',
        'word': 'minum',
        'tier': 't1',
        'rank': 2,
        'zh': '喝',
        'enabled': 1,
        'favorite': 0,
      },
      {
        'id': 'rumah',
        'word': 'rumah',
        'tier': 't2',
        'rank': 3,
        'zh': '房子',
        'enabled': 1,
        'favorite': 0,
      },
      {
        'id': 'pergi',
        'word': 'pergi',
        'tier': 't2',
        'rank': 4,
        'zh': '去',
        'enabled': 1,
        'favorite': 0,
      },
    ]);
    await db.setDataVersion(kDataVersion);
    return db;
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

  Future<void> pumpDetail(
      WidgetTester tester, AppState app, int id) async {
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: WordListDetailScreen(listId: id, title: '清单'),
      ),
    ));
    await settle(tester);
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  test('新建不重名覆盖；改名按主键、拒绝重名', () async {
    final db = await seedDb();
    final id = await db.createWordList('高频', ['makan', 'minum']);
    expect(id, isNotNull);

    expect(await db.createWordList('高频', ['rumah']), isNull);
    expect(await db.createWordList('高 频', ['rumah']), isNotNull);
    expect(await db.wordListIds(id!), ['makan', 'minum']);

    final other = (await db.createWordList('另一张', []))!;
    expect(await db.renameWordList(id, '另一张'), isFalse,
        reason: '撞名必须拒绝，不能像 saveWordList 那样静默覆盖');
    expect(await db.renameWordList(id, '新名字'), isTrue);
    expect(await db.wordListIds(id), ['makan', 'minum'],
        reason: '改名是 UPDATE，主键与成员都不变');
    expect(await db.wordListIds(other), isEmpty);

    await db.saveWordList('新名字', ['pergi']);
    expect(await db.wordListIds(id), ['pergi']);
    await db.close();
  });

  test('增删词保序去重，且不碰 plan / srs', () async {
    final db = await seedDb();
    final id = (await db.createWordList('清单', ['makan']))!;
    await db.planWord(['makan']);
    await db.saveSrs(
        'minum',
        FsrsState(
          stability: 3,
          difficulty: 5,
          due: DateTime.now().add(const Duration(days: 1)),
          reps: 1,
        ));

    await db.updateWordListIds(id, ['rumah', 'makan', 'rumah', 'pergi']);
    expect(await db.wordListIds(id), ['rumah', 'makan', 'pergi'],
        reason: '顺序保留、重复去掉');

    expect(await db.isPlanned('makan'), isTrue, reason: '词单增删不碰 plan');
    expect(await db.getSrs('minum'), isNotNull, reason: '词单增删不碰 srs');
    await db.close();
  });

  test('wordListStats：joined = enabled && (plan||srs)，learned 是子集', () async {
    final db = await seedDb();
    final id = (await db.createWordList(
        '清单', ['makan', 'minum', 'rumah', 'ghost']))!;
    await db.planWord(['makan']);
    await db.saveSrs(
        'minum',
        FsrsState(
          stability: 3,
          difficulty: 5,
          due: DateTime.now().add(const Duration(days: 1)),
          reps: 1,
        ));

    final s = (await db.wordListStat(id))!;
    expect(s.count, 3, reason: 'ghost 不在 words 表，不计入');
    expect(s.joined, 2);
    expect(s.learned, 1);

    await db.unenroll(['makan']);
    final s2 = (await db.wordListStat(id))!;
    expect(s2.joined, 1);
    expect(s2.learned, 1);
    expect(await db.getSrs('minum'), isNotNull, reason: '移出记忆保留进度');
    await db.close();
  });

  testWidgets('详情概览三数；批量移出词单只动 ids', (tester) async {
    final app = (await tester.runAsync(() async {
      final db = await seedDb();
      final id = (await db.createWordList(
          '清单', ['makan', 'minum', 'rumah']))!;
      await db.planWord(['makan']);
      await db.saveSrs(
          'minum',
          FsrsState(
            stability: 3,
            difficulty: 5,
            due: DateTime.now().add(const Duration(days: 1)),
            reps: 1,
          ));
      return (AppState(db), id);
    }))!;
    final a = app.$1;
    final id = app.$2;

    await pumpDetail(tester, a, id);
    expect(find.text('清单'), findsOneWidget);
    expect(find.text('1 已学 · 1 未加入'), findsOneWidget);

    await tester.tap(find.text('管理'));
    await tester.pump();
    expect(find.text('已选 0 个'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wordlist.word-makan')));
    await tester.pump();
    expect(find.text('已选 1 个'), findsOneWidget);
    expect(find.text('移出词单 1'), findsOneWidget);

    await tester.tap(find.text('移出词单 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('把勾选的 1 个词移出词单？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '移出'));
    await settle(tester);

    final ids = await tester.runAsync(() => a.db.wordListIds(id));
    expect(ids, ['minum', 'rumah']);
    final planned = await tester.runAsync(() => a.db.isPlanned('makan'));
    expect(planned, isTrue, reason: '移出词单不能动 plan');
    final srs = await tester.runAsync(() => a.db.getSrs('minum'));
    expect(srs, isNotNull, reason: '移出词单不能动 srs');
    expect(find.byKey(const Key('wordlist.word-makan')), findsNothing);

    await disposeTree(tester);
    await tester.runAsync(() => a.db.close());
  });

  testWidgets('管理态批量加入记忆：只对未加入的写 plan', (tester) async {
    final app = (await tester.runAsync(() async {
      final db = await seedDb();
      final id = (await db.createWordList('清单', ['makan', 'minum']))!;
      await db.planWord(['makan']);
      return (AppState(db), id);
    }))!;
    final a = app.$1;

    await pumpDetail(tester, a, app.$2);
    await tester.tap(find.text('管理'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wordlist.word-makan')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('wordlist.word-minum')));
    await tester.pump();
    expect(find.text('加入记忆 1'), findsOneWidget,
        reason: 'makan 已在记忆里，不能再算一张');

    await tester.tap(find.text('加入记忆 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('加入后按每天的卡量排队，不会一次塞进今天的学习。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '加入记忆'));
    await settle(tester);

    final p1 = await tester.runAsync(() => a.db.isPlanned('makan'));
    final p2 = await tester.runAsync(() => a.db.isPlanned('minum'));
    expect(p1, isTrue);
    expect(p2, isTrue);

    await disposeTree(tester);
    await tester.runAsync(() => a.db.close());
  });

  testWidgets('添加页：已在词单灰显不可选，选中后返回 id', (tester) async {
    final app = (await tester.runAsync(() async {
      final db = await seedDb();
      return AppState(db);
    }))!;
    List<String>? picked;

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await Navigator.push<List<String>>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) =>
                          const WordPickScreen(existingIds: {'makan'}),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('makan'), findsOneWidget);
    expect(find.text('已在词单'), findsOneWidget);
    expect(find.text('minum'), findsOneWidget);

    await tester.tap(find.text('minum'));
    await tester.pump();
    expect(find.text('已选 1 个'), findsOneWidget);

    await tester.tap(find.text('添加到词单'));
    await tester.pumpAndSettle();
    expect(picked, ['minum']);

    await disposeTree(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('列表页显示三数；空态有两个明确入口', (tester) async {
    final app = (await tester.runAsync(() async {
      final db = await seedDb();
      await db.createWordList('清单', ['makan', 'minum']);
      await db.planWord(['makan']);
      return AppState(db);
    }))!;

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const MyScreen(),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('词单'));
    await tester.pump();
    await settle(tester);

    expect(find.text('清单'), findsOneWidget);
    expect(find.text('2 词 · 1 已加入 · 0 已学'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await disposeTree(tester);

    await tester.runAsync(() async {
      await app.db.deleteWordList(
          (await app.db.listWordLists()).first.$1);
    });
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const MyScreen(),
      ),
    ));
    await settle(tester);
    await tester.tap(find.text('词单'));
    await tester.pump();
    await settle(tester);
    expect(find.text('还没有词单'), findsOneWidget);
    expect(find.text('去词库挑词'), findsOneWidget);
    expect(find.text('新建空词单'), findsOneWidget);

    await disposeTree(tester);
    await tester.runAsync(() => app.db.close());
  });
}
