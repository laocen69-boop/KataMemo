import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (final id in ['w0', 'w1', 'w2'])
        {
          'id': id,
          'word': id,
          'tier': 't1',
          'rank': 1,
          'frequency': 100,
          'word_class': 'n',
          'zh': '词$id',
          'senses': 'def=x',
          'enabled': 1,
          'favorite': 0,
          'user_word': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    return db;
  }

  test('某天数据：词数 ≠ 次数，三档按当天第一次作答，新学＋复习 == 碰过的词数', () async {
    final db = await seed();
    final raw = await db.db;
    final today0 = dayStart(DateTime.now()).millisecondsSinceEpoch;
    final yStart = dayStart(DateTime.now().subtract(const Duration(days: 1)))
        .millisecondsSinceEpoch;

    await raw.insert(
        'study_log', {'card_id': 'w0', 'rating': 0, 'ts': yStart + 3600000});

    await raw.insert(
        'study_log', {'card_id': 'w0', 'rating': 2, 'ts': today0 + 1000});
    await raw.insert(
        'study_log', {'card_id': 'w1', 'rating': 1, 'ts': today0 + 2000});
    await raw.insert(
        'study_log', {'card_id': 'w1', 'rating': 0, 'ts': today0 + 3000});

    await raw.insert(
        'study_log', {'card_id': 'w2', 'rating': 3, 'ts': today0 + 4000});

    final t = await db.dayStatsAt(DateTime.now());
    expect(t.words, 3, reason: 'w0 + w1 + w2 三张词');
    expect(t.answers, 4, reason: '今天一共答了 4 次（w1 答了两遍）');
    expect(t.newWords, 2, reason: 'w1、w2 的「全库首次作答」都落在今天');
    expect(t.reviewWords, 1, reason: 'w0 是复习');
    expect(t.easy, 1, reason: 'w2 当天第一次是「轻松」——第四档不能被丢');
    expect(t.know, 1);
    expect(t.fuzzy, 1, reason: 'w1 当天第一次是「模糊」');
    expect(t.forget, 0, reason: 'w1 第二次点困难不该改档');
    expect(t.easy + t.know + t.fuzzy + t.forget, t.words,
        reason: '四档之和 == 碰过的词数');

    final y =
        await db.dayStatsAt(DateTime.now().subtract(const Duration(days: 1)));
    expect(y.words, 1);
    expect(y.answers, 1);
    expect(y.newWords, 1, reason: 'w0 的首次作答在昨天 ⇒ 那天算新学');
    expect(y.forget, 1);

    final none =
        await db.dayStatsAt(DateTime.now().subtract(const Duration(days: 5)));
    expect(none.isEmpty, isTrue);
    expect(none.words, 0);
    expect(none.reviewWords, 0);
    await db.close();
  });

  testWidgets('点日历上的某一天 → 弹出那天的学习数据', (tester) async {

    final today0 = dayStart(DateTime.now()).millisecondsSinceEpoch;
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final raw = await db.db;

      await raw.insert(
          'study_log', {'card_id': 'w0', 'rating': 2, 'ts': today0 + 1000});
      await raw.insert(
          'study_log', {'card_id': 'w1', 'rating': 1, 'ts': today0 + 2000});
      await raw.insert(
          'study_log', {'card_id': 'w1', 'rating': 0, 'ts': today0 + 3000});
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;

    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: ProfileScreen()),
    ));

    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final d = DateTime.now().day;

    await tester.tap(find.text('$d').first);
    await tester.tap(find.text('$d').first);

    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('词'), findsOneWidget,
        reason: '连点两次只能有一个弹窗（叠加的话这里会命中 2 个）');
    expect(find.text('作答 3 次'), findsOneWidget);
    expect(find.text('新学'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('记得'), findsOneWidget);
    expect(find.text('模糊'), findsOneWidget);
    expect(find.text('困难'), findsOneWidget);
    expect(find.text('轻松'), findsOneWidget, reason: '第四档「轻松」要显示出来');

  });
}
