import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/fsrs.dart';
import 'package:katamemo/fsrs_personalize.dart';

void main() {
  tearDown(() => Fsrs.useWeights(null));

  test('Fsrs.defaultW 与 FsrsPersonalize.defaultW 一致（防两份漂移）', () {
    expect(Fsrs.defaultW, FsrsPersonalize.defaultW);
    expect(Fsrs.defaultW, hasLength(21));
    expect(FsrsPersonalize.validateWeights(Fsrs.defaultW), isNull);
  });

  test('useWeights 换上用户参数，useWeights(null) 回到官方默认', () {
    expect(identical(Fsrs.W, Fsrs.defaultW), isTrue);
    final custom = [...Fsrs.defaultW]..[3] = 9.5;
    Fsrs.useWeights(custom);
    expect(Fsrs.W[3], 9.5);
    expect(Fsrs.defaultW[3], 8.2956, reason: 'defaultW 不能被改动');

    final next = Fsrs.apply(null, Fsrs.ratingEasy);
    expect(next.stability, closeTo(9.5, 1e-9));
    Fsrs.useWeights(null);
    expect(identical(Fsrs.W, Fsrs.defaultW), isTrue);
    expect(Fsrs.apply(null, Fsrs.ratingEasy).stability, closeTo(8.2956, 1e-9));
  });

  test('传入的列表被冻结，外面再改不影响生效中的参数', () {
    final custom = [...Fsrs.defaultW];
    Fsrs.useWeights(custom);
    custom[0] = 99;
    expect(Fsrs.W[0], Fsrs.defaultW[0]);
    expect(() => Fsrs.W[0] = 1, throwsUnsupportedError);
  });
}
