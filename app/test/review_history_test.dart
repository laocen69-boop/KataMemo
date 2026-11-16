import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/ratings.dart';
import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/review_history.dart';

typedef _Day = ({DateTime day, int dayNo, int rating});

List<_Day> _days(int count) => List.generate(
      count,
      (i) => (day: DateTime.utc(2026, 1, i + 1), dayNo: i + 1, rating: i % 4),
    );

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Finder _withPrefix(String prefix) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });

List<int> _indices(String prefix) => _withPrefix(prefix)
    .evaluate()
    .map((element) => int.parse(
        (element.widget.key! as ValueKey<String>).value.substring(prefix.length)))
    .toList();

String _date(DateTime day) => '${day.year}年${day.month}月${day.day}日';
String _monthKey(DateTime day) => 'history-month-${day.year * 12 + day.month}';

Finder _textIn(Finder parent, String text) =>
    find.descendant(of: parent, matching: find.text(text));

Future<void> _pumpHistory(
  WidgetTester tester,
  List<_Day> days, {
  String cardId = 'card-a',
  int? logs,
  List<int> today = const [],
  double width = 380,
  bool dark = false,
  double textScale = 1,
}) async {

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? KColors.dark : KColors.light],
      splashFactory: NoSplash.splashFactory,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Container(
              padding: const EdgeInsets.all(15),
              child: ReviewHistory(
                key: const ValueKey('review-history-under-test'),
                cardId: cardId,
                days: days,
                logs: logs ?? days.length + today.length,
                today: today,
              ),
            ),
          ),
        ),
      ),
    ),
  ));

  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectDots(List<int> indices) {
  expect(_indices('history-dot-'), orderedEquals(indices));
  for (final index in indices) {
    expect(_key('history-dot-$index'), findsOneWidget);
  }
}

void _expectSelection(_Day day, {String? interval}) {
  final detail = _key('history-selection');
  expect(detail, findsOneWidget);
  expect(_textIn(detail, _date(day.day)), findsOneWidget);
  expect(_textIn(detail, '当日首次 · ${ratingName(day.rating)}'), findsOneWidget);
  if (interval != null) {
    expect(_textIn(detail, interval), findsOneWidget);
  }
}

void _expectPaging(WidgetTester tester,
    {required bool older, required bool newer}) {
  expect(tester.widget<TextButton>(_key('history-older')).onPressed != null,
      older);
  expect(tester.widget<TextButton>(_key('history-newer')).onPressed != null,
      newer);
}

void _expectAllClosed() {
  expect(_textIn(_key('history-all'), '全部记录 ↗'), findsOneWidget);
  expect(_withPrefix('history-month-'), findsNothing);
  expect(_withPrefix('history-record-'), findsNothing);
}

Future<void> _openOlderMonth(WidgetTester tester, List<_Day> days) async {
  await _tap(tester, 'history-older');
  await _tap(tester, 'history-dot-1');
  await _tap(tester, 'history-all');
  await _tap(tester, _monthKey(days.first.day));
  _expectSelection(days[1]);
  expect(_withPrefix('history-record-'), findsNWidgets(days.length));
}

void main() {
  testWidgets('空历史不显示轨迹、详情或按钮', (tester) async {
    await _pumpHistory(tester, const [], logs: 0);
    expect(find.text('复习轨迹'), findsNothing);
    expect(_withPrefix('history-'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单日默认选中，首次学习、次数与当天补答分开显示', (tester) async {
    final days = <_Day>[
      (day: DateTime.utc(2026, 10, 27), dayNo: 1, rating: 2),
    ];
    await _pumpHistory(tester, days, logs: 4, today: [0, 1, 3]);
    _expectDots([0]);
    _expectSelection(days.single, interval: '首次学习');
    expect(_textIn(_key('history-selection'), '当日首次 · 认识'), findsOneWidget);
    expect(find.text('记得'), findsNothing);
    expect(find.text('1 天 · 1 个学习日 · 4 次作答'), findsOneWidget);
    expect(find.text('今天又答了 3 次'), findsOneWidget);
    expect(find.text('最近 1 个学习日'), findsOneWidget);
    _expectPaging(tester, older: false, newer: false);
    _expectAllClosed();

    await _tap(tester, 'history-older');
    await _tap(tester, 'history-newer');
    _expectDots([0]);
    _expectSelection(days.single, interval: '首次学习');
    expect(tester.takeException(), isNull);
  });

  testWidgets('长历史仅绘最近六个等距点，不按真实日期间隔拉开', (tester) async {
    final days = List<_Day>.generate(
      30,
      (i) => (
        day: DateTime.utc(2024, 1, 1 + i * i),
        dayNo: 1 + i * i,
        rating: i % 4,
      ),
    );
    await _pumpHistory(tester, days, logs: 91);
    _expectDots([24, 25, 26, 27, 28, 29]);
    _expectSelection(days.last, interval: '间隔 57 天');
    expect(find.text('842 天 · 30 个学习日 · 91 次作答'), findsOneWidget);
    expect(find.text('最近 6 个学习日'), findsOneWidget);
    expect(find.textContaining('今天又答了'), findsNothing);
    final centers = [
      for (var i = 24; i < 30; i++) tester.getCenter(_key('history-dot-$i')),
    ];
    final step = centers[1].dx - centers[0].dx;
    for (var i = 1; i < centers.length; i++) {
      expect(centers[i].dx - centers[i - 1].dx, closeTo(step, 0.01));
      expect(centers[i].dy, closeTo(centers[0].dy, 0.01));
    }
  });

  testWidgets('点较早日期更新唯一详情与选中语义，圆点支持读屏点击', (tester) async {
    final semantics = tester.ensureSemantics();
    final days = _days(13);
    await _pumpHistory(tester, days);
    _expectSelection(days[12]);
    await _tap(tester, 'history-dot-10');
    _expectSelection(days[10], interval: '间隔 1 天');
    expect(_textIn(_key('history-selection'), _date(days[12].day)), findsNothing);
    _expectDots([7, 8, 9, 10, 11, 12]);

    final selected = find.bySemanticsLabel('2026年1月11日，认识，间隔 1 天');
    final previous = find.bySemanticsLabel('2026年1月13日，困难，间隔 1 天');
    expect(selected, findsOneWidget);
    expect(previous, findsOneWidget);
    expect(
        tester.getSemantics(previous),
        matchesSemantics(
            hasSelectedState: true,
            isSelected: false,
            isButton: true,
            hasTapAction: true,
            label: '2026年1月13日，困难，间隔 1 天'));

    expect(
      tester.getSemantics(selected),
      matchesSemantics(
        label: '2026年1月11日，认识，间隔 1 天',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('间隔按日历日期计算，覆盖不足24小时、闰日与跨年', (tester) async {
    final days = <_Day>[
      (day: DateTime.utc(2024, 2, 28, 23, 55), dayNo: 1, rating: 0),
      (day: DateTime.utc(2024, 2, 29, 0, 5), dayNo: 2, rating: 1),
      (day: DateTime.utc(2024, 3, 1, 0, 1), dayNo: 3, rating: 2),
      (day: DateTime.utc(2024, 12, 31, 23, 58), dayNo: 308, rating: 3),
      (day: DateTime.utc(2025, 1, 1, 0, 2), dayNo: 309, rating: 2),
    ];
    await _pumpHistory(tester, days);
    _expectSelection(days[4], interval: '间隔 1 天');
    for (final index in [1, 2]) {
      await _tap(tester, 'history-dot-$index');
      _expectSelection(days[index], interval: '间隔 1 天');
    }
    await _tap(tester, 'history-dot-3');
    _expectSelection(days[3], interval: '间隔 305 天');
    await _tap(tester, 'history-dot-0');
    _expectSelection(days[0], interval: '首次学习');
    expect(find.text('间隔 0 天'), findsNothing);
  });

  testWidgets('四种评分在选中详情和月记录中统一使用 ratingName', (tester) async {
    final days = _days(4);
    await _pumpHistory(tester, days);
    for (var i = 0; i < days.length; i++) {
      await _tap(tester, 'history-dot-$i');
      _expectSelection(days[i]);
    }
    await _tap(tester, 'history-all');
    await _tap(tester, _monthKey(days.first.day));
    for (var i = 0; i < days.length; i++) {
      expect(_textIn(_key('history-record-$i'), '当日首次 · ${ratingName(i)}'), findsOneWidget);
    }
    expect(_textIn(_key('history-record-2'), '当日首次 · 认识'), findsOneWidget);
    expect(find.text('记得'), findsNothing);
  });

  testWidgets('13日分段为8至13、2至7、1，边界禁用并可完整返回', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final visited = <int>[];
    _expectDots([7, 8, 9, 10, 11, 12]);
    visited.addAll(_indices('history-dot-'));
    _expectPaging(tester, older: true, newer: false);
    await _tap(tester, 'history-newer');
    _expectSelection(days[12]);

    await _tap(tester, 'history-older');
    _expectDots([1, 2, 3, 4, 5, 6]);
    visited.addAll(_indices('history-dot-'));
    _expectSelection(days[6], interval: '间隔 1 天');
    expect(find.text('第 2—7 个学习日'), findsOneWidget);
    _expectPaging(tester, older: true, newer: true);
    await _tap(tester, 'history-dot-1');

    _expectSelection(days[1], interval: '间隔 1 天');

    await _tap(tester, 'history-older');
    _expectDots([0]);
    visited.addAll(_indices('history-dot-'));
    _expectSelection(days[0], interval: '首次学习');
    expect(find.text('第 1—1 个学习日'), findsOneWidget);
    _expectPaging(tester, older: false, newer: true);
    await _tap(tester, 'history-older');
    _expectDots([0]);
    _expectSelection(days[0]);
    expect(visited, hasLength(13));
    expect(visited.toSet(), hasLength(13), reason: '分段不能重复覆盖同一个学习日');
    expect(visited, unorderedEquals(List.generate(13, (i) => i)));

    await _tap(tester, 'history-newer');
    _expectDots([1, 2, 3, 4, 5, 6]);
    _expectSelection(days[6]);
    await _tap(tester, 'history-newer');
    _expectDots([7, 8, 9, 10, 11, 12]);
    _expectSelection(days[12]);
    _expectPaging(tester, older: true, newer: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部记录跨年按月倒序，只有点开的月份展示行且无重复遗漏', (tester) async {
    final days = <_Day>[
      (day: DateTime.utc(2025, 1, 5), dayNo: 1, rating: 0),
      (day: DateTime.utc(2025, 12, 30), dayNo: 360, rating: 1),
      (day: DateTime.utc(2025, 12, 31), dayNo: 361, rating: 2),
      (day: DateTime.utc(2026, 1, 1), dayNo: 362, rating: 3),
      (day: DateTime.utc(2026, 1, 20), dayNo: 381, rating: 0),
      (day: DateTime.utc(2026, 2, 1), dayNo: 393, rating: 1),
      (day: DateTime.utc(2026, 2, 2), dayNo: 394, rating: 2),
    ];
    await _pumpHistory(tester, days);
    _expectAllClosed();
    await _tap(tester, 'history-all');
    expect(find.text('按学习日汇总 · 评分为当天首次作答'), findsOneWidget);
    final groups = <int, List<int>>{
      2026 * 12 + 2: [6, 5],
      2026 * 12 + 1: [4, 3],
      2025 * 12 + 12: [2, 1],
      2025 * 12 + 1: [0],
    };
    expect(_indices('history-month-'), orderedEquals(groups.keys));
    expect(_withPrefix('history-record-'), findsNothing);
    final monthTops = [
      for (final id in groups.keys) tester.getTopLeft(_key('history-month-$id')).dy,
    ];
    for (var i = 1; i < monthTops.length; i++) {
      expect(monthTops[i], greaterThan(monthTops[i - 1]));
    }
    final seen = <int>[];
    for (final group in groups.entries) {
      final month = _key('history-month-${group.key}');
      final date = days[group.value.first].day;
      expect(
          _textIn(month,
              '${date.year}年${date.month}月 · ${group.value.length} 个学习日'),
          findsOneWidget);
      await _tap(tester, 'history-month-${group.key}');
      expect(_indices('history-record-'), orderedEquals(group.value));
      seen.addAll(_indices('history-record-'));
      for (final index in group.value) {
        final row = _key('history-record-$index');
        expect(row, findsOneWidget);
        expect(_textIn(row, _date(days[index].day)), findsOneWidget);
        expect(_textIn(row, '当日首次 · ${ratingName(days[index].rating)}'), findsOneWidget);
      }
      _expectSelection(days.last);
      await _tap(tester, 'history-month-${group.key}');
      expect(_withPrefix('history-record-'), findsNothing);
    }
    expect(seen, orderedEquals([6, 5, 4, 3, 2, 1, 0]));
    expect(seen.toSet(), hasLength(days.length));
    await _tap(tester, 'history-all');
    _expectAllClosed();
  });

  testWidgets('复用组件更换cardId，即使日期数据完全相同也复位并关闭月份', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final state = tester.state(find.byType(ReviewHistory));
    await _openOlderMonth(tester, days);

    await _pumpHistory(tester, days, cardId: 'card-b');
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([7, 8, 9, 10, 11, 12]);
    _expectSelection(days.last);
    _expectPaging(tester, older: true, newer: false);
    _expectAllClosed();
    await _tap(tester, 'history-all');
    expect(_withPrefix('history-month-'), findsOneWidget);
    expect(_withPrefix('history-record-'), findsNothing,
        reason: '换卡不仅隐藏全部记录，还要清空月份展开状态');
  });

  testWidgets('增加学习日时复位最新段与选择并清除展开状态', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final state = tester.state(find.byType(ReviewHistory));
    await _openOlderMonth(tester, days);
    final added = [...days, (day: DateTime.utc(2026, 1, 14), dayNo: 14, rating: 3)];
    await _pumpHistory(tester, added);
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([8, 9, 10, 11, 12, 13]);
    _expectSelection(added.last);
    _expectPaging(tester, older: true, newer: false);
    _expectAllClosed();
    await _tap(tester, 'history-all');
    expect(_withPrefix('history-record-'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('撤销缩短至单日或空历史不越界，重新有数据时仍选最新', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final state = tester.state(find.byType(ReviewHistory));
    await _openOlderMonth(tester, days);

    await _pumpHistory(tester, days.take(1).toList());
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([0]);
    _expectSelection(days.first, interval: '首次学习');
    _expectPaging(tester, older: false, newer: false);
    _expectAllClosed();
    expect(tester.takeException(), isNull);

    await _pumpHistory(tester, const []);
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    expect(_withPrefix('history-'), findsNothing);
    expect(tester.takeException(), isNull);
    await _pumpHistory(tester, days);
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([7, 8, 9, 10, 11, 12]);
    _expectSelection(days.last);
    _expectAllClosed();
    await _tap(tester, 'history-all');
    expect(_withPrefix('history-record-'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新list与新DateTime但值相同，更新次数不重置选择、分段或月份', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final state = tester.state(find.byType(ReviewHistory));
    await _openOlderMonth(tester, days);
    final equalDays = <_Day>[
      for (final item in days)
        (
          day: DateTime.utc(item.day.year, item.day.month, item.day.day),
          dayNo: item.dayNo,
          rating: item.rating,
        ),
    ];
    expect(identical(equalDays, days), isFalse);
    expect(identical(equalDays.first.day, days.first.day), isFalse);
    await _pumpHistory(tester, equalDays, logs: 40, today: [3, 2]);
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([1, 2, 3, 4, 5, 6]);
    _expectSelection(days[1]);
    _expectPaging(tester, older: true, newer: true);
    expect(_textIn(_key('history-all'), '收起记录'), findsOneWidget);
    expect(_indices('history-record-'), orderedEquals(List.generate(13, (i) => 12 - i)));
    expect(find.text('13 天 · 13 个学习日 · 40 次作答'), findsOneWidget);
    expect(find.text('今天又答了 2 次'), findsOneWidget);
  });

  testWidgets('条数不变但评分数据变化仍须复位，不能只比较length', (tester) async {
    final days = _days(13);
    await _pumpHistory(tester, days);
    final state = tester.state(find.byType(ReviewHistory));
    await _openOlderMonth(tester, days);
    final changed = [...days];
    changed[12] = (day: days[12].day, dayNo: days[12].dayNo, rating: 3);
    await _pumpHistory(tester, changed);
    expect(tester.state(find.byType(ReviewHistory)), same(state));
    _expectDots([7, 8, 9, 10, 11, 12]);
    _expectSelection(changed.last);
    _expectAllClosed();
    await _tap(tester, 'history-all');
    expect(_withPrefix('history-record-'), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('320px ${dark ? 'dark' : 'light'} ${scale}x：260px内容无溢出且触点不重叠',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final days = List<_Day>.generate(
          13,
          (i) => (
            day: DateTime.utc(2024, 12, 20 + i * i),
            dayNo: 1 + i * i,
            rating: i % 4,
          ),
        );
        await _pumpHistory(tester, days,
            width: 320, dark: dark, textScale: scale, logs: 125, today: [2, 3]);
        final history = find.byType(ReviewHistory);
        final context = tester.element(history);
        expect(Theme.of(context).extension<KColors>(),
            dark ? KColors.dark : KColors.light);
        expect(MediaQuery.textScalerOf(context).scale(10), closeTo(10 * scale, 0.01));
        expect(tester.getSize(history).width, closeTo(260, 0.01));
        _expectDots([7, 8, 9, 10, 11, 12]);
        final rects = [
          for (var i = 7; i <= 12; i++) tester.getRect(_key('history-dot-$i')),
        ];
        for (final rect in rects) {
          expect(rect.width, greaterThanOrEqualTo(40));
          expect(rect.height, greaterThanOrEqualTo(40));
        }
        for (var i = 1; i < rects.length; i++) {
          final previous = rects[i - 1];
          final current = rects[i];
          expect(current.center.dx - previous.center.dx, greaterThan(20));
          expect(current.center.dx - previous.center.dx, closeTo(260 / 6, 0.01));
          expect(previous.right, lessThanOrEqualTo(current.left + 0.01));
        }
        for (final key in ['history-all', 'history-older', 'history-newer']) {
          final size = tester.getSize(_key(key));
          expect(size.width, greaterThanOrEqualTo(40));
          expect(size.height, greaterThanOrEqualTo(40));
        }
        expect(tester.takeException(), isNull);
        for (var i = 7; i <= 12; i++) {
          await _tap(tester, 'history-dot-$i');
          _expectSelection(days[i]);
          expect(tester.takeException(), isNull);
        }
        await _tap(tester, 'history-older');
        _expectDots([1, 2, 3, 4, 5, 6]);
        expect(tester.takeException(), isNull);
        await _tap(tester, 'history-older');
        _expectDots([0]);
        _expectPaging(tester, older: false, newer: true);
        expect(tester.takeException(), isNull);
        await _tap(tester, 'history-newer');
        await _tap(tester, 'history-newer');
        _expectSelection(days.last);
        expect(tester.takeException(), isNull);
        await _tap(tester, 'history-all');
        expect(tester.takeException(), isNull);
        final monthKeys = [
          for (final id in _indices('history-month-')) 'history-month-$id',
        ];
        for (final key in monthKeys) {
          final size = tester.getSize(_key(key));
          expect(size.width, greaterThanOrEqualTo(40));
          expect(size.height, greaterThanOrEqualTo(40));
          await _tap(tester, key);
          expect(tester.takeException(), isNull);
          await _tap(tester, key);
          expect(tester.takeException(), isNull);
        }
        await _tap(tester, 'history-all');
        _expectAllClosed();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
