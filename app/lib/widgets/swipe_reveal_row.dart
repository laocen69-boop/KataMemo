import 'package:flutter/material.dart';

import '../theme/k_colors.dart';

class SwipeRevealRow extends StatefulWidget {
  const SwipeRevealRow({
    super.key,
    required this.child,
    required this.enabled,
    required this.open,
    required this.actionLabel,
    required this.onAction,
    required this.onOpenChanged,
    this.destructive = false,
    this.actionWidth = 104,
    this.actionKey,
    this.height = 58,
  });

  final Widget child;
  final bool enabled;
  final bool open;
  final String actionLabel;
  final VoidCallback onAction;
  final ValueChanged<bool> onOpenChanged;
  final bool destructive;
  final double actionWidth;

  final Key? actionKey;

  final double height;

  @override
  State<SwipeRevealRow> createState() => _SwipeRevealRowState();
}

class _SwipeRevealRowState extends State<SwipeRevealRow> {
  double _dx = 0;
  bool _dragging = false;
  bool _ignore = false;

  @override
  void initState() {
    super.initState();
    _dx = widget.open ? widget.actionWidth : 0;
  }

  @override
  void didUpdateWidget(covariant SwipeRevealRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open && !_dragging) {
      setState(() => _dx = widget.open ? widget.actionWidth : 0);
    }
  }

  void _snap(bool open) {
    setState(() => _dx = open ? widget.actionWidth : 0);
    widget.onOpenChanged(open);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final k = context.k;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.destructive
        ? (dark ? const Color(0xFF3A2222) : const Color(0xFFFDECEC))
        : k.tint;
    final fg = widget.destructive
        ? (dark ? const Color(0xFFFF9B9B) : const Color(0xFFB3261E))
        : k.deep;

    return SizedBox(

      height: widget.height,
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dx > 1 ? () => _snap(false) : null,
            onHorizontalDragStart: (d) {
              _dragging = true;

              _ignore = d.globalPosition.dx < 24;
            },
            onHorizontalDragUpdate: (d) {
              if (_ignore) return;
              setState(() {
                _dx = (_dx - d.delta.dx).clamp(0.0, widget.actionWidth);
              });
            },
            onHorizontalDragEnd: (d) {
              _dragging = false;
              final v = d.primaryVelocity ?? 0;
              final open = _dx > widget.actionWidth / 2 || v < -300;
              _snap(open);
            },
            child: IgnorePointer(

              ignoring: _dx > 1,
              child: ColoredBox(color: k.surface, child: widget.child),
            ),
          ),
          AnimatedPositioned(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            right: -widget.actionWidth + _dx,
            top: 0,
            bottom: 0,
            width: widget.actionWidth,
            child: GestureDetector(
              key: widget.actionKey,
              behavior: HitTestBehavior.opaque,
              onTap: widget.onAction,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                      left: BorderSide(color: k.line, width: 0.5)),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          widget.destructive
                              ? Icons.close
                              : Icons.flag_outlined,
                          size: 14,
                          color: fg),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.actionLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: fg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SwipeTargetHint extends StatelessWidget {
  const SwipeTargetHint(
      {super.key, required this.onDismiss, this.compact = false});

  final VoidCallback onDismiss;
  final bool compact;

  Widget _close(KColors k) => GestureDetector(
        key: const Key('swipe.hint.close'),
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(
          width: compact ? 18 : 24,
          height: compact ? 18 : 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: k.surface,
            shape: BoxShape.circle,
            border: Border.all(color: k.line, width: 0.5),
          ),
          child: Icon(Icons.close, size: compact ? 11 : 14, color: k.t3),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swipe_right_alt, size: 13, color: k.t3),
          const SizedBox(width: 4),
          Text('左滑可设目标',
              style: TextStyle(fontSize: 10.5, color: k.t3)),
          const SizedBox(width: 6),
          _close(k),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: k.tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
            child: Row(
              children: [
                Icon(Icons.swipe_right_alt, size: 18, color: k.deep),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('左滑卡组可设为学习目标',
                      style: TextStyle(fontSize: 12.5, color: k.deep)),
                ),
              ],
            ),
          ),
          Positioned(top: 2, right: 2, child: _close(k)),
        ],
      ),
    );
  }
}
