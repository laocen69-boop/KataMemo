library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart';
import '../ratings.dart';
import 'speak_button.dart' show kSpeakGreen;

bool _daySheetOpen = false;

Future<void> showDayStatsSheet(BuildContext context, DateTime day) async {
  if (_daySheetOpen) return;
  _daySheetOpen = true;
  try {
    await _showDayStatsSheetBody(context, day);
  } finally {
    _daySheetOpen = false;
  }
}

Future<void> _showDayStatsSheetBody(BuildContext context, DateTime day) async {
  final app = context.read<AppState>();
  final DayStats s = await app.db.dayStatsAt(day);

  final signed = await app.db.isSignedDay(day);
  if (!context.mounted) return;
  const wk = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final title = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')} · ${wk[day.weekday - 1]}';
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (s.isEmpty && !signed)
              Text('这天没有学习记录',
                  style: TextStyle(fontSize: 13, color: context.k.nT2))
            else ...[

              if (signed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    Icon(Icons.check_circle, size: 16, color: kSpeakGreen),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('这天完成了全部学习任务（已自动签到）',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kSpeakGreen)),
                    ),
                  ]),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${s.words}',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: kSpeakGreen)),
                  const SizedBox(width: 4),
                  const Text('词', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 14),
                  Text('作答 ${s.answers} 次',
                      style: TextStyle(fontSize: 13, color: context.k.nT2)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _DayChip(label: '新学', value: s.newWords, color: kSpeakGreen),
                  const SizedBox(width: 8),
                  _DayChip(
                      label: '复习',
                      value: s.reviewWords,
                      color: const Color(0xFF7A8B99)),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DayChip(label: '轻松', value: s.easy, color: kRatingEasy),
                  _DayChip(label: '记得', value: s.know, color: kRatingKnow),
                  _DayChip(label: '模糊', value: s.fuzzy, color: kRatingFuzzy),
                  _DayChip(label: '困难', value: s.forget, color: kRatingForget),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '四档按「当天这个词第一次怎么答的」分档（与统计页趋势同一条口径，'
                '趋势图也是这四条线）；「词」是去重后的个数，'
                '「次」是作答次数（同一张卡答几遍算几次）。',
                style: TextStyle(
                    fontSize: 11.5, color: context.k.nFaint2, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DayChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _DayChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 6),
          Text('$value',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
