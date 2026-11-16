import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/select_screen.dart';
import 'package:katamemo/widgets/memory_ring.dart';

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

  Future<AppState> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (var i = 1; i <= 201; i++)
        {
          'id': 'w$i',
          'word': 'w$i',
          'tier': 'core',
          'rank': i,
          'zh': '义$i',
          'enabled': 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    await db.planWord([for (var i = 2; i <= 201; i++) 'w$i']);
    final app = AppState(db);
    await app.init();
    return app;
  }

  const book = BookNode(id: 'core', name: '核心词', count: 201, filter: {
    'tier': ['core']
  });

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 8; round++) {
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

  Future<void> pumpList(WidgetTester tester, AppState app) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const WordListScreen(book: book),
        ),
      ));
    });
    await settle(tester);
  }

  Future<void> press(WidgetTester tester, Finder f, {bool long = true}) async {
    await tester.runAsync(() async {
      final g = await tester.startGesture(tester.getCenter(f));
      if (long) await Future<void>.delayed(const Duration(milliseconds: 700));
      await g.up();
      await g.removePointer();
    });
    await settle(tester);
  }

  testWidgets('默认「未选」把已加入的词滤掉：列表被滤空时分页仍自己续完', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);

    expect(find.text('w1'), findsOneWidget);
    expect(find.text('w2'), findsNothing, reason: '已加入记忆的词在「未选」范围（默认高亮那格）下不显示');

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '页脚的转圈停在屏幕上就是用户报的现象');
    expect(find.textContaining('继续下滑加载'), findsNothing,
        reason: '列表短到没有可滚距离，「继续下滑」是不可能完成的任务');
    expect(find.text('— 共 1 词 —'), findsOneWidget,
        reason: '第二页取完了：w2…w201 都在记忆里，被滤掉');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('切到「全部」范围：隐藏的词全回来，分页也已续完', (tester) async {
    final app = (await tester.runAsync(seed))!;
    await pumpList(tester, app);
    expect(find.text('— 共 1 词 —'), findsOneWidget);

    await press(tester, find.byKey(const Key('cell-all')), long: false);

    expect(find.text('w2'), findsOneWidget, reason: '切到「全部」后已加入的词要回来');
    expect(find.textContaining('已隐藏'), findsNothing,
        reason: '旧选词模式那行「已隐藏 N 个」提示已经不存在');

    await tester.dragUntilVisible(
        find.text('— 共 201 词 —'), find.byType(ListView), const Offset(0, -800),
        maxIteration: 40);
    expect(find.text('— 共 201 词 —'), findsOneWidget,
        reason: '两页都取回来了（201 = 全部）');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('记忆模式卡：点一下就换字，不用等下次进页面', (tester) async {

    final app = (await tester.runAsync(() async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await db.upsertWords([
        for (var i = 1; i <= 3; i++)
          {
            'id': 'w$i',
            'word': 'w$i',
            'tier': 'core',
            'rank': i,
            'zh': '义$i',
            'enabled': 1,
            'favorite': 0,
          },
      ]);
      await db.setDataVersion(kDataVersion);
      await db.planWord(['w1', 'w2', 'w3']);
      final app = AppState(db);
      await app.init();
      await app.setAutoSpeak(false);
      return app;
    }))!;

    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const SelectScreen(),
        ),
      ));
    });
    await settle(tester);

    expect(find.text('印尼-中'), findsOneWidget);

    await press(tester, find.byKey(const Key('mode-card')), long: false);

    expect(app.studyMode, 'zh2id', reason: '状态确实切了（这一半本来就没坏）');
    expect(find.text('中-印尼'), findsOneWidget,
        reason: '卡片要自己换成新值——这里红过就说明页面没订阅 studyMode');
    expect(find.text('印尼-中'), findsNothing, reason: '旧值不能留在屏幕上');

    await tester.runAsync(() => app.db.close());
  });

  const t1Book = BookNode(id: 't1', name: '最高频', count: 4, filter: {
    'tier': ['t1']
  });

  Future<AppState> seedLibrary({BookNode? target}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (var i = 1; i <= 4; i++)
        {
          'id': 'a$i',
          'word': 'a$i',
          'tier': 't1',
          'rank': i,
          'zh': '甲$i',
          'enabled': 1,
          'favorite': 0,
        },
      for (var i = 1; i <= 2; i++)
        {
          'id': 'b$i',
          'word': 'b$i',
          'tier': 't2',
          'rank': 10 + i,
          'zh': '乙$i',
          'enabled': 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    await db.planWord(['a1', 'a2', 'b1', 'b2']);
    final app = AppState(db);
    await app.init();
    if (target != null) await app.setBook(target);
    return app;
  }

  Future<void> pumpLibrary(WidgetTester tester, AppState app) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const SelectScreen(),
        ),
      ));
    });
    await settle(tester);
  }

  List<({Color color, double width})> segmentsOf(
      WidgetTester tester, Finder bar) {
    final boxes = find.descendant(of: bar, matching: find.byType(ColoredBox));
    return [
      for (var i = 0; i < boxes.evaluate().length; i++)
        (
          color: tester.widget<ColoredBox>(boxes.at(i)).color,
          width: tester.getSize(boxes.at(i)).width,
        ),
    ];
  }

  Finder cardBar(WidgetTester tester) {
    final bar = find.descendant(
        of: find.byKey(const Key('selected-words-card')),
        matching: find.byType(MemorySegmentBar));
    expect(bar, findsOneWidget, reason: '卡上就一根分段条');
    return bar;
  }

  testWidgets('「已选单词」卡的分段条按整本卡组算（六段，含「未选」）', (tester) async {

    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(() => seedLibrary(target: t1Book)))!;
    await pumpLibrary(tester, app);

    final segs = segmentsOf(tester, cardBar(tester));

    final ctx = tester.element(find.byType(MemorySegmentBar).first);
    expect(segs.length, 2,
        reason: '整本 4 词：已选 2（都还没学过）＋ 未选 2 —— 旧代码这里只有 1 截'
            '（五段条把「未选」整段抹掉了，卡于是永远「满条深灰」）');
    expect(segs[0].color, kMemorySegmentsOf(ctx)[4].color, reason: '已选未学 = 深灰');
    expect(segs[1].color, kUnselectedColor(ctx), reason: '未选 = 淡灰');

    expect(
        find.descendant(
            of: find.byKey(const Key('selected-words-card')),
            matching: find.textContaining('2/4 词')),
        findsOneWidget,
        reason: '分母必须写在卡上，否则用户以为这根条子只数已选的词');

    final trackW = tester.getSize(find.byKey(const Key('book.track-t1'))).width;
    final fillW = tester.getSize(find.byKey(const Key('book.fill-t1'))).width;
    expect(fillW / trackW, closeTo(0.5, 0.02),
        reason: '已加入记忆 2 / 全部 4 ⇒ 进度线填充 50%');
    expect(tester.getSize(find.byKey(const Key('book.fill-t1'))).height, 3,
        reason: '进度线固定 3px');
    expect(
        find.descendant(
            of: find.byKey(const Key('book.row-t1')),
            matching: find.text('50%')),
        findsOneWidget,
        reason: '百分比改成纯文字，跟在同一行');
    expect(find.textContaining('正在学习中'), findsNothing,
        reason: '胶囊已取消');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('左滑提示只有点 ✕ 才消失（并持久化）', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);
    expect(find.text('左滑可设目标'), findsOneWidget);

    await tester.tap(find.byKey(const Key('swipe.hint.close')));
    await settle(tester);
    expect(find.text('左滑可设目标'), findsNothing);
    expect(app.swipeTipDismissed, isTrue);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('左滑卡组出现「设为学习目标」，点击后真的设置（2026-10-18）',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);
    expect(app.book, isNull, reason: '这条用例从「没有目标」开始');

    await tester.drag(
        find.byKey(const Key('book.row-t1')), const Offset(-140, 0));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(milliseconds: 250));
    final actionX =
        tester.getTopLeft(find.byKey(const Key('swipe.action-t1'))).dx;
    expect(actionX, lessThan(380), reason: '动作区应从右侧滑入');
    expect(tester.getTopLeft(find.byKey(const Key('book.row-t1'))).dx, 12,
        reason: '行内容不移动（头像/名称始终可见）');
    expect(find.byKey(const Key('swipe.action-t1')), findsOneWidget,
        reason: '左滑后应露出动作');

    await tester.tap(find.byKey(const Key('swipe.action-t1')));
    await settle(tester);
    expect(app.book?.id, 't1', reason: '点击动作应真的写入学习目标');

    for (var i = 0;
        i < 8 && find.byKey(const Key('target.guide')).evaluate().isEmpty;
        i++) {
      await settle(tester);
    }
    expect(find.byKey(const Key('target.guide')), findsOneWidget,
        reason: '设完目标应弹出引导面板');
    final before = (await tester.runAsync(() => app.db.bookProgress(t1Book.filter)))!;
    expect(before.total, lessThan(before.all),
        reason: '这条用例要从「还有词没加入」开始，才能验加词按钮');
    await tester.tap(find.byKey(const Key('target.addBatch')));
    for (var i = 0;
        i < 8 && find.byKey(const Key('target.guide')).evaluate().isNotEmpty;
        i++) {
      await settle(tester);
    }
    final after = (await tester.runAsync(() => app.db.bookProgress(t1Book.filter)))!;
    expect(after.total, greaterThan(before.total), reason: '点「加入」才真的加词');
    expect(find.byKey(const Key('target.guide')), findsNothing,
        reason: '加完面板应关闭');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('没有目标时「已选单词」卡有「设学习目标」入口，选一档即设为目标（2026-11-06）',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);
    expect(app.book, isNull);

    final pill = find.byKey(const Key('home.pickTarget'));
    expect(pill, findsOneWidget, reason: '没有目标时卡上要直接给入口');
    await tester.tap(pill);
    for (var i = 0;
        i < 8 && find.byKey(const Key('target.picker')).evaluate().isEmpty;
        i++) {
      await settle(tester);
    }
    expect(find.byKey(const Key('target.picker')), findsOneWidget);

    await tester.tap(find.byKey(const Key('target.pick-t1')));
    for (var i = 0;
        i < 8 && find.byKey(const Key('target.guide')).evaluate().isEmpty;
        i++) {
      await settle(tester);
    }
    expect(app.book?.id, 't1', reason: '在面板里点一档就设为目标');
    expect(find.byKey(const Key('target.guide')), findsOneWidget,
        reason: '设完照样弹引导面板');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('取消学习目标：条子跟着重算，不会停在旧卡组的比例上', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary(target: t1Book)))!;
    await pumpLibrary(tester, app);

    expect(segmentsOf(tester, cardBar(tester)).length, 2);

    await press(
        tester,
        find.descendant(
            of: find.byKey(const Key('selected-words-card')),
            matching: find.text('取消目标')),
        long: false);

    await press(
        tester,
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('取消目标')),
        long: false);

    expect(app.book, isNull, reason: '状态确实清了（这一半本来就没坏）');
    expect(find.text('· 全部词汇'), findsOneWidget);

    final segs = segmentsOf(tester, cardBar(tester));
    expect(segs.length, 2);
    expect(
        segs[0].width / (segs[0].width + segs[1].width), closeTo(2 / 3, 0.02),
        reason: '深灰 = 已选 4 个、淡灰 = 未选 2 个（6 个词里）');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('额度对话框：数字能直接用键盘输，不是只能拖滑块', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);

    await press(tester, find.byKey(const Key('quota-card')), long: false);

    expect(find.byType(TextField), findsOneWidget, reason: '数字要能直接敲，不能做成纯展示文本');
    await tester.enterText(find.byType(TextField), '777');
    await tester.pump();

    await tester.tap(find.text('确定'));

    await tester.runAsync(() async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();

    expect(app.dailyQuota, 777, reason: '敲进去的数字要点「确定」后真的生效');

    final again = AppState(app.db);
    await tester.runAsync(() => again.init());
    expect(again.dailyQuota, 777);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('记忆模式 chip：字号 12.5 且点击切换（合成卡右上角）', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);

    final v = tester.widget<Text>(find.text('印尼-中'));
    expect(v.style?.fontSize, 12.5, reason: '合成卡里的模式 chip 比旧卡小一号（20→14→12.5）');

    await press(tester, find.byKey(const Key('mode-card')), long: false);
    expect(app.studyMode, 'zh2id',
        reason: '默认「印尼-中」(id2zh) ⇒ 点一下切到「中-印尼」(zh2id)');
    expect(find.text('中-印尼'), findsOneWidget, reason: 'chip 字要跟着换');
    expect(find.text('印尼-中'), findsNothing, reason: '旧值不能留在屏幕上');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('今日进度卡：统计行三段可点，点开真的出词表（第六十一轮）', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);

    expect(find.byKey(const Key('status-due')), findsOneWidget);
    expect(find.byKey(const Key('status-new')), findsOneWidget);
    expect(find.byKey(const Key('status-left')), findsOneWidget);
    expect(find.byKey(const Key('quota-card')), findsOneWidget);

    expect(find.text('去学习'), findsOneWidget);

    await press(tester, find.byKey(const Key('status-new')), long: false);
    expect(find.text('待新学'), findsOneWidget, reason: '进到了查看页的标题');
    expect(find.text('a1'), findsOneWidget, reason: '页面列出的正是格子上那个数背后的词');
    await press(tester, find.byType(BackButton), long: false);
    expect(find.byKey(const Key('status-new')), findsOneWidget,
        reason: '返回词库页');

    await press(tester, find.byKey(const Key('status-due')), long: false);
    expect(find.text('今天没有到期的复习卡'), findsOneWidget);
    await press(tester, find.byType(BackButton), long: false);

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('今日进度卡：一个词都没加入时不写「今日已完成」（2026-10-23）', (tester) async {
    final app = (await tester.runAsync(() async {
      final a = await seedLibrary();
      await (await a.db.db).delete('plan');
      return a;
    }))!;
    await pumpLibrary(tester, app);

    expect(find.text('今日已完成'), findsNothing,
        reason: '什么都没学过不能说「已完成」（模拟器复查：新用户第一次打开就是这句）');
    expect(find.text('还没选词'), findsOneWidget);

    final go = find.byKey(const Key('status-go'));
    expect(find.descendant(of: go, matching: find.text('去选词')), findsOneWidget,
        reason: '新用户点「去学习」只会看到空页，应直接去选词');
    expect(find.descendant(of: go, matching: find.text('最高频')), findsOneWidget,
        reason: '没设目标时打开第一个还没加满的词频卡组');
    await press(tester, go, long: false);
    expect(find.byType(WordListScreen), findsOneWidget, reason: '点了进到那个卡组的词表');
    expect(await tester.runAsync(() => app.db.planCount()), 0,
        reason: '「去选词」只打开卡组，不能替用户加词');

    await tester.runAsync(() => app.db.close());
  });

  testWidgets('今日进度卡按钮：额度 0 =「改额度」，额度用完还有词 =「加额度」', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await tester.runAsync(() => app.setQuota(0));
    await pumpLibrary(tester, app);
    final go = find.byKey(const Key('status-go'));
    expect(find.descendant(of: go, matching: find.text('改卡量')), findsOneWidget);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('今日进度卡按钮：今天额度学满、池子里还有词 =「加额度 · 还有 N 张」', (tester) async {
    final app = (await tester.runAsync(() async {
      final a = await seedLibrary();
      await a.setQuota(1);

      await a.db.saveSrs('a1', Fsrs.apply(null, Fsrs.ratingKnow));
      return a;
    }))!;
    await pumpLibrary(tester, app);
    final go = find.byKey(const Key('status-go'));
    expect(find.descendant(of: go, matching: find.text('加卡量')), findsOneWidget);
    expect(find.descendant(of: go, matching: find.text('还有 3 张')), findsOneWidget,
        reason: '还没学的 a2 / b1 / b2');
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('已选单词卡参考设计稿参考：比例环 + 四组彩字 + 灰色辅助行（第 21 轮）', (tester) async {
    final app = (await tester.runAsync(() => seedLibrary()))!;
    await pumpLibrary(tester, app);
    final card = find.byKey(const Key('selected-words-card'));

    expect(
        find.descendant(of: card, matching: find.text('67%')), findsOneWidget,
        reason: '环心写已选占比（4/6）');
    expect(find.descendant(of: card, matching: find.byTooltip('更多')),
        findsOneWidget,
        reason: '右上角是竖三点菜单（按设计稿，装 进入词表/设为目标）');

    expect(
        find.descendant(
            of: card, matching: find.byType(CircularProgressIndicator)),
        findsNothing);

    for (final t in const ['已掌握 0', '熟悉 0', '一般 0', '不熟 0']) {
      expect(find.descendant(of: card, matching: find.text(t)), findsOneWidget,
          reason: '「$t」是行三那组彩字之一');
    }

    expect(find.descendant(of: card, matching: find.textContaining('未学 4')),
        findsOneWidget,
        reason: '第五档「未学」挪进辅助行（4 词都是已选未学）');
    expect(find.descendant(of: card, matching: find.textContaining('未选 2')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('4/6 词')),
        findsOneWidget,
        reason: '分母照旧写在卡上');
    expect(find.descendant(of: card, matching: find.textContaining('预计还需')),
        findsOneWidget);

    await tester.runAsync(() => app.db.close());
  });

  test('今日进度条三段权重之和恒为 1000（学完 = 满条）', () {

    expect(todayProgressFlex(reviewDone: 12, newDone: 4, total: 16),
        [750, 250, 0]);

    final half = todayProgressFlex(reviewDone: 6, newDone: 2, total: 16);
    expect(half[0] + half[1] + half[2], 1000);
    expect(half[2], 500);

    expect(todayProgressFlex(reviewDone: 0, newDone: 0, total: 16),
        [0, 0, 1000]);

    final capped = todayProgressFlex(reviewDone: 3, newDone: 1, total: 20);
    expect(capped[0] + capped[1], 200);
    expect(capped[2], 800);

    final over = todayProgressFlex(reviewDone: 13, newDone: 5, total: 16);
    expect(over[2], 0);

    expect(todayProgressFlex(reviewDone: 0, newDone: 0, total: 0),
        [0, 0, 1000]);
  });
}
