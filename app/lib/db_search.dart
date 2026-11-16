part of 'db.dart';

extension AppDbSearch on AppDb {

  Future<int> wordCount() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) c FROM words');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> countByFilter(Map<String, dynamic>? filter) async {
    final d = await db;
    final (where, args) = AppDb.buildFilter(filter);
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM words WHERE $where AND ${AppDb.listVisibleSql}', args);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<WordCard>> wordsByFilter(Map<String, dynamic>? filter,
      {int limit = 2000, int offset = 0, String sort = 'rank'}) async {
    final d = await db;
    final (where, args) = AppDb.buildFilter(filter);

    final rows = await d.rawQuery(
      "SELECT * FROM words WHERE $where AND "

      '${AppDb.listVisibleSql} '
      'ORDER BY ${AppDb.orderByClause(sort)} LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return rows.map(WordCard.fromDb).toList();
  }

  Future<List<WordCard>> wordsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final d = await db;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await d.rawQuery('SELECT * FROM words WHERE id IN ($ph)', ids);
    final byId = <String, WordCard>{
      for (final r in rows) r['id'] as String: WordCard.fromDb(r),
    };
    return [
      for (final i in ids)
        if (byId[i] != null) byId[i]!,
    ];
  }

  Future<List<WordCard>> searchAll(String query,
      {Map<String, dynamic>? filter, int limit = 200}) async {
    final d = await db;
    final keys =
        query.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (keys.isEmpty) return const [];

    final (fw, fa) = AppDb.buildFilter(filter);
    final parts = <String>[];
    final args = <Object?>[...fa];
    for (final k in keys) {
      final raw = AppDb._escLike(k);

      if (RegExp(r'[0-9a-zA-Z]').hasMatch(k) && AppDb.fold(k).isNotEmpty) {
        parts.add(r"(id LIKE ? ESCAPE '\' OR word LIKE ? ESCAPE '\' "
            r"OR zh LIKE ? ESCAPE '\' OR COALESCE(examples,'') LIKE ? ESCAPE '\')");
        args.addAll(['%${AppDb._escLike(AppDb.fold(k))}%', '%$raw%', '%$raw%', '%$raw%']);
      } else {
        parts.add(r"(zh LIKE ? ESCAPE '\' "
            r"OR COALESCE(examples,'') LIKE ? ESCAPE '\')");
        args.addAll(['%$raw%', '%$raw%']);
      }
    }
    final where = parts.join(' AND ');

    final k0 = keys.first;
    final hasAscii0 =
        RegExp(r'[0-9a-zA-Z]').hasMatch(k0) && AppDb.fold(k0).isNotEmpty;
    final f0 = hasAscii0 ? AppDb._escLike(AppDb.fold(k0)) : '\u0000';
    final r0 = hasAscii0 ? AppDb._escLike(k0) : '\u0000';

    final z0 = AppDb._escLike(k0);
    args.addAll([f0, '$f0%', '$r0%', z0, '$z0%', '%$z0%']);

    final rows = await d.rawQuery(
      'SELECT * FROM words '
      'WHERE enabled = 1 AND $fw AND $where '
      r"ORDER BY CASE WHEN id = ? THEN 0 "
      r"WHEN id LIKE ? ESCAPE '\' THEN 1 "
      r"WHEN word LIKE ? ESCAPE '\' THEN 2 "
      r"WHEN zh = ? THEN 3 "
      r"WHEN zh LIKE ? ESCAPE '\' THEN 4 "
      r"WHEN zh LIKE ? ESCAPE '\' THEN 5 "
      'ELSE 6 END, '
      '  (rank IS NULL), rank ASC, word ASC LIMIT ?',
      [...args, limit],
    );
    return rows.map(WordCard.fromDb).toList();
  }

  Future<WordCard?> searchWords(String q, {bool prefixFallback = false}) async {
    final d = await db;
    final raw = q.trim().toLowerCase();
    if (raw.isEmpty) return null;
    final key = AppDb.fold(raw);
    if (key.isEmpty) return null;
    final rows =
        await d.query('words', where: 'id = ?', whereArgs: [key], limit: 1);
    if (rows.isNotEmpty) return WordCard.fromDb(rows.first);
    if (!prefixFallback) return null;
    final rows2 = await d.query('words',
        where: 'id LIKE ?',
        whereArgs: ['$key%'],
        orderBy: '(rank IS NULL), rank ASC',
        limit: 1);
    return rows2.isEmpty ? null : WordCard.fromDb(rows2.first);
  }

  Future<
          ({
            WordCard? card,
            CliticParse? clitic,
            PassiveParse? passive,
            SpacingParse? spacing,
            DerivedParse? derived
          })>
      searchWordWithMorph(String q) async {
    final folded = AppDb.fold(q);

    final exact = await searchWords(q);
    if (exact != null) {
      final p = await _passiveOfCard(exact);
      if (p == null) {
        return (
          card: exact,
          clitic: null,
          passive: null,
          spacing: null,
          derived: null
        );
      }
      return (
        card: await searchWords(p.active),
        clitic: null,
        passive: p,
        spacing: null,
        derived: null
      );
    }

    for (final cand in cliticParses(folded)) {
      final c = await searchWords(cand.base);
      if (c == null) continue;

      final p = await _passiveOfCard(c);
      if (p == null) {
        return (
          card: c,
          clitic: cand,
          passive: null,
          spacing: null,
          derived: null
        );
      }
      return (
        card: await searchWords(p.active),
        clitic: cand,
        passive: p,
        spacing: null,
        derived: null
      );
    }

    final spacingParts = kSpacingVariants[folded];
    if (spacingParts != null) {
      final (prefix, rest) = spacingParts;
      final phrase = '$prefix $rest';
      final phraseCard = await searchWords(phrase);
      if (phraseCard != null) {
        return (
          card: phraseCard,
          clitic: null,
          passive: null,
          spacing: SpacingParse(
            clicked: folded,
            prefix: prefix,
            rest: rest,
            target: phraseCard.id,
            phraseCard: true,
          ),
          derived: null
        );
      }
      final restCard = await searchWords(rest);
      if (restCard != null) {
        return (
          card: restCard,
          clitic: null,
          passive: null,
          spacing: SpacingParse(
            clicked: folded,
            prefix: prefix,
            rest: rest,
            target: restCard.id,
            phraseCard: false,
          ),
          derived: null
        );
      }
    }

    for (final part in kParticleSuffixes) {
      if (!folded.endsWith(part) || folded.length - part.length < 3) continue;
      if (await searchWords(folded.substring(0, folded.length - part.length)) !=
          null) {
        return (
          card: null,
          clitic: null,
          passive: null,
          spacing: null,
          derived: null
        );
      }
    }
    for (final p in passiveParses(folded)) {
      final act = await searchWords(p.active);

      if (act == null || act.isNonStandardVariantCard) continue;
      return (
        card: act,
        clitic: null,
        passive: p,
        spacing: null,
        derived: null
      );
    }

    for (final p in derivedParses(folded)) {
      final root = await searchWords(p.root);
      if (root == null || root.isNonStandardVariantCard) continue;
      return (
        card: root,
        clitic: null,
        passive: null,
        spacing: null,
        derived: p
      );
    }
    return (
      card: null,
      clitic: null,
      passive: null,
      spacing: null,
      derived: null
    );
  }

  Future<bool> _stemLooksReal(String stem) async {
    if (stem.length < 4) return false;

    final s = await searchWords(stem);
    if (s != null && !s.isNonStandardVariantCard) return true;
    for (final suf in const ['kan', 'i']) {
      if (!stem.endsWith(suf)) continue;
      final root = stem.substring(0, stem.length - suf.length);
      if (root.length < kPassiveMinStemLen) continue;
      final r = await searchWords(root);
      if (r != null && !r.isNonStandardVariantCard) return true;
    }
    return false;
  }

  Future<PassiveParse?> _passiveOfCard(WordCard card) async {
    final id = card.id;
    if (!id.startsWith('di') || id.length < 2 + kPassiveMinStemLen) return null;
    final byAffix = card.affixes.any((a) => a.morph.startsWith('di-'));
    if (!byAffix && !await _stemLooksReal(id.substring(2))) return null;
    for (final p in passiveParses(id)) {
      if (p.particle.isNotEmpty) continue;
      final act = await searchWords(p.active);
      if (act != null && !act.isNonStandardVariantCard) {
        return PassiveParse(
          clicked: p.clicked,
          form: p.form,
          particle: p.particle,
          stem: p.stem,
          active: p.active,
          ownCard: id,
        );
      }
    }
    return null;
  }

  Future<List<String>> topicsOfWord(String query) async {
    final t = query.trim();
    if (t.isEmpty) return const [];
    final key = AppDb.fold(t);
    if (key.isEmpty) return const [];
    final d = await db;
    final rows = await d.query('words',
        columns: ['topics'],
        where: "enabled != 0 AND topics IS NOT NULL AND "
            "(id = ? OR word = ? OR word = ? OR zh = ?)",
        whereArgs: [key, t, t.toLowerCase(), t],
        limit: 1);
    final raw = rows.isEmpty ? null : rows.first['topics'] as String?;
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').where((s) => s.trim().isNotEmpty).toList();
  }
}
