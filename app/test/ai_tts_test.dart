import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/ai_chat.dart' show AiSpeechConfig;
import 'package:katamemo/ai_tts.dart';

void main() {
  group('extractIndonesianForTts', () {
    test('提取混合中印讲解里的印尼语句并剥离中文注记', () {
      const raw = '''
### 例句讲解
1. **Saya sudah makan nasi goreng.**（我已经吃了炒饭。）
2. Kamu mau pergi ke mana? — 你要去哪里？
3. 这句只是纯中文解释，不要读出来。
- Lihat [kamus](https://example.com/kbbi) untuk arti lengkap.
''';
      final out = extractIndonesianForTts(raw);
      expect(out, contains('Saya sudah makan nasi goreng.'));
      expect(out, contains('Kamu mau pergi ke mana?'));
      expect(out, contains('Lihat kamus untuk arti lengkap.'));
      expect(out, isNot(contains('炒饭')));
      expect(out, isNot(contains('纯中文解释')));
      expect(out, isNot(contains('https://')));
    });

    test('剥离代码块、quiz 块和 Markdown 表格分隔线', () {
      const raw = '''
```dart
print("hello code");
```
:::quiz
{"question":"Arti makan?","options":["吃","喝"],"answer":0}
:::
| 原句 | 改后 |
|---|---|
| Saya makan | Saya sudah makan |
Terima kasih banyak!
''';
      final out = extractIndonesianForTts(raw);
      expect(out, isNot(contains('hello code')));
      expect(out, isNot(contains('Arti makan')));
      expect(out, contains('Terima kasih banyak!'));
    });

    test('纯中文或空文本返回空串', () {
      expect(extractIndonesianForTts(''), '');
      expect(extractIndonesianForTts('   \n  '), '');
      expect(extractIndonesianForTts('这是一段完全只有中文的语法解释，没有任何印尼语词句。'), '');
    });

    test('复叠词（kata ulang）词内连字符不被误切，且自动剔除带 * 的错误词形示例', () {
      const raw = '''
- Anak-anak bermain di halaman. — 孩子们在院子里玩。
- Hati-hati di jalan: 路上小心
- 注意：不要写 *merubah 或 *mempengaruhi，规范写法是 **mengubah** dan **memengaruhi**.
''';
      final out = extractIndonesianForTts(raw);
      expect(out, contains('Anak-anak bermain di halaman.'));
      expect(out, contains('Hati-hati di jalan'));
      expect(out, contains('mengubah dan memengaruhi.'));
      expect(out, isNot(contains('merubah')));
      expect(out, isNot(contains('mempengaruhi')));
    });

    test('超长文本在词边界安全截断', () {
      final longText = List.filled(80, 'Saya belajar bahasa Indonesia setiap hari.').join(' ');
      final out = extractIndonesianForTts(longText, maxChars: 200);
      expect(out.length, lessThanOrEqualTo(200));
      expect(out, startsWith('Saya belajar'));
    });
  });

  group('resolveAiTtsUri & buildAiTtsPayload', () {
    test('HTTPS 与本地 localhost 地址校验与路径补全', () {
      expect(resolveAiTtsUri('https://api.openai.com/v1')?.toString(),
          'https://api.openai.com/v1/audio/speech');
      expect(resolveAiTtsUri('https://api.openai.com/v1/')?.toString(),
          'https://api.openai.com/v1/audio/speech');
      expect(resolveAiTtsUri('https://api.openai.com/v1/audio/speech')?.toString(),
          'https://api.openai.com/v1/audio/speech');
      expect(resolveAiTtsUri('http://127.0.0.1:8880/v1')?.toString(),
          'http://127.0.0.1:8880/v1/audio/speech');
      expect(resolveAiTtsUri('http://example.com/v1'), isNull);
      expect(resolveAiTtsUri(''), isNull);
    });

    test('构造请求体默认模型与语速钳制', () {
      const cfg = AiSpeechConfig(enabled: true, endpoint: 'https://x.test/v1');
      final p1 = buildAiTtsPayload(cfg, 'Halo', speed: 0.75);
      expect(p1['model'], 'tts-1');
      expect(p1['speed'], 0.75);
      expect(p1['input'], 'Halo');

      final p2 = buildAiTtsPayload(
        const AiSpeechConfig(enabled: true, endpoint: 'https://x.test/v1', model: 'gpt-4o-mini-tts'),
        'Selamat pagi',
        speed: 9.9,
      );
      expect(p2['model'], 'gpt-4o-mini-tts');
      expect(p2['speed'], 2.0);
    });
  });
}
