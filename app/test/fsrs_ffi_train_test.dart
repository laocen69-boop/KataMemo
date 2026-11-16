library;

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/fsrs_ffi.dart';

void main() {
  group('trainSets（训练输入口径）', () {
    test('首条 delta 0；同日多条保留为 0；隔天为天数差', () {
      final hist = [
        [
          [10, 2],
          [10, 3],
          [13, 1],
        ],
      ];
      expect(trainSets(hist), [
        [
          (2, 0),
          (3, 0),
          (1, 3),
        ],
      ]);
    });

    test('多张卡各自独立计算 delta', () {
      final hist = [
        [
          [5, 2],
          [9, 3],
        ],
        [
          [7, 1],
        ],
      ];
      expect(trainSets(hist), [
        [
          (2, 0),
          (3, 4),
        ],
        [(1, 0)],
      ]);
    });

    test('rating 脏数据夹在 1..4（不能把越界值送进 FFI）', () {
      expect(trainSets([
        [
          [1, 5],
        ]
      ]), [
        [(4, 0)]
      ]);
      expect(trainSets([
        [
          [1, 0],
        ]
      ]), [
        [(1, 0)]
      ]);
    });

    test('空历史 → 空列表（optimizeOnDevice 对空集直接返回 null）', () {
      expect(trainSets(const []), isEmpty);
    });
  });

  group('optimizeOnDevice 的降级路径', () {
    test('宿主机没有 libfsrs.so 时优雅返回 null（不抛）', () async {

      if (!FsrsFfi.available) {
        expect(await FsrsFfi.optimizeOnDevice([
          [
            [1, 2],
          ]
        ]), isNull);
      }
    });
  });

  group('diagnoseTrainData 与 filterTrainableHist', () {
    test('区分单次作答 / 仅同日多次 / 含跨天有效卡 / initCards', () {
      final hist = [
        [
          [10, 3],
        ],
        [
          [10, 2],
          [10, 3],
        ],
        [
          [10, 3],
          [12, 3],
        ],
        [
          [10, 3],
          [12, 3],
          [15, 4],
        ],
      ];
      final d = diagnoseTrainData(hist);
      expect(d.totalCards, 4);
      expect(d.singleReviewCards, 1);
      expect(d.sameDayOnlyCards, 1);
      expect(d.usableCards, 2);
      expect(d.initCards, 1);

      final filtered = filterTrainableHist(hist);
      expect(filtered.length, 2);
    });
  });
}
