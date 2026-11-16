library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart' show TodayPlan;

Future<bool> showOverQuotaDialog(
    BuildContext context, AppState app, int quota) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('已达到今日卡量'),
      content: Text(quota == 0
          ? '今日卡量是 0，今天不排新卡。想加入记忆，先把卡量调高。'
          : '今日卡量是 $quota 张，已经勾了 $quota 个。\n想一次多加一些，先把卡量调高。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('先不加了')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('调整卡量')),
      ],
    ),
  );
  if (go != true || !context.mounted) return false;
  await showQuotaDialog(context, app);
  return true;
}

Future<void> showQuotaDialog(BuildContext context, AppState app) async {

  final newCount = await app.db.todayNewCount();
  final done = await app.db.todayAnsweredWords();
  final logs = await app.db.todayLogCount();

  final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
  final due = plan.reviewPlan - plan.reviewDone;
  if (!context.mounted) return;

  final ctl = TextEditingController(text: '${app.dailyQuota}');
  var v = app.dailyQuota;
  void sync(int nv) {
    final c = nv.clamp(0, AppState.kMaxDailyQuota);
    v = c;
    final t = '$c';
    if (ctl.text != t) {
      ctl.value = TextEditingValue(
          text: t, selection: TextSelection.collapsed(offset: t.length));
    }
  }

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {

        final maxQ = AppState.kMaxDailyQuota.toDouble();
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    const Expanded(
                      child: Text('设置今日卡量',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      width: 40,
                      child: IconButton(
                        icon: Icon(Icons.info_outline,
                            size: 20, color: context.k.nFaint2),
                        tooltip: '今日卡量说明',
                        onPressed: () => _showQuotaHelp(ctx,
                            done: done,
                            logs: logs,
                            newCount: newCount,
                            due: due,
                            v: v,
                            plan: plan),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.k.nPanel9,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: ctl,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,

                          LengthLimitingTextInputFormatter(4),
                        ],

                        style: TextStyle(
                            fontSize: 36,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: context.k.text),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '0',
                        ),
                        onChanged: (s) {
                          final n = int.tryParse(s);
                          if (n != null) {
                            v = n.clamp(0, AppState.kMaxDailyQuota);
                          }
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 2),

                      SizedBox(
                        height: 36,
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: context.k.deep,
                            inactiveTrackColor: context.k.border,
                            trackHeight: 4,
                            thumbColor: context.k.deep,
                            overlayShape: SliderComponentShape.noOverlay,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10),
                          ),
                          child: Slider(
                            value: v.toDouble().clamp(0, maxQ),
                            min: 0,
                            max: maxQ,
                            onChanged: (d) => setState(() => sync(d.round())),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (final (i, n) in const [40, 80, 120, 200].indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                key: ValueKey('quota.preset.$n'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => sync(n)),
                                child: Container(
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: v == n
                                        ? context.k.tint
                                        : context.k.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: v == n
                                            ? context.k.brand
                                            : context.k.border,
                                        width: v == n ? 1.5 : 1),
                                  ),
                                  child: Text('$n',
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: v == n
                                              ? context.k.deep
                                              : context.k.text)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          v == 0
                              ? '0 = 今天一张都不排（复习也不排）'
                              : '今日卡量 = 今天「复习 + 新词」的总张数',
                          style: TextStyle(
                              fontSize: 11, color: context.k.nFaint2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Divider(height: 1, thickness: 1, color: context.k.g200),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const RoundedRectangleBorder(),
                  ),
                  onPressed: () async {
                    await app.setQuota(v);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text('确定',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: context.k.deep)),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showQuotaHelp(
  BuildContext context, {
  required int done,
  required int logs,
  required int newCount,
  required int due,
  required int v,
  required TodayPlan plan,
}) async {
  final grey = TextStyle(fontSize: 12.5, color: context.k.nT2, height: 1.5);
  await showDialog(
    context: context,
    builder: (dctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: '关闭',
              onPressed: () => Navigator.pop(dctx),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('今日卡量是怎么算的',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                      '今日卡量 = 今天「复习 + 新词」一共学几张，'
                      '同一张卡今天答几遍只算一张。',
                      style: grey),
                  const SizedBox(height: 10),
                  if (v == 0)
                    Text(
                        '卡量为 0：今天一张都不排（复习也不排）。\n'
                        '想「只复习不学新词」，把卡量设成不小于到期张数即可。',
                        style: grey)
                  else ...[
                    Text(
                        '今天已学 $done 张，今日卡量还剩 ${(v - done).clamp(0, v)} 张'
                        '${logs > done ? '（一共作答 $logs 次）' : ''}',
                        style: grey),
                    const SizedBox(height: 6),

                    Text(
                        '（其中新词 $newCount 个 · 复习 ${done - newCount} 张 · '
                        '今天之内到期 $due 张）',
                        style: grey),
                    if (done > plan.finished) ...[
                      const SizedBox(height: 6),

                      Text(
                          '顶栏那个「今日 ${plan.finished}」只数今天「彻底过了」的张数：'
                          '碰过但还欠一遍的（点了困难/模糊）占卡量、不算进度。',
                          style: grey),
                    ],
                    if (due > v - done) ...[
                      const SizedBox(height: 6),
                      Text(
                          '到期复习会优先占用剩余卡量；${due - (v - done)} 张今天排不进来，'
                          '明天继续（想当天清完就把卡量调到 $due 以上）',
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: Color(0xFFC9604F))),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Text(
                    plan.poolLeft == 0
                        ? '已经没有「加入记忆且没学过」的词了'
                        : '还有 ${plan.poolLeft} 个已加入、未学的词（先学当前学习目标的，'
                            '学完接着从其它卡组取）',
                    style: grey,
                  ),
                  const SizedBox(height: 10),
                  const Text('改完立刻生效，学习页会自动重新取词；设置会保存到本机',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF9E9E9E))),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('知道了'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
