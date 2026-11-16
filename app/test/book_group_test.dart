library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/select_screen.dart';
import 'package:katamemo/widgets/speak_button.dart';
import 'package:katamemo/widgets/word_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  Future<AppState> seed({List<String> enroll = const []}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'a1',
        'word': 'a1',
        'tier': 't1',
        'rank': 1,
        'zh': '甲一',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'a2',
        'word': 'a2',
        'tier': 't1',
        'rank': 2,
        'zh': '甲二',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'b',
        'word': 'b',
        'tier': 't2',
        'rank': 3,
        'zh': '乙',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'c',
        'word': 'c',
        'tier': 't2',
        'rank': 4,
        'zh': '丙',
        'enabled': 1,
        'favorite': 0
      },
    ]);
    await db.setDataVersion(kDataVersion);
    if (enroll.isNotEmpty) await db.planWord(enroll);
    final app = AppState(db);
    await app.init();
    return app;
  }

  const book = BookNode(id: 'mix', name: '混合卡组', count: 4, filter: {
    'tier': ['t1', 't2']
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 30; round++) {
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
  }

  Future<void> flush(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpList(WidgetTester tester, AppState app,
      {BookNode b = book, bool fromStudy = false}) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: WordListScreen(book: b, fromStudy: fromStudy),
        ),
      ));
    });
    await settle(tester);
  }

  Future<AppState> seedBig() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (var i = 1; i <= 200; i++)
        {
          'id': 'a$i',
          'word': 'a$i',
          'tier': 't1',
          'rank': i,
          'zh': '甲$i',
          'enabled': 1,
          'favorite': 0
        },
      for (var i = 1; i <= 200; i++)
        {
          'id': 'b$i',
          'word': 'b$i',
          'tier': 't2',
          'rank': 200 + i,
          'zh': '乙$i',
          'enabled': 1,
          'favorite': 0
        },
    ]);
    await db.setDataVersion(kDataVersion);
    final app = AppState(db);
    await app.init();
    return app;
  }

  const bookBig = BookNode(id: 'big', name: '大卡组', count: 400, filter: {
    'tier': ['t1', 't2']
  });

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await flush(tester);
    await settle(tester);
    await flush(tester);
  }

  String cellText(WidgetTester tester, String key, String value) {
    final t =
        find.descendant(of: find.byKey(Key(key)), matching: find.text(value));
    return t.evaluate().isEmpty ? '' : value;
  }

  testWidgets('进度细条：一个词都没加入时不说「本库已全部学过」（2026-10-22）',
      (tester) async {
    final app = (await tester.runAsync(() => seed()))!;
    await pumpList(tester, app);
    expect(find.text('本库已全部学过'), findsNothing,
        reason: '在记忆 0 词 ⇒ 未学数也是 0，但这不等于「学完了」');
    expect(find.text('还没有词加入记忆'), findsOneWidget);
  });

  testWidgets('四格统计条：等宽、数字对得上、点格切范围（高亮跟着走）', (tester) async {
    final app = (await tester.runAsync(() => seed(enroll: ['a1', 'a2'])))!;
    await pumpList(tester, app);

    const keys = ['cell-unselected', 'cell-selected', 'cell-all', 'cell-today'];
    final widths = [
      for (final k in keys) tester.getSize(find.byKey(Key(k))).width
    ];
    for (var i = 1; i < widths.length; i++) {
      expect(widths[i], closeTo(widths[0], 0.5),
          reason: '第 $i 格宽 ${widths[i]} ≠ 第 0 格宽 ${widths[0]}');
    }

    expect(cellText(tester, 'cell-unselected', '2'), '2');
    expect(cellText(tester, 'cell-selected', '50%'), '50%');
    expect(cellText(tester, 'cell-all', '4'), '4');
    expect(cellText(tester, 'cell-today', '0'), '0');

    Color bgOf(String key) {
      final d = find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(DecoratedBox));
      final box = tester.widget<DecoratedBox>(d.first);
      return (box.decoration as BoxDecoration).color ?? Colors.transparent;
    }

    expect(bgOf('cell-unselected'), const Color(0xFFF1F3F6));
    expect(bgOf('cell-all'), Colors.transparent);

    expect(find.text('a1'), findsNothing, reason: '默认「未选」：已加入的不显示');
    expect(find.text('b'), findsOneWidget);

    await tap(tester, find.byKey(const Key('cell-all')));
    expect(find.text('a1'), findsOneWidget, reason: '「全部」：已加入的回来');
    expect(bgOf('cell-all'), const Color(0xFFF1F3F6), reason: '高亮跟着生效的那格走');
    expect(bgOf('cell-unselected'), Colors.transparent);

    await tap(tester, find.byKey(const Key('cell-selected')));
    expect(find.text('a1'), findsOneWidget);
    expect(find.text('b'), findsNothing, reason: '「已选」只看已加入的');

    await tap(tester, find.byKey(const Key('cell-unselected')));
    expect(find.text('b'), findsOneWidget);
    await tap(tester, find.byType(RingCheck).first);
    expect(cellText(tester, 'cell-today', '2'), '2',
        reason: '整组勾上：t2 组两行都还没加入 ⇒ 勾中 2');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('分组头跟排序走：词频序按档、字母序按首字母，可折叠', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    expect(find.text('最高频'), findsOneWidget);
    expect(find.text('高频'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2), reason: '两组各 2 条');

    await tap(tester, find.text('最高频'));
    expect(find.text('a1'), findsNothing, reason: '折叠后组内的行不显示');
    expect(find.text('最高频'), findsOneWidget, reason: '组头自己不消失');
    expect(find.text('2'), findsNWidgets(2), reason: '条数是整组的 SQL 计数，不随折叠变');

    await tap(tester, find.text('最高频'));
    expect(find.text('a1'), findsOneWidget, reason: '再点展开');

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A→Z'));
    await tester.pumpAndSettle();
    await flush(tester);

    expect(find.text('最高频'), findsNothing, reason: '字母序下不再按档分组');
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'A 组 2 条');
    expect(find.text('1'), findsNWidgets(2), reason: 'B、C 组各 1 条');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('折叠分组不会立刻把下一页灌回来（第 36 轮修的「折叠闪动」）', (tester) async {

    final app = (await tester.runAsync(seedBig))!;
    await pumpList(tester, app, b: bookBig);

    expect(find.text('最高频'), findsOneWidget);
    expect(find.text('高频'), findsNothing, reason: '第一页 200 条全是 t1，t2 还没加载');

    await tap(tester, find.text('最高频'));
    expect(find.text('a1'), findsNothing, reason: '折叠后组内的行不显示');
    expect(find.text('高频'), findsNothing,
        reason: '折叠后自动续页把 t2 的 200 行灌了进来 = 用户看到的「闪动」');

    await tap(tester, find.text('最高频'));
    expect(find.text('a1'), findsOneWidget, reason: '再点展开');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('「已选」百分比文本：整数不带小数、小数留一位、小到看不清给 <0.1%', (tester) async {

    expect(pctLabel(0, 4), '0%');
    expect(pctLabel(2, 4), '50%');
    expect(pctLabel(4, 4), '100%');
    expect(pctLabel(3, 4), '75%');
    expect(pctLabel(1, 3), '33.3%');
    expect(pctLabel(2, 3), '66.7%');
    expect(pctLabel(32637, 32637), '100%');

    expect(pctLabel(1, 32637), '<0.1%');
    expect(pctLabel(0, 0), '0%', reason: '空词库不能除零');
    expect(pctLabel(5, 3), '100%', reason: '分子超分母（词库删过词）也要夹住');
  });

  testWidgets('底部绿钮「加入记忆」：0 时禁用，勾上就亮，点了真的写进记忆', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    final off = find.widgetWithText(FilledButton, '加入记忆 0');
    expect(off, findsOneWidget);
    expect(tester.widget<FilledButton>(off).onPressed, isNull,
        reason: '一个都没勾时不该能点');

    await tap(tester, find.byType(RingCheck).first);
    expect(cellText(tester, 'cell-today', '2'), '2', reason: '第四格与绿钮分子必须是同一个数');
    final on = find.widgetWithText(FilledButton, '加入记忆 2');
    expect(tester.widget<FilledButton>(on).onPressed, isNotNull);

    await tap(tester, on);

    expect(find.textContaining('已把 2 个词加入记忆'), findsOneWidget);

    await flush(tester);
    final planned = (await tester
        .runAsync(() => app.db.plannedIds(['a1', 'a2', 'b', 'c'])))!;
    expect(planned.length, 2, reason: '真的写进 plan 了，不只是提示条');

    expect(find.text('a1'), findsNothing);
    expect(cellText(tester, 'cell-unselected', '2'), '2');
    expect(cellText(tester, 'cell-selected', '50%'), '50%');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('顺选/随机是可取消的互斥开关（2026-10-18）', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    FilledButton seqBtn() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '顺选'));
    FilledButton rndBtn() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '随机'));
    bool lit(FilledButton b) {
      final s = b.style?.side?.resolve(const <WidgetState>{});
      return s != null && s.style != BorderStyle.none && s.width > 0;
    }

    expect(lit(seqBtn()), isFalse, reason: '初始没有绿框');
    expect(lit(rndBtn()), isFalse, reason: '初始没有绿框');

    await tap(tester, find.widgetWithText(FilledButton, '顺选'));
    expect(lit(seqBtn()), isTrue);
    expect(lit(rndBtn()), isFalse);
    expect(find.widgetWithText(FilledButton, '加入记忆 4'), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, '顺选'));
    expect(lit(seqBtn()), isFalse);
    expect(find.widgetWithText(FilledButton, '加入记忆 0'), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, '顺选'));
    await tap(tester, find.widgetWithText(FilledButton, '随机'));
    expect(lit(seqBtn()), isFalse);
    expect(lit(rndBtn()), isTrue);
    expect(find.widgetWithText(FilledButton, '加入记忆 4'), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, '随机'));
    expect(lit(rndBtn()), isFalse);
    expect(find.widgetWithText(FilledButton, '加入记忆 0'), findsOneWidget);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('顺选/随机只勾选不写入（第三十四轮：点加入记忆才真正加入）', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    await tap(tester, find.widgetWithText(FilledButton, '顺选'));
    expect(find.textContaining('已按当前顺序勾上 4 个词'), findsOneWidget);
    expect(cellText(tester, 'cell-today', '4'), '4');
    final planned0 = (await tester
        .runAsync(() => app.db.plannedIds(['a1', 'a2', 'b', 'c'])))!;
    expect(planned0, isEmpty, reason: '顺选只是挑选帮手：点了「加入记忆」之前不许写 plan');

    final green = find.widgetWithText(FilledButton, '加入记忆 4');
    final noticeTop = tester.getTopLeft(find.textContaining('已按当前顺序勾上')).dy;
    final greenTop = tester.getTopLeft(green).dy;
    expect(noticeTop, lessThan(greenTop), reason: '提示条在底条上方，绝不能盖住按钮');

    await tap(tester, green);
    await flush(tester);
    final ids = await tester.runAsync(() async {
      final d = await app.db.db;
      final rows = await d.rawQuery('SELECT card_id FROM plan ORDER BY rowid');
      return [for (final r in rows) r['card_id'] as String];
    });
    expect(ids, ['a1', 'a2', 'b', 'c'],
        reason: '顺选勾上的顺序 = 列表从上到下（词频序），加入按同一批写入');

    await tap(tester, find.widgetWithText(FilledButton, '随机'));
    expect(find.textContaining('已经没有可勾选的词'), findsOneWidget,
        reason: '剩下的都已在记忆里 ⇒ 没有候选');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('⋮ 批量移出：全选已加入 → 移出勾选的词（需确认），真的删 plan', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    await tap(tester, find.widgetWithText(FilledButton, '顺选'));
    await tap(tester, find.widgetWithText(FilledButton, '加入记忆 4'));
    await flush(tester);

    await tap(tester, find.byKey(const Key('cell-selected')));
    await settle(tester);

    expect(find.byWidgetPredicate((w) => w is RingCheck && w.member),
        findsNWidgets(4),
        reason: '已选范围的 4 行都该有「已在记忆」的灰勾标记');

    await tap(tester,
        find.byWidgetPredicate((w) => w is RingCheck && w.member).first);
    expect(cellText(tester, 'cell-today', '0'), '0',
        reason: '已加入的词是**移出**候选，不进绿钮的加入计数');

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tap(tester, find.text('全选已加入'));
    await settle(tester);

    await tester.tap(find.byTooltip('更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tap(tester, find.textContaining('移出勾选'));
    await settle(tester);
    expect(find.text('把勾选的 4 个词移出记忆？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移出'));

    await flush(tester);

    final planned = (await tester
        .runAsync(() => app.db.plannedIds(['a1', 'a2', 'b', 'c'])))!;
    expect(planned, isEmpty, reason: '批量移出必须真的删 plan，不只是提示条');

    await flush(tester);
    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('顶栏放大镜：点开才有搜索框（autofocus），收起连查询一起清', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);
    expect(find.byType(TextField), findsNothing,
        reason: '搜索框收在放大镜后面（用户拍板「顶栏放大镜点开」）');

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue,
        reason: '点开就要能直接打字，不用再点一下输入框');

    await tester.enterText(find.byType(TextField), 'a1');

    tester.widget<TextField>(find.byType(TextField)).onSubmitted!('a1');
    for (var i = 0;
        i < 12 && find.textContaining('命中').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('命中 1 个'), findsOneWidget,
        reason: '_runSearch 真的跑完了（结果数 = a1 一条）');

    expect(
        find.descendant(of: find.byType(ListView), matching: find.text('a1')),
        findsOneWidget);
    expect(find.text('b'), findsNothing, reason: '搜的是结果，不是全列表');
    expect(find.text('最高频'), findsNothing, reason: '搜索结果按相关度平铺，不分组');

    await tap(tester, find.byTooltip('收起搜索'));
    expect(find.byType(TextField), findsNothing,
        reason: '收起 = 连查询一起清掉，不留「看得见结果却关不掉」的页面');
    expect(find.text('b'), findsOneWidget, reason: '回到全列表');
    expect(find.text('最高频'), findsOneWidget, reason: '分组跟着回来');

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('行长相按设计稿：喇叭 + `>`、没有方形加入框、行高等高', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    final tiles = find.byType(ListTile);
    final n = tiles.evaluate().length;
    expect(n, greaterThan(0), reason: '至少建出来几行');

    expect(find.byType(SpeakButton).evaluate().length, n);
    expect(find.byIcon(Icons.chevron_right).evaluate().length, n,
        reason: '> 是行尾的进详情提示（按设计稿）');

    expect(find.byTooltip('加入记忆'), findsNothing);
    expect(find.byTooltip('移出记忆'), findsNothing,
        reason: '方形框按设计稿去了；长按 / 圆圈 / 底部三钮都能做这件事');

    final heights = [
      for (final e in tiles.evaluate())
        tester.getSize(find.byWidget(e.widget)).height
    ];
    final h0 = heights.first;
    for (final h in heights) {
      expect(h, closeTo(h0, 0.5), reason: '「布局大小一致」：任何一行都不能被内容撑高');
    }

    await flush(tester);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('fromStudy：左上角换成「返回学习页面」胶囊，尺寸不破、点它返回',
      (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app, fromStudy: true);

    final label = find.text('返回学习页面');
    expect(label, findsOneWidget, reason: '从学习页进来必须有这枚按钮');
    expect(find.byIcon(Icons.arrow_back), findsNothing,
        reason: '胶囊顶掉默认返回箭头，不能两个都占左上角');

    final pill = find.ancestor(of: label, matching: find.byType(Container)).first;
    final box = tester.widget<Container>(pill);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, kSpeakGreen, reason: '绿底');
    expect(deco.borderRadius, BorderRadius.circular(9), reason: '偏圆角');
    expect(tester.widget<Text>(label).style?.color, Colors.white, reason: '白字');
    expect(tester.widget<Text>(label).maxLines, 1, reason: '只准一行');

    final barH = tester.getSize(find.byType(AppBar)).height;
    expect(barH, 56, reason: '工具条高度不许变');
    final size = tester.getSize(pill);
    expect(size.height, greaterThanOrEqualTo(28),
        reason: '胶囊还得是个能点的方块');
    expect(size.height, lessThanOrEqualTo(barH),
        reason: '胶囊不能穿模超出工具条');
    expect(size.height, lessThan(size.width),
        reason: '「返回学习页面」必须是一行，不是竖排');
    expect(size.width, lessThanOrEqualTo(100),
        reason: '别把返回位撑太宽（leadingWidth 只给了 100）');

    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(find.byType(WordListScreen), findsNothing);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('词库页正常进来：没有「返回学习页面」，顶栏还是原来那样', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);
    expect(find.text('返回学习页面'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.runAsync(() => app.db.close());
  });
}
