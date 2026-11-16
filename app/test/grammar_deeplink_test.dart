library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/grammar/grammar_hub_screen.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/screens/home_shell.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/grammar_note_section.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _raw() => File('test/fixtures/grammar_v2_sample.json').readAsStringSync();

GrammarRepo _fixture() => GrammarRepo(autoLoad: false)..loadFromJson(_raw());

String _tmp(String tag) =>
    '${Directory.systemTemp.path}/katamemo_$tag'
    '_${DateTime.now().microsecondsSinceEpoch}.db';

AppState _app(GrammarRepo repo, {GrammarRepo? writing}) =>
    AppState(AppDb(dbPath: _tmp('gram_link')), grammar: repo, writing: writing);

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

const _note = GrammarNote(tag: '(1)', zh: '测试用法：虚拟语气');

Future<void> _pumpNoteSection(WidgetTester tester, AppState app,
    {required String? wordId, bool bare = false}) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(_wrap(
      app,
      Scaffold(
        body: SingleChildScrollView(
          child: GrammarNoteSection(
            notes: const [_note],
            wordId: wordId,
            bare: bare,
          ),
        ),
      ),
    ));
    await tester.pump();
  });
}

Future<void> _tapLink(WidgetTester tester) => tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('grammar-note-link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('有命中的词显示「查看语法 ›」；bare / 非 bare 都能显示', (tester) async {
    final app = _app(_fixture());

    await _pumpNoteSection(tester, app, wordId: 'yang');
    expect(find.text('查看语法 ›'), findsOneWidget);
    final t = tester.widget<Text>(find.text('查看语法 ›'));
    expect(t.style!.fontSize, 12.5);
    expect(t.style!.color, KColors.light.deep);

    await _pumpNoteSection(tester, app, wordId: 'yang', bare: true);
    expect(find.text('查看语法 ›'), findsOneWidget, reason: 'bare 模式也要显示');
  });

  testWidgets('没有命中词的卡不显示链接；用法区块不再显示出处', (tester) async {
    final repo = _fixture();
    final app = _app(repo);
    expect(repo.pagesForWord('kata-yang-tidak-ada'), isEmpty);
    await _pumpNoteSection(tester, app, wordId: 'kata-yang-tidak-ada');
    expect(find.text('查看语法 ›'), findsNothing);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(
        app,
        const Scaffold(
          body: GrammarNoteSection(notes: [
            GrammarNote(tag: '(1)', zh: '用法', src: '某书 p181#(6)'),
          ]),
        ),
      ));
      await tester.pump();
    });
    expect(find.textContaining('p181'), findsNothing,
        reason: '用户 2026-10-23：界面上不再出现书名/页码');
  });

  testWidgets('点「查看语法 ›」→ 打开命中页的 GrammarPageScreen', (tester) async {
    final app = _app(_fixture());
    await _pumpNoteSection(tester, app, wordId: 'membaca');
    await _tapLink(tester);
    final page = tester.widget<GrammarPageScreen>(find.byType(GrammarPageScreen));
    expect(page.page.id, 'af-me');
    expect(find.text('me- 前缀'), findsOneWidget);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('免责版：没有用法注释、但词在语法页里出现 → 只显示一行「语法讲解：页名」', (tester) async {
    final repo = _fixture();
    final app = _app(repo);
    final noNotes = WordCard(id: 'membaca', word: 'membaca');
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(
        app,
        Scaffold(
          body: Builder(
            builder: (context) => Column(children: [
              Text('has=${GrammarNoteSection.has(context, noNotes)}'),
              Text('label=${GrammarNoteSection.label(noNotes)}'),
              const GrammarNoteSection(notes: [], wordId: 'membaca'),
            ]),
          ),
        ),
      ));
      await tester.pump();
    });
    expect(find.text('has=true'), findsOneWidget);
    expect(find.text('label=语法'), findsOneWidget);
    expect(find.textContaining('语法讲解：'), findsOneWidget);
    await _tapLink(tester);
    expect(find.byType(GrammarPageScreen), findsOneWidget);
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('没有注释、也不在任何语法页的词：区块不出现', (tester) async {
    final app = _app(_fixture());
    final card = WordCard(id: 'tidak-ada', word: 'tidak-ada');
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(
        app,
        Scaffold(
          body: Builder(
            builder: (context) =>
                Text('has=${GrammarNoteSection.has(context, card)}'),
          ),
        ),
      ));
      await tester.pump();
    });
    expect(find.text('has=false'), findsOneWidget);
  });

  testWidgets('多页命中：词类页优先于跨章专题页', (tester) async {
    final repo = GrammarRepo(autoLoad: false)
      ..loadFromJson('''
{
  "sections": [
    {"id": "cross", "title": "跨词类专题", "groups": [{"pages": ["x-1"]}]},
    {"id": "wordclass", "title": "词类", "groups": [{"pages": ["wc-1"]}]}
  ],
  "pages": [
    {"id": "x-1", "section": "cross", "title": "专题页", "words": ["kata"],
     "blocks": [{"t": "text", "text": "x"}]},
    {"id": "wc-1", "section": "wordclass", "title": "词类页", "words": ["kata"],
     "blocks": [{"t": "text", "text": "w"}]}
  ]
}
''');
    expect(repo.pagesForWord('kata').first.id, 'x-1', reason: '前提：数据顺序专题页在前');
    final app = _app(repo);
    await _pumpNoteSection(tester, app, wordId: 'kata');
    await _tapLink(tester);
    final page = tester.widget<GrammarPageScreen>(find.byType(GrammarPageScreen));
    expect(page.page.id, 'wc-1');
    await tester.runAsync(() => app.db.flushGrammarWrites());
  });

  testWidgets('「我的」页：语法入口切 Tab、写作入口进写作模块、关于有来源说明', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final writing = GrammarRepo(autoLoad: false)..loadFromJson(_raw());
    final app = (await tester.runAsync(() async {
      final a = _app(_fixture(), writing: writing);
      await a.init();
      return a;
    }))!;

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(app, const HomeShell()));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    Finder navLabel(String text) => find.byWidgetPredicate((w) =>
        w is Text && w.data == text && w.style?.fontSize == 10.5);

    await tester.runAsync(() async {
      await tester.tap(navLabel('我的'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    await tester.tap(find.text('关于'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('about-note')), findsOneWidget);
    expect(find.textContaining('整理编写'), findsOneWidget,
        reason: 'fixture 不带 about（同完整版）→ 用 App 内置的默认说明');
    expect(find.textContaining('《'), findsNothing,
        reason: '用户 2026-10-23：关于里也不列书名');
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('profile-writing')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
    });
    final hubs = tester.widgetList<GrammarHubScreen>(find.byType(GrammarHubScreen));
    expect(hubs.any((h) => h.writing), isTrue);
    expect(find.text('写作'), findsWidgets);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final tileTitle = find.byWidgetPredicate(
        (w) => w is Text && w.data == '语法' && w.style?.fontSize != 10.5);
    expect(tileTitle, findsOneWidget);
    await tester.tap(tileTitle);
    await tester.pump();
    final selected = tester.widget<Text>(navLabel('语法'));
    expect(selected.style!.color, KColors.light.brand);

    await tester.pump(const Duration(milliseconds: 200));
  });
}
