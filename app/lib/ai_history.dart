library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'ai_chat.dart';
import 'db.dart';

const String kAiChatDdl = '''
CREATE TABLE ai_chat (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ctx_key TEXT NOT NULL,
  title TEXT NOT NULL,
  subtitle TEXT,
  system TEXT,
  preview TEXT,
  msg_count INTEGER NOT NULL DEFAULT 0,
  created INTEGER NOT NULL,
  updated INTEGER NOT NULL,
  msgs TEXT NOT NULL
)''';
const String kAiChatIdx = 'CREATE INDEX idx_ai_chat_updated ON ai_chat(updated)';

const int kAiChatKeep = 200;

class AiConvSummary {
  final int id;
  final String key;
  final String title;
  final String subtitle;
  final String preview;
  final int count;
  final DateTime updated;

  const AiConvSummary({
    required this.id,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.count,
    required this.updated,
  });

  factory AiConvSummary.fromRow(Map<String, Object?> r) => AiConvSummary(
        id: r['id'] as int,
        key: (r['ctx_key'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        subtitle: (r['subtitle'] as String?) ?? '',
        preview: (r['preview'] as String?) ?? '',
        count: (r['msg_count'] as int?) ?? 0,
        updated: DateTime.fromMillisecondsSinceEpoch((r['updated'] as int?) ?? 0),
      );

  String get kind =>
      key.startsWith('word:') ? 'word' : key.startsWith('grammar:') ? 'grammar' : 'general';
}

class AiConv {
  final AiConvSummary head;
  final String system;
  final List<AiMessage> msgs;
  const AiConv(this.head, this.system, this.msgs);
}

Map<String, Object?> aiMessageToJson(AiMessage m) {
  var content = m.content;
  if (m.imageB64 != null) {
    content = content.isEmpty ? '（附图）' : '$content（附图）';
  }
  return {
    'r': m.role,
    'c': content,
    if (m.toolCalls.isNotEmpty)
      't': [
        for (final c in m.toolCalls) {'i': c.id, 'n': c.name, 'a': c.args},
      ],
    if (m.toolCallId != null) 'ti': m.toolCallId,
    if (m.toolName != null) 'tn': m.toolName,
    if (m.label != null) 'l': m.label,
  };
}

AiMessage aiMessageFromJson(Map<String, dynamic> j) => AiMessage(
      (j['r'] as String?) ?? 'user',
      (j['c'] as String?) ?? '',
      toolCalls: [
        for (final c in (j['t'] as List? ?? const []))
          if (c is Map)
            AiToolCall('${c['i'] ?? ''}', '${c['n'] ?? ''}', '${c['a'] ?? ''}'),
      ],
      toolCallId: j['ti'] as String?,
      toolName: j['tn'] as String?,
      label: j['l'] as String?,
    );

String aiMessagesEncode(List<AiMessage> msgs) =>
    jsonEncode([for (final m in msgs) aiMessageToJson(m)]);

List<AiMessage> aiMessagesDecode(String s) {
  try {
    final v = jsonDecode(s);
    if (v is! List) return [];
    return [
      for (final e in v)
        if (e is Map<String, dynamic>) aiMessageFromJson(e),
    ];
  } catch (_) {
    return [];
  }
}

String aiPreviewOf(List<AiMessage> msgs, {int n = 60}) {
  for (final m in msgs) {
    if (m.role == 'user' && m.content.trim().isNotEmpty) {
      final s = m.content.trim().replaceAll(RegExp(r'\s+'), ' ');
      return s.length <= n ? s : '${s.substring(0, n)}…';
    }
  }
  return '';
}

int _visibleCount(List<AiMessage> msgs) => msgs.where((m) => m.visible).length;

extension AppDbAiChat on AppDb {

  Future<int?> aiChatSave({
    int? id,
    required String key,
    required String title,
    required String subtitle,
    required String system,
    required List<AiMessage> msgs,
  }) async {
    final d = await db;
    if (msgs.isEmpty) {
      if (id != null) await d.delete('ai_chat', where: 'id = ?', whereArgs: [id]);
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = <String, Object?>{
      'ctx_key': key,
      'title': title,
      'subtitle': subtitle,
      'system': system,
      'preview': aiPreviewOf(msgs),
      'msg_count': _visibleCount(msgs),
      'updated': now,
      'msgs': aiMessagesEncode(msgs),
    };
    int? rid = id;
    if (rid != null) {
      final n = await d.update('ai_chat', row, where: 'id = ?', whereArgs: [rid]);
      if (n == 0) rid = null;
    }
    if (rid == null) {
      rid = await d.insert('ai_chat', {...row, 'created': now});

      await d.rawDelete(
          'DELETE FROM ai_chat WHERE id IN (SELECT id FROM ai_chat '
          'ORDER BY updated DESC LIMIT -1 OFFSET ?)',
          [kAiChatKeep]);
    }
    return rid;
  }

  Future<List<AiConvSummary>> aiChatList({String q = '', int limit = 300}) async {
    final d = await db;
    final s = q.trim();
    final rows = s.isEmpty
        ? await d.query('ai_chat',
            columns: _sumCols, orderBy: 'updated DESC', limit: limit)
        : await d.query('ai_chat',
            columns: _sumCols,
            where: 'title LIKE ? OR subtitle LIKE ? OR msgs LIKE ?',
            whereArgs: ['%$s%', '%$s%', '%$s%'],
            orderBy: 'updated DESC',
            limit: limit);
    return [for (final r in rows) AiConvSummary.fromRow(r)];
  }

  static const List<String> _sumCols = [
    'id', 'ctx_key', 'title', 'subtitle', 'preview', 'msg_count', 'updated',
  ];

  Future<AiConv?> aiChatGet(int id) async {
    final d = await db;
    final rows = await d.query('ai_chat', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _conv(rows.first);
  }

  Future<AiConv?> aiChatLatestForKey(String key) async {
    final d = await db;
    final rows = await d.query('ai_chat',
        where: 'ctx_key = ?',
        whereArgs: [key],
        orderBy: 'updated DESC',
        limit: 1);
    return rows.isEmpty ? null : _conv(rows.first);
  }

  AiConv _conv(Map<String, Object?> r) => AiConv(AiConvSummary.fromRow(r),
      (r['system'] as String?) ?? '', aiMessagesDecode((r['msgs'] as String?) ?? '[]'));

  Future<void> aiChatDelete(int id) async {
    final d = await db;
    await d.delete('ai_chat', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> aiChatClear() async {
    final d = await db;
    await d.delete('ai_chat');
  }

  Future<int> aiChatCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM ai_chat')) ?? 0;
  }
}
