library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/screens/grammar/grammar_hub_screen.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/grammar/g_blocks.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _raw() => File('test/fixtures/grammar_v2_sample.json').readAsStringSync();

GrammarRepo _repo() => GrammarRepo(autoLoad: false)..loadFromJson(_raw());

AppState _app(GrammarRepo repo) => AppState(
    AppDb(
        dbPath:
            '${Directory.systemTemp.path}/gram_ui_${DateTime.now().microsecondsSinceEpoch}.db'),
    grammar: repo);

Widget _wrap(AppState app, Widget home, {bool dark = false}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: (dark ? ThemeData.dark() : ThemeData()).copyWith(
            splashFactory: NoSplash.splashFactory,
            extensions: [dark ? KColors.dark : KColors.light]),
        home: home,
      ),
    );

Future<void> _pumpApp(WidgetTester tester, AppState app, Widget home,
    {bool dark = false}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(_wrap(app, home, dark: dark));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
}

Future<void> _tapAsync(WidgetTester tester, Finder f) => tester.runAsync(() async {
      await tester.tap(f);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('知识点页：每种块都渲染；表格 U+3000 拆行；** 不漏到界面', (tester) async {
    _tallView(tester);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(tester, app, GrammarPageScreen(repo: repo, page: repo.pageById['af-me']!));
    expect(tester.takeException(), isNull);

    expect(find.text('me- 前缀'), findsOneWidget);
    expect(find.text('prefiks meN-'), findsOneWidget);
    expect(find.text('结论'), findsOneWidget);
    expect(find.text('易错'), findsOneWidget);
    expect(find.text('音变表'), findsOneWidget);
    expect(find.text('baca → membaca'), findsOneWidget, reason: 'U+3000 分隔的格拆成多行');
    expect(find.text('pukul → memukul'), findsOneWidget);
    expect(find.text('我读书。'), findsOneWidget);
    expect(find.text('membaca'), findsWidgets, reason: '例句逐词可点（TappableIdText 拆词）');
    expect(find.textContaining('**'), findsNothing);

    expect(find.text('ter- 前缀 ›'), findsOneWidget);
    expect(find.byKey(const ValueKey('gram-toc')), findsOneWidget);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('对照块与决策树、词表块都能渲染', (tester) async {
    _tallView(tester);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(
        tester, app, GrammarPageScreen(repo: repo, page: repo.pageById['vs-kan-i']!));
    expect(tester.takeException(), isNull);
    expect(find.text('me-kan'), findsWidgets);
    expect(find.text('宾语被移动'), findsOneWidget);
    expect(find.text('宾语是地方'), findsOneWidget);
    expect(find.text('先问：宾语是东西还是地方？'), findsOneWidget);
    expect(find.text('宾语是什么？'), findsOneWidget);
    expect(find.byKey(const ValueKey('gram-toc')), findsNothing, reason: '没有小标题就不出目录');

    await _pumpApp(tester, app,
        GrammarPageScreen(key: const ValueKey('yang'), repo: repo, page: repo.pageById['wc-yang']!));
    expect(find.text('相关词'), findsOneWidget);
    expect(find.text('yang'), findsWidgets);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('Hub：常查 / 学习路线 / 分区；→ 分区页 → 知识点页', (tester) async {
    _tallView(tester);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(tester, app, const GrammarHubScreen());
    expect(find.text('常查'), findsOneWidget);
    expect(find.byKey(const ValueKey('gram-hot-af-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('gram-path')), findsOneWidget);
    expect(find.text('0 / 3'), findsOneWidget, reason: '学习路线进度');
    for (final s in ['affix', 'contrast', 'wordclass']) {
      expect(find.byKey(ValueKey('gram-sec-$s')), findsOneWidget);
    }
    expect(find.text('2 页'), findsOneWidget, reason: '没读过时显示页数');

    await _tapAsync(tester, find.byKey(const ValueKey('gram-sec-affix')));
    expect(find.byType(GrammarPageListScreen), findsOneWidget);
    expect(find.text('前缀'), findsOneWidget, reason: '分组标题');
    expect(find.text('构成主动动词；词首音变有规律。'), findsOneWidget, reason: '每行带一句话');

    await _tapAsync(tester, find.byKey(const ValueKey('gram-row-af-ter')));
    expect(find.byType(GrammarPageScreen), findsOneWidget);
    expect(find.text('ter- 三种意思：无意、状态、最高级。'), findsOneWidget);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('学习路线页：带序号，顺序照 path', (tester) async {
    _tallView(tester);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(tester, app, GrammarPageListScreen.path(repo));
    final y = [
      for (final id in repo.doc.path)
        tester.getTopLeft(find.byKey(ValueKey('gram-row-$id'))).dy
    ];
    expect(y, orderedEquals([...y]..sort()));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('停留够久才写 seen_at；回到分区页打勾、继续阅读出现', (tester) async {
    _tallView(tester);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(
        tester,
        app,
        GrammarPageScreen(
            repo: repo,
            page: repo.pageById['af-me']!,
            dwell: const Duration(milliseconds: 700)));

    await tester.runAsync(() => app.db.flushGrammarWrites());
    expect((await tester.runAsync(() => app.db.grammarProgress('af-me')))?.seenAt, isNull);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await app.db.flushGrammarWrites();
    });
    expect((await tester.runAsync(() => app.db.grammarProgress('af-me')))!.seenAt,
        isNotNull);
    expect(await tester.runAsync(() => app.db.grammarLastCard()), 'af-me');

    await _pumpApp(tester, app, GrammarPageListScreen.section(repo, repo.sectionById['affix']!));
    final row = find.byKey(const ValueKey('gram-row-af-me'));
    expect(find.descendant(of: row, matching: find.byIcon(Icons.check)), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('gram-row-af-ter')),
            matching: find.byIcon(Icons.check)),
        findsNothing);

    await _pumpApp(tester, app, const GrammarHubScreen(key: ValueKey('hub2')));
    expect(find.byKey(const ValueKey('gram-continue')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget, reason: '词缀分区读了 1 页');
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('语法数据后到（重试成功）时 Hub 自己刷新，不靠 AppState 通知', (tester) async {
    final repo = GrammarRepo(autoLoad: false);
    final app = _app(repo);
    await _pumpApp(tester, app, const GrammarHubScreen());
    expect(find.text('内容加载中…'), findsOneWidget);

    await tester.runAsync(() async {
      repo.loadFromJson(_raw());
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    expect(find.text('内容加载中…'), findsNothing);
    expect(find.text('全部分区'), findsOneWidget);
  });

  testWidgets('320×568 窄屏不溢出（Hub / 分区 / 带表格与对照的页）', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(tester, app, const GrammarHubScreen());
    expect(tester.takeException(), isNull);
    await _pumpApp(tester, app, GrammarPageListScreen.section(repo, repo.sectionById['affix']!));
    expect(tester.takeException(), isNull);
    for (final id in ['af-me', 'vs-kan-i']) {
      await _pumpApp(tester, app,
          GrammarPageScreen(key: ValueKey(id), repo: repo, page: repo.pageById[id]!));
      expect(tester.takeException(), isNull, reason: '$id 在 320 宽上溢出了');
    }
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('暗色主题下可读（走令牌）', (tester) async {
    final repo = _repo();
    final app = _app(repo);
    await _pumpApp(tester, app,
        GrammarPageScreen(repo: repo, page: repo.pageById['af-me']!), dark: true);
    expect(tester.takeException(), isNull);
    final ctx = tester.element(find.text('me- 前缀'));
    expect(ctx.k.bg, KColors.dark.bg);
    expect(ctx.k.gWarn, KColors.dark.gWarn);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('GRichText：** 成对加粗，奇数个 ** 不崩', (tester) async {
    final app = _app(_repo());
    await _pumpApp(
        tester,
        app,
        const Scaffold(
            body: Column(children: [
          GRichText('a **b** c', style: TextStyle(fontSize: 14)),
          GRichText('坏 **数据', style: TextStyle(fontSize: 14)),
          GBlockView(block: GUnknownBlock('x')),
        ])));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('阅读页向下滚动到第 4 节时，上方目录胶囊横向自动跟随滚动进视口', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final raw = jsonEncode({
      'v': 2,
      'sections': [
        {
          'id': 's1',
          'title': '测试专题',
          'subtitle': '',
          'groups': [
            {'title': '', 'pages': ['scroll-sync']},
          ],
        },
      ],
      'pages': [
        {
          'id': 'scroll-sync',
          'section': 's1',
          'title': '多节长页',
          'blocks': [
            for (var i = 1; i <= 5; i++) ...[
              {'t': 'h', 'text': '第$i节长标题示例'},
              {
                't': 'lead',
                'text': List.filled(24, '第$i节正文内容占高行').join('\n'),
              },
            ],
          ],
        },
      ],
    });
    final repo = GrammarRepo(autoLoad: false)..loadFromJson(raw);
    final page = repo.pageById['scroll-sync']!;
    final app = _app(repo);
    await _pumpApp(tester, app, GrammarPageScreen(repo: repo, page: page));
    await tester.pumpAndSettle();

    final pill4Before = tester.getTopLeft(find.byKey(const ValueKey('gram-index-3')));
    expect(pill4Before.dx, greaterThanOrEqualTo(320),
        reason: '窄屏初始时第 4 个胶囊应在视口右侧之外');

    final vScroll = find.byType(CustomScrollView).first;
    await tester.drag(vScroll, const Offset(0, -2200));
    await tester.pumpAndSettle();
    await tester.drag(vScroll, const Offset(0, -2200));
    await tester.pumpAndSettle();

    final pill4Rect = tester.getRect(find.byKey(const ValueKey('gram-index-3')));
    expect(pill4Rect.left, greaterThanOrEqualTo(0));
    expect(pill4Rect.right, lessThanOrEqualTo(320));
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });
}
