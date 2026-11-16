library;

import 'dart:convert';
import 'dart:math' as math;

part 'models_word_parts.dart';
part 'models_memory.dart';
part 'models_word_card.dart';

class BookNode {
  final String id;
  final String name;
  final String? parent;
  final int count;

  final Map<String, dynamic>? filter;
  final String desc;

  final List<String> aliases;

  final List<String> order;

  final String group;

  const BookNode({
    required this.id,
    required this.name,
    this.parent,
    required this.count,
    this.filter,
    this.desc = '',
    this.aliases = const [],
    this.order = const [],
    this.group = '',
  });

  factory BookNode.fromJson(Map<String, dynamic> m) => BookNode(
        id: m['id'] as String,
        name: m['name'] as String,
        parent: m['parent'] as String?,
        count: m['count'] as int? ?? 0,
        filter: m['filter'] as Map<String, dynamic>?,
        desc: m['desc'] as String? ?? '',
        aliases: (m['aliases'] as List?)?.map((e) => '$e').toList() ??
            const <String>[],
        order: (m['order'] as List?)?.map((e) => '$e').toList() ??
            const <String>[],
        group: m['group'] as String? ?? '',
      );

  bool matchesBookQuery(String q) {
    final needle = q.toLowerCase();
    if (needle.isEmpty) return false;
    if (name.toLowerCase().contains(needle)) return true;
    for (final a in aliases) {
      if (a.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  bool get clickable => filter != null;
}
