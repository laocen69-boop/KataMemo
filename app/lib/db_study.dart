part of 'db.dart';

/// [AppDb] 的实例方法（2026-10-22 从 `db.dart` 原样搬出，只把对静态成员的裸引用补成 `AppDb.`）。
extension AppDbStudy on AppDb {
  // ---------- FSRS 状态 ----------

  /// 批量取记忆程度。
  ///
  /// 列表里逐词 `getSrs` 是 N+1 查询（一页 2000 个词就是 2000 次），
  /// 所以一次查回来。SQLite 的变量上限默认 999，所以分块。
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
    // first_seen 是「这个词第一次进入学习」的时间，「今天新学 N」靠它计数。
    // replace 语义会整行重写，所以必须先读出来带上，否则每次评分都会把它重置成
    // 「现在」——那样额度就永远算不出今天新学了多少。
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

  /// 今天新学（首次进入学习）的词数。**只作显示**（顶部「新词 N」、额度对话框
  /// 里的 breakdown）——额度的扣减依据是 [todayAnsweredWords]（今天作答过的去重词数，
  /// 新学与复习都算在内）。
  Future<int> todayNewCount() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM srs WHERE first_seen >= ? AND card_id IN (SELECT id FROM words)',
        [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// **今天新学**的词 id 集合（判据与 [todayNewCount] 完全一致：`first_seen` 是今天）。
  ///
  /// 用途：学习页第三档按钮的措辞分流（v2.5.20 起 **新学 → 「认识」／复习 → 「记得」**）。
  /// 原先学习页靠「这张卡来自 due 桶还是 fresh 桶」来判，
  /// 于是**今天刚学、点了困难/模糊而回队的卡**会被当成复习卡（`isNew: false` 硬编码），
  /// 用户看到自己几分钟前才第一次见到的词，第三个按钮却写着「记得」——
  /// 原话：「这个词我似乎完全没学过就进了复习」✗。
  ///
  /// 改成与「今日新学 N/M」**同一个口径**（`srs.first_seen` 是不是今天）：
  ///   · 今天第一次接触的词（含困难后回队的、含退出重进又遇到的）→ 认识 ✓
  ///   · 昨天以前学过的词 → 记得 ✓
  Future<Set<String>> todayNewIds() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final rows = await d.rawQuery(
        'SELECT card_id FROM srs WHERE first_seen >= ? AND card_id IN (SELECT id FROM words)',
        [start]);
    return {for (final r in rows) r['card_id'] as String};
  }

  // ---------- 记忆计划（手动「加入记忆」） ----------

  /// 把词加入记忆计划。
  ///
  /// 写 `plan` 行 = 用户明确要学它；顺带把 `enabled` 拉回 1，
  /// 因为它可能之前被「移出记忆」屏蔽过（重新加入就该能学）。
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
    await setEnabled(ids, true); // 加入记忆的同时把它从「移出」状态拉回来
  }

  /// 移出记忆：删 `plan` 行 **并且** 屏蔽 `enabled`。
  ///
  /// 旧代码的「取消勾选」只删 plan、词仍照常被派发（SnackBar 自己写着
  /// 「已取消置顶（仍在记忆里）」），与新的「已加入才有进度」口径冲突 ✗。
  /// 两件事一起做才真的退出队列；**srs / study_log 一个字都不动**——
  /// 移出不该销毁历史进度，重新点 ＋ 就接着原来的间隔学。
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

  /// 词库重导后重放「加入记忆」。
  ///
  /// words 表被整体重建时 `enabled` 按出厂 `en` 重置，而 plan 表是用户资产
  /// （独立于 words，重导不清）。v2.5.3 起派生词可以「加入记忆」，但未入册的
  /// 派生词出厂 en = 0——不重放的话，plan 里排最前却永远进不了队列
  /// （所有取词 SQL 都要 enabled = 1），「加入记忆」等于白点。
  /// 只重放 tier='derived' 的：可学词出厂就是 en=1，不需要；也因此如果用户
  /// 把某个派生词「移出记忆」（enabled=0）但 plan 行还在，重导后它会被复活——
  /// 这是已知的边缘 case，量级远小于「重导后手动加入全部失效」。
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

  /// 一批词里哪些**已在记忆计划**里（列表用它给行画「已加入」标记）。
  ///
  /// 逐条 `isPlanned` 会打 N 次查询；列表一屏几十行、搜索结果能有 300 条，
  /// 所以按 IN 一次查完（`plan` 表很小，代价可忽略）。
  Future<Set<String>> plannedIds(List<String> ids) async {
    if (ids.isEmpty) return <String>{};
    final d = await db;
    final out = <String>{};
    // SQLite 的变量上限约 999，分批查（搜索结果正好卡在这个量级）
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

  /// 按筛选条件**随机**挑 `limit` 个生词加入记忆（等价 `planWord`）。
  ///
  /// 用户 2026-09-17：「选词」——自己挑，不吃随机的苦；挑了之后
  /// 每天学多少仍由「每日额度」（今天碰过的张数）管。所以这里按**今日剩余额度**挑：
  ///   · 只挑 `enabled = 1`、**没有 srs 行**（还没学过的）的词；
  ///   · 跳过已经在 `plan` 里的（重复加没意义，还会挤掉名额）；
  ///   · `ORDER BY RANDOM()` —— 同一批里尽量分散，不是按 rank 从头切一刀。
  /// 返回实际加入的 id（调用方拿它做提示与界面刷新）。
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

  /// 有没有任何一张「在记忆里」的可学卡（判据同 [AppDb.inMemorySql]：
  /// `enabled = 1` 且 plan 或 srs 有行）。
  ///
  /// 学习页完成页用它区分「从来没加入过词」（新用户）与「今天学完了」——
  /// 两者在 [TodayPlan] 上都是全 0，只看计划会把新用户说成「任务全部完成」。
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

  /// 按筛选条件**整批**加入记忆（词库页「加入本库」用）。
  ///
  /// 列表只加载前 200 条，批量操作必须作用在**全量筛选结果**上，
  /// 不能只对已加载的那一页调 [planWord]。跳过已在记忆里的（有 plan 或有 srs）。
  /// [limit] 用来「按今天的额度只加这些」，null = 全加。返回实际加入数。
  ///
  /// [sort]（第 20 轮）：「顺选」要**按当前列表的显示顺序**从上往下加——
  /// 字母序时得按字母加，不能一律按词频（词频序对用户来说是乱跳的）。
  /// 取值必须过 [kSortModes] 白名单（外面传的也是白名单值，双保险）。
  ///
  /// ⚠️ 这里**不能**要求 `w.enabled = 1`：3.0 起「移出记忆」会把 enabled 置 0
  /// （[unenroll]），于是「移出本库」再「加入本库」会一个词都加不回来——
  /// 整库变成灰色死局，只能逐个点 ＋。3.0 开发时就是这个顺序把用户卡住的。
  /// 改用 [listVisibleSql] 当闸门：它仍把**查词层**（`derived`/`redup` 里
  /// `enabled = 0` 的那些）挡在外面，不会把查词条目塞进学习队列。
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
    await setEnabled(ids, true); // 与 [planWord] 同一条语义：加入即拉回可学
    return ids.length;
  }

  /// 「顺选」的**只读**候选查询（第三十四轮：顺选/随机改成了**只勾选、不写入**
  /// —— 用户原话「点了就加入记忆」改成「点了自动选上，点右边的加入记忆才真正加入」；
  /// 写入统一由底部绿钮的 [AppDb.planWord] 确认）。
  ///
  /// SELECT 判据与 [planByFilter] **逐字同源**（listVisibleSql 闸门 + 无 plan +
  /// 无 srs，按显示顺序取前 N）；[exclude] = 已经勾上的 id（第二次点顺选应该
  /// **接着往下挑**，不是把同一批再勾一遍）。
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

  /// 「随机」的只读候选（[planRandom] 的 SELECT 减去写入；[exclude] 同上）。
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

  /// 分组计数：卡组页分组头右边那个数（第 20 轮）。
  ///
  /// 列表是分页的（首屏 200 行），组内行数**不能拿已加载的行数凑**——
  /// 页头必须是整组的真实条数，否则滚动时数字会一直跳。所以一次
  /// `GROUP BY` 把整组（不是整页）数出来。
  ///
  /// [mode] `'tier'` = 按词频档分组、`'letter'` = 按首字母分组
  ///   —— 与列表的分组口径**必须同源**（首字母：ASCII 大写，非字母归 `#`，
  ///   两边同一句判据，见 `select_screen.dart` 的 [_groupKey]）。
  /// [scope] 卡片统计条的三格过滤：`'unselected'` 只数没加入记忆的 /
  ///   `'enrolled'` 只数已在记忆里的 / `'all'` 全数（默认）。
  ///
  /// ⚠️ 不认「只看没掌握的」（那是客户端按记忆强度筛的）——开着它时
  /// 分组头的数会比屏幕上多，页面在那种模式下改用已加载行数兜底（见调用处）。
  Future<Map<String, int>> groupCounts(Map<String, dynamic>? filter,
      {String mode = 'tier', String scope = 'all'}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    // 首字母口径：ASCII 字母取大写首字母，其余（`-kan`、数字、é 开头…）归 '#'
    final keyExpr = mode == 'letter'
        ? "CASE WHEN word GLOB '[A-Za-z]*' THEN UPPER(SUBSTR(word, 1, 1)) "
            "ELSE '#' END"
        : "COALESCE(tier, '')";
    final scoped = scope != 'all';
    final join = scoped
        ? ' LEFT JOIN plan pl ON pl.card_id = w.id'
            ' LEFT JOIN srs s ON s.card_id = w.id'
        : '';
    // ⚠️ 必须用 [inMemorySql] 并**自己加括号**：它展开是
    // `w.enabled = 1 AND (plan∪srs)`，外面接 `NOT` 时 SQLite 的
    // `NOT` 优先级低于 `=`、高于 `AND` ——不加括号会把
    // `NOT w.enabled = 1 AND (…)` 解析成「没启用 **且** 在记忆里」，全错。
    // 判据与页面上 `_enrolledOf`（= inMemorySql 的界面版）逐字对齐：
    // 「移出记忆」会把 enabled 置 0，那些词必须算进「未选」。
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

  /// 按筛选条件整批**移出记忆**（词库页「移出本库」用）。
  ///
  /// = [unenroll] 的全量版：删 plan + 屏蔽 enabled，两步都要，
  /// 只删 plan 的话已学过的词照样被 [dueCards] 派发。
  /// srs / study_log 不动（进度留着，重新加入接着学）。
  ///
  /// ⚠️ 只动**已在记忆里**的行（`enrolledSql`）：一次「清空本词库」不该把
  /// 从没加入过的词也 `enabled = 0`，那样它就变成了「用户移出过」。
  /// 返回**真正移出**的条数（不是筛选结果的条数）。
  ///
  /// ⚠️ 两步的**顺序**有讲究：必须先 UPDATE 再删 plan。`enrolledSql` 认的是
  /// 「有 plan 行或有 srs 行」，plan 先删掉就又认又不出谁在记忆里了——
  /// 结果是**已学过的词（有 srs）留在记忆里继续被派发**，「移出本库」
  /// 只对没学过的词生效，返回值也变成 0（`quota_test` 的批量用例抓到过）。
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

  /// 按筛选条件清掉置顶标记（词库页「清空本词库」时用）。
  /// 不能只对已加载的那一页调 unplanWords——列表只加载前 2000 条。
  Future<int> unplanByFilter(Map<String, dynamic>? filter) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    return d.rawUpdate(
        'DELETE FROM plan WHERE card_id IN (SELECT w.id FROM words w WHERE $fw)',
        fa);
  }

  /// 某范围内已进入学习的词 id 集合（列表页打「已学」小绿点用）
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

  // ---------- 队列与今日计划（TodayPlan 的算术在 todayPlanOf） ----------

  Future<List<WordCard>> dueCards(
          {DateTime? now, Map<String, dynamic>? filter, int? limit}) async =>
      (await _dueRows('w.*', now: now, filter: filter, limit: limit))
          .map(WordCard.fromDb)
          .toList();

  /// 同 [dueCards]，但**只取 id**（队列 id 化，实施单 B）：到期多时不必把整张
  /// `words` 行全读出来。⚠️ 与 [dueCards] 共用 [_dueRows]——筛选/排序/LIMIT 只有
  /// 这一份 SQL，不要再抄第二遍（「同一个口径抄多份」是这个项目的老毛病）。
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
    final current = now ?? DateTime.now();
    final nowMs = current.millisecondsSinceEpoch;
    final t0 = AppDb.dayEndMs(current); // 注意是**明天 00:00**，不是「此刻」——见上面那段
    final (fw, fa) = AppDb.buildFilter(filter);
    return d.rawQuery('''
      SELECT $cols FROM words w
      JOIN srs s ON s.card_id = w.id
      WHERE w.enabled = 1 AND s.due < ? AND $fw
      ORDER BY (s.due >= ?),
               (s.state != 2) DESC,
               ((? - IFNULL(s.last_review, s.due)) / MAX(IFNULL(s.stability, 0.1), 0.1)) DESC,
               s.due ASC${limit == null ? '' : ' LIMIT ?'}
    ''', [
      t0,
      ...fa,
      nowMs,
      nowMs,
      if (limit != null) limit
    ]);
  }

  /// 今日可发的**新词**：只在「已加入记忆且还没学过」的词里取。
  ///
  /// 排序三层（`filter` 从「闸门」改成「第一层优先级」，2026-09-20）：
  ///   ① **当前学习目标卡组的词优先**。用户原话：「学习目标指的是出现多余额度时
  ///      优先添加该卡组的词，不是说除了这个卡组以外不能学其它的，如果这个卡组
  ///      没词可选了再跳转学其它卡组的词」。
  ///      以前 `filter` 是 WHERE 里的硬闸门，于是**卡组学空之后队列永远是空的**：
  ///      额度还剩一堆也没词可发，用户只能自己去换学习目标（`docs/08` 的 Q 段）。
  ///   ② `rank` 非空的优先 —— rank 对 rare 层是 NULL，SQLite 中 NULL 最小，
  ///      不显式排最后就会先学无音标无释义的生僻层（v1 的老 bug）。
  ///   ③ `rank` 升序 = 词频高的先学。
  ///
  /// ⚠️ 把 `filter` 挪进 ORDER BY 之后它**不再过滤**，所以 `fa` 只用在 CASE 里，
  /// 参数仍只传一份；调用方（`buildSessionQueue`）拿到的词可能来自别的卡组，
  /// 这是**有意的**（兜底）。
  Future<List<WordCard>> newWords(
          {int limit = 20, Map<String, dynamic>? filter}) async =>
      interleaveFreshRows(
              await _newWordRows('w.*', limit: limit, filter: filter))
          .map(WordCard.fromDb)
          .toList();

  /// 同 [newWords]，但**只取 id**（队列 id 化，实施单 B）。共用 [_newWordRows]。
  Future<List<String>> newWordIds(
          {int limit = 20, Map<String, dynamic>? filter}) async =>
      [
        for (final r in interleaveFreshRows(await _newWordRows(
            'w.id, w.base_word, w.word',
            limit: limit,
            filter: filter)))
          r['id'] as String
      ];

  /// 新词队列防扎堆微重排（SLA 干扰控制）：
  /// 保持词频与卡组优先的大致顺序，仅在局部窗口 [window] 内将同词根 `base_word`
  /// 或同 4 字母前缀的形近词至少隔开 [minGap] 张，避免连发造成前摄/倒摄干扰。
  static List<Map<String, Object?>> interleaveFreshRows(
    List<Map<String, Object?>> rows, {
    int window = 6,
    int minGap = 3,
  }) {
    if (rows.length <= 2) return rows;
    String keyOf(Map<String, Object?> r) {
      final base = (r['base_word'] as String?)?.trim().toLowerCase() ?? '';
      if (base.isNotEmpty) return 'b:$base';
      var raw = ((r['word'] as String?) ?? (r['id'] as String?) ?? '')
          .trim()
          .toLowerCase();
      // 剥除常见前缀，避免 meng-/memb-/peng-/ber-/ter-/per-/ke-/se-/di- 碰撞在同一桶。
      raw = raw.replaceFirst(
          RegExp(
              r'^(meng|meny|memb|mend|mem|men|peng|peny|pemb|pend|pem|pen|ber|ter|per|ke|se|di)(?=[a-z]{3,})'),
          '');
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
    // 负额度必须在这里拦住，不能只在调用处拦：调用方算的是
    // 「额度 - 今日已学」，用户把额度下调到已学数以下时它就会是负的，
    // 而 **SQLite 的 LIMIT -1 表示不限量**——等于把整个生词库倒进队列。
    // 已由 study_flow_test.dart 的变异测试确认：去掉这一行，测试立刻红。
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

  /// 还有多少「已加入、但还没学过」的词 —— **全库口径，不按当前卡组收窄**。
  ///
  /// ⚠️ 必须是全库：取词现在是「本卡组优先 + 全库兜底」（见 [newWords]），
  /// 这个数用来决定完成页说「今天全清完了」还是「还有生词没排上」
  /// （`StudyStop.nothingToLearn`）。按卡组数的话，卡组学空、兜底还有几千个词时
  /// 会写「没有生词了」，用户一点「再学一组」却又出词，自相矛盾。
  /// 额度对话框那句「还有 N 个已加入、未学的词」同理。
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

  /// 组一节课的队列（**id 版**，学习页用）：**额度是复习 + 新学的总额**，复习优先占额度。
  ///
  /// 用户 2026-09-19 拍板（在「复习也占额度 / 只卡新学 / 两个额度分开」三选一里
  /// 选了第一个）：`dailyQuota` = 今天**总共**学多少**张卡**，到期复习也算在里面。
  ///   · 今日已用量用 [todayAnsweredWords]（今天作答过的卡，**按张去重**，全局不分
  ///     卡组——与「复习不分卡组」是同一条道理）；**第二十九轮之前**这里用的是
  ///     [todayLogCount]（作答条数），于是组内「困难→当场回队→再答」的每一次都扣
  ///     一张额度，一张卡能把额度吃掉 4 张 ⇒ 用户实测「额度 570、答了 588 次、
  ///     只过了一百多个词、还有一堆复习卡被压着」；
  ///   · 剩余额度先给到期卡（按 due 升序 = 欠最久的先来），剩下的给新词；
  ///   · ~~单组 500 张保护闸~~ 已删（实施单 B，用户 2026-10-12）：额度本身就是
  ///     唯一闸门；队列改成**只存 id**（见 [buildSessionQueueIds]），学习页按
  ///     滑动窗口取卡，所以几千张也不卡。
  /// ⚠️ 这一条**撤销了** v2.5.23 的「当天到期复习全量进队」：当时的问题是分 500
  /// 一批且批外数量不可见，现在改成受总额度管、并在完成页明写「还有 N 张到期未复」，
  /// 代价是复习积压时可能永远清不完——这是用户知情后选的。
  ///
  /// `remaining` 会为负：用户把额度下调到今日已学数以下时就会。而 **SQLite 的
  /// `LIMIT -1` 表示不限量**，所以负数必须在 [newWords] 与 [dueCards] 里各拦一道，
  /// 别在调用处 clamp 一次把它掩盖掉——那样 guard 就永远不会被测到了。
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
    // 实施单 B（用户 2026-10-12 明确：500 会干扰新学/复习，必须删）：
    // 原来这里有一道 `perGroupCap = 500` 的保护闸。现在**整组按额度全量进队**，
    // 额度本身（dailyQuota / remaining）是唯一闸门，数字口径不变
    //（todayPlanOf / TodayPlan 仍是唯一来源）；队列里只放 id，不 hydrate。
    final done = await todayAnsweredWords();
    final remaining = dailyQuota - done;
    // 复习不受当前卡组影响（到期的是你的记忆，跟在哪个库里无关）；
    // 新词**按卡组优先、全库兜底**（`filter` 是 ORDER BY 第一层而不是闸门）：
    // 本卡组还有生词就先发它的，本卡组学空了、额度又还有剩，就接着从其它卡组发
    // —— 用户 2026-09-20：「学习目标是优先，不是说别的卡组不能学」。
    final due = remaining <= 0
        ? const <String>[]
        : await dueCardIds(now: now, limit: remaining);
    final freshCap = remaining - due.length;
    final fresh = await newWordIds(limit: freshCap, filter: filter);
    // 池子按**全库**数（不受卡组收窄）：它决定完成页说「全清完了」还是
    // 「还有生词没排上」，卡组口径会与兜底取词自相矛盾。
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

  /// 同 [buildSessionQueueIds]，但把词**全量取出**（测试 / 需要整批卡的调用方用；
  /// 学习页不用它）。取词分批（每批 400）：SQLite 的 `IN (...)` 参数个数有上限，
  /// 几千张一次塞进去会炸。
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

  /// [wordsByIds] 的分批版（保持传入顺序）。
  Future<List<WordCard>> wordsByIdsChunked(List<String> ids,
      {int chunk = 400}) async {
    final out = <WordCard>[];
    for (var i = 0; i < ids.length; i += chunk) {
      out.addAll(await wordsByIds(
          ids.sublist(i, i + chunk > ids.length ? ids.length : i + chunk)));
    }
    return out;
  }

  /// 今天的学习计划（顶栏两条 `x/y 张`、今日进度、底部角标都用它）。
  ///
  /// 一条 SQL 把 `srs` 里的每张卡分成五个互斥的桶（外加池子），
  /// 剩下的算术全在 [todayPlanOf] 里——**别在界面上再算一遍**。
  ///
  /// 判据全部只看 `srs`（不看 `study_log`）：`first_seen` 决定「今天开学的」，
  /// `last_review` 决定「今天答过的」，`due` 决定「今天完没完」。
  /// 这样「一张卡今天答了三次」天然只落进一个桶 ⇒ 进度不会重复涨（用户报的
  /// 「y 会大于 x」就是作答张数当分子造成的）。
  ///
  /// 切线用**明天 00:00**（`t0`）而不是「此刻」：困难/模糊把 due 推到 +10 分钟，
  /// 那张卡今天还没完 ⇒ 它必须留在「还欠着」这一侧，否则复习的分母会在
  /// 那 10 分钟里凭空少一张、10 分钟后又涨回来 —— 又变成「数字变来变去」。
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

  /// 今天**最先作答的 `n` 张卡**里，复习 / 新学各几张（2026-10-18）。
  ///
  /// 用户口径：「额度改得比今日已学还小时，条子也要立刻满，颜色取**先学的那几个
  /// 词**的数据」。所以按 `study_log` 的**首次作答时间**排序、按卡去重，取前 n 张，
  /// 再用与 [todayPlan] 完全相同的判据分类：
  /// `first_seen >= 今天 0 点` = 新学，否则 = 复习。
  ///
  /// ⚠️ 只在「已完成 > 额度」时调用（正常情况直接用 plan 里的两个计数）——
  /// 这时条子已经超额，绿色段要按额度内那几张的构成来上色。
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

  // ---------- 自动签到（第三十三轮：打卡 = 当天全部任务完成）----------

  /// **自动签到**：当天任务全部「彻底过了」（`taskLeft == 0`）的那一刻记一条。
  ///
  /// 挂在 [todayPlan] 里而不是 `logRating` 里：顶栏、角标、完成页、词库页状态条
  /// 都读 plan —— 答完最后一张卡的下一帧必然有一次 plan 读取，签到就发生了；
  /// 挂在写路径反而要在每次作答后多算一遍全量 plan。
  ///
  /// 三条判据：
  ///   · `taskTotal > 0` —— 额度 0 是用户主动「今天不排」，没有「任务」可言，
  ///     白送签到会把连续打卡变成空转（tests 里 todayPlan 常拿 0 额度算账）；
  ///   · `taskLeft == 0` —— 「彻底过了」的分母清零（口径与完成页同一条）；
  ///   · 还没签过 —— **幂等**：签到的时刻取第一次完成那刻，之后不再改
  ///     （打卡不回退：之后又点「困难」让 finished 掉下来，签到的历史不撤销 ——
  ///     与第二十九轮否决「finished 当闸门」是同一个理由：它会回退）。
  ///
  /// 代价：未完成时**零额外查询**；完成时一次 `metaGet`（+首签的一次 `metaSet`）。
  Future<void> _autoCheckin(TodayPlan plan, {DateTime? now}) async {
    if (plan.taskTotal <= 0 || plan.taskLeft > 0) return;
    final key = AppDb.checkinKey(now ?? DateTime.now());
    if (await metaGet(key) != null) return;
    await metaSet(key, '${DateTime.now().millisecondsSinceEpoch}');
  }

  /// 历史签到**回填**（一次性）：本功能（第三十三轮）之前的日子没有签到记录，
  /// 用「**当天碰过去重词数 ≥ 当前额度**」估算补齐。
  ///
  /// ⚠️ 这是**估算**，边界都记在这：
  ///   · 额度**改过**的日子会算不准（老库只存当前值）——额度调小过的历史
  ///     会**漏签**（宁可报少，不报错）；当天任务本来就不满额（池子/到期见底）
  ///     的日子同样漏签。
  ///   · 「今天」永远不回填 —— 今天由 [_autoCheckin] 实时判。
  /// 旗子 `checkin_backfill_v1` 保证只跑一次（study_log 全表按天分组，几万行也
  /// 就是几十毫秒，但没必要每次开「我的」都跑）。
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
      await metaSet(key, '0'); // 回填没有精确时刻，占 0（界面上只判有无）
    }
  }

  /// 某一天签到了吗（有 `checkin:` 记录即真，回填的也算）。
  Future<bool> isSignedDay(DateTime day) async =>
      await metaGet(AppDb.checkinKey(day)) != null;

  /// 一个月的日历数据：每天「碰过去重词数 / 作答次数 / 签到与否」。
  ///
  /// 「我的 → 打卡日历」翻看**之前月份**（第三十三轮）就靠它 —— 旧实现只拿
  /// `recentLogs(60)` 的 60 天，月初翻开上月后半就空白。
  /// 签到 = `checkin:` 记录（实时签的或回填的）；进方法先 [ensureCheckinBackfill]，
  /// 所以老库第一次翻开就有历史签到。
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
      // `DateTime(year, month+1, 1)` 归一化：12 月时 month+1=13 会拼出
      // `checkin:2026-13-`，永远匹配不上（十二月全年无签到的假象）。
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

  // ---------- FSRS 负荷均衡与断签温和顺延 ----------

  /// 查询未来 [daysAhead] 天每天已排定的到期复习卡数（`state = 2`），
  /// 键为相对今天 00:00 的天数偏移（`0, 1, 2, ...`）。
  Future<Map<int, int>> futureDueDayCounts({int daysAhead = 60}) async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final end = start + daysAhead * Duration.millisecondsPerDay;
    final rows = await d.rawQuery(
      'SELECT due FROM srs WHERE state = ? AND due >= ? AND due < ?',
      [FsrsState.review, start, end],
    );
    final counts = <int, int>{};
    for (final r in rows) {
      final due = (r['due'] as int?) ?? start;
      final offset = (due - start) ~/ Duration.millisecondsPerDay;
      if (offset >= 0) counts[offset] = (counts[offset] ?? 0) + 1;
    }
    return counts;
  }

  /// 仅查询负荷均衡所需的局部窗口 `[minDayOffset, maxDayOffset]`（O(1) 区间）。
  Future<Map<int, int>> futureDueWindowCounts({
    required int minDayOffset,
    required int maxDayOffset,
  }) async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final lo = math.max(0, minDayOffset);
    final hi = math.max(lo, maxDayOffset);
    final from = start + lo * Duration.millisecondsPerDay;
    final to = start + (hi + 1) * Duration.millisecondsPerDay;
    final rows = await d.rawQuery(
      'SELECT due FROM srs WHERE state = ? AND due >= ? AND due < ?',
      [FsrsState.review, from, to],
    );
    final counts = <int, int>{};
    for (final r in rows) {
      final due = (r['due'] as int?) ?? from;
      final offset = (due - start) ~/ Duration.millisecondsPerDay;
      if (offset >= lo && offset <= hi) {
        counts[offset] = (counts[offset] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 当前逾期复习卡数量（仅计 `state = 2` 且 `due < 今天 00:00` 的可学词）。
  Future<int> overdueReviewCount() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
      'SELECT COUNT(*) c FROM srs s '
      'JOIN words w ON w.id = s.card_id '
      'WHERE w.enabled = 1 AND s.state = ? AND s.due < ? AND s.first_seen < ?',
      [FsrsState.review, start, start],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 断签温和顺延（Postpone）：仅修改逾期 `state = 2` 复习卡的 `srs.due`，
  /// 绝不改动 `last_review` / `stability` / `difficulty` / `study_log`。
  Future<int> postponeOverdueReviews({
    required int postponeDays,
    double ratio = 0.5,
  }) async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final tomorrowStart = start + Duration.millisecondsPerDay;
    final rows = await d.rawQuery(
      'SELECT s.card_id, s.stability, s.due, s.last_review FROM srs s '
      'JOIN words w ON w.id = s.card_id '
      'WHERE w.enabled = 1 AND s.state = ? AND s.due < ? AND s.first_seen < ?',
      [FsrsState.review, start, start],
    );
    if (rows.isEmpty) return 0;
    final cards = [
      for (final r in rows)
        (
          cardId: r['card_id'] as String,
          stability: (r['stability'] as num?)?.toDouble() ?? 0.0,
          dueMs: (r['due'] as int?) ?? 0,
        ),
    ];
    final lastReviewByCard = <String, int>{
      for (final r in rows)
        if (r['last_review'] is int)
          r['card_id'] as String: r['last_review'] as int,
    };
    final updates = planPostpone(
      cards,
      postponeDays: postponeDays,
      ratio: ratio,
      tomorrowStartMs: tomorrowStart,
      nowMs: start,
      lastReviewByCard: lastReviewByCard,
    );
    if (updates.isEmpty) return 0;
    final batch = d.batch();
    for (final u in updates) {
      batch.update(
        'srs',
        {'due': u.newDueMs},
        where: 'card_id = ?',
        whereArgs: [u.cardId],
      );
    }
    await batch.commit(noResult: true);
    return updates.length;
  }
}
