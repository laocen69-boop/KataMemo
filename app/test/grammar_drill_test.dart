library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/screens/grammar/drill_runner_screen.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/grammar/tree_block.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GrammarRepo _fixture() => GrammarRepo(autoLoad: false)
  ..loadFromJson(File('test/fixtures/grammar_v2_sample.json').readAsStringSync());

String _tmp(String tag) =>
    '${Directory.systemTemp.path}/katamemo_$tag'
    '_${DateTime.now().microsecondsSinceEpoch}.db';

AppState _app(GrammarRepo repo) =>
    AppState(AppDb(dbPath: _tmp('gram_drill')), grammar: repo);

Widget _wrap(AppState app, Widget home) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: const [KColors.light]),
        home: home,
      ),
    );

Future<void> _pumpApp(WidgetTester tester, AppState app, Widget home) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(_wrap(app, home));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
  await tester.pump();
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

BoxDecoration _optDeco(WidgetTester tester, int j) {
  final c = tester.widget<AnimatedContainer>(find.byKey(ValueKey('drill-opt-$j')));
  return c.decoration! as BoxDecoration;
}

Color _optEdge(WidgetTester tester, int j) =>
    (_optDeco(tester, j).border! as Border).top.color;

const _negTree = GTreeBlock(q: '你要否定的是什么？', opts: [
  GTreeOpt(
      label: '一个动作、性状或介词短语',
      hint: '如 masuk kerja、besar、di rumah',
      result: GTreeOptResult(
          answer: 'tidak',
          rule: 'tidak 否定动词、形容词或介词结构。',
          examples: ['Broto tidak masuk kerja hari ini.'])),
  GTreeOpt(
      label: '一个名词、代词或数词',
      hint: '如 dia、dokter',
      result: GTreeOptResult(
          answer: 'bukan',
          rule: 'bukan 否定名词、代词或数词。',
          examples: ['Yang menolong anak itu bukan dia.'])),
  GTreeOpt(
      label: '事情还没发生，但可能会发生',
      hint: '「还没……」',
      result: GTreeOptResult(
          answer: 'belum',
          rule: 'belum 用于还没有发生的事情。',
          examples: ['Ayah belum berangkat ke kantor.'])),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('quizByPage：只出该页的题，顺序照数据', () {
    final r = _fixture();
    expect(r.quizByPage['af-me']!.map((q) => q.id).toList(),
        ['q-me-1', 'q-me-2', 'q-me-3']);
    expect(r.quizByPage['af-ter'], isNull, reason: 'af-ter 没有题 —— 页底不出按钮');
  });

  testWidgets('决策树：3 条路径逐条走通（点 label → 对应 result.answer）', (tester) async {
    _tallView(tester);
    final app = _app(_fixture());
    await _pumpApp(tester, app,
        const Scaffold(body: SingleChildScrollView(child: TreeBlockView(block: _negTree))));
    expect(find.text(_negTree.q), findsOneWidget);

    for (var i = 0; i < _negTree.opts.length; i++) {
      final o = _negTree.opts[i];
      await tester.tap(find.text(o.label));
      await tester.pump();
      expect(find.text(o.result.answer), findsOneWidget);
      expect(find.text(o.result.rule), findsOneWidget);
      expect(find.text(o.result.examples.first), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
      expect(find.text(_negTree.opts[(i + 1) % 3].label), findsNothing);

      await tester.tap(find.text('重选'));
      await tester.pump();
      expect(find.text(_negTree.opts[(i + 1) % 3].label), findsOneWidget);
      expect(find.text(o.result.answer), findsNothing);
    }
  });

  testWidgets('面包屑点「开始」也能回退', (tester) async {
    _tallView(tester);
    final app = _app(_fixture());
    await _pumpApp(tester, app,
        const Scaffold(body: SingleChildScrollView(child: TreeBlockView(block: _negTree))));
    await tester.tap(find.text(_negTree.opts[2].label));
    await tester.pump();
    expect(find.text('belum'), findsOneWidget);
    await tester.tap(find.text('开始'));
    await tester.pump();
    for (final o in _negTree.opts) {
      expect(find.text(o.label), findsOneWidget);
    }
  });

  testWidgets('答对：选项变绿 + 讲解 + drill_ok 记 1（按页落库，不算读过）', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);
    final drills = repo.quizByPage['af-me']!;
    final d = drills.first;

    await _pumpApp(tester, app, DrillRunnerScreen(drills: drills, title: '练习 · 测试'));
    expect(find.text(d.q), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drill-opt-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_optEdge(tester, 1), KColors.light.brand);
    expect(_optDeco(tester, 1).color, KColors.light.tint);
    expect(find.text('答对了'), findsOneWidget);
    expect(find.text(d.why), findsOneWidget);

    await tester.runAsync(() => app.db.flushGrammarWrites());
    final p = await tester.runAsync(() => app.db.grammarProgress('af-me'));
    expect(p!.drillOk, 1);
    expect(p.drillTotal, 1);
    expect(p.seenAt, isNull, reason: '练习不替页面写「读过」');
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('答错：正确项标绿、错项标红（抖一下）+ drill_ok 记 0', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);
    final drills = repo.quizByPage['af-me']!;

    await _pumpApp(tester, app, DrillRunnerScreen(drills: drills, title: '练习 · 测试'));
    await tester.tap(find.byKey(const ValueKey('drill-opt-0')));
    await tester.pump();
    final atStart = tester.getTopLeft(find.byKey(const ValueKey('drill-opt-0'))).dx;
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getTopLeft(find.byKey(const ValueKey('drill-opt-0'))).dx;
    expect(mid, isNot(atStart));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_optEdge(tester, 1), KColors.light.brand);
    expect(_optEdge(tester, 0), KColors.light.danger);
    expect(find.text('再看一下'), findsOneWidget);

    await tester.runAsync(() => app.db.flushGrammarWrites());
    final p = await tester.runAsync(() => app.db.grammarProgress('af-me'));
    expect(p!.drillOk, 0);
    expect(p.drillTotal, 1);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('系统开了「减少动效」：不抖（也不崩）', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(
        app,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: DrillRunnerScreen(drills: repo.quizByPage['af-me']!),
        ),
      ));
      await tester.pump();
    });
    await tester.tap(find.byKey(const ValueKey('drill-opt-0')));
    await tester.pump();
    final a = tester.getTopLeft(find.byKey(const ValueKey('drill-opt-0'))).dx;
    await tester.pump(const Duration(milliseconds: 40));
    final b = tester.getTopLeft(find.byKey(const ValueKey('drill-opt-0'))).dx;
    expect(b, a);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => app.db.flushGrammarWrites());
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('坏数据（没有选项）：显示「暂未支持」并跳过，不计分', (tester) async {
    _tallView(tester);
    final app = _app(_fixture());
    final drills = [
      const GQuiz(id: 'x-1', page: 'af-me', q: '坏题', opts: [], ans: 0),
      const GQuiz(
          id: 'x-2', page: 'af-me', q: '正常的题', opts: ['错', '对'], ans: 1, why: '因为对。'),
    ];
    await _pumpApp(tester, app, DrillRunnerScreen(drills: drills));
    expect(find.text('此题型暂未支持'), findsOneWidget);
    expect(find.byKey(const ValueKey('drill-opt-0')), findsNothing);
    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(find.text('正常的题'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('drill-opt-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => app.db.flushGrammarWrites());
    final p = await tester.runAsync(() => app.db.grammarProgress('af-me'));
    expect(p!.drillTotal, 1);
    expect(p.drillOk, 1);
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('知识点页：有题才出「做练习」，点进去只出这一页的题', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);

    await _pumpApp(tester, app,
        GrammarPageScreen(key: const ValueKey('no-quiz'), repo: repo, page: repo.pageById['af-ter']!));
    expect(find.byKey(const ValueKey('gram-page-quiz')), findsNothing);

    await _pumpApp(tester, app,
        GrammarPageScreen(key: const ValueKey('has-quiz'), repo: repo, page: repo.pageById['vs-kan-i']!));
    expect(find.text('做练习 · 2 题'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('gram-page-quiz')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    expect(find.byType(DrillRunnerScreen), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('分区页「练习 N」：一次收集分区内所有页的题', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);
    await _pumpApp(
        tester, app, GrammarPageListScreen.section(repo, repo.sectionById['affix']!));
    expect(find.text('练习 3'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('gram-list-quiz')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.runAsync(() => app.db.flushGrammarWrites());
    await tester.runAsync(() => app.db.close());
  });

  testWidgets('回归：做完 5 道练习，todayPlan 的每个数字都不动', (tester) async {
    _tallView(tester);
    final repo = _fixture();
    final app = _app(repo);

    await tester.runAsync(() async {
      await app.db.upsertWords([
        for (var i = 1; i <= 5; i++)
          {
            'id': 'w$i',
            'word': 'w$i',
            'tier': 'core',
            'rank': i,
            'zh': '释义$i',
            'enabled': 1,
            'favorite': 0,
          }
      ]);
      await app.db.setDataVersion(kDataVersion);
      await app.db.planWord([for (var i = 1; i <= 5; i++) 'w$i']);
    });

    final before = await tester.runAsync(() => app.db.todayPlan(dailyQuota: 20));
    expect(before!.newPlan, 5);

    final drills = repo.doc.quiz;
    expect(drills.length, 5);
    await _pumpApp(tester, app, DrillRunnerScreen(drills: drills));
    for (var k = 0; k < drills.length; k++) {
      await tester.tap(find.byKey(ValueKey('drill-opt-${k.isEven ? 0 : 1}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (k < drills.length - 1) {
        await tester.tap(find.text('下一题'));
        await tester.pump();
      }
    }
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(find.text('本组答完'), findsOneWidget);

    await tester.runAsync(() => app.db.flushGrammarWrites());
    final after = await tester.runAsync(() => app.db.todayPlan(dailyQuota: 20));
    expect(after!.quotaShown, before.quotaShown);
    expect(after.finished, before.finished);
    expect(after.taskTotal, before.taskTotal);
    expect(after.taskLeft, before.taskLeft);
    expect(after.newPlan, before.newPlan);
    expect(after.newDone, before.newDone);
    expect(after.newPending, before.newPending);
    expect(after.reviewPlan, before.reviewPlan);
    expect(after.reviewDone, before.reviewDone);
    expect(after.reviewShown, before.reviewShown);
    expect(await tester.runAsync(() => app.db.todayLogCount()), 0);
    expect(await tester.runAsync(() => app.db.todayAnsweredWords()), 0);

    final all = await tester.runAsync(() => app.db.allGrammarProgress());
    expect(all!.length, 2, reason: '5 道题落在 af-me、vs-kan-i 两页');
    expect(all.values.fold<int>(0, (s, r) => s + r.drillTotal), 5);
    expect(all['af-me']!.drillTotal, 3);
    await tester.runAsync(() => app.db.close());
  });
}
