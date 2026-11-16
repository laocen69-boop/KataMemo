import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> copyText(
  BuildContext context,
  String text, {
  String label = '已复制',
}) async {
  final value = text.trim();
  if (value.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    duration: const Duration(milliseconds: 1400),
    content: Text(label),
  ));
}
