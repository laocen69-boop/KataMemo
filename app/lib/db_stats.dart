part of 'db.dart';

extension AppDbStats on AppDb {

  Future<({int all, int total, int started, int due, MemoryBands bands})>
      bookProgress(Map<String, dynamic>? filter, {DateTime? now}) async {
    final d = await db;
    final t0 = AppDb.dayEndMs(now);
    final (fw, fa) = AppDb.buildFilter(filter);
    final r = await d.rawQuery('''
      SELECT COUNT(*) AS total,
             COUNT(s.card_id) AS started,
             SUM(CASE WHEN s.due IS NOT NULL AND s.due < ? THEN 1 ELSE 0 END) AS due,
             ${AppDb._bandCols()}
      FROM words w
      LEFT JOIN srs s ON s.card_id = w.id
      LEFT JOIN plan pl ON pl.card_id = w.id
      WHERE ${AppDb.inMemorySql} AND $fw
    ''', [t0, ...fa]);
    final allRows = await d.rawQuery(
        'SELECT COUNT(*) c FROM words w WHERE ${AppDb.listVisibleSql} AND $fw', fa);
    final row = r.first;
    return (
      all: Sqflite.firstIntValue(allRows) ?? 0,
      total: (row['total'] as int?) ?? 0,
      started: (row['started'] as int?) ?? 0,
      due: (row['due'] as int?) ?? 0,
      bands: AppDb._bandsOf(row),
    );
  }

  Future<
          Map<String,
              ({int all, int total, int started, int due, MemoryBands bands})>>
      bookProgressBatch(List<({String id, Map<String, dynamic>? filter})> books,
          {DateTime? now}) async {
    final items = [
      for (final b in books)
        if (b.filter != null) b
    ];
    if (items.isEmpty) return const {};
    final d = await db;

    final t0 = AppDb.dayEndMs(now);
    final parts = <String>[];
    final args = <Object?>[];
    for (final b in items) {
      final (fw, fa) = AppDb.buildFilter(b.filter);
      parts.add('''
        SELECT ? AS bid,
               COUNT(CASE WHEN ${AppDb.listVisibleSql} THEN 1 END) AS all_,
               SUM(CASE WHEN ${AppDb.inMemorySql} THEN 1 ELSE 0 END) AS total,
               SUM(CASE WHEN ${AppDb.inMemorySql} AND s.card_id IS NOT NULL
                        THEN 1 ELSE 0 END) AS started,
               SUM(CASE WHEN ${AppDb.inMemorySql} AND s.due IS NOT NULL AND s.due < ?
                        THEN 1 ELSE 0 END) AS due,
               ${AppDb._bandCols(AppDb.inMemorySql)}
        FROM words w
        LEFT JOIN srs s ON s.card_id = w.id
        LEFT JOIN plan pl ON pl.card_id = w.id
        WHERE ($fw)
      ''');
      args.add(b.id);
      args.add(t0);
      args.addAll(fa);
    }
    final rows = await d.rawQuery(parts.join(' UNION ALL '), args);
    return {
      for (final r in rows)
        r['bid'] as String: (
          all: (r['all_'] as int?) ?? 0,
          total: (r['total'] as int?) ?? 0,
          started: (r['started'] as int?) ?? 0,
          due: (r['due'] as int?) ?? 0,
          bands: AppDb._bandsOf(r),
        ),
    };
  }

  Future<List<WordCard>> wordsByBand(int band,
      {int limit = 200, int offset = 0, Map<String, dynamic>? filter}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final order = band >= 3 ? 'w.rank ASC' : 's.stability ASC';

    final rows = await d.rawQuery(
      'SELECT w.* FROM words w '
      'LEFT JOIN srs s ON s.card_id = w.id '
      'LEFT JOIN plan pl ON pl.card_id = w.id '
      'WHERE ${AppDb.inMemorySql} AND (${AppDb._bandWhere(band)}) AND $fw '
      'ORDER BY $order LIMIT ? OFFSET ?',
      [...fa, limit, offset],
    );
    return rows.map(WordCard.fromDb).toList();
  }

  Future<int> logRating(String cardId, int rating) async {
    final d = await db;
    return d.insert('study_log', {
      'card_id': cardId,
      'rating': rating,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteLog(int id) async {
    final d = await db;
    await d.delete('study_log', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSrs(String cardId) async {
    final d = await db;
    await d.delete('srs', where: 'card_id = ?', whereArgs: [cardId]);
  }

  Future<
      ({
        List<({DateTime day, int dayNo, int rating})> days,
        int logs,
        List<int> todayExtra,
      })> cardHistory(String cardId) async {
    final d = await db;

    final rows = await d.rawQuery(
        'SELECT id, ts, rating FROM study_log WHERE card_id = ? ORDER BY id',
        [cardId]);
    if (rows.isEmpty) {
      return (
        days: const <({DateTime day, int dayNo, int rating})>[],
        logs: 0,
        todayExtra: const <int>[],
      );
    }
    final todayKey = _localDayKey(DateTime.now());

    final firstOfDay = <String, ({DateTime day, int rating})>{};
    final extra = <int>[];
    for (final r in rows) {
      final t = DateTime.fromMillisecondsSinceEpoch(r['ts'] as int);
      final key = _localDayKey(t);
      if (!firstOfDay.containsKey(key)) {
        firstOfDay[key] = (
          day: DateTime(t.year, t.month, t.day),
          rating: (r['rating'] as int?) ?? 0
        );
      } else if (key == todayKey) {

        extra.add((r['rating'] as int?) ?? 0);
      }
    }
    final keys = firstOfDay.keys.toList()..sort();
    final firstDay = firstOfDay[keys.first]!.day;
    final days = <({DateTime day, int dayNo, int rating})>[
      for (final k in keys)
        (
          day: firstOfDay[k]!.day,
          dayNo: firstOfDay[k]!.day.difference(firstDay).inDays + 1,
          rating: firstOfDay[k]!.rating
        )
    ];
    return (days: days, logs: rows.length, todayExtra: extra);
  }

  static String _localDayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  Future<Map<String, int>> todayStats() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
        'SELECT rating, COUNT(*) c FROM study_log WHERE ts >= ? GROUP BY rating',
        [start]);
    final map = <String, int>{
      'new': 0,
      'review': 0,
      'easy': 0,
      'forget': 0,
      'fuzzy': 0,
      'know': 0
    };
    for (final row in r) {
      final rating = row['rating'] as int? ?? 0;
      final c = row['c'] as int? ?? 0;
      switch (rating) {

        case 3:
          map['easy'] = (map['easy'] ?? 0) + c;
        case 0:
          map['forget'] = (map['forget'] ?? 0) + c;
        case 1:
          map['fuzzy'] = (map['fuzzy'] ?? 0) + c;
        case 2:
          map['know'] = (map['know'] ?? 0) + c;
      }
    }

    map['new'] = await todayNewCount();

    final all = await todayAnsweredWords();
    map['review'] = (all - (map['new'] ?? 0)).clamp(0, all);
    return map;
  }

  Future<int> streakDays() async {
    final d = await db;
    final rows =
        await d.rawQuery("SELECT k FROM meta WHERE k LIKE 'checkin:%'");
    final days = <String>{
      for (final r in rows) (r['k'] as String).substring('checkin:'.length)
    };
    final today = AppDb.dayStartOf();
    var streak = 0;
    for (var i = 0; i < 365; i++) {
      final key = AppDb._dayKey(today.subtract(Duration(days: i)));
      if (days.contains(key)) {
        streak++;
      } else if (i == 0) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  Future<int> bestStreakDays() async {
    final d = await db;
    final rows =
        await d.rawQuery("SELECT k FROM meta WHERE k LIKE 'checkin:%'");
    final days = [
      for (final r in rows)
        DateTime.parse((r['k'] as String).substring('checkin:'.length))
    ]..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final day in days) {
      final d0 = DateTime(day.year, day.month, day.day);
      run = (prev != null && d0.difference(prev).inDays == 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d0;
    }
    return best;
  }

  Future<List<Map<String, Object?>>> recentLogs(int days) async {
    final d = await db;
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final s0 = AppDb.dayStartMs(start);
    return d.rawQuery('''
      SELECT l.card_id AS card_id, l.rating AS rating, l.ts AS ts, s.first_seen AS first_seen
      FROM study_log l
      LEFT JOIN srs s ON s.card_id = l.card_id
      WHERE l.ts >= ? ORDER BY l.ts ASC
    ''', [s0]);
  }

  Future<int> todayLogCount() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d
        .rawQuery('SELECT COUNT(*) c FROM study_log WHERE ts >= ?', [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> todayAnsweredWords() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
        'SELECT COUNT(DISTINCT card_id) c FROM study_log WHERE ts >= ?',
        [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> totalStudySeconds({int gapCapMs = 60000}) async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT SUM(gap) AS s FROM (
        SELECT (l2.ts - l1.ts) AS gap
        FROM study_log l1
        JOIN study_log l2 ON l2.id = (SELECT MIN(id) FROM study_log WHERE id > l1.id)
      )
      WHERE gap > 0 AND gap <= ?
    ''', [gapCapMs]);
    final ms = Sqflite.firstIntValue(r) ?? 0;
    return (ms / 1000).round();
  }

  Future<Map<String, int>> dailyStudySeconds(
      {int days = 90, int gapCapMs = 60000}) async {
    final d = await db;
    final from = AppDb.dayStartMs(DateTime.now().subtract(Duration(days: days)));
    final rows = await d.rawQuery('''
      SELECT strftime('%Y-%m-%d', l1.ts / 1000, 'unixepoch', 'localtime') AS d,
             SUM(l2.ts - l1.ts) AS ms
      FROM study_log l1
      JOIN study_log l2 ON l2.id = (SELECT MIN(id) FROM study_log WHERE id > l1.id)
      WHERE l1.ts >= ? AND (l2.ts - l1.ts) > 0 AND (l2.ts - l1.ts) <= ?
      GROUP BY d
    ''', [from, gapCapMs]);
    return {
      for (final r in rows)
        (r['d'] as String): (((r['ms'] as int?) ?? 0) / 1000).round(),
    };
  }

  Future<List<({String topic, int total, int started, MemoryBands bands})>>
      topicProgress(
          {int top = 8, Map<String, dynamic>? filter, DateTime? now}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);

    final names = await d.rawQuery('''
      WITH RECURSIVE parts(rest) AS (
        SELECT COALESCE(topics,'') || ',' FROM words w
        WHERE ${AppDb.listVisibleSql} AND COALESCE(topics,'') != '' AND $fw
        UNION ALL
        SELECT SUBSTR(rest, INSTR(rest, ',') + 1) FROM parts
        WHERE INSTR(rest, ',') > 0
      )
      SELECT DISTINCT TRIM(SUBSTR(rest, 1, INSTR(rest, ',') - 1)) AS t
      FROM parts
      WHERE INSTR(rest, ',') > 0
    ''', fa);
    final topics = [
      for (final r in names)
        if ((r['t'] as String?)?.isNotEmpty ?? false) r['t'] as String
    ]..sort();
    if (topics.isEmpty) return const [];

    final rankParts = <String>[];
    final rankArgs = <Object?>[];
    for (final t in topics) {

      rankParts.add('SELECT ? AS t, COUNT(*) AS c FROM words w '
          'LEFT JOIN srs s ON s.card_id = w.id '
          'LEFT JOIN plan pl ON pl.card_id = w.id '
          "WHERE ${AppDb.inMemorySql} AND (',' || COALESCE(topics,'') || ',') LIKE ?");
      rankArgs
        ..add(t)
        ..add('%,$t,%');
    }
    final ranked = await d.rawQuery(
        '${rankParts.join(' UNION ALL ')} ORDER BY c DESC, t ASC LIMIT ?',
        [...rankArgs, top]);
    if (ranked.isEmpty) return const [];

    final out = <({String topic, int total, int started, MemoryBands bands})>[];
    for (final r in ranked) {
      final topic = r['t'] as String;
      final tr = await d.rawQuery('''
        SELECT COUNT(*) AS total,
               COUNT(s.card_id) AS started,
               ${AppDb._bandCols()}
        FROM words w
        LEFT JOIN srs s ON s.card_id = w.id
        LEFT JOIN plan pl ON pl.card_id = w.id
        WHERE ${AppDb.inMemorySql} AND (',' || COALESCE(topics,'') || ',') LIKE ?
      ''', ['%,$topic,%']);
      final row = tr.first;
      out.add((
        topic: topic,
        total: (row['total'] as int?) ?? 0,
        started: (row['started'] as int?) ?? 0,
        bands: AppDb._bandsOf(row),
      ));
    }
    return out;
  }

  Future<Map<String, ({int easy, int know, int fuzzy, int forget})>>
      dailyWordRatingCounts({int days = 950}) async {
    final d = await db;
    final start = DateTime.now().subtract(Duration(days: days));
    final s0 = AppDb.dayStartMs(start);
    final rows = await d.rawQuery('''
      SELECT strftime('%Y-%m-%d', l.ts / 1000, 'unixepoch', 'localtime') AS d,
             l.rating AS r, COUNT(*) AS c
      FROM (
        SELECT card_id, MIN(id) AS first_id
        FROM study_log WHERE ts >= ?
        GROUP BY card_id,
                 strftime('%Y-%m-%d', ts / 1000, 'unixepoch', 'localtime')
      ) t
      JOIN study_log l ON l.id = t.first_id
      GROUP BY d, r
    ''', [s0]);
    final out = <String, ({int easy, int know, int fuzzy, int forget})>{};
    for (final row in rows) {
      final k = row['d'] as String?;
      if (k == null) continue;
      final prev = out[k] ?? (easy: 0, know: 0, fuzzy: 0, forget: 0);
      final c = (row['c'] as int?) ?? 0;
      out[k] = switch (row['r'] as int? ?? -1) {
        3 => (
            easy: prev.easy + c,
            know: prev.know,
            fuzzy: prev.fuzzy,
            forget: prev.forget
          ),
        2 => (
            easy: prev.easy,
            know: prev.know + c,
            fuzzy: prev.fuzzy,
            forget: prev.forget
          ),
        1 => (
            easy: prev.easy,
            know: prev.know,
            fuzzy: prev.fuzzy + c,
            forget: prev.forget
          ),
        0 => (
            easy: prev.easy,
            know: prev.know,
            fuzzy: prev.fuzzy,
            forget: prev.forget + c
          ),
        _ => prev,
      };
    }
    return out;
  }

  Future<DayStats> dayStatsAt(DateTime day) async {
    final d = await db;
    final t0 = AppDb.dayStartMs(day);
    final t1 = AppDb.dayEndMs(day);

    final agg = await d.rawQuery(
        'SELECT COUNT(DISTINCT card_id) w, COUNT(*) a FROM study_log '
        'WHERE ts >= ? AND ts < ?',
        [t0, t1]);
    final words = (agg.isEmpty ? 0 : (agg.first['w'] as int? ?? 0));
    final answers = (agg.isEmpty ? 0 : (agg.first['a'] as int? ?? 0));

    final nw = await d.rawQuery('''
      SELECT COUNT(*) c FROM (
        SELECT card_id, MIN(ts) AS f FROM study_log GROUP BY card_id
      ) WHERE f >= ? AND f < ?
    ''', [t0, t1]);
    final newWords = (nw.isEmpty ? 0 : (nw.first['c'] as int? ?? 0));

    final rows = await d.rawQuery('''
      SELECT l.rating AS r, COUNT(*) AS c
      FROM (
        SELECT card_id, MIN(id) AS fid FROM study_log
        WHERE ts >= ? AND ts < ? GROUP BY card_id
      ) t JOIN study_log l ON l.id = t.fid
      GROUP BY l.rating
    ''', [t0, t1]);
    var easy = 0, know = 0, fuzzy = 0, forget = 0;
    for (final row in rows) {
      final c = (row['c'] as int?) ?? 0;
      switch (row['r'] as int? ?? -1) {
        case 3:
          easy += c;
        case 2:
          know += c;
        case 1:
          fuzzy += c;
        case 0:
          forget += c;
      }
    }
    return DayStats(
      words: words,
      answers: answers,
      newWords: newWords.clamp(0, words),
      easy: easy,
      know: know,
      fuzzy: fuzzy,
      forget: forget,
    );
  }

  Future<int> learnedWordCount() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM srs WHERE card_id IN (SELECT id FROM words)');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<ForgetBin>> forgetRateByInterval() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT l.card_id AS card_id, l.rating AS r,
             date(l.ts / 1000, 'unixepoch', 'localtime') AS d
      FROM (SELECT card_id AS cid, MIN(id) AS fid
            FROM study_log
            WHERE card_id IN (SELECT id FROM words)
            GROUP BY card_id, date(ts / 1000, 'unixepoch', 'localtime')) t
      JOIN study_log l ON l.id = t.fid
      ORDER BY l.card_id ASC, l.ts ASC
    ''');
    final n = _kIntervalLabels.length;
    final reviews = List<int>.filled(n, 0);
    final forgets = List<int>.filled(n, 0);
    final words = List<Set<String>>.generate(n, (_) => <String>{});
    String? card;
    DateTime? prev;
    for (final row in rows) {
      final cid = row['card_id'] as String? ?? '';
      final day = AppDb._asDay(row['d'] as String?);
      if (day == null) continue;
      if (cid != card) {
        card = cid;
        prev = day;
        continue;
      }
      final gap = day.difference(prev!).inDays;
      prev = day;
      final i = AppDb._intervalBin(gap);
      if (i < 0) continue;
      reviews[i]++;
      if ((row['r'] as int? ?? -1) == 0) forgets[i]++;
      words[i].add(cid);
    }
    return [
      for (var i = 0; i < n; i++)
        (
          label: _kIntervalLabels[i],
          reviews: reviews[i],
          forgets: forgets[i],
          words: words[i].length,
        ),
    ];
  }

  Future<double?> overallRecallRate() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c, SUM(CASE WHEN rating >= 1 THEN 1 ELSE 0 END) ok FROM study_log');
    if (r.isEmpty) return null;
    final total = r.first['c'] as int? ?? 0;
    if (total == 0) return null;
    final ok = r.first['ok'] as int? ?? 0;
    return ok / total;
  }

  Future<double?> medianStability() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT stability FROM srs
      WHERE reps > 0 AND stability > 0 AND card_id IN (SELECT id FROM words)
      ORDER BY stability ASC
    ''');
    if (r.isEmpty) return null;
    final vals = [
      for (final x in r) (x['stability'] as num?)?.toDouble() ?? 0.0
    ];
    if (vals.isEmpty) return null;
    final mid = vals.length ~/ 2;
    return vals.length.isOdd ? vals[mid] : (vals[mid - 1] + vals[mid]) / 2;
  }
}
