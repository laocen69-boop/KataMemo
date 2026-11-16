import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/dict_import/dict_kind.dart';
import 'package:katamemo/dict_import/dict_model.dart';

void main() {
  List<ImportEntry> kbbiShape(int n) => [
        for (var i = 0; i < n; i++)
          ImportEntry(
            lemma: i % 7 == 0 ? 'te.man ($i)' : 'pra.ju.rit$i',
            senses: [
              ImportSense(
                pos: 'n',
                definition: i % 3 == 0
                    ? 'n kata benda; contoh'
                    : '<i>v</i> melakukan sesuatu',
              ),
            ],
          ),
      ];

  List<ImportEntry> plainNotes(int n) => [
        for (var i = 0; i < n; i++)
          ImportEntry(
            lemma: 'kata$i',
            senses: [ImportSense(definition: '我自己写的义项 $i')],
          ),
      ];

  group('强信号', () {
    test('文件名写明 KBBI → 直接认，附带依据', () {
      final g = guessDictKind(
          name: 'kbbi_v6_wordlist.csv', sample: plainNotes(3));
      expect(g.kind, DictKind.kbbi);
      expect(g.confident, isTrue);
      expect(g.evidence.single, contains('文件名写明'));
    });

    test('文件名写 Kamus Besar Bahasa Indonesia 也算', () {
      final g = guessDictKind(
          name: 'Kamus Besar Bahasa Indonesia.txt', sample: plainNotes(3));
      expect(g.kind, DictKind.kbbi);
    });

    test('文件名带 kbbi 但内容只有十几条 → 仍按文件名认，但依据写明', () {
      final g = guessDictKind(name: '我的 KBBI 摘录.csv', sample: plainNotes(12));
      expect(g.kind, DictKind.kbbi);
    });
  });

  group('结构信号', () {
    test('分音节 + 同形编号 + 词性标记 → KBBI（文件名不含 kbbi 也认）', () {
      final g = guessDictKind(
          name: '词表(1).csv', sample: kbbiShape(200), totalEntries: 193833);
      expect(g.kind, DictKind.kbbi);
      expect(g.confident, isTrue);
      expect(g.evidence.length, greaterThanOrEqualTo(3));
      expect(g.evidence.join('\n'), contains('分音节点'));
      expect(g.evidence.join('\n'), contains('同形词编号'));
    });

    test('普通笔记表 → 其它词典，且判得很确定', () {
      final g = guessDictKind(
          name: '老师给的词表.csv', sample: plainNotes(200), totalEntries: 200);
      expect(g.kind, DictKind.other);
      expect(g.confident, isTrue);
      expect(g.evidence.join('\n'), contains('没有 KBBI 特征'));
    });

    test('只命中一条弱信号 → 不自动优先，并写明原因', () {

      final g = guessDictKind(
          name: '大词表.csv', sample: plainNotes(200), totalEntries: 50000);
      expect(g.kind, DictKind.other);
      expect(g.confident, isFalse);
      expect(g.evidence.join('\n'), contains('只命中一条弱信号'));
    });

    test('样本少于 30 条时结构信号不计，避免十几条笔记被误判', () {
      final g = guessDictKind(
          name: '随手记.csv', sample: kbbiShape(20), totalEntries: 20);
      expect(g.kind, DictKind.other);
    });
  });

  group('识别不改数据', () {
    test('词条对象与列表都没被改动', () {
      final sample = kbbiShape(50);
      final snapshot = sample
          .map((e) => '${e.lemma}|${e.senses.first.definition}')
          .toList();
      guessDictKind(name: 'x.csv', sample: sample, totalEntries: 50);
      expect(
        sample.map((e) => '${e.lemma}|${e.senses.first.definition}').toList(),
        snapshot,
      );
    });
  });

  group('改判结果', () {
    test('byUser 的序列化往返不变', () {
      const info = DictKindInfo(
          kind: DictKind.kbbi,
          byUser: true,
          evidence: ['学生手动指定为KBBI']);
      final back = DictKindInfo.fromMap(info.toMap());
      expect(back!.kind, DictKind.kbbi);
      expect(back.byUser, isTrue);
      expect(back.evidence, ['学生手动指定为KBBI']);
    });

    test('坏数据不炸，按空处理', () {
      expect(DictKindInfo.fromMap('oops'), isNull);
      expect(DictKindInfo.fromMap(null), isNull);
    });
  });
}
