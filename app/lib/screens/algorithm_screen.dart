library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../backup_pack.dart';
import '../db.dart';
import '../fsrs.dart';
import '../fsrs_ffi.dart';
import '../fsrs_personalize.dart';
import '../version.dart';
import '../widgets/speak_button.dart' show kSpeakGreen;

const int kPersonalizeMinReviews = 1000;
const int kPersonalizeMinForgets = 50;

List<List<List<int>>> _histOf(List rows) => FsrsPersonalize.histories([
      for (final r in rows)
        ReviewEvent((r as List)[0] as String, r[1] as int, r[2] as int)
    ]);

Map<String, int> _statusTask(List rows) {
  final u = FsrsPersonalize.usable(_histOf(rows));
  return {'n': u.predictions, 'forgets': u.forgets, 'rows': rows.length};
}

List<List<List<int>>> _histTask(List rows) => _histOf(rows);

Map<String, Object> _compareTask(Map args) {
  final hist = _histOf(args['rows'] as List);
  final cur = [for (final x in args['cur'] as List) (x as num).toDouble()];
  final cand = [for (final x in args['cand'] as List) (x as num).toDouble()];
  final c = FsrsPersonalize.compare(cur, cand, hist);
  return {'cur': c.currentLoss, 'cand': c.candidateLoss, 'n': c.n};
}

String _csvTask(List rows) => FsrsPersonalize.buildCsv([
      for (final r in rows)
        ReviewEvent((r as List)[0] as String, r[1] as int, r[2] as int)
    ]);

String _jsonEncodeTask(Map<String, Object?> m) => jsonEncode(m);

Object? _jsonDecodeTask(String s) => jsonDecode(s);

class AlgorithmScreen extends StatefulWidget {
  const AlgorithmScreen({super.key});

  @override
  State<AlgorithmScreen> createState() => _AlgorithmScreenState();
}

class _AlgorithmScreenState extends State<AlgorithmScreen> {

  int? _usable, _forgets, _rowCount;

  bool? _canUndo;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final app = context.read<AppState>();
    final rows = await app.db.allReviewRows();
    final st = await compute(_statusTask, rows);
    final canUndo = await app.fsrsHasUndo();
    if (!mounted) return;
    setState(() {
      _usable = st['n'];
      _forgets = st['forgets'];
      _rowCount = st['rows'];
      _canUndo = canUndo;
    });
  }

  Future<void> _info(String title, String body, {Widget? extra}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(body), if (extra != null) extra],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('好')),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body,
      {String ok = '确定', String cancel = '取消'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }

  Widget _pathBox(String path) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('文件位置', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(path, style: const TextStyle(fontSize: 12)),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('路径已复制')));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制路径'),
          ),
        ],
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${_two(n.month)}${_two(n.day)}-'
        '${_two(n.hour)}${_two(n.minute)}${_two(n.second)}';
  }

  Future<Directory> _exportDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}KataMemo');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> _tzName() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } catch (_) {
      return DateTime.now().timeZoneName;
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportCsv() => _guard(() async {
        final app = context.read<AppState>();
        final rows = await app.db.allReviewRows();
        if (rows.isEmpty) {
          if (!mounted) return;
          await _info('还没有复习记录', '先背一阵子再来导出吧。');
          return;
        }
        final csv = await compute(_csvTask, rows);
        final dir = await _exportDir();
        final file = File(
            '${dir.path}${Platform.pathSeparator}katamemo-reviews-${_stamp()}.csv');
        await file.writeAsString(csv);
        final tz = await _tzName();
        final u = _usable ?? 0;
        final short = u < kPersonalizeMinReviews
            ? '\n\n你目前只有 $u 条复习记录，建议至少 $kPersonalizeMinReviews 条后再个性化。'
                '记录太少时，优化结果可能不如官方默认参数。'
            : '';
        if (!mounted) return;
        await _info(
          '已导出',
          '已导出 ${rows.length} 条复习记录。下一步：在电脑上用优化工具训练，'
              '得到 21 个数字后回来导入。\n\n'
              '训练时请把时区选成 $tz，日界（一天从几点算）选 0 点。'
              '导出的文件只包含复习记录，不含词的内容。$short',
          extra: _pathBox(file.path),
        );
      });

  Future<void> _importWeights() => _guard(() async {
        final app = context.read<AppState>();
        final ctl = TextEditingController();
        final text = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导入个性化参数'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '把优化器输出的 21 个数字粘贴到这里（逗号、空格、换行分隔，'
                    '或 JSON 数组都行）。',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: ctx.k.alt,
                    hintText: '0.212, 1.2931, …',
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
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ctl.text),
                  child: const Text('检查')),
            ],
          ),
        );

        if (text == null || !mounted) return;

        final w = FsrsPersonalize.parseWeights(text);
        final err = FsrsPersonalize.validateWeights(w);
        if (err != null) {
          await _info('无法导入', err);
          return;
        }

        final rows = await app.db.allReviewRows();
        await _gateAndApply(w, rows);
      });

  Future<void> _gateAndApply(List<double> w, List rows) async {
    final app = context.read<AppState>();
    final r = await compute(_compareTask, {
      'rows': rows,
      'cur': List<double>.from(Fsrs.W),
      'cand': w,
    });
    final c = WeightsCompare((r['cur'] as num).toDouble(),
        (r['cand'] as num).toDouble(), r['n'] as int);
    final u = _usable ?? 0;
    final short = u < kPersonalizeMinReviews
        ? '\n\n你目前只有 $u 条复习记录，建议至少 $kPersonalizeMinReviews 条后再个性化。'
            '记录太少时，优化结果可能不如官方默认参数。'
        : '';
    if (!mounted) return;

    var go = false;
    if (c.n == 0 || c.improvement.isNaN) {
      go = await _confirm(
          '没法对比',
          '你的历史里还没有可用于对比的复习记录（需要同一张卡隔天以上的作答），'
              '判断不了新参数好不好。仍要应用吗？$short',
          ok: '仍要应用');
    } else {
      final pct = (c.improvement * 100).toStringAsFixed(1);
      if (c.clearlyBetter) {
        go = await _confirm(
            '新参数更准', '新参数在你的历史上预测更准（误差降低 $pct%）。是否应用？$short',
            ok: '应用');
      } else {
        final force = await _confirm(
            '没有明显更好', '新参数在你的历史上没有明显更好（$pct%）。继续用当前参数更稳妥。$short',
            ok: '仍要应用', cancel: '不应用');
        go = force &&
            mounted &&
            await _confirm('再确认一次', '确定要用这组参数吗？随时可以恢复官方默认。', ok: '确定应用');
      }
    }
    if (!go || !mounted) return;

    await app.applyFsrsWeights(w);
    await _refreshStatus();
    if (!mounted) return;
    await _info('已应用', '已应用个性化参数。已有卡片不会被改动，只影响之后的复习安排。'
        '随时可以「回退到优化前参数」或恢复官方默认。');
  }

  Future<void> _optimizeLocal() => _guard(() async {
        final app = context.read<AppState>();
        final u = _usable ?? 0, f = _forgets ?? 0;
        if (u < kPersonalizeMinReviews || f < kPersonalizeMinForgets) {
          await _info('记录还不够',
              '与导入参数同一道门槛：可用复习记录 $u/$kPersonalizeMinReviews 条、'
              '「困难」$f/$kPersonalizeMinForgets 次。再积累一段时间，'
              '或走下面的三步流程在电脑上训练。');
          return;
        }
        if (!await _confirm(
            '在本机优化',
            '用这台手机上的 $u 条复习记录训练 FSRS-6 参数，一般几十秒。'
            '你的学习数据不会被修改；训练出的参数仍要先在你的历史上回放对比、'
            '明显更好才应用，应用后可一键回退。',
            ok: '开始训练')) {
          return;
        }
        if (!mounted) return;
        final rows = await app.db.allReviewRows();
        final hist = await compute(_histTask, rows);
        final diag = diagnoseTrainData(hist);
        if (diag.usableCards < 8 || diag.initCards == 0) {
          if (!mounted) return;
          await _info(
            '有效样本不足',
            '共 ${diag.totalCards} 张学过的卡，其中：\n'
                '· 只有 1 次记录（无后续复习）：${diag.singleReviewCards} 张\n'
                '· 仅同一天内多次复习（无跨天记录）：${diag.sameDayOnlyCards} 张\n'
                '· 含跨天复习的有效卡：${diag.usableCards} 张（其中恰好 1 次跨天复习：${diag.initCards} 张）\n\n'
                'FSRS 训练需要至少 8 张含跨天复习的卡，且需要有「只跨天复习过 1 次」的卡来估计初始稳定性。'
                '这不是数据损坏，继续按计划复习几天后再试即可。',
          );
          return;
        }
        final w = await FsrsFfi.optimizeOnDevice(hist);
        if (w == null) {
          if (!mounted) return;
          await _info(
            '训练未能完成',
            '已筛除单次/同日卡，共有 ${diag.usableCards} 张含跨天复习的卡'
                '（初始样本 ${diag.initCards} 张），但训练器未返回有效参数。\n\n'
                '常见原因：经过训练器离群间隔过滤后有效初始样本不足，或当前梯度未收敛。'
                '你可以再试一次，或点击下方「导出复习记录」发到电脑端排查与训练。',
          );
          return;
        }
        final err = FsrsPersonalize.validateWeights(w);
        if (err != null) {
          if (!mounted) return;
          await _info('训练结果无效',
              '训练出的参数超出允许范围，已丢弃。记录偏少时会出现这种情况，'
              '建议继续用当前参数。$err');
          return;
        }
        await _gateAndApply(w, rows);
      });

  Future<void> _undoWeights() async {
    final app = context.read<AppState>();
    if (!await _confirm('回退参数',
        '撤销最近一次应用的参数，回到那之前的状态（可能是官方默认，也可能是上一组个性化参数）。继续吗？',
        ok: '回退')) {
      return;
    }
    final done = await app.undoFsrsWeights();
    await _refreshStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done ? '已回退到优化前的参数' : '没有可回退的快照')));
  }

  Future<void> _resetDefault() async {
    final app = context.read<AppState>();
    if (!await _confirm('恢复官方默认', '恢复为官方默认参数？你的学习记录不会丢失。', ok: '恢复')) {
      return;
    }
    await app.resetFsrsWeights();
    await _refreshStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复官方默认参数')));
  }

  Future<void> _exportPack() => _guard(() async {
        final app = context.read<AppState>();
        final d = await app.db.db;
        final pack = await BackupPack.export(d,
            schemaVersion: kSchemaVersion,
            dataVersion: kDataVersion,
            appVersion: '$kAppVersion+$kBuildNumber');
        final json = await compute(_jsonEncodeTask, pack);
        final dir = await _exportDir();
        final file = File(
            '${dir.path}${Platform.pathSeparator}katamemo-pack-${_stamp()}.json');
        await file.writeAsString(json);
        if (!mounted) return;
        await _info(
            '已保存',
            '学习数据包已保存。换手机时把这个文件拷到新手机的同一个文件夹，'
                '再选「导入学习数据包」即可。请妥善保管这个文件。',
            extra: _pathBox(file.path));
      });

  Future<void> _importPack() => _guard(() async {
        final app = context.read<AppState>();
        if (!await _confirm('导入学习数据包', '导入会与当前数据合并。建议先导出一份当前数据备份。继续吗？',
            ok: '继续')) {
          return;
        }
        final dir = await _exportDir();
        final files = [
          for (final e in dir.listSync())
            if (e is File && e.path.toLowerCase().endsWith('.json')) e
        ]..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        if (!mounted) return;
        if (files.isEmpty) {
          await _info(
              '没有找到数据包', '请先把数据包文件（katamemo-pack-….json）放进下面这个文件夹，再点导入。',
              extra: _pathBox(dir.path));
          return;
        }
        final picked = await showDialog<File>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('选择数据包'),
            children: [
              for (final f in files)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, f),
                  child: Text(
                    '${f.uri.pathSegments.last}\n'
                    '${(f.lengthSync() / 1024).round()} KB · '
                    '${f.lastModifiedSync().toString().substring(0, 16)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        );
        if (picked == null || !mounted) return;

        try {
          final raw =
              await compute(_jsonDecodeTask, await picked.readAsString());
          if (raw is! Map) throw PackException('这不是 KataMemo 的学习数据包。');
          final pack = raw.cast<String, Object?>();
          final d = await app.db.db;
          final rep = await d.transaction((txn) =>
              BackupPack.import(txn, pack, localSchemaVersion: kSchemaVersion));
          await app.reloadAfterRestore();
          await _refreshStatus();
          if (!mounted) return;
          final ok = rep.srsNew + rep.srsUpdated + rep.srsKept;
          await _info(
              '导入完成',
              '成功 $ok 条学习进度；有 ${rep.unmatched} 条找不到对应词（词库版本不同）已跳过。\n\n'
                  '新增复习记录 ${rep.logAdded} 条，自建词 ${rep.customAdded} 个，'
                  '词单 ${rep.listAdded} 个，笔记 ${rep.editApplied} 条。');
        } on PackException catch (e) {
          if (!mounted) return;
          await _info('导入失败', '导入失败，当前数据没有任何改动。原因：${e.message}');
        } catch (e) {
          if (!mounted) return;
          await _info('导入失败', '导入失败，当前数据没有任何改动。原因：$e');
        }
      });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final u = _usable, f = _forgets;
    final enough = u != null &&
        f != null &&
        u >= kPersonalizeMinReviews &&
        f >= kPersonalizeMinForgets;

    String status;
    if (u == null) {
      status = '正在统计复习记录…';
    } else if (u < kPersonalizeMinReviews) {
      status = '再积累 ${kPersonalizeMinReviews - u} 条复习记录后，个性化参数才有意义。'
          '现在用官方默认参数就很好。';
    } else if (f! < kPersonalizeMinForgets) {
      status = '记录条数够了，但「困难」只有 $f 次（建议至少 $kPersonalizeMinForgets 次），'
          '再用一阵子效果更可靠。';
    } else {
      status = '记录已足够，可以尝试个性化。';
    }

    final ts = app.fsrsWeightsTs;
    String current = '官方默认参数';
    if (app.fsrsPersonalized) {
      if (ts != null && ts > 0) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        current = '个性化参数（${d.month}月${d.day}日导入）';
      } else {
        current = '个性化参数';
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('记忆算法')),
      body: AbsorbPointer(
        absorbing: _working,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Section(
              title: '当前状态',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FSRS-6 · 21 个参数',
                        style: TextStyle(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('当前：$current',
                        style: TextStyle(color: kSpeakGreen)),
                    const SizedBox(height: 14),
                    Text(
                        u == null
                            ? '可用复习记录：统计中…'
                            : '可用复习记录：$u 条（目标 $kPersonalizeMinReviews 条）'
                                '　困难次数：${f ?? 0}（建议 ≥$kPersonalizeMinForgets）',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: u == null
                          ? null
                          : math.min(1.0, u / kPersonalizeMinReviews),
                      color: kSpeakGreen,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 10),
                    Text(status,
                        style: TextStyle(
                            fontSize: 13,
                            color: enough
                                ? kSpeakGreen
                                : Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color)),
                    if (_rowCount != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            '全部作答 $_rowCount 条（同一天内重复作答、'
                            '第一次作答只用来建立状态，不计入「可用」）',
                            style: const TextStyle(fontSize: 11.5)),
                      ),
                  ],
                ),
              ),
            ),

            if (FsrsFfi.available)
              _Section(
                title: '个性化参数（推荐）',
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.memory, color: kSpeakGreen),
                      title: const Text('在本机优化'),
                      subtitle: const Text('用你的复习记录在这台手机上直接训练，不用电脑'),
                      trailing: _working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: _optimizeLocal,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text(
                        '训练与 Anki 桌面版同款（fsrs-rs）。结果和导入一样要先在你的历史上'
                        '回放对比、明显更好才应用；应用后可一键回退。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            _Section(
              title: FsrsFfi.available ? '在电脑上训练（备用）' : '个性化参数（三步）',
              child: Column(
                children: [
                  _Step(
                    n: 1,
                    title: '导出复习记录',
                    subtitle: '生成 CSV 文件，只含复习记录，不含词的内容',
                    onTap: _exportCsv,
                  ),
                  const Divider(height: 1),
                  const _Step(
                    n: 2,
                    title: '在电脑上训练',
                    subtitle:
                        '用 Anki 自带的 FSRS 优化，或 fsrs-optimizer 工具，输出 21 个数字',
                  ),
                  const Divider(height: 1),
                  _Step(
                    n: 3,
                    title: '导入个性化参数',
                    subtitle: '粘贴 21 个数字；应用前会先在你的历史上对比',
                    onTap: _importWeights,
                  ),
                  if (FsrsFfi.available)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text(
                        '本机优化可用时一般用不上这三步；留着作为备用通道。',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text(
                        '个性化的作用：让间隔更贴合你自己的遗忘曲线。记录少时优化结果可能比官方默认更差，'
                        '所以 App 会先在你的历史上对比，只有明显更好才应用。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            _Section(
              title: '恢复',
              child: Column(
                children: [
                  if (_canUndo == true)
                    ListTile(
                      title: const Text('回退到优化前参数'),
                      subtitle:
                          const Text('撤销最近一次应用（导入或本机优化都算）'),
                      trailing: const Icon(Icons.undo),
                      onTap: _undoWeights,
                    ),
                  if (_canUndo == true) const Divider(height: 1),
                  ListTile(
                    title: const Text('恢复官方默认参数'),
                    subtitle:
                        Text(app.fsrsPersonalized ? '你的学习记录不会丢失' : '当前已经是官方默认参数'),
                    trailing: const Icon(Icons.restore),
                    enabled: app.fsrsPersonalized,
                    onTap: app.fsrsPersonalized ? _resetDefault : null,
                  ),
                ],
              ),
            ),
            _Section(
              title: '备份与换机',
              child: Column(
                children: [
                  ListTile(
                    title: const Text('导出学习数据包'),
                    subtitle: const Text('学习进度、笔记、自定义词、词单、设置打包成一个 JSON 文件'),
                    trailing: const Icon(Icons.upload_file),
                    onTap: _exportPack,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('导入学习数据包'),
                    subtitle: const Text('与当前数据合并；失败时当前数据不会有任何改动'),
                    trailing: const Icon(Icons.download),
                    onTap: _importPack,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Text(
                      '换手机前先导出，装好新手机后导入，学习进度、笔记、自定义词都会回来。'
                      '仅复习记录 CSV 不能完整换机。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            if (_working)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child:
              Text(title, style: TextStyle(fontSize: 13, color: context.k.t3)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: child,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _Step(
      {required this.n,
      required this.title,
      required this.subtitle,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 13,
        backgroundColor: kSpeakGreen.withValues(alpha: 0.15),
        child: Text('$n',
            style: TextStyle(fontSize: 13, color: kSpeakGreen)),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
