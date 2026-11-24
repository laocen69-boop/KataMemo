/// FSRS 队列管理工具：负荷均衡（Load Balance）与断签温和顺延（Postpone）。
///
/// 严格放在 `Fsrs._applyScheduling` / `Fsrs.apply` 外层：
///   - 绝不修改 FSRS 公式本体（保证与官方 `fsrs-rs` 24 项 oracle 用例逐字对拍）；
///   - 顺延只改 `srs.due`，绝不改 `last_review` / `stability` / `difficulty` / `study_log`。
library;

import 'dart:math' as math;

import 'fsrs.dart';

/// 为复习卡挑选负载最轻的到期天数（Load Balance）。
///
/// [rawDays] 为 FSRS 原算出的间隔天数；[dayCounts] 为未来各天（相对今天的天数偏移）
/// 当前已排的到期复习卡数。间隔低于 [minDaysForBalance]（默认 4 天）直接原样返回，
/// 避免扰动短间隔记忆巩固；否则在 `±5%`（至少 `±1` 天，上限 `7` 天）窗口内选最少的一天，
/// 相等时优先离 [rawDays] 最近的天数。
int chooseBalancedDays(
  int rawDays,
  Map<int, int> dayCounts, {
  int minDaysForBalance = 4,
}) {
  if (rawDays < minDaysForBalance) return rawDays;
  final delta = math.max(1, (rawDays * 0.05).round()).clamp(1, 7);
  final lo = math.max(2, rawDays - delta);
  final hi = rawDays + delta;

  var bestDay = rawDays;
  var bestCount = dayCounts[rawDays] ?? 0;
  for (var d = lo; d <= hi; d++) {
    final c = dayCounts[d] ?? 0;
    final dist = (d - rawDays).abs();
    final bestDist = (bestDay - rawDays).abs();
    final symPreferRight =
        c == bestCount && dist == bestDist && bestDay != rawDays && ((rawDays + c) & 1) == 1 && d > bestDay;
    if (c < bestCount || (c == bestCount && dist < bestDist) || symPreferRight) {
      bestCount = c;
      bestDay = d;
    }
  }
  return bestDay;
}

/// 规划断签逾期复习卡的顺延排期（Postpone）。
///
/// 只应传入 `state == review` 且已逾期的复习卡：当提供 [nowMs] 与 [lastReviewByCard] 时，
/// 按当前预测可提取性 $R(t, S)$ 从高到低排序（保留率越高越安全，最先顺延），
/// 否则退化为按稳定度 [stability] 降序；取前 `ratio` 比例均匀摊到
/// `[tomorrowStartMs, tomorrowStartMs + postponeDays - 1]` 每天的 08:00。
List<({String cardId, int newDueMs})> planPostpone(
  List<({String cardId, double stability, int dueMs})> overdueReviewCards, {
  required int postponeDays,
  required double ratio,
  required int tomorrowStartMs,
  int? nowMs,
  Map<String, int>? lastReviewByCard,
}) {
  if (overdueReviewCards.isEmpty || postponeDays <= 0 || ratio <= 0) {
    return const [];
  }
  final sorted = [...overdueReviewCards];
  if (nowMs != null && lastReviewByCard != null) {
    double retrOf(({String cardId, double stability, int dueMs}) c) {
      final lr = lastReviewByCard[c.cardId];
      if (lr == null || lr >= nowMs) return 1.0;
      final elapsed = (nowMs - lr) / Duration.millisecondsPerDay;
      return Fsrs.retrievability(elapsed, c.stability);
    }

    sorted.sort((a, b) {
      final cmp = retrOf(b).compareTo(retrOf(a));
      return cmp != 0 ? cmp : b.stability.compareTo(a.stability);
    });
  } else {
    sorted.sort((a, b) => b.stability.compareTo(a.stability));
  }
  final count = (sorted.length * ratio).round().clamp(1, sorted.length);
  const eightHoursMs = 8 * Duration.millisecondsPerHour;
  final out = <({String cardId, int newDueMs})>[];
  for (var i = 0; i < count; i++) {
    final dayOffset = i % postponeDays;
    final newDueMs = tomorrowStartMs +
        dayOffset * Duration.millisecondsPerDay +
        eightHoursMs;
    out.add((cardId: sorted[i].cardId, newDueMs: newDueMs));
  }
  return out;
}
