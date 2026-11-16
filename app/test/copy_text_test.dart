import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/grammar/grammar_copy.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/widgets/copy_text.dart';
import 'package:katamemo/widgets/word_copy.dart';

void main() {
  testWidgets('copyText 写入剪贴板并提示', (tester) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => copyText(ctx, 'halo'),
            child: const Text('copy'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, 'halo');
    expect(find.text('已复制'), findsOneWidget);
  });

  test('单词复制文本：详情带例句、速览精简，最多 3 条例句', () {
    final card = WordCard(
      id: 'besar',
      word: 'besar',
      phonetic: '/bə·sar/',
      wordClass: 'a',
      zh: '大；高大粗壮',
      examples: const [
        WordExample(
            text: 'Ukurannya terlalu besar untuk saya.', zh: '这个码对我来说太大了。'),
        WordExample(text: 'Rumah itu sangat besar.', zh: '那栋房子很大。'),
        WordExample(text: 'Dia punya besar hati.', zh: '他心胸宽广。'),
        WordExample(text: 'Ini besar sekali.', zh: '这个非常大。'),
      ],
    );

    expect(
      wordCopyText(card, withExamples: true),
      'besar  /bə·sar/\n'
      '形容词 · 大；高大粗壮\n'
      '\n'
      '例句：\n'
      '1. Ukurannya terlalu besar untuk saya.\n'
      '   这个码对我来说太大了。\n'
      '2. Rumah itu sangat besar.\n'
      '   那栋房子很大。\n'
      '3. Dia punya besar hati.\n'
      '   他心胸宽广。',
    );

    expect(wordCopyText(card), 'besar  /bə·sar/\n形容词 · 大；高大粗壮');
  });

  test('单词复制文本：缺音标/释义时不留空行', () {
    final card = WordCard(id: 'halo', word: 'halo');
    expect(wordCopyText(card), 'halo');
  });

  test('语法页纯文本保留标题/结论/小标题/例句/表格/对照，去掉 ** 标记', () {
    const page = GPage(
      id: 'p-test',
      title: '标题',
      titleId: 'judul',
      summary: '一句话',
      blocks: [
        GLeadBlock('结论**正文**'),
        GHeadingBlock('第一节'),
        GExBlock([
          GEx(i: 'Saya **makan**.', z: '我吃。'),
          GEx(i: 'Dia makan nasi.', z: '他吃饭。'),
        ]),
        GTableBlock(cols: ['形式', '用法'], rows: [
          ['-kan', '使动　致使']
        ]),
        GVsBlock(
          a: GVsSide(title: 'A 边', text: '甲'),
          b: GVsSide(title: 'B 边', text: '乙'),
        ),
      ],
    );
    final text = grammarPagePlainText(page);
    expect(text, contains('标题\njudul'));
    expect(text, contains('一句话'));
    expect(text, contains('【结论】\n结论正文'));
    expect(text, contains('【第一节】'));
    expect(text,
        contains('1. Saya makan.\n   我吃。\n2. Dia makan nasi.\n   他吃饭。'));
    expect(text, contains('形式 | 用法\n-kan | 使动 / 致使'));
    expect(text, contains('▸ A 边\n甲'));
    expect(text, contains('▸ B 边\n乙'));
    expect(text, isNot(contains('**')));

    expect(text, isNot(contains('\n\n\n')));
  });
}
