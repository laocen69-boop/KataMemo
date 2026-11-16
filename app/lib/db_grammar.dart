part of 'db.dart';

extension AppDbGrammar on AppDb {

  void _scheduleGrammarFlush() {
    _gramTimer?.cancel();
    _gramTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(flushGrammarWrites());
    });
  }

  Future<void> flushGrammarWrites() async {
    _gramTimer?.cancel();
    _gramTimer = null;
    if (_gramPending.isEmpty && _gramLastDirty == null) return;
    final d = await db;
    final batch = Map<String, _GramPending>.from(_gramPending);
    final last = _gramLastDirty;
    _gramPending.clear();
    _gramLastDirty = null;
    for (final e in batch.entries) {
      final cur = await d.query('grammar_progress',
          where: 'card_id = ?', whereArgs: [e.key], limit: 1);
      final base = cur.isEmpty ? null : GrammarProgressRow.fromRow(cur.first);
      final p = e.value;
      final row = GrammarProgressRow(
        cardId: e.key,

        seenAt: _maxInt2(base?.seenAt, p.seenAt),
        starred: p.starred ?? base?.starred ?? false,
        drillOk: (base?.drillOk ?? 0) + p.okAdd,
        drillTotal: (base?.drillTotal ?? 0) + p.totalAdd,
      );
      await d.insert('grammar_progress', row.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (last != null) await metaSet(AppDb._kGramLast, last);
  }

  Future<void> markGrammarSeen(String cardId, {int? at}) async {
    final t = at ?? DateTime.now().millisecondsSinceEpoch;
    final p = _gramPending.putIfAbsent(cardId, _GramPending.new);
    p.seenAt = _maxInt2(p.seenAt, t);
    _scheduleGrammarFlush();
  }

  Future<void> setGrammarStarred(String cardId, bool on) async {
    _gramPending.putIfAbsent(cardId, _GramPending.new).starred = on;
    _scheduleGrammarFlush();
  }

  Future<void> recordGrammarDrill(String cardId, bool ok) async {
    final p = _gramPending.putIfAbsent(cardId, _GramPending.new);
    p.okAdd += ok ? 1 : 0;
    p.totalAdd += 1;
    _scheduleGrammarFlush();
  }

  Future<GrammarProgressRow?> grammarProgress(String cardId) async {
    final d = await db;
    final r = await d.query('grammar_progress',
        where: 'card_id = ?', whereArgs: [cardId], limit: 1);
    return r.isEmpty ? null : GrammarProgressRow.fromRow(r.first);
  }

  Future<Map<String, GrammarProgressRow>> allGrammarProgress() async {
    final d = await db;
    final rows = await d.query('grammar_progress');
    return {
      for (final r in rows)
        (r['card_id'] as String): GrammarProgressRow.fromRow(r)
    };
  }

  Future<String?> grammarLastCard() => metaGet(AppDb._kGramLast);

  Future<void> setGrammarLastCard(String cardId) async {
    _gramLastDirty = cardId;
    _scheduleGrammarFlush();
  }

  Future<String?> grammarFilter() => metaGet(AppDb._kGramFilter);
  Future<void> setGrammarFilter(String v) => metaSet(AppDb._kGramFilter, v);

  Future<List<GEditRow>> grammarEdits(String scope, String pageId) async {
    final d = await db;
    final rows = await d.query('grammar_edit',
        where: 'scope = ? AND page_id = ?', whereArgs: [scope, pageId]);
    return [for (final r in rows) GEditRow.fromRow(r)];
  }

  Future<List<GEditRow>> allGrammarEdits(String scope) async {
    final d = await db;
    final rows = await d.query('grammar_edit',
        where: 'scope = ?', whereArgs: [scope], orderBy: 'page_id, ts');
    return [for (final r in rows) GEditRow.fromRow(r)];
  }

  Future<void> saveGrammarEdit(GEditRow row) async {
    final d = await db;
    await d.insert('grammar_edit', row.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteGrammarEdit(
      String scope, String pageId, String key) async {
    final d = await db;
    await d.delete('grammar_edit',
        where: 'scope = ? AND page_id = ? AND block_key = ?',
        whereArgs: [scope, pageId, key]);
  }

  Future<void> resetGrammarPage(String scope, String pageId) async {
    final d = await db;
    await d.delete('grammar_edit',
        where: 'scope = ? AND page_id = ?', whereArgs: [scope, pageId]);
  }
}
