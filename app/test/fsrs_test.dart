import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/fsrs.dart';

import 'package:katamemo/screens/study_screen.dart';

void main() {
  group('FSRS-6 公式对拍（oracle 来自 fsrs-rs 官方测试）', () {
    test('遗忘曲线锚点：R(S,S)=0.9, R(0)=1', () {
      expect(Fsrs.retrievability(0, 1), closeTo(1.0, 1e-9));
      expect(Fsrs.retrievability(1, 1), closeTo(0.9, 1e-6));

      expect(Fsrs.intervalFor(5.0, 0.9), closeTo(5.0, 0.05));
    });

    test('成功路径稳定性 S\'_r（oracle: [25.602541, 28.226582, 58.656002, 127.226685]）',
        () {

      const w = Fsrs.defaultW;
      for (var i = 0; i < 4; i++) {
        final g = i + 1;
        final r = [0.9, 0.8, 0.7, 0.6][i];
        final s = Fsrs.nextSuccessStability(5.0, g.toDouble(), r, g);
        expect(
            s, closeTo([25.602541, 28.226582, 58.656002, 127.226685][i], 0.001),
            reason: 'G=$g');
      }

      expect(w[15], closeTo(0.6014, 1e-6));
      expect(w[16], closeTo(1.8729, 1e-6));
    });

    test('失败路径稳定性 S\'_f（oracle: [1.0525396, 1.1894329, 1.3680838, 1.584989]）',
        () {
      for (var i = 0; i < 4; i++) {
        final d = i + 1.0;
        final r = [0.9, 0.8, 0.7, 0.6][i];
        final s = Fsrs.nextForgetStability(5.0, d, r);
        expect(
            s, closeTo([1.0525396, 1.1894329, 1.3680838, 1.584989][i], 0.001),
            reason: 'D=$d');
      }
    });

    test('难度更新（oracle 均值回归后: [8.341763, 6.6659956, 4.990228, 3.3144615]）', () {
      for (var i = 0; i < 4; i++) {
        final g = i + 1;
        final d = Fsrs.nextDifficulty(5.0, g);
        expect(d, closeTo([8.341763, 6.6659956, 4.990228, 3.3144615][i], 0.001),
            reason: 'G=$g');
      }
    });

    test('初始稳定性 S0(G)=w[G-1]', () {
      expect(Fsrs.initStability(1), closeTo(0.212, 1e-6));
      expect(Fsrs.initStability(2), closeTo(1.2931, 1e-6));
      expect(Fsrs.initStability(3), closeTo(2.3065, 1e-6));
      expect(Fsrs.initStability(4), closeTo(8.2956, 1e-6));
    });

    test('初始难度 D0(G)=w4-e^{w5(G-1)}+1', () {
      expect(Fsrs.initDifficulty(1), closeTo(6.4133, 1e-4));
      expect(Fsrs.initDifficulty(2), closeTo(6.4133 - 2.3065 + 1, 0.5));
    });

    test('间隔函数：r=0.9 时 I(S)=S（锚点）', () {
      for (final s in [1.0, 5.0, 20.0, 100.0]) {
        expect(Fsrs.intervalFor(s, 0.9), closeTo(s, s * 0.01), reason: 'S=$s');
      }
    });
  });

  group('FSRS-6 三选项特化（状态机）', () {
    test('新卡点认识 -> 直接毕业进复习，间隔≈S0(Good)=2.3 天', () {
      final s = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      expect(s.state, FsrsState.review);
      expect(s.stability, closeTo(2.3065, 0.001));
      expect(s.reps, 1);
      final days = s.due.difference(DateTime.now()).inDays;
      expect(days, inInclusiveRange(1, 3));
    });

    test('新卡点困难 -> 进入学习，10分钟后', () {
      final s = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(s.state, FsrsState.learning);
      expect(s.due.difference(DateTime.now()).inMinutes, closeTo(10, 1));
    });

    test('新卡点模糊 -> 进入学习', () {
      final s = Fsrs.apply(null, Fsrs.ratingFuzzy, elapsedDays: 0);
      expect(s.state, FsrsState.learning);
      expect(s.stability, closeTo(1.2931, 0.001));
    });

    test('困难后要连着两次「记得」才毕业', () {
      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(l.state, FsrsState.learning);
      expect(l.step, 0);

      final s1 = Fsrs.apply(l, Fsrs.ratingKnow);
      expect(s1.state, FsrsState.learning, reason: '一次记得还不该过卡');
      expect(s1.step, 1);
      expect(s1.due.difference(DateTime.now()).inMinutes, closeTo(10, 1));
      expect(StudyScreen.needsRequeue(s1), isTrue, reason: '没攒够就得回队');

      final s2 = Fsrs.apply(s1, Fsrs.ratingKnow);
      expect(s2.state, FsrsState.review);
      expect(s2.reps, 3);
      expect(StudyScreen.needsRequeue(s2), isFalse);
    });

    test('模糊后一次「记得」就毕业；复习卡点模糊也要回队', () {

      final f = Fsrs.apply(null, Fsrs.ratingFuzzy, elapsedDays: 0);
      expect(f.state, FsrsState.learning);
      expect(f.step, 1);
      expect(Fsrs.apply(f, Fsrs.ratingKnow).state, FsrsState.review,
          reason: '模糊只要一次记得');

      final rv = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      expect(rv.state, FsrsState.review);
      final fz = Fsrs.apply(rv, Fsrs.ratingFuzzy, elapsedDays: 1, now: rv.due);
      expect(fz.state, FsrsState.relearning, reason: '复习卡点模糊要回队');
      expect(fz.step, 1);
      expect(Fsrs.apply(fz, Fsrs.ratingKnow).state, FsrsState.review);
    });

    test('两次记得之间又点困难 → 计数归零，重新数两次', () {
      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      final s1 = Fsrs.apply(l, Fsrs.ratingKnow);
      expect(s1.step, 1);
      final back = Fsrs.apply(s1, Fsrs.ratingForget);
      expect(back.step, 0, reason: '又忘了就要重新数两次');
      expect(back.state, FsrsState.learning);
      final again = Fsrs.apply(back, Fsrs.ratingKnow);
      expect(again.state, FsrsState.learning, reason: '这只能算第一次记得');
      expect(again.step, 1);
    });

    test('复习卡点认识照旧一次就过（门槛不拦复习卡）', () {
      final s = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      final s2 = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 3, now: s.due);
      expect(s2.state, FsrsState.review);
    });

    test('复习中困难 -> 重学 + lapse + 稳定性下降（失败路径）', () {
      var s = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      final s2 = Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 5, now: s.due);
      expect(s2.state, FsrsState.relearning);
      expect(s2.lapses, 1);
      expect(s2.due.difference(s.due).inMinutes, closeTo(10, 1));
      expect(s2.stability, lessThan(s.stability));
    });

    test('复习中认识 -> 间隔增长（成功路径）', () {
      var s = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      final s2 = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 5, now: s.due);
      expect(s2.state, FsrsState.review);
      expect(s2.stability, greaterThan(s.stability));
      final days = s2.due.difference(s.due).inDays;
      expect(days, greaterThan(2));
    });

    test('间隔单调性：认识 >= 模糊 >= 困难', () {
      var s = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      final forget =
          Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 5, now: s.due);
      final fuzzy = Fsrs.apply(s, Fsrs.ratingFuzzy, elapsedDays: 5, now: s.due);
      final know = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 5, now: s.due);
      expect(know.stability, greaterThanOrEqualTo(fuzzy.stability));
      expect(fuzzy.stability, greaterThan(forget.stability));
    });

    test('难度始终 clamp 在 1-10', () {
      var s = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      for (var i = 0; i < 50; i++) {
        s = Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 1, now: s.due);
        expect(s.difficulty, inInclusiveRange(1, 10));
      }
    });

    test('按钮标签：困难显示「重学」，认识显示天后', () {

      final forgetLabel = Fsrs.nextLabel(null, Fsrs.ratingForget);
      expect(forgetLabel, '重学');
      expect(forgetLabel, isNot(contains('分钟')),
          reason: '排期是 10 分钟，但用户不等它 —— 别把排期当会话节奏写出来');
      final knowLabel = Fsrs.nextLabel(null, Fsrs.ratingKnow);
      expect(knowLabel, contains('天'));
    });

    test('记忆强度设置影响间隔（保留率越高复习越勤）', () {
      Fsrs.requestedRetention = 0.9;
      final s90 = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      Fsrs.requestedRetention = 0.95;
      final s95 = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);

      expect(s95.due.difference(DateTime.now()),
          lessThan(s90.due.difference(DateTime.now())));
      Fsrs.requestedRetention = 0.9;
    });

    group('同日复习（短时稳定度）', () {
      FsrsState reviewCard(double s) => FsrsState(
            stability: s,
            difficulty: 5,
            state: FsrsState.review,
            reps: 3,
            lastReview: DateTime.now(),
            due: DateTime.now(),
          );

      test('同日认识：sinc 被下限 1 托住，S 不倒退', () {
        final s = reviewCard(5);
        final n = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 0);

        expect(n.stability, closeTo(5.0, 1e-9));
        expect(n.state, FsrsState.review);
      });

      test('同日认识（小 S）：S 会变大（0.5 -> 0.5499）', () {
        final n = Fsrs.apply(reviewCard(0.5), Fsrs.ratingKnow, elapsedDays: 0);
        expect(n.stability, closeTo(0.549876, 1e-5));
      });

      test('同日模糊：同样被托住，绝不降低 S', () {
        final n = Fsrs.apply(reviewCard(5), Fsrs.ratingFuzzy, elapsedDays: 0);
        expect(n.stability, closeTo(5.0, 1e-9));
      });

      test('同日困难：走短时公式，S 下降并进重学（5 -> 1.5968）', () {
        final s = reviewCard(5);
        final n = Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 0);
        expect(n.stability, closeTo(1.596818, 1e-5));
        expect(n.stability, lessThan(s.stability));
        expect(n.state, FsrsState.relearning);
        expect(n.lapses, s.lapses + 1);
      });

      test('相隔 1 天以上仍走长期公式（短时不越界）', () {
        final s = reviewCard(5);
        final long = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 5);
        final short = Fsrs.apply(s, Fsrs.ratingKnow, elapsedDays: 0);

        expect(long.stability, isNot(closeTo(short.stability, 1e-9)));
      });

      test('w17/w18/w19 真的参与计算（改权重会改结果）', () {

        final s = reviewCard(5);
        final n = Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 0);
        final manual = Fsrs.nextShortTermStability(5, 1);
        expect(n.stability, closeTo(manual, 1e-9));
      });
    });
  });

  group('Easy（轻松）第四档', () {
    test('新卡首次点轻松 → 直接毕业进 review', () {
      final s = Fsrs.apply(null, Fsrs.ratingEasy, elapsedDays: 0);
      expect(s.state, FsrsState.review);
      expect(s.stability, greaterThan(0));
    });

    test('新卡首次轻松给出的间隔 ≥ 首次记得（g=4 比 g=3 更远）', () {
      final easy = Fsrs.apply(null, Fsrs.ratingEasy, elapsedDays: 0);
      final know = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      expect(easy.due.isAfter(know.due), isTrue);
    });

    test('轻松**绕过记得门槛**：学习中的卡点轻松即毕业（不必攒两次「记得」）', () {

      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(l.state, FsrsState.learning);

      final k1 = Fsrs.apply(l, Fsrs.ratingKnow);
      expect(k1.state, FsrsState.learning, reason: '只垫了 1 次，还差 1 次');

      final e = Fsrs.apply(l, Fsrs.ratingEasy);
      expect(e.state, FsrsState.review);

      final lf = Fsrs.apply(null, Fsrs.ratingFuzzy, elapsedDays: 0);
      expect(lf.state, FsrsState.learning);
      expect(Fsrs.apply(lf, Fsrs.ratingKnow).state, FsrsState.review,
          reason: '模糊垫 1 次 + 这次记得 = 2 ⇒ 毕业');
    });

    test('重学中的卡点轻松也直接毕业', () {
      final rv = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      expect(rv.state, FsrsState.review);
      final back =
          Fsrs.apply(rv, Fsrs.ratingForget, elapsedDays: 30, now: rv.due);
      expect(back.state, FsrsState.relearning);
      final e = Fsrs.apply(back, Fsrs.ratingEasy);
      expect(e.state, FsrsState.review);
    });

    test('复习卡点轻松：稳定度不低于点记得', () {
      final rv = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0);
      final e = Fsrs.apply(rv, Fsrs.ratingEasy, elapsedDays: 1, now: rv.due);
      final k = Fsrs.apply(rv, Fsrs.ratingKnow, elapsedDays: 1, now: rv.due);
      expect(e.stability, greaterThanOrEqualTo(k.stability));
      expect(e.state, FsrsState.review);
    });

    test('nextLabel 支持轻松（给出非「重学」的预估文案）', () {
      final lbl = Fsrs.nextLabel(null, Fsrs.ratingEasy, elapsedDays: 0);
      expect(lbl, isNot('重学'));
    });
  });
}
