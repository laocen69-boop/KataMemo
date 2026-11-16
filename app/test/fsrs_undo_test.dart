library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/fsrs_personalize.dart';

void main() {

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppState> boot() async {
    final db = AppDb(dbPath: inMemoryDatabasePath);

    await db.upsertWords([
      {
        'id': 'makan',
        'word': 'makan',
        'tier': 'core',
        'rank': 10,
        'enabled': 1,
      },
    ]);
    await db.setDataVersion(kDataVersion);
    final app = AppState(db);
    await app.init();
    return app;
  }

  List<double> tweaked([double delta = 0.01]) =>
      [FsrsPersonalize.defaultW[0] + delta, ...FsrsPersonalize.defaultW.skip(1)];

  test('应用默认之外的参数会快照「应用前=官方默认」，回退后快照清空', () async {
    final app = await boot();
    final w = tweaked();
    expect(FsrsPersonalize.validateWeights(w), isNull);

    await app.applyFsrsWeights(w);
    expect(app.fsrsPersonalized, isTrue);
    expect(Fsrs.W.first, closeTo(w.first, 1e-9));
    expect(await app.db.metaGet('fsrs_w_prev'), '',
        reason: '应用前用的是官方默认 → 快照是空串，不是空值');

    expect(await app.undoFsrsWeights(), isTrue);
    expect(app.fsrsPersonalized, isFalse);
    expect(Fsrs.W.first, closeTo(FsrsPersonalize.defaultW.first, 1e-9));
    expect(await app.fsrsHasUndo(), isFalse, reason: '一级回退，回退后快照即清空');
    expect(await app.undoFsrsWeights(), isFalse);

    await app.db.close();
  });

  test('连续应用两次：回退只回到上一次，不会无限撤销', () async {
    final app = await boot();
    final w1 = tweaked(0.01);
    final w2 = tweaked(0.02);

    await app.applyFsrsWeights(w1);
    await app.applyFsrsWeights(w2);
    expect(await app.undoFsrsWeights(), isTrue);
    expect(Fsrs.W.first, closeTo(w1.first, 1e-9),
        reason: '快照是第二次应用之前的那组参数');
    expect(await app.undoFsrsWeights(), isFalse);
    expect(Fsrs.W.first, closeTo(w1.first, 1e-9), reason: '拒绝回退时参数不动');

    await app.db.close();
  });

  test('坏快照会被清掉（否则回退入口永远点不动）', () async {
    final app = await boot();
    await app.db.metaSet('fsrs_w_prev', '这不是参数');
    expect(await app.fsrsHasUndo(), isTrue);

    expect(await app.undoFsrsWeights(), isFalse);
    expect(await app.db.metaGet('fsrs_w_prev'), isNull,
        reason: '校验失败要把坏键删掉，界面下一轮刷新就不再显示回退行');
    expect(await app.fsrsHasUndo(), isFalse);

    await app.db.close();
  });

  test('恢复官方默认会清掉回退快照', () async {
    final app = await boot();
    await app.applyFsrsWeights(tweaked());
    expect(await app.fsrsHasUndo(), isTrue);

    await app.resetFsrsWeights();
    expect(app.fsrsPersonalized, isFalse);
    expect(await app.fsrsHasUndo(), isFalse,
        reason: '恢复默认是主动收口，不该还能被「回退」拽回个性化参数');

    await app.db.close();
  });
}
