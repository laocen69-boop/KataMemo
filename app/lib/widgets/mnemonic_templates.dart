library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';

class MnemonicTemplates extends StatelessWidget {
  const MnemonicTemplates({super.key, required this.controller});

  final TextEditingController controller;

  static const List<({String label, String text})> templates = [
    (label: '拆词缀', text: '词根 ___ + 词缀 ___ → ___'),
    (label: '同源词', text: '≈ 英语 / 荷兰语 / 葡语 / 阿拉伯语 ___'),
    (label: '画面', text: '画面：___'),
  ];

  void _insert(String text) {
    final v = controller.value;
    final base = v.text;
    final hasSel = v.selection.isValid && v.selection.start >= 0;
    final start = hasSel ? v.selection.start : base.length;
    final end = hasSel ? v.selection.end : base.length;
    final glue =
        (base.isNotEmpty && start == base.length && !base.endsWith('\n'))
            ? '\n'
            : '';
    final insert = '$glue$text';
    final next = base.replaceRange(start, end, insert);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final t in templates)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _insert(t.text),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: k.tint,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: k.catEdge, width: 0.8),
              ),
              child: Text('＋ ${t.label}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: k.deep)),
            ),
          ),
      ],
    );
  }
}
