import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/models.dart';
import 'package:katamemo/widgets/tappable_text.dart';

void main() {
  group('MemoryStrength（记忆强度圆环）', () {
    test('填充随天数单调增加，且刚学的只有一小点', () {
      final fresh = const MemoryStrength(0.4).fill;
      final week = const MemoryStrength(7).fill;
      final year = const MemoryStrength(365).fill;
      expect(fresh, lessThan(week));
      expect(week, lessThan(year));

      expect(fresh, greaterThan(0));
      expect(fresh, lessThan(0.15));
      expect(year, 1.0);
    });

    test('对数尺度：早期进步可见，后期不再明显', () {

      final jump =
          const MemoryStrength(7).fill - const MemoryStrength(0.5).fill;
      expect(jump, greaterThan(0.2));

      final tail =
          const MemoryStrength(365).fill - const MemoryStrength(180).fill;
      expect(tail, lessThan(0.15));
    });

    test('档位阈值就是统计页用的那几档天数', () {
      MemoryBand at(double d) => MemoryStrength(d).band;
      expect(at(0), MemoryBand.none);
      expect(at(0.9), MemoryBand.fresh);
      expect(at(2.9), MemoryBand.weak);
      expect(at(6.9), MemoryBand.fair);
      expect(at(20.9), MemoryBand.good);
      expect(at(59.9), MemoryBand.strong);
      expect(at(179.9), MemoryBand.solid);
      expect(at(180), MemoryBand.mastered);
      expect(at(3650), MemoryBand.mastered);
    });

    test('标签说的是「能记住多少天」，不是「复习中」这种标签', () {
      expect(const MemoryStrength(0).label, '还没学过');
      expect(const MemoryStrength(0.5).label, contains('今天'));
      expect(const MemoryStrength(7).label, '约可记住 7 天');
      expect(const MemoryStrength(60).label, '约可记住 2 个月');
      expect(const MemoryStrength(730).label, '约可记住 2.0 年');
    });

    test('列表短标签更短——一行里还要放词形和中文', () {
      expect(const MemoryStrength(0).shortLabel, '未学');
      expect(const MemoryStrength(0.5).shortLabel, '今天');
      expect(const MemoryStrength(7).shortLabel, '7 天');
      expect(const MemoryStrength(90).shortLabel, '3 个月');
      expect(const MemoryStrength(730).shortLabel, '2.0 年');
    });

    test('没有 srs 行 = 还没学（不能误报成「今天要再见」）', () {
      final none = MemoryStrength.of(stability: 12.5, reps: 0);
      expect(none.days, 0);
      expect(none.band, MemoryBand.none);
    });
  });

  group('isTappableId（只有印尼语单词可点）', () {
    test('普通词形可点', () {
      for (final w in ['makan', 'absén', 'anak-anak', 'ke-2', 'Makan']) {
        expect(isTappableId(w), isTrue, reason: w);
      }
    });

    test('中文一律不可点 —— 用户实测报的就是这条', () {
      for (final w in [
        '墙壁',
        '他缺课了',
        '妈妈看makan',
        'makan吃',
        '。',
        '“中文”',
        '...'
      ]) {
        expect(isTappableId(w), isFalse, reason: w);
      }

      expect(isTappableId('“lah,'), isTrue);
    });

    test('首尾标点剥掉后仍可点（句子里的词本来就带标点）', () {
      for (final w in ['makan,', '(makan)', '“makan”', 'makan.', 'makan?']) {
        expect(isTappableId(w), isTrue, reason: w);
      }
    });

    test('混合串里的印尼语单词**不**单独可点', () {

      expect(isTappableId('妈妈看makan'), isFalse);
      expect(isTappableId('makan看'), isFalse);
    });
  });
}
