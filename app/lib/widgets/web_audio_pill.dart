library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../audio.dart';
import '../theme/k_colors.dart';

class WebAudioPackPill extends StatelessWidget {
  const WebAudioPackPill({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: AudioService.instance.webPackStatus,
      builder: (context, st, _) {
        if (!st.visible) return const SizedBox.shrink();
        final k = context.k;
        final pct = st.total > 0 ? ((st.done * 100) ~/ st.total).clamp(0, 100) : 0;
        final ratio = st.total > 0 ? (st.done / st.total).clamp(0.0, 1.0) : 0.0;
        final label = st.doneToast
            ? '离线语音已全部就绪'
            : (st.paused
                ? '语音已暂停 ${st.done}/${st.total} · 点此继续'
                : '离线语音缓存 ${st.done}/${st.total} ($pct%)');
        return Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: k.surface.withValues(alpha: 0.96),
            elevation: 3,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: st.doneToast ? null : AudioService.instance.toggleBackgroundWebPack,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
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
                    if (st.doneToast)
                      Icon(Icons.check_circle_rounded, size: 15, color: k.brand)
                    else if (st.paused)
                      Icon(Icons.pause_circle_outline_rounded, size: 15, color: k.t2)
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
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: st.doneToast ? k.deep : k.t2,
                      ),
                    ),
                    if (!st.doneToast) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: AudioService.instance.dismissWebPackPill,
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close, size: 13, color: k.t3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
