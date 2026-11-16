import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/audio.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/study_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Map<String, Object?> row(int i) => {
        'id': 'w$i',
        'word': 'w$i',
        'tier': 'core',
        'rank': i,
        'zh': '释义$i',
        'enabled': 1,
        'favorite': 0,
      };

  Future<AppDb> seed(int n, {bool enroll = true}) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([for (var i = 1; i <= n; i++) row(i)]);
    await db.setDataVersion(kDataVersion);
    if (enroll) await db.planWord([for (var i = 1; i <= n; i++) 'w$i']);
    return db;
  }

  Future<void> learn(AppDb db, String id) async {
    await db.saveSrs(id, Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating(id, Fsrs.ratingKnow);
  }

  test('额度闸门：复习和新学共用同一份额度', () async {
    final db = await seed(6);

    final s1 = await db.buildSessionQueue(dailyQuota: 3);
    expect(s1.fresh.length, 3);
    expect(s1.learnedNew, 0);
    expect(s1.pool, 6);

    for (final w in s1.fresh) {
      await learn(db, w.id);
    }

    final s2 = await db.buildSessionQueue(dailyQuota: 3);
    expect(s2.done, 3, reason: '三张卡各答一次 = 三张额度');
    expect(s2.remaining, 0);
    expect(s2.fresh, isEmpty, reason: '额度用完了');
    expect(s2.pool, 3, reason: '库里还有 3 个生词，为的是区分「学完」和「额度用完」');

    final overdue = (await db.getSrs('w1'))!;
    overdue.due = DateTime.now().subtract(const Duration(hours: 1));
    await db.saveSrs('w1', overdue);

    final plan = await db.todayPlan(dailyQuota: 3);
    expect(plan.newPending, 1, reason: '确实到期了（今天欠着一次作答），不是没排上');

    final s3 = await db.buildSessionQueue(dailyQuota: 3);
    expect(s3.fresh, isEmpty);
    expect(s3.due, isEmpty, reason: '额度已满时到期复习也不给——这就是「复习也占额度」的另一面');

    final s4 = await db.buildSessionQueue(dailyQuota: 4);
    expect(s4.remaining, 1);
    expect(s4.due.map((w) => w.id), ['w1'], reason: '复习优先占额度');
    expect(s4.fresh, isEmpty, reason: 'freshCap = 1 - 1 = 0');

    await db.close();
  });

  test('到期复习：受剩余额度夹，但 dueCards 本身不再截 500', () async {
    final db = await seed(600);
    final past = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 1; i <= 600; i++) {
      await learn(db, 'w$i');
      final s = (await db.getSrs('w$i'))!..due = past;
      await db.saveSrs('w$i', s);
    }

    final q0 = await db.buildSessionQueue(dailyQuota: 0);
    expect(q0.fresh, isEmpty);
    expect(q0.due, isEmpty);

    final q = await db.buildSessionQueue(dailyQuota: 9999);
    expect(q.due, hasLength(600), reason: '额度够大就全进队，不再 500 一批');
    expect(q.fresh, isEmpty, reason: 'freshCap = 9999 - 500 但库里没生词了');

    final plan = await db.todayPlan(dailyQuota: 9999);
    expect(plan.newPending + plan.reviewPending + plan.reviewBacklog, 600,
        reason: '「还有 100 张没排上」靠这几个数（旧 dueCount() 已删）');

    expect(await db.dueCards(limit: 500), hasLength(500));
    expect(await db.dueCards(), hasLength(600));

    final qi = await db.buildSessionQueueIds(dailyQuota: 9999);
    expect(qi.due, hasLength(600));
    expect(qi.due, q.due.map((c) => c.id).toList(),
        reason: 'id 版与整行版顺序必须一致（共用同一份 SQL）');

    final s1 = (await db.getSrs('w1'))!;
    await db.saveSrs('w1', Fsrs.apply(s1, Fsrs.ratingKnow));
    expect(await db.dueCards(), hasLength(599));

    await db.close();
  });

  test('把额度下调到今日已学数以下：不能把整库倒进队列', () async {
    final db = await seed(6);
    for (final w in (await db.buildSessionQueue(dailyQuota: 3)).fresh) {
      await learn(db, w.id);
    }
    expect(await db.todayNewCount(), 3);

    final s = await db.buildSessionQueue(dailyQuota: 1);
    expect(s.remaining, -2);
    expect(s.fresh, isEmpty, reason: '负额度不能放行任何新词');
    expect(s.due, isEmpty, reason: '负额度同样不能放行复习');
    expect(s.pool, 3);

    final s0 = await db.buildSessionQueue(dailyQuota: 3);
    expect(s0.fresh, isEmpty);

    expect(await db.newWords(limit: 0), isEmpty);
    expect(await db.newWords(limit: -1), isEmpty);
    expect(await db.newWords(limit: -999), isEmpty);

    await db.close();
  });

  test('【用户实测复现】答了 52 次但只碰过 30 张：额度按 30 扣', () async {
    final db = await seed(30);

    final first = await db.buildSessionQueue(dailyQuota: 22);
    expect(first.fresh.length, 22);
    for (final w in first.fresh) {
      await learn(db, w.id);
    }
    expect(await db.todayNewCount(), 22);
    expect(await db.todayLogCount(), 22);

    final second = await db.buildSessionQueue(dailyQuota: 500);
    expect(second.fresh.length, 8, reason: '库里只剩 8 个生词了');
    for (final w in second.fresh) {
      await learn(db, w.id);
    }
    expect(await db.todayNewCount(), 30);

    for (final w in first.fresh) {
      final s = (await db.getSrs(w.id))!;
      s.due = DateTime.now().subtract(const Duration(hours: 1));
      await db.saveSrs(w.id, s);
      await db.logRating(w.id, Fsrs.ratingKnow);
    }

    expect(await db.todayLogCount(), 52, reason: '作答次数 52（只作对账）');
    expect(await db.todayAnsweredWords(), 30, reason: '碰过的张数 30（扣额度）');
    expect(await db.todayNewCount(), 30, reason: '复习不能算成今天新学的词');

    expect(await db.todayLogCount() - await db.todayAnsweredWords(), 22,
        reason: '重复作答被多吃掉的额度张数');

    final s = await db.buildSessionQueue(dailyQuota: 45);
    expect(s.done, 30);
    expect(s.remaining, 15, reason: '45 - 30：旧闸门这里是 45 - 52 = -7，一张都不排');
    expect(s.due, hasLength(15), reason: '复习优先占额度');
    expect(s.fresh, isEmpty);
    expect(s.learnedNew, 30);
    expect(s.pool, 0, reason: '这 30 个词库里已经学完了');

    final s2 = await db.buildSessionQueue(dailyQuota: 30);
    expect(s2.remaining, 0);
    expect(s2.due, isEmpty);
    expect(s2.fresh, isEmpty);

    final s3 = await db.buildSessionQueue(dailyQuota: 31);
    expect(s3.due, hasLength(1));
    expect(s3.fresh, isEmpty, reason: 'freshCap = 1 - 1 = 0');

    await db.close();
  });

  test('额度 45 已作答 23 -> 还剩 22 张名额', () async {
    final db = await seed(200);

    final a = await db.buildSessionQueue(dailyQuota: 500);
    expect(a.fresh.length, 200, reason: '额度 500 时把库里 200 个生词都排进来');
    for (final w in a.fresh.take(23)) {
      await learn(db, w.id);
    }
    expect(await db.todayNewCount(), 23);

    final b = await db.buildSessionQueue(dailyQuota: 45);
    expect(b.learnedNew, 23);
    expect(b.fresh.length, 22, reason: '45 - 23 = 22，正是用户看到的那个数');
    expect(b.pool, 177);

    final c = await db.buildSessionQueue(dailyQuota: 23);
    expect(c.fresh, isEmpty, reason: '额度扣的是碰过的张数，等于已学就正好卡住');

    final d = await db.buildSessionQueue(dailyQuota: 0);
    expect(d.fresh, isEmpty);
    expect(d.due, isEmpty);

    await db.close();
  });

  test('调高额度立刻能继续学，且只放出差额', () async {
    final db = await seed(6);
    for (final w in (await db.buildSessionQueue(dailyQuota: 3)).fresh) {
      await learn(db, w.id);
    }

    final s = await db.buildSessionQueue(dailyQuota: 5);
    expect(s.fresh.length, 2, reason: '5 - 3 = 2，不多给也不少给');
    for (final w in s.fresh) {
      await learn(db, w.id);
    }

    final s2 = await db.buildSessionQueue(dailyQuota: 5);
    expect(s2.learnedNew, 5);
    expect(s2.fresh, isEmpty);
    expect(s2.pool, 1);

    final s3 = await db.buildSessionQueue(dailyQuota: 500);
    expect(s3.fresh.length, 1);

    await db.close();
  });

  test('撤销：撤掉重复作答不退额度，撤掉唯一那次才退', () async {
    final db = await seed(6);
    final s1 = await db.buildSessionQueue(dailyQuota: 4);
    final first = s1.fresh.first.id;

    await db.saveSrs(first, Fsrs.apply(null, Fsrs.ratingFuzzy));
    await db.logRating(first, Fsrs.ratingFuzzy);

    await db.saveSrs(
        first, Fsrs.apply(await db.getSrs(first), Fsrs.ratingKnow));
    await db.logRating(first, Fsrs.ratingKnow);
    await db.saveSrs(
        first, Fsrs.apply(await db.getSrs(first), Fsrs.ratingKnow));
    await db.logRating(first, Fsrs.ratingKnow);

    expect(await db.todayNewCount(), 1, reason: '今日新学词数只有 1（显示用）');
    expect(await db.todayLogCount(), 3, reason: '作答 3 次（只作对账）');
    expect(await db.todayAnsweredWords(), 1, reason: '额度只扣 1 张');

    final rows = await db.db.then((d) => d.query('study_log',
        columns: ['id'],
        where: 'card_id = ?',
        whereArgs: [first],
        orderBy: 'id ASC'));
    final logIds = [for (final r in rows) r['id'] as int];
    expect(logIds, hasLength(3));

    await db.deleteLog(logIds.last);
    await db.deleteLog(logIds[1]);
    expect(await db.todayLogCount(), 1);
    expect(await db.todayAnsweredWords(), 1, reason: '撤重复作答不退额度');
    final s2 = await db.buildSessionQueue(dailyQuota: 4);
    expect(s2.remaining, 3, reason: '4 - 1 = 3；旧口径这里只会剩 1 张');
    expect(s2.fresh.length, 3);

    await db.deleteLog(logIds.first);
    await db.deleteSrs(first);
    expect(await db.todayAnsweredWords(), 0);
    expect(await db.todayNewCount(), 0);
    expect((await db.buildSessionQueue(dailyQuota: 4)).remaining, 4);

    await db.close();
  });

  test('统计页「今日新学」与学习页「新词」同口径（都按 first_seen）', () async {
    final db = await seed(3);

    await learn(db, 'w1');
    final s = (await db.getSrs('w1'))!;
    await db.saveSrs('w1', Fsrs.apply(s, Fsrs.ratingFuzzy));
    await db.logRating('w1', Fsrs.ratingFuzzy);
    expect((await db.getSrs('w1'))!.reps, 2);

    expect(await db.todayNewCount(), 1);
    expect((await db.todayStats())['new'], 1, reason: '统计页与学习页必须是同一个数');

    expect((await db.todayStats())['review'], 0,
        reason: '复习 = 当天过过的词数(1) − 新学(1)');
    expect(await db.todayLogCount(), 2, reason: '作答 2 次（只作对账，不扣额度）');
    expect(await db.todayAnsweredWords(), 1, reason: '扣额度的是这 1 张');

    await db.close();
  });

  test('附着词并入宿主卡：复习进度搬到宿主，不凭空消失', () async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'aku',
        'word': 'aku',
        'tier': 'core',
        'rank': 1,
        'zh': '我',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'kamu',
        'word': 'kamu',
        'tier': 'core',
        'rank': 2,
        'zh': '你',
        'enabled': 1,
        'favorite': 0
      },
    ]);
    await db.setDataVersion(kDataVersion);

    final s = Fsrs.apply(null, Fsrs.ratingKnow)..stability = 12.0;
    await db.saveSrs('ku', s);
    await db.logRating('ku', Fsrs.ratingKnow);
    await db.planWord(['ku']);

    final moved = await db.remapMergedCards();
    expect(moved, 1);
    expect(await db.getSrs('ku'), isNull, reason: '旧卡的 srs 行要删掉');
    final host = await db.getSrs('aku');
    expect(host, isNotNull, reason: '进度必须搬到宿主卡');
    expect(host!.stability, 12.0);
    expect(await db.isPlanned('aku'), isTrue, reason: '置顶标记也要搬');
    expect(await db.isPlanned('ku'), isFalse);

    final newer = Fsrs.apply(null, Fsrs.ratingKnow)..stability = 40.0;
    await db.saveSrs('kamu', newer);
    final older = Fsrs.apply(null, Fsrs.ratingKnow)..stability = 3.0;
    await db.saveSrs('mu', older);
    await db.remapMergedCards();
    expect((await db.getSrs('kamu'))!.stability, 3.0,
        reason: '取 stability 更小（更保守）的那条');

    await db.upsertWords([
      {
        'id': 'pasaran',
        'word': 'pasaran',
        'tier': 't4',
        'rank': 9,
        'zh': '市场；市面',
        'enabled': 1,
        'favorite': 0
      },
    ]);
    final bad = Fsrs.apply(null, Fsrs.ratingKnow)..stability = 7.0;
    await db.saveSrs('pasa\u0433an', bad);
    await db.remapMergedCards();
    expect((await db.getSrs('pasaran'))?.stability, 7.0,
        reason: '坏字形条目 pasaгan 的进度要搬到正确拼写的 pasaran 上');
    expect(await db.getSrs('pasa\u0433an'), isNull);

    expect(await db.remapMergedCards(), 0);

    await db.close();
  });

  test('用户操作路径：额度设成 0 后一张都不排', () async {

    final db = await seed(30);
    final app = AppState(db);
    await app.init();

    await app.setQuota(20);
    final before = await db.buildSessionQueue(dailyQuota: app.dailyQuota);
    expect(before.fresh.length, 20, reason: '额度 20 应放出 20 个新词');

    await app.setQuota(0);
    final after = await db.buildSessionQueue(dailyQuota: app.dailyQuota);
    expect(after.fresh, isEmpty, reason: '额度 0 不放新词');
    expect(after.due, isEmpty, reason: '额度 0 也不放复习');
    expect(after.pool, 30, reason: '库里确实还有生词，只是额度不放');

    expect(app.queueRevision, greaterThan(0));

    await db.close();
  });

  test('学习步骤：困难/模糊 的卡必须回队，认识的不回', () {

    final fresh = Fsrs.apply(null, Fsrs.ratingKnow);

    final forgetNew = Fsrs.apply(null, Fsrs.ratingForget);
    expect(forgetNew.state, FsrsState.learning);
    expect(StudyScreen.needsRequeue(forgetNew), isTrue,
        reason: '困难的卡必须回来，否则「困难」没有任何效果');

    final fuzzyNew = Fsrs.apply(null, Fsrs.ratingFuzzy);
    expect(fuzzyNew.state, FsrsState.learning);
    expect(StudyScreen.needsRequeue(fuzzyNew), isTrue);

    expect(fresh.state, FsrsState.review);
    expect(StudyScreen.needsRequeue(fresh), isFalse, reason: '认识的卡本次会话就该过关');

    final lapsed = Fsrs.apply(fresh, Fsrs.ratingForget);
    expect(lapsed.state, FsrsState.relearning);
    expect(StudyScreen.needsRequeue(lapsed), isTrue);

    final ok = Fsrs.apply(fresh, Fsrs.ratingKnow);
    expect(ok.state, FsrsState.review);
    expect(StudyScreen.needsRequeue(ok), isFalse);
  });

  test('音频扩展名互转：格式迁移后老版本还有声音', () {

    expect(AudioService.swapAudioExt('edge/ardi/id-makan.mp3'),
        'edge/ardi/id-makan.ogg');
    expect(AudioService.swapAudioExt('edge/ardi/id-makan.ogg'),
        'edge/ardi/id-makan.mp3');
    expect(AudioService.swapAudioExt('edge/ardi/id-makan.MP3'),
        'edge/ardi/id-makan.ogg',
        reason: '大小写不敏感');

    expect(AudioService.swapAudioExt('wiktionary/LL-x.wav'), isNull);
    expect(AudioService.swapAudioExt(''), isNull);
  });

  test('记忆强度：按 FSRS 稳定天数推，不发明新评分', () async {

    expect(MemoryStrength.of(stability: null, reps: null).days, 0);
    expect(
        MemoryStrength.of(stability: null, reps: null).band, MemoryBand.none);
    expect(MemoryStrength.of(stability: 0, reps: 0).band, MemoryBand.none);

    expect(MemoryStrength.of(stability: 0.4, reps: 1).band, MemoryBand.fresh);

    expect(MemoryStrength.of(stability: 5, reps: 2).band, MemoryBand.fair);
    expect(MemoryStrength.of(stability: 7, reps: 4).band, MemoryBand.good);
    expect(MemoryStrength.of(stability: 150, reps: 8).band, MemoryBand.solid);
    expect(
        MemoryStrength.of(stability: 400, reps: 20).band, MemoryBand.mastered);

    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'a',
        'word': 'a',
        'tier': 'core',
        'rank': 1,
        'zh': '甲',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'b',
        'word': 'b',
        'tier': 'core',
        'rank': 2,
        'zh': '乙',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'c',
        'word': 'c',
        'tier': 'core',
        'rank': 3,
        'zh': '丙',
        'enabled': 1,
        'favorite': 0
      },
    ]);
    await db.setDataVersion(kDataVersion);

    await db.saveSrs('a', Fsrs.apply(null, Fsrs.ratingKnow)..stability = 400);

    await db.saveSrs('b', Fsrs.apply(null, Fsrs.ratingFuzzy)..stability = 0.5);

    final lv = await db.srsLevels(['a', 'b', 'c']);
    expect(lv.length, 2, reason: 'c 没学过，不该出现在结果里');
    expect(
        MemoryStrength.of(stability: lv['a']!.stability, reps: lv['a']!.reps)
            .band,
        MemoryBand.mastered);
    expect(
        MemoryStrength.of(stability: lv['b']!.stability, reps: lv['b']!.reps)
            .band,
        MemoryBand.fresh);

    expect(await db.srsLevels([]), isEmpty);

    await db.close();
  });

  test('双向搜索：印尼语词形 / 中文 / 例句，且通配符被转义', () async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'tembok',
        'word': 'témbok',
        'tier': 'core',
        'rank': 1,
        'zh': '墙壁',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'makan',
        'word': 'makan',
        'tier': 'core',
        'rank': 2,
        'zh': '吃',
        'enabled': 1,
        'favorite': 0,
        'examples': 'i=Aku makan nasi.=我吃米饭。'
      },
      {
        'id': 'makanan',
        'word': 'makanan',
        'tier': 'core',
        'rank': 3,
        'zh': '食物',
        'enabled': 1,
        'favorite': 0
      },
      {
        'id': 'mati',
        'word': 'mati',
        'tier': 'core',
        'rank': 4,
        'zh': '死；熄灭',
        'enabled': 0,
        'favorite': 0
      },
    ]);
    await db.setDataVersion(kDataVersion);

    expect((await db.searchAll('tembok')).map((w) => w.id), contains('tembok'));
    expect((await db.searchAll('Témbok')).map((w) => w.id), contains('tembok'));

    final r = await db.searchAll('makan');
    expect(r.first.id, 'makan', reason: '主键精确匹配必须排第一');
    expect(r.map((w) => w.id), containsAll(['makan', 'makanan']));

    expect((await db.searchAll('墙壁')).map((w) => w.id), ['tembok']);
    expect((await db.searchAll('食物')).map((w) => w.id), ['makanan']);

    expect((await db.searchAll('nasi')).map((w) => w.id), ['makan']);

    expect((await db.searchAll('makan nasi')).map((w) => w.id), ['makan']);

    expect(await db.searchAll('mati'), isEmpty);

    expect(await db.searchAll('%'), isEmpty, reason: '% 是 LIKE 通配符，不转义会命中全库');
    expect(await db.searchAll('_'), isEmpty, reason: '_ 匹配任意单字');
    expect(await db.searchAll('a%b'), isEmpty);

    expect(await db.searchAll('   '), isEmpty);

    await db.close();
  });

  test('总体回忆率 / 中位稳定性：没数据时返回 null，不假装成满分', () async {
    final db = await seed(2);

    expect(await db.overallRecallRate(), isNull);
    expect(await db.medianStability(), isNull);

    await db.saveSrs('w1', Fsrs.apply(null, Fsrs.ratingKnow));
    await db.logRating('w1', Fsrs.ratingForget);
    expect(await db.overallRecallRate(), 0.0);
    expect(await db.medianStability(), isNotNull);
    expect(await db.medianStability(), greaterThan(0));

    await db.close();
  });

  test('学习目标是**优先**不是排他：本卡组打头，额度还有剩就带其它卡组', () async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'c1',
        'word': 'c1',
        'tier': 'core',
        'rank': 1,
        'zh': '甲',
        'enabled': 1,
        'favorite': 0,
        'topics': '餐饮食物'
      },
      {
        'id': 'c2',
        'word': 'c2',
        'tier': 'core',
        'rank': 2,
        'zh': '乙',
        'enabled': 1,
        'favorite': 0,
        'topics': '餐饮食物'
      },
      {
        'id': 't1',
        'word': 't1',
        'tier': 'core',
        'rank': 3,
        'zh': '丙',
        'enabled': 1,
        'favorite': 0,
        'topics': '交通出行'
      },
    ]);
    await db.setDataVersion(kDataVersion);

    await db.planWord(['c1', 'c2']);

    const food = {
      'topicsAny': ['餐饮食物']
    };
    final s = await db.buildSessionQueue(dailyQuota: 5, filter: food);
    expect(s.fresh.map((w) => w.id).toSet(), {'c1', 'c2'},
        reason: 't1 没加入记忆 → 任何范围的队列都取不到它（成员闸与卡组无关）');
    expect(s.pool, 2);

    expect((await db.buildSessionQueue(dailyQuota: 5)).pool, 2,
        reason: '「已加入记忆」这道闸与词库范围是**且**的关系');

    await db.planWord(['t1']);
    final s2 = await db.buildSessionQueue(dailyQuota: 5, filter: food);
    expect(s2.fresh.map((w) => w.id).toList(), ['c1', 'c2', 't1'],
        reason: '本卡组的 c1/c2 打头，剩下的额度接着发其它卡组的 t1');
    expect(s2.pool, 3, reason: '池子按**全库**算：它决定完成页说「全清完了」还是「还有生词没排上」');

    final s3 = await db.buildSessionQueue(dailyQuota: 2, filter: food);
    expect(s3.fresh.map((w) => w.id).toList(), ['c1', 'c2'],
        reason: '优先 = 本卡组先占额度');

    await db.close();
  });

  test('没加入记忆的卡不进队列；加入后出现；移出后消失', () async {
    final db = await seed(4, enroll: false);

    final empty = await db.buildSessionQueue(dailyQuota: 10);
    expect(empty.fresh, isEmpty, reason: '一个都没加入，队列必须是空的');
    expect(empty.pool, 0, reason: '池子也不能算上没加入的');
    expect(empty.due, isEmpty);

    await db.planWord(['w2', 'w3']);
    final q = await db.buildSessionQueue(dailyQuota: 10);
    expect(q.fresh.map((w) => w.id).toSet(), {'w2', 'w3'});
    expect(q.pool, 2);

    await db.unenroll(['w2']);
    final q2 = await db.buildSessionQueue(dailyQuota: 10);
    expect(q2.fresh.map((w) => w.id).toSet(), {'w3'});
    expect(q2.pool, 1);

    await db.planWord(['w1']);
    await learn(db, 'w1');
    await db.unplanWords(['w1']);
    expect(await db.getSrs('w1'), isNotNull);
    expect(await db.isPlanned('w1'), isFalse);
    expect(await db.bookProgress(null).then((p) => p.total), 2,
        reason: 'w1（有 srs）+ w3（有 plan）都算在记忆里，w2/w4 不算');

    await db.close();
  });

  test('额度用尽 / 再学一组 / 全部完成：三种停止态', () async {
    final db = await seed(4);
    for (final w in (await db.buildSessionQueue(dailyQuota: 2)).fresh) {
      await learn(db, w.id);
    }

    var plan = await db.todayPlan(dailyQuota: 2);
    expect(plan.finished, 2);
    expect(plan.poolLeft, 2, reason: '还有 2 个已加入未学的词，只是额度不给');
    expect(studyStopOf(plan), StudyStop.quotaOut,
        reason: '该显示「今日卡量已用完」，按钮是「修改卡量」');

    for (final w in (await db.buildSessionQueue(dailyQuota: 99)).fresh) {
      await learn(db, w.id);
    }
    plan = await db.todayPlan(dailyQuota: 2);
    expect(plan.poolLeft, 0);
    expect(studyStopOf(plan), StudyStop.nothingToLearn,
        reason: '该显示「今日任务已全部完成！」，按钮是「去词库选词」');

    final past = DateTime.now().subtract(const Duration(hours: 1));
    final w1 = (await db.getSrs('w1'))!..due = past;
    await db.saveSrs('w1', w1);
    final s = await db.buildSessionQueue(dailyQuota: 99);
    expect(s.due, hasLength(1), reason: '额度有余额时到期复习排得进来');
    plan = await db.todayPlan(dailyQuota: 99);

    expect(plan.newPending, 1, reason: '今天欠着一张（今天学过、又被弄成到期）');
    expect(studyStopOf(plan), StudyStop.moreGroup);

    await db.close();
  });

  test('studyStopOf 的边界：额度 0 与单组上限', () {

    TodayPlan p({
      int quota = 20,
      int newDone = 0,
      int reviewDone = 0,
      int newPending = 0,
      int reviewPending = 0,
      int reviewBacklog = 0,
      int poolLeft = 0,
    }) =>
        todayPlanOf(
            quota: quota,
            newDone: newDone,
            reviewDone: reviewDone,
            newPending: newPending,
            reviewPending: reviewPending,
            reviewBacklog: reviewBacklog,
            poolLeft: poolLeft);

    expect(studyStopOf(p(quota: 0, reviewBacklog: 99, poolLeft: 99)),
        StudyStop.zero);
    expect(studyStopOf(p(quota: 0, reviewDone: 30, reviewPending: 0)),
        StudyStop.zero,
        reason: '设 0 之后哪怕今天已经学过，也还是「今天不排卡」');
    expect(studyStopOf(p(quota: 9999, reviewBacklog: 600)), StudyStop.moreGroup,
        reason: '额度还剩 9499，只是这一组被 500 张夹住了');
    expect(studyStopOf(p(quota: 500, reviewDone: 500, reviewBacklog: 600)),
        StudyStop.quotaOut,
        reason: '额度真用完了才是 quotaOut');
    expect(studyStopOf(p(quota: 20, reviewDone: 20, newDone: 0)),
        StudyStop.nothingToLearn,
        reason: '额度用完但**没东西可排**：不该再催用户改额度');

    expect(studyStopOf(p(reviewPending: 5)), StudyStop.moreGroup,
        reason: '答了「困难」的卡还在 10 分钟步长里 —— 还欠着，不许说「过完了」');
    expect(studyStopOf(p(newPending: 3, newDone: 0)), StudyStop.moreGroup,
        reason: '今天新学、点了困难回队的卡同理（newPending）');
    expect(studyStopOf(p(reviewBacklog: 1)), StudyStop.moreGroup,
        reason: '今天之内到期的卡（哪怕此刻还没到点）也算欠账');
    expect(studyStopOf(p(poolLeft: 1, newDone: 0)), StudyStop.moreGroup,
        reason: '池子里还有已加入未学的词 —— 不是 nothingToLearn');
  });

  test('3000 张到期卡：id 队列顺序正确，分批取卡不炸 IN 参数上限', () async {
    final db = await seed(3000);
    final base = DateTime.now().subtract(const Duration(days: 2));
    for (var i = 1; i <= 3000; i++) {
      await learn(db, 'w$i');

      final s = (await db.getSrs('w$i'))!..due = base.add(Duration(seconds: i));
      await db.saveSrs('w$i', s);
    }

    final d = await db.db;
    await d.rawUpdate('UPDATE study_log SET ts = ?',
        [base.millisecondsSinceEpoch]);
    final q = await db.buildSessionQueueIds(dailyQuota: 9999);
    expect(q.due, hasLength(3000));
    expect(q.due.first, 'w1');
    expect(q.due.last, 'w3000');
    expect(q.fresh, isEmpty);

    final q50 = await db.buildSessionQueueIds(dailyQuota: 50);
    expect(q50.due, hasLength(50));
    expect(q50.due.first, 'w1');

    final win = await db.wordsByIds(q.due.sublist(100, 130));
    expect(win.map((c) => c.id).toList(), q.due.sublist(100, 130));

    expect(await db.wordsByIdsChunked(q.due), hasLength(3000));

    await db.close();
  });
}
