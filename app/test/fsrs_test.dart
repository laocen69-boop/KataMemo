import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/fsrs.dart';
// `StudyScreen.needsRequeue` —— 「回不回队」的判据只有那一份，这里不自己拼一遍
import 'package:katamemo/screens/study_screen.dart';

void main() {
  group('FSRS-6 公式对拍（oracle 来自 fsrs-rs 官方测试）', () {
    test('遗忘曲线锚点：R(S,S)=0.9, R(0)=1', () {
      expect(Fsrs.retrievability(0, 1), closeTo(1.0, 1e-9));
      expect(Fsrs.retrievability(1, 1), closeTo(0.9, 1e-6));
      // R(1,1)=0.9 意味着 intervalFor(S, 0.9) == S（自洽）
      expect(Fsrs.intervalFor(5.0, 0.9), closeTo(5.0, 0.05));
    });

    test('成功路径稳定性 S\'_r（oracle: [25.602541, 28.226582, 58.656002, 127.226685]）',
        () {
      // D 块（记忆算法）把 `W` 改成「可被用户个性化参数覆盖的可变静态」，
      // 默认值挪到 `const defaultW` ⇒ 纯公式对拍这里取 `defaultW`（oracle 就是那 21 个数）。
      const w = Fsrs.defaultW;
      for (var i = 0; i < 4; i++) {
        final g = i + 1;
        final r = [0.9, 0.8, 0.7, 0.6][i];
        final s = Fsrs.nextSuccessStability(5.0, g.toDouble(), r, g);
        expect(
            s, closeTo([25.602541, 28.226582, 58.656002, 127.226685][i], 0.001),
            reason: 'G=$g');
      }
      // 关键：成功路径含 ((S+1)^w13 - 1) 之外的 hard/easy 权重
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
      expect(days, inInclusiveRange(1, 3)); // 2.3 天（含毫秒取整误差）
    });

    test('新卡点困难 -> 进入学习，10分钟后', () {
      final s = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(s.state, FsrsState.learning);
      expect(s.due.difference(DateTime.now()).inMinutes, closeTo(10, 1));
    });

    test('新卡点模糊 -> 进入学习', () {
      final s = Fsrs.apply(null, Fsrs.ratingFuzzy, elapsedDays: 0);
      expect(s.state, FsrsState.learning);
      expect(s.stability, closeTo(1.2931, 0.001)); // S0(Hard)
    });

    // ---- 「记得门槛」（2026-09-23 用户拍板的学习手感）----
    //
    // 用户原话：「第一次点忘记后要连续点击两次记得才能过卡，且两次都有间隔以免用户是
    // 假记得；点模糊后点击一次记得就会过卡」。
    test('困难后要连着两次「记得」才毕业', () {
      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(l.state, FsrsState.learning);
      expect(l.step, 0);
      // 第一次记得：还不够 → 留在学习里（`needsRequeue` 会让它隔 6 张再来）
      final s1 = Fsrs.apply(l, Fsrs.ratingKnow);
      expect(s1.state, FsrsState.learning, reason: '一次记得还不该过卡');
      expect(s1.step, 1);
      expect(s1.due.difference(DateTime.now()).inMinutes, closeTo(10, 1));
      expect(StudyScreen.needsRequeue(s1), isTrue, reason: '没攒够就得回队');
      // 第二次记得：攒够 → 毕业进复习
      final s2 = Fsrs.apply(s1, Fsrs.ratingKnow);
      expect(s2.state, FsrsState.review);
      expect(s2.reps, 3);
      expect(StudyScreen.needsRequeue(s2), isFalse);
    });

    test('模糊后一次「记得」就毕业；复习卡点模糊也要回队', () {
      // 新卡点模糊 → 学习（step 1 = 已算一次）
      final f = Fsrs.apply(null, Fsrs.ratingFuzzy, elapsedDays: 0);
      expect(f.state, FsrsState.learning);
      expect(f.step, 1);
      expect(Fsrs.apply(f, Fsrs.ratingKnow).state, FsrsState.review,
          reason: '模糊只要一次记得');

      // 复习卡点模糊：以前**直接过卡、不回队**，现在要回队走一遍
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
      // 2026-09-22 改：显示「重学」而不是「10分钟后」——那张卡在本组里
      // **隔 6 张就再出现**（`_relearnGap`，不设上限），根本不是 10 分钟后
      // 才见面；写时间会让用户觉得界面在骗人（`Fsrs.nextLabel` 的注释有全文）。
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
      // 保留率 0.95 > 0.9 → 间隔更短（更勤复习）
      expect(s95.due.difference(DateTime.now()),
          lessThan(s90.due.difference(DateTime.now())));
      Fsrs.requestedRetention = 0.9; // 还原
    });

    // ===== FSRS-6 同日复习（短时公式，w17/w18/w19）=====
    //
    // 公式与判据对齐官方实现 ts-fsrs 的 `next_short_term_stability`
    // + `if (t === 0 && enable_short_term)`；本移植用「小时/24」的浮点，
    // 等价条件是 elapsedDays < 1。期望值是**按公式手算**的（见脚本留痕：
    // data/rebuild/_shortterm.py），不是从实现里反推的。
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
        // sinc = 5^-w19 · e^{w17·w18} = 0.8995·1.0507 = 0.9452 < 1 → 取 1
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
        // 长期公式在 r<1 时才会增长；两者必须不同（说明分支确实分开了）
        expect(long.stability, isNot(closeTo(short.stability, 1e-9)));
      });

      test('w17/w18/w19 真的参与计算（改权重会改结果）', () {
        // 这条是防回归：这三个权重曾经定义了却从未被用到
        final s = reviewCard(5);
        final n = Fsrs.apply(s, Fsrs.ratingForget, elapsedDays: 0);
        final manual = Fsrs.nextShortTermStability(5, 1);
        expect(n.stability, closeTo(manual, 1e-9));
      });
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 第四档「轻松」（实施单 C · 用户已批 2026-10-12）——
  // 官方对拍用例一字不动，这里只**新增** Easy 的行为用例。
  // 评分映射：g = rating + 1 ⇒ Easy → g=4（easyBonus / S0(4) 官方路径）。
  // ─────────────────────────────────────────────────────────────
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
      // ⚠️ 造「门槛未攒够」的学习卡要用**困难**（`banked = 0`）。
      //    用「模糊」不行 —— 模糊本身就垫 1 次（`banked = prev.step + 1 = 2`），
      //    下一次「记得」就该毕业，那是 `fsrs.dart` `_applyKnowGate` 注释里明写的
      //    设计（「模糊 → 下一次记得就过卡」），不是 bug。
      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0);
      expect(l.state, FsrsState.learning);
      // 门槛（`kKnowStepsNeeded = 2`）未攒够时点「记得」仍在学习里…
      final k1 = Fsrs.apply(l, Fsrs.ratingKnow);
      expect(k1.state, FsrsState.learning, reason: '只垫了 1 次，还差 1 次');
      // …但点「轻松」直接毕业
      final e = Fsrs.apply(l, Fsrs.ratingEasy);
      expect(e.state, FsrsState.review);
      // 附：模糊垫 1 次 ⇒ 模糊 + 记得 就该毕业（设计如此，别当回归）
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

    test('跨夜早读（昨晚22:00学 → 今早08:30复习）判为跨天≥1天，不陷入短时1天死循环', () {
      final night = DateTime(2026, 11, 23, 22, 0);
      final morning = DateTime(2026, 11, 24, 8, 30);
      final lateSameSession = DateTime(2026, 11, 24, 0, 10);

      expect(Fsrs.elapsedDaysSince(night, lateSameSession), 0.0,
          reason: '4小时内熬夜跨零点仍视为同一次会话');
      final elapsed = Fsrs.elapsedDaysSince(night, morning);
      expect(elapsed, 1.0);

      final s0 = Fsrs.apply(null, Fsrs.ratingKnow, elapsedDays: 0, now: night);
      final s1 = Fsrs.apply(s0, Fsrs.ratingKnow,
          elapsedDays: elapsed, now: morning);
      expect(s1.stability, greaterThan(s0.stability * 1.5),
          reason: '跨夜复习必须走长期公式大幅增长，而不是被短时公式卡在 ~2.3 天');
    });

    test('learning 卡点轻松不再被 0.212 冻结成 1 天；跨天答对享受长期增益', () {
      final t0 = DateTime(2026, 11, 18, 10, 0);
      final l = Fsrs.apply(null, Fsrs.ratingForget, elapsedDays: 0, now: t0);
      expect(l.state, FsrsState.learning);
      expect(l.stability, closeTo(0.212, 1e-4));

      // 同日连错，难度必须上升
      final lAgain = Fsrs.apply(l, Fsrs.ratingForget, elapsedDays: 0, now: t0);
      expect(lAgain.difficulty, greaterThan(l.difficulty));

      // 同日点轻松，毕业稳定度不低于 S0(Easy)
      final easyGrad =
          Fsrs.apply(l, Fsrs.ratingEasy, elapsedDays: 0, now: t0);
      expect(easyGrad.state, FsrsState.review);
      expect(easyGrad.stability, greaterThanOrEqualTo(Fsrs.initStability(4)));

      // 隔 5 天回来答对（两次认识或轻松），享受长期公式增益
      final t5 = t0.add(const Duration(days: 5));
      final crossDay =
          Fsrs.apply(l, Fsrs.ratingEasy, elapsedDays: 5.0, now: t5);
      expect(crossDay.state, FsrsState.review);
      expect(crossDay.stability, greaterThan(Fsrs.initStability(1) * 2));
    });
  });
}
