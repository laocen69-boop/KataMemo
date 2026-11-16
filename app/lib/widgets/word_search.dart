library;

import 'package:flutter/material.dart';

import '../theme/k_colors.dart';
import '../db.dart';
import '../models.dart';

typedef SrsLevelMap
    = Map<String, ({int state, double stability, int reps, int lapses})>;

class WordSearchBar extends StatelessWidget {
  const WordSearchBar({
    super.key,
    required this.controller,
    required this.query,
    required this.onSubmit,
    required this.onClear,
    this.scope,
    this.autofocus = false,
  });

  final TextEditingController controller;

  final String query;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  final String? scope;

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          isDense: true,
          hintText: scope == null
              ? '搜全部词汇：印尼语或中文（可多个关键词，空格分隔）'
              : '在「$scope」里搜：印尼语或中文（可多个，空格分隔）',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '清空',
                  onPressed: onClear,
                ),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          filled: true,
          fillColor: context.k.nFaint2.withValues(alpha: 0.10),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

String matchHint(WordCard w, String q) {
  final k0 = q.split(RegExp(r'\s+')).first;
  final hasAscii = RegExp(r'[0-9a-zA-Z]').hasMatch(k0);
  final folded = hasAscii ? AppDb.fold(k0) : '';
  if (folded.isNotEmpty) {

    if (w.id == folded || w.id == AppDb.fold(q.trim())) return '完全匹配';

    if (w.id.startsWith('$folded ')) return '词组';
    if (w.id.startsWith(folded)) return '词形';
  }
  final zh = w.zhClean ?? '';
  if (zh.contains(q) || zh.contains(k0)) return '释义';
  return '例句';
}

Future<SrsLevelMap> loadLevels(AppDb db, List<WordCard> ws) =>
    db.srsLevels([for (final w in ws) w.id]);

MemoryStrength strengthOf(SrsLevelMap lv, String id) {
  final s = lv[id];
  if (s == null) return MemoryStrength.unknown;
  return MemoryStrength.of(stability: s.stability, reps: s.reps);
}
