part of 'models.dart';

enum MemoryBand { none, fresh, weak, fair, good, strong, solid, mastered }

typedef MemoryBands = ({
  int mastered,
  int familiar,
  int fair,
  int weak,
  int newSel,
});

extension MemoryBandsX on MemoryBands {
  int get all => mastered + familiar + fair + weak + newSel;
}

const MemoryBands kEmptyBands =
    (mastered: 0, familiar: 0, fair: 0, weak: 0, newSel: 0);

class MemoryStrength {

  final double days;
  const MemoryStrength(this.days);

  factory MemoryStrength.of({double? stability, int? reps}) =>
      MemoryStrength((reps == null || reps == 0) ? 0 : (stability ?? 0));

  static const MemoryStrength unknown = MemoryStrength(0);

  double get fill {
    if (days <= 0) return 0;
    final v = math.log(1 + days) / math.log(1 + 365);
    return v.clamp(0.06, 1.0);
  }

  MemoryBand get band {
    if (days <= 0) return MemoryBand.none;
    if (days < 1) return MemoryBand.fresh;
    if (days < 3) return MemoryBand.weak;
    if (days < 7) return MemoryBand.fair;
    if (days < 21) return MemoryBand.good;
    if (days < 60) return MemoryBand.strong;
    if (days < 180) return MemoryBand.solid;
    return MemoryBand.mastered;
  }

  String get label {
    if (days <= 0) return '还没学过';
    if (days < 1) return '刚学，今天还要再见';
    if (days < 30) return '约可记住 ${days.round()} 天';
    if (days < 365) return '约可记住 ${(days / 30).round()} 个月';
    final y = days / 365;
    return '约可记住 ${y < 10 ? y.toStringAsFixed(1) : y.round()} 年';
  }

  String get shortLabel {
    if (days <= 0) return '未学';
    if (days < 1) return '今天';
    if (days < 30) return '${days.round()} 天';
    if (days < 365) return '${(days / 30).round()} 个月';
    final y = days / 365;
    return '${y < 10 ? y.toStringAsFixed(1) : y.round()} 年';
  }
}
