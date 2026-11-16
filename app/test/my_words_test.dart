import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> seed() async {
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
    return db;
  }

  test('新建 → 能列出 / 能被搜到；重复时返回已有那张、不写库', () async {
    final db = await seed();
    final r1 =
        await db.createUserWord(word: 'rumah sakit', zh: '医院', wordClass: 'n');
    expect(r1.id, 'rumah sakit', reason: '主键 = 折叠形（去空格小写）');
    expect(r1.existed, isNull, reason: '第一次建不该判重复');

    final list = await db.userWords();
    expect(list, hasLength(1));
    expect(list.single.word, 'rumah sakit');
    expect(list.single.userWord, isTrue, reason: '自建标记必须落库');
    expect(list.single.zhClean, '医院');

    final r2 = await db.createUserWord(word: 'Makan', zh: '吃');
    expect(r2.id, isNull);
    expect(r2.existed?.id, 'makan', reason: '折叠后撞上内置词，要把那张卡给出来');

    expect(await db.countUserWords(), 1);

    final r3 = await db.createUserWord(word: 'Rumah Sakit', zh: '医院');
    expect(r3.existed?.id, 'rumah sakit');
    expect(await db.countUserWords(), 1);

    expect((await db.searchWords('rumah sakit'))?.id, 'rumah sakit');
    await db.close();
  });

  test('能进学习队列、占额度（它就是 words 表普通的一行）', () async {
    final db = await seed();
    await db.createUserWord(word: 'rumah sakit', zh: '医院');
    await db.planWord(['rumah sakit']);

    final q = await db.buildSessionQueue(dailyQuota: 20);
    final ids = [
      for (final c in [...q.due, ...q.fresh]) c.id
    ];
    expect(ids, contains('rumah sakit'),
        reason: '自建词必须能被排进学习队列（用户点名「正常加入记忆学习」）');

    final plan = await db.todayPlan(dailyQuota: 20);
    expect(plan.newPlan, greaterThanOrEqualTo(1));
    await db.close();
  });

  test('词库重导（clearWords）**不清自建词**', () async {
    final db = await seed();
    await db.createUserWord(word: 'rumah sakit', zh: '医院');
    await db.createUserWord(word: 'kantor pos', zh: '邮局');

    await db.clearWords();

    final ids = [for (final w in await db.userWords()) w.id];
    expect(ids, containsAll(['rumah sakit', 'kantor pos']),
        reason: '自建词是用户资产，重导绝不能冲掉（这条就是本功能的底线）');
    expect((await db.getWord('makan')), isNull, reason: '内置词照常被清');
    await db.close();
  });

  test('编辑改词形会换主键，plan/srs 一起搬；删词连进度一起清', () async {
    final db = await seed();
    final r = await db.createUserWord(word: 'rumah sakit', zh: '医院');
    final id = r.id!;
    await db.planWord([id]);
    expect(await db.isPlanned(id), isTrue);

    final up =
        await db.updateUserWord(id, word: 'rumah sakit besar', zh: '大医院');
    expect(up.id, 'rumah sakit besar');
    expect(await db.isPlanned('rumah sakit besar'), isTrue,
        reason: '改个拼写不能把加入记忆弄丢');
    expect((await db.searchWords('rumah sakit')), isNull, reason: '旧主键不能再查到');

    await db.deleteUserWord('rumah sakit besar');
    expect((await db.userWords()), isEmpty);
    expect(await db.isPlanned('rumah sakit besar'), isFalse);
    await db.close();
  });

  test('草稿链路：先建再改同一张卡，不会建出两条', () async {
    final db = await seed();

    final d = await db.createUserWord(word: 'kantor pos', zh: '邮局');
    expect(d.id, 'kantor pos');
    expect(d.existed, isNull);
    expect(await db.countUserWords(), 1);

    final up = await db.updateUserWord(d.id!,
        word: 'kantor pos',
        zh: '邮局',
        wordClass: 'n',
        examples: const [(i: 'Saya ke kantor pos.', z: '我去邮局。')]);
    expect(up.existed, isNull);
    expect(await db.countUserWords(), 1, reason: '还是那一条，不能变两条');

    final card = await db.getWord('kantor pos');
    expect(card!.wordClass, 'n');
    expect(card.examples.single.text, 'Saya ke kantor pos.');

    final again = await db.createUserWord(word: 'kantor pos', zh: '邮局');
    expect(again.existed?.id, 'kantor pos',
        reason: '草稿已经在库里了 ⇒ 再 create 一定撞车，所以保存必须走 update');
    await db.close();
  });
}
