import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/dict_import/dict_flow.dart';
import 'package:katamemo/dict_import/dict_model.dart';
import 'package:katamemo/dict_import/dict_parse.dart';

void main() {
  const opt = DictImportOptions();

  test('按格式读取 CSV / TSV / JSON', () {
    final csv = readDictRecords(DictFormat.csv, '词,释义\ntesalfa,义甲\n', opt);
    expect(csv.single['释义'], '义甲');

    final tsv = readDictRecords(DictFormat.tsv, '词\t释义\ntesbeta\t义乙\n', opt);
    expect(tsv.single['词'], 'tesbeta');

    final json = readDictRecords(DictFormat.json, '[{"word":"tesgamma","def":"义丙"}]', opt);
    expect(json.single['def'], '义丙');
  });

  test('格式与内容不符时抛 FormatException', () {
    expect(() => readDictRecords(DictFormat.json, '"坏"', opt), throwsA(isA<FormatException>()));
    expect(() => readDictRecords(DictFormat.csv, 'a,"b\n', opt), throwsA(isA<FormatException>()));
  });

  test('dictHeaders 按首次出现顺序列出所有列名', () {
    final h = dictHeaders([
      {'a': '1', 'b': '2'},
      {'b': '3', 'c': '4'},
    ]);
    expect(h, ['a', 'b', 'c']);
  });

  group('默认映射猜测', () {
    test('中英文表头都能猜到对应字段', () {
      final m = guessDictMapping(['Word', '释义', '词性', '例句', '例句翻译', '音标']);
      expect(m[ImportField.lemma], 'Word');
      expect(m[ImportField.definition], '释义');
      expect(m[ImportField.pos], '词性');
      expect(m[ImportField.example], '例句');
      expect(m[ImportField.translation], '例句翻译');
      expect(m[ImportField.pronunciation], '音标');
    });

    test('猜不到的字段不出现（即默认不导入）', () {
      final m = guessDictMapping(['甲', '乙']);
      expect(m.containsKey(ImportField.lemma), isFalse);
      expect(m, isEmpty);
    });

    test('大小写和首尾空格不影响匹配', () {
      final m = guessDictMapping([' LEMMA ']);
      expect(m[ImportField.lemma], ' LEMMA ');
    });
  });

  group('显示用文件名', () {
    test('去掉原生层加的 pick_<时间戳>_ 前缀，保留原名', () {
      expect(dictDisplayName('/data/cache/pick_1700000000_words.csv'), 'words.csv');
    });

    test('没有前缀时原样返回文件名，路径分隔符两种都认', () {
      expect(dictDisplayName(r'C:\tmp\my list.json'), 'my list.json');
      expect(dictDisplayName('/a/b/plain.tsv'), 'plain.tsv');
    });

    test('格式识别不区分大小写', () {
      expect(detectDictFormat('X.TSV'), DictFormat.tsv);
      expect(dictFormatLabel(DictFormat.json), 'JSON');
    });
  });
}
