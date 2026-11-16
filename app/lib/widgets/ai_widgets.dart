library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai_chat.dart';
import '../ai_logos.dart';
import '../app_state.dart';
import '../svg_path.dart';
import '../screens/ai_history_screen.dart' show pickAiConversation;
import '../screens/ai_settings_screen.dart' show openAiSettings;
import '../theme/k_colors.dart';
import '../version.dart' show kAiChat;
import 'ai_chat_sheet.dart';

const Color kAiGradA = Color(0xFF3FB98A);
const Color kAiGradB = Color(0xFF4C8DF6);
const LinearGradient kAiGradient = LinearGradient(
  colors: [kAiGradA, kAiGradB],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

final GlobalKey<NavigatorState> kRootNavKey = GlobalKey<NavigatorState>();

class AiSpark extends StatelessWidget {
  final double size;
  const AiSpark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: kAiGradient,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.auto_awesome, size: size * 0.6, color: Colors.white),
    );
  }
}

class AiAppBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const AiAppBarButton(
      {super.key, required this.onTap, this.tooltip = '问一问（AI）'});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: AiSpark(size: 26),
        ),
      ),
    );
  }
}

class AiAskChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dense;
  const AiAskChip(
      {super.key, this.label = '问 AI', required this.onTap, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(4, 4, dense ? 10 : 12, 4),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAiGradB.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AiSpark(size: dense ? 20 : 22),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: dense ? 12.5 : 13.5,
                    fontWeight: FontWeight.w600,
                    color: k.deep)),
          ],
        ),
      ),
    );
  }
}

class AiAskCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const AiAskCard({
    super.key,
    required this.onTap,
    this.title = '还不太懂？问问 AI',
    this.subtitle = '讲用法 · 近义词辨析 · 帮你记 · 造句批改',
  });

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return GestureDetector(
      key: const ValueKey('ai.askCard'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: [
            kAiGradA.withValues(alpha: 0.10),
            kAiGradB.withValues(alpha: 0.10),
          ]),
          border: Border.all(color: kAiGradB.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            const AiSpark(size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: k.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: k.t3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: k.t3),
          ],
        ),
      ),
    );
  }
}

class AiStatusPill extends StatelessWidget {
  final AiStatus status;
  final bool configured;
  const AiStatusPill({super.key, required this.status, this.configured = true});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (Color c, String t) = !configured
        ? (k.t3, '未设置')
        : switch (status.state) {
            AiLinkState.ok => (const Color(0xFF2E9E6A), '已连接'),
            AiLinkState.fail => (const Color(0xFFD9534F), '连接失败'),
            AiLinkState.unknown => (const Color(0xFFE09A2B), '未测试'),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}

class AiProviderAvatar extends StatelessWidget {
  final AiProvider provider;
  final double size;
  const AiProviderAvatar({super.key, required this.provider, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final logo = kAiLogos[provider.id];
    if (logo != null) {
      final c = Color(provider.color);
      return Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.18),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: CustomPaint(painter: _LogoPainter(logo, c)),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(provider.color),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(provider.badge,
          style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final List<(double, String)> parts;
  final Color color;
  _LogoPainter(this.parts, this.color);

  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    for (final (op, d) in parts) {
      final path = _cache.putIfAbsent(d, () {
        try {
          return parseSvgPath(d)..fillType = PathFillType.evenOdd;
        } catch (_) {
          return Path();
        }
      });
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: op));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.color != color || !identical(old.parts, parts);
}

String aiAgo(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}

class AiContextHub {
  AiContextHub._();
  static final List<(Object, AiChatContext Function())> _stack = [];

  static final ValueNotifier<int> sheetsOpen = ValueNotifier<int>(0);

  static void push(Object owner, AiChatContext Function() build) {
    _stack.removeWhere((e) => identical(e.$1, owner));
    _stack.add((owner, build));
  }

  static void pop(Object owner) =>
      _stack.removeWhere((e) => identical(e.$1, owner));

  static AiChatContext? get current => _stack.isEmpty ? null : _stack.last.$2();
}

Future<List<(String, String)>> aiTodayWords(AppState app) async {
  try {
    final raw = await app.db.db;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final rows = await raw.rawQuery(
        'SELECT w.word AS word, w.zh AS zh, MAX(l.ts) AS t FROM study_log l '
        'JOIN words w ON w.id = l.card_id WHERE l.ts >= ? '
        'GROUP BY l.card_id ORDER BY t DESC LIMIT 30',
        [start]);
    return [
      for (final r in rows)
        ((r['word'] as String?) ?? '', (r['zh'] as String?) ?? ''),
    ];
  } catch (_) {
    return const [];
  }
}

Future<void> openGeneralAi(BuildContext context, {String? draft}) =>

    aiOpenGuarded(() async {
      final app = context.read<AppState>();
      final recent = await aiTodayWords(app);
      if (!context.mounted) return;
      await presentAiChat(context, aiGeneralContext(recent: recent), draft: draft);
    });

Future<void> openAiHistory(BuildContext context) async {
  if (aiChatOpening) return;
  final app = context.read<AppState>();
  final pick = await pickAiConversation(context);
  if (pick == null || !context.mounted) return;
  final ctx = await aiContextForConv(app, pick);
  if (!context.mounted) return;
  await showAiChat(context, ctx, convId: pick.id);
}

class AiFloatingBall extends StatefulWidget {
  const AiFloatingBall({super.key});

  @override
  State<AiFloatingBall> createState() => _AiFloatingBallState();
}

class _AiFloatingBallState extends State<AiFloatingBall> {
  static const double _size = 50;
  Offset? _drag;
  bool _idle = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _armIdle();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _armIdle() {
    _idleTimer?.cancel();
    if (_idle) setState(() => _idle = false);
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _idle = true);
    });
  }

  BuildContext? get _navCtx => kRootNavKey.currentContext;

  bool _menuOpen = false;

  void _open() {
    if (aiChatOpening) return;
    _armIdle();
    final ctx = _navCtx;
    if (ctx == null) return;
    final cur = AiContextHub.current;
    if (cur != null) {
      showAiChat(ctx, cur);
    } else {
      openGeneralAi(ctx);
    }
  }

  Future<void> _menu() async {
    if (_menuOpen || aiChatOpening) return;
    _armIdle();
    final ctx = _navCtx;
    if (ctx == null) return;
    _menuOpen = true;
    final cur = AiContextHub.current;
    final app = context.read<AppState>();
    final pick = await showModalBottomSheet<String>(
      context: ctx,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cur != null)
              ListTile(
                leading: const AiSpark(size: 26),
                title: Text('问「${cur.title}」'),
                subtitle: const Text('带上当前页面的资料'),
                onTap: () => Navigator.pop(c, 'cur'),
              ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('通用印尼语助手'),
              subtitle: const Text('翻译、批改、情景对话、考今天学的词'),
              onTap: () => Navigator.pop(c, 'general'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('对话历史'),
              subtitle: const Text('翻看、搜索以前的对话，不用重复问'),
              onTap: () => Navigator.pop(c, 'history'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('AI 设置'),
              subtitle: Text('${app.aiProvider.name} · ${app.aiConfig.model}'),
              onTap: () => Navigator.pop(c, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('隐藏悬浮球'),
              subtitle: const Text('可在「设置 → AI 助手」重新打开'),
              onTap: () => Navigator.pop(c, 'hide'),
            ),
          ],
        ),
      ),
    );
    _menuOpen = false;
    final nav = _navCtx;
    if (nav == null || !nav.mounted) return;
    switch (pick) {
      case 'cur':
        if (cur != null) await showAiChat(nav, cur);
      case 'general':
        await openGeneralAi(nav);
      case 'history':
        await openAiHistory(nav);
      case 'settings':
        await openAiSettings(nav);
      case 'hide':
        await app.setAiFab(false);
        if (nav.mounted) {
          ScaffoldMessenger.maybeOf(nav)?.showSnackBar(const SnackBar(
              content: Text('悬浮球已隐藏，可在「设置 → AI 助手」重新打开')));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kAiChat) return const SizedBox.shrink();
    final show = context.select<AppState, bool>(
        (a) => a.ready && a.aiFab && a.aiReady);
    if (!show) return const SizedBox.shrink();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ValueListenableBuilder<int>(
      valueListenable: AiContextHub.sheetsOpen,
      builder: (context, open, _) {
        if (open > 0 || keyboard) return const SizedBox.shrink();
        return LayoutBuilder(builder: (context, box) {
          final app = context.read<AppState>();
          final pad = MediaQuery.paddingOf(context);
          final minY = pad.top + 8, maxY = box.maxHeight - pad.bottom - _size - 72;
          final maxX = box.maxWidth - _size - 6;
          final right = app.aiFabX >= 0.5;

          final docked = _idle && _drag == null;
          final pos = _drag ??
              Offset(
                  docked
                      ? (right ? box.maxWidth - _size / 2 : -_size / 2)
                      : (right ? maxX : 6),
                  minY + (maxY - minY) * app.aiFabY);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              AnimatedPositioned(
                duration: _drag == null
                    ? const Duration(milliseconds: 260)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                left: pos.dx,
                top: pos.dy.clamp(minY, maxY < minY ? minY : maxY),
                child: GestureDetector(
                  key: const ValueKey('ai.fab'),
                  onTap: _open,
                  onLongPress: _menu,
                  onPanStart: (_) {
                    _idleTimer?.cancel();
                    setState(() {
                      _idle = false;

                      _drag = Offset(right ? maxX : 6, pos.dy);
                    });
                  },
                  onPanUpdate: (d) => setState(() => _drag = Offset(
                      (_drag!.dx + d.delta.dx).clamp(0, maxX),
                      (_drag!.dy + d.delta.dy).clamp(minY, maxY))),
                  onPanEnd: (_) {
                    final p = _drag!;
                    final right = p.dx + _size / 2 > box.maxWidth / 2;
                    final fy = maxY > minY ? (p.dy - minY) / (maxY - minY) : 0.5;
                    unawaited(app.setAiFabPos(right ? 1 : 0, fy));
                    setState(() => _drag = null);
                    _armIdle();
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: docked ? 0.75 : 1,
                    child: Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        gradient: kAiGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x33204060),
                              blurRadius: 10,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}
