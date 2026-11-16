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

  Future<void> settleDb(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();
    }
  }

  Future<AppDb> seed() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (final id in ['w0', 'w1'])
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

  test('总时长：间隔 ≤1 分钟才累计，长的整段不计（不是封顶）', () async {
    final db = await seed();
    final raw = await db.db;
    final t0 = DateTime(2026, 9, 1, 20, 0).millisecondsSinceEpoch;

    await raw.insert('study_log', {'card_id': 'w0', 'rating': 2, 'ts': t0});
    await raw
        .insert('study_log', {'card_id': 'w1', 'rating': 2, 'ts': t0 + 10000});
    await raw
        .insert('study_log', {'card_id': 'w0', 'rating': 2, 'ts': t0 + 40000});
    await raw.insert(
        'study_log', {'card_id': 'w1', 'rating': 2, 'ts': t0 + 40000 + 300000});
    await raw.insert('study_log',
        {'card_id': 'w0', 'rating': 2, 'ts': t0 + 40000 + 300000 + 5000});

    await raw.insert('study_log',
        {'card_id': 'w1', 'rating': 2, 'ts': t0 + 40000 + 300000 + 5000});

    expect(await db.totalStudySeconds(), 45,
        reason: '10 + 30 + 5 = 45 秒；那 5 分钟必须**整段**消失，'
            '被算成 60 秒就是「封顶」而不是「不计」了');

    expect(await db.totalStudySeconds(gapCapMs: 5000), 5,
        reason: '把上限收到 5 秒，只剩最后那段 5 秒（10 秒、30 秒的都超出）');
    await db.close();
  });

  test('跨天的那一段也走同一条判据（连续作答照样算，停一夜照样不算）', () async {
    final db = await seed();
    final raw = await db.db;

    final a = DateTime(2026, 9, 1, 23, 59, 55).millisecondsSinceEpoch;
    await raw.insert('study_log', {'card_id': 'w0', 'rating': 2, 'ts': a});
    await raw
        .insert('study_log', {'card_id': 'w1', 'rating': 2, 'ts': a + 10000});

    await raw.insert('study_log',
        {'card_id': 'w0', 'rating': 2, 'ts': a + 10000 + 8 * 3600000});
    expect(await db.totalStudySeconds(), 10,
        reason: '跨天不是判据，**间隔长度**才是：10 秒算、8 小时不算');
    await db.close();
  });

  testWidgets('学习概况：2×2 四格 + 时长用小时（够一小时）', (tester) async {
    await tester.binding
        .setSurfaceSize(const Size(320, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final raw = await db.db;
      final t0 = DateTime(2026, 9, 1, 20, 0).millisecondsSinceEpoch;

      for (var i = 0; i < 91; i++) {
        await raw.insert('study_log',
            {'card_id': 'w${i % 2}', 'rating': 2, 'ts': t0 + i * 60000});
      }
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await settleDb(tester);

    expect(tester.takeException(), isNull, reason: '窄屏 320×568 不许溢出');
    expect(find.text('学习概况'), findsOneWidget);

    for (final l in ['在学（词）', '已学（词）', '已掌握（词）', '学习总时长（小时）']) {
      expect(find.text(l), findsOneWidget, reason: '四个数各占一格：$l');
    }
    expect(find.text('1.5'), findsOneWidget,
        reason: '90 段 × 60 秒 = 5400 秒 = 1.5 小时');

    expect(find.text('0'), findsWidgets,
        reason: '在学 0 / 已学 0 / 标熟 0（没加入记忆就没数）');
    expect(find.textContaining('停顿超 1 分钟不计'), findsOneWidget,
        reason: '口径必须写在界面上：这是估算，不是计时器');

  });

  testWidgets('学习概况：不足一小时显示分钟（新用户看「10 分」，不是「0.2 小时」）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final built = (await tester.runAsync(() async {
      final db = await seed();
      final raw = await db.db;
      final t0 = DateTime(2026, 9, 1, 20, 0).millisecondsSinceEpoch;
      for (var i = 0; i < 11; i++) {
        await raw.insert('study_log',
            {'card_id': 'w${i % 2}', 'rating': 2, 'ts': t0 + i * 60000});
      }
      final app = AppState(db);
      await app.init();
      return (app: app, db: db);
    }))!;

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: built.app,
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await settleDb(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('学习总时长（分）'), findsOneWidget);

    Finder statValue(String v) => find.byWidgetPredicate(
        (w) => w is Text && w.data == v && w.style?.fontSize == 24);
    expect(statValue('10'), findsOneWidget,
        reason: '10 段 × 60 秒 = 600 秒 = 10 分');

    expect(statValue('0'), findsWidgets, reason: '在学/已学/标熟 三个 0');
  });
}
