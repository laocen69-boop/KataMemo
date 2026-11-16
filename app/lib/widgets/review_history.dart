import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../ratings.dart';
import '../theme/k_colors.dart';

class ReviewHistory extends StatefulWidget {
  const ReviewHistory({
    super.key,
    required this.cardId,
    required this.days,
    required this.logs,
    required this.today,
  });

  final String cardId;
  final List<({DateTime day, int dayNo, int rating})> days;
  final int logs;
  final List<int> today;

  @override
  State<ReviewHistory> createState() => _ReviewHistoryState();
}

class _ReviewHistoryState extends State<ReviewHistory> {
  static const _pageSize = 6;
  int _page = 0;
  int _selected = 0;
  bool _showAll = false;
  final Set<int> _expandedMonths = {};

  int get _end => widget.days.length - _page * _pageSize;
  int get _start => math.max(0, _end - _pageSize);

  @override
  void initState() {
    super.initState();
    _selected = math.max(0, widget.days.length - 1);
  }

  @override
  void didUpdateWidget(covariant ReviewHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId ||
        !listEquals(oldWidget.days, widget.days)) {
      _page = 0;
      _selected = math.max(0, widget.days.length - 1);
      _showAll = false;
      _expandedMonths.clear();
    }
  }

  void _turnPage(int delta) => setState(() {
        _page += delta;
        _selected = _end - 1;
      });

  String _date(DateTime day, {bool year = false}) =>
      '${year ? '${day.year}年' : ''}${day.month}月${day.day}日';

  String _interval(int index) {
    if (index == 0) return '首次学习';
    final day = widget.days[index].day;
    final previous = widget.days[index - 1].day;

    final gap = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(previous.year, previous.month, previous.day))
        .inDays;
    return '间隔 $gap 天';
  }

  ButtonStyle _textButtonStyle(BuildContext context) => TextButton.styleFrom(
        foregroundColor: context.k.deep,
        disabledForegroundColor: context.k.faint,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        textStyle: const TextStyle(fontSize: 12),
      );

  Widget _rating(int rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: ratingColor(rating)),
          ),
          const SizedBox(width: 6),
          Text('当日首次 · ${ratingName(rating)}',
              style: TextStyle(fontSize: 13, color: context.k.text)),
        ],
      );

  Widget _detail(int index, {Key? key}) {
    final day = widget.days[index];
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(_date(day.day, year: true),
              style: TextStyle(fontSize: 13, color: context.k.text)),
          _rating(day.rating),
          Text(_interval(index),
              style: TextStyle(fontSize: 12, color: context.k.t3)),
        ],
      ),
    );
  }

  Widget _rail() => LayoutBuilder(builder: (context, constraints) {
        final count = _end - _start;
        final cellWidth = constraints.maxWidth / count;
        return SizedBox(
          height: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (count > 1)
                Positioned(
                  left: cellWidth / 2,
                  right: cellWidth / 2,
                  top: 22,
                  child: Container(height: 1, color: context.k.line),
                ),
              Row(
                children: [
                  for (var i = _start; i < _end; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: _selected == i,

                        onTap: () => setState(() => _selected = i),
                        label: '${_date(widget.days[i].day, year: true)}，'
                            '${ratingName(widget.days[i].rating)}，${_interval(i)}',
                        child: ExcludeSemantics(
                          child: InkWell(
                            key: ValueKey('history-dot-$i'),
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => setState(() => _selected = i),
                            child: SizedBox(
                              height: 52,
                              child: Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  Positioned(
                                    top: 12,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: context.k.surface,
                                        border: Border.all(
                                          color: _selected == i
                                              ? ratingColor(widget.days[i].rating)
                                              : context.k.surface,
                                        ),
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: ratingColor(widget.days[i].rating),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_selected == i)
                                    Positioned(
                                      bottom: 5,
                                      child: Container(
                                        width: 3,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: context.k.t3,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      });

  List<Widget> _months() {
    final groups = <int, List<int>>{};
    for (var i = widget.days.length - 1; i >= 0; i--) {
      final date = widget.days[i].day;
      (groups[date.year * 12 + date.month] ??= []).add(i);
    }
    return [
      for (final entry in groups.entries) ...[
        Divider(height: 1, thickness: 0.5, color: context.k.line),
        Semantics(
          expanded: _expandedMonths.contains(entry.key),
          child: TextButton(
            key: ValueKey('history-month-${entry.key}'),
            style: _textButtonStyle(context),
            onPressed: () => setState(() {
              if (!_expandedMonths.add(entry.key)) {
                _expandedMonths.remove(entry.key);
              }
            }),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.days[entry.value.first].day.year}年'
                    '${widget.days[entry.value.first].day.month}月'
                    ' · ${entry.value.length} 个学习日',
                    style: TextStyle(color: context.k.t3),
                  ),
                ),
                Icon(
                    _expandedMonths.contains(entry.key)
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18),
              ],
            ),
          ),
        ),
        if (_expandedMonths.contains(entry.key))
          for (final index in entry.value)
            _detail(index, key: ValueKey('history-record-$index')),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) return const SizedBox.shrink();
    final k = context.k;
    final first = widget.days[_start].day;
    final last = widget.days[_end - 1].day;
    final crossYear = first.year != last.year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('复习轨迹',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: k.text)),
            ),
            Semantics(
              expanded: _showAll,
              child: TextButton(
                key: const ValueKey('history-all'),
                style: _textButtonStyle(context),
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? '收起记录' : '全部记录 ↗'),
              ),
            ),
          ],
        ),
        Text(
          '${widget.days.last.dayNo} 天 · ${widget.days.length} 个学习日'
          ' · ${widget.logs} 次作答',
          style: TextStyle(fontSize: 12, color: k.t3),
        ),
        if (widget.today.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('今天又答了 ${widget.today.length} 次',
                style: TextStyle(fontSize: 12, color: k.t3)),
          ),
        const SizedBox(height: 14),
        _rail(),
        Row(
          mainAxisAlignment: _end - _start == 1
              ? MainAxisAlignment.center
              : MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Text(_date(first, year: crossYear),
                    style: TextStyle(fontSize: 11, color: k.t3))),
            if (_end - _start > 1) ...[
              const SizedBox(width: 8),
              Flexible(
                  child: Text(_date(last, year: crossYear),
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 11, color: k.t3))),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Divider(height: 1, thickness: 0.5, color: k.line),
        Semantics(
          liveRegion: true,
          child: _detail(_selected, key: const ValueKey('history-selection')),
        ),
        Divider(height: 1, thickness: 0.5, color: k.line),
        Row(
          children: [
            TextButton(
              key: const ValueKey('history-older'),
              style: _textButtonStyle(context),
              onPressed: _start > 0 ? () => _turnPage(1) : null,
              child: const Text('‹ 较早'),
            ),
            Expanded(
              child: Text(
                _page == 0
                    ? '最近 ${_end - _start} 个学习日'
                    : '第 ${_start + 1}—$_end 个学习日',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: k.t3),
              ),
            ),
            TextButton(
              key: const ValueKey('history-newer'),
              style: _textButtonStyle(context),
              onPressed: _page > 0 ? () => _turnPage(-1) : null,
              child: const Text('较近 ›'),
            ),
          ],
        ),
        if (_showAll) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('按学习日汇总 · 评分为当天首次作答',
                style: TextStyle(fontSize: 12, color: k.t3)),
          ),
          ..._months(),
        ],
      ],
    );
  }
}
