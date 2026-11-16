part of 'db.dart';

extension AppDbCard on AppDb {

  Future<WordCard?> getWord(String id) async {
    final d = await db;
    final rows =
        await d.query('words', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WordCard.fromDb(rows.first);
  }

  Future<Map<String, String>> derivationZhMap(List<String> forms) async {
    final keys = <String>{
      for (final f in forms)
        if (f.trim().isNotEmpty) AppDb.fold(f.trim()),
    }.toList();
    if (keys.isEmpty) return const {};
    final d = await db;
    final rows = await d.query('words',
        columns: ['id', 'zh'],
        where:
            'id IN (${List.filled(keys.length, '?').join(',')}) AND zh IS NOT NULL',
        whereArgs: keys);
    final out = <String, String>{};
    for (final r in rows) {
      final zh = (r['zh'] as String?)?.trim();
      if (zh != null && zh.isNotEmpty) out[r['id'] as String] = zh;
    }
    return out;
  }

  Future<Set<String>> selectedDerivedIds() async {
    final d = await db;
    final rows = await d.query('words',
        columns: ['id'], where: "tier = 'derived' AND enabled = 1");
    return {for (final r in rows) r['id'] as String};
  }

  Future<void> setEnabled(List<String> ids, bool enabled) async {
    final d = await db;
    final batch = d.batch();
    for (final id in ids) {
      batch.update('words', {'enabled': enabled ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> toggleFavorite(String id) async {
    final d = await db;
    final rows = await d.query('words',
        columns: ['favorite'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final fav = rows.first['favorite'] as int? ?? 0;
    await d.update('words', {'favorite': fav == 1 ? 0 : 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveMnemonic(String id, String text) =>
      saveEdit(id, 'mnemonic', text);

  Future<void> saveExamples(String id, List<WordExample> examples) => saveEdit(
      id,
      'examples',
      WordCard.encodeMaps([for (final e in examples) e.toMap()]));

  Future<void> saveEdit(String id, String field, String? value) async {
    if (!AppDb._editableFields.contains(field)) {
      throw ArgumentError('不可编辑的字段: $field');
    }
    final d = await db;
    final v = (value == null || value.trim().isEmpty) ? null : value;
    await d.transaction((txn) async {
      if (v == null) {
        await txn.delete('user_edit',
            where: 'card_id = ? AND field = ?', whereArgs: [id, field]);
      } else {
        await txn.insert(
            'user_edit',
            {
              'card_id': id,
              'field': field,
              'value': v,
              'ts': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.update('words', {field: v}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> applyUserEdits() async {
    final d = await db;
    final rows = await d.query('user_edit');
    if (rows.isEmpty) return 0;
    final batch = d.batch();
    var n = 0;
    for (final r in rows) {
      final field = r['field'] as String? ?? '';
      if (!AppDb._editableFields.contains(field)) continue;
      batch.update('words', {field: r['value']},
          where: 'id = ?', whereArgs: [r['card_id']]);
      n++;
    }
    await batch.commit(noResult: true);
    return n;
  }

  Future<Map<String, String>> userEdits(String id) async {
    final d = await db;
    final rows =
        await d.query('user_edit', where: 'card_id = ?', whereArgs: [id]);
    return {
      for (final r in rows)
        if (r['value'] != null) r['field'] as String: r['value'] as String,
    };
  }

  Future<List<WordCard>> favorites() async {
    final d = await db;

    final rows = await d.query('words',
        where: 'favorite = 1', orderBy: 'word COLLATE NOCASE ASC');
    return rows.map(WordCard.fromDb).toList();
  }

  Future<int> purgeRetiredCards() async {
    final d = await db;
    var n = 0;
    for (final id in AppDb.kRetiredCards) {
      n += await d.delete('srs', where: 'card_id = ?', whereArgs: [id]);
      n += await d.delete('plan', where: 'card_id = ?', whereArgs: [id]);
    }
    return n;
  }

  Future<int> remapMergedCards() async {
    final d = await db;
    var moved = 0;
    for (final e in AppDb.kMergedCards.entries) {
      final from = await d.query('srs',
          where: 'card_id = ?', whereArgs: [e.key], limit: 1);
      if (from.isEmpty) continue;
      final src = FsrsState.fromMap(from.first);
      final firstSeen = from.first['first_seen'] as int?;

      final to = await d.query('srs',
          where: 'card_id = ?', whereArgs: [e.value], limit: 1);
      if (to.isEmpty) {
        await d.insert('srs', {...src.toMap(e.value), 'first_seen': firstSeen},
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        final dst = FsrsState.fromMap(to.first);
        final keepSrc = src.stability <= dst.stability;
        final pick = keepSrc ? src : dst;
        final pickSeen = keepSrc ? firstSeen : to.first['first_seen'] as int?;

        final seen = (firstSeen == null)
            ? pickSeen
            : (pickSeen == null
                ? firstSeen
                : (firstSeen < pickSeen ? firstSeen : pickSeen));
        await d.insert('srs', {...pick.toMap(e.value), 'first_seen': seen},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await d.delete('srs', where: 'card_id = ?', whereArgs: [e.key]);

      final oldPlan = await d.query('plan',
          columns: ['ts'], where: 'card_id = ?', whereArgs: [e.key], limit: 1);
      if (oldPlan.isNotEmpty) {
        final host = await d.query('plan',
            columns: ['ts'],
            where: 'card_id = ?',
            whereArgs: [e.value],
            limit: 1);
        final tsOld = oldPlan.first['ts'] as int? ?? 0;
        final tsHost = host.isEmpty ? null : host.first['ts'] as int?;
        final ts = (tsHost == null || tsOld < tsHost) ? tsOld : tsHost;
        await d.insert('plan', {'card_id': e.value, 'ts': ts},
            conflictAlgorithm: ConflictAlgorithm.replace);
        await d.delete('plan', where: 'card_id = ?', whereArgs: [e.key]);
      }
      moved++;
    }
    return moved;
  }
}
