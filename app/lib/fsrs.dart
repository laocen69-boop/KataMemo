library;

import 'dart:math' as math;

class Fsrs {

  static const List<double> defaultW = [
    0.212, 1.2931, 2.3065, 8.2956,
    6.4133, 0.8334, 3.0194, 0.001,
    1.8722, 0.1666, 0.796,
    1.4835, 0.0614, 0.2629, 1.6483,
    0.6014, 1.8729,
    0.5425, 0.0912, 0.0658,
    0.1542,
  ];

  static List<double> W = defaultW;

  static void useWeights(List<double>? w) =>
      W = w == null ? defaultW : List.unmodifiable(w);

  static const double sMin = 0.001;
  static const double sMax = 36500.0;
  static const double dMin = 1.0;
  static const double dMax = 10.0;

  static const Duration relearnStep = Duration(minutes: 10);

  static double requestedRetention = 0.9;

  static const int ratingForget = 0;
  static const int ratingFuzzy = 1;
  static const int ratingKnow = 2;

  static const int ratingEasy = 3;

  static double get _decay => -W[20];
  static double get _factor => math.exp(math.log(0.9) / _decay) - 1.0;

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  static double retrievability(double elapsedDays, double stability) {
    if (stability <= 0) return 1.0;
    return math.pow(elapsedDays / stability * _factor + 1.0, _decay).toDouble();
  }

  static double intervalFor(double stability, double r) =>
      stability / _factor * (math.pow(r, 1 / _decay) - 1);

  static double initStability(int g) => W[g.clamp(1, 4) - 1];

  static double initDifficulty(int g) => W[4] - math.exp(W[5] * (g - 1)) + 1.0;

  static double nextDifficulty(double d, int g) {
    final deltaD = -W[6] * (g - 3);
    final nextD = d + deltaD * (10 - d) / 9.0;
    final reverted = W[7] * (initDifficulty(4) - nextD) + nextD;
    return _clamp(reverted, dMin, dMax);
  }

  static double nextForgetStability(double s, double d, double r) {
    final v = W[11] *
        math.pow(d, -W[12]) *
        (math.pow(s + 1, W[13]) - 1) *
        math.exp(W[14] * (1 - r));
    return _clamp(v, sMin, sMax);
  }

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

  static double nextShortTermStability(double s, int g) {
    final sinc = math.pow(s, -W[19]) * math.exp(W[17] * (g - 3 + W[18]));
    final masked = g >= 2 ? math.max(sinc, 1.0) : sinc;
    return _clamp(s * masked, sMin, sMax);
  }

  static const int kKnowStepsNeeded = 2;

  static FsrsState apply(FsrsState? prev, int rating,
      {double elapsedDays = 0, DateTime? now}) {
    final t = now ?? DateTime.now();
    final s = prev ?? FsrsState();
    final next = _applyScheduling(s, rating, elapsedDays: elapsedDays, t: t);
    return _applyKnowGate(s, next, rating, t);
  }

  static FsrsState _applyKnowGate(
      FsrsState prev, FsrsState next, int rating, DateTime t) {
    final inLearn =
        prev.state == FsrsState.learning || prev.state == FsrsState.relearning;

    final fuzzyFromReview =
        rating == ratingFuzzy && prev.state == FsrsState.review;
    if (!inLearn && !fuzzyFromReview) return next;

    final banked = rating == ratingForget
        ? 0
        : (rating == ratingFuzzy ? 1 : prev.step + 1);

    if (rating == ratingEasy) return next;

    if (rating == ratingKnow && banked >= kKnowStepsNeeded) return next;

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

  static FsrsState _applyScheduling(FsrsState s, int rating,
      {double elapsedDays = 0, required DateTime t}) {
    final g = rating + 1;

    if (s.state == FsrsState.newCard) {
      final st = initStability(g);
      final d = initDifficulty(g);
      if (g >= 3) {

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

    if (s.state == FsrsState.learning) {

      if (rating >= ratingKnow) {

        final st = s.stability > 0 ? s.stability : initStability(g);
        final d = s.difficulty > 0 ? s.difficulty : initDifficulty(g);
        return FsrsState(
          stability: st,
          difficulty: _clamp(d, dMin, dMax),
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
        stability: s.stability,
        difficulty: s.difficulty,
        due: t.add(relearnStep),
        reps: s.reps + 1,
        lapses: s.lapses,
        state: FsrsState.learning,
        lastReview: t,
        step: rating == 0 ? 0 : (s.step + 1),
      );
    }

    if (elapsedDays < 1.0) {
      final st = nextShortTermStability(s.stability, g);
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
        lapses: s.lapses + 1,
        state: FsrsState.relearning,
        lastReview: t,
        step: 0,
      );
    }

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

class FsrsState {
  static const int newCard = 0;
  static const int learning = 1;
  static const int review = 2;
  static const int relearning = 3;

  double stability;
  double difficulty;
  DateTime due;
  DateTime? lastReview;
  int reps;
  int lapses;
  int state;
  int step;

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
