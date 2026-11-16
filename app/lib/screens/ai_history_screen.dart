library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_history.dart';
import '../app_state.dart';
import '../theme/k_colors.dart';

Future<AiConvSummary?> pickAiConversation(BuildContext context,
    {int? currentId}) {
  return Navigator.of(context).push<AiConvSummary>(
    MaterialPageRoute(builder: (_) => AiHistoryScreen(currentId: currentId)),
  );
}

class AiHistoryScreen extends StatefulWidget {

  final int? currentId;
  const AiHistoryScreen({super.key, this.currentId});

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  List<AiConvSummary>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final r = await app.db.aiChatList(q: _q.text);
      if (mounted) setState(() => _rows = r);
    } catch (_) {
      if (mounted) setState(() => _rows = const []);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _delete(AiConvSummary c) async {
    final app = context.read<AppState>();
    final full = await app.db.aiChatGet(c.id);
    await app.db.aiChatDelete(c.id);
    setState(() => _rows = [for (final r in _rows ?? const <AiConvSummary>[]) if (r.id != c.id) r]);
    if (!mounted || full == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已删除「${c.title}」这段对话'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await app.db.aiChatSave(
              key: c.key,
              title: c.title,
              subtitle: c.subtitle,
              system: full.system,
              msgs: full.msgs,
            );
            if (mounted) unawaited(_load());
          },
        ),
      ));
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空全部对话历史？'),
        content: const Text('所有和 AI 的对话记录都会从本机删除，不能恢复。学习进度、词库和助记不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().db.aiChatClear();
    if (mounted) setState(() => _rows = const []);
  }

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(t.year, t.month, t.day);
    final diff = today.difference(d).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff < 7) return '本周';
    return '更早';
  }

  static String _timeLabel(DateTime t) {
    final now = DateTime.now();
    final same = t.year == now.year && t.month == now.month && t.day == now.day;
    String two(int n) => n.toString().padLeft(2, '0');
    if (same) return '${two(t.hour)}:${two(t.minute)}';
    return '${t.month}月${t.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final rows = _rows;
    return Scaffold(
      backgroundColor: k.bg,
      appBar: AppBar(
        title: const Text('对话历史'),
        backgroundColor: k.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (rows != null && rows.isNotEmpty && _q.text.isEmpty)
            TextButton(
                key: const ValueKey('ai.history.clear'),
                onPressed: _clearAll,
                child: const Text('清空')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              key: const ValueKey('ai.history.search'),
              controller: _q,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索标题或对话内容',
                prefixIcon: Icon(Icons.search, size: 20, color: k.t3),
                isDense: true,
                filled: true,
                fillColor: k.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: k.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: k.line),
                ),
              ),
            ),
          ),
          Expanded(child: _body(context, rows)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<AiConvSummary>? rows) {
    final k = context.k;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _q.text.trim().isEmpty
                ? '还没有对话记录。\n和 AI 聊过的每一段都会自动存在这里，下次不用再问一遍。'
                : '没有找到包含「${_q.text.trim()}」的对话。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.7, color: k.t3),
          ),
        ),
      );
    }

    final children = <Widget>[];
    String? last;
    for (final c in rows) {
      final g = _dayLabel(c.updated);
      if (g != last) {
        last = g;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(g,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: k.t3)),
        ));
      }
      children.add(_row(context, c));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  IconData _icon(AiConvSummary c) => switch (c.kind) {
        'word' => Icons.menu_book_outlined,
        'grammar' => Icons.school_outlined,
        _ => Icons.forum_outlined,
      };

  Widget _row(BuildContext context, AiConvSummary c) {
    final k = context.k;
    final current = c.id == widget.currentId;
    return Dismissible(
      key: ValueKey('ai.history.row.${c.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        color: const Color(0xFFD9534F),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(c),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context, c),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: k.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: current ? k.brand : k.line, width: current ? 1.4 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: k.alt,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon(c), size: 18, color: k.deep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: k.text)),
                      ),
                      if (c.subtitle.isNotEmpty && c.kind != 'general') ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(c.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: k.t3)),
                        ),
                      ],
                      if (current) ...[
                        const SizedBox(width: 6),
                        Text('当前',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: k.brand)),
                      ],
                    ]),
                    if (c.preview.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(c.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, height: 1.4, color: k.t2)),
                    ],
                    const SizedBox(height: 4),
                    Text('${_timeLabel(c.updated)} · ${c.count} 条',
                        style: TextStyle(fontSize: 11.5, color: k.t3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
