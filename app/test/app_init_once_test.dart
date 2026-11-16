import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('init() 只执行一次：重复调用不再 notifyListeners（防构建-初始化死循环）',
      () async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      {
        'id': 'satu',
        'word': 'satu',
        'tier': 't1',
        'rank': 1,
        'zh': '一',
        'enabled': 1,
        'favorite': 0,
      },
    ]);

    await db.setDataVersion(kDataVersion);

    final app = AppState(db);
    var notified = 0;
    app.addListener(() => notified++);

    await app.init();
    expect(app.ready, isTrue);
    final afterFirst = notified;
    expect(afterFirst, greaterThan(0), reason: '第一次 init 完成时要通知界面就绪');

    for (var i = 0; i < 5; i++) {
      await app.init();
    }
    expect(notified, afterFirst,
        reason: '就绪之后再调 init() 不许再发通知，否则 watch 它的外层会无限重建');
    expect(identical(app.init(), app.init()), isTrue,
        reason: '重复调用复用同一个 Future（FutureBuilder 不会重置状态）');
    await db.close();
  });
}
