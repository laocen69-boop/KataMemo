import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/dict_import/dict_map.dart';
import 'package:katamemo/dict_import/dict_model.dart';
import 'package:katamemo/dict_import/dict_parse.dart';

void main() {
  group('文件格式识别', () {
    test('按后缀识别 csv / tsv / json，其它返回 null', () {
      expect(detectDictFormat('a.CSV'), DictFormat.csv);
      expect(detectDictFormat('b.tsv'), DictFormat.tsv);
      expect(detectDictFormat('c.json'), DictFormat.json);
      expect(detectDictFormat('d.xlsx'), isNull);
      expect(detectDictFormat('e.db'), isNull);
    });
  });

  group('分隔文本解析', () {
    test('双引号内的逗号与换行不拆分，「""」还原为「"」', () {
      final rows = parseDelimited(
        'a,"b,c","say ""hi""",\n"x\ny",z,w\n',
        delimiter: ',',
      );
      expect(rows[0], ['a', 'b,c', 'say "hi"', '']);
      expect(rows[1], ['x\ny', 'z', 'w']);
    });

    test('去掉 UTF-8 BOM，CRLF 与 LF 等价', () {
      final rows = parseDelimited('﻿h1,h2\r\nv1,v2\n', delimiter: ',');
      expect(rows, [
        ['h1', 'h2'],
        ['v1', 'v2'],
      ]);
    });

    test('引号未闭合直接拒绝，不静默吞掉后文', () {
      expect(
        () => parseDelimited('a,"b\nc,d\n', delimiter: ','),
        throwsA(isA<FormatException>()),
      );
    });

    test('TSV 用制表符分隔', () {
      final rows = parseDelimited('a\tb\n1\t2\n', delimiter: '\t');
      expect(rows[1], ['1', '2']);
    });

    test('表头重复列名直接拒绝', () {
      final rows = parseDelimited('w,w\n1,2\n', delimiter: ',');
      expect(() => delimitedToRecords(rows), throwsA(isA<FormatException>()));
    });

    test('数据行列数不足时缺的列为空串；整行空白跳过', () {
      final rows = parseDelimited('w,d,e\ntesalfa,释义一\n\n', delimiter: ',');
      final recs = delimitedToRecords(rows);
      expect(recs.length, 1);
      expect(recs.first['e'], '');
      expect(recs.first['d'], '释义一');
    });
  });

  group('JSON 解析', () {
    test('接受对象数组，也接受带 entries 的对象', () {
      expect(parseJsonRecords('[{"w":"a"}]').length, 1);
      expect(parseJsonRecords('{"entries":[{"w":"a"},{"w":"b"}]}').length, 2);
    });

    test('顶层不是数组或 entries 也拒绝', () {
      expect(() => parseJsonRecords('"x"'), throwsA(isA<FormatException>()));
      expect(() => parseJsonRecords('{"foo":1}'), throwsA(isA<FormatException>()));
    });

    test('值里出现嵌套对象直接拒绝', () {
      expect(
        () => parseJsonRecords('[{"w":{"x":1}}]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('记录数不设上限（2026-11-06）', () {
    test('默认选项下 6 万条 CSV / JSON 都能读', () {
      final csv = StringBuffer('lemma,definition\n');
      for (var i = 0; i < 60000; i++) {
        csv.write('w$i,d$i\n');
      }
      const opt = DictImportOptions();
      expect(opt.maxRecords, isNull, reason: '默认不限条数');
      final fromCsv = delimitedToRecords(
          parseDelimited(csv.toString(), delimiter: ',', maxRows: opt.maxRecords));
      expect(fromCsv.length, 60000);
      final json = '[${List.generate(60000, (i) => '{"lemma":"w$i"}').join(',')}]';
      expect(parseJsonRecords(json, maxRecords: opt.maxRecords).length, 60000);
    });

    test('显式给了上限仍然生效（调用方想限时可以限）', () {
      expect(() => parseJsonRecords('[{"w":"a"},{"w":"b"}]', maxRecords: 1),
          throwsA(isA<FormatException>()));
      expect(() => parseDelimited('a\nb\nc\n', delimiter: ',', maxRows: 1),
          throwsA(isA<FormatException>()));
    });
  });

  group('字段映射：单个释义', () {
    test('一个释义 + 多条例句，全部挂在它名下', () {
      final recs = [
        {'词': 'tesalfa', '释义': '测试义项甲', '例句': '例句一|例句二'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.example: '例句',
      });
      expect(res.entries.length, 1);
      final s = res.entries.first.senses;
      expect(s.length, 1);
      expect(s.first.definition, '测试义项甲');
      expect(s.first.examples.map((e) => e.text), ['例句一', '例句二']);
      expect(res.issues, isEmpty);
    });
  });

  group('字段映射：多个释义的对应关系（防串读）', () {
    test('释义、词性、例句数量都相等时按位置一一对应', () {
      final recs = [
        {
          '词': 'tesbeta',
          '释义': '义甲|义乙',
          '词性': 'n|v',
          '例句': 'ex甲|ex乙',
        },
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.pos: '词性',
        ImportField.example: '例句',
      });
      final s = res.entries.first.senses;
      expect(s[0].pos, 'n');
      expect(s[0].examples.single.text, 'ex甲');
      expect(s[1].pos, 'v');
      expect(s[1].examples.single.text, 'ex乙');
      expect(res.issues, isEmpty);
    });

    test('多个释义但例句数量对不上：例句整格不导入，并给出警告，绝不猜归属', () {
      final recs = [
        {'词': 'tesbeta', '释义': '义甲|义乙', '例句': 'ex一|ex二|ex三'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.example: '例句',
      });
      final s = res.entries.first.senses;
      expect(s.every((x) => x.examples.isEmpty), isTrue);
      expect(res.issues.any((i) => i.warning && i.message.contains('例句数量')), isTrue);
    });

    test('词性数量对不上：词性整体忽略并警告', () {
      final recs = [
        {'词': 'tesbeta', '释义': '义甲|义乙', '词性': 'n|v|a'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.pos: '词性',
      });
      expect(res.entries.first.senses.every((x) => x.pos == null), isTrue);
      expect(res.issues.any((i) => i.message.contains('词性数量')), isTrue);
    });

    test('译文与例句数量一致时配对，不一致时整体忽略', () {
      final okRes = mapRecords([
        {'词': 'tesgamma', '释义': '义', '例句': 'a|b', '译文': '甲|乙'},
      ], {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.example: '例句',
        ImportField.translation: '译文',
      });
      final ex = okRes.entries.first.senses.first.examples;
      expect(ex[0].translation, '甲');
      expect(ex[1].translation, '乙');

      final badRes = mapRecords([
        {'词': 'tesgamma', '释义': '义', '例句': 'a|b', '译文': '只有一个'},
      ], {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
        ImportField.example: '例句',
        ImportField.translation: '译文',
      });
      expect(badRes.entries.first.senses.first.examples.every((e) => e.translation == null), isTrue);
      expect(badRes.issues.any((i) => i.message.contains('译文数量')), isTrue);
    });
  });

  group('词条合并与同形异义', () {
    test('同一词头多行、未映射同形序号：合并为一条并给出提示', () {
      final recs = [
        {'词': 'tesdelta', '释义': '甲义'},
        {'词': 'Tesdelta ', '释义': '乙义'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
      });
      expect(res.entries.length, 1);
      expect(res.entries.first.senses.map((s) => s.definition), ['甲义', '乙义']);
      expect(res.issues.any((i) => !i.warning && i.message.contains('合并')), isTrue);
    });

    test('映射了同形序号列：同一词头按序号分开', () {
      final recs = [
        {'词': 'tesdelta', '序号': '1', '释义': '甲义'},
        {'词': 'tesdelta', '序号': '2', '释义': '乙义'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.homograph: '序号',
        ImportField.definition: '释义',
      });
      expect(res.entries.length, 2);
      expect(res.entries.map((e) => e.homographIndex), [1, 2]);
    });

    test('同形序号无效时按 1 处理并提示', () {
      final recs = [
        {'词': 'tesdelta', '序号': '甲', '释义': '义'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.homograph: '序号',
        ImportField.definition: '释义',
      });
      expect(res.entries.first.homographIndex, 1);
      expect(res.issues.any((i) => i.message.contains('同形序号无效')), isTrue);
    });
  });

  group('防御性检查', () {
    test('词头为空的行跳过并提示，不影响其它行', () {
      final recs = [
        {'词': '', '释义': '无词头'},
        {'词': 'tesepsilon', '释义': '正常'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
      });
      expect(res.entries.map((e) => e.lemma), ['tesepsilon']);
      expect(res.issues.any((i) => i.row == 1 && i.message.contains('词头为空')), isTrue);
    });

    test('映射的列名在文件里不存在，直接报错，不静默导入空数据', () {
      expect(
        () => mapRecords([
          {'词': 'tesalfa', '释义': '义'},
        ], {
          ImportField.lemma: '词',
          ImportField.definition: '解释',
        }),
        throwsArgumentError,
      );
    });

    test('没有映射词头时报错', () {
      expect(
        () => mapRecords([
          {'词': 'tesalfa'},
        ], {ImportField.definition: '词'}),
        throwsArgumentError,
      );
    });

    test('释义超过上限时截断并提示', () {
      const opt = DictImportOptions(maxSensesPerEntry: 2);
      final recs = [
        {'词': 'tesalfa', '释义': 'a|b|c'},
      ];
      final res = mapRecords(recs, {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
      }, options: opt);
      expect(res.entries.first.senses.length, 2);
      expect(res.issues.any((i) => i.message.contains('超过')), isTrue);
    });

    test('超长词头跳过', () {
      const opt = DictImportOptions(maxLemmaLength: 5);
      final res = mapRecords([
        {'词': 'abcdefgh', '释义': '义'},
      ], {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
      }, options: opt);
      expect(res.entries, isEmpty);
    });

    test('释义列 = 词头列是无效映射，直接拒绝（2026-11-08）', () {

      expect(
        () => mapRecords([
          {'词': 'rumah', '释义': '房子'},
        ], {
          ImportField.lemma: '词',
          ImportField.definition: '词',
        }),
        throwsArgumentError,
      );
    });

    test('映射列校验看全部记录的键并集，JSON 键集不一致不再误判（2026-11-08）', () {

      final res = mapRecords([
        {'词': 'tesalfa'},
        {'词': 'tesbeta', '释义': '义'},
      ], {
        ImportField.lemma: '词',
        ImportField.definition: '释义',
      });
      expect(res.entries.single.lemma, 'tesbeta');

      expect(res.issues.any((i) => i.message.contains('没有可导入的释义')), isTrue);
    });

    test('没有释义/例句的词条不入库并提示（2026-11-08）', () {
      final res = mapRecords([
        {'词': 'tesalfa'},
      ], {ImportField.lemma: '词'});
      expect(res.entries, isEmpty);
      expect(res.issues.single.message, contains('没有可导入的释义或例句'));
    });
  });

  group('词条映照（只读对照）', () {

    List<String> fakeLookup(String folded) {
      if (folded == 'tesalfa') return ['id-a'];
      if (folded == 'tesbeta') return ['id-b1', 'id-b2'];
      return const [];
    }

    test('唯一匹配、多候选、无匹配三种状态', () {
      final entries = [
        const ImportEntry(lemma: 'TesAlfa'),
        const ImportEntry(lemma: 'tesbeta'),
        const ImportEntry(lemma: 'tesgamma'),
      ];
      final out = alignEntries(entries, fakeLookup);
      expect(out[0].status, AlignStatus.matched);
      expect(out[0].candidateIds, ['id-a']);
      expect(out[1].status, AlignStatus.ambiguous);
      expect(out[1].candidateIds.length, 2);
      expect(out[2].status, AlignStatus.unmatched);
      expect(out[2].candidateIds, isEmpty);
    });

    test('映照不修改输入词条', () {
      const e = ImportEntry(lemma: 'tesalfa', senses: [ImportSense(definition: '义')]);
      alignEntries([e], fakeLookup);
      expect(e.lemma, 'tesalfa');
      expect(e.senses.length, 1);
    });
  });

  group('规范化', () {
    test('dictFold 只用于比较：去空白、小写；dictTidy 保留大小写', () {
      expect(dictFold('  Tes   Alfa '), 'tes alfa');
      expect(dictTidy('  Tes   Alfa '), 'Tes Alfa');
    });
  });

  group('宽松检索键 fold_loose', () {
    test('去分音节点 / 连字符 / 间隔号 / 空白，大小写归一', () {
      expect(dictFoldLoose('te.man'), 'teman');
      expect(dictFoldLoose('Pra.ju.rit'), 'prajurit');
      expect(dictFoldLoose('a.pos.te.ri.o.ri'), 'aposteriori');
      expect(dictFoldLoose('A.di-Bud.dha'), 'adibuddha');
      expect(dictFoldLoose('  terima   kasih '), 'terimakasih');

      expect(dictFoldLoose('ma.kan (1)'), 'makan');
      expect(dictFoldLoose('A.bai (2)'), 'abai');

      expect(dictFoldLoose('api makan sekam (dedak)'), 'apimakansekam(dedak)');
    });

    test('保守口径：不去变音符号（é/ê 辨义），也不动撇号等其它字符', () {
      expect(dictFoldLoose('dêngar'), 'dêngar');
      expect(dictFoldLoose("ma'af"), "ma'af");
    });
  });
}
