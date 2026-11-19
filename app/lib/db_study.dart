part of 'db.dart';

extension AppDbStudy on AppDb {

  Future<Map<String, ({int state, double stability, int reps, int lapses})>>
      srsLevels(List<String> ids) async {
    final out =
        <String, ({int state, double stability, int reps, int lapses})>{};
    if (ids.isEmpty) return out;
    final d = await db;
    const chunk = 900;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      final rows = await d.rawQuery(
        'SELECT card_id, state, stability, reps, lapses FROM srs '
        'WHERE card_id IN (${List.filled(part.length, '?').join(',')})',
        part,
      );
      for (final r in rows) {
        out[r['card_id'] as String] = (
          state: r['state'] as int? ?? 0,
          stability: (r['stability'] as num?)?.toDouble() ?? 0,
          reps: r['reps'] as int? ?? 0,
          lapses: r['lapses'] as int? ?? 0,
        );
      }
    }
    return out;
  }

  Future<FsrsState?> getSrs(String cardId) async {
    final d = await db;
    final rows = await d.query('srs',
        where: 'card_id = ?', whereArgs: [cardId], limit: 1);
    return rows.isEmpty ? null : FsrsState.fromMap(rows.first);
  }

  Future<void> saveSrs(String cardId, FsrsState s) async {
    final d = await db;

    final prev = await d.query('srs',
        columns: ['first_seen'],
        where: 'card_id = ?',
        whereArgs: [cardId],
        limit: 1);
    final firstSeen =
        (prev.isEmpty ? null : prev.first['first_seen'] as int?) ??
            DateTime.now().millisecondsSinceEpoch;
    await d.insert('srs', {...s.toMap(cardId), 'first_seen': firstSeen},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> todayNewCount() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM srs WHERE first_seen >= ? AND card_id IN (SELECT id FROM words)',
        [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<Set<String>> todayNewIds() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final rows = await d.rawQuery(
        'SELECT card_id FROM srs WHERE first_seen >= ? AND card_id IN (SELECT id FROM words)',
        [start]);
    return {for (final r in rows) r['card_id'] as String};
  }

  Future<void> planWord(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final id in ids) {
      batch.insert('plan', {'card_id': id, 'ts': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await setEnabled(ids, true);
  }

  Future<void> unenroll(List<String> ids) async {
    if (ids.isEmpty) return;
    await unplanWords(ids);
    await setEnabled(ids, false);
  }

  Future<void> unplanWords(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final id in ids) {
      batch.delete('plan', where: 'card_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replayPlannedDerived() async {
    final d = await db;
    await d.rawUpdate("UPDATE words SET enabled = 1 "
        "WHERE tier = 'derived' AND id IN (SELECT card_id FROM plan)");
  }

  Future<bool> isPlanned(String id) async {
    final d = await db;
    final r =
        await d.query('plan', where: 'card_id = ?', whereArgs: [id], limit: 1);
    return r.isNotEmpty;
  }

  Future<Set<String>> plannedIds(List<String> ids) async {
    if (ids.isEmpty) return <String>{};
    final d = await db;
    final out = <String>{};

    for (var i = 0; i < ids.length; i += 800) {
      final chunk = ids.sublist(i, i + 800 > ids.length ? ids.length : i + 800);
      final rows = await d.rawQuery(
          'SELECT card_id FROM plan WHERE card_id IN '
          '(${List.filled(chunk.length, '?').join(',')})',
          chunk);
      for (final r in rows) {
        out.add(r['card_id'] as String);
      }
    }
    return out;
  }

  Future<List<String>> planRandom(
      Map<String, dynamic>? filter, int limit) async {
    if (limit <= 0) return const [];
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final rows = await d.rawQuery('''
      SELECT w.id FROM words w
      LEFT JOIN srs s ON s.card_id = w.id
      WHERE w.enabled = 1 AND s.card_id IS NULL AND $fw
        AND w.id NOT IN (SELECT card_id FROM plan)
      ORDER BY RANDOM() LIMIT ?
    ''', [...fa, limit]);
    final ids = [for (final r in rows) r['id'] as String];
    if (ids.isEmpty) return ids;
    await planWord(ids);
    return ids;
  }

  Future<bool> hasEnrolledCards() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT EXISTS(SELECT 1 FROM plan pl JOIN words w ON w.id = pl.card_id
                    WHERE w.enabled = 1)
          OR EXISTS(SELECT 1 FROM srs s JOIN words w ON w.id = s.card_id
                    WHERE w.enabled = 1) AS e
    ''');
    return (Sqflite.firstIntValue(r) ?? 0) != 0;
  }

  Future<int> planCount() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM plan WHERE card_id IN (SELECT id FROM words)');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> planByFilter(Map<String, dynamic>? filter,
      {int? limit, String sort = 'rank'}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final safeSort = AppDb.kSortModes.contains(sort) ? sort : 'rank';
    final rows = await d.rawQuery('''
      SELECT w.id FROM words w
      LEFT JOIN plan pl ON pl.card_id = w.id
      LEFT JOIN srs s ON s.card_id = w.id
      WHERE ${AppDb.listVisibleSql} AND $fw
        AND pl.card_id IS NULL AND s.card_id IS NULL
      ORDER BY ${AppDb.orderByClause(safeSort)}${limit == null ? '' : ' LIMIT ?'}
    ''', [...fa, if (limit != null) limit]);
    final ids = [for (final r in rows) r['id'] as String];
    if (ids.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = d.batch();
    for (final id in ids) {
      batch.insert('plan', {'card_id': id, 'ts': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await setEnabled(ids, true);
    return ids.length;
  }

  Future<List<String>> selectableIdsByFilter(Map<String, dynamic>? filter,
      {int? limit,
      String sort = 'rank',
      List<String> exclude = const []}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final safeSort = AppDb.kSortModes.contains(sort) ? sort : 'rank';
    final ex = exclude.where((e) => e.isNotEmpty).toList();
    final rows = await d.rawQuery('''
      SELECT w.id FROM words w
      LEFT JOIN plan pl ON pl.card_id = w.id
      LEFT JOIN srs s ON s.card_id = w.id
      WHERE ${AppDb.listVisibleSql} AND $fw
        AND pl.card_id IS NULL AND s.card_id IS NULL
        ${ex.isEmpty ? '' : 'AND w.id NOT IN (${List.filled(ex.length, '?').join(',')})'}
      ORDER BY ${AppDb.orderByClause(safeSort)}${limit == null ? '' : ' LIMIT ?'}
    ''', [...fa, ...ex, if (limit != null) limit]);
    return [for (final r in rows) r['id'] as String];
  }

  Future<List<String>> randomSelectableIds(
      Map<String, dynamic>? filter, int limit,
      {List<String> exclude = const []}) async {
    if (limit <= 0) return const [];
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final ex = exclude.where((e) => e.isNotEmpty).toList();
    final rows = await d.rawQuery('''
      SELECT w.id FROM words w
      LEFT JOIN srs s ON s.card_id = w.id
      WHERE w.enabled = 1 AND s.card_id IS NULL AND $fw
        AND w.id NOT IN (SELECT card_id FROM plan)
        ${ex.isEmpty ? '' : 'AND w.id NOT IN (${List.filled(ex.length, '?').join(',')})'}
      ORDER BY RANDOM() LIMIT ?
    ''', [...fa, ...ex, limit]);
    return [for (final r in rows) r['id'] as String];
  }

  Future<Map<String, int>> groupCounts(Map<String, dynamic>? filter,
      {String mode = 'tier', String scope = 'all'}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);

    final keyExpr = mode == 'letter'
        ? "CASE WHEN word GLOB '[A-Za-z]*' THEN UPPER(SUBSTR(word, 1, 1)) "
            "ELSE '#' END"
        : "COALESCE(tier, '')";
    final scoped = scope != 'all';
    final join = scoped
        ? ' LEFT JOIN plan pl ON pl.card_id = w.id'
            ' LEFT JOIN srs s ON s.card_id = w.id'
        : '';

    final cond = scope == 'unselected'
        ? ' AND NOT (${AppDb.inMemorySql})'
        : scope == 'enrolled'
            ? ' AND (${AppDb.inMemorySql})'
            : '';
    final rows = await d.rawQuery(
        'SELECT $keyExpr AS gk, COUNT(*) AS c FROM words w$join '
        'WHERE ${AppDb.listVisibleSql} AND $fw$cond GROUP BY gk',
        fa);
    return {
      for (final r in rows) (r['gk'] as String): (r['c'] as int?) ?? 0,
    };
  }

  Future<int> unenrollByFilter(Map<String, dynamic>? filter) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final n = await d.rawUpdate('''
      UPDATE words SET enabled = 0 WHERE id IN (
        SELECT w.id FROM words w
        LEFT JOIN plan pl ON pl.card_id = w.id
        LEFT JOIN srs s ON s.card_id = w.id
        WHERE ($fw) AND ${AppDb.enrolledSql})
    ''', fa);
    await d.rawUpdate(
        'DELETE FROM plan WHERE card_id IN '
        '(SELECT w.id FROM words w WHERE ($fw))',
        fa);
    return n;
  }

  Future<int> unplanByFilter(Map<String, dynamic>? filter) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    return d.rawUpdate(
        'DELETE FROM plan WHERE card_id IN (SELECT w.id FROM words w WHERE $fw)',
        fa);
  }

  Future<Set<String>> startedIds(Map<String, dynamic>? filter,
      {int limit = 20000}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final rows = await d.rawQuery('''
      SELECT w.id FROM words w
      JOIN srs s ON s.card_id = w.id
      WHERE w.enabled = 1 AND $fw LIMIT ?
    ''', [...fa, limit]);
    return {for (final r in rows) r['id'] as String};
  }

  Future<List<WordCard>> dueCards(
          {DateTime? now, Map<String, dynamic>? filter, int? limit}) async =>
      (await _dueRows('w.*', now: now, filter: filter, limit: limit))
          .map(WordCard.fromDb)
          .toList();

  Future<List<String>> dueCardIds(
          {DateTime? now, Map<String, dynamic>? filter, int? limit}) async =>
      [
        for (final r
            in await _dueRows('w.id', now: now, filter: filter, limit: limit))
          r['id'] as String
      ];

  Future<List<Map<String, Object?>>> _dueRows(String cols,
      {DateTime? now, Map<String, dynamic>? filter, int? limit}) async {
    final d = await db;
    final t0 = AppDb.dayEndMs(now);
    final (fw, fa) = AppDb.buildFilter(filter);
    return d.rawQuery('''
      SELECT $cols FROM words w
      JOIN srs s ON s.card_id = w.id
      WHERE w.enabled = 1 AND s.due < ? AND $fw
      ORDER BY (s.due >= ?), s.due ASC${limit == null ? '' : ' LIMIT ?'}
    ''', [
      t0,
      ...fa,
      DateTime.now().millisecondsSinceEpoch,
      if (limit != null) limit
    ]);
  }

  Future<List<WordCard>> newWords(
          {int limit = 20, Map<String, dynamic>? filter}) async =>
      interleaveFreshRows(
              await _newWordRows('w.*', limit: limit, filter: filter))
          .map(WordCard.fromDb)
          .toList();

  Future<List<String>> newWordIds(
          {int limit = 20, Map<String, dynamic>? filter}) async =>
      [
        for (final r in interleaveFreshRows(await _newWordRows(
            'w.id, w.base_word, w.word',
            limit: limit,
            filter: filter)))
          r['id'] as String
      ];

  static List<Map<String, Object?>> interleaveFreshRows(
    List<Map<String, Object?>> rows, {
    int window = 6,
    int minGap = 3,
  }) {
    if (rows.length <= 2) return rows;
    String keyOf(Map<String, Object?> r) {
      final base = (r['base_word'] as String?)?.trim().toLowerCase() ?? '';
      if (base.isNotEmpty) return 'b:$base';
      final raw = ((r['word'] as String?) ?? (r['id'] as String?) ?? '')
          .trim()
          .toLowerCase();
      final m = RegExp(r'[a-z]{4,}').firstMatch(raw);
      if (m != null) return 'p:${m.group(0)!.substring(0, 4)}';
      return 'id:${r['id']}';
    }

    final pool = List<Map<String, Object?>>.from(rows);
    final out = <Map<String, Object?>>[];
    final recent = <String>[];
    while (pool.isNotEmpty) {
      final scan = pool.length < window ? pool.length : window;
      var pick = 0;
      for (var i = 0; i < scan; i++) {
        if (!recent.contains(keyOf(pool[i]))) {
          pick = i;
          break;
        }
      }
      final chosen = pool.removeAt(pick);
      out.add(chosen);
      recent.add(keyOf(chosen));
      if (recent.length > minGap) recent.removeAt(0);
    }
    return out;
  }

  Future<List<Map<String, Object?>>> _newWordRows(String cols,
      {required int limit, Map<String, dynamic>? filter}) async {

    if (limit <= 0) return const [];
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    return d.rawQuery('''
      SELECT $cols FROM words w
      LEFT JOIN srs s ON s.card_id = w.id
      JOIN plan pl ON pl.card_id = w.id
      WHERE w.enabled = 1 AND s.card_id IS NULL
      ORDER BY CASE WHEN ($fw) THEN 0 ELSE 1 END, (w.rank IS NULL), w.rank ASC
      LIMIT ?
    ''', [...fa, limit]);
  }

  Future<int> newWordPool() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT COUNT(*) c FROM words w
      LEFT JOIN srs s ON s.card_id = w.id
      JOIN plan pl ON pl.card_id = w.id
      WHERE w.enabled = 1 AND s.card_id IS NULL
    ''');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<
      ({
        List<String> due,
        List<String> fresh,
        int done,
        int learnedNew,
        int pool,
        int remaining
      })> buildSessionQueueIds({
    required int dailyQuota,
    Map<String, dynamic>? filter,
    DateTime? now,
  }) async {

    final done = await todayAnsweredWords();
    final remaining = dailyQuota - done;

    final due = remaining <= 0
        ? const <String>[]
        : await dueCardIds(now: now, limit: remaining);
    final freshCap = remaining - due.length;
    final fresh = await newWordIds(limit: freshCap, filter: filter);

    final pool = await newWordPool();
    return (
      due: due,
      fresh: fresh,
      done: done,
      learnedNew: await todayNewCount(),
      pool: pool,
      remaining: remaining,
    );
  }

  Future<
      ({
        List<WordCard> due,
        List<WordCard> fresh,
        int done,
        int learnedNew,
        int pool,
        int remaining
      })> buildSessionQueue({
    required int dailyQuota,
    Map<String, dynamic>? filter,
    DateTime? now,
  }) async {
    final s = await buildSessionQueueIds(
        dailyQuota: dailyQuota, filter: filter, now: now);
    return (
      due: await wordsByIdsChunked(s.due),
      fresh: await wordsByIdsChunked(s.fresh),
      done: s.done,
      learnedNew: s.learnedNew,
      pool: s.pool,
      remaining: s.remaining,
    );
  }

  Future<List<WordCard>> wordsByIdsChunked(List<String> ids,
      {int chunk = 400}) async {
    final out = <WordCard>[];
    for (var i = 0; i < ids.length; i += chunk) {
      out.addAll(await wordsByIds(
          ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk)));
    }
    return out;
  }

  Future<TodayPlan> todayPlan({required int dailyQuota, DateTime? now}) async {
    final d = await db;
    final start = AppDb.dayStartMs(now);
    final t0 = AppDb.dayEndMs(now);
    final rows = await d.rawQuery('''
      SELECT bucket, COUNT(*) AS c FROM (
        SELECT CASE
          WHEN fs >= ? AND due >= ? THEN 'nd'
          WHEN fs >= ?               THEN 'np'
          WHEN lr >= ? AND due >= ? THEN 'rd'
          WHEN lr >= ?               THEN 'rp'
          WHEN due <  ?              THEN 'rb'
          ELSE 'idle'
        END AS bucket
        FROM (
          SELECT IFNULL(s.first_seen, 0) AS fs,
                 IFNULL(s.last_review, 0) AS lr,
                 IFNULL(s.due, 0) AS due
          FROM words w JOIN srs s ON s.card_id = w.id
          WHERE w.enabled = 1
        )
      ) GROUP BY bucket
    ''', [start, t0, start, start, t0, start, t0]);
    final b = <String, int>{
      for (final r in rows) r['bucket'] as String: (r['c'] as int?) ?? 0
    };
    final plan = todayPlanOf(
      quota: dailyQuota,
      newDone: b['nd'] ?? 0,
      newPending: b['np'] ?? 0,
      reviewDone: b['rd'] ?? 0,
      reviewPending: b['rp'] ?? 0,
      reviewBacklog: b['rb'] ?? 0,
      poolLeft: await newWordPool(),
    );
    await _autoCheckin(plan, now: now);
    return plan;
  }

  Future<({int review, int newCount})> todayFirstComposition(int n,
      {DateTime? now}) async {
    if (n <= 0) return (review: 0, newCount: 0);
    final d = await db;
    final start = AppDb.dayStartMs(now);
    final end = AppDb.dayEndMs(now);
    final rows = await d.rawQuery('''
      SELECT (IFNULL(s.first_seen, 0) >= ?) AS is_new, COUNT(*) AS c
      FROM (
        SELECT l.card_id AS cid, MIN(l.ts) AS t
        FROM study_log l
        WHERE l.ts >= ? AND l.ts < ?
        GROUP BY l.card_id
        ORDER BY t ASC
        LIMIT ?
      ) f
      LEFT JOIN srs s ON s.card_id = f.cid
      GROUP BY is_new
    ''', [start, start, end, n]);
    var review = 0;
    var fresh = 0;
    for (final r in rows) {
      final c = (r['c'] as int?) ?? 0;
      if (((r['is_new'] as int?) ?? 0) == 1) {
        fresh += c;
      } else {
        review += c;
      }
    }
    return (review: review, newCount: fresh);
  }

  Future<void> _autoCheckin(TodayPlan plan, {DateTime? now}) async {
    if (plan.taskTotal <= 0 || plan.taskLeft > 0) return;
    final key = AppDb.checkinKey(now ?? DateTime.now());
    if (await metaGet(key) != null) return;
    await metaSet(key, '${DateTime.now().millisecondsSinceEpoch}');
  }

  Future<void> ensureCheckinBackfill() async {
    if (await metaGet('checkin_backfill_v1') != null) return;
    await metaSet('checkin_backfill_v1', '1');
    final quota = int.tryParse(await metaGet('new_quota') ?? '') ?? 20;
    if (quota <= 0) return;
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT strftime('%Y-%m-%d', ts / 1000, 'unixepoch', 'localtime') AS day,
             COUNT(DISTINCT card_id) AS words
      FROM study_log GROUP BY day HAVING words >= ?
    ''', [quota]);
    for (final r in rows) {
      final key = 'checkin:${r['day']}';
      if (await metaGet(key) != null) continue;
      await metaSet(key, '0');
    }
  }

  Future<bool> isSignedDay(DateTime day) async =>
      await metaGet(AppDb.checkinKey(day)) != null;

  Future<Map<String, MonthDay>> monthView(int year, int month) async {
    await ensureCheckinBackfill();
    final d = await db;
    final from = DateTime(year, month, 1).millisecondsSinceEpoch;
    final to = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
    final rows = await d.rawQuery('''
      SELECT strftime('%Y-%m-%d', ts / 1000, 'unixepoch', 'localtime') AS day,
             COUNT(DISTINCT card_id) AS words,
             COUNT(*) AS answers
      FROM study_log WHERE ts >= ? AND ts < ? GROUP BY day
    ''', [from, to]);
    final out = <String, MonthDay>{
      for (final r in rows)
        (r['day'] as String): MonthDay(
          words: (r['words'] as int?) ?? 0,
          answers: (r['answers'] as int?) ?? 0,
        )
    };
    final signs =
        await d.rawQuery('SELECT k FROM meta WHERE k >= ? AND k < ?', [
      'checkin:$year-${month.toString().padLeft(2, '0')}-',

      'checkin:${DateTime(year, month + 1, 1).year}-'
          '${DateTime(year, month + 1, 1).month.toString().padLeft(2, '0')}-'
    ]);
    for (final r in signs) {
      final key = (r['k'] as String).substring('checkin:'.length);
      out[key] =
          (out[key] ?? const MonthDay(words: 0, answers: 0)).markSigned();
    }
    return out;
  }
}
