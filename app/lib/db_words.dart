part of 'db.dart';

extension AppDbWords on AppDb {

  Future<void> upsertWords(List<Map<String, Object?>> rows) async {
    final d = await db;
    final batch = d.batch();
    for (final r in rows) {
      batch.insert('words', r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> clearWords() async {
    final d = await db;
    await d.delete('words', where: 'COALESCE(user_word, 0) = 0');
  }

  Future<int> countUserWords() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM words WHERE COALESCE(user_word, 0) = 1');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<WordCard>> userWords(
      {String? q, int limit = 2000, String sort = 'created'}) async {
    final d = await db;
    final kw = (q ?? '').trim();
    final args = <Object?>[];
    var where = 'COALESCE(user_word, 0) = 1';
    if (kw.isNotEmpty) {
      where += " AND (word LIKE ? OR COALESCE(zh,'') LIKE ?)";
      args
        ..add('%$kw%')
        ..add('%$kw%');
    }
    final order = switch (sort) {
      'alpha' => 'word ASC',
      'alphaDesc' => 'word DESC',
      'class' => "COALESCE(word_class,'') ASC, word ASC",
      _ => 'rowid DESC',
    };
    args.add(limit);
    final rows = await d.rawQuery(
        'SELECT * FROM words WHERE $where ORDER BY $order LIMIT ?', args);
    return [for (final r in rows) WordCard.fromDb(r)];
  }

  Future<({String? id, WordCard? existed})> createUserWord({
    required String word,
    required String zh,
    String? wordClass,
    List<({String i, String? z})> examples = const [],
    String? mnemonic,
    List<UserBlock> userBlocks = const [],
    String? cardOrder,
  }) async {
    final id = AppDb.fold(word);
    if (id.isEmpty || word.trim().isEmpty) return (id: null, existed: null);
    final dup = await searchWords(id);
    if (dup != null) return (id: null, existed: dup);
    final builtInAudio =
        await AudioService.instance.resolveBuiltInAudio(word, folded: id);
    final autoTopics = classifyTopics(word: word, zh: zh);
    final d = await db;
    await d.insert(
        'words',
        {
          'id': id,
          'word': word.trim(),
          'zh': zh.trim(),
          if ((wordClass ?? '').isNotEmpty) 'word_class': wordClass,
          if (autoTopics.isNotEmpty) 'topics': jsonEncode(autoTopics),
          if (AppDb.encodeExamples(examples) != null)
            'examples': AppDb.encodeExamples(examples),
          if ((mnemonic ?? '').trim().isNotEmpty) 'mnemonic': mnemonic!.trim(),
          if (builtInAudio != null) 'audio_ardi': builtInAudio,
          'user_word': 1,
          if (userBlocks.isNotEmpty)
            'user_blocks': jsonEncode([for (final b in userBlocks) b.toMap()]),
          if ((cardOrder ?? '').isNotEmpty) 'card_order': cardOrder,
          'enabled': 1,
          'favorite': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return (id: id, existed: null);
  }

  Future<({String? id, WordCard? existed})> updateUserWord(
    String oldId, {
    required String word,
    required String zh,
    String? wordClass,
    List<({String i, String? z})> examples = const [],
    String? mnemonic,
    List<UserBlock> userBlocks = const [],
    String? cardOrder,
  }) async {
    final newId = AppDb.fold(word);
    if (newId.isEmpty || word.trim().isEmpty) return (id: null, existed: null);
    final d = await db;
    final prevRows = await d.query('words',
        columns: ['audio_ardi'], where: 'id = ?', whereArgs: [oldId], limit: 1);
    final prevAu = prevRows.isEmpty
        ? null
        : (prevRows.first['audio_ardi'] as String?);
    if (newId != oldId) {
      final dup = await searchWords(newId);
      if (dup != null && dup.id != oldId) return (id: null, existed: dup);

      for (final t in ['srs', 'plan', 'study_log']) {
        try {
          await d.update(t, {'card_id': newId},
              where: 'card_id = ?', whereArgs: [oldId]);
        } catch (_) {}
      }
      await d.delete('words', where: 'id = ?', whereArgs: [oldId]);
    }
    final String? keptOrBuiltInAu;
    if (prevAu != null && prevAu.startsWith(kUserAudioPrefix)) {
      keptOrBuiltInAu = prevAu;
    } else if (newId == oldId && prevAu != null && prevAu.isNotEmpty) {
      keptOrBuiltInAu = prevAu;
    } else {
      keptOrBuiltInAu =
          await AudioService.instance.resolveBuiltInAudio(word, folded: newId);
    }
    final autoTopics = classifyTopics(word: word, zh: zh);
    await d.insert(
        'words',
        {
          'id': newId,
          'word': word.trim(),
          'zh': zh.trim(),
          if ((wordClass ?? '').isNotEmpty) 'word_class': wordClass,
          if (autoTopics.isNotEmpty) 'topics': jsonEncode(autoTopics),
          if (AppDb.encodeExamples(examples) != null)
            'examples': AppDb.encodeExamples(examples),
          if ((mnemonic ?? '').trim().isNotEmpty) 'mnemonic': mnemonic!.trim(),
          if (keptOrBuiltInAu != null && keptOrBuiltInAu.isNotEmpty)
            'audio_ardi': keptOrBuiltInAu,
          'user_word': 1,
          if (userBlocks.isNotEmpty)
            'user_blocks': jsonEncode([for (final b in userBlocks) b.toMap()]),
          if ((cardOrder ?? '').isNotEmpty) 'card_order': cardOrder,
          'enabled': 1,
          'favorite': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return (id: newId, existed: null);
  }

  Future<void> deleteUserWord(String id) async {
    final d = await db;
    await d.delete('words',
        where: 'id = ? AND COALESCE(user_word, 0) = 1', whereArgs: [id]);
    await d.delete('plan', where: 'card_id = ?', whereArgs: [id]);
    await d.delete('srs', where: 'card_id = ?', whereArgs: [id]);
    await d.delete('study_log', where: 'card_id = ?', whereArgs: [id]);
  }

  Future<int> saveWordList(String name, List<String> ids) async {
    final d = await db;
    final payload = {
      'name': name,
      'ids_json': jsonEncode(ids),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };
    final exist = await d.query('word_list',
        columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    if (exist.isNotEmpty) {
      final id = exist.first['id'] as int;
      await d.update('word_list', payload, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return d.insert('word_list', payload);
  }

  int _idsJsonLen(Object? raw) {
    try {
      return (jsonDecode(raw as String) as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<(int, String, int)>> listWordLists() async {
    final d = await db;
    final rows = await d.query('word_list',
        columns: ['id', 'name', 'ids_json'],
        orderBy: 'created_at DESC, id DESC');
    return [
      for (final r in rows)
        (
          r['id'] as int,
          r['name'] as String,
          _idsJsonLen(r['ids_json']),
        )
    ];
  }

  Future<List<String>> wordListIds(int id) async {
    final d = await db;
    final rows = await d.query('word_list',
        columns: ['ids_json'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return const [];
    try {
      return (jsonDecode(rows.first['ids_json'] as String) as List)
          .map((e) => '$e')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteWordList(int id) async {
    final d = await db;
    await d.delete('word_list', where: 'id = ?', whereArgs: [id]);
  }

  Future<int?> createWordList(String name, List<String> ids) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    if (await _wordListNameTaken(n)) return null;
    final d = await db;
    return d.insert('word_list', {
      'name': n,
      'ids_json': jsonEncode(_dedupeIds(ids).take(5000).toList()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<bool> renameWordList(int id, String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (await _wordListNameTaken(n, exceptId: id)) return false;
    final d = await db;
    final changed = await d.update('word_list', {'name': n},
        where: 'id = ?', whereArgs: [id]);
    return changed > 0;
  }

  Future<void> updateWordListIds(int id, List<String> ids) async {
    final d = await db;
    await d.update(
        'word_list',
        {
          'ids_json':
              jsonEncode(_dedupeIds(ids).take(5000).toList()),
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<bool> _wordListNameTaken(String name, {int? exceptId}) async {
    final d = await db;
    final rows = await d.query(
      'word_list',
      columns: ['id'],
      where: exceptId == null
          ? 'name = ? COLLATE NOCASE'
          : 'name = ? COLLATE NOCASE AND id != ?',
      whereArgs: exceptId == null ? [name] : [name, exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  List<String> _parseIds(Object? raw) {
    try {
      return (jsonDecode(raw as String) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  List<String> _dedupeIds(List<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (seen.add(id)) id
    ];
  }

  Future<List<WordListStat>> wordListStats() async {
    final d = await db;
    final rows = await d.query('word_list',
        columns: ['id', 'name', 'ids_json'],
        orderBy: 'created_at DESC, id DESC');
    return _statsForRows(rows);
  }

  Future<WordListStat?> wordListStat(int id) async {
    final d = await db;
    final rows = await d.query('word_list',
        columns: ['id', 'name', 'ids_json'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    final out = await _statsForRows(rows);
    return out.isEmpty ? null : out.first;
  }

  Future<List<WordListStat>> _statsForRows(
      List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const [];
    final d = await db;
    final byList = <int, List<String>>{};
    final all = <String>{};
    for (final r in rows) {
      final ids = _parseIds(r['ids_json']);
      byList[r['id'] as int] = ids;
      all.addAll(ids);
    }
    final ids = all.toList();
    final enabled = <String, bool>{};
    final planned = <String>{};
    final hasSrs = <String>{};
    for (var i = 0; i < ids.length; i += 800) {
      final chunk = ids.sublist(i, (i + 800).clamp(0, ids.length));
      final ph = List.filled(chunk.length, '?').join(',');
      final wr = await d.rawQuery(
          'SELECT id, COALESCE(enabled, 0) AS e FROM words WHERE id IN ($ph)',
          chunk);
      for (final r in wr) {
        enabled[r['id'] as String] = (r['e'] as int? ?? 0) == 1;
      }
      final pr = await d.rawQuery(
          'SELECT card_id FROM plan WHERE card_id IN ($ph)', chunk);
      for (final r in pr) {
        planned.add(r['card_id'] as String);
      }
      final sr = await d
          .rawQuery('SELECT card_id FROM srs WHERE card_id IN ($ph)', chunk);
      for (final r in sr) {
        hasSrs.add(r['card_id'] as String);
      }
    }
    return [
      for (final r in rows)
        _statOf(
          id: r['id'] as int,
          name: r['name'] as String,
          ids: byList[r['id'] as int] ?? const [],
          enabled: enabled,
          planned: planned,
          hasSrs: hasSrs,
        )
    ];
  }

  WordListStat _statOf({
    required int id,
    required String name,
    required List<String> ids,
    required Map<String, bool> enabled,
    required Set<String> planned,
    required Set<String> hasSrs,
  }) {
    var count = 0, joined = 0, learned = 0;
    final seen = <String>{};
    for (final wid in ids) {
      if (!seen.add(wid)) continue;
      if (!enabled.containsKey(wid)) continue;
      count++;
      final inMemory = enabled[wid] == true &&
          (planned.contains(wid) || hasSrs.contains(wid));
      if (!inMemory) continue;
      joined++;
      if (hasSrs.contains(wid)) learned++;
    }
    return (
      id: id,
      name: name,
      count: count,
      joined: joined,
      learned: learned,
    );
  }
}
