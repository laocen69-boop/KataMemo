import 'package:flutter/material.dart';

import '../cloze.dart' show foldCloze;
import '../theme/k_colors.dart';

class LetterSlots extends StatelessWidget {
  const LetterSlots({
    super.key,
    required this.target,
    this.typed = '',
    this.verdict = false,
    this.tile = 26,
  });

  final String target;

  final String typed;

  final bool verdict;

  final double tile;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final want = foldCloze(target);
    final got = foldCloze(typed);
    final n = want.length > got.length ? got.length : want.length;
    final total = want.length > got.length ? want.length : got.length;

    final cells = <Widget>[];
    var li = 0;
    void slot() {
      final i = li++;
      final has = i < got.length;
      final inTarget = i < want.length;
      final ok = has && inTarget && got[i] == want[i];
      Color fill = k.surface;
      Color line = k.border;
      Color ink = k.text;
      if (verdict) {
        if (has && ok) {
          fill = k.mntint;
          line = k.brand;
          ink = k.deep;
        } else if (has || inTarget) {

          fill = const Color(0x1AD96A5A);
          line = const Color(0xFFD96A5A);
          ink = const Color(0xFFB4443A);
        }
      } else if (has) {
        fill = k.mntint;
        line = k.brand;
        ink = k.deep;
      }
      cells.add(Container(
        width: tile,
        height: tile * 1.18,
        margin: EdgeInsets.symmetric(horizontal: tile * 0.07),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(tile * 0.26),
          border: Border.all(color: line, width: has || verdict ? 1.2 : 0.8),
        ),
        child: has
            ? Text(got[i],
                style: TextStyle(
                    fontSize: tile * 0.62,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: ink))
            : null,
      ));
    }

    for (final r in target.runes) {
      final ch = String.fromCharCode(r);
      if (foldCloze(ch).isNotEmpty) {
        slot();
      } else if (ch.trim().isEmpty) {
        cells.add(SizedBox(width: tile * 0.5));
      } else {
        cells.add(Container(
          width: tile * 0.3,
          alignment: Alignment.center,
          child: Text(ch,
              style: TextStyle(fontSize: tile * 0.6, color: k.t3, height: 1.0)),
        ));
      }
    }
    while (li < total) {
      slot();
    }

    if (cells.isEmpty || n < 0) return const SizedBox.shrink();

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: cells),
    );
  }
}
