library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
    for (final ch in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  Future<AppState> seed(
      List<
              ({
                String id,
                String word,
                String zh,
                List<({String i, String? q})> ex
              })>
          cards) async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.upsertWords([
      for (final c in cards)
        {
          'id': c.id,
          'word': c.word,
          'tier': 't1',
          'rank': 10,
          'frequency': 10,
          'word_class': 'v',
          'zh': c.zh,
          'examples': WordCard.encodeMaps([
            for (final e in c.ex)
              {'i': e.i, 'z': '中文对照', if (e.q != null) 'q': e.q},
          ]),
          'enabled': 1,
          'favorite': 0,
        },
    ]);
    await db.setDataVersion(kDataVersion);
    await db.planWord([for (final c in cards) c.id]);
    final app = AppState(db);
    await app.init();
    await app.setAutoSpeak(false);
    await app.setStudyMode('zh2id');
    return app;
  }

  Future<void> pumpStudy(WidgetTester tester, AppState app) async {

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const StudyScreen(),
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.runAsync(() async {
      await tester.tap(f);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> typeAndSettle(WidgetTester tester, String s) async {
    await tester.enterText(find.byKey(const Key('spell-input')), s);
    await tester.pump();
  }

  String clozePlain(WidgetTester tester, String key) {
    final t =
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text));
    return tester.widget<Text>(t.first).textSpan!.toPlainText();
  }

  testWidgets('正面：提示框 + 题面中文 + 挖空例句；不出现答案与评分按钮', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'tulis',
            word: 'tulis',
            zh: '写；书写',
            ex: [(i: 'Dia menulis surat itu kemarin.', q: 'menulis')],
          )
        ])))!;
    await pumpStudy(tester, app);

    expect(find.text('先想想这个词怎么拼'), findsOneWidget);
    expect(find.text('一格一个字母'), findsOneWidget);
    expect(find.byKey(const Key('spell-input')), findsOneWidget,
        reason: '一屏作答：输入框就在正面');

    expect(find.textContaining('写；书写'), findsOneWidget);

    final plain = clozePlain(tester, 'cloze-0');
    expect(plain, contains('surat itu kemarin.'));
    expect(plain, isNot(contains('menulis')));

    for (final t in ['困难', '模糊', '认识', '记得']) {
      expect(find.text(t), findsNothing, reason: '拼写正面不该出现「$t」');
    }
    expect(find.byKey(const Key('spell-give-up')), findsOneWidget);

    expect(find.textContaining('写；书写'), findsOneWidget);
  });

  testWidgets('点提示/空白 → 翻到「原来的界面」：单词大字 + 三档评分', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'tulis',
            word: 'tulis',
            zh: '写；书写',
            ex: [(i: 'Dia menulis surat itu kemarin.', q: 'menulis')],
          )
        ])))!;
    await pumpStudy(tester, app);

    await tapAndSettle(tester, find.byKey(const ValueKey('cloze-0')));

    expect(find.text('tulis'), findsOneWidget);
    expect(find.textContaining('写；书写'), findsOneWidget);
    for (final t in ['认识', '模糊', '困难']) {
      expect(find.text(t), findsOneWidget, reason: '答案面要有「$t」让用户自己选');
    }
    expect(find.text('先想想这个词怎么拼'), findsNothing, reason: '翻面后提示框收回');
  });

  testWidgets('拼写正面：例句贴顶 + 点例句下方的空白也能翻面（283 回归）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(() => seed([
          (
            id: 'berhak',
            word: 'berhak',
            zh: '有权（的）；享有权利的',
            ex: [
              (
                i: 'Setiap warga negara berhak menerima pendidikan yang layak.',
                q: 'berhak'
              ),
            ],
          ),
        ])))!;
    await pumpStudy(tester, app);

    final headerBottom =
        tester.getBottomLeft(find.byKey(const Key('study.band'))).dy;
    final labelTop = tester.getTopLeft(find.text('例句')).dy;
    expect(labelTop - headerBottom, lessThan(60),
        reason: '例句区块被居中了：与表头底边相距 ${(labelTop - headerBottom).round()}px');

    final input = find.byKey(const Key('spell-input'));
    final verifyTop = tester.getTopLeft(input).dy;
    await tester.tapAt(Offset(tester.getCenter(input).dx, verifyTop - 30));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('先想想这个词怎么拼'), findsNothing,
        reason: '点空白处应当翻到答案面（核对拼写按钮上方那片白也是正面的一部分）');
    expect(find.text('认识'), findsOneWidget, reason: '翻面后三档评分出现');
    expect(verifyTop, greaterThan(0), reason: '（取过按钮位置，防 find 为空假过）');
  });

  testWidgets('答案面内容从顶部开始（内容少的卡也不居中）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = (await tester.runAsync(() => seed([
          (
            id: 'kecil',
            word: 'kecil',
            zh: '小的',
            ex: <({String i, String? q})>[]
          ),
        ])))!;
    await pumpStudy(tester, app);

    await tapAndSettle(tester, find.text('点一下，看答案'));
    expect(find.text('kecil'), findsOneWidget, reason: '答案面：单词大字');

    final headerBottom =
        tester.getBottomLeft(find.byKey(const Key('study.band'))).dy;

    final firstBlock = tester.getTopLeft(find.text('助记')).dy;
    expect(firstBlock - headerBottom, lessThan(80),
        reason: '答案面被居中了：首块与表头底边相距 ${(firstBlock - headerBottom).round()}px');
  });

  testWidgets('核对拼写：输对了 = 记得，直接进下一张', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'tulis',
            word: 'tulis',
            zh: '写；书写',
            ex: [(i: 'Dia menulis surat itu kemarin.', q: 'menulis')],
          ),
          (
            id: 'rumah',
            word: 'rumah',
            zh: '房子',
            ex: [(i: 'Rumah itu besar sekali.', q: 'Rumah')],
          ),
        ])))!;
    await pumpStudy(tester, app);

    expect(find.byKey(const Key('spell-input')), findsOneWidget);
    expect(find.textContaining('写；书写'), findsOneWidget);
    expect(find.text('tulis'), findsNothing, reason: '输入界面不能把答案亮出来');

    await typeAndSettle(tester, 'tulis');
    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));

    final h = (await tester.runAsync(() => app.db.cardHistory('tulis')))!;
    expect(h.logs, 1, reason: '答对要落一条作答记录');
    expect(h.days.single.rating, Fsrs.ratingKnow, reason: '对了就是记得');

    expect(find.text('先想想这个词怎么拼'), findsOneWidget);
    expect(find.textContaining('房子'), findsOneWidget);
  });

  testWidgets('核对拼写：输错了 = 困难，亮出正确答案，点「继续」走人', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'tulis',
            word: 'tulis',
            zh: '写；书写',
            ex: [(i: 'Dia menulis surat itu kemarin.', q: 'menulis')],
          ),
          (
            id: 'rumah',
            word: 'rumah',
            zh: '房子',
            ex: [(i: 'Rumah itu besar sekali.', q: 'Rumah')],
          ),
        ])))!;
    await pumpStudy(tester, app);

    await typeAndSettle(tester, 'tuliz');
    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));

    expect(find.textContaining('没拼对'), findsOneWidget);
    expect(clozePlain(tester, 'cloze-0'), contains('menulis'));
    final h0 = (await tester.runAsync(() => app.db.cardHistory('tulis')))!;
    expect(h0.logs, 0, reason: '揭晓时还没记分：先看清答案再走');

    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));
    final h = (await tester.runAsync(() => app.db.cardHistory('tulis')))!;
    expect(h.logs, 1);
    expect(h.days.single.rating, Fsrs.ratingForget, reason: '错了就是困难');
    expect(find.textContaining('房子'), findsOneWidget);
  });

  testWidgets('不会：原地揭晓，继续 = 困难', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'tulis',
            word: 'tulis',
            zh: '写；书写',
            ex: [(i: 'Dia menulis surat itu kemarin.', q: 'menulis')],
          )
        ])))!;
    await pumpStudy(tester, app);

    await tapAndSettle(tester, find.byKey(const Key('spell-give-up')));
    expect(find.textContaining('没拼对'), findsOneWidget);
    expect(clozePlain(tester, 'cloze-0'), contains('menulis'));
    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));
    final h = (await tester.runAsync(() => app.db.cardHistory('tulis')))!;
    expect(h.days.single.rating, Fsrs.ratingForget);
  });

  testWidgets('出不了题的卡（例句里没有这个词）退回原来的中-印尼界面', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'sepertinya',
            word: 'sepertinya',
            zh: '似乎',

            ex: [(i: 'Diperlakukan dengan cara yang aneh.', q: null)],
          )
        ])))!;
    await pumpStudy(tester, app);

    expect(find.text('先想想这个词怎么拼'), findsNothing);
    expect(find.text('点一下，看答案'), findsOneWidget, reason: '退回原来的中-印尼正面');
    expect(find.byKey(const Key('spell-input')), findsNothing,
        reason: '出不了题就别给输入行');
    expect(find.text('似乎'), findsOneWidget, reason: '正面照旧给中文大字');
    expect(find.text('sepertinya'), findsNothing, reason: '正面不能泄题');
  });

  testWidgets('例句里没有 q 的卡（用户手写的例句）也能出题', (tester) async {
    final app = (await tester.runAsync(() => seed([
          (
            id: 'rumah',
            word: 'rumah',
            zh: '房子',

            ex: [(i: 'Rumah itu besar sekali dan luas.', q: null)],
          )
        ])))!;
    await pumpStudy(tester, app);
    expect(find.text('先想想这个词怎么拼'), findsOneWidget);
    expect(clozePlain(tester, 'cloze-0'), contains('besar sekali'));
    expect(clozePlain(tester, 'cloze-0'), isNot(contains('Rumah')));
  });

  test('编辑保存的元数据合并：没动的行保住 q/s/p/d，动了行才丢（第四十四轮）', () {

    final old = [
      const WordExample(
          text: 'Rumah itu besar.', zh: '那房子很大。', src: 'ai', quiz: 'Rumah'),
      const WordExample(text: 'Dia jual rumah.', zh: null),
    ];

    final same = mergeExamples(old, [
      const WordExample(text: 'Rumah itu besar.', zh: '那房子很大。'),
      const WordExample(text: 'Dia jual rumah.', zh: null),
    ]);
    expect(same[0].quiz, 'Rumah');
    expect(same[0].src, 'ai');
    expect(examplesUnchanged(old, same), isTrue);

    final edited = mergeExamples(old, [
      const WordExample(text: 'Rumah itu sangat besar.', zh: '那房子很大。'),
      const WordExample(text: 'Dia jual rumah.', zh: null),
    ]);
    expect(examplesUnchanged(old, edited), isFalse);
    expect(edited[0].quiz, isNull, reason: '旧 q 对新文本是错位标记，必须丢');
    expect(edited[1].quiz, isNull);

    const dvo = [
      Derivation(form: 'makanan', gloss: '食物', pos: 'n', def: 'makanan'),
    ];
    final dvs = mergeDvs(dvo, const [Derivation(form: 'makanan', gloss: '食物')]);
    expect(dvs[0].pos, 'n');
    expect(dvs[0].def, 'makanan');
    final dve = mergeDvs(dvo, const [Derivation(form: 'memakan', gloss: '吃')]);
    expect(dve[0].pos, isNull);
    expect(dve[0].def, isNull);
  });

  testWidgets('中-印尼拼写答对、答错/不会、翻到背面均按 autoSpeak 播放音频', (tester) async {
    final played = <String?>[];
    AudioService.instance.debugOnPlayCard = played.add;
    addTearDown(() => AudioService.instance.debugOnPlayCard = null);

    final app = (await tester.runAsync(() async {
      final a = await seed([
        (
          id: 'tulis',
          word: 'tulis',
          zh: '写',
          ex: [(i: 'Dia menulis surat.', q: 'menulis')],
        ),
        (
          id: 'baca',
          word: 'baca',
          zh: '读',
          ex: [(i: 'Saya membaca buku.', q: 'membaca')],
        ),
        (
          id: 'sepertinya',
          word: 'sepertinya',
          zh: '似乎',
          ex: [(i: 'Diperlakukan dengan cara yang aneh.', q: null)],
        ),
      ]);
      await a.setAutoSpeak(true);
      return a;
    }))!;

    await pumpStudy(tester, app);

    await typeAndSettle(tester, 'menulis');
    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));
    expect(played, ['tulis']);

    played.clear();
    await typeAndSettle(tester, 'salah');
    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));
    expect(played, ['baca']);

    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));

    played.clear();
    expect(find.text('点一下，看答案'), findsOneWidget);
    await tapAndSettle(tester, find.text('点一下，看答案'));
    expect(played, ['sepertinya']);
  });

  testWidgets('中-印尼点「不会」揭晓答案时播放音频，关闭 autoSpeak 则不播', (tester) async {
    final played = <String?>[];
    AudioService.instance.debugOnPlayCard = played.add;
    addTearDown(() => AudioService.instance.debugOnPlayCard = null);

    final app = (await tester.runAsync(() async {
      final a = await seed([
        (
          id: 'tulis',
          word: 'tulis',
          zh: '写',
          ex: [(i: 'Dia menulis surat.', q: 'menulis')],
        ),
        (
          id: 'baca',
          word: 'baca',
          zh: '读',
          ex: [(i: 'Saya membaca buku.', q: 'membaca')],
        ),
      ]);
      await a.setAutoSpeak(true);
      return a;
    }))!;

    await pumpStudy(tester, app);
    await tapAndSettle(tester, find.byKey(const Key('spell-give-up')));
    expect(played, ['tulis']);

    await tapAndSettle(tester, find.byKey(const Key('spell-verify')));
    played.clear();
    await tester.runAsync(() => app.setAutoSpeak(false));
    await tapAndSettle(tester, find.byKey(const Key('spell-give-up')));
    expect(played, isEmpty);
  });
}
