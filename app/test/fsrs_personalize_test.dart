import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/fsrs_personalize.dart';

void main() {
  final g = jsonDecode(File('test/golden.json').readAsStringSync())
      as Map<String, dynamic>;
  List<List<List<int>>> hist() => [
        for (final v in (g['histories'] as Map<String, dynamic>).values)
          [
            for (final e in (v as List))
              [for (final x in (e as List)) (x as num).toInt()]
          ]
      ];
  List<double> w2() => [for (final x in g['W2'] as List) (x as num).toDouble()];

  test('默认权重通过校验；19 个 / 越界 / NaN 被拒绝', () {
    expect(FsrsPersonalize.validateWeights(FsrsPersonalize.defaultW), isNull);
    expect(
        FsrsPersonalize.validateWeights(
            FsrsPersonalize.defaultW.sublist(0, 19)),
        contains('21'));
    final bad = [...FsrsPersonalize.defaultW]..[4] = 11;
    expect(FsrsPersonalize.validateWeights(bad), contains('第 5 个'));
    final nan = [...FsrsPersonalize.defaultW]..[0] = double.nan;
    expect(FsrsPersonalize.validateWeights(nan), isNotNull);
  });

  test('parseWeights 支持逗号/空格/方括号/换行', () {
    expect(FsrsPersonalize.parseWeights('[0.2, 1.3,\n2.3 8e-1]'),
        [0.2, 1.3, 2.3, 0.8]);
    expect(FsrsPersonalize.parseWeights('没有数字'), isEmpty);
  });

  test('对数损失与 Python 参考实现一致（1e-9）', () {
    final a = FsrsPersonalize.logLoss(FsrsPersonalize.defaultW, hist());
    final b = FsrsPersonalize.logLoss(w2(), hist());
    expect(a.n, g['n_default']);
    expect(a.loss, closeTo((g['loss_default'] as num).toDouble(), 1e-9));
    expect(b.loss, closeTo((g['loss_W2'] as num).toDouble(), 1e-9));
  });

  test('逐条预测一致', () {
    final ev = hist()[0];
    final p = FsrsPersonalize.replay(FsrsPersonalize.defaultW, ev);
    final want = g['preds_a_default'] as List;
    expect(p.length, want.length);
    for (var i = 0; i < p.length; i++) {
      expect(p[i][0], closeTo((want[i][0] as num).toDouble(), 1e-9));
      expect(p[i][1], (want[i][1] as num).toDouble());
    }
  });

  test('CSV 与日序号对拍', () {
    final rows = [
      for (final r in g['rows'] as List)
        ReviewEvent(r[0] as String, r[2] as int, r[1] as int)
    ];
    expect(FsrsPersonalize.buildCsv(rows), g['csv']);
    for (final d in g['dayIndex'] as List) {
      expect(
          FsrsPersonalize.dayIndexWithOffset(d[0] as int, d[1] as int), d[2]);
    }
  });

  test('compare：更好的参数 improvement>0', () {
    final c = FsrsPersonalize.compare(FsrsPersonalize.defaultW, w2(), hist());
    expect(c.improvement, greaterThan(0));
  });
}
