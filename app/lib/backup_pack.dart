library;

import 'package:sqflite/sqflite.dart';

const String kPackFormat = 'katamemo-pack';
const int kPackFormatVersion = 1;

const List<String> kPackSettingKeys = [
  'new_quota', 'auto_speak', 'retention', 'dark_mode', 'theme_mode',
  'fsrs_load_balance', 'study_mode',
  'show_intervals', 'library_sort', 'study_ui_style', 'lib_ui_style',
  'reminder_on', 'current_book',
  'fsrs_w', 'fsrs_w_ts',
];

class PackImportReport {
  int srsNew = 0, srsUpdated = 0, srsKept = 0;
  int logAdded = 0, logSkipped = 0;
  int planAdded = 0, editApplied = 0, listAdded = 0, customAdded = 0;
  int grammarEditApplied = 0;
  int unmatched = 0;
  List<String> unmatchedSample = [];
}

class PackException implements Exception {
  final String message;
  PackException(this.message);
  @override
  String toString() => message;
}

class BackupPack {
  BackupPack._();

  static Future<Map<String, Object?>> export(
    DatabaseExecutor db, {
    required int schemaVersion,
    required int dataVersion,
    required String appVersion,
  }) async {
    final logs = await db
        .rawQuery('SELECT card_id, rating, ts FROM study_log ORDER BY ts');
    final meta = await db.query('meta');
    return {
      'format': kPackFormat,
      'formatVersion': kPackFormatVersion,
      'schemaVersion': schemaVersion,
      'dataVersion': dataVersion,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'srs': await db.query('srs'),

      'studyLog': [
        for (final r in logs) [r['card_id'], r['rating'], r['ts']]
      ],
      'plan': await db.query('plan'),
      'userEdit': await db.query('user_edit'),
      'wordList':
          await db.rawQuery('SELECT name, ids_json, created_at FROM word_list'),

      'grammarProgress': await db.query('grammar_progress'),

      'grammarEdit': await db.query('grammar_edit'),

      'customWords': await db
          .rawQuery('SELECT * FROM words WHERE COALESCE(user_word,0)=1'),

      'wordFlags': await db.rawQuery(
          'SELECT id, favorite, enabled FROM words WHERE COALESCE(user_word,0)=0 '
          'AND (COALESCE(favorite,0)=1 OR COALESCE(enabled,1)=0)'),
      'meta': [
        for (final m in meta)
          if (kPackSettingKeys.contains(m['k']) ||
              (m['k'] as String).startsWith('checkin:'))
            {'k': m['k'], 'v': m['v']}
      ],
    };
  }

  static Future<PackImportReport> import(
    DatabaseExecutor txn,
    Map<String, Object?> pack, {
    required int localSchemaVersion,
    bool restoreSettings = true,
  }) async {
    if (pack['format'] != kPackFormat) {
      throw PackException('这不是 KataMemo 的学习数据包。');
    }
    final fv = (pack['formatVersion'] as num?)?.toInt() ?? 0;
    final sv = (pack['schemaVersion'] as num?)?.toInt() ?? 0;
    if (fv > kPackFormatVersion || sv > localSchemaVersion) {
      throw PackException('这个数据包来自更新版本的 App，请先把 App 升级到最新版再导入。');
    }
    final rep = PackImportReport();
    final orphan = <String>{};
    List<Map<String, Object?>> list(String k) =>
        ((pack[k] as List?) ?? const []).cast<Map<String, Object?>>();

    for (final w in list('customWords')) {
      final has =
          await txn.rawQuery('SELECT 1 FROM words WHERE id=?', [w['id']]);
      if (has.isEmpty) {
        await txn.insert('words', w);
        rep.customAdded++;
      }
    }
    final known = {
      for (final r in await txn.rawQuery('SELECT id FROM words'))
        r['id'] as String
    };
    bool ok(String id) {
      if (known.contains(id)) return true;
      orphan.add(id);
      return false;
    }

    final keptLocalNewer = <String>{};
    final incomingSrsIds = <String>{};
    final local = {
      for (final r in await txn.query('srs')) r['card_id'] as String: r
    };
    for (final r in list('srs')) {
      final id = r['card_id'] as String;
      if (!ok(id)) continue;
      incomingSrsIds.add(id);
      final cur = local[id];
      if (cur == null) {
        await txn.insert('srs', r);
        rep.srsNew++;
        continue;
      }
      final fsA = cur['first_seen'] as int?, fsB = r['first_seen'] as int?;
      final fs =
          fsA == null ? fsB : (fsB == null ? fsA : (fsA < fsB ? fsA : fsB));
      final curLr = (cur['last_review'] as int?) ?? 0;
      final rLr = (r['last_review'] as int?) ?? 0;
      final newer = rLr > curLr;
      if (newer) {
        await txn.update(
            'srs',
            {
              'stability': r['stability'],
              'difficulty': r['difficulty'],
              'due': r['due'],
              'last_review': r['last_review'],
              'reps': r['reps'],
              'lapses': r['lapses'],
              'state': r['state'],
              'step': r['step'],
              'first_seen': fs,
            },
            where: 'card_id=?',
            whereArgs: [id]);
        rep.srsUpdated++;
      } else {
        if (curLr > rLr) keptLocalNewer.add(id);
        await txn.update('srs', {'first_seen': fs},
            where: 'card_id=?', whereArgs: [id]);
        rep.srsKept++;
      }
    }
    for (final id in local.keys) {
      if (!incomingSrsIds.contains(id)) keptLocalNewer.add(id);
    }

    final have = {
      for (final r
          in await txn.rawQuery('SELECT card_id, ts, rating FROM study_log'))
        '${r['card_id']}|${r['ts']}|${r['rating']}'
    };
    final logs = ((pack['studyLog'] as List?) ?? const []).cast<List>();
    final batch = txn.batch();
    for (final r in logs) {
      final id = r[0] as String;
      if (!ok(id)) continue;
      final key = '$id|${r[2]}|${r[1]}';
      if (have.contains(key)) {
        rep.logSkipped++;
        continue;
      }
      have.add(key);
      batch.insert('study_log', {'card_id': id, 'rating': r[1], 'ts': r[2]});
      rep.logAdded++;
    }
    await batch.commit(noResult: true);

    final incomingPlanIds = <String>{};
    for (final r in list('plan')) {
      final id = r['card_id'] as String;
      if (!ok(id)) continue;
      incomingPlanIds.add(id);
      final cur =
          await txn.rawQuery('SELECT ts FROM plan WHERE card_id=?', [id]);
      if (cur.isEmpty) {
        await txn.insert('plan', r);
        rep.planAdded++;
        await txn.update('words', {'enabled': 1},
            where: 'id=? AND enabled=0', whereArgs: [id]);
      } else if ((r['ts'] as int) < (cur.first['ts'] as int)) {
        await txn.update('plan', {'ts': r['ts']},
            where: 'card_id=?', whereArgs: [id]);
      }
    }
    final localOnlyPlanned = {
      for (final r in await txn.rawQuery('SELECT card_id FROM plan'))
        if (!incomingPlanIds.contains(r['card_id'] as String))
          r['card_id'] as String
    };

    for (final r in list('userEdit')) {
      final id = r['card_id'] as String;
      if (!ok(id)) continue;
      final cur = await txn.rawQuery(
          'SELECT ts FROM user_edit WHERE card_id=? AND field=?',
          [id, r['field']]);
      final inTs = (r['ts'] as int?) ?? 0;
      if (cur.isEmpty || inTs > ((cur.first['ts'] as int?) ?? 0)) {
        await txn.insert('user_edit', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
        rep.editApplied++;
      }
    }

    final localLists = [
      for (final r
          in await txn.rawQuery('SELECT name, ids_json FROM word_list'))
        {'name': r['name'] as String, 'ids': r['ids_json'] as String}
    ];
    final names = {for (final l in localLists) l['name']!};
    for (final r in list('wordList')) {
      final name = r['name'] as String, ids = r['ids_json'] as String;
      final same = localLists.any((l) =>
          l['ids'] == ids &&
          (l['name'] == name || l['name']!.startsWith('$name（导入')));
      if (same) continue;
      var n = name;
      if (names.contains(n)) {
        n = '$name（导入）';
        var i = 2;
        while (names.contains(n)) {
          n = '$name（导入$i）';
          i++;
        }
      }
      await txn.insert('word_list',
          {'name': n, 'ids_json': ids, 'created_at': r['created_at']});
      names.add(n);
      localLists.add({'name': n, 'ids': ids});
      rep.listAdded++;
    }

    for (final r in list('grammarProgress')) {
      final cid = r['card_id'] as String;
      final inSeen = (r['seen_at'] as num?)?.toInt();
      final inStar = ((r['starred'] as num?)?.toInt() ?? 0) != 0;
      final inOk = (r['drill_ok'] as num?)?.toInt() ?? 0;
      final inTot = (r['drill_total'] as num?)?.toInt() ?? 0;
      final cur = await txn.query('grammar_progress',
          where: 'card_id = ?', whereArgs: [cid], limit: 1);
      if (cur.isEmpty) {
        await txn.insert('grammar_progress', {
          'card_id': cid,
          'seen_at': inSeen,
          'starred': inStar ? 1 : 0,
          'drill_ok': inOk,
          'drill_total': inTot,
        });
        continue;
      }
      final c = cur.first;
      await txn.update(
          'grammar_progress',
          {
            'seen_at': _maxInt((c['seen_at'] as num?)?.toInt(), inSeen),
            'starred':
                (((c['starred'] as num?)?.toInt() ?? 0) != 0 || inStar) ? 1 : 0,
            'drill_ok': _maxInt((c['drill_ok'] as num?)?.toInt(), inOk),
            'drill_total': _maxInt((c['drill_total'] as num?)?.toInt(), inTot),
          },
          where: 'card_id = ?',
          whereArgs: [cid]);
    }

    for (final r in list('grammarEdit')) {
      final cur = await txn.rawQuery(
          'SELECT ts FROM grammar_edit WHERE scope=? AND page_id=? AND block_key=?',
          [r['scope'], r['page_id'], r['block_key']]);
      final inTs = (r['ts'] as int?) ?? 0;
      if (cur.isEmpty || inTs > ((cur.first['ts'] as int?) ?? 0)) {
        await txn.insert('grammar_edit', r,
            conflictAlgorithm: ConflictAlgorithm.replace);
        rep.grammarEditApplied++;
      }
    }

    // 7) 库词的收藏 / 停用标记（安全合并：不抹掉本地已收藏，不让旧包覆盖本地更新的 SRS 词）
    for (final r in list('wordFlags')) {
      final id = r['id'] as String?;
      if (id == null) continue;
      final patch = <String, Object?>{};
      if (((r['favorite'] as int?) ?? 0) == 1) {
        patch['favorite'] = 1;
      }
      final en = r['enabled'] as int?;
      if (en != null &&
          !keptLocalNewer.contains(id) &&
          !(en == 0 && localOnlyPlanned.contains(id))) {
        patch['enabled'] = en;
      }
      if (patch.isEmpty) continue;
      await txn.update('words', patch,
          where: 'id=? AND COALESCE(user_word,0)=0', whereArgs: [id]);
    }

    for (final m in list('meta')) {
      final k = m['k'] as String;
      if (k.startsWith('checkin:')) {
        await txn.insert('meta', m,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } else if (restoreSettings && kPackSettingKeys.contains(k)) {
        await txn.insert('meta', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    rep.unmatched = orphan.length;
    rep.unmatchedSample = (orphan.toList()..sort()).take(20).toList();
    return rep;
  }
}

int? _maxInt(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}
