library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../audio.dart';
import '../theme/k_colors.dart';

class WebAudioPackPill extends StatefulWidget {
  const WebAudioPackPill({super.key});

  @override
  State<WebAudioPackPill> createState() => _WebAudioPackPillState();
}

class _WebAudioPackPillState extends State<WebAudioPackPill> {
  bool _minimized = false;
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: AudioService.instance.webPackStatus,
      builder: (context, st, _) {
        if (!st.visible) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, box) {
            final k = context.k;
            final padTop = MediaQuery.paddingOf(context).top + 8;
            final maxW = box.maxWidth;
            final maxH = box.maxHeight;
            final wEst = _minimized ? 40.0 : 230.0;
            final hEst = _minimized ? 40.0 : 34.0;
            final defPos = Offset(
              (maxW - wEst - 12).clamp(8.0, maxW - wEst - 8),
              (maxH - hEst - 72).clamp(padTop, maxH - hEst - 16),
            );
            final cur = _pos ?? defPos;
            final left = cur.dx.clamp(8.0, (maxW - wEst - 8).clamp(8.0, maxW));
            final top = cur.dy.clamp(padTop, (maxH - hEst - 16).clamp(padTop, maxH));

            final pct =
                st.total > 0 ? ((st.done * 100) ~/ st.total).clamp(0, 100) : 0;
            final ratio =
                st.total > 0 ? (st.done / st.total).clamp(0.0, 1.0) : 0.0;

            void onDrag(DragUpdateDetails d) {
              setState(() {
                final base = _pos ?? Offset(left, top);
                _pos = Offset(
                  (base.dx + d.delta.dx).clamp(8.0, (maxW - wEst - 8).clamp(8.0, maxW)),
                  (base.dy + d.delta.dy).clamp(padTop, (maxH - hEst - 16).clamp(padTop, maxH)),
                );
              });
            }

            if (_minimized && !st.doneToast) {
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    child: GestureDetector(
                      onPanUpdate: onDrag,
                      onTap: () => setState(() => _minimized = false),
                      child: Material(
                        color: k.surface.withValues(alpha: 0.86),
                        elevation: 2,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: k.line, width: 0.8),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  value: ratio > 0 ? ratio : null,
                                  strokeWidth: 2.2,
                                  color: st.paused ? k.t3 : k.brand,
                                  backgroundColor: k.tint,
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: k.t2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final label = st.doneToast
                ? '离线语音已全部就绪'
                : (st.paused
                    ? '已暂停 ${st.done}/${st.total}'
                    : '语音缓存 ${st.done}/${st.total}');
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: GestureDetector(
                    onPanUpdate: onDrag,
                    child: Material(
                      color: k.surface.withValues(alpha: 0.94),
                      elevation: 3,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: st.doneToast ? k.brand : k.line,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: st.doneToast
                                  ? null
                                  : AudioService.instance.toggleBackgroundWebPack,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (st.doneToast)
                                    Icon(Icons.check_circle_rounded,
                                        size: 15, color: k.brand)
                                  else if (st.paused)
                                    Icon(Icons.play_arrow_rounded,
                                        size: 16, color: k.brand)
                                  else
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        value: ratio > 0 ? ratio : null,
                                        strokeWidth: 2,
                                        color: k.brand,
                                        backgroundColor: k.tint,
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: st.doneToast ? k.deep : k.t2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!st.doneToast) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _minimized = true),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(Icons.minimize_rounded,
                                      size: 14, color: k.t3),
                                ),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: AudioService.instance.dismissWebPackPill,
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child:
                                      Icon(Icons.close, size: 13, color: k.t3),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
