library;

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/ocr_scan.dart';

OcrRun run(String text, double l, double t, double r, double b,
        {bool cjk = false}) =>
    OcrRun(text, Rect.fromLTRB(l, t, r, b), cjk: cjk);

void main() {
  group('mergeRows', () {
    test('同一视觉行的拉丁段与汉字段合成一行', () {
      final rows = mergeRows([
        run('makan', 10, 100, 60, 120),
        run('吃', 70, 102, 90, 122, cjk: true),
      ]);
      expect(rows, hasLength(1));
      expect(rows.first.latinText, 'makan');
      expect(rows.first.cjkText, '吃');
    });

    test('y 相差一个行高分两行；行框上下抖几个像素不拆行', () {
      final rows = mergeRows([
        run('makan', 10, 100, 60, 120),
        run('nasi', 10, 108, 50, 128),
        run('air', 10, 200, 40, 220),
      ]);
      expect(rows, hasLength(2));
      expect(rows.first.latinText, 'makan nasi');
      expect(rows.last.latinText, 'air');
    });

    test('汉字行独立成行（没有拉丁词）', () {
      final rows = mergeRows([
        run('释义单独一行', 10, 100, 200, 120, cjk: true),
      ]);
      expect(rows, hasLength(1));
      expect(rows.first.latinText, '');
      expect(rows.first.cjkText, isNotEmpty);
    });
  });

  group('cleanZh', () {
    test('剥行首编号与行尾标点', () {
      expect(cleanZh('1. 吃；食物。'), '吃；食物');
      expect(cleanZh('、睡觉'), '睡觉');
      expect(cleanZh('12喝'), '喝');
    });

    test('正常释义原样保留', () {
      expect(cleanZh('吃；进食'), '吃；进食');
      expect(cleanZh(''), '');
    });
  });

  group('pairDefinitions', () {
    test('同行直接配对', () {
      final pairs = pairDefinitions([
        mergeRows([run('makan', 10, 100, 60, 120), run('吃', 70, 100, 90, 120, cjk: true)]).first,
      ]);
      expect(pairs, hasLength(1));
      expect(pairs.first.latin, 'makan');
      expect(pairs.first.zh, '吃');
      expect(pairs.first.weak, isFalse);
    });

    test('词 / 释义分行排 → 弱配（标猜测）', () {
      final pairs = pairDefinitions(mergeRows([
        run('belajar', 10, 100, 80, 120),
        run('学习', 10, 130, 60, 150, cjk: true),
      ]));
      expect(pairs, hasLength(1));
      expect(pairs.first.zh, '学习');
      expect(pairs.first.weak, isTrue);
    });

    test('没抓到中文 → 空释义；纯汉字行不产出条目', () {
      final pairs = pairDefinitions(mergeRows([
        run('rumah', 10, 100, 70, 120),
        run('只词无义', 10, 140, 90, 160, cjk: true),
        run('makan', 10, 180, 80, 200),
      ]));

      expect(pairs, hasLength(2));
      expect(pairs.first.latin, 'rumah');
      expect(pairs.first.weak, isTrue);
      expect(pairs.last.latin, 'makan');
      expect(pairs.last.zh, '');
    });
  });

  group('rowCandidates', () {
    test('span 从长到短；标点经 fold 剥掉', () {
      final spans = rowCandidates('makan, nasi');
      expect(spans.map((s) => s.form).toList(), ['makan nasi', 'makan', 'nasi']);
      expect(spans.first.fold, 'makan nasi');
    });

    test('大小写 / é 折叠成主键形态', () {
      final spans = rowCandidates('Toko Buku absén,');
      expect(spans.map((s) => s.fold).toList(),
          containsAll(['toko buku', 'toko', 'buku', 'absen']));
    });

    test('单字母与纯数字噪声丢弃；两字母真词保留', () {
      final spans = rowCandidates('a 1 di ke 23x');

      final forms = spans.where((s) => s.width == 1).map((s) => s.form).toList();
      expect(forms, containsAll(['di', 'ke']));
      expect(forms, isNot(contains('a')));
    });

    test('长行最多给 5 词 span，滑窗覆盖全部起点', () {
      final spans = rowCandidates('saya mau makan nasi goreng enak sekali');
      expect(spans.every((s) => s.width <= 5), isTrue);
      expect(spans.first.width, 5);

      expect(spans.where((s) => s.width == 1).length, 7);
    });
  });

  group('runsFromPastedText', () {
    test('每行「词 + 中文」拆成拉丁段与汉字段，合成同一视觉行', () {
      final rows = mergeRows(runsFromPastedText('makan\t吃\nminum 喝'));
      expect(rows, hasLength(2));
      expect(rows.first.latinText, 'makan');
      expect(rows.first.cjkText, '吃');
      expect(rows.last.latinText, 'minum');
      expect(rows.last.cjkText, '喝');
    });

    test('纯课文按行保留；空行跳过；CRLF 兼容', () {
      final rows = mergeRows(
          runsFromPastedText('saya mau makan nasi\r\n\r\nkemarin saya pergi'));
      expect(rows, hasLength(2));
      expect(rows.first.latinText, 'saya mau makan nasi');
      expect(rows.first.cjkText, '');
      expect(rows.last.latinText, 'kemarin saya pergi');
    });

    test('词义配对直接复用 pairDefinitions', () {
      final pairs = pairDefinitions(mergeRows(
          runsFromPastedText('toko buku 书店\nrumah 房子')));
      expect(pairs.map((p) => p.latin).toList(), ['toko buku', 'rumah']);
      expect(pairs.map((p) => p.zh).toList(), ['书店', '房子']);
    });

    test('生词表的行首编号与项目符号剥掉', () {
      final rows = mergeRows(
          runsFromPastedText('1. makan 吃\n① minum 喝\n- tidur 睡'));
      expect(rows.map((r) => r.latinText).toList(), ['makan', 'minum', 'tidur']);
    });
  });

  group('resolveRow', () {
    test('长 span 命中后吃掉单词候选（toko buku 不再单列）', () {
      final spans = rowCandidates('toko buku');
      final dict = {'toko buku': true, 'toko': true, 'buku': true};
      final hits = resolveRow(spans, dict.containsKey, tokenCount: 2);
      expect(hits.map((s) => s.fold).toList(), ['toko buku']);
    });

    test('短语没命中时单词各自命中', () {
      final spans = rowCandidates('toko buku');
      final dict = {'toko': true, 'buku': true};
      final hits = resolveRow(spans, dict.containsKey, tokenCount: 2);
      expect(hits.map((s) => s.fold).toList(), ['toko', 'buku']);
    });

    test('被左边更长短语吃掉的中间词不再命中', () {

      final spans = rowCandidates('makan nasi goreng');
      final dict = {'makan nasi goreng': true, 'nasi': true};
      final hits = resolveRow(spans, dict.containsKey, tokenCount: 3);
      expect(hits.map((s) => s.fold).toList(), ['makan nasi goreng']);
    });
  });
}
