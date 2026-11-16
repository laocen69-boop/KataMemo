import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';

import 'package:katamemo/db.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/backup_pack.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/grammar/grammar_edit.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/screens/grammar/grammar_edits_screen.dart';
import 'package:katamemo/screens/grammar/grammar_hub_screen.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/theme/k_colors.dart';

GPage _page(List<GBlock> blocks) => GPage(id: 'p1', title: '测试页', blocks: blocks);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('10 种块行约定往返逐字一致', () {
    final samples = <GBlock>[
      const GLeadBlock('结论 **x**'),
      const GHeadingBlock('小标题'),
      const GTextBlock('a **b** c'),
      const GStepsBlock(title: '判断', items: ['一', '二']),
      const GPitBlock(['甲', '乙']),
      const GTableBlock(title: '表', cols: ['A', 'B'], rows: [
        ['1', '2'],
        ['3', '4']
      ]),
      const GExBlock([GEx(i: 'Dia **makan**.', z: '他吃。'), GEx(i: 'Saya makan.')]),
      const GVsBlock(
          a: GVsSide(title: '甲', text: 't1', ex: [GEx(i: 'e1', z: 'z1')]),
          b: GVsSide(title: '乙', text: 't2'),
          note: 'n'),
      const GWordsBlock(title: '词', list: ['makan', 'minum']),
      const GTreeBlock(q: '问', opts: [
        GTreeOpt(
            label: 'L',
            hint: 'H',
            result: GTreeOptResult(answer: 'A', rule: 'R', examples: ['E1', 'E2']))
      ]),
    ];
    for (final b in samples) {
      final t = gBlockTypeOf(b);
      final text = gBlockToText(b);
      final r = gParseBlock(t, text);
      expect(r.ok, true, reason: '$t 解析失败：${r.error}\n$text');
      expect(jsonEncode(gBlockToJson(r.block!)), jsonEncode(gBlockToJson(b)),
          reason: '$t 往返不一致');
    }
  });

  test('块哈希：同内容同键、改内容换键', () {
    const a = GTextBlock('你好');
    const b = GTextBlock('你好');
    const c = GTextBlock('你好！');
    expect(gBlockKey(a), gBlockKey(b));
    expect(gBlockKey(a), isNot(gBlockKey(c)));
    expect(gBlockKey(a).length, 16);
  });

  test('解析错误显式返回，不静默吞', () {
    expect(gParseBlock('text', '  ').ok, false);
    expect(gParseBlock('table', '').ok, false);
    expect(gParseBlock('vs', '[A] 甲\n正文').ok, false);
    expect(gParseBlock('tree', '[问] q').ok, false);
    expect(gParseBlock('ex', '').ok, false);

    final r = gParseBlock('ex', 'a | b | c');
    expect(r.block, isA<GExBlock>());
    expect((r.block as GExBlock).items.first.z, 'b | c');
  });

  test('override 套用 + 已改标记 + 孤儿显式', () {
    final page = _page([const GTextBlock('原'), const GTextBlock('二')]);
    final k0 = gBlockKey(page.blocks[0]);
    final rows = [
      GEditRow(
          scope: 'grammar',
          pageId: 'p1',
          blockKey: k0,
          kind: kGKindOverride,
          payload: jsonEncode(gBlockToJson(const GTextBlock('改'))),
          ts: 1),
      GEditRow(
          scope: 'grammar',
          pageId: 'p1',
          blockKey: 'deadbeefdeadbeef',
          kind: kGKindOverride,
          payload: jsonEncode(gBlockToJson(const GTextBlock('孤儿'))),
          ts: 2),
    ];
    final eff = applyGrammarEdits(page, rows);
    expect((eff.blocks[0] as GTextBlock).text, '改');
    expect(eff.editedKeys, {k0});
    expect(eff.orphans.length, 1);
    expect(eff.added, [false, false]);
  });

  test('layout：增删移序；悬空键跳过', () {
    final page = _page([
      const GTextBlock('A'),
      const GTextBlock('B'),
      const GTextBlock('C'),
    ]);
    final k = [for (final b in page.blocks) gBlockKey(b)];
    const addedBlock = GTextBlock('新增');
    final layout = jsonEncode([
      {'k': k[2]},
      {'a': gBlockToJson(addedBlock)},
      {'k': k[0]},
      {'k': 'ffffffffffffffff'},
    ]);
    final eff = applyGrammarEdits(page, [
      GEditRow(
          scope: 'grammar',
          pageId: 'p1',
          blockKey: kGLayoutKey,
          kind: kGKindLayout,
          payload: layout,
          ts: 1),
    ]);
    expect([for (final b in eff.blocks) (b as GTextBlock).text], ['C', '新增', 'A']);
    expect(eff.added, [false, true, false]);
    expect(eff.entries.length, 3);
  });

  test('note 按 ts 排序追加', () {
    final page = _page([const GTextBlock('A')]);
    final eff = applyGrammarEdits(page, [
      GEditRow(
          scope: 'grammar',
          pageId: 'p1',
          blockKey: 'note:2',
          kind: kGKindNote,
          payload: gNotePayload('后'),
          ts: 2),
      GEditRow(
          scope: 'grammar',
          pageId: 'p1',
          blockKey: 'note:1',
          kind: kGKindNote,
          payload: gNotePayload('先'),
          ts: 1),
    ]);
    expect([for (final n in eff.notes) gNoteText(n.payload)], ['先', '后']);
  });

  test('db CRUD + 重导不清 + 整页恢复', () async {
    final db = AppDb(dbPath: inMemoryDatabasePath);
    const row = GEditRow(
        scope: 'grammar',
        pageId: 'p1',
        blockKey: 'k1',
        kind: kGKindOverride,
        payload: '{"t":"text","text":"改"}',
        ts: 1);
    await db.saveGrammarEdit(row);
    expect((await db.grammarEdits('grammar', 'p1')).length, 1);

    await db.saveGrammarEdit(GEditRow(
        scope: row.scope,
        pageId: row.pageId,
        blockKey: row.blockKey,
        kind: row.kind,
        payload: '{"t":"text","text":"改2"}',
        ts: 2));
    final got = await db.grammarEdits('grammar', 'p1');
    expect(got.length, 1);
    expect(got.first.payload, contains('改2'));

    await db.clearWords();
    expect((await db.grammarEdits('grammar', 'p1')).length, 1);

    await db.resetGrammarPage('grammar', 'p1');
    expect(await db.grammarEdits('grammar', 'p1'), isEmpty);
    await db.close();
  });

  test('备份包往返 grammar_edit（ts 大者胜）', () async {
    final a = AppDb(dbPath: inMemoryDatabasePath);
    await a.saveGrammarEdit(const GEditRow(
        scope: 'writing',
        pageId: 'w1',
        blockKey: 'k1',
        kind: kGKindOverride,
        payload: '{"t":"text","text":"甲"}',
        ts: 5));
    final pack = await BackupPack.export(await a.db,
        schemaVersion: kSchemaVersion,
        dataVersion: kDataVersion,
        appVersion: 'test');
    await a.close();

    final b = AppDb(dbPath: inMemoryDatabasePath);

    await b.saveGrammarEdit(const GEditRow(
        scope: 'writing',
        pageId: 'w1',
        blockKey: 'k1',
        kind: kGKindOverride,
        payload: '{"t":"text","text":"旧"}',
        ts: 1));
    final rep = await (await b.db).transaction((txn) => BackupPack.import(txn, pack,
        localSchemaVersion: kSchemaVersion));
    expect(rep.grammarEditApplied, 1);
    final got = await b.grammarEdits('writing', 'w1');
    expect(got.single.payload, contains('甲'));
    await b.close();
  });

  testWidgets('阅读页：铅笔改块 → 套用+已改角标 → 恢复默认', (tester) async {
    final repo = _wRepo();
    final app = _wApp(repo);
    await _wPump(tester, app,
        GrammarPageScreen(repo: repo, page: repo.pageById['p1']!, dwell: const Duration(seconds: 999)));
    expect(find.byKey(const ValueKey('g-edit-0')), findsOneWidget);
    await _wTap(tester, find.byKey(const ValueKey('g-edit-0')));
    expect(find.text('保存'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '改后 **x**');
    await tester.pump();
    await _wTap(tester, find.text('保存'));
    expect(find.textContaining('改后'), findsOneWidget);
    expect(find.text('已改'), findsOneWidget);

    await _wTap(tester, find.byKey(const ValueKey('g-edit-0')));
    await _wTap(tester, find.text('恢复默认（删掉我的修改）'));
    expect(find.text('已改'), findsNothing);
    expect(find.text('A'), findsOneWidget);
    await _wEnd(tester, app);
  });

  testWidgets('笔记：添加 → 卡片显示 → 删除', (tester) async {
    final repo = _wRepo();
    final app = _wApp(repo);
    await _wPump(tester, app,
        GrammarPageScreen(repo: repo, page: repo.pageById['p1']!, dwell: const Duration(seconds: 999)));
    await _wTap(tester, find.text('添加笔记'));
    await tester.enterText(find.byType(TextField), '笔记内容');
    await tester.pump();
    await _wTap(tester, find.text('保存'));
    expect(find.text('我的笔记'), findsOneWidget);
    expect(find.textContaining('笔记内容'), findsOneWidget);
    await _wTap(tester, find.byIcon(Icons.delete_outline));
    expect(find.text('我的笔记'), findsNothing);
    await _wEnd(tester, app);
  });

  testWidgets('⋯ 菜单：删除块要二次确认', (tester) async {
    final repo = _wRepo();
    final app = _wApp(repo);
    await _wPump(tester, app,
        GrammarPageScreen(repo: repo, page: repo.pageById['p1']!, dwell: const Duration(seconds: 999)));
    await _wTap(tester, find.byKey(const ValueKey('g-more-0')));
    await _wTap(tester, find.text('删除块'));

    expect(find.text('A'), findsOneWidget);
    await _wTap(tester, find.text('删除'));
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    await _wEnd(tester, app);
  });

  testWidgets('管理页：修改/笔记/孤儿分组列出', (tester) async {
    final repo = _wRepo();
    final app = _wApp(repo);
    final k0 = gBlockKey(const GTextBlock('A'));
    await tester.runAsync(() async {
      await app.db.saveGrammarEdit(GEditRow(
          scope: kGScopeGrammar,
          pageId: 'p1',
          blockKey: k0,
          kind: kGKindOverride,
          payload: jsonEncode(gBlockToJson(const GTextBlock('改后'))),
          ts: 1));
      await app.db.saveGrammarEdit(GEditRow(
          scope: kGScopeGrammar,
          pageId: 'p1',
          blockKey: 'note:1',
          kind: kGKindNote,
          payload: gNotePayload('课堂补充'),
          ts: 2));
      await app.db.saveGrammarEdit(GEditRow(
          scope: kGScopeGrammar,
          pageId: 'p1',
          blockKey: 'deadbeefdeadbeef',
          kind: kGKindOverride,
          payload: jsonEncode(gBlockToJson(const GTextBlock('孤儿'))),
          ts: 3));
    });
    await _wPump(tester, app,
        GrammarEditsScreen(repo: repo, scope: kGScopeGrammar));
    expect(find.text('我的修改与笔记'), findsOneWidget);
    expect(find.text('改·段落'), findsOneWidget);
    expect(find.text('笔记'), findsOneWidget);
    expect(find.text('未套用'), findsOneWidget);
    expect(find.textContaining('1 条未套用'), findsOneWidget);
    await _wEnd(tester, app);
  });

  testWidgets('hub 顶栏入口进管理页', (tester) async {
    final repo = _wRepo();
    final app = _wApp(repo);
    await _wPump(tester, app, const GrammarHubScreen());
    await _wTap(tester, find.byKey(const ValueKey('gram-my-edits')));
    expect(find.text('我的修改与笔记'), findsOneWidget);
    await _wEnd(tester, app);
  });
}

String _wRaw() => jsonEncode({
      'sections': [
        {
          'id': 's',
          'title': '分区',
          'groups': [
            {'title': '', 'pages': ['p1']}
          ]
        }
      ],
      'pages': [
        {
          'id': 'p1',
          'title': '测试页',
          'section': 's',
          'blocks': [
            {'t': 'text', 'text': 'A'},
            {'t': 'text', 'text': 'B'},
          ]
        }
      ],
      'quiz': [],
    });

GrammarRepo _wRepo() => GrammarRepo(autoLoad: false)..loadFromJson(_wRaw());

AppState _wApp(GrammarRepo repo) => AppState(
    AppDb(
        dbPath:
            '${Directory.systemTemp.path}/gram_edit_${DateTime.now().microsecondsSinceEpoch}.db'),
    grammar: repo);

Widget _wWrap(AppState app, Widget home) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData().copyWith(
            splashFactory: NoSplash.splashFactory,
            extensions: [KColors.light]),
        home: home,
      ),
    );

Future<void> _wPump(WidgetTester tester, AppState app, Widget home) async {

  await tester.pumpWidget(_wWrap(app, home));
  await _wDrain(tester);
  await tester.pump();
}

Future<void> _wDrain(WidgetTester tester) => tester
    .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));

Future<void> _wTap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump();

  await _wDrain(tester);
  await tester.pump();
  await _wDrain(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _wEnd(WidgetTester tester, AppState app) async {
  await tester.runAsync(() => app.db.close());
}