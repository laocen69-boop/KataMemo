import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dict_import/dict_flow.dart';
import '../dict_import/dict_kind.dart';
import '../dict_import/dict_model.dart';
import '../dict_import/dict_parse.dart';
import '../dict_import/dict_pick.dart';
import '../dict_import/dict_store.dart';
import '../platform/io_shim.dart';
import '../theme/k_colors.dart';

class DictScreen extends StatefulWidget {
  const DictScreen({super.key});

  @override
  State<DictScreen> createState() => _DictScreenState();
}

class _DictScreenState extends State<DictScreen> {
  List<DictSourceRow>? _rows;
  Map<int, DictKindInfo> _kinds = const <int, DictKindInfo>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    try {
      final r = await db.dictSources();
      final kinds = await db.dictKinds();
      if (mounted) {
        setState(() {
          _rows = r;
          _kinds = kinds;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _dialog(String title, String body) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _import() async {
    if (_busy) return;
    final db = context.read<AppState>().db;
    const opt = DictImportOptions();

    String? path;
    try {
      path = await pickDictFilePath();
    } on DictPickException catch (e) {
      _snack(e.message);
      return;
    }
    if (path == null) return;

    final name = dictDisplayName(path);
    final format = detectDictFormat(name);
    if (format == null) {
      _snack('只支持 CSV、TSV、TXT、JSON 文件');
      return;
    }

    setState(() => _busy = true);
    try {
      final file = File(path);
      if (await file.length() > opt.maxFileBytes) {
        _snack('文件超过 ${opt.maxFileBytes ~/ (1024 * 1024)} MB，已拒绝导入');
        return;
      }

      final DictPreview preview;
      try {
        preview = await _previewInBackground(format, path, opt);
      } on FormatException catch (e) {
        await _dialog('无法读取文件', '${e.message}\n\n如果是 Excel 导出的文件，'
            '可以试试「另存为 → CSV UTF-8」或「Unicode 文本」。');
        return;
      }
      if (preview.count(preview.hasHeaderGuess) == 0 &&
          preview.count(!preview.hasHeaderGuess) == 0) {
        await _dialog('没有可导入的数据', '文件里没有记录。');
        return;
      }

      final choice = await _askMapping(preview);
      if (choice == null || !mounted) return;

      final ImportResult res;
      try {
        res = await _importInBackground(
            format, path, choice.hasHeader, choice.mapping, opt);
      } on ArgumentError catch (e) {
        await _dialog('映射有误', '${e.message}');
        return;
      } on FormatException catch (e) {
        await _dialog('无法读取文件', e.message);
        return;
      }
      if (res.entries.isEmpty) {
        await _dialog('没有导入任何词条', '所有记录都被跳过了，请看下一步的提示，或检查词头列是否选对。');
        return;
      }

      final sid = await db.dictWriteImport(
        name: name,
        format: dictFormatLabel(format),
        entries: res.entries,
      );

      final kind = await db.dictAutoKind(
        sid,
        name: name,
        sample: res.entries.take(300).toList(),
        totalEntries: res.entries.length,
      );
      final aligned = await db.dictAlignWordIds(
        res.entries.map((e) => dictFold(e.lemma)),
      );
      if (!mounted) return;
      await _showSummary(name, res, aligned, kind: kind);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({bool hasHeader, Map<ImportField, String> mapping})?> _askMapping(
      DictPreview p) {
    var hasHeader = p.hasHeaderGuess;
    var current = Map<ImportField, String>.of(p.mapping(hasHeader));
    return showDialog<({bool hasHeader, Map<ImportField, String> mapping})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final headers = p.headers(hasHeader);
          final samples = p.samples(hasHeader);
          final lemmaOk = (current[ImportField.lemma] ?? '').isNotEmpty;
          String label(String h) {
            final s = samples[h] ?? const [];
            return s.isEmpty ? h : '$h（${s.join('、')}）';
          }

          void toggleHeader(bool v) {
            if (v == hasHeader) return;

            final from = p.headers(hasHeader);
            final to = p.headers(v);
            final moved = <ImportField, String>{};
            current.forEach((f, h) {
              final i = from.indexOf(h);
              if (i >= 0 && i < to.length) moved[f] = to[i];
            });
            p.mapping(v).forEach((f, h) {
              if (!moved.containsKey(f) && !moved.containsValue(h)) moved[f] = h;
            });
            setS(() {
              hasHeader = v;
              current = moved;
            });
          }

          return AlertDialog(
            title: const Text('确认列的对应关系'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (p.delimiter != null)
                        '自动识别：${dictDelimiterLabel(p.delimiter!)}分隔',
                      '共 ${p.count(hasHeader)} 条',
                      '下面的对应关系是按列名和内容猜的，可以改',
                      '同一列只能对应一个字段，后选的会顶掉先选的',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: context.k.t2),
                  ),
                  if (p.delimiter != null)
                    CheckboxListTile(
                      key: const Key('dict.hasHeader'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: hasHeader,
                      onChanged: (v) => toggleHeader(v ?? true),
                      title: const Text('第一行是表头（列名）'),
                    ),
                  const SizedBox(height: 4),
                  for (final f in ImportField.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_fieldLabel(f),
                              style: const TextStyle(fontSize: 13)),
                          DropdownButton<String?>(
                            isExpanded: true,
                            value: headers.contains(current[f]) ? current[f] : null,
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('（不导入）')),
                              for (final h in headers)
                                DropdownMenuItem<String?>(
                                    value: h,
                                    child: Text(label(h),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setS(() {
                              if (v == null) {
                                current.remove(f);
                              } else {

                                final stolen = current.keys
                                    .where((k2) => k2 != f && current[k2] == v)
                                    .toList();
                                for (final k2 in stolen) {
                                  current.remove(k2);
                                }
                                current[f] = v;
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  if (!lemmaOk)
                    const Text('必须选择「词头」列。',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: lemmaOk
                    ? () => Navigator.pop(ctx, (hasHeader: hasHeader, mapping: current))
                    : null,
                child: const Text('导入'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _fieldLabel(ImportField f) => switch (f) {
        ImportField.lemma => '词头（必选）',
        ImportField.definition => '释义',
        ImportField.pos => '词性',
        ImportField.example => '例句',
        ImportField.translation => '例句译文',
        ImportField.pronunciation => '发音',
        ImportField.homograph => '同形序号',
      };

  Future<void> _showSummary(
    String name,
    ImportResult res,
    Map<String, List<String>> aligned, {
    DictKindInfo? kind,
  }) async {
    var matched = 0;
    var ambiguous = 0;
    var none = 0;
    for (final e in res.entries) {
      final c = aligned[dictFold(e.lemma)];
      if (c == null || c.isEmpty) {
        none++;
      } else if (c.length == 1) {
        matched++;
      } else {
        ambiguous++;
      }
    }
    final warnings = res.issues.where((i) => i.warning).toList();
    final shown = warnings.take(20).toList();
    final lines = <String>[
      '已导入「$name」：${res.entries.length} 个词条。',
      '与学习词库对照（只读，不会改动词库）：唯一对应 $matched 个，'
          '词库中有多个同形词 $ambiguous 个，词库中没有 $none 个。',
      if (kind != null) ...[
        '',
        '来源识别：${kind.isKbbi ? 'KBBI（AI 优先参考）' : kind.label}'
            '${kind.byUser ? '（你手动指定）' : '（自动识别）'}',
        for (final e in kind.evidence) '· $e',
        '识别只用于排序，不改任何一个词条；可在词典列表点标签改判。',
      ],
      if (warnings.isEmpty) '没有需要注意的问题。'
      else ...[
        '有 ${warnings.length} 条需要注意（已按规则跳过或忽略，未猜测处理）：',
        for (final w in shown) '第 ${w.row} 行：${w.message}',
        if (warnings.length > shown.length) '……其余 ${warnings.length - shown.length} 条未显示。',
      ],
    ];

    final offer = kind != null &&
        kind.isKbbi &&
        !context.read<AppState>().aiLocalDictOn;
    if (!offer) {
      await _dialog('导入完成', lines.join('\n'));
      return;
    }
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: SingleChildScrollView(child: Text(lines.join('\n'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('知道了')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('让 AI 优先参考')),
        ],
      ),
    );
    if (go == true && mounted) await _setConsent(true);
  }

  Future<void> _askKind(DictSourceRow row, DictKindInfo? current) async {
    final pick = await showDialog<DictKind>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${row.name}」的来源类型'),
        content: SingleChildScrollView(
          child: Text(
            '${current == null ? '还没识别。' : '当前：${current.label}'
                '${current.byUser ? '（你手动指定）' : '（自动识别）'}。'}\n\n'
            '${current == null || current.evidence.isEmpty
                ? '识别依据：暂无'
                : '识别依据：\n${current.evidence.map((e) => '· $e').join('\n')}'}\n\n'
            '标为 KBBI 后，问 AI 时这份词典的释义会排在其它导入词典前面。'
            '这只是排序，不会改动任何词条内容。',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, DictKind.other),
              child: const Text('其它词典')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, DictKind.kbbi),
              child: const Text('标为 KBBI')),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    await context.read<AppState>().db.dictSetKind(
      row.id,
      DictKindInfo(
        kind: pick,
        byUser: true,
        evidence: ['学生手动指定为${pick.label}'],
      ),
    );
    await _load();
  }

  Future<void> _toggle(DictSourceRow row, bool on) async {
    final db = context.read<AppState>().db;
    await db.dictSetEnabled(row.id, on);
    await _load();
  }

  Future<void> _delete(DictSourceRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个词典？'),
        content: Text('「${row.name}」的 ${row.entryCount} 个词条会从本机删除。'
            '学习记录和学习词库不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final db = context.read<AppState>().db;
    await db.dictDelete(row.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地词典'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _import,
            child: const Text('导入'),
          ),
        ],
      ),
      body: Column(children: [
        _consentCard(context),
        Expanded(
          child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    '还没有导入词典。\n\n'
                    '支持 CSV、TSV、JSON 文件（例如老师整理的词表）。'
                    '导入的内容只保存在本机，用于「问 AI」时参考，不会改动学习词库。\n\n'
                    '⚠️ 只导入你自己拥有、或已获得授权的文件。第三方词典通常受版权保护，'
                    '导入后请仅供自己使用，不要外传或公开分享。\n\n'
                    '点右上角「导入」开始。',
                    style: TextStyle(fontSize: 14, height: 1.5, color: k.t3),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final info = _kinds[r.id];
                    final isKbbi = info?.isKbbi ?? false;
                    return _rowCard(
                      context,
                      title: r.name,
                      subtitle: '${r.format} · ${r.entryCount} 个词条'
                          '${isKbbi ? ' · KBBI（AI 优先引用）' : ''}',
                      trailing: [
                        IconButton(
                          tooltip: '来源类型 / 改判',
                          icon: Icon(
                            isKbbi ? Icons.verified_outlined : Icons.label_outline,
                            color: isKbbi ? k.brand : k.t3,
                            size: 20,
                          ),
                          onPressed: () => _askKind(r, info),
                        ),
                        Switch(
                          value: r.enabled,
                          onChanged: (v) => _toggle(r, v),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline, color: k.t3),
                          onPressed: () => _delete(r),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _consentCard(BuildContext context) {
    final on = context.watch<AppState>().aiLocalDictOn;
    return _rowCard(
      context,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      title: '允许问 AI 参考本地词典',
      subtitle: '开启后，问 AI 时，与问题相关的少量词条（每次最多 5 个词）会发送给你选择的 AI 服务商。'
          '关闭后不再发送。第三方词典受版权保护，请只导入自己有权使用的内容，仅供自己使用，勿外传。',
      trailing: [Switch(value: on, onChanged: (v) => _setConsent(v))],
    );
  }

  Widget _rowCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> trailing,
    EdgeInsets margin = EdgeInsets.zero,
  }) {
    final k = context.k;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        border: Border.all(color: k.t3.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: k.text)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: k.t3, height: 1.4)),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }

  Future<void> _setConsent(bool v) async {
    if (!v) {
      await context.read<AppState>().setAiLocalDict(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('允许 AI 参考本地词典？'),
        content: const Text(
          '开启后，你问 AI 与某个词相关的问题时，这个词在你导入的词典里的释义和例句（最多 5 个词）'
          '会发送给你在 AI 设置里选择的服务商，用来生成回答。\n\n'
          '这些内容只是你自己导入的资料，App 不会上传整个词典。随时可以在这里关闭。\n\n'
          '⚠️ 请只导入你自己拥有或已获得授权的文件。第三方词典通常受版权保护，'
          '导入和发送给 AI 的内容请仅供自己使用，不要外传或公开分享。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('暂不开启')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开启')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().setAiLocalDict(true);
  }
}

Future<DictPreview> _previewInBackground(
        DictFormat format, String path, DictImportOptions opt) =>
    runCompute(() => buildDictPreview(format, File(path).readAsStringSync(), opt));

Future<ImportResult> _importInBackground(DictFormat format, String path,
        bool hasHeader, Map<ImportField, String> mapping, DictImportOptions opt) =>
    runCompute(() => importDictText(
        format, File(path).readAsStringSync(), hasHeader, mapping, opt));
