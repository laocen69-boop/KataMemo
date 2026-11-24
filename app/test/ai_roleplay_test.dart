import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/ai_roleplay.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/ai_roleplay_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('kAiRoleplayScenarios · EYD V 与结构校验', () {
    test('12 个 BIPA A1-B2 场景齐全、ID 唯一、开场白符合 EYD V 拼写规范', () {
      expect(kAiRoleplayScenarios.length, 12);
      final ids = kAiRoleplayScenarios.map((s) => s.id).toSet();
      expect(ids.length, 12);

      final levels = kAiRoleplayScenarios.map((s) => s.level).toSet();
      expect(levels, containsAll(['A1', 'A2', 'B1', 'B2']));

      final detachedClitic = RegExp(r'\s+(nya|ku|mu|lah|kah|tah)\b', caseSensitive: false);
      final nonStandard = RegExp(r'\b(silahkan|merubah|mempengaruhi|mensukseskan)\b', caseSensitive: false);

      for (final s in kAiRoleplayScenarios) {
        expect(s.title, isNotEmpty, reason: s.id);
        expect(s.register, isNotEmpty, reason: s.id);
        expect(s.aiRole, isNotEmpty, reason: s.id);
        expect(s.userGoal, isNotEmpty, reason: s.id);
        expect(s.grammarFocus, isNotEmpty, reason: s.id);
        expect(s.defaultTargets.length, 4, reason: s.id);
        expect(s.openerZh, isNotEmpty, reason: s.id);

        final op = s.openerId.trim();
        expect(op, isNotEmpty, reason: s.id);
        expect(RegExp(r'^[A-Z]').hasMatch(op), isTrue, reason: '${s.id} 句首需大写');
        expect(RegExp(r'[.!?]$').hasMatch(op), isTrue, reason: '${s.id} 句末需标点');
        expect(detachedClitic.hasMatch(op), isFalse, reason: '${s.id} 附着词不可分写: $op');
        expect(nonStandard.hasMatch(op), isFalse, reason: '${s.id} 含非规范词形: $op');
        expect(op.contains(' anda '), isFalse, reason: '${s.id} Anda 需大写');
      }
    });
  });

  group('matchRoleplayTargetWords · 词干还原与派生形命中', () {
    test('原词、meN-/di-/peN-an/-kan/-i 派生形、-nya 附着词、叠词与多词短语均可命中', () {
      final targets = [
        'pesan',
        'harga',
        'pengaruhi',
        'kuasai',
        'bimbingan',
        'kambing hitam',
      ];
      final userReplies = [
        'Saya mau memesan nasi goreng yang tidak terlalu pedas.',
        'Berapa harganya kalau saya ambil dua kilogram?',
        'Keterlambatan ini tidak memengaruhi jadwal utama, dan saya sudah menguasai materinya.',
        'Kami tidak mencari kambing hitam dalam proyek ini.',
      ];

      final hit = matchRoleplayTargetWords(targets, userReplies);
      expect(hit, containsAll(['pesan', 'harga', 'pengaruhi', 'kuasai', 'kambing hitam']));
      expect(hit, isNot(contains('bimbingan')));
    });
  });

  group('loadUserRoleplayTargets & aiRoleplayContext', () {
    test('按今日错词 → 长期痛点词 → 今日已学词优先级抽词，排除词缀与专名', () async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await db.upsertWords([
        {
          'id': 'pesan',
          'word': 'pesan',
          'tier': 't1',
          'rank': 1,
          'word_class': 'v',
          'zh': '点餐；预订',
          'senses': 'def=x',
          'enabled': 1,
          'favorite': 0,
          'user_word': 0,
        },
        {
          'id': 'jadwal',
          'word': 'jadwal',
          'tier': 't2',
          'rank': 2,
          'word_class': 'n',
          'zh': '日程；时间表',
          'senses': 'def=x',
          'enabled': 1,
          'favorite': 0,
          'user_word': 0,
        },
      ]);
      await db.setDataVersion(kDataVersion);
      final raw = await db.db;
      final now = DateTime.now().millisecondsSinceEpoch;
      await raw.insert('study_log', {
        'card_id': 'pesan',
        'ts': now,
        'rating': 1,
      });
      await raw.insert('srs', {
        'card_id': 'jadwal',
        'state': 2,
        'due': now,
        'stability': 3.0,
        'difficulty': 6.0,
        'reps': 8,
        'lapses': 5,
        'last_review': now,
        'first_seen': now,
      });

      final app = AppState(db);
      final loaded = await loadUserRoleplayTargets(app);
      expect(loaded.map((e) => e.$1).toList(), ['pesan', 'jadwal']);

      final sc = aiRoleplayById('warung_makan')!;
      final ctx = aiRoleplayContext(sc, targetWords: ['pesan', 'jadwal']);
      expect(ctx.key, 'roleplay:warung_makan');
      expect(ctx.system, contains('pesan、jadwal'));
      expect(ctx.system, contains(sc.register));
      expect(ctx.quick.length, 3);
    });
  });

  group('AiRoleplaySheet UI', () {
    testWidgets('按 BIPA 等级筛选并点选场景返回 AiRoleplaySelection', (tester) async {
      late AppState app;
      await tester.runAsync(() async {
        await databaseFactory.deleteDatabase(inMemoryDatabasePath);
        final db = AppDb(dbPath: inMemoryDatabasePath);
        await db.setDataVersion(kDataVersion);
        app = AppState(db);
      });
      AiRoleplaySelection? picked;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [KColors.light]),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  picked = await showAiRoleplaySheet(ctx, app);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('印尼语情景对话'), findsOneWidget);
      expect(find.text('餐馆点菜与忌口'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('roleplay.level.B2')));
      await tester.pumpAndSettle();

      expect(find.text('餐馆点菜与忌口'), findsNothing);
      expect(find.text('银行开户与银行卡挂失'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('roleplay.card.bank_rekening')));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.scenario.id, 'bank_rekening');
      expect(picked!.targetWords, contains('rekening'));
    });

    test('aiRoleplayContext 系统提示词注入 :::quiz JSON 格式约束', () {
      final ctx = aiRoleplayContext(kAiRoleplayScenarios.first);
      expect(ctx.system, contains(':::quiz'));
      expect(ctx.system, contains('"options"'));
      expect(ctx.system, contains('"answer"'));
    });
  });
}
