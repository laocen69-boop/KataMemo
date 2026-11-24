part of 'db.dart';

/// [AppDb] 的实例方法（2026-10-22 从 `db.dart` 原样搬出，只把对静态成员的裸引用补成 `AppDb.`）。
extension AppDbStats on AppDb {
  // ---------- 记忆分档与进度（_kBandExprs 是五档阈值唯一出处） ----------

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

  /// 一次查出**多个**词库的进度（词库页有 9~19 个子类目）。
  ///
  /// 原先逐个查（`loadBookProgress` 串行 await）：19 个子类目 = **38 条聚合 SQL**，
  /// 每条都在 `words`（16,578 行 × `enabled = 1`）上做 LEFT JOIN + COUNT，
  /// 而 `domainsAny` / `topicsAny` 那两类 filter 走的是 `','||domains||',' LIKE '%x%'`，
  /// **用不上索引**（36 个节点用 domainsAny、18 个用 topicsAny）——
  /// 进「按词类/主题词库」子页时那一段掉帧就是这么来的。
  ///
  /// 现在合成**一条** `UNION ALL`：每个类目一个分支，各自带自己的参数
  /// （全部走 `buildFilter()` 的占位符，不做字符串拼接）。
  /// 分支数受 SQLite 变量上限约束，这里最多二十来条，安全。
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
    // 与 [bookProgress] / [dueCards] / `TodayPlan` 同一条切线：**今天之内**到期
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

  /// 五档里某一档的词（选词页点分段条/图例 → 该档词表）。[band] 0..4。
  ///
  /// 条件与 [_bandCols] 的五式**逐字一致**（同一份 `_bandWhere`），
  /// 否则会出现「条上写着 1410，点进去 1389 个」这种对不上的事。
  ///
  /// 排序：
  ///   · 标熟/熟悉/一般（已学过）→ `stability` **升序**：同一档里最接近掉档的排前面，
  ///     这就是用户点进来要看的（「哪些快忘了」）。
  ///   · 不熟/未学 → `rank` 升序：按词频，先看该先学的。
  Future<List<WordCard>> wordsByBand(int band,
      {int limit = 200, int offset = 0, Map<String, dynamic>? filter}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    final order = band >= 3 ? 'w.rank ASC' : 's.stability ASC';
    // ⚠️ 必须 LEFT JOIN：不熟/未学那两档里绝大多数词**没有 srs 行**
    // （加入了但一次都没学过）。用 INNER JOIN 会把它们全滤掉，
    // 于是「条上写着 1410，点进去 0 个」。
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

  // ---------- 学习记录 ----------

  /// 记一次作答，返回自增主键。
  ///
  /// 返回 id 是为了支持「撤销上一张」：撤销要把刚才那条记录精确删掉，
  /// 而不是靠 (card_id, ts) 反查（同一毫秒内可能有多条）。
  Future<int> logRating(String cardId, int rating) async {
    final d = await db;
    return d.insert('study_log', {
      'card_id': cardId,
      'rating': rating,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 撤销一次作答记录
  Future<void> deleteLog(int id) async {
    final d = await db;
    await d.delete('study_log', where: 'id = ?', whereArgs: [id]);
  }

  /// 删掉某词的学习状态（撤销「首次学习」用：撤销后它重新变成新词）
  Future<void> deleteSrs(String cardId) async {
    final d = await db;
    await d.delete('srs', where: 'card_id = ?', whereArgs: [cardId]);
  }

  /// 某张卡的**记忆历史**（照同类记忆 App卡片页最下面那一栏「记忆历史」）。
  ///
  /// 用户 2026-09-23 原话：「记录的是从第一天开始的改单词的记忆历史，颜色由当天
  /// 第一次点击的选项决定，最后的那些小方格是显示今天的记忆的」。
  ///
  /// 返回：
  ///   · `days`   —— **一天一条**（升序，含今天）：`rating` = 当天第一次点的那个选项，
  ///                 `dayNo` = 距第一次学它的那天第几天（第一天 = 1，对应同类记忆 App 的 `D1`）；
  ///   · `logs`   —— 这张卡累计作答次数（表头那句「记忆 N 次」）；
  ///   · `todayExtra` —— **今天第 2 次起**的每一次评级，界面上画成不带 `D` 标签的
  ///                 小方格（就是同类记忆 App `D738@认识` 后面那几格）。
  ///
  /// ⚠️ 「当天第一次」用自增主键 `id` 取、**不是** `ts`：同一毫秒可能落多条
  /// （见 [logRating]）。与 [dailyWordRatingCounts] 是同一条口径。
  /// ⚠️ 撤销（[deleteLog]）删的就是 `study_log` 的行 ⇒ 撤回后**重查这里自然就对了**；
  /// 所以调用方每次换卡 / 作答 / 撤销都要重查，**不要缓存**（「勾稽关系」那一半）。
  Future<
      ({
        List<({DateTime day, int dayNo, int rating})> days,
        int logs,
        List<int> todayExtra,
      })> cardHistory(String cardId) async {
    final d = await db;
    // 一条带索引的查询取这张卡的全部作答（v21->v22 之前没有 card_id 索引，
    // 这里是三条 `WHERE card_id = ?` 的全表扫，随 study_log 长大越来越卡）。
    // 聚合在 Dart 做：这张卡最多几十行，比三条 SQL 各扫全表快一个量级。
    // ⚠️ `ORDER BY id` 钉住「当天第一次 = MIN(id)」的旧口径（见上）：
    //    同 id 升序里每天第一条就是那天 MIN(id) 那条。
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
    // 每天「第一次」的那条：按 id 升序取每个日历键的首条（= 当天 MIN(id)，旧口径）。
    // 输出前按 `yyyy-MM-dd` 键排序 = 日历升序（旧 SQL 的 ORDER BY d）——
    // id 序与日历序在设备时钟被回拨时会分叉，键排序把它们钉回一致。
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
        // 今天第 2 次起：不带标签的小方块
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

  /// 本地时区的 `yyyy-MM-dd`（对应旧 SQL 的 `date(ts/1000,'unixepoch','localtime')`）。
  static String _localDayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  // ---------- 统计（口径唯一出处：天数/时长/趋势/遗忘率） ----------

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
        // 2026-11-02：补上第四档「轻松」——此前没有 case 3，
        // 当天点过轻松的那几条在这张图里**一条都没算**（与趋势图同款漏法）。
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
    // 「今天新学」必须与学习页的额度扣减用**同一个口径**（srs.first_seen 是今天）。
    //
    // 这里原来是 `COUNT(DISTINCT card_id) ... AND card_id IN (SELECT card_id FROM srs
    // WHERE reps <= 1)`，两处都错：
    //   · 30 天前学过、之后没再复习（reps 仍是 1）的词，今天复习一次会被算成「今天新学」
    //   · 今天学、今天又复习（reps 变成 2）的词反而不算
    // 于是统计页的「新学」和学习页的「新词」对不上，用户看到两个数会以为有 bug。
    map['new'] = await todayNewCount();
    // 复习 = 今天答过的去重词数 − 今天新学。**减出来而不是另写一条 COUNT(DISTINCT)**：
    // 这样 `new + review == 去重词数` 是构造出来的恒等式，不可能与趋势图对不上。
    // 那个去重词数就是闸门的扣减依据 [todayAnsweredWords]，**不要再抄一份 SQL**。
    final all = await todayAnsweredWords();
    map['review'] = (all - (map['new'] ?? 0)).clamp(0, all);
    return map;
  }

  /// 连续**签到**天数（第三十三轮起口径 = 「当天完成全部学习任务」，不再是
  /// 「当天碰过词」—— 用户：「打卡日历改为完成所有任务后自动签到」）。
  ///
  /// 判据 = 连续的 `checkin:` 记录（实时签的与回填的都是签到）。
  /// 宽容沿用旧版那条「今天还没学不算断」：今天还没签（任务没做完）时
  /// 从昨天往回数，昨天签了就不断 —— 否则每天 00:00 起刷新页面必显示 0。
  /// 一次 LIKE 查回全部签到键（一年几百条，比逐天 365 次查询轻）。
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
        continue; // 今天还没签不算断（任务还没做完而已）
      } else {
        break;
      }
    }
    return streak;
  }

  /// **历史最长连续签到**（「我的」页打卡英雄区用，第六十一轮）。
  ///
  /// 与 [streakDays] 同一个数据源（meta 的 `checkin:` 键），但算的是**全历史**
  /// 最长连续段，不从今天往回数。meta 表里一天至多一条、总量几百条，
  /// 全扫零压力 —— 不值得为它写 SQL 窗口函数（老安卓也没有）。
  /// 日期解析直接 `DateTime.parse`：键格式就是 `_dayKey` 的 `YYYY-MM-DD`。
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

  /// 近 N 天学习记录（统计图用）。
  ///
  /// 带 `LEFT JOIN srs` 把每条作答对应的 `first_seen` 一起取回来：
  /// 统计页的「近 7 天学习趋势」要按**同类记忆 App 口径**拆「新学词 / 复习词」——
  /// 新学 = 当天首次进入学习的词（`first_seen` 落在当天），复习 = 学过之后
  /// 当天又作答的词。只看 study_log 自己分不出来（它只有 rating/ts）。
  /// 其它调用方（profile_screen）只用 `ts`，多出来的键对它们无害。
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

  /// 今日学习进度（用于打卡/进度条）—— **作答条数**，同一张卡答 4 遍算 4。
  ///
  /// ⚠️ 3.1.x 起它**不再决定额度**（第二十九轮改）：闸门走 [todayAnsweredWords]。
  /// 留着它是因为「我的 → 今日学习 N 次」和额度对话框那句对账要的就是次数。
  Future<int> todayLogCount() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d
        .rawQuery('SELECT COUNT(*) c FROM study_log WHERE ts >= ?', [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 今天**作答过的词数**（按 `card_id` 去重）—— **额度的扣减依据**。
  ///
  /// 为什么按词不按次（用户 2026-09-21 实测：额度 570，「只复习了 100 多张卡
  /// 加 4 张新学卡就达到额度了，一看额度那里说作答了 588 次，还有一堆复习卡被压着」）：
  /// 组内一张卡点「困难」会**当场**回队再来一遍（`StudyScreen._relearnCap` = 3 ⇒
  /// 一张卡一组里最多答 4 次），而旧闸门每次作答都扣一张额度 ⇒ 588 ÷ 110 ≈ 5 倍，
  /// 额度被「同一批没过的卡」重复吃光，真正到期的复习卡反而排不上。
  ///
  /// 这条与统计页/顶栏的口径一致（都按词去重）：它等于 [todayStats] 的
  /// `新学 + 复习`（那边 2026-09-20 就改成按词了，用户原话「一个单词统计一次就够了」）。
  /// ⚠️ 与顶栏分子 [TodayPlan.finished] 仍差一个数：这里是「今天**碰过**的词」，
  /// 那里是「今天**彻底过了**的词」（`due >= 明天 00:00`）。碰过没过的照样占额度，
  /// 否则一个人点 570 次「困难」就能一天不封顶地刷下去。
  Future<int> todayAnsweredWords() async {
    final d = await db;
    final start = AppDb.dayStartMs();
    final r = await d.rawQuery(
        'SELECT COUNT(DISTINCT card_id) c FROM study_log WHERE ts >= ?',
        [start]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// **学习总时长（秒）** —— 「我的 → 学习概况」那个累计时长（第三十一轮）。
  ///
  /// ⚠️ 这是**估算**，口径写死在这里（别按印象改）：
  ///   · 数据只有 `study_log` 的 `(id, ts)`，**没有「每张卡停了多久」的记录**，
  ///     所以按**相邻两次作答的间隔**累计（`id` 序 = 作答序，AUTOINCREMENT 保证）；
  ///   · 秒数说明它数不出什么：打开 App 但一道题没答的那段、最后一张卡之后停的
  ///     那会儿，**都不计**；所以界面上必须写明这是估算。
  ///
  /// **间隔 > [gapCapMs]（默认 60 秒）的整段不计**（不是「封顶 60 秒」——
  /// 那样每跨一次天、每停一次都会凭空多算一分钟；「宁可报少，不要报错」）。
  /// 一分钟的取值依据：正常一张卡 5~20 秒（读例句、看词根拆解会到 30~60 秒），
  /// 一分钟以上基本是放下手机去干别的了。**两段之间隔了一夜也走这支**。
  ///
  /// SQL 用「自连接取相邻 id」而不是窗口函数 `LAG()`：`LAG` 要 SQLite 3.25+，
  /// 老安卓（8/9 自带 3.19~3.22）会用不了 —— 这个项目里踩过版本差异的坑，
  /// 自连接走主键索引，几万条也就几十毫秒。
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

  /// 按天折叠的**学习时长**（秒）：`{'2026-10-09': 754, ...}`（本地时区）。
  ///
  /// 统计页「今日学习」四宫格下面的那条 sparkline 用它（第五十七轮）。
  /// 口径与 [totalStudySeconds] **逐字一致**（相邻作答间隔累计、>60 秒的整段
  /// 不计、宁可报少不报错），区别只是多切了一刀「算在哪一天」：
  ///   · 分天取 `l1.ts`（**前一次**作答所在的本地日期）——一段时长是「从
  ///     l1 答完到 l2 答完」的思考时间，它属于 l1 那一刻，不属于 l2。
  ///     顺手也就保证「一天内部的间隔不会跨天累计」，同一天的分段之和
  ///     与 [totalStudySeconds] 在只查那一天时相等（`statistics_test` 钉住）。
  ///   · 只回**有记录的**天，没学的日子调用方自己补 0（SQL 造不出空行的日期轴）。
  ///
  /// 自连接写法与 [totalStudySeconds] 同款（老安卓没有 `LAG()`，见那边的注释）。
  /// [days] 是回溯窗口，默认 90 天（够画一段有意义的 sparkline，又不至于
  /// 把几万行日志全扫一遍）。
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

  /// 按**主题**统计掌握分布（统计页「掌握情况 · 主题地图」，第五十七轮）。
  ///
  /// 与 [bookProgressBatch] 的区别只有一个：那里的「库」由客户端常量表给定，
  /// 这里的「主题」是**数据里实际出现的**。实测（`data/rebuild/words_new.json`，
  /// 构建字段名是 `tp`、落库是 `words.topics` 逗号串）：
  ///   · 45 个不同主题，12,204 / 34,167 个词挂了至少一个，**一词最多 8 个**；
  ///   · 所以「一词多主题」是常态，`topics` 是**一对多**，不是标签枚举。
  ///
  /// ## 为什么不能靠 SQL 把 `topics` 拆开数
  /// 逗号串拆分在 SQLite 里只能靠 `SUBSTR` + 固定序号的数字表。序号写死成
  /// 1..N，N 取小了会**静默漏掉**排在第 N 个之后的主题（实测有 8 个主题的词，
  /// 写 1..6 就漏 2 个，且不报错）；N 取大了要 `UNION` 一长串、每行都做 8 次
  /// 子串运算，在 16k 行上白白翻倍。
  ///
  /// 所以反过来做，**两步**：
  ///   ① 用 `GROUP BY` + `HAVING` 选出**在记忆里的词数**最多的 [top] 个主题
  ///      （先按 `','||topics||','  LIKE '%,'||t||',%'` 把 `topics` 自己展开成行，
  ///      这一步只在 `words` 上跑一次，与 [bookProgressBatch] 同一量级）；
  ///   ② 对选出的每个主题跑一条 [bookProgress] 同款聚合（`topicsAny` 筛选）。
  /// 20 个主题 = 1 + 20 条 SQL，与 `bookProgressBatch` 的 19 个子类目同量级；
  /// 走的是 `LIKE '%,x,%'`，**用不上索引**——这是 topics 轴的已知限制
  /// （`bookProgressBatch` 的 topics 类目同样吃这一条）。
  ///
  /// ## ⚠️ 百分比**不可求和**
  /// 一个词可以同时属于多个主题，所以各主题的 `total` 加起来 **远大于**
  /// 全库在记忆里的词数，「所有主题加起来掌握了多少」是个没有意义的数。
  /// 界面上只画**单条占比**，且必须写明这一点（`statistics_test` 钉住这句文案）。
  ///
  /// 排序：按 `total`（该主题在记忆里的词数）降序，同样多的按主题名升序
  /// （不稳定排序会让同一份数据两次打开顺序不同）。
  Future<List<({String topic, int total, int started, MemoryBands bands})>>
      topicProgress(
          {int top = 8, Map<String, dynamic>? filter, DateTime? now}) async {
    final d = await db;
    final (fw, fa) = AppDb.buildFilter(filter);
    // ① 取出「数据里实际出现过的主题名」。
    //
    //    ⚠️ 两个坑都要绕开：
    //      · **不要用 `json_each`**：JSON1 扩展在 Android 自带 SQLite 上
    //        要 API 24+ 才默认编译进去（本机 3.53 有，老机器没有），
    //        与 `LAG()` / 窗口函数是同一类坑（见 [totalStudySeconds] 的注释）。
    //        项目铁律：只用 3.19 就有的语法。
    //      · **不要把主题名硬编码成常量表**：主题表随构建变（实测 45 个，
    //        `scripts/rebuild/topics.py` 只增不减 + `topics_extra.json` 策展），
    //        写死就会在下一版词库里静默少画几个主题、且不报错。
    //
    //    所以用**递归 CTE 逐段剥**（3.8.3+ 就有，老安卓安全）：
    //    每轮砍掉 `rest` 里第一个逗号之前的部分，`rest` 为空即停。
    //    实测一词最多 8 个主题（见方法注释），这个写法对段数**没有上限**。
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
    // ② 数每个候选主题挂了多少**在记忆里的**词，取前 top。
    //    整词 `',x,'` LIKE，`交通出行` 不会命中 `交通出行X`（实测过）。
    final rankParts = <String>[];
    final rankArgs = <Object?>[];
    for (final t in topics) {
      // ⚠️ 必须带 LEFT JOIN srs/plan：$inMemorySql 里引用了 `pl.card_id` /
      //    `s.card_id`，FROM 只有 `words w` 的话 SQLite 直接抛
      //    `no such column: pl.card_id` —— 主题地图一打开就崩（第六十轮
      //    真机测试前抓掉的雷；步③本来就是同款 JOIN，别把这里的 JOIN 当冗余删）。
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
    // ③ 每个主题一条聚合（与 [bookProgress] 逐字同源：inMemorySql + _bandCols）
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

  /// 按天统计「**当天第一次作答**」的**词数**，按四档评分折叠：
  /// `{'2026-09-19': (easy: 2, know: 20, fuzzy: 5, forget: 3)}`（本地时区）。
  /// 统计页「学习趋势」的四条折线用它。
  ///
  /// 用户 2026-09-20 更正口径（上一轮我按「当天最后一次判定 + 只算最终记住的」
  /// 实现，是理解偏了，用户原话是「上回我没说清楚」）：
  ///   · 「统计**所有当天过的单词**」→ 当天答过的词都算，不只算最终记住的；
  ///   · 「统计用户在**第一次**遇到这个单词时点的是什么」→ 每词取当天**最早**
  ///     那条（`MIN(id)`），不是最后一条；
  ///   · 「一个单词**统计一次**就够了」→ 按词去重：同一天答 5 次也只算 1 个；
  ///   · 「总数等于**当日的复习加新学**」→ 四档之和 == 当天答过的去重词数 ==
  ///     [todayStats] 的 新学 + 复习（那边也改成了去重词数口径，见它的注释）。
  ///
  /// 2026-11-02 用户：「学习趋势还是没有统计『轻松』的数据」。根因就在这：
  /// 上一版 switch 只写了 2 / 1 / 0，`rating 3`（轻松）落进 `_` 被直接丢掉，
  /// 导致那条柱的总数比「今日学习」少，图例里也没有蓝色那条。现在四档齐全。
  ///
  /// 为什么用 `MIN(id)` 而不是窗口函数 `ROW_NUMBER()`：Android 自带的 SQLite
  /// 在 API < 30 上还没有窗口函数（要 3.25+），装到老机器上会直接崩。
  /// 用自增主键而不是 `ts`：同一毫秒可能有多条（`logRating` 的注释写过）。
  ///
  /// 30 个月要回溯约 950 天（统计页趋势图的默认窗口），把行原样取回来
  /// （`recentLogs`）太重——SQL 里先折叠到「每天每词一条」，回来只有几百行。
  /// `strftime(..., 'localtime')` 是关键：study_log 存的是 epoch 毫秒，
  /// 不转本地时区的话「今天」会按 UTC 切，跨零点前后统计会漂。
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

  /// 某一天的**学习数据**（打卡日历点开某天看它 —— 用户 2026-09-24 的需求）。
  ///
  /// 口径与统计页/学习页**同源**，不另起一套（这是本项目最容易漂移的地方）：
  ///   · [DayStats.words]   当天碰过的**去重词数**（`COUNT(DISTINCT card_id)`，
  ///                        就是额度扣减依据 [todayAnsweredWords] 的同一条口径）；
  ///   · [DayStats.answers] 当天**作答次数**（同一张卡答 4 遍算 4 次，与「今日学习 N 次」同源）；
  ///   · [DayStats.newWords] 其中**这天第一次见到**的词数 —— 判据是「该词在全库的
  ///                        **首次**作答落在这一天」（与 [dailyWordRatingCounts] 的
  ///                        `MIN(id)`、学习趋势的「新学」同口径）；
  ///   · `know/fuzzy/forget` 当天**每词取第一次作答**分档（与趋势图逐字一致）。
  ///
  /// [DayStats.reviewWords] 由 `words - newWords` **算出来**、不另写一条 COUNT：
  /// 这样「新学 + 复习 == 碰过的词数」是构造出来的恒等式（与 [todayStats] 同一手法），
  /// 两个数不可能对不上。
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

    // 「这天新学」：该词**全库首次**作答落在这一天（不看 srs.first_seen ——
    // 那是「当前」值，回头查历史某天会被后来的复习改写，见 todayStats 的注释）。
    final nw = await d.rawQuery('''
      SELECT COUNT(*) c FROM (
        SELECT card_id, MIN(ts) AS f FROM study_log GROUP BY card_id
      ) WHERE f >= ? AND f < ?
    ''', [t0, t1]);
    final newWords = (nw.isEmpty ? 0 : (nw.first['c'] as int? ?? 0));

    // 四档：当天每词第一次作答的评分（`MIN(id)`，与趋势图同一条 SQL 的形状）。
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

  /// 有 FSRS 状态的词数（= 已学）
  Future<int> learnedWordCount() async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM srs WHERE card_id IN (SELECT id FROM words)');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// 遗忘曲线：按「距上次复习的天数」分档的**实测**困难率。
  ///
  /// 用户 2026-09-21：「忘记率的表格设计也不合理」。旧版 `forgetRateByReps`
  /// 拿每个词**当前**的 `srs.reps` 当横轴，看的是「现在很熟的词当年忘过几次」——
  /// 幸存者偏差：能活到 reps=10 的词本来就好记，柱子必然一路往下掉，
  /// 界面上那句「这不是真正的遗忘曲线」就是在替它认错。改成按**当时的间隔**分档：
  /// 每条作答只按它自己那次的间隔入档，早早忘掉的词落在短间隔档里，不会被漏掉。
  ///
  /// 口径（与「学习趋势」同一套，不是另起一套）：
  ///   · 一个词**一天只算一次**，取当天**第一次**作答（`MIN(id)`，
  ///     与 [dailyWordRatingCounts] 同源）；
  ///   · 该词**第一次**出现的那天是「新学」，不算复习，不进任何档；
  ///   · 间隔 = 本次复习日 − 上一次作答日（按天算：同一天再答 5 次也只算 1 次）；
  ///   · 困难 = 评分 0（与 [overallRecallRate] 的「认识＋模糊」互补）。
  ///
  /// 分母是**复习次数**而不是词数：一个词第 3 天忘一次、第 10 天记住，
  /// 就分别给「1–3 天档」和「8–14 天档」各记 1 次分母、0 或 1 次困难。
  ///
  /// 固定返回 8 档（空档也在），画不画由界面按样本量决定（`statBinVisible`）——
  /// SQL 这边不写 LIMIT，旧版那个 `LIMIT 20` 会悄悄截断，界面上看不出来。
  ///
  /// 用 `date()` + Dart 侧算间隔，不用窗口函数 `LAG()`：Android 自带 SQLite
  /// 要 3.25+ 才有窗口函数，装到老机器上直接崩（[dailyWordRatingCounts] 同款坑）。
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
        continue; // 该词第一次出现的那天 = 新学，不算复习
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

  /// 总体回忆率（与目标保留率同口径）：
  /// 优先统计**跨天复习**（距上次作答 >= 1 天，每词每天取首次作答，与 [forgetRateByInterval] 同源）；
  /// 若尚无跨天复习记录（如首日学习），回退为全量作答中「评分 >= 模糊」的比例；无记录返回 null。
  Future<double?> overallRecallRate() async {
    final bins = await forgetRateByInterval();
    var crossReviews = 0;
    var crossForgets = 0;
    for (final b in bins) {
      crossReviews += b.reviews;
      crossForgets += b.forgets;
    }
    if (crossReviews > 0) {
      return (crossReviews - crossForgets) / crossReviews;
    }
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c, SUM(CASE WHEN rating >= 1 THEN 1 ELSE 0 END) ok FROM study_log');
    if (r.isEmpty) return null;
    final total = r.first['c'] as int? ?? 0;
    if (total == 0) return null; // 分母为 0，「回忆率」没有意义
    final ok = r.first['ok'] as int? ?? 0;
    return ok / total;
  }

  /// 全量已学词的稳定度列表（供记忆曲线计算混合期望 `1/N ∑ R(t, S_i)`，消除中位数詹森不等式偏差）。
  Future<List<double>> learnedStabilities() async {
    final d = await db;
    final r = await d.rawQuery('''
      SELECT stability FROM srs
      WHERE reps > 0 AND stability > 0 AND card_id IN (SELECT id FROM words)
      ORDER BY stability ASC
    ''');
    return [
      for (final x in r)
        if ((x['stability'] as num?) != null) (x['stability'] as num).toDouble(),
    ];
  }

  /// 已学词的平均记忆稳定性（天）。统计页的记忆曲线用它当 S，
  /// 取代原先写死的 15 天——那条曲线画的是「如果 S=15，遗忘有多快」，
  /// 与用户自己的数据毫无关系。
  ///
  /// 用中位数而非平均数：稳定性分布长尾很重（个别词能到几百天），
  /// 平均数会被少数复习过很多次的词拉飞。
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
