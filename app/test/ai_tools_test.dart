import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/activity_log.dart';
import 'package:katamemo/ai_chat.dart';
import 'package:katamemo/ai_logos.dart';
import 'package:katamemo/ai_tools.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/svg_path.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Map<String, Object?> row(String id, String zh, {int rank = 1}) => {
        'id': id,
        'word': id,
        'tier': 't1',
        'rank': rank,
        'frequency': 100,
        'word_class': 'v',
        'zh': zh,
        'senses': 'def=x',
        'enabled': 1,
        'favorite': 0,
        'user_word': 0,
      };

  Future<AppState> seed() async {
    resetActivityLogCache();
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([row('makan', '吃'), row('minum', '喝', rank: 2), row('tidur', '睡觉', rank: 3)]);
    await db.setDataVersion(kDataVersion);
    return AppState(db);
  }

  Map<String, dynamic> js(AiToolOutcome o) => jsonDecode(o.result) as Map<String, dynamic>;
  AiToolCall call(String name, Map<String, Object?> args) =>
      AiToolCall('x', name, jsonEncode(args));
  Future<bool> yes(AiPendingAction _) async => true;
  Future<bool> no(AiPendingAction _) async => false;

  group('工具声明', () {
    test('名字唯一、每个都有类别、参数是 object schema', () {
      final names = [for (final (_, s) in kAiToolSpecs) s.name];
      expect(names.toSet().length, names.length);
      for (final (k, s) in kAiToolSpecs) {
        expect(aiToolKind(s.name), k);
        expect(s.parameters['type'], 'object', reason: s.name);
      }
      expect(aiToolKind('add_to_memory'), AiToolKind.write);
      expect(aiToolKind('open_screen'), AiToolKind.nav);
      expect(aiToolKind('search_words'), AiToolKind.read);
    });
  });

  group('工具执行', () {
    test('search_words / get_word：查得到、标出是否在记忆里', () async {
      final app = await seed();
      final box = AiToolbox(app);
      await app.remember(['makan']);
      final r = js(await box.run(call('search_words', {'query': 'makan'}), confirm: yes));
      final first = (r['results'] as List).first as Map;
      expect(first['id'], 'makan');
      expect(first['in_memory'], true);
      final g = js(await box.run(call('get_word', {'id': 'minum'}), confirm: yes));
      expect(g['zh'], '喝');
      expect(g['in_memory'], false);
    });

    test('add_to_memory：拒绝就不写；同意才写 plan；已在记忆的跳过', () async {
      final app = await seed();
      final box = AiToolbox(app);
      var asked = 0;
      final o1 = await box.run(call('add_to_memory', {'ids': ['minum', 'tidur']}),
          confirm: (a) async {
        asked++;
        expect(a.title, contains('2 个词'));
        return false;
      });
      expect(js(o1)['declined'], true);
      expect(await app.db.plannedIds(['minum', 'tidur']), isEmpty);
      final o2 = await box.run(call('add_to_memory', {'ids': ['minum', 'tidur']}), confirm: yes);
      expect(js(o2)['added'], 2);
      expect(asked, 1);
      final o3 = await box.run(call('add_to_memory', {'ids': ['minum']}), confirm: (_) async {
        fail('都已在记忆里时不该再问');
      });
      expect(js(o3)['added'], 0);
    });

    test('create_word_list：同意后建好、带「打开词单」按钮；重名不覆盖', () async {
      final app = await seed();
      final box = AiToolbox(app);
      final o = await box.run(
          call('create_word_list', {'name': '今天', 'ids': ['makan', 'nope', 'minum']}),
          confirm: yes);
      expect(js(o)['count'], 2, reason: '不存在的 id 丢掉');
      expect(o.nav, isNotNull);
      final again = await box.run(
          call('create_word_list', {'name': '今天', 'ids': ['tidur']}), confirm: yes);
      expect(js(again)['error'], contains('同名'));
      final lists = await app.db.listWordLists();
      expect(lists.single.$3, 2);
      final add = await box.run(
          call('add_to_word_list', {'list_id': lists.single.$1, 'ids': ['tidur', 'makan']}),
          confirm: yes);
      expect(js(add)['added'], 1, reason: '已在词单里的不重复加');
    });

    test('today_mistakes：只数今天答「困难/模糊」的词', () async {
      final app = await seed();
      final raw = await app.db.db;
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = DateTime.now().subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      await raw.insert('study_log', {'card_id': 'makan', 'rating': 0, 'ts': now});
      await raw.insert('study_log', {'card_id': 'makan', 'rating': 2, 'ts': now + 1});
      await raw.insert('study_log', {'card_id': 'minum', 'rating': 2, 'ts': now});
      await raw.insert('study_log', {'card_id': 'tidur', 'rating': 1, 'ts': old});
      final r = js(await AiToolbox(app).run(call('today_mistakes', {}), confirm: yes));
      final ws = r['words'] as List;
      expect(ws.length, 1);
      expect((ws.single as Map)['id'], 'makan');
      final week = js(await AiToolbox(app).run(call('today_mistakes', {'days': 7}), confirm: yes));
      expect((week['words'] as List).length, 2);
    });

    test('recent_searches / grammar_mistakes：读带日期的日志', () async {
      final app = await seed();
      final yesterday = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      await logSearch(app.db, 'makan');
      await logSearch(app.db, 'xyzzy');
      await logSearch(app.db, 'tidur', at: yesterday);
      final r = js(await AiToolbox(app).run(call('recent_searches', {}), confirm: yes));
      expect([for (final w in r['words'] as List) (w as Map)['id']], ['makan']);
      expect(r['not_in_dictionary'], ['xyzzy']);

      await logGrammarWrong(app.db,
          quizId: 'q1', page: 'p1', question: 'Buku itu ___ adik.',
          options: ['membaca', 'dibaca'], picked: 0, answer: 1, why: '被动');
      final g = js(await AiToolbox(app).run(call('grammar_mistakes', {}), confirm: yes));
      final m = (g['mistakes'] as List).single as Map;
      expect(m['picked'], 'membaca');
      expect(m['correct'], 'dibaca');
    });

    test('set_daily_quota / save_mnemonic：确认后才改', () async {
      final app = await seed();
      final box = AiToolbox(app);
      await box.run(call('set_daily_quota', {'quota': 50}), confirm: no);
      expect(app.dailyQuota, 20);
      await box.run(call('set_daily_quota', {'quota': 50}), confirm: yes);
      expect(app.dailyQuota, 50);
      await box.run(call('save_mnemonic', {'id': 'makan', 'text': 'makan → 「妈看」吃饭'}), confirm: yes);
      expect((await app.db.getWord('makan'))!.mnemonic, contains('妈看'));
    });

    test('indonesian_reference：按主题词命中；对不上时给出目录', () async {
      final app = await seed();
      final box = AiToolbox(app);
      final v = js(await box.run(call('indonesian_reference', {'topic': '被动'}), confirm: yes));
      expect(v.keys.single, contains('语态'));
      expect(v.values.single, contains('Buku itu saya baca'));
      final k = js(await box.run(call('indonesian_reference', {'topic': '-kan'}), confirm: yes));
      expect(k.keys.single, contains('-kan'));
      final edit = js(await box.run(call('indonesian_reference', {'topic': '有效句'}), confirm: yes));
      expect(edit.keys.single, '有效句 编辑 写作');
      expect(edit.values.single, contains('yaitu'));
      final norm = js(await box.run(call('indonesian_reference', {'topic': '规范'}), confirm: yes));
      expect(norm.keys.single, '规范 常见误用');
      expect(norm.values.single, contains('sirop'));
      expect(norm.values.single, contains('populer'));
      final sd = js(await box.run(call('indonesian_reference', {'topic': 'K13'}), confirm: yes));
      expect(sd.keys.single, '小学 文本 教学 K13');
      expect(sd.values.single, contains('建立语境'));
      final research = js(await box.run(call('indonesian_reference', {'topic': '研究 思路'}), confirm: yes));
      expect(research.keys.single, '研究 思路 方法');
      expect(research.values.single, contains('证据级'));
      final tr = js(await box.run(call('indonesian_reference', {'topic': '翻译 错误'}), confirm: yes));
      expect(tr.keys.single, '翻译 错误 分析');
      expect(tr.values.single, contains('选词'));

      const copied = '句子成分 主语 谓语 宾语 补语 状语 句型 klausa';
      final cp = js(await box.run(call('indonesian_reference', {'topic': copied}), confirm: yes));
      expect(cp.keys, [copied]);

      final tg = js(await box.run(call('indonesian_reference', {'topic': 'menyapu'}), confirm: yes));
      expect(tg.keys.any((k) => k.contains('me-词缀')), isTrue);

      final tk = js(await box.run(call('indonesian_reference', {'topic': 'terima kasih'}), confirm: yes));
      expect(tk.keys.any((k) => k.startsWith('语气词')), isFalse);

      final wide = js(await box.run(call('indonesian_reference', {'topic': '词缀'}), confirm: yes));
      expect(wide['topics'], isA<List>());
      expect((wide['topics'] as List).length, greaterThan(3));

      final ft = js(await box.run(call('indonesian_reference', {'topic': 'sudah telah'}), confirm: yes));
      expect(ft.keys.any((k) => k.contains('时体')), isTrue);
      expect(ft.length, lessThanOrEqualTo(2));

      final dm = js(await box.run(call('indonesian_reference', {'topic': 'di mana 关系从句'}), confirm: yes));
      expect(dm.keys.any((k) => k.startsWith('介词')), isFalse);
      expect(dm.length, lessThanOrEqualTo(kReferenceMaxHits));
      expect('${dm.values.first}'.length, greaterThan(200));

      final oc = js(await box.run(call('indonesian_reference', {'topic': '宾语从句'}), confirm: yes));
      expect(oc.keys.single, contains('从句功能'));

      final bare = js(await box.run(call('indonesian_reference', {'topic': 'di'}), confirm: yes));
      expect((bare['topics'] as List).any((k) => '$k'.startsWith('介词')), isTrue);
      final bare2 = js(await box.run(call('indonesian_reference', {'topic': '语态'}), confirm: yes));
      expect(bare2.keys.any((k) => k.contains('语态')), isTrue);

      final utbk1 = js(await box.run(
          call('indonesian_reference', {'topic': 'cidera 还是 cedera'}),
          confirm: yes));
      expect(utbk1.keys, contains('规范 常见误用'));
      expect('${utbk1['规范 常见误用']}', contains('cidera→cedera'));
      final utbk2 = js(await box.run(
          call('indonesian_reference', {'topic': 'pengeboman 为什么是 penge-'}),
          confirm: yes));
      expect(utbk2.keys.single, contains('名词词缀'));
      expect(utbk2.values.single, contains('pengeboman'));
      final utbk3 = js(await box.run(
          call('indonesian_reference', {'topic': 'Bagi peserta 这句话有什么语病'}),
          confirm: yes));
      expect(utbk3.keys.single, '有效句 编辑 写作');
      expect(utbk3.values.single, contains('主语前误加介词导致缺主语'));
      final none = js(await box.run(call('indonesian_reference', {'topic': '天气'}), confirm: yes));
      expect(none['topics'], containsAll(kIndoReference.keys));
    });

    test('indonesianStem 词干还原 + BM25 检索 + sliceReferenceText 切片 + topics 多问题拆解配额', () async {
      expect(indonesianStem('menyapu'), contains('sapu'));
      expect(indonesianStem('memperhatikan'), contains('perhati'));
      expect(indonesianStem('pengajaran'), contains('ajar'));
      expect(indonesianStem('pertanggungjawaban'), contains('tanggungjawab'));

      final head = '第一段讲无关背景。' * 40;
      final tail = '尾部补充说明。' * 40;
      final longText = '$head关键规则：cidera 是非标准词，KBBI 标准词形为 cedera。$tail';
      final sliced = sliceReferenceText(longText, 'cidera cedera', 180);
      expect(sliced.length, lessThanOrEqualTo(180));
      expect(sliced, contains('cidera'));
      expect(sliced, contains('cedera'));

      final app = await seed();
      final box = AiToolbox(app);
      final multi = js(await box.run(
        call('indonesian_reference', {
          'topics': [
            'cidera 还是 cedera',
            'pengeboman 为什么是 penge-',
            'Bagi peserta 这句话有什么语病',
            'meskipun 和 namun 能不能连用',
            'belum 和 tidak 的区别',
          ]
        }),
        confirm: yes,
      ));
      final results = multi['results'] as Map<String, dynamic>;
      expect((results['cidera 还是 cedera'] as Map).keys, contains('规范 常见误用'));
      expect((results['pengeboman 为什么是 penge-'] as Map).keys, contains('名词词缀 peN- peN-an per-an ke-an 名词化'));
      expect((results['Bagi peserta 这句话有什么语病'] as Map).keys, contains('有效句 编辑 写作'));
      expect((results['meskipun 和 namun 能不能连用'] as Map).keys.any((k) => '$k'.contains('连词')), isTrue);
      expect(multi['deferred'], isNull);

      await app.setAiCtxTier(AiCtxTier.economy);
      final econMulti = js(await box.run(
        call('indonesian_reference', {
          'topics': [
            'cidera 还是 cedera',
            'pengeboman 为什么是 penge-',
            'Bagi peserta 这句话有什么语病',
            'meskipun 和 namun 能不能连用',
            'belum 和 tidak 的区别',
          ]
        }),
        confirm: yes,
      ));
      expect(econMulti['deferred'], ['belum 和 tidak 的区别']);

      final wa = js(await box.run(
        call('indonesian_reference', {'topic': 'WhatsApp 置顶 转发 撤回'}),
        confirm: yes,
      ));
      expect(wa.keys.single, contains('手机软件 聊天界面'));
      expect(wa.values.single, contains('Sematkan'));
      expect(wa.values.single, contains('Teruskan'));
      expect(wa.values.single, contains('Hapus untuk semua orang'));
    });

    test('indonesian_reference 与工具说明不吐出 TBBBI / Tata Bahasa 等书名', () async {
      final app = await seed();
      final box = AiToolbox(app);
      for (final (_, spec) in kAiToolSpecs) {
        expect(spec.description, isNot(contains('TBBBI')));
        expect(spec.description, isNot(contains('Tata Bahasa')));
      }
      for (final topic in kIndoReference.keys) {
        final out = js(await box.run(call('indonesian_reference', {'topic': topic}), confirm: yes));
        final body = out.values.join('\n');
        expect(body, isNot(contains('TBBBI')), reason: 'topic=$topic');
        expect(body, isNot(contains('Tata Bahasa')), reason: 'topic=$topic');
        expect(body, isNot(contains('morphology.md')), reason: 'topic=$topic');
      }
    });

    test('水平：两档讲法不同；坏值与已删的「高级」都回落进阶', () {

      expect(AiLevel.values.length, 2);
      expect(aiLevelFromName('advanced'), AiLevel.intermediate);
      expect(aiLevelFromName('乱写'), AiLevel.intermediate);
      expect(aiLevelRule(AiLevel.beginner), contains('入门'));
      expect(aiLevelRule(AiLevel.intermediate), contains('进阶'));
    });

    test('aiPlainText：表格、引用、标题转成纯文字', () {
      const md = '### 批改\n| 原句 | 改后 |\n|---|---|\n| *Saya bukan suka* | **Saya tidak suka** |\n> 规则：tidak 否定动词';
      final p = aiPlainText(md);
      expect(p, isNot(contains('|')));
      expect(p, isNot(contains('---')));
      expect(p, isNot(contains('>')));
      expect(p, contains('Saya tidak suka'));
      expect(p.startsWith('批改'), isTrue);
    });

    test('app_guide / open_screen / 未知工具', () async {
      final app = await seed();
      final box = AiToolbox(app);
      final all = js(await box.run(call('app_guide', {}), confirm: yes));
      expect(all.keys, containsAll(kAppGuide.keys));
      final one = js(await box.run(call('app_guide', {'topic': '今日卡量'}), confirm: yes));
      expect(one.keys, ['今日卡量']);
      final tab = await box.run(call('open_screen', {'screen': 'stats'}), confirm: yes);
      expect(tab.nav!.closeSheet, isTrue, reason: '切 Tab 要先关弹层');
      final page = await box.run(call('open_screen', {'screen': 'settings'}), confirm: yes);
      expect(page.nav!.closeSheet, isFalse);
      final bad = await box.run(call('open_screen', {'screen': 'mars'}), confirm: yes);
      expect(bad.nav, isNull);
      final unk = await box.run(call('rm_rf', {}), confirm: yes);
      expect(js(unk)['error'], contains('没有这个工具'));
    });
  });

  group('日志', () {
    test('搜索日志去重、最近在前、封顶', () async {
      final app = await seed();
      for (var i = 0; i < kLogSearchCap + 5; i++) {
        await logSearch(app.db, 'w$i');
      }
      await logSearch(app.db, 'W1');
      final s = await searchesSince(app.db, DateTime(2000));
      expect(s.first, 'W1');
      expect(s.length, lessThanOrEqualTo(kLogSearchCap));
    });
  });

  group('服务商图标', () {
    test('每个图标都能解析，且落在 24×24 画布内', () {

      if (kAiLogos.isEmpty) return;
      expect(kAiLogos.keys, containsAll(<String>['deepseek', 'glm', 'claude']));
      for (final e in kAiLogos.entries) {
        for (final (op, d) in e.value) {
          expect(op, inInclusiveRange(0, 1));
          final b = parseSvgPath(d).getBounds();
          expect(b.isEmpty, isFalse, reason: e.key);
          expect(b.left, greaterThanOrEqualTo(-0.5), reason: e.key);
          expect(b.right, lessThanOrEqualTo(24.5), reason: e.key);
          expect(b.top, greaterThanOrEqualTo(-0.5), reason: e.key);
          expect(b.bottom, lessThanOrEqualTo(24.5), reason: e.key);
        }
      }
    });

    test('解析器：紧凑数字与挤在一起的弧线标志位', () {
      final p = parseSvgPath('M0 0h10v10H0zm2 2a2 2 0 014 0 2 2 0 01-4 0z');
      expect(p.getBounds().right, closeTo(10, 0.01));
      expect(() => parseSvgPath('M0 0 X1'), throwsFormatException);
    });
  });
}
