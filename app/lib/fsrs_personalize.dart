library;

import 'dart:math' as math;

class ReviewEvent {
  final String cardId;
  final int ts;
  final int rating;
  const ReviewEvent(this.cardId, this.ts, this.rating);
}

class WeightsCompare {
  final double currentLoss;
  final double candidateLoss;
  final int n;
  const WeightsCompare(this.currentLoss, this.candidateLoss, this.n);

  double get improvement =>
      currentLoss <= 0 ? 0 : (currentLoss - candidateLoss) / currentLoss;

  bool get clearlyBetter => improvement >= 0.01;
}

class FsrsPersonalize {
  FsrsPersonalize._();

  static const List<double> defaultW = [
    0.212,
    1.2931,
    2.3065,
    8.2956,
    6.4133,
    0.8334,
    3.0194,
    0.001,
    1.8722,
    0.1666,
    0.796,
    1.4835,
    0.0614,
    0.2629,
    1.6483,
    0.6014,
    1.8729,
    0.5425,
    0.0912,
    0.0658,
    0.1542,
  ];

  static const List<List<double>> clips = [
    [0.001, 100], [0.001, 100], [0.001, 100], [0.001, 100],
    [1, 10], [0.001, 4], [0.001, 4], [0.001, 0.75],
    [0, 4.5], [0, 0.8], [0.001, 3.5],
    [0.001, 5], [0.001, 0.25], [0.001, 0.9], [0, 4],
    [0, 1], [1, 6],
    [0, 2], [0, 2], [0.01, 0.8], [0.1, 0.8],
  ];

  static const double _sMin = 0.001, _sMax = 36500.0, _dMin = 1.0, _dMax = 10.0;

  static String? validateWeights(List<double> w) {
    if (w.length != 21) {
      return '需要 21 个数字。你输入了 ${w.length} 个。请确认用的是 FSRS-6 的优化结果（旧版是 19 个）。';
    }
    for (var i = 0; i < 21; i++) {
      final v = w[i];
      if (!v.isFinite) return '第 ${i + 1} 个参数不是有效数字。';
      if (v < clips[i][0] || v > clips[i][1]) {
        return '第 ${i + 1} 个参数 $v 超出允许范围，已拒绝导入。';
      }
    }
    return null;
  }

  static List<double> parseWeights(String text) {
    final re = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
    return [for (final m in re.allMatches(text)) double.parse(m.group(0)!)];
  }

  static int dayIndexLocal(int tsMs) {
    final l = DateTime.fromMillisecondsSinceEpoch(tsMs);
    return DateTime.utc(l.year, l.month, l.day).millisecondsSinceEpoch ~/
        86400000;
  }

  static int dayIndexWithOffset(int tsMs, int tzOffsetMin) =>
      ((tsMs + tzOffsetMin * 60000) / 86400000).floor();

  static List<List<List<int>>> histories(Iterable<ReviewEvent> events,
      {int Function(int tsMs)? dayOf}) {
    final f = dayOf ?? dayIndexLocal;
    final by = <String, List<ReviewEvent>>{};
    for (final e in events) {
      (by[e.cardId] ??= []).add(e);
    }
    return [
      for (final list in by.values)
        (list..sort((a, b) => a.ts.compareTo(b.ts)))
            .map((e) => [f(e.ts), e.rating + 1])
            .toList()
    ];
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);
  static double _decay(List<double> w) => -w[20];
  static double _factor(List<double> w) =>
      math.exp(math.log(0.9) / _decay(w)) - 1.0;
  static double _retr(List<double> w, num t, double s) =>
      s <= 0 ? 1.0 : math.pow(1 + _factor(w) * t / s, _decay(w)).toDouble();
  static double _d0(List<double> w, int g) =>
      w[4] - math.exp(w[5] * (g - 1)) + 1.0;
  static double _nextD(List<double> w, double d, int g) {
    final nd = d + (-w[6] * (g - 3)) * (10 - d) / 9.0;
    return _clamp(w[7] * (_d0(w, 4) - nd) + nd, _dMin, _dMax);
  }

  static double _sFail(List<double> w, double s, double d, double r) => _clamp(
      w[11] *
          math.pow(d, -w[12]) *
          (math.pow(s + 1, w[13]) - 1) *
          math.exp(w[14] * (1 - r)),
      _sMin,
      _sMax);
  static double _sSucc(List<double> w, double s, double d, double r, int g) {
    final hp = g == 2 ? w[15] : 1.0;
    final eb = g == 4 ? w[16] : 1.0;
    return _clamp(
        s *
            (1 +
                math.exp(w[8]) *
                    (11 - d) *
                    math.pow(s, -w[9]) *
                    (math.exp(w[10] * (1 - r)) - 1) *
                    hp *
                    eb),
        _sMin,
        _sMax);
  }

  static double _sShort(List<double> w, double s, int g) {
    final sinc = math.pow(s, -w[19]) * math.exp(w[17] * (g - 3 + w[18]));
    return _clamp(s * (g >= 2 ? math.max(sinc, 1.0) : sinc), _sMin, _sMax);
  }

  static List<List<double>> replay(List<double> w, List<List<int>> ev) {
    final out = <List<double>>[];
    double? s, d;
    int? last;
    for (final e in ev) {
      final day = e[0], g = e[1];
      if (s == null) {
        s = w[g - 1];
        d = _clamp(_d0(w, g), _dMin, _dMax);
      } else {
        final dt = day - last!;
        if (dt == 0) {
          s = _sShort(w, s, g);
          d = _nextD(w, d!, g);
        } else {
          final r = _retr(w, dt, s);
          out.add([r, g > 1 ? 1.0 : 0.0]);
          s = g == 1
              ? math.min(_sFail(w, s, d!, r), s / math.exp(w[17] * w[18]))
              : _sSucc(w, s, d!, r, g);
          d = _nextD(w, d, g);
        }
      }
      last = day;
    }
    return out;
  }

  static ({double loss, int n}) logLoss(
      List<double> w, List<List<List<int>>> hist) {
    var tot = 0.0;
    var n = 0;
    for (final ev in hist) {
      for (final p in replay(w, ev)) {
        final q = _clamp(p[0], 1e-6, 1 - 1e-6);
        tot += -(p[1] * math.log(q) + (1 - p[1]) * math.log(1 - q));
        n++;
      }
    }
    return (loss: n == 0 ? double.nan : tot / n, n: n);
  }

  static WeightsCompare compare(List<double> current, List<double> candidate,
      List<List<List<int>>> hist) {
    final a = logLoss(current, hist);
    final b = logLoss(candidate, hist);
    return WeightsCompare(a.loss, b.loss, a.n);
  }

  static String buildCsv(Iterable<ReviewEvent> events) {
    final list = events.toList()
      ..sort((a, b) {
        final c = a.ts.compareTo(b.ts);
        return c != 0 ? c : a.cardId.compareTo(b.cardId);
      });
    final sb = StringBuffer('card_id,review_time,review_rating,review_state\n');
    for (final e in list) {
      sb.write('${e.cardId},${e.ts},${e.rating + 1},\n');
    }
    return sb.toString();
  }

  static ({int predictions, int forgets}) usable(List<List<List<int>>> hist) {
    var n = 0, f = 0;
    for (final ev in hist) {
      int? last;
      for (final e in ev) {
        if (last != null && e[0] != last) {
          n++;
          if (e[1] == 1) f++;
        }
        last = e[0];
      }
    }
    return (predictions: n, forgets: f);
  }
}
