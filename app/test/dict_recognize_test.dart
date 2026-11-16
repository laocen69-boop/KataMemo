import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/dict_import/dict_flow.dart';
import 'package:katamemo/dict_import/dict_model.dart';
import 'package:katamemo/dict_import/dict_parse.dart';

void main() {
  group('分隔符嗅探', () {
    test('逗号 / 制表符 / 分号 / 竖线都能认出来', () {
      expect(sniffDelimiter('a,b\nc,d\n'), ',');
      expect(sniffDelimiter('a\tb\nc\td\n'), '\t');
      expect(sniffDelimiter('a;b\nc;d\n'), ';');
      expect(sniffDelimiter('a|b\nc|d\n'), '|');
    });

    test('引号里的逗号不算：分号文件里释义带逗号也认成分号', () {
      expect(sniffDelimiter('rumah;"房子, 家"\nmakan;"吃, 吃饭"\n'), ';');
    });

    test('单列文件用后缀给的兜底', () {
      expect(sniffDelimiter('rumah\nmakan\n', fallback: '\t'), '\t');
    });

    test('.txt 是可导入格式', () {
      expect(detectDictFormat('我的笔记.TXT'), DictFormat.txt);
    });
  });

  test('JSON 带 UTF-8 BOM 也能解析', () {
    final s = '${String.fromCharCode(0xFEFF)}[{"word":"rumah"}]';
    expect(parseJsonRecords(s).single['word'], 'rumah');
  });

  group('有没有表头', () {
    test('第一行是常见列名 → 有表头', () {
      expect(guessHasHeader([['word', 'meaning'], ['rumah', '房子']]), isTrue);
    });

    test('列名不常见，但类型和数据不同（Arti 是拉丁字母、数据是汉字）→ 有表头', () {
      expect(guessHasHeader([['Kata', 'Arti'], ['rumah', '房子'], ['makan', '吃']]), isTrue);
    });

    test('第一行和下面的数据长得一样 → 没有表头', () {
      expect(guessHasHeader([['rumah', '房子'], ['makan', '吃'], ['pergi', '去']]), isFalse);
    });

    test('没有表头时列名叫「第1列」「第2列」，第一行也算数据', () {
      final recs = delimitedToRecords([['rumah', '房子'], ['makan', '吃']], hasHeader: false);
      expect(recs.length, 2);
      expect(recs.first['第1列'], 'rumah');
      expect(recs.first['第2列'], '房子');
    });
  });

  group('按内容猜映射', () {
    final headers = ['A', 'B', 'C', 'D', 'E'];
    final records = [
      for (final r in [
        ['rumah', 'n', '房子；家', 'Saya pulang ke rumah sekarang.', '我现在回家。'],
        ['makan', 'v', '吃', 'Kami makan nasi setiap hari.', '我们每天吃米饭。'],
        ['besar', 'adj', '大', 'Rumah itu sangat besar sekali.', '那所房子非常大。'],
      ])
        {for (var i = 0; i < headers.length; i++) headers[i]: r[i]},
    ];

    test('词头 / 词性 / 释义 / 例句 / 译文 各归各位', () {
      final m = guessDictMappingFromContent(headers, records);
      expect(m[ImportField.lemma], 'A');
      expect(m[ImportField.pos], 'B');
      expect(m[ImportField.definition], 'C', reason: '汉字列里平均最短的是释义');
      expect(m[ImportField.example], 'D');
      expect(m[ImportField.translation], 'E');
    });

    test('列名已经猜到的字段不被覆盖', () {
      final m = guessDictMappingFromContent(headers, records,
          known: {ImportField.lemma: 'D'});
      expect(m[ImportField.lemma], 'D');
      expect(m.values.where((h) => h == 'D').length, 1, reason: '同一列不会给两个字段');
    });
  });

  group('两趟导入', () {
    const opt = DictImportOptions();
    const text = 'rumah;n;房子\nmakan;v;吃\npergi;v;去\n';

    test('没有表头、分号分隔：预判全对', () {
      final p = buildDictPreview(DictFormat.csv, text, opt);
      expect(p.delimiter, ';');
      expect(p.hasHeaderGuess, isFalse);
      expect(p.count(false), 3);
      final m = p.mapping(false);
      expect(m[ImportField.lemma], '第1列');
      expect(m[ImportField.pos], '第2列');
      expect(m[ImportField.definition], '第3列');
      expect(p.samples(false)['第1列'], ['rumah', 'makan']);
    });

    test('按预判的映射导入，3 条一条不少', () {
      final p = buildDictPreview(DictFormat.csv, text, opt);
      final res = importDictText(DictFormat.csv, text, false, p.mapping(false), opt);
      expect(res.entries.map((e) => e.lemma), ['rumah', 'makan', 'pergi']);
      expect(res.entries.first.senses.single.definition, '房子');
      expect(res.entries.first.senses.single.pos, 'n');
    });
  });

  group('2026-11-08 实证修复（真机 kbbi_v6.json 导入 194,656 条空壳）', () {
    const opt = DictImportOptions();

    test('稀疏列不能靠「只数非空」的满分反超正文列', () {

      final records = [
        for (var i = 0; i < 30; i++)
          {
            'kata': ['rumah', 'makan', 'besar', 'pergi', 'lihat', 'duduk'][i % 6],
            'sparse': i < 3 ? 'word' : null,
          }
      ];
      final m = guessDictMappingFromContent(['kata', 'sparse'], records);
      expect(m[ImportField.lemma], 'kata');
    });

    test('JSON 数组值压平：样例不再显示成「[...]」、发音猜测不再被「[...]」误中', () {

      const text = '[{"lema":["3M"],"makna":["[n] kp pakai masker"],'
          '"pelafalan":["enem es"]}]';
      final p = buildDictPreview(DictFormat.json, text, opt);
      expect(p.samplesWith['lema'], ['3M']);
      expect(p.mappingWith[ImportField.pronunciation], 'pelafalan',
          reason: 'pelafalan 走列名同义词命中（数组压平后 lema 不再误中括号正则）');
      expect(p.mappingWith[ImportField.lemma], 'lema');
    });

    test('KBBI 风格 JSON（lema/makna/contoh/pelafalan）自动映射全对', () {
      const text = '''
[
  {"lema":["3M"],"makna":["[n] kp pakai masker, cuci tangan, jaga jarak"]},
  {"lema":["à la carte"],"makna":["ukp <Pr> sesuai menu (harga dihitung terpisah)"],
   "contoh":["makan à la carte"],"pelafalan":["a la kart"]},
  {"lema":["a"],"makna":["huruf pertama abjad"]}
]''';
      final p = buildDictPreview(DictFormat.json, text, opt);
      expect(p.mappingWith[ImportField.lemma], 'lema');
      expect(p.mappingWith[ImportField.definition], 'makna');
      expect(p.mappingWith[ImportField.example], 'contoh',
          reason: '释义列同义词命中后，例句才从剩下的长句列里选');
      expect(p.mappingWith[ImportField.pronunciation], 'pelafalan');
      final res =
          importDictText(DictFormat.json, text, true, p.mappingWith, opt);
      final e = res.entries.singleWhere((x) => x.lemma == 'à la carte');
      expect(e.senses.single.definition,
          'ukp <Pr> sesuai menu (harga dihitung terpisah)');
      expect(e.senses.single.examples.single.text, 'makan à la carte');
      expect(e.pronunciation, 'a la kart');
    });

    test('纯印尼语文件（整份没有一个汉字）：最长的长句列当释义', () {

      const text = 'rumah;n;bangunan tempat tinggal manusia dan keluarganya;Saya pulang ke rumah sekarang.\n'
          'makan;v;memasukkan makanan ke dalam mulut;Kami makan nasi setiap hari.\n';
      final p = buildDictPreview(DictFormat.csv, text, opt);
      expect(p.hasHeaderGuess, isFalse);
      final m = p.mapping(false);
      expect(m[ImportField.definition], '第3列');
      expect(m[ImportField.example], '第4列');
    });
  });
}
