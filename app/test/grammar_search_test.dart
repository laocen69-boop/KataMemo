library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/screens/grammar/grammar_page_screen.dart';
import 'package:katamemo/screens/grammar/grammar_search_screen.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GrammarRepo _fixture() => GrammarRepo(autoLoad: false)
  ..loadFromJson(File('test/fixtures/grammar_v2_sample.json').readAsStringSync());

String _tmp(String tag) =>
    '${Directory.systemTemp.path}/katamemo_$tag'
    '_${DateTime.now().microsecondsSinceEpoch}.db';

Widget _wrap(AppState app, Widget home) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory, extensions: const [KColors.light]),
        home: home,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('最近搜索：去重、最近在前、封顶 8；坏 JSON 当空表', () async {
    final db = AppDb(dbPath: _tmp('recent'));
    for (var i = 1; i <= 10; i++) {
      await pushGramRecent(db, 'q$i');
    }
    final r = await loadGramRecent(db);
    expect(r.length, kGramRecentMax);
    expect(r.first, 'q10');
    expect(r, isNot(contains('q1')));
    await pushGramRecent(db, 'q10');
    expect((await loadGramRecent(db)).where((e) => e == 'q10').length, 1);
    await db.metaSet(kGramRecentKey, '{不是数组}');
    expect(await loadGramRecent(db), isEmpty);
    await db.close();
  });

  testWidgets('边输边出结果（不用回车）；点结果进页面并记最近搜索', (tester) async {
    final repo = _fixture();
    final app = AppState(AppDb(dbPath: _tmp('gsearch')), grammar: repo);
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(app, GrammarSearchScreen(repo: repo)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('gram-search-field')), 'ter');
    await tester.pump();
    expect(find.byKey(const ValueKey('gram-hit-af-ter')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gram-search-field')), '鼻音前缀');
    await tester.pump();
    expect(find.byKey(const ValueKey('gram-hit-af-me')), findsOneWidget);
    expect(find.text('别名'), findsOneWidget, reason: '不是标题命中时，右侧说明命中在哪');

    await tester.enterText(find.byKey(const ValueKey('gram-search-field')), 'zzz没有');
    await tester.pump();
    expect(find.text('没有找到「zzz没有」'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gram-search-field')), 'me-kan');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('gram-hit-vs-kan-i')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    expect(find.byType(GrammarPageScreen), findsOneWidget);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await loadGramRecent(app.db), ['me-kan']);
      await app.db.flushGrammarWrites();
    });
  });
}
