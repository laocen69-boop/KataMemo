import 'package:flutter/material.dart';

import '../theme/k_colors.dart';

class KSwitch extends StatelessWidget {
  final bool value;

  final ValueChanged<bool>? onChanged;

  const KSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 28,
          decoration: BoxDecoration(
            color: value ? k.brand : k.track,
            borderRadius: BorderRadius.circular(14),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? k.onbrand : k.knob,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
