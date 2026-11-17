import 'package:flutter/material.dart';

import '../ai_tools.dart' show AiHomeTabs;
import '../app_state.dart';
import '../theme/k_colors.dart';
import '../models.dart';

Future<bool> requestSetTarget(
    BuildContext context, AppState app, BookNode book) async {
  if (!book.clickable) return false;
  if (app.book?.id == book.id) return false;

  final current = app.book;
  if (current != null && current.id != book.id) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('替换学习目标？'),
        content: Text('当前学习目标是「${current.name}」。\n'
            '替换为「${book.name}」？\n\n'
            '只更换目标，不会自动把任何卡片加入记忆；已学进度都保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('替换')),
        ],
      ),
    );
    if (ok != true) return false;
  }

  await app.setBook(book);

  if (context.mounted) await showTargetGuide(context, app, book);
  return true;
}

Future<void> showTargetGuide(
    BuildContext context, AppState app, BookNode book) async {
  final p = await app.db.bookProgress(book.filter);
  final notAdded = (p.all - p.total).clamp(0, p.all);
  final quota = app.dailyQuota > 0 ? app.dailyQuota : 20;
  final defaultBatch = notAdded < quota ? notAdded : quota;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);

  Future<void> add(BuildContext sheet, int n) async {
    final clamped = n.clamp(1, notAdded);
    final ids = await app.db.selectableIdsByFilter(book.filter, limit: clamped);
    await app.remember(ids);
    if (sheet.mounted) Navigator.pop(sheet);
    messenger?.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 3),
      content: Text('已加入 ${ids.length} 个词，下一组开始优先学习'),
      action: SnackBarAction(label: '去学习', onPressed: () => _goStudy(context)),
    ));
  }

  Future<int?> askCustomCount(BuildContext host, int current) async {
    final ctl = TextEditingController(text: '$current');
    return showDialog<int>(
      context: host,
      builder: (dCtx) => AlertDialog(
        title: const Text('按卡量设置加入数量'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '加入词数（1 ~ $notAdded）',
            helperText: '当前每日新词上限：$quota 个/天',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim());
              if (v == null || v <= 0) {
                Navigator.pop(dCtx);
                return;
              }
              Navigator.pop(dCtx, v.clamp(1, notAdded));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  final presets = <({int count, String label})>[];
  final seenCounts = <int>{};
  for (final days in [1, 3, 7]) {
    final c = (quota * days).clamp(1, notAdded);
    if (c < notAdded && seenCounts.add(c)) {
      presets.add((count: c, label: '$days天 · $c'));
    }
  }
  if (presets.isEmpty && notAdded > 0) {
    presets.add((count: defaultBatch, label: '$defaultBatch 个'));
  }

  var selectedBatch = defaultBatch;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheetState) {
        final k = c.k;
        Widget stat(String n, String label) => Expanded(
              child: Column(children: [
                Text(n,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: k.text)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 12, color: k.t2)),
              ]),
            );
        return SafeArea(
          child: Padding(
            key: const Key('target.guide'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('已设为学习目标', style: TextStyle(fontSize: 13, color: k.t2)),
                const SizedBox(height: 2),
                Text(book.name,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700, color: k.text)),
                const SizedBox(height: 10),
                Text(
                  notAdded > 0
                      ? '之后学习时，会先出这组里已加入记忆的新词。'
                          '这组还有 $notAdded 个词没加入记忆，不加入就不会出现。'
                      : '这组的词都已加入记忆，之后学习时会优先出这组的新词。',
                  style: TextStyle(fontSize: 14, height: 1.5, color: k.text),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  stat('${p.all}', '全部'),
                  stat('${p.total}', '已加入'),
                  stat('${p.started}', '已学'),
                ]),
                const SizedBox(height: 16),
                if (notAdded > 0) ...[
                  Text(
                    '按卡量选择加入数量（每日配额 $quota 张）',
                    style: TextStyle(fontSize: 12.5, color: k.t2),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final pItem in presets)
                        ChoiceChip(
                          key: Key('target.preset.${pItem.count}'),
                          label: Text(pItem.label),
                          selected: selectedBatch == pItem.count,
                          selectedColor: k.tint,
                          backgroundColor: k.surface,
                          checkmarkColor: k.deep,
                          side: BorderSide(
                            color:
                                selectedBatch == pItem.count ? k.brand : k.line,
                          ),
                          labelStyle: TextStyle(
                            color:
                                selectedBatch == pItem.count ? k.deep : k.text,
                            fontWeight: selectedBatch == pItem.count
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          onSelected: (_) =>
                              setSheetState(() => selectedBatch = pItem.count),
                        ),
                      ActionChip(
                        key: const Key('target.customCount'),
                        avatar: Icon(Icons.tune, size: 16, color: k.deep),
                        backgroundColor: k.surface,
                        side: BorderSide(color: k.line),
                        labelStyle: TextStyle(color: k.text),
                        label: Text(
                          seenCounts.contains(selectedBatch)
                              ? '自选数量'
                              : '自选 · $selectedBatch',
                        ),
                        onPressed: () async {
                          final picked = await askCustomCount(c, selectedBatch);
                          if (picked != null && c.mounted) {
                            setSheetState(() => selectedBatch = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('target.addBatch'),
                    onPressed: () => add(c, selectedBatch),
                    child: Text('加入 $selectedBatch 个高频词'),
                  ),
                  if (notAdded > selectedBatch) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('target.addAll'),
                      onPressed: () => add(c, notAdded),
                      child: Text('全部加入（$notAdded 个）'),
                    ),
                  ],
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('以后再说'),
                  ),
                ] else ...[
                  FilledButton(
                    key: const Key('target.goStudy'),
                    onPressed: () {
                      Navigator.pop(c);
                      _goStudy(context);
                    },
                    child: const Text('去学习'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('好的'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showTargetPicker(BuildContext context, AppState app) async {
  final books = await app.repo.loadBooks();
  final tiers = [
    for (final b in books)
      if (b.parent == null && b.group == '按词频' && b.clickable && b.id != 'nofreq') b,
  ];
  if (!context.mounted) return;
  final picked = await showModalBottomSheet<BookNode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) {
      final k = c.k;
      return SafeArea(
        child: Padding(
          key: const Key('target.picker'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选一个学习目标',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: k.text)),
              const SizedBox(height: 6),
              Text('学习时会先出目标卡组里的新词。不知道选哪个，就从最高频开始。',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: k.t2)),
              const SizedBox(height: 10),
              for (final b in tiers)
                InkWell(
                  key: Key('target.pick-${b.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(c, b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                    child: Row(children: [
                      Icon(app.book?.id == b.id ? Icons.flag : Icons.flag_outlined,
                          size: 18, color: k.deep),
                      const SizedBox(width: 10),
                      Text(b.name,
                          style: TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600, color: k.text)),
                      if (b.id == tiers.first.id) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: k.tint, borderRadius: BorderRadius.circular(8)),
                          child: Text('推荐',
                              style: TextStyle(fontSize: 11, color: k.deep)),
                        ),
                      ],
                      const Spacer(),
                      Text('${b.count} 词',
                          style: TextStyle(fontSize: 13, color: k.t2)),
                      Icon(Icons.chevron_right, size: 18, color: k.t3),
                    ]),
                  ),
                ),
              const SizedBox(height: 6),
              TextButton(
                key: const Key('target.pickMore'),
                onPressed: () {
                  Navigator.pop(c);
                  if (context.mounted) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                  AiHomeTabs.select?.call(1);
                },
                child: const Text('按主题、词性挑选：去词库，左滑卡组或进卡组设置'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (picked != null && context.mounted) {
    await requestSetTarget(context, app, picked);
  }
}

void _goStudy(BuildContext context) {
  if (context.mounted) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
  AiHomeTabs.select?.call(0);
}

Future<bool> requestClearTarget(BuildContext context, AppState app) async {
  final current = app.book;
  if (current == null) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('取消学习目标？'),
      content: Text('取消「${current.name}」作为学习目标？\n\n'
          '不会移除已加入记忆的卡片，已学进度保留；只是不再作为目标卡组。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('保留')),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(c).colorScheme.error),
            child: const Text('取消目标')),
      ],
    ),
  );
  if (ok != true) return false;
  await app.setBook(null);
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      duration: Duration(milliseconds: 1400),
      content: Text('已取消学习目标'),
    ));
  }
  return true;
}
