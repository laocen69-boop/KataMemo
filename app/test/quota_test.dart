import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Map<String, Object?> row(String id,
          {int rank = 1, int enabled = 1, String tier = 'core'}) =>
      {
        'id': id,
        'word': id,
        'tier': tier,
        'rank': rank,
        'zh': '释义-$id',
        'enabled': enabled,
        'favorite': 0,
      };

  Future<AppDb> seed(List<Map<String, Object?>> words) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords(words);

    await db.setDataVersion(kDataVersion);
    return db;
  }

  test('今日新学词数：按 first_seen 计数，同一张卡重复评分不重复算', () async {

    final db = await seed([row('satu'), row('dua'), row('tiga', rank: 3)]);
    expect(await db.todayNewCount(), 0);

    await db.saveSrs('satu', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('satu', Fsrs.ratingKnow);
    expect(await db.todayNewCount(), 1);

    final s = await db.getSrs('satu');
    await db.saveSrs('satu', Fsrs.apply(s, Fsrs.ratingFuzzy));
    await db.logRating('satu', Fsrs.ratingFuzzy);
    await db.saveSrs(
        'satu', Fsrs.apply(await db.getSrs('satu'), Fsrs.ratingKnow));
    await db.logRating('satu', Fsrs.ratingKnow);

    expect(await db.todayNewCount(), 1, reason: '重复评分不该多算一个新词');
    expect(await db.todayLogCount(), 3, reason: '作答 3 次（次数只用来对账）');

    expect(await db.todayAnsweredWords(), 1, reason: '同一张卡今天答 3 遍只扣 1 张额度');

    await db.saveSrs('dua', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('dua', Fsrs.ratingKnow);
    expect(await db.todayNewCount(), 2);

    await db.deleteSrs('dua');
    expect(await db.todayNewCount(), 1);

    await db.close();
  });

  test('todayNewIds：与 todayNewCount 同一口径（今天第一次接触的词）', () async {
    final db = await seed([row('a1'), row('a2', rank: 2), row('a3', rank: 3)]);

    await db.saveSrs('a1', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('a1', Fsrs.ratingKnow);
    await db.saveSrs('a2', Fsrs.apply(null, Fsrs.ratingFuzzy));
    await db.logRating('a2', Fsrs.ratingFuzzy);

    await db.saveSrs('a3', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('a3', Fsrs.ratingKnow);
    final y =
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    await db.db.then((d) => d.update('srs', {'first_seen': y},
        where: 'card_id = ?', whereArgs: ['a3']));

    expect(await db.todayNewCount(), 2);
    expect(await db.todayNewIds(), {'a1', 'a2'},
        reason: '学习页第三档按钮靠它判「认识/记得」，判据必须与「今日新学 N」一致');

    expect((await db.todayNewIds()).length, await db.todayNewCount());

    await db.close();
  });

  test('额度：学满之后不再放词，但池子仍有货（区分「练完」与「额度用完」）', () async {
    final db = await seed([
      for (var i = 1; i <= 6; i++) row('w$i', rank: i),
    ]);
    await db.planWord([for (var i = 1; i <= 6; i++) 'w$i']);
    const quota = 3;

    final b1 = await db.buildSessionQueue(dailyQuota: quota);
    expect(b1.remaining, 3);
    expect(b1.fresh.length, 3);

    for (final w in b1.fresh) {
      await db.saveSrs(w.id, Fsrs.apply(null, Fsrs.ratingKnow));
      await db.logRating(w.id, Fsrs.ratingKnow);
    }

    final b2 = await db.buildSessionQueue(dailyQuota: quota);
    expect(b2.done, 3);
    expect(b2.remaining, 0);
    expect(b2.fresh, isEmpty);

    expect(b2.pool, 3);

    final b3 = await db.buildSessionQueue(dailyQuota: 5);
    expect(b3.remaining, 2);
    expect(b3.fresh.length, 2);

    await db.close();
  });

  final relearnInsideToday = () {
    final n = DateTime.now();
    return n
        .add(Fsrs.relearnStep)
        .isBefore(DateTime(n.year, n.month, n.day, 23, 59, 59));
  }();

  test('额度按张去重：同一张卡答 4 遍只吃 1 张，别卡照样排得上', () async {
    final db = await seed([
      for (var i = 1; i <= 6; i++) row('q$i', rank: i),
    ]);
    await db.planWord([for (var i = 1; i <= 6; i++) 'q$i']);
    const quota = 4;

    final b = await db.buildSessionQueue(dailyQuota: quota);
    expect(b.fresh.length, 4);
    final stubborn = b.fresh.first;

    for (var i = 0; i < 4; i++) {
      await db.saveSrs(stubborn.id,
          Fsrs.apply(await db.getSrs(stubborn.id), Fsrs.ratingForget));
      await db.logRating(stubborn.id, Fsrs.ratingForget);
    }

    for (final w in b.fresh.skip(1).take(2)) {
      await db.saveSrs(w.id, Fsrs.apply(null, Fsrs.ratingKnow));
      await db.logRating(w.id, Fsrs.ratingKnow);
    }

    expect(await db.todayLogCount(), 6, reason: '一共作答 6 次');
    expect(await db.todayAnsweredWords(), 3, reason: '但只碰过 3 张卡');

    final again = await db.buildSessionQueue(dailyQuota: quota);
    expect(again.done, 3);
    expect(again.remaining, 1);

    expect(again.due.map((w) => w.id), [stubborn.id],
        reason: '答错的卡今天还欠一遍，额度的最后一格先给它');
    expect(again.fresh, isEmpty, reason: 'freshCap = 1 − 1 = 0');

    final t = await db.todayStats();
    expect(t['new']! + t['review']!, await db.todayAnsweredWords(),
        reason: '额度闸门与统计页必须数同一件事');

    await db.close();
  }, skip: relearnInsideToday
      ? false
      : '23:50 后 +10 分钟跨天，前提不成立（真实行为，见 study_ui_test 同款前提）');

  test('加入记忆：没加入的不进队列，加入才出现，移出即消失', () async {
    final db = await seed([
      row('a', rank: 1),
      row('b', rank: 2),
      row('z', rank: 9999),
      row('off', rank: 3, enabled: 0),
    ]);

    expect(await db.newWords(limit: 4), isEmpty,
        reason: '一个都没加入记忆 → 队列必须是空的（旧版会把整库倒进来）');

    await db.planWord(['z']);
    expect(await db.isPlanned('z'), isTrue);
    expect((await db.newWords(limit: 4)).map((w) => w.id), ['z']);

    await db.planWord(['a', 'b']);
    expect((await db.newWords(limit: 4)).map((w) => w.id), ['a', 'b', 'z'],
        reason: 'plan 只管成员，排序仍是词频优先');

    await db.planWord(['off']);
    expect((await db.getWord('off'))!.enabled, isTrue);
    expect(
        (await db.newWords(limit: 4)).map((w) => w.id), ['a', 'b', 'off', 'z']);

    await db.unenroll(['off']);
    expect(await db.isPlanned('off'), isFalse);
    expect((await db.newWords(limit: 4)).map((w) => w.id), ['a', 'b', 'z']);
    expect(await db.planCount(), 3);

    await db.close();
  });

  test('批量：加入/移出记忆作用在全量筛选结果上', () async {
    final db = await seed([
      row('c1', rank: 1, tier: 'core'),
      row('c2', rank: 2, tier: 'core'),
      row('a1', rank: 3, tier: 'advanced'),
    ]);
    const core = {
      'tier': ['core']
    };

    expect(await db.planByFilter(core), 2, reason: '整库加入：只吃 core 那两个');
    final p = await db.bookProgress(core);
    expect(p.all, 2);
    expect(p.total, 2);
    expect(p.started, 0);

    expect(await db.unenrollByFilter(core), 2);
    final p2 = await db.bookProgress(core);
    expect(p2.all, 2, reason: '全部词数不受 enabled 影响（看不见就没法加回来）');
    expect(p2.total, 0, reason: '在记忆里已经一个不剩');

    expect(await db.newWords(limit: 10), isEmpty);

    expect(await db.planByFilter(core), 2);
    expect((await db.bookProgress(core)).total, 2);
    expect((await db.newWords(limit: 10)).map((w) => w.id), ['c1', 'c2'],
        reason: 'enabled 也要被拉回 1，词才真的能进队列');

    await db.planWord(['c1', 'c2', 'a1']);
    expect(await db.planCount(), 3);
    expect(await db.unplanByFilter(core), 2);
    expect(await db.planCount(), 1, reason: '只剩 advanced 那个');

    await db.close();
  });

  test('设置持久化：额度 / 学习方向 / 夜间模式重启后仍在', () async {
    final db = await seed([row('makan')]);

    final app = AppState(db);
    await app.init();
    expect(app.dailyQuota, 20, reason: '首次运行用默认值');

    await app.setQuota(88);
    await app.setStudyMode('zh2id');
    await app.setDarkMode(true);
    await app.setRetention(0.85);

    await app.setReminderOn(false);
    expect(app.reminderOn, isFalse);
    expect(app.queueRevision, greaterThan(0), reason: '改额度要通知学习页重排队列');

    final app2 = AppState(db);
    await app2.init();
    expect(app2.dailyQuota, 88);
    expect(app2.studyMode, 'zh2id');
    expect(app2.darkMode, isTrue);
    expect(app2.retention, closeTo(0.85, 1e-9));
    expect(app2.reminderOn, isFalse, reason: '关掉的提醒重启后不能自己变回开');

    await app2.setQuota(1000);
    expect(app2.dailyQuota, 1000, reason: '超过 500 的额度要能存下来');
    await app2.setQuota(999999);
    expect(app2.dailyQuota, AppState.kMaxDailyQuota,
        reason: '防手滑，但上限远在 500 之上');

    await app2.setQuota(0);
    expect(app2.dailyQuota, 0);
    await app2.setQuota(-3);
    expect(app2.dailyQuota, 0, reason: '负数也夹到 0，不是夹到 5');

    final app3 = AppState(db);
    await app3.init();
    expect(app3.dailyQuota, 0);

    await db.close();
  });

  test('单组不再夹 500：额度本身是唯一闸门（实施单 B，2026-10-12）', () async {

    final db = await seed([for (var i = 1; i <= 600; i++) row('s$i', rank: i)]);
    await db.planWord([for (var i = 1; i <= 600; i++) 's$i']);
    final app = AppState(db);
    await app.init();
    await app.setQuota(AppState.kMaxDailyQuota);

    final q1 = await db.buildSessionQueue(dailyQuota: app.dailyQuota);
    expect(q1.fresh.length, 600,
        reason: '额度 9999 ⇒ 600 个生词一次全排出来（不再夹 500）');
    expect(q1.pool, 600, reason: '库里还有 600 个没学过的');

    for (final w in q1.fresh.take(10)) {
      await db.saveSrs(w.id, Fsrs.apply(null, Fsrs.ratingKnow));
      await db.logRating(w.id, Fsrs.ratingKnow);
    }
    final q2 = await db.buildSessionQueue(dailyQuota: app.dailyQuota);
    expect(q2.fresh.length, 590,
        reason: '600 − 已学 10 = 590 个还没学的；额度 9999−10 仍够');
    expect(q2.learnedNew, 10);

    await db.close();
  });

  test('随机加入：按额度挑生词、跳过已学与已在计划的、可反复换一批（v2.5.17）', () async {

    final db = await seed([for (var i = 1; i <= 10; i++) row('r$i', rank: i)]);

    await db.saveSrs('r1', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('r1', Fsrs.ratingKnow);

    final picked = await db.planRandom(null, 4);
    expect(picked, hasLength(4));
    expect(picked, isNot(contains('r1')), reason: '已学过的词不该被加入计划');
    expect(await db.planCount(), 4);

    final second = await db.planRandom(null, 3);
    expect(second, hasLength(3));
    expect(picked.toSet().intersection(second.toSet()), isEmpty,
        reason: 'planRandom 跳过已在 plan 的词 → 连点两次就是「换一批」');
    expect(await db.planCount(), 7);

    final third = await db.planRandom(null, 10);
    expect(third, hasLength(2), reason: '10 个词里 1 个已学、7 个已计划，还剩 2 个');
    expect(await db.planRandom(null, 5), isEmpty);

    expect(await db.planRandom(null, 0), isEmpty);
    expect(await db.planRandom(null, -3), isEmpty);

    final q = await db.buildSessionQueue(dailyQuota: 5);
    final planned = picked.toSet()
      ..addAll(second)
      ..addAll(third);
    expect(planned, hasLength(9), reason: '4 + 3 + 2 次随机加入');
    expect(await db.planCount(), 9);
    expect(q.fresh, isNotEmpty);
    expect(q.fresh.every((w) => planned.contains(w.id)), isTrue,
        reason: '新词队列只从 plan 里取；r1 已学过，不会再当新词派发');

    await db.close();
  });

  test('plannedIds：一次 IN 查完（列表行尾按钮画勾用，避免 N+1）', () async {
    final db = await seed([for (var i = 1; i <= 5; i++) row('p$i', rank: i)]);
    await db.planWord(['p1', 'p3']);
    final s = await db.plannedIds(['p1', 'p2', 'p3', 'p4', 'p5']);
    expect(s, {'p1', 'p3'});
    expect(await db.plannedIds([]), isEmpty);

    expect(await db.plannedIds(['不存在']), isEmpty);
    await db.close();
  });

  test('词形折叠：带标点 / 带音标的词都能查', () async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'makan',
        'word': 'makan',
        'tier': 'core',
        'rank': 1,
        'zh': '吃',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'tembok',
        'word': 'témbok',
        'tier': 'core',
        'rank': 2,
        'zh': '墙壁',
        'enabled': 1,
        'favorite': 0
      },
    ]);

    expect((await db.searchWords('makan,'))!.id, 'makan');
    expect((await db.searchWords('témbok.'))!.id, 'tembok');
    expect((await db.searchWords('(makan)'))!.id, 'makan');

    expect(await db.searchWords('—'), isNull);

    expect(AppDb.fold('3M'), '3m');
    expect(AppDb.fold('ke-2'), 'ke-2');
    expect(AppDb.fold('témbok.'), 'tembok');
    expect(AppDb.tokens('Aku makan nasi.'), ['Aku', 'makan', 'nasi.']);

    await db.saveSrs('makan', Fsrs.apply(null, Fsrs.ratingKnow));
    expect(await db.startedIds(null), {'makan'});

    await db.close();
  });

  test('v3 -> v4 迁移：补 first_seen 并回填，且不误触发全量重导入', () async {

    final dir = await Directory.systemTemp.createTemp('katamemo_mig');
    final path = p.join(dir.path, 'v3.db');
    const v3words = '''
      CREATE TABLE words (
        id TEXT PRIMARY KEY, word TEXT NOT NULL, tier TEXT, rank INTEGER,
        frequency INTEGER DEFAULT 0, phonetic TEXT, word_class TEXT,
        domains TEXT, topics TEXT, origin TEXT, base_word TEXT,
        non_standard TEXT, non_standard_forms TEXT, variants TEXT,
        senses TEXT, examples TEXT, derivations TEXT, zh TEXT,
        affix_base TEXT, affixes TEXT, audio_ardi TEXT, audio_gadis TEXT,
        audio_human TEXT, mnemonic TEXT, enabled INTEGER DEFAULT 1,
        favorite INTEGER DEFAULT 0)''';

    final raw = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 3,
            onCreate: (d, v) async {
              await d.execute(v3words);

              await d.execute('CREATE TABLE srs (card_id TEXT PRIMARY KEY, '
                  'stability REAL DEFAULT 0, difficulty REAL DEFAULT 5, due INTEGER, '
                  'last_review INTEGER, reps INTEGER DEFAULT 0, lapses INTEGER DEFAULT 0, '
                  'state INTEGER DEFAULT 0, step INTEGER DEFAULT 0)');
              await d.execute('CREATE TABLE study_log (id INTEGER PRIMARY KEY '
                  'AUTOINCREMENT, card_id TEXT, rating INTEGER, ts INTEGER)');
              await d.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT)');
              await d.execute('CREATE TABLE user_edit (card_id TEXT NOT NULL, '
                  'field TEXT NOT NULL, value TEXT, ts INTEGER, '
                  'PRIMARY KEY (card_id, field))');
            }));
    await raw.insert(
        'words', {'id': 'lama', 'word': 'lama', 'enabled': 1, 'favorite': 0});
    await raw.insert('srs', {'card_id': 'lama', 'reps': 1, 'due': 0});
    await raw.insert(
        'study_log', {'card_id': 'lama', 'rating': 2, 'ts': 1700000000000});
    await raw.insert('meta', {'k': 'data_version', 'v': '$kDataVersion'});
    await raw.close();

    final db = AppDb(dbPath: path);
    await db.db;

    final cols = await db.db.then((d) => d.rawQuery('PRAGMA table_info(srs)'));
    expect(cols.map((c) => c['name']), contains('first_seen'));

    final row0 = await db.db.then((d) => d.query('srs', limit: 1));
    expect(row0, isNotEmpty, reason: '老数据必须留着');
    expect(row0.first['first_seen'], 1700000000000);

    expect(await db.dataVersion(), kDataVersion);

    final plan = await db.db.then((d) => d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='plan'"));
    expect(plan, isNotEmpty);

    await db.saveSrs(
        'lama', Fsrs.apply(await db.getSrs('lama'), Fsrs.ratingKnow));
    final row1 = await db.db.then((d) => d.query('srs', limit: 1));
    expect(row1.first['first_seen'], 1700000000000);

    await db.close();
    await dir.delete(recursive: true);
  });
}
