import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path/path.dart' as p;

import '../db.dart';
import '../export_dir.dart';
import '../platform/io_shim.dart';
import '../theme/k_colors.dart';

enum WordListActionOutcome { none, changed, deleted }

Future<WordListActionOutcome> showWordListActionsSheet(
  BuildContext context, {
  required AppDb db,
  required int id,
  required String name,
}) async {
  final stat = await db.wordListStat(id);
  if (!context.mounted) return WordListActionOutcome.none;
  final n = stat?.count ?? 0;

  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.k.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: ctx.k.g300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('词单管理',
                      style:
                          TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$name · $n 词',
                      style: TextStyle(fontSize: 10.5, color: ctx.k.nT3)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _item(ctx, '重命名', 'rename', Icons.drive_file_rename_outline),
            _item(ctx, '复制词单', 'copy', Icons.copy_all_outlined),
            _item(ctx, '导出为 JSON', 'export', Icons.file_download_outlined),
            _item(ctx, '删除词单', 'delete', Icons.delete_outline,
                danger: true),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ctx.k.nPanel3,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('取消',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ctx.k.nT2)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return WordListActionOutcome.none;

  switch (choice) {
    case 'rename':
      final newName = await _askName(
        context,
        title: '重命名词单',
        initial: name,
        action: '保存',
      );
      if (newName == null || newName == name || !context.mounted) {
        return WordListActionOutcome.none;
      }
      final ok = await db.renameWordList(id, newName);
      if (!context.mounted) return WordListActionOutcome.none;
      if (!ok) {
        _snack(context, '已有一个叫「$newName」的词单，换个名字');
        return WordListActionOutcome.none;
      }
      _snack(context, '已重命名为「$newName」');
      return WordListActionOutcome.changed;

    case 'copy':
      final ids = await db.wordListIds(id);
      final lists = await db.listWordLists();
      final taken = {for (final l in lists) l.$2.toLowerCase()};
      var copyName = '$name 副本';
      var i = 2;
      while (taken.contains(copyName.toLowerCase())) {
        copyName = '$name 副本 $i';
        i++;
      }
      final newId = await db.createWordList(copyName, ids);
      if (!context.mounted) return WordListActionOutcome.none;
      if (newId == null) {
        _snack(context, '复制失败：名称重复');
        return WordListActionOutcome.none;
      }
      _snack(context, '已复制为「$copyName」');
      return WordListActionOutcome.changed;

    case 'export':
      await _export(context, db: db, id: id, name: name);
      return WordListActionOutcome.none;

    case 'delete':
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除词单？'),
          content: Text('「$name」将被删除。\n\n'
              '它只是一个待学清单，不影响这些词的学习进度或记忆状态。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除',
                    style: TextStyle(color: Color(0xFFD96A5A)))),
          ],
        ),
      );
      if (ok != true || !context.mounted) return WordListActionOutcome.none;
      await db.deleteWordList(id);
      if (!context.mounted) return WordListActionOutcome.none;
      _snack(context, '已删除词单「$name」');
      return WordListActionOutcome.deleted;
  }
  return WordListActionOutcome.none;
}

Widget _item(BuildContext context, String text, String value, IconData icon,
    {bool danger = false}) {
  final fg = danger ? const Color(0xFFD96A5A) : context.k.nT1;
  return GestureDetector(
    onTap: () => Navigator.pop(context, value),
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      height: 50,
      child: Row(children: [
        const SizedBox(width: 10),
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: danger ? const Color(0xFFFBEFED) : context.k.nPanel3,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon,
              size: 17,
              color: danger ? const Color(0xFFD96A5A) : context.k.nT2),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: fg)),
        ),
        Icon(Icons.chevron_right, size: 18, color: context.k.nFaint2),
        const SizedBox(width: 6),
      ]),
    ),
  );
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initial,
  required String action,
}) async {
  final ctl = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: ctx.k.alt,
          hintText: '词单名字',
          hintStyle: TextStyle(color: ctx.k.faint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ctx.k.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ctx.k.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: ctx.k.brand, width: 1.4),
          ),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => ctl.text = initial, child: const Text('重置')),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: Text(action)),
      ],
    ),
  );
  ctl.dispose();
  final name = value?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

Future<void> _export(
  BuildContext context, {
  required AppDb db,
  required int id,
  required String name,
}) async {
  final ids = await db.wordListIds(id);
  final words = await db.wordsByIdsChunked(ids);
  final data = <String, Object?>{
    'app': 'KataMemo',
    'kind': 'word_list',
    'name': name,
    'exported_at': DateTime.now().toIso8601String(),
    'count': words.length,
    'words': [
      for (final w in words) {'id': w.id, 'word': w.word, 'zh': w.zh}
    ],
  };
  String outPath;
  try {
    final dir = await exportBaseDir();
    final out = Directory(p.join(dir.path, 'exports'));
    if (!await out.exists()) await out.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final f = File(p.join(out.path, 'katamemo-wordlist-$id-$stamp.json'));
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    outPath = f.path;
  } catch (e) {
    if (context.mounted) _snack(context, '导出失败：$e');
    return;
  }
  await Clipboard.setData(ClipboardData(text: outPath));
  if (!context.mounted) return;
  _snack(context, '已导出 ${words.length} 词，${exportWhereHint(outPath)}');
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(milliseconds: 2600),
    content: Text(msg),
  ));
}
