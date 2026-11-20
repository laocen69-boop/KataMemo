library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/io_shim.dart'
    show clearWebAudioCache, downloadWebAudioShards, webAudioCachedShardCount;

import '../audio.dart';
import '../theme/k_colors.dart';
import '../ai_chat.dart' show aiVendorNames;
import '../app_state.dart';
import '../fsrs.dart';
import '../version.dart';
import 'algorithm_screen.dart';
import 'dict_screen.dart';
import '../widgets/ai_widgets.dart' show AiStatusPill;
import '../widgets/k_switch.dart';
import 'ai_settings_screen.dart';
import '../widgets/quota_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final k = context.k;
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(

        centerTitle: false,
        titleSpacing: 0,
        backgroundColor: k.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 22,
              tooltip: '返回',
              icon: Icon(Icons.chevron_left, color: k.text),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
        title: Text(
          '设置',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: k.text,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          _Group(
            title: '学习',
            first: true,
            children: [
              _Row(
                key: const ValueKey('settings.row.今日卡量'),
                title: '今日卡量',

                subtitle: '今天「复习 + 新词」一共学几张；到期复习优先排',
                trailing: Text('${app.dailyQuota} 张',
                    style: TextStyle(fontSize: 16, color: k.brand)),
                onTap: () => showQuotaDialog(context, app),
              ),
              _Row(
                key: const ValueKey('settings.row.记忆强度（请求保留率）'),
                title: '记忆强度（请求保留率）',
                subtitle:
                    '${(app.retention * 100).round()}% — 越高复习越频繁，记忆越牢',
                trailing: Icon(Icons.tune, size: 22, color: k.t2),
                onTap: () => _retentionDialog(context, app),
              ),
              _Row(
                key: const ValueKey('settings.row.学习方向'),
                title: '学习方向',
                subtitle: app.studyMode == 'id2zh'
                    ? '印尼语 → 中文（看词想义）'
                    : '中文 → 印尼语（看义想词）',
                trailing: Icon(Icons.swap_horiz, size: 22, color: k.t2),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('印尼语 → 中文'),
                            subtitle: const Text('看印尼语单词，回忆中文释义（推荐）'),
                            trailing: app.studyMode == 'id2zh'
                                ? Icon(Icons.check, color: k.brand)
                                : null,
                            onTap: () {
                              app.setStudyMode('id2zh');
                              Navigator.pop(ctx);
                            },
                          ),
                          ListTile(
                            title: const Text('中文 → 印尼语'),
                            subtitle: const Text('看中文释义，回忆印尼语单词（强化输出）'),
                            trailing: app.studyMode == 'zh2id'
                                ? Icon(Icons.check, color: k.brand)
                                : null,
                            onTap: () {
                              app.setStudyMode('zh2id');
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              _Row(
                key: const ValueKey('settings.row.按钮显示复习时间'),
                title: '按钮显示复习时间',
                subtitle: '在评分按钮上显示下次复习时间（默认显示，可关）',
                trailing: KSwitch(
                  value: app.showIntervals,
                  onChanged: (v) => app.setShowIntervals(v),
                ),

                onTap: () => app.setShowIntervals(!app.showIntervals),
              ),
              _Row(
                key: const ValueKey('settings.row.每日学习提醒'),
                title: '每日学习提醒',
                subtitle: '每天 21:00 未完成学习时提醒',
                trailing: KSwitch(
                  value: app.reminderOn,
                  onChanged: (v) => app.setReminderOn(v),
                ),
                onTap: () => app.setReminderOn(!app.reminderOn),
              ),
            ],
          ),
          _Group(
            title: '发音',
            children: [
              _Row(
                key: const ValueKey('settings.row.自动朗读'),
                title: '自动朗读',
                subtitle: '翻面后自动播放发音',
                trailing: KSwitch(
                  value: app.autoSpeak,
                  onChanged: (v) => app.setAutoSpeak(v),
                ),
                onTap: () => app.setAutoSpeak(!app.autoSpeak),
              ),

              Opacity(
                opacity: 0.5,
                child: _Row(
                  key: const ValueKey('settings.row.发音音色'),
                  title: '发音音色',
                  subtitle: 'Ardi 男声（全库统一）',
                  trailing: Icon(Icons.record_voice_over, size: 20, color: k.t2),
                ),
              ),
              if (kIsWeb)
                _Row(
                  key: const ValueKey('settings.row.离线语音包'),
                  title: '离线语音包（防卡顿）',
                  subtitle: '集中缓存在浏览器沙盒中，不占手机文件目录',
                  trailing: Icon(Icons.download_for_offline_outlined,
                      size: 22, color: k.brand),
                  onTap: () => _showWebAudioPackSheet(context),
                ),
            ],
          ),
          _Group(
            title: '外观',
            children: [

              Builder(builder: (ctx) {
                final sysDark =
                    MediaQuery.platformBrightnessOf(ctx) == Brightness.dark;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('主题',
                          style: TextStyle(fontSize: 16, color: k.text)),
                      const SizedBox(height: 12),
                      _ThemeSegment(
                        value: app.themeMode,
                        onChanged: (m) => app.setThemeMode(m),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '跟随系统时，手机切换深浅色，这里立即跟着变。当前系统：'
                        '${sysDark ? '深色' : '浅色'}',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.5, color: k.t3),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
          if (kAiChat)
            _Group(
              title: 'AI 助手',
              children: [
                _Row(
                  key: const ValueKey('settings.row.问一问'),
                  title: '问一问 · 模型与连接',
                  subtitle: app.aiReady
                      ? '${app.aiProvider.name} · ${app.aiConfig.model}'
                      : '支持 ${aiVendorNames(max: 5, sep: ' / ')}，填自己的 Key 即可',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AiStatusPill(
                          status: app.aiStatus, configured: app.aiReady),
                      Icon(Icons.chevron_right, size: 22, color: k.t3),
                    ],
                  ),
                  onTap: () => openAiSettings(context),
                ),
              ],
            ),
          _Group(
            title: '关于',
            children: [
              const _Row(
                key: ValueKey('settings.row.词库来源'),
                title: '词库来源',
                subtitle: '音标参考 KBBI + 维基百科（CC BY-SA 4.0）百科补充',
              ),
              const _Row(
                key: ValueKey('settings.row.发音来源'),
                title: '发音来源',
                subtitle: '印尼语神经网络合成音（男声，全库统一）',
              ),
              _Row(
                key: const ValueKey('settings.row.记忆算法'),
                title: '记忆算法',

                subtitle: _algoSubtitle(app),
                trailing: Icon(Icons.chevron_right, size: 22, color: k.t3),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlgorithmScreen()),
                ),
              ),

              _Row(
                key: const ValueKey('settings.row.本地词典'),
                title: '本地词典',
                subtitle: '导入自己的词表（CSV / TSV / JSON），用于问 AI 参考',
                trailing: Icon(Icons.chevron_right, size: 22, color: k.t3),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DictScreen()),
                ),
              ),

              _Row(
                key: const ValueKey('settings.row.版本'),
                title: '版本',
                trailing: Text('v$kAppVersion · build $kBuildNumber',
                    style: TextStyle(fontSize: 14, color: k.t3)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _algoSubtitle(AppState app) {
    const base = 'FSRS-6 · 21 个参数 · ';
    if (!app.fsrsPersonalized) return '$base官方默认参数';
    final ts = app.fsrsWeightsTs;
    if (ts == null || ts <= 0) return '$base个性化参数';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return '$base个性化参数（${d.month}月${d.day}日导入）';
  }

  void _retentionDialog(BuildContext context, AppState app) {
    var r = app.retention;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('记忆强度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('请求保留率：${(r * 100).round()}%'),
              Slider(
                value: r,
                min: 0.80,
                max: 0.95,
                divisions: 15,
                label: '${(r * 100).round()}%',
                onChanged: (v) => setState(() => r = v),
              ),
              Text('较低=复习间隔更长（省时）\n较高=记忆更牢固（费时）',
                  style: TextStyle(fontSize: 12, color: context.k.t3)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                app.setRetention(r);
                Fsrs.requestedRetention = r;
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  final bool first;

  const _Group({
    required this.title,
    required this.children,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, first ? 8 : 18, 8, 6),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: k.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: k.t2,
                ),
              ),
            ],
          ),
        ),
        Container(

          key: ValueKey('settings.group.$title'),
          decoration: BoxDecoration(
            color: k.surface,
            borderRadius: BorderRadius.circular(16),

            boxShadow: k.shadowOn
                ? const [
                    BoxShadow(
                      color: Color(0x14153C2D),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x73000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Container(height: 1, color: k.line),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const _Row({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final row = Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 16, color: k.text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: k.t3),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemeSegment({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    const items = <(ThemeMode, String)>[
      (ThemeMode.system, '跟随系统'),
      (ThemeMode.light, '浅色'),
      (ThemeMode.dark, '深色'),
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration:
          BoxDecoration(color: k.alt, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (mode, label) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(mode),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == mode ? k.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: value == mode && k.shadowOn
                        ? [
                            const BoxShadow(
                                color: Color(0x141D342C),
                                blurRadius: 8,
                                offset: Offset(0, 2)),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (value == mode) ...[
                        Icon(Icons.check, size: 15, color: k.deep),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              value == mode ? FontWeight.w600 : FontWeight.w400,
                          color: value == mode ? k.deep : k.t2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showWebAudioPackSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _WebAudioPackSheet(),
  );
}

class _WebAudioPackSheet extends StatefulWidget {
  const _WebAudioPackSheet();

  @override
  State<_WebAudioPackSheet> createState() => _WebAudioPackSheetState();
}

class _WebAudioPackSheetState extends State<_WebAudioPackSheet> {
  int _cached = 0;
  bool _downloading = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final n = await webAudioCachedShardCount();
    if (mounted) setState(() => _cached = n);
  }

  Future<void> _download(int from, int to) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _cancelled = false;
      _done = 0;
      _total = to - from + 1;
    });
    await downloadWebAudioShards(
      from,
      to,
      onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      },
      isCancelled: () => _cancelled || !mounted,
    );
    await _refreshCount();
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final ratio = _total > 0 ? (_done / _total).clamp(0.0, 1.0) : 0.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '离线语音包管理',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: k.text),
            ),
            const SizedBox(height: 6),
            Text(
              '已本地缓存 $_cached 个数据包（集中存放在浏览器私有沙盒，不会出现在手机「文件」里）。',
              style: TextStyle(fontSize: 13, height: 1.45, color: k.t2),
            ),
            if (_downloading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 7,
                  color: k.brand,
                  backgroundColor: k.tint,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('正在缓存分片 $_done / $_total…',
                      style: TextStyle(fontSize: 12.5, color: k.t2)),
                  TextButton(
                    onPressed: () => setState(() => _cancelled = true),
                    child: const Text('暂停'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _download(0, 11),
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('下载核心高频词语音（t1–t4，约 6 MB）'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _download(0, 511),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('下载全库离线语音（9.7 万词，约 220 MB）'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _cached >= AudioService.kWebTotalShards
                    ? null
                    : () {
                        AudioService.instance.showWebPackPill();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              duration: Duration(milliseconds: 1400),
                              content: Text('已恢复显示悬浮进度球')),
                        );
                      },
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                label: const Text('恢复显示悬浮进度球'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _cached == 0
                    ? null
                    : () async {
                        await clearWebAudioCache();
                        await _refreshCount();
                      },
                child: Text('清空本地语音缓存',
                    style: TextStyle(
                        color: _cached == 0
                            ? k.t3
                            : Theme.of(context).colorScheme.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
