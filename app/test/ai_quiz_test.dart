import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/ai_quiz.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/ai_quiz_card.dart';

void main() {
  group('parseAiChatSegments', () {
    test('解析标准单题与前后 Markdown 混排', () {
      const raw = '''
先做一道小练习：

:::quiz
{"question":"“我吃过饭了”最自然的印尼语是？","options":["Saya makan sudah","Saya sudah makan","Saya bukan makan"],"answer":1,"explanation":"体标记 sudah 放在动词前。","word_id":"sudah"}
:::

做完告诉我！
''';
      final segs = parseAiChatSegments(raw);
      expect(segs.length, 3);
      expect(segs[0], isA<AiTextSegment>());
      expect(segs[1], isA<AiQuizSegment>());
      expect(segs[2], isA<AiTextSegment>());

      final q = (segs[1] as AiQuizSegment).items.single;
      expect(q.answerIndex, 1);
      expect(q.options.length, 3);
      expect(q.wordId, 'sudah');
      expect(q.explanation, contains('sudah'));
    });

    test('支持字母答案 A/B/C/D 与多题数组', () {
      const raw = '''
:::quiz
[
  {"question":"Q1","options":["opt1","opt2"],"answer":"B","explanation":"ok"},
  {"question":"Q2","options":["a","b","c"],"answer":"A"}
]
:::
''';
      final segs = parseAiChatSegments(raw);
      expect(segs.length, 1);
      final items = (segs.single as AiQuizSegment).items;
      expect(items.length, 2);
      expect(items[0].answerIndex, 1);
      expect(items[1].answerIndex, 0);
    });

    test('流式未闭合、损坏 JSON、越界索引一律无损回退普通文本', () {
      const streaming = '先看题：\n:::quiz\n{"question":"Q1"';
      final s1 = parseAiChatSegments(streaming);
      expect(s1.length, 1);
      expect((s1.single as AiTextSegment).markdown, streaming);

      const badJson = ':::quiz\n{not valid json}\n:::';
      final s2 = parseAiChatSegments(badJson);
      expect(s2.single, isA<AiTextSegment>());

      const badIdx = ':::quiz\n{"question":"Q","options":["a","b"],"answer":5}\n:::';
      final s3 = parseAiChatSegments(badIdx);
      expect(s3.single, isA<AiTextSegment>());
    });
  });

  group('AiQuizCard', () {
    testWidgets('点击选项后即时判对错、显示解析并触发加词回调', (tester) async {
      String? added;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [KColors.light]),
          home: Scaffold(
            body: AiQuizCard(
              items: const [
                AiQuizItem(
                  question: '选出正确用法',
                  options: ['tidak buku', 'bukan buku'],
                  answerIndex: 1,
                  explanation: '否定名词用 bukan。',
                  wordId: 'bukan',
                ),
              ],
              onAddWord: (id) => added = id,
            ),
          ),
        ),
      );

      expect(find.text('选出正确用法'), findsOneWidget);
      expect(find.text('否定名词用 bukan。'), findsNothing);

      await tester.tap(find.text('bukan buku'));
      await tester.pump();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('否定名词用 bukan。'), findsOneWidget);
      expect(find.text('+ 把 bukan 加入记忆'), findsOneWidget);

      await tester.tap(find.text('+ 把 bukan 加入记忆'));
      await tester.pump();

      expect(added, 'bukan');
      expect(find.text('已加入记忆'), findsOneWidget);
    });
  });
}
