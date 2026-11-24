/// FSRS-6 记忆调度引擎（三选项特化）
///
/// 公式与参数逐条对照官方参考实现 open-spaced-repetition/fsrs-rs
/// (src/model.rs + src/inference.rs) 与 ts-fsrs（`next_short_term_stability`）验证，
/// 单元测试使用其自带 oracle 值（18 项）+ 本移植新增的同日复习用例（6 项）。
///
/// rating 映射（三选项 -> FSRS 4 级，Easy 不映射）:
///   0 = 困难 (Again=1)   -> 失败路径 S'_f, lapses++
///   1 = 模糊 (Hard=2)    -> 成功路径 × hardPenalty
///   2 = 认识 (Good=3)    -> 标准成功路径
///   （Easy=4 从未接线：界面上没有触发入口，注释里那句「长按认识触发」
///     描述的是一个从未实现的功能，别照它去补。）
///
/// v2.5.6：**启用同日复习（短时）公式**——此前 `w17/w18/w19` 只声明未使用，
/// 同一天内的第 2 次评分对 S 毫无影响。判据 `elapsedDays < 1`（等价于官方
/// 的整数天 `t == 0`），见 `nextShortTermStability` 与 `docs/15` §4。
library;

import 'dart:math' as math;

class Fsrs {
  /// FSRS-6 官方默认权重（21 个，w[20] = decay 幅值）。
  /// 官方对拍用例**永远用它**（不受个性化影响）；与
  /// `FsrsPersonalize.defaultW` 必须一致（`fsrs_weights_test` 钉着）。
  static const List<double> defaultW = [
    0.212, 1.2931, 2.3065, 8.2956, // w0-3: S0(Again/Hard/Good/Easy)
    6.4133, 0.8334, 3.0194, 0.001, // w4-7: D0 基、D0 指数、难度衰减、均值回归强度
    1.8722, 0.1666, 0.796, // w8-10: 成功路径
    1.4835, 0.0614, 0.2629, 1.6483, // w11-14: 失败路径
    0.6014, 1.8729, // w15-16: hardPenalty / easyBonus
    0.5425, 0.0912, 0.0658, // w17-19: 同日复习稳定性
    0.1542, // w20: decay 幅值（decay = -0.1542）
  ];

  /// **当前生效的权重**：默认 = [defaultW]；用户导入个性化参数后由
  /// [useWeights] 换成那 21 个数（设置 → 记忆算法，实施单 D）。
  /// 只影响**之后**的调度，已存在的 srs 状态不重算。
  /// ⚠️ 测试里改过它的，`tearDown` 里必须 `Fsrs.useWeights(null)`。
  static List<double> W = defaultW;

  /// 传 null = 恢复官方默认。调用方须先用 `FsrsPersonalize.validateWeights` 校验。
  static void useWeights(List<double>? w) =>
      W = w == null ? defaultW : List.unmodifiable(w);

  static const double sMin = 0.001;
  static const double sMax = 36500.0;
  static const double dMin = 1.0;
  static const double dMax = 10.0;

  /// 「困难/模糊」后的**排期**间隔（FSRS 学习/重学步长）。
  ///
  /// ⚠️ 这是**写进 `srs.due` 的排期**，不是「会话里什么时候再见到它」。
  /// 之前这行注释写的是「同类记忆 App"10分钟后"」——那是一句**没验证过**的话，而且
  /// 被后来的人（包括写这段的 agent）当成了同类记忆 App 的行为去论证设计，2026-09-22
  /// 用户照真机纠正：「同类记忆 App并没有这么搞，他是一次性的，后面还是会接着跳出来」。
  /// 事实是：**会话内**答错的卡由 `StudyScreen._relearnGap` 隔 6 张就再发一次
  /// （不设次数上限，一直发到答对为止），根本不等这 10 分钟；这个 `due` 只是
  /// 万一用户中途退出，下次进来时该在什么时候再考它。
  static const Duration relearnStep = Duration(minutes: 10);

  /// 请求保留率（设置页"记忆强度"可调 0.8-0.95）
  static double requestedRetention = 0.9;

  // 三选项常量
  static const int ratingForget = 0;
  static const int ratingFuzzy = 1;
  static const int ratingKnow = 2;

  /// **轻松**（第四档，实施单 C · 用户已批 2026-10-12）：评分 → FSRS 的
  /// 映射是 `g = rating + 1`，所以 Easy → **g=4**，走 easyBonus(w16) 与
  /// S0(4) 的官方路径（公式本来就已实现，此前只是没有入口）。
  static const int ratingEasy = 3;

  static double get _decay => -W[20];
  static double get _factor => math.exp(math.log(0.9) / _decay) - 1.0;

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  /// 可提取性 R(t, S) = (1 + factor·t/S)^decay
  static double retrievability(double elapsedDays, double stability) {
    if (stability <= 0) return 1.0;
    return math.pow(elapsedDays / stability * _factor + 1.0, _decay).toDouble();
  }

  /// 间隔（天）：I(S, r) = S/factor·(r^(1/decay) − 1)
  static double intervalFor(double stability, double r) =>
      stability / _factor * (math.pow(r, 1 / _decay) - 1);

  /// 初始稳定性 S0(G) = w[G−1]（G=1..4）
  static double initStability(int g) => W[g.clamp(1, 4) - 1];

  /// 初始难度 D0(G) = w4 − e^{w5·(G−1)} + 1
  static double initDifficulty(int g) => W[4] - math.exp(W[5] * (g - 1)) + 1.0;

  /// 难度更新：线性阻尼 + 均值回归（目标 D0(4)），clamp [1,10]
  static double nextDifficulty(double d, int g) {
    final deltaD = -W[6] * (g - 3);
    final nextD = d + deltaD * (10 - d) / 9.0;
    final reverted = W[7] * (initDifficulty(4) - nextD) + nextD;
    return _clamp(reverted, dMin, dMax);
  }

  /// 失败路径稳定性（Again）: w11·D^−w12·((S+1)^w13 − 1)·e^{w14·(1−R)}
  static double nextForgetStability(double s, double d, double r) {
    final v = W[11] *
        math.pow(d, -W[12]) *
        (math.pow(s + 1, W[13]) - 1) *
        math.exp(W[14] * (1 - r));
    return _clamp(v, sMin, sMax);
  }

  /// 成功路径稳定性（Hard/Good/Easy）
  static double nextSuccessStability(double s, double d, double r, int g) {
    final hardPenalty = g == 2 ? W[15] : 1.0;
    final easyBonus = g == 4 ? W[16] : 1.0;
    final v = s *
        (1 +
            math.exp(W[8]) *
                (11 - d) *
                math.pow(s, -W[9]) *
                (math.exp(W[10] * (1 - r)) - 1) *
                hardPenalty *
                easyBonus);
    return _clamp(v, sMin, sMax);
  }

  /// 同日复习稳定度（FSRS-6 **短时**公式，v2.5.6 起启用）
  ///
  ///   sinc = S^(−w19) · e^{w17·(G−3+w18)}
  ///   G ≥ 2（模糊/认识）时 sinc 下限为 1 —— 成功评级**不允许**降低 S；
  ///   G = 1（困难）时原样使用（可以降低）。
  ///
  /// 逐行对齐官方实现 ts-fsrs 的 `next_short_term_stability`：
  ///   `const sinc = Math.pow(s, -w[19]) * Math.exp(w[17] * (g - 3 + w[18]));`
  ///   `const maskedSinc = g >= Rating.Hard ? Math.max(sinc, 1.0) : sinc;`
  ///   `return clamp(s * maskedSinc, S_MIN, 36500);`
  ///
  /// 为什么现在才启用：w17/w18/w19 一直只出现在权重表里、**从未参与计算**，
  /// 于是同一天内的第二次评分对 S 毫无影响——长期公式里
  /// `e^{w10·(1−R)}` 在 R=1（刚复习完）时恰好为 0，成功路径 S′ ≡ S。
  static double nextShortTermStability(double s, int g) {
    final sinc = math.pow(s, -W[19]) * math.exp(W[17] * (g - 3 + W[18]));
    final masked = g >= 2 ? math.max(sinc, 1.0) : sinc;
    return _clamp(s * masked, sMin, sMax);
  }

  /// 困难后要连着点几次「记得」才算「过卡」（2026-09-23 用户拍板）。
  ///
  /// 用户原话：「第一次点忘记后要连续点击两次记得才能过卡，且两次都有间隔以免用户是
  /// 假记得；点模糊后点击一次记得就会过卡」⇒ 困难进来 `step = 0`（还差 2 次）、
  /// 模糊进来 `step = 1`（还差 1 次）。隔几张再见由
  /// `StudyScreen._relearnGap = 6` 决定（本次会话的队列侧）。
  static const int kKnowStepsNeeded = 2;

  /// 本地日历天数索引（与 `FsrsPersonalize.dayIndexLocal` 同口径）。
  static int dayIndexLocal(DateTime t) =>
      DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ 86400000;

  /// 计算距上次复习的逻辑天数：
  /// - 4 小时以内一律视为同一次学习会话（`0.0`，走短时公式，防熬夜跨零点误算跨天）；
  /// - 超过 4 小时且已跨本地日历天（如昨晚 22:00 学、今早 08:30 复习），返回日历整数天差
  ///   （`>= 1.0`），正常进入长期公式并避免「<24h 早读死循环」，与端内优化器完全同口径。
  static double elapsedDaysSince(DateTime? lastReview, [DateTime? now]) {
    if (lastReview == null) return 0.0;
    final current = now ?? DateTime.now();
    final diff = current.difference(lastReview);
    if (diff.isNegative || diff.inMinutes < 240) return 0.0;
    final dayDiff = dayIndexLocal(current) - dayIndexLocal(lastReview);
    return dayDiff >= 1 ? dayDiff.toDouble() : 0.0;
  }

  /// 对一次作答执行完整状态更新（= 排期算式 ＋ 「记得门槛」两层）。
  ///
  /// [prev] 上次状态（null = 新卡）；[rating] 四档评级 0/1/2/3；
  /// [elapsedDays] 距上次复习天数；[now] 当前时间
  static FsrsState apply(FsrsState? prev, int rating,
      {double elapsedDays = 0, DateTime? now}) {
    final t = now ?? DateTime.now();
    final s = prev ?? FsrsState();
    final next = _applyScheduling(s, rating, elapsedDays: elapsedDays, t: t);
    return _applyKnowGate(s, next, rating, t);
  }

  /// 「记得门槛」：把**本该毕业**的学习 / 重学卡留下来、再走一遍。
  ///
  /// 2026-09-23 用户拍板的三条（同类记忆 App 的手感）：
  ///   · **困难** → 计数归零，要连着两次「记得」才过卡；
  ///   · **模糊** → 也要回队，下一次「记得」就过卡；
  ///   · **记得** 在复习卡上照旧一次就过（这里不拦）。
  ///
  /// ⚠️ **只否决「毕业」这个动作，S/D/间隔一个字都不改** —— [next]（排期算式的输出）
  /// 的 stability/difficulty/reps/lapses 原样带过去，所以 `fsrs_test.dart` 里那组
  /// **公式对拍（oracle 来自官方 fsrs-rs）一条都不受影响**，受影响的只是状态机。
  /// ⚠️ `srs.step` 本来就是持久化的列（`DEFAULT 0`）⇒ **不用动 `kSchemaVersion`**。
  static FsrsState _applyKnowGate(
      FsrsState prev, FsrsState next, int rating, DateTime t) {
    final inLearn =
        prev.state == FsrsState.learning || prev.state == FsrsState.relearning;
    // 复习卡点「模糊」也要回队走一遍（用户 2026-09-23 在三个选项里选的那个）
    final fuzzyFromReview =
        rating == ratingFuzzy && prev.state == FsrsState.review;
    if (!inLearn && !fuzzyFromReview) return next;
    // 已攒下的「记得」次数：困难归零、模糊算一次、记得 +1
    final banked = rating == ratingForget
        ? 0
        : (rating == ratingFuzzy ? 1 : prev.step + 1);
    // 轻松 = 直接毕业，不需要攒「记得门槛」（实施单 C1·用户已批）：
    // 语义上「我一眼就认识」不该被再考一次。
    if (rating == ratingEasy) return next;
    // 攒够了 → 放行，按排期算式给的 due 毕业
    if (rating == ratingKnow && banked >= kKnowStepsNeeded) return next;
    // 否则留在学习 / 重学里，10 分钟后「到期」（本次会话由队列隔 6 张再发）
    return FsrsState(
      stability: next.stability,
      difficulty: next.difficulty,
      due: t.add(relearnStep),
      reps: next.reps,
      lapses: next.lapses,
      state: inLearn ? prev.state : FsrsState.relearning,
      lastReview: t,
      step: banked,
    );
  }

  /// 排期算式（FSRS-6）：就是与官方 `fsrs-rs` 对拍的那一层，**与「记得门槛」无关**。
  static FsrsState _applyScheduling(FsrsState s, int rating,
      {double elapsedDays = 0, required DateTime t}) {
    final g = rating + 1; // 本 App 的 0/1/2 -> FSRS 1/2/3

    // ---------- 新卡 ----------
    if (s.state == FsrsState.newCard) {
      final st = initStability(g);
      final d = initDifficulty(g);
      if (g >= 3) {
        // 认识：直接毕业进复习，间隔由 S0 计算
        return FsrsState(
          stability: st,
          difficulty: _clamp(d, dMin, dMax),
          due: t.add(Duration(
              days:
                  intervalFor(st, requestedRetention).round().clamp(1, 3650))),
          reps: 1,
          lapses: 0,
          state: FsrsState.review,
          lastReview: t,
          step: 0,
        );
      }
      // 困难/模糊：进入学习阶段（step 层管理，10 分钟后）
      return FsrsState(
        stability: st,
        difficulty: _clamp(d, dMin, dMax),
        due: t.add(relearnStep),
        reps: 1,
        lapses: 0,
        state: FsrsState.learning,
        lastReview: t,
        step: rating == 0 ? 0 : 1,
      );
    }

    // ---------- 同日学习阶段（不足 1 天）：更新 S/D，同时防个性化参数把防蒙连击吹高 ----------
    if (s.state == FsrsState.learning && elapsedDays < 1.0) {
      final st0 = s.stability > 0 ? s.stability : initStability(g);
      final d0 = s.difficulty > 0 ? s.difficulty : initDifficulty(g);
      final dd = nextDifficulty(d0, g);
      if (rating == ratingEasy) {
        final st = _clamp(
            math.max(nextShortTermStability(st0, g), initStability(4)),
            sMin,
            sMax);
        return FsrsState(
          stability: st,
          difficulty: dd,
          due: t.add(Duration(
              days:
                  intervalFor(st, requestedRetention).round().clamp(1, 3650))),
          reps: s.reps + 1,
          lapses: s.lapses,
          state: FsrsState.review,
          lastReview: t,
          step: 0,
        );
      }
      final rawSinc =
          math.pow(st0, -W[19]) * math.exp(W[17] * (g - 3 + W[18]));
      final masked =
          g >= 2 ? math.min(math.max(rawSinc, 1.0), 2.5) : rawSinc;
      final st = _clamp(st0 * masked, sMin, sMax);
      if (rating >= ratingKnow) {
        return FsrsState(
          stability: st,
          difficulty: dd,
          due: t.add(Duration(
              days:
                  intervalFor(st, requestedRetention).round().clamp(1, 3650))),
          reps: s.reps + 1,
          lapses: s.lapses,
          state: FsrsState.review,
          lastReview: t,
          step: 0,
        );
      }
      return FsrsState(
        stability: st,
        difficulty: dd,
        due: t.add(relearnStep),
        reps: s.reps + 1,
        lapses: s.lapses,
        state: FsrsState.learning,
        lastReview: t,
        step: rating == 0 ? 0 : (s.step + 1),
      );
    }

    // ---------- 同日复习/重学（不足 1 天）：走 FSRS-6 短时公式 ----------
    //
    // 判据与官方实现一致（ts-fsrs：`if (t === 0 && enable_short_term)`）——
    // fsrs-rs 的 `days_elapsed` 是**整数天**（同一天内复习都是 0），
    // 对 relearning 的成功防蒙连击额外限制单次乘子上限 2.5，review 保持原公式不变。
    if (elapsedDays < 1.0) {
      final double st;
      if (s.state == FsrsState.relearning && g >= 2) {
        final rawSinc =
            math.pow(s.stability, -W[19]) * math.exp(W[17] * (g - 3 + W[18]));
        st = _clamp(
            s.stability * math.min(math.max(rawSinc, 1.0), 2.5), sMin, sMax);
      } else {
        st = nextShortTermStability(s.stability, g);
      }
      final dd = nextDifficulty(s.difficulty, g);
      if (rating == ratingForget) {
        return FsrsState(
          stability: st,
          difficulty: dd,
          due: t.add(relearnStep),
          reps: s.reps + 1,
          lapses: s.lapses + 1,
          state: FsrsState.relearning,
          lastReview: t,
          step: 0,
        );
      }
      final ivl0 = intervalFor(st, requestedRetention).round().clamp(1, 3650);
      return FsrsState(
        stability: st,
        difficulty: dd,
        due: t.add(Duration(days: ivl0)),
        reps: s.reps + 1,
        lapses: s.lapses,
        state: FsrsState.review,
        lastReview: t,
        step: 0,
      );
    }

    // ---------- 复习/重学/跨天学习阶段（间隔 ≥ 1 天）----------
    final r = retrievability(elapsedDays, s.stability);
    if (rating == ratingForget) {
      final raw = nextForgetStability(s.stability, s.difficulty, r);
      final ns = _clamp(
          math.min(raw, s.stability / math.exp(W[17] * W[18])), sMin, sMax);
      final nd = nextDifficulty(s.difficulty, 1);
      return FsrsState(
        stability: ns,
        difficulty: nd,
        due: t.add(relearnStep),
        reps: s.reps + 1,
        lapses: s.state == FsrsState.learning ? s.lapses : s.lapses + 1,
        state: FsrsState.relearning,
        lastReview: t,
        step: 0,
      );
    }
    // 模糊/认识 -> 成功路径
    final ns = nextSuccessStability(s.stability, s.difficulty, r, g);
    final nd = nextDifficulty(s.difficulty, g);
    final ivl = intervalFor(ns, requestedRetention).round().clamp(1, 3650);
    return FsrsState(
      stability: ns,
      difficulty: nd,
      due: t.add(Duration(days: ivl)),
      reps: s.reps + 1,
      lapses: s.lapses,
      state: FsrsState.review,
      lastReview: t,
      step: 0,
    );
  }

  /// 按钮显示的间隔标签（"重学" / "1天后" / "3天后"）。
  ///
  /// 学习/重学中的卡返回**「重学」而不是「10分钟后」**（2026-09-22 改）：
  /// 点完困难/模糊之后，这张卡在本组里**隔 6 张就会再出现**（`_relearnGap`，
  /// 不设上限），根本不是 10 分钟后才见面——写时间会让用户觉得界面在骗人
  /// （用户上一轮刚因为「同一张卡两套记号」抓过一次同类问题）。
  /// `relearnStep` 那个 10 分钟只是万一退出会话后的排期，不面向这个按钮。
  static String nextLabel(FsrsState? prev, int rating,
      {double elapsedDays = 0}) {
    final s = apply(prev, rating, elapsedDays: elapsedDays);
    if (s.state == FsrsState.learning || s.state == FsrsState.relearning) {
      return '重学';
    }
    final days = s.due.difference(DateTime.now()).inDays;
    if (days <= 0) return '今天';
    if (days == 1) return '1天后';
    if (days < 30) return '$days天后';
    return '${(days / 30).ceil()}个月后';
  }
}

/// 卡片记忆状态（FSRS-6）
class FsrsState {
  static const int newCard = 0;
  static const int learning = 1;
  static const int review = 2;
  static const int relearning = 3;

  double stability; // S（天）
  double difficulty; // D（1-10）
  DateTime due;
  DateTime? lastReview;
  int reps;
  int lapses;
  int state;
  int step; // 学习/重学 step 索引

  FsrsState({
    this.stability = 0,
    this.difficulty = 5,
    DateTime? due,
    this.lastReview,
    this.reps = 0,
    this.lapses = 0,
    this.state = newCard,
    this.step = 0,
  }) : due = due ?? DateTime.now();

  Map<String, Object?> toMap(String cardId) => {
        'card_id': cardId,
        'stability': stability,
        'difficulty': difficulty,
        'due': due.millisecondsSinceEpoch,
        'last_review': lastReview?.millisecondsSinceEpoch,
        'reps': reps,
        'lapses': lapses,
        'state': state,
        'step': step,
      };

  factory FsrsState.fromMap(Map<String, Object?> m) => FsrsState(
        stability: (m['stability'] as num?)?.toDouble() ?? 0,
        difficulty: (m['difficulty'] as num?)?.toDouble() ?? 5,
        due: DateTime.fromMillisecondsSinceEpoch(m['due'] as int? ?? 0),
        lastReview: m['last_review'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_review'] as int),
        reps: m['reps'] as int? ?? 0,
        lapses: m['lapses'] as int? ?? 0,
        state: m['state'] as int? ?? 0,
        step: m['step'] as int? ?? 0,
      );
}
