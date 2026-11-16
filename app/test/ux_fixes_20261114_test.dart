import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/grammar/g_edit_sheet.dart';
import 'package:katamemo/widgets/pair_list_editor.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('2026-11-14 编辑体验与合块修复验证', () {
    testWidgets('PairListEditor 无需手打 |，分开填印尼语与中文并自动同步为 i | z',
        (tester) async {
      final ctl = TextEditingController(text: 'Saya makan. | 我吃饭。');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PairListEditor(
                controller: ctl,
                firstHint: '印尼语',
                secondHint: '中文',
                addLabel: '添加例句',
              ),
            ),
          ),
        ),
      );

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Dia tidur.');
      await tester.enterText(fields.at(1), '他在睡觉。');
      await tester.pump();
      expect(ctl.text, 'Dia tidur. | 他在睡觉。');
      ctl.dispose();
    });

    testWidgets('showGBlockEditSheet 编辑表格默认使用结构化表单（无 | 符号）',
        (tester) async {
      const tableBlock = GTableBlock(
        title: '人称代词',
        cols: ['词形', '用法'],
        rows: [
          ['saya', '正式第一人称'],
        ],
      );

      GEditSheetResult? got;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  got = await showGBlockEditSheet(
                    ctx,
                    pageTitle: '代词',
                    block: tableBlock,
                    canReset: false,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('表头列（2 列）'), findsOneWidget);
      expect(find.text('数据行（1 行）'), findsOneWidget);
      expect(find.text('添加一行'), findsOneWidget);

      await tester.ensureVisible(find.text('保存'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(got?.text, contains('saya | 正式第一人称'));
    });

    testWidgets('GrammarPageScreen 将相邻小标题与内容合并为同一小节并可同屏编辑',
        (tester) async {
      final repo = GrammarRepo(autoLoad: false)
        ..loadFromJson(jsonEncode({
          'sections': [
            {
              'id': 'intro',
              'title': '入门',
              'groups': [
                {'title': '', 'pages': ['origin']}
              ]
            }
          ],
          'pages': [
            {
              'id': 'origin',
              'section': 'intro',
              'title': '印尼语简介',
              'blocks': [
                {'t': 'h', 'text': '从哪里来'},
                {'t': 'text', 'text': '印尼语属于南岛语系。'},
              ],
              'see': [],
            }
          ],
          'quiz': [],
        }));
      final app = AppState(
        AppDb(
            dbPath:
                '${Directory.systemTemp.path}/ux_fixes_${DateTime.now().microsecondsSinceEpoch}.db'),
        grammar: repo,
      );
      final page = repo.pageById['origin']!;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: ThemeData().copyWith(
              splashFactory: NoSplash.splashFactory,
              extensions: [KColors.light],
            ),
            home: GrammarPageScreen(
              repo: repo,
              page: page,
              dwell: const Duration(seconds: 999),
            ),
          ),
        ),
      );
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();

      expect(find.byKey(const ValueKey('g-edit-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('g-edit-1')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('g-edit-0')));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('改小节 · 印尼语简介'), findsOneWidget);
      expect(find.text('从哪里来'), findsWidgets);
      expect(find.text('印尼语属于南岛语系。'), findsWidgets);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '起源与发展');
      await tester.enterText(fields.at(1), '印尼语属于南岛语系马来语支。');
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('起源与发展'), findsOneWidget);
      expect(find.text('印尼语属于南岛语系马来语支。'), findsOneWidget);

      final resetBtn = find.byKey(const ValueKey('grammar.resetPage'));
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置'));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      expect(find.text('从哪里来'), findsOneWidget);
      expect(resetBtn, findsNothing);

      await tester.runAsync(() => app.db.close());
    });
  });
}
