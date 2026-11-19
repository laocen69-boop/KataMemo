import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/screens/study_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => null,
    );
  });

  group('SLA 2: 新词队列同词根/形近词防扎堆', () {
    test('相同 base_word 的词在滑动窗口内被隔开，整体顺序不乱', () {
      final rows = <Map<String, Object?>>[
        {'id': 'ajar', 'base_word': 'ajar', 'word': 'ajar'},
        {'id': 'belajar', 'base_word': 'ajar', 'word': 'belajar'},
        {'id': 'mengajar', 'base_word': 'ajar', 'word': 'mengajar'},
        {'id': 'pelajaran', 'base_word': 'ajar', 'word': 'pelajaran'},
        {'id': 'makan', 'base_word': 'makan', 'word': 'makan'},
        {'id': 'minum', 'base_word': 'minum', 'word': 'minum'},
        {'id': 'tidur', 'base_word': 'tidur', 'word': 'tidur'},
        {'id': 'jalan', 'base_word': 'jalan', 'word': 'jalan'},
      ];
      final out = AppDbStudy.interleaveFreshRows(rows, window: 6, minGap: 3);
      final ids = [for (final r in out) r['id'] as String];
      expect(ids.length, rows.length);
      expect(ids.toSet(), rows.map((r) => r['id']).toSet());
      final basesFirst4 = [for (final r in out.take(4)) r['base_word']];
      expect(basesFirst4.where((b) => b == 'ajar').length, 1);
    });

    test('短词/测试合成 id（w1/w2/w3）不误撞键，保持原序', () {
      final rows = <Map<String, Object?>>[
        {'id': 'w1', 'base_word': null, 'word': 'w1'},
        {'id': 'w2', 'base_word': null, 'word': 'w2'},
        {'id': 'w3', 'base_word': null, 'word': 'w3'},
        {'id': 'w4', 'base_word': null, 'word': 'w4'},
      ];
      final out = AppDbStudy.interleaveFreshRows(rows);
      expect([for (final r in out) r['id']], ['w1', 'w2', 'w3', 'w4']);
    });
  });

  group('SLA 1 & 3: 水蛭卡干预 + 听音辨词模式', () {
    Future<(AppDb, AppState)> seedApp({int lapses = 0}) async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await db.upsertWords([
        {
          'id': 'makan',
          'word': 'makan',
          'tier': 't1',
          'rank': 1,
          'zh': '吃',
          'enabled': 1,
          'favorite': 0,
        },
      ]);
      await db.setDataVersion(kDataVersion);
      await db.planWord(['makan']);
      final app = AppState(db);
      await app.init();
      await app.setAutoSpeak(false);
      if (lapses > 0) {
        await db.saveSrs(
          'makan',
          FsrsState(
            state: FsrsState.relearning,
            due: DateTime.now().subtract(const Duration(minutes: 5)),
            stability: 1.0,
            difficulty: 7.0,
            reps: lapses + 1,
            lapses: lapses,
          ),
        );
      }
      return (db, app);
    }

    Future<void> mountStudy(WidgetTester tester, AppState app) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: app,
            child: const MaterialApp(home: StudyScreen()),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 160));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('lapses >= 4 时卡背显示水蛭卡干预提示条', (tester) async {
      late AppDb db;
      late AppState app;
      await tester.runAsync(() async {
        (db, app) = await seedApp(lapses: 4);
      });

      await mountStudy(tester, app);

      expect(find.byKey(const Key('study.leechBanner')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('front')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('study.leechBanner')), findsOneWidget);
      expect(find.textContaining('已遗忘 4 次'), findsOneWidget);
      expect(find.byKey(const Key('study.leechMnemonic')), findsOneWidget);

      await tester.runAsync(() => db.close());
    });
  });
}
