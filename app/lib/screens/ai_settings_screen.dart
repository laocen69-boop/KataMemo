library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai_chat.dart';
import '../ai_search.dart';
import '../app_state.dart';
import '../open_url.dart';
import '../theme/k_colors.dart';
import '../widgets/ai_widgets.dart';
import '../widgets/ai_bench_links.dart';
import '../widgets/k_switch.dart';

Future<void> openAiSettings(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
    );

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _Draft {
  final TextEditingController key, model, base;
  _Draft(AiConfig c)
      : key = TextEditingController(text: c.apiKey),
        model = TextEditingController(text: c.model),
        base = TextEditingController(text: c.baseOverride);
  void dispose() {
    key.dispose();
    model.dispose();
    base.dispose();
  }
}

class _SpeechDraft {
  bool enabled;
  bool expanded;
  final TextEditingController endpoint, model, key;
  _SpeechDraft(AiSpeechConfig c)
      : enabled = c.enabled,
        expanded = c.enabled,
        endpoint = TextEditingController(text: c.endpoint),
        model = TextEditingController(text: c.model),
        key = TextEditingController(text: c.apiKey);
  void dispose() {
    endpoint.dispose();
    model.dispose();
    key.dispose();
  }
}

class _AiSettingsScreenState extends State<AiSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late String _editing;
  final Map<String, _Draft> _drafts = {};
  final Map<String, AiTestResult> _results = {};
  bool _showKey = false;
  bool _testing = false;
  late final _SpeechDraft _asrDraft;
  late final _SpeechDraft _ttsDraft;
  bool _showAsrKey = false;
  bool _showTtsKey = false;

  final Map<String, TextEditingController> _searchKeys = {};
  TextEditingController _searchKeyCtl(String id) => _searchKeys.putIfAbsent(
      id, () => TextEditingController(text: context.read<AppState>().aiSearchKeyFor(id)));
  late final TextEditingController _searchEndpointCtl;
  bool _searchShow = false;
  bool _searchTesting = false;
  bool _searchOk = false;
  String? _searchMsg;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    final app = context.read<AppState>();
    _editing = app.aiProviderId;
    _asrDraft = _SpeechDraft(app.aiAsrConfig);
    _ttsDraft = _SpeechDraft(app.aiTtsConfig);
    _searchEndpointCtl = TextEditingController(text: app.aiSearchCustomEndpoint);
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final d in _drafts.values) {
      d.dispose();
    }
    _asrDraft.dispose();
    _ttsDraft.dispose();
    _searchEndpointCtl.dispose();
    for (final c in _searchKeys.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveSearchKey() async {
    FocusScope.of(context).unfocus();
    final app = context.read<AppState>();
    final id = app.aiSearchProviderId;
    if (aiSearchProviderById(id)?.ownKey != true) return;
    final text = _searchKeyCtl(id).text;
    final ep = id == 'custom' ? _searchEndpointCtl.text : null;
    await app.saveAiSearch(id, key: text, endpoint: ep, select: true);
    if (!mounted) return;
    setState(() => _searchMsg = null);
    if (text.trim().isEmpty) {
      _snack('已清除 Key');
    } else if (id == 'custom' && !aiValidCustomSearchEndpoint(_searchEndpointCtl.text)) {
      _snack('已保存，但接口地址须为有效的 https:// 链接');
    } else {
      _snack('已保存，联网搜索已开启');
    }
  }

  Future<void> _testSearch() async {
    FocusScope.of(context).unfocus();
    final app = context.read<AppState>();
    final id = app.aiSearchProviderId;
    final prov = aiSearchProviderById(id);
    if (prov == null) return;
    if (prov.ownKey) {
      await app.saveAiSearch(
        id,
        key: _searchKeyCtl(id).text,
        endpoint: id == 'custom' ? _searchEndpointCtl.text : null,
        select: true,
      );
    }
    setState(() {
      _searchTesting = true;
      _searchMsg = null;
    });
    String msg;
    var ok = false;
    try {
      final hits = await aiWebSearch(
        prov,
        app.aiSearchKeyFor(id),
        'selamat pagi artinya',
        count: 1,
        customEndpoint: app.aiSearchCustomEndpoint,
      );
      ok = true;
      msg = hits.isEmpty ? '连接成功，但这次没有返回结果' : '搜索可用 · ${prov.name} 返回了结果';
      await app.bumpAiSearchUsed();
    } on AiException catch (e) {
      msg = e.message;
    }
    if (!mounted) return;
    setState(() {
      _searchTesting = false;
      _searchOk = ok;
      _searchMsg = msg;
    });
  }

  Future<void> _openSearchConsole(AiSearchProvider p) async {
    final ok = await openExternalUrl(p.console);
    if (ok || !mounted) return;
    await Clipboard.setData(ClipboardData(text: p.console));
    if (mounted) _snack('打不开浏览器，链接已复制：${p.console}');
  }

  _Draft _draft(String id) => _drafts.putIfAbsent(
      id, () => _Draft(context.read<AppState>().aiConfigFor(id)));

  AiConfig _draftConfig(String id) {
    final d = _draft(id);
    return AiConfig(
      provider: aiProviderById(id),
      apiKey: d.key.text,
      model: d.model.text,
      baseOverride: d.base.text,
    );
  }

  Future<void> _save({required bool select}) async {
    final d = _draft(_editing);
    await context.read<AppState>().saveAiProvider(_editing,
        key: d.key.text, model: d.model.text, base: d.base.text, select: select);
  }

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    final app = context.read<AppState>();
    final id = _editing;
    final cfg = _draftConfig(id);
    setState(() => _testing = true);

    await _save(select: false);
    final r = await aiTestConnection(cfg);
    if (!mounted) return;

    await app.setAiModelWindows(id, r.windows);
    if (!mounted) return;
    await app.setAiStatus(
        id,
        AiStatus(r.ok ? AiLinkState.ok : AiLinkState.fail,
            at: DateTime.now().millisecondsSinceEpoch,
            message: r.message,
            model: cfg.model.trim(),
            latencyMs: r.latencyMs));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _results[id] = r;
    });
  }

  Future<void> _saveAndUse() async {
    FocusScope.of(context).unfocus();
    final cfg = _draftConfig(_editing);
    final miss = cfg.missing;
    if (miss != null) {
      _snack(miss);
      return;
    }
    await _save(select: true);
    if (!mounted) return;
    _snack('已保存，现在使用 ${cfg.provider.name} · ${cfg.model.trim()}');
  }

  Future<void> _openConsole(AiProvider p) async {
    if (p.console.isEmpty) return;
    final ok = await openExternalUrl(p.console);
    if (ok || !mounted) return;
    await Clipboard.setData(ClipboardData(text: p.console));
    if (mounted) _snack('打不开浏览器，链接已复制：${p.console}');
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 3)));

  static const _tabLabels = ['模型配置', '对话与入口', '说明与参考'];

  InputDecoration _inputDeco(
    BuildContext context,
    String hint, {
    Widget? suffix,
  }) {
    final k = context.k;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: k.faint, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
      filled: true,
      fillColor: k.alt,
      suffixIcon: suffix,
      border: border(k.border),
      enabledBorder: border(k.border),
      focusedBorder: border(k.brand, 1.4),
    );
  }

  Widget _labeledField(BuildContext context, String label, Widget field) {
    final k = context.k;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: k.t2)),
        ),
        field,
      ],
    );
  }

  Widget _tabBar(BuildContext context) {
    final k = context.k;
    final active = _tabs.index;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: k.alt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabLabels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('ai.tab.$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _tabs.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active == i ? k.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: active == i
                        ? [
                            BoxShadow(
                              color: k.text.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabLabels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active == i ? FontWeight.w700 : FontWeight.w500,
                      color: active == i ? k.deep : k.t2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(
        backgroundColor: k.bg,
        scrolledUnderElevation: 0,
        title: const Text('AI 助手'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Column(
              children: [
                _currentCard(context, app),
                const SizedBox(height: 10),
                _tabBar(context),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 32),
                  children: [
                    _title(context, '选择服务商'),
                    _grid(context, app),
                    _title(context, '${aiProviderById(_editing).name} 设置'),
                    _editor(context, app),
                    _title(context, '语音扩展（ASR / TTS · 可选）'),
                    _speechCard(context, app),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 32),
                  children: [
                    _title(context, '我的印尼语水平'),
                    _levels(context, app),
                    _title(context, '跨会话学习记忆'),
                    _learningMemory(context, app),
                    _title(context, '上下文与压缩策略'),
                    _context(context, app),
                    _title(context, '入口与显示'),
                    _entries(context, app),
                    _title(context, '联网搜索（可选）'),
                    _search(context, app),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 32),
                  children: [
                    _title(context, '隐私与费用'),
                    _card(
                      context,
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          '· 不内置任何 Key：用你自己在服务商开放平台申请的 Key，按该服务商的价格计费。\n'
                          '· Key 只保存在本机，导出学习数据包时不会带上。\n'
                          '· 提问时会把你的问题和当前话题的资料（单词释义、例句或语法页内容）发给你选的服务商。\n'
                          '· 对话保存在本机（「对话历史」里可查看、搜索、删除），不进学习记录。\n'
                          '· 开了联网搜索时，AI 只会把一个搜索词发给搜索服务商，结果只作参考。'
                          '${aiVendorNames(overseas: true).isEmpty ? '' : '\n· ${aiVendorNames(overseas: true, sep: ' / ')} 在国内一般需要可访问的网络环境。'}',
                          style: TextStyle(fontSize: 12.5, height: 1.7, color: k.t2),
                        ),
                      ),
                    ),
                    _title(context, '印尼语能力参考（第三方）'),
                    const AiBenchLinksCard(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.k.t2)),
      );

  Widget _card(BuildContext context, Widget child) => Container(
        decoration: BoxDecoration(
          color: context.k.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.k.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _currentCard(BuildContext context, AppState app) {
    final k = context.k;
    final cfg = app.aiConfig;
    final st = app.aiStatus;
    final configured = app.aiConfigured(cfg.provider.id);
    final detail = !configured
        ? '还没填 API Key —— 在下面选一家服务商，填好 Key 和模型'
        : switch (st.state) {
            AiLinkState.ok =>
              '${aiAgo(st.at)}验证通过${st.latencyMs > 0 ? ' · 首包 ${st.latencyMs} ms' : ''}',
            AiLinkState.fail => st.message,
            AiLinkState.unknown => '还没测试过，点下方「测试连接」确认能用',
          };
    return Container(
      key: const ValueKey('ai.current'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [
          kAiGradA.withValues(alpha: 0.13),
          kAiGradB.withValues(alpha: 0.13),
        ]),
        border: Border.all(color: kAiGradB.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiProviderAvatar(provider: cfg.provider, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text('正在使用 · ${cfg.provider.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: k.text)),
                  ),
                  const SizedBox(width: 8),
                  AiStatusPill(status: st, configured: configured),
                ]),
                const SizedBox(height: 3),
                Text(cfg.model.isEmpty ? '模型：未填' : '模型：${cfg.model}',
                    style: TextStyle(fontSize: 12.5, color: k.t2)),
                const SizedBox(height: 4),
                Text(detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.45, color: k.t3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, AppState app) {
    final k = context.k;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final p in kAiProviders)
            GestureDetector(
              key: ValueKey('ai.provider.${p.id}'),
              onTap: () => setState(() {
                _editing = p.id;
                _showKey = false;
              }),
              child: Container(
                width: w,
                padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                decoration: BoxDecoration(
                  color: k.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: p.id == _editing ? kAiGradB : k.line,
                    width: p.id == _editing ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    AiProviderAvatar(provider: p, size: 32),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: k.text)),
                            ),
                            if (p.recommended) const _RecommendTag(),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            p.id == app.aiProviderId && app.aiConfigured(p.id)
                                ? '使用中'
                                : app.aiConfigured(p.id)
                                    ? '已填 Key'
                                    : p.overseas
                                        ? '需海外网络'
                                        : p.vendor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: p.id == app.aiProviderId &&
                                        app.aiConfigured(p.id)
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: p.id == app.aiProviderId &&
                                        app.aiConfigured(p.id)
                                    ? kAiGradA
                                    : k.t3),
                          ),
                        ],
                      ),
                    ),
                    if (app.aiConfigured(p.id))
                      Icon(
                        app.aiStatusFor(p.id).state == AiLinkState.fail
                            ? Icons.error
                            : Icons.check_circle,
                        size: 16,
                        color: app.aiStatusFor(p.id).state == AiLinkState.fail
                            ? const Color(0xFFD9534F)
                            : kAiGradA,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _editor(BuildContext context, AppState app) {
    final k = context.k;
    final p = aiProviderById(_editing);
    final d = _draft(p.id);
    final r = _results[p.id];
    final st = app.aiStatusFor(p.id);
    InputDecoration deco(String hint, {Widget? suffix}) =>
        _inputDeco(context, hint, suffix: suffix);
    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AiProviderAvatar(provider: p, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(p.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: k.text)),
                      if (p.recommended) const _RecommendTag(),
                    ]),
                    Text(p.recommended ? '${p.vendor} · 本项目的评测主要在它上面做' : p.vendor,
                        style: TextStyle(fontSize: 12, color: k.t3)),
                  ],
                ),
              ),
              if (p.console.isNotEmpty)
                GestureDetector(
                  key: const ValueKey('ai.console'),
                  onTap: () => _openConsole(p),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: k.alt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_new, size: 14, color: k.deep),
                      const SizedBox(width: 4),
                      Text('开放平台',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: k.deep)),
                    ]),
                  ),
                ),
            ]),
            if (p.overseas || p.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (p.overseas) '国内一般需要可访问的网络环境。',
                  if (p.note.isNotEmpty) p.note,
                ].join(''),
                style: TextStyle(fontSize: 12, height: 1.5, color: k.t3),
              ),
            ],
            if (p.nativeSearch && p.searchNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: k.alt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.travel_explore, size: 15, color: k.deep),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '支持原生联网 · ${p.searchNote}（协议兼容性截至 2026-11-15）',
                        style: TextStyle(fontSize: 11.5, height: 1.45, color: k.t2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _labeledField(
              context,
              'API Key',
              TextField(
                key: const ValueKey('ai.key'),
                controller: d.key,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() => _results.remove(p.id)),
                decoration: deco(
                  '在开放平台创建后粘贴到这里',
                  suffix: IconButton(
                    tooltip: _showKey ? '隐藏' : '显示',
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility,
                        size: 20, color: k.t3),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _labeledField(
              context,
              '模型',
              TextField(
                key: const ValueKey('ai.model'),
                controller: d.model,
                autocorrect: false,
                onChanged: (_) => setState(() => _results.remove(p.id)),
                decoration: deco(p.modelHint.isEmpty ? '服务商给的模型名' : p.modelHint),
              ),
            ),
            if (p.modelHint.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                key: const ValueKey('ai.recommend'),
                onTap: () => setState(() {
                  d.model.text = p.modelHint;
                  _results.remove(p.id);
                }),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: d.model.text == p.modelHint ? k.tint : k.alt,
                    borderRadius: BorderRadius.circular(14),
                    border: d.model.text == p.modelHint
                        ? Border.all(color: kAiGradA)
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.thumb_up_alt_outlined, size: 14, color: k.deep),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '推荐（$kAiRecommendedAsOf · 高性价比）：${p.modelHint}',
                        style: TextStyle(fontSize: 12, color: k.text),
                      ),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 2),
                child: Text('点一下填入；新型号以开放平台为准',
                    style: TextStyle(fontSize: 11, color: k.t3)),
              ),
              if (p.extraModels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (id, label) in p.extraModels)
                      GestureDetector(
                        key: ValueKey('ai.recommend.$id'),
                        onTap: () => setState(() {
                          d.model.text = id;
                          _results.remove(p.id);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: d.model.text == id ? k.tint : k.alt,
                            borderRadius: BorderRadius.circular(14),
                            border: d.model.text == id
                                ? Border.all(color: kAiGradA)
                                : null,
                          ),
                          child: Text(
                            '$id · $label',
                            style: TextStyle(fontSize: 11.5, color: k.text),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
            if ((r?.models ?? const []).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('可用模型（点一下填入）',
                  style: TextStyle(fontSize: 12, color: k.t3)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in r!.models)
                    GestureDetector(
                      onTap: () => setState(() => d.model.text = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: d.model.text == m ? k.tint : k.alt,
                          borderRadius: BorderRadius.circular(14),
                          border: d.model.text == m
                              ? Border.all(color: kAiGradA)
                              : null,
                        ),
                        child: Text(m,
                            style: TextStyle(fontSize: 12, color: k.text)),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _labeledField(
              context,
              p.isCustom ? '接口地址（必填）' : '接口地址（留空 = 默认）',
              TextField(
                key: const ValueKey('ai.base'),
                controller: d.base,
                autocorrect: false,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() => _results.remove(p.id)),
                decoration: deco(p.isCustom ? 'https://…/v1' : p.base),
              ),
            ),
            const SizedBox(height: 12),
            Text('输出上限（max_tokens）',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: k.t2)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in kAiCustomMaxOutputChoices)
                  GestureDetector(
                    key: ValueKey('ai.customMaxOutput.${v ?? 'auto'}'),
                    onTap: () => app.setAiCustomMaxOutput(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: app.aiCustomMaxOutput == v ? k.tint : k.alt,
                        borderRadius: BorderRadius.circular(14),
                        border: app.aiCustomMaxOutput == v
                            ? Border.all(color: kAiGradA)
                            : null,
                      ),
                      child: Text(
                        v == null
                            ? (p.protocol == AiProtocol.anthropic
                                ? '默认（${aiTokensShort(kAiMaxOutput)} · 协议必填）'
                                : '跟随模型默认（不限制）')
                            : aiTokensShort(v),
                        style: TextStyle(fontSize: 12, color: k.text),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _resultBanner(context, r, st),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('ai.test'),
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check, size: 18),
                    label: Text(_testing ? '测试中…' : '测试连接'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('ai.save'),
                    onPressed: _testing ? null : _saveAndUse,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('保存并使用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _speechCard(BuildContext context, AppState app) {
    final k = context.k;
    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '语音识别（ASR）与语音合成（TTS）暂未内置默认通道，这里保留自定义接入入口。'
              '开启并填写接口地址或模型名后，AI 对话页会显示对应按钮。',
              style: TextStyle(fontSize: 12, height: 1.5, color: k.t3),
            ),
            const SizedBox(height: 10),
            _speechSection(
              context,
              app,
              isAsr: true,
              title: '语音识别（ASR · 语音输入）',
              sub: '把你的印尼语或中文语音转成提问文字',
              draft: _asrDraft,
              showKey: _showAsrKey,
              onToggleKey: () => setState(() => _showAsrKey = !_showAsrKey),
              endpointHint: 'https://api.deepseek.com/v1/tools/asr',
              modelHint: 'deepseek-asr / qwen3-asr-flash / whisper-1',
              presetEndpoint: 'https://api.deepseek.com/v1/tools/asr',
              presetModel: 'deepseek-asr',
            ),
            Container(height: 1, color: k.line, margin: const EdgeInsets.symmetric(vertical: 10)),
            _speechSection(
              context,
              app,
              isAsr: false,
              title: '语音合成（TTS · 朗读回答）',
              sub: '将 AI 的印尼语讲解或例句合成为语音',
              draft: _ttsDraft,
              showKey: _showTtsKey,
              onToggleKey: () => setState(() => _showTtsKey = !_showTtsKey),
              endpointHint: 'https://api.deepseek.com/v1/tools/tts',
              modelHint: 'stella / tide / tts-1',
              presetEndpoint: 'https://api.deepseek.com/v1/tools/tts',
              presetModel: 'stella',
            ),
          ],
        ),
      ),
    );
  }

  Widget _speechSection(
    BuildContext context,
    AppState app, {
    required bool isAsr,
    required String title,
    required String sub,
    required _SpeechDraft draft,
    required bool showKey,
    required VoidCallback onToggleKey,
    required String endpointHint,
    required String modelHint,
    required String presetEndpoint,
    required String presetModel,
  }) {
    final k = context.k;
    final tag = isAsr ? 'asr' : 'tts';
    final configured = isAsr ? app.aiAsrConfigured : app.aiTtsConfigured;

    Future<void> save({bool? enabledOverride}) async {
      FocusScope.of(context).unfocus();
      final on = enabledOverride ?? draft.enabled;
      await app.saveAiSpeech(
        isAsr: isAsr,
        enabled: on,
        endpoint: draft.endpoint.text,
        model: draft.model.text,
        apiKey: draft.key.text,
      );
      if (!mounted) return;
      final ready = isAsr ? app.aiAsrConfigured : app.aiTtsConfigured;
      if (on && !ready) {
        _snack('请先填写接口地址或模型名');
      } else {
        _snack(on ? '已保存，对话页将显示对应入口' : '已关闭');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => draft.expanded = !draft.expanded),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(title,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: k.text)),
                      ),
                      if (configured) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: k.tint,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('已接入',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: k.deep)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 12, color: k.t3)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            KSwitch(
              key: ValueKey('ai.$tag.switch'),
              value: draft.enabled,
              onChanged: (v) async {
                setState(() {
                  draft.enabled = v;
                  if (v) draft.expanded = true;
                });
                await app.saveAiSpeech(
                  isAsr: isAsr,
                  enabled: v,
                  endpoint: draft.endpoint.text,
                  model: draft.model.text,
                  apiKey: draft.key.text,
                );
              },
            ),
          ],
        ),
        if (draft.expanded) ...[
          const SizedBox(height: 10),
          _labeledField(
            context,
            '接口地址',
            TextField(
              key: ValueKey('ai.$tag.base'),
              controller: draft.endpoint,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: _inputDeco(context, endpointHint),
            ),
          ),
          const SizedBox(height: 10),
          _labeledField(
            context,
            isAsr ? '模型名' : '模型 / 音色',
            TextField(
              key: ValueKey('ai.$tag.model'),
              controller: draft.model,
              autocorrect: false,
              decoration: _inputDeco(context, modelHint),
            ),
          ),
          const SizedBox(height: 10),
          _labeledField(
            context,
            'API Key（留空 = 复用当前对话 Key）',
            TextField(
              key: ValueKey('ai.$tag.key'),
              controller: draft.key,
              obscureText: !showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _inputDeco(
                context,
                '独立服务商时填写；复用当前 Key 可留空',
                suffix: IconButton(
                  tooltip: showKey ? '隐藏' : '显示',
                  icon: Icon(showKey ? Icons.visibility_off : Icons.visibility,
                      size: 20, color: k.t3),
                  onPressed: onToggleKey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                key: ValueKey('ai.$tag.preset'),
                onTap: () => setState(() {
                  draft.endpoint.text = presetEndpoint;
                  draft.model.text = presetModel;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: k.alt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text('填入 DeepSeek 预设',
                      style: TextStyle(fontSize: 11.5, color: k.deep)),
                ),
              ),
              const Spacer(),
              FilledButton(
                key: ValueKey('ai.$tag.save'),
                onPressed: () => save(enabledOverride: true),
                child: const Text('保存配置'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _resultBanner(BuildContext context, AiTestResult? r, AiStatus st) {
    final k = context.k;
    final bool? ok = r?.ok ??
        switch (st.state) {
          AiLinkState.ok => true,
          AiLinkState.fail => false,
          AiLinkState.unknown => null,
        };
    if (ok == null) return const SizedBox.shrink();
    final msg = r?.message ??
        (ok
            ? '上次验证通过（${aiAgo(st.at)}）${st.model.isEmpty ? '' : ' · ${st.model}'}'
            : '上次连接失败（${aiAgo(st.at)}）：${st.message}');
    final c = ok ? const Color(0xFF2E9E6A) : const Color(0xFFD9534F);
    return Container(
      key: ValueKey(ok ? 'ai.result.ok' : 'ai.result.fail'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: k.text)),
          ),
        ],
      ),
    );
  }

  Widget _levels(BuildContext context, AppState app) {
    final k = context.k;
    return _card(
      context,
      Column(
        children: [
          for (final (i, l) in AiLevel.values.indexed) ...[
            if (i > 0) Container(height: 1, color: k.line),
            GestureDetector(
              key: ValueKey('ai.level.${l.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => app.setAiLevel(l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    Icon(
                      app.aiLevel == l
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: app.aiLevel == l ? kAiGradA : k.t3,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(aiLevelLabel(l),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: app.aiLevel == l
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: k.text)),
                          const SizedBox(height: 2),
                          Text(aiLevelDesc(l),
                              style: TextStyle(
                                  fontSize: 12, height: 1.4, color: k.t3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _learningMemory(BuildContext context, AppState app) {
    final k = context.k;
    final on = app.aiMemoryEnabled;
    final mem = app.aiLearningMemory;
    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('自动跨会话学习记忆',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: k.text)),
                      const SizedBox(height: 2),
                      Text(
                        '开启后，助手会在对话中与切走会话时自动提炼你的水平、讲解偏好与易错点（上限 $kAiMemoryMaxChars 字）；也可手动编辑或关闭。',
                        style: TextStyle(fontSize: 12, height: 1.45, color: k.t3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  key: const ValueKey('ai.memory.switch'),
                  value: on,
                  onChanged: app.setAiMemoryEnabled,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              opacity: on ? 1.0 : 0.5,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: k.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: k.line),
                ),
                child: Text(
                  key: const ValueKey('ai.memory.text'),
                  mem.isEmpty
                      ? (on
                          ? '暂无学习记忆。开启后对话会自动累积，也可以点下方手动补充。'
                          : '已关闭自动跨会话记忆（现有记录不会发送给助手）。')
                      : mem,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: mem.isEmpty ? k.t3 : k.text),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  key: const ValueKey('ai.memory.edit'),
                  onPressed: () => _editLearningMemory(context, app),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑'),
                ),
                if (mem.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('ai.memory.clear'),
                    onPressed: () => app.setAiLearningMemory(''),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLearningMemory(BuildContext context, AppState app) async {
    final res = await showDialog<String>(
      context: context,
      builder: (c) => _MemoryEditDialog(initial: app.aiLearningMemory),
    );
    if (res != null) await app.setAiLearningMemory(res);
  }

  Widget _context(BuildContext context, AppState app) {
    final k = context.k;
    final w = app.aiWindow;
    final cur = app.aiBudget;
    final toolB = app.aiBudgetForTurn(forTools: true);
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              key: const ValueKey('ai.ctx.window'),
              app.aiConfig.model.trim().isEmpty
                  ? '还没填模型，先按 ${aiTokensShort(w.tokens)} 计'
                  : '${app.aiConfig.model.trim()} 的上下文窗口约 ${aiTokensShort(w.tokens)}（${w.source}）\n'
                      '日常上限约 ${aiTokensShort(cur.input)} · 长任务自动放宽至 ${aiTokensShort(toolB.input)}（最多 ${toolB.rounds} 步）',
              style: TextStyle(fontSize: 12, height: 1.5, color: k.t3),
            ),
          ),
          for (final t in kAiCtxUiTiers) ...[
            Container(height: 1, color: k.line),
            Builder(builder: (context) {
              final selected = t == AiCtxTier.economy
                  ? app.aiCtxTier == AiCtxTier.economy
                  : app.aiCtxTier != AiCtxTier.economy;
              return GestureDetector(
                key: ValueKey('ai.ctx.${t.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => app.setAiCtxTier(t),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected ? kAiGradA : k.t3,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(aiCtxLabel(t),
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                    color: k.text)),
                            const SizedBox(height: 2),
                            Text(aiCtxDesc(t),
                                style: TextStyle(fontSize: 12, height: 1.4, color: k.t3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          Container(height: 1, color: k.line),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => app.setAiDiag(!app.aiDiag),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('诊断记录', style: TextStyle(fontSize: 15, color: k.text)),
                        const SizedBox(height: 2),
                        Text('长任务出问题时打开：记录每一步发了多少内容、调了哪些工具、用时多久。'
                            '不记对话内容和 Key，只存在内存里，关掉 App 就没了',
                            style: TextStyle(fontSize: 12, height: 1.45, color: k.t3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  KSwitch(
                      key: const ValueKey('ai.diagSwitch'),
                      value: app.aiDiag,
                      onChanged: (v) => app.setAiDiag(v)),
                ],
              ),
            ),
          ),
          if (app.aiDiag) ...[
            Container(height: 1, color: k.line),
            GestureDetector(
              key: const ValueKey('ai.diagView'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _showDiag(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(children: [
                  Expanded(
                    child: Text('查看 / 复制诊断记录（${AiDiag.lines.length} 行）',
                        style: TextStyle(fontSize: 14, color: k.deep)),
                  ),
                  Icon(Icons.chevron_right, color: k.t3),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showDiag(BuildContext context) async {
    final text = AiDiag.dump();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('诊断记录'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(text.isEmpty ? '还没有记录。去问一个需要好几步的问题再回来看。' : text,
                style: const TextStyle(fontSize: 11.5, height: 1.45, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                AiDiag.clear();
                Navigator.pop(c);
              },
              child: const Text('清空')),
          TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('复制')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('关闭')),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _search(BuildContext context, AppState app) {
    final k = context.k;
    final sel = app.aiSearchProviderId;
    final selProv = app.aiSearchProvider;

    Widget option(String id, String title, String sub, {String tag = ''}) {
      final on = sel == id;
      return GestureDetector(
        key: ValueKey('ai.search.opt.${id.isEmpty ? 'off' : id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _searchMsg = null);
          app.saveAiSearch(id, select: true);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: on ? k.tint : k.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? kAiGradA : k.line, width: on ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20, color: on ? kAiGradA : k.t3),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(title,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: k.text)),
                      ),
                      if (tag.isNotEmpty) _RecommendTag(label: tag),
                    ]),
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(fontSize: 12, height: 1.5, color: k.t3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final used = app.aiSearchUsedThisMonth;

    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '词库和知识库里没有答案时，AI 可以上网搜一下。搜到的只是网页摘要，只作参考，'
              '回答里会写出处、并说明没经过词典核实；词典里查得到的，仍以词典为准。\n'
              'DeepSeek、智谱 GLM（同 Key 外部搜索）与阿里云百炼通义千问（原生 enable_search）在填入 Key 后默认自动开启；'
              '其他模型也支持在下方选用博查、Tavily 或自定义搜索 API，或随时手动关闭。\n'
              '注：各厂商联网协议与工具调用兼容性说明截至 2026-11-15，后续若服务商调整接口以官方最新文档为准。',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: k.t2),
            ),
            if (app.aiConfig.provider.nativeSearch &&
                app.aiConfig.provider.searchNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: k.alt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '当前模型（${app.aiConfig.provider.name}）：${app.aiConfig.provider.searchNote}（截至 2026-11-15 协议）',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: k.t2),
                ),
              ),
            ],
            const SizedBox(height: 12),
            option('', '不联网', '关闭联网。AI 只用词库、知识库和 KBBI 回答，没有依据就直说没有'),
            for (final sp in kAiSearchProviders)
              option(sp.id, sp.name, sp.note, tag: sp.tag),
            if (selProv != null && selProv.ownKey) ...[
              if (selProv.id == 'custom') ...[
                const SizedBox(height: 8),
                _labeledField(
                  context,
                  '接口地址（POST JSON）',
                  TextField(
                    key: const ValueKey('ai.search.endpoint'),
                    controller: _searchEndpointCtl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() => _searchMsg = null),
                    decoration: _inputDeco(
                      context,
                      'https://example.com/search（接收 {query, count}）',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _labeledField(
                context,
                '${selProv.name} API Key',
                TextField(
                  key: const ValueKey('ai.search.key'),
                  controller: _searchKeyCtl(selProv.id),
                  obscureText: !_searchShow,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() => _searchMsg = null),
                  decoration: _inputDeco(
                    context,
                    selProv.id == 'tavily'
                        ? 'tvly- 开头，注册后在控制台复制'
                        : selProv.id == 'custom'
                            ? '作为 Bearer Token 发送到你的搜索接口'
                            : '在开放平台创建后粘贴到这里',
                    suffix: IconButton(
                      tooltip: _searchShow ? '隐藏' : '显示',
                      icon: Icon(_searchShow ? Icons.visibility_off : Icons.visibility,
                          size: 20, color: k.t3),
                      onPressed: () => setState(() => _searchShow = !_searchShow),
                    ),
                  ),
                ),
              ),
              if (selProv.console.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  key: const ValueKey('ai.search.console'),
                  onTap: () => _openSearchConsole(selProv),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.open_in_new, size: 14, color: k.deep),
                    const SizedBox(width: 4),
                    Text('去 ${selProv.name} 官网注册、拿 Key',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600, color: k.deep)),
                  ]),
                ),
              ],
            ],
            if (selProv != null && !selProv.ownKey) ...[
              const SizedBox(height: 4),
              Builder(builder: (_) {
                final reuse = aiProviderById(selProv.reuseAiKeyOf).name;
                final ok = app.aiConfigured(selProv.reuseAiKeyOf!);
                return Text(
                  ok
                      ? '已用 AI 设置里的 $reuse Key，不用再填。'
                      : '还没填 $reuse 的 Key：先在上面「选择服务商」里选 $reuse 并填好 Key。',
                  key: const ValueKey('ai.search.dsHint'),
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: ok ? k.t2 : const Color(0xFFD9534F)),
                );
              }),
            ],
            if (selProv != null) ...[
              const SizedBox(height: 10),
              Text(
                selProv.freeMonthly > 0
                    ? '本月已搜 $used 次 / 免费 ${selProv.freeMonthly} 次（本机估算，以官网用量为准）'
                    : '本月已搜 $used 次（按量计费，用量以服务商控制台为准）',
                key: const ValueKey('ai.search.used'),
                style: TextStyle(fontSize: 12, color: k.t3),
              ),
              if (_searchMsg != null) ...[
                const SizedBox(height: 8),
                Text(_searchMsg!,
                    key: const ValueKey('ai.search.msg'),
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: _searchOk ? kAiGradA : const Color(0xFFD9534F))),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('ai.search.test'),
                      onPressed: _searchTesting || !app.aiSearchReady && !selProv.ownKey
                          ? null
                          : _testSearch,
                      icon: _searchTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.travel_explore, size: 18),
                      label: Text(_searchTesting ? '测试中…' : '测试搜索'),
                    ),
                  ),
                  if (selProv.ownKey) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('ai.search.save'),
                        onPressed: _searchTesting ? null : _saveSearchKey,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('保存'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entries(BuildContext context, AppState app) {
    final k = context.k;
    return _card(
      context,
      Column(
        children: [
          GestureDetector(
            key: const ValueKey('ai.historyRow'),
            behavior: HitTestBehavior.opaque,
            onTap: () => openAiHistory(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('对话历史',
                            style: TextStyle(fontSize: 15, color: k.text)),
                        const SizedBox(height: 2),
                        Text('翻看、搜索以前和 AI 的对话，点一段接着聊，不用重复问',
                            style: TextStyle(
                                fontSize: 12, height: 1.45, color: k.t3)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: k.t3),
                ],
              ),
            ),
          ),
          Container(height: 1, color: k.line),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => app.setAiFab(!app.aiFab),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('显示悬浮球',
                            style: TextStyle(fontSize: 15, color: k.text)),
                        const SizedBox(height: 2),
                        Text('连好 AI 后在页面边上显示 ✨，可拖动；长按有菜单。'
                            '在单词详情、语法页里点它，会直接问当前内容',
                            style: TextStyle(
                                fontSize: 12, height: 1.45, color: k.t3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  KSwitch(
                      key: const ValueKey('ai.fabSwitch'),
                      value: app.aiFab,
                      onChanged: (v) => app.setAiFab(v)),
                ],
              ),
            ),
          ),
          Container(height: 1, color: k.line),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => app.setAiTools(!app.aiTools),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('允许 AI 操作 App',
                            style: TextStyle(fontSize: 15, color: k.text)),
                        const SizedBox(height: 2),
                        Text('查学习记录、今天的错词与搜索、整理词单、加入记忆、打开页面。'
                            '凡是会改动数据的，都会先在对话里请你确认。关掉 = 纯聊天',
                            style: TextStyle(
                                fontSize: 12, height: 1.45, color: k.t3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  KSwitch(
                      key: const ValueKey('ai.toolsSwitch'),
                      value: app.aiTools,
                      onChanged: (v) => app.setAiTools(v)),
                ],
              ),
            ),
          ),
          Container(height: 1, color: k.line),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '其它入口：单词详情页右上角 ✨ · 单词速览弹窗 · 学习页翻面后卡背底部 · '
              '语法页右上角 · 搜索没结果时 · 「我的 → 学习工具 → AI 助手」',
              style: TextStyle(fontSize: 12, height: 1.6, color: k.t3),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendTag extends StatelessWidget {
  final String label;
  const _RecommendTag({this.label = '推荐'});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ai.recommendTag'),
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: kAiGradA.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: kAiGradA)),
    );
  }
}

class _MemoryEditDialog extends StatefulWidget {
  final String initial;
  const _MemoryEditDialog({required this.initial});

  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑跨会话学习记忆'),
      content: TextField(
        key: const ValueKey('ai.memory.field'),
        controller: _ctl,
        maxLines: 5,
        maxLength: kAiMemoryMaxChars,
        decoration: const InputDecoration(
          hintText: '例如：零基础，喜欢少术语多生活例句；容易混淆 me-kan 和 me-i。',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctl.text),
            child: const Text('保存')),
      ],
    );
  }
}
