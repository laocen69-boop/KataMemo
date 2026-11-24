/// 断签温和顺延（Postpone）弹窗组件。
///
/// 设置页与学习页积压提示条共用，防止两端逻辑与文案分叉。
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme/k_colors.dart';

Future<int?> showPostponeSheet(
  BuildContext context,
  AppState app, {
  required int overdueCount,
}) async {
  var ratio = 0.5;
  var days = 7;

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.k.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final k = ctx.k;
        final targetCount = overdueCount == 0
            ? 0
            : (overdueCount * ratio).round().clamp(1, overdueCount);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_repeat_rounded, color: k.brand, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      '断签温和顺延',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: k.text,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: k.tint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '当前逾期 $overdueCount 张',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: k.deep,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '按记忆稳定度从高到低温和推迟部分复习卡，不改写历史复习时间与 FSRS 权重；正在重学与今日新词不受影响。',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: k.t2),
                ),
                const SizedBox(height: 16),
                Text('顺延比例',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: k.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final opt in [
                      (label: '轻度 30%', v: 0.3),
                      (label: '推荐 50%', v: 0.5),
                      (label: '大幅 80%', v: 0.8),
                    ])
                      ChoiceChip(
                        label: Text(opt.label),
                        selected: ratio == opt.v,
                        backgroundColor: k.bg,
                        selectedColor: k.tint,
                        side: BorderSide(
                            color: ratio == opt.v ? k.brand : k.border),
                        onSelected: (_) => setModalState(() => ratio = opt.v),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('分散到未来几天',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: k.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in [3, 7, 14])
                      ChoiceChip(
                        label: Text('$d 天'),
                        selected: days == d,
                        backgroundColor: k.bg,
                        selectedColor: k.tint,
                        side: BorderSide(color: days == d ? k.brand : k.border),
                        onSelected: (_) => setModalState(() => days = d),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: k.brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: overdueCount == 0
                        ? null
                        : () async {
                            final moved = await app.postponeOverdue(
                                days: days, ratio: ratio);
                            if (ctx.mounted) Navigator.pop(ctx, moved);
                          },
                    child: Text(
                      overdueCount == 0
                          ? '当前没有逾期复习卡'
                          : '顺延 $targetCount 张到未来 $days 天',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
