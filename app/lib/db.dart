library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'audio.dart' show AudioService, kUserAudioPrefix;
import 'platform/io_shim.dart' show ensureWebDatabaseFactory;
import 'clitic.dart';
import 'models.dart';
import 'passive.dart';
import 'derived_form.dart';
import 'topic_classifier.dart';
import 'spacing.dart';
import 'fsrs.dart';
import 'grammar/grammar_edit.dart';
import 'ai_history.dart' show kAiChatDdl, kAiChatIdx;
import 'dict_import/dict_store.dart' show createDictTables;

part 'db_grammar.dart';
part 'db_words.dart';
part 'db_search.dart';
part 'db_card.dart';
part 'db_study.dart';
part 'db_stats.dart';

const String kGrammarEditDdl = '''
  CREATE TABLE grammar_edit (
    scope TEXT NOT NULL,
    page_id TEXT NOT NULL,
    block_key TEXT NOT NULL,
    kind TEXT NOT NULL,
    payload TEXT NOT NULL,
    ts INTEGER NOT NULL,
    PRIMARY KEY (scope, page_id, block_key)
  )''';

const int kDataVersion = 927000;

const int kSchemaVersion = 29;

typedef TodayPlan = ({

  int quota,

  int finished,
  int newDone,
  int reviewDone,

  int newPending,
  int reviewPending,

  int reviewBacklog,

  int reviewPlan,

  int newPlan,

  int taskTotal,

  int taskLeft,

  int quotaShown,

  int poolLeft,
});

extension TodayPlanX on TodayPlan {
  int get reviewShown => reviewPlan < quotaShown ? reviewPlan : quotaShown;
}

typedef ForgetBin = ({String label, int reviews, int forgets, int words});

typedef WordListStat = ({
  int id,
  String name,
  int count,
  int joined,
  int learned,
});

const List<String> _kIntervalLabels = [
  '1',
  '2',
  '3',
  '4-7',
  '8-14',
  '15-30',
  '31-90',
  '90+',
];

TodayPlan todayPlanOf({
  required int quota,
  required int newDone,
  required int reviewDone,
  required int newPending,
  required int reviewPending,
  required int reviewBacklog,
  required int poolLeft,
}) {
  final finished = newDone + reviewDone;
  final quotaShown = quota > finished ? quota : finished;
  final reviewPlan = reviewDone + reviewPending + reviewBacklog;

  final newRoom = (quotaShown - reviewPlan).clamp(0, quotaShown);

  final newAvail = newDone + newPending + poolLeft;
  var newPlan = newAvail < newRoom ? newAvail : newRoom;
  if (newPlan < newDone) newPlan = newDone;
  final total = reviewPlan + newPlan;
  final taskTotal = total < quotaShown ? total : quotaShown;
  final left = taskTotal - finished;
  return (
    quota: quota,
    finished: finished,
    newDone: newDone,
    reviewDone: reviewDone,
    newPending: newPending,
    reviewPending: reviewPending,
    reviewBacklog: reviewBacklog,
    reviewPlan: reviewPlan,
    newPlan: newPlan,
    taskTotal: taskTotal,
    taskLeft: left > 0 ? left : 0,
    quotaShown: quotaShown,
    poolLeft: poolLeft,
  );
}

class DayStats {

  final int words;

  final int answers;

  final int newWords;

  final int easy;
  final int know;
  final int fuzzy;
  final int forget;

  const DayStats({
    required this.words,
    required this.answers,
    required this.newWords,
    required this.easy,
    required this.know,
    required this.fuzzy,
    required this.forget,
  });

  int get reviewWords => (words - newWords).clamp(0, words);

  bool get isEmpty => words == 0;
}

class MonthDay {

  final int words;

  final int answers;

  final bool signed;

  const MonthDay(
      {required this.words, required this.answers, this.signed = false});

  MonthDay markSigned() =>
      MonthDay(words: words, answers: answers, signed: true);

  bool get isEmpty => words == 0 && !signed;
}

class AppDb {
  Database? _db;

  bool get isOpen => _db != null;
  bool _closed = false;
  final String? dbPath;

  AppDb({this.dbPath});

  bool get isClosed => _closed;

  Future<Database> get db async => _db ??= await _open();

  Future<void> close() async {
    _closed = true;
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    _closed = false;
    ensureWebDatabaseFactory();
    final path = dbPath ??
        (kIsWeb
            ? 'katamemo.db'
            : p.join(await getDatabasesPath(), 'katamemo.db'));
    return openDatabase(path,
        version: kSchemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static const _wordColumns = '''
      CREATE TABLE words (
        id TEXT PRIMARY KEY,
        word TEXT NOT NULL,
        tier TEXT,
        rank INTEGER,
        frequency INTEGER DEFAULT 0,
        phonetic TEXT,
        word_class TEXT,
        full_name TEXT,
        affix_type TEXT,
        pos_all TEXT,
        proper_kind TEXT,
        domains TEXT,
        topics TEXT,
        origin TEXT,
        base_word TEXT,
        non_standard TEXT,
        non_standard_forms TEXT,
        clitics TEXT,
        variants TEXT,
        senses TEXT,
        examples TEXT,
        derivations TEXT,
        gabungan TEXT,
        root_count INTEGER,
        zh TEXT,
        affix_base TEXT,
        affixes TEXT,
        grammar_function TEXT,
        grammar_notes TEXT,
        audio_ardi TEXT,
        audio_gadis TEXT,
        audio_human TEXT,
        -- 组件拼接发音（kSchemaVersion 21）：JSON 数组，元素是 assets 相对路径。
        -- 只给没有整句音频的 KBBI 搭配卡用；播放时按顺序播、词间留空档。
        -- 空 = 走 audio_ardi / audio_human 的老路径。
        audio_parts TEXT,
        mnemonic TEXT,
        mnemonic_default TEXT,
        mnemonic_images TEXT,
        -- 短语词频子轴（kSchemaVersion 24，2026-11-01）：p1 高频 / p2 常用 / p3 低频 /
        -- p0 未收录。**只对 tier='phrase' 的条目有值**，单字走 tier 的 t1–t7。
        phrase_tier TEXT,
        -- 词组与短语语言学细类（kSchemaVersion 29，2026-11-21）：peribahasa / idiom /
        -- func / term / verbal / adj / nominal。只对 tier='phrase' 的条目有值。
        phrase_kind TEXT,
        -- 中文释义逐段词性（kSchemaVersion 25，2026-11-01）：`v|n` 这种，
        -- 与 `zh` 的「；」段一一对应；空 = 未核对，界面用卡级 pa 前缀。
        zh_pos TEXT,
        -- 拼写题面中文（第三十六轮）：默认由 question_zh.dart 从 zh 现算，
        -- 用户单独改过才有值。**不是** `zh`——那边是印尼-中模式的释义，不许动。
        quiz_zh TEXT,
        user_word INTEGER DEFAULT 0,
        user_blocks TEXT,
        card_order TEXT,
        -- 词频未知标记（kSchemaVersion 18 建「无词频」，2026-10-31 改两源口径）：
        -- 1 = wordfreq 与牌组语料都没有的可学词；
        -- 「无词频」卡组用它筛（buildFilter 的 noFreq 轴）。必须是 INTEGER。
        no_freq INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        favorite INTEGER DEFAULT 0
      )''';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_wordColumns);
    await db.execute('''
      CREATE TABLE srs (
        card_id TEXT PRIMARY KEY,
        stability REAL DEFAULT 0,
        difficulty REAL DEFAULT 5,
        due INTEGER,
        last_review INTEGER,
        reps INTEGER DEFAULT 0,
        lapses INTEGER DEFAULT 0,
        state INTEGER DEFAULT 0,
        step INTEGER DEFAULT 0,
        first_seen INTEGER
      )''');
    await db.execute('''
      CREATE TABLE study_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id TEXT,
        rating INTEGER,
        ts INTEGER
      )''');
    await db.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT)');

    await db.execute('''
      CREATE TABLE plan (
        card_id TEXT PRIMARY KEY,
        ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE user_edit (
        card_id TEXT NOT NULL,
        field TEXT NOT NULL,
        value TEXT,
        ts INTEGER,
        PRIMARY KEY (card_id, field)
      )''');

    await db.execute('''
      CREATE TABLE word_list (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ids_json TEXT NOT NULL,
        created_at INTEGER
      )''');

    await db.execute('''
      CREATE TABLE grammar_progress (
        card_id TEXT PRIMARY KEY,
        seen_at INTEGER,
        starred INTEGER NOT NULL DEFAULT 0,
        drill_ok INTEGER NOT NULL DEFAULT 0,
        drill_total INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute(kGrammarEditDdl);
    await db.execute('CREATE INDEX idx_words_tier ON words(tier)');
    await db.execute('CREATE INDEX idx_srs_due ON srs(due)');
    await db.execute('CREATE INDEX idx_log_ts ON study_log(ts)');
    await db.execute('CREATE INDEX idx_words_rank ON words(rank)');

    await db.execute('CREATE INDEX idx_words_word_class ON words(word_class)');

    await db.execute('CREATE INDEX idx_log_card ON study_log(card_id)');

    await db.execute(kAiChatDdl);
    await db.execute(kAiChatIdx);

    await createDictTables(db);
  }

  Future<void> _onUpgrade(Database db, int from, int to) async {
    Future<void> addCol(String name) async {
      try {
        await db.execute('ALTER TABLE words ADD COLUMN $name TEXT');
      } catch (_) {}
    }

    await addCol('examples');
    await addCol('derivations');
    await addCol('non_standard_forms');

    await addCol('topics');

    await addCol('clitics');

    await addCol('mnemonic_images');

    await addCol('grammar_function');
    await addCol('grammar_notes');

    await addCol('full_name');

    await addCol('affix_type');

    await addCol('pos_all');

    await addCol('proper_kind');

    await addCol('mnemonic_default');

    await addCol('quiz_zh');

    try {
      await db
          .execute('ALTER TABLE words ADD COLUMN user_word INTEGER DEFAULT 0');
    } catch (_) {}

    await addCol('user_blocks');
    await addCol('card_order');

    try {
      await db.execute('ALTER TABLE words ADD COLUMN no_freq INTEGER DEFAULT 0');
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE words ADD COLUMN root_count INTEGER');
    } catch (_) {}
    await db.execute(
        'CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS word_list (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        ids_json TEXT NOT NULL,
        created_at INTEGER
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_edit (
        card_id TEXT NOT NULL,
        field TEXT NOT NULL,
        value TEXT,
        ts INTEGER,
        PRIMARY KEY (card_id, field)
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS plan (
        card_id TEXT PRIMARY KEY,
        ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS grammar_progress (
        card_id TEXT PRIMARY KEY,
        seen_at INTEGER,
        starred INTEGER NOT NULL DEFAULT 0,
        drill_ok INTEGER NOT NULL DEFAULT 0,
        drill_total INTEGER NOT NULL DEFAULT 0
      )''');

    await addCol('gabungan');

    await addCol('audio_parts');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_log_card ON study_log(card_id)');

    await addCol('phrase_tier');
    await addCol('phrase_kind');

    await addCol('zh_pos');

    await db.execute(kAiChatDdl.replaceFirst('CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS '));
    await db.execute(kAiChatIdx.replaceFirst('CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS '));

    try {
      await db.execute(
          "ALTER TABLE dict_entry ADD COLUMN fold_loose TEXT NOT NULL DEFAULT ''");
    } catch (_) {}

    await createDictTables(db);

    await db.execute(kGrammarEditDdl.replaceFirst(
        'CREATE TABLE ', 'CREATE TABLE IF NOT EXISTS '));

    await db.execute('''
      UPDATE dict_entry SET fold_loose =
        lower(replace(replace(replace(replace(
          CASE
            WHEN fold GLOB '*([0-9][0-9])' THEN substr(fold, 1, instr(fold, '(') - 1)
            WHEN fold GLOB '*([0-9])' THEN substr(fold, 1, instr(fold, '(') - 1)
            ELSE fold
          END
        , '.', ''), '-', ''), '·', ''), ' ', ''))
      WHERE fold_loose = '' OR fold_loose IS NULL
      ''');
    var hasFirstSeen = false;
    final cols = await db.rawQuery('PRAGMA table_info(srs)');
    for (final c in cols) {
      if (c['name'] == 'first_seen') hasFirstSeen = true;
    }
    if (!hasFirstSeen) {
      await db.execute('ALTER TABLE srs ADD COLUMN first_seen INTEGER');

      await db.execute('''
        UPDATE srs SET first_seen = (
          SELECT MIN(l.ts) FROM study_log l WHERE l.card_id = srs.card_id
        ) WHERE first_seen IS NULL''');
    }

    if (from < 3) {
      await db.delete('meta', where: 'k = ?', whereArgs: ['data_version']);
    }
  }

  final Map<String, _GramPending> _gramPending = {};
  String? _gramLastDirty;
  Timer? _gramTimer;

  static const String _kGramLast = 'gram.last';
  static const String _kGramFilter = 'gram.filter';

  Future<int> dataVersion() async {
    final d = await db;
    final r = await d.query('meta',
        where: 'k = ?', whereArgs: ['data_version'], limit: 1);
    if (r.isEmpty) return 0;
    return int.tryParse(r.first['v'] as String? ?? '') ?? 0;
  }

  Future<void> setDataVersion(int v) async {
    final d = await db;
    await d.insert('meta', {'k': 'data_version', 'v': '$v'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> metaGet(String k) async {
    final d = await db;
    final r = await d.query('meta', where: 'k = ?', whereArgs: [k], limit: 1);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> metaSet(String k, String v) async {
    final d = await db;
    await d.insert('meta', {'k': k, 'v': v},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> metaDelete(String k) async {
    final d = await db;
    await d.delete('meta', where: 'k = ?', whereArgs: [k]);
  }

  Future<List<List<Object>>> allReviewRows() async {
    final d = await db;
    final rows = await d
        .rawQuery('SELECT card_id, ts, rating FROM study_log ORDER BY ts');
    return [
      for (final r in rows)
        [
          r['card_id'] as String,
          (r['ts'] as num).toInt(),
          (r['rating'] as num).toInt()
        ]
    ];
  }

  Future<String?> currentBook() => metaGet('current_book');

  Future<void> setCurrentBook(String? bookId) async {
    final d = await db;
    if (bookId == null || bookId.isEmpty || bookId == 'all') {
      await d.delete('meta', where: 'k = ?', whereArgs: ['current_book']);
      return;
    }
    await metaSet('current_book', bookId);
  }

  static String? encodeExamples(List<({String i, String? z})> ex) =>
      WordCard.encodeMaps([
        for (final e in ex)
          if (e.i.trim().isNotEmpty) {'i': e.i.trim(), 'z': (e.z ?? '').trim()},
      ]);

  static (String, List<Object?>) buildFilter(Map<String, dynamic>? f) {
    if (f == null || f.isEmpty) return ('1=1', const []);
    final parts = <String>[];
    final args = <Object?>[];

    final tiers = (f['tier'] as List?)?.whereType<String>().toList();
    if (tiers != null && tiers.isNotEmpty) {
      parts.add('tier IN (${List.filled(tiers.length, '?').join(',')})');
      args.addAll(tiers);
    }
    if (f['wordClassIsNull'] == true) {
      parts.add('word_class IS NULL');
    }
    final classes = (f['wordClass'] as List?)?.whereType<String>().toList();
    if (classes != null && classes.isNotEmpty) {

      parts.add(
          '(${List.filled(classes.length, "(word_class = ? OR (',' || COALESCE(pos_all,'') || ',') LIKE ?)").join(' OR ')})');
      for (final c in classes) {
        args
          ..add(c)
          ..add('%,$c,%');
      }
    }

    final domains = (f['domainsAny'] as List?)?.whereType<String>().toList();
    if (domains != null && domains.isNotEmpty) {
      parts.add(
          '(${List.filled(domains.length, "(',' || domains || ',') LIKE ?").join(' OR ')})');
      for (final d in domains) {
        args.add('%,$d,%');
      }
    }

    final topics = (f['topicsAny'] as List?)?.whereType<String>().toList();
    if (topics != null && topics.isNotEmpty) {
      parts.add(
          '(${List.filled(topics.length, "(',' || COALESCE(topics,'') || ',') LIKE ?").join(' OR ')})');
      for (final t in topics) {
        args.add('%,$t,%');
      }
    }
    final origins = (f['originAny'] as List?)?.whereType<String>().toList();
    if (origins != null && origins.isNotEmpty) {
      parts.add(
          '(${List.filled(origins.length, 'origin LIKE ?').join(' OR ')})');
      for (final o in origins) {
        args.add('%$o%');
      }
    }

    final pk = (f['properKind'] as List?)?.whereType<String>().toList();
    if (pk != null && pk.isNotEmpty) {
      parts.add('proper_kind IN (${List.filled(pk.length, '?').join(',')})');
      args.addAll(pk);
    }

    if (f['properAny'] == true) {
      parts.add("(tier = 'proper' OR proper_kind IS NOT NULL)");
    }

    final pt = (f['phraseTier'] as List?)?.whereType<String>().toList();
    if (pt != null && pt.isNotEmpty) {
      parts.add('phrase_tier IN (${List.filled(pt.length, '?').join(',')})');
      args.addAll(pt);
    }
    final phk = (f['phraseKind'] as List?)?.whereType<String>().toList();
    if (phk != null && phk.isNotEmpty) {
      parts.add('phrase_kind IN (${List.filled(phk.length, '?').join(',')})');
      args.addAll(phk);
    }

    if (f['noFreq'] == true) {
      parts.add('no_freq = 1');
    } else if (f['noFreq'] == false) {
      parts.add('no_freq = 0');
    }

    final affix = (f['affixAny'] as List?)?.whereType<String>().toList();
    if (affix != null && affix.isNotEmpty) {
      parts.add('affix_type IN (${List.filled(affix.length, '?').join(',')})');
      args.addAll(affix);
    }
    final gfunc = (f['grammarFunc'] as String?)?.trim();
    if (gfunc != null && gfunc.isNotEmpty) {
      parts.add('grammar_function = ?');
      args.add(gfunc);
    }

    final dmin = (f['derivMin'] as List?)?.whereType<num>().toList();
    if (dmin != null && dmin.isNotEmpty) {
      parts.add('root_count IS NOT NULL AND root_count >= ?');
      args.add(dmin.reduce((a, b) => a < b ? a : b));
    }
    return parts.isEmpty ? ('1=1', const []) : (parts.join(' AND '), args);
  }

  static const kSortModes = {'rank', 'rankDesc', 'alpha', 'alphaDesc'};

  static String orderByClause(String sort) => switch (sort) {

        'alpha' => 'word COLLATE NOCASE ASC, (rank IS NULL), rank ASC',
        'alphaDesc' => 'word COLLATE NOCASE DESC, (rank IS NULL), rank ASC',
        'rankDesc' => '(rank IS NULL), rank DESC, word ASC',
        _ => '(rank IS NULL), rank ASC, word ASC',
      };

  static String _escLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static String fold(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll(RegExp(r'^[^0-9a-z]+'), '')
      .replaceAll(RegExp(r'[^0-9a-z]+$'), '');

  static List<String> tokens(String sentence) => sentence
      .split(RegExp(r'\s+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static final RegExp _wordRun =
      RegExp(r'[A-Za-z0-9\u00e9\u00ea\u00c9\u00ca\-]+');

  static List<({String text, bool isWord})> segments(String text) {
    final out = <({String text, bool isWord})>[];
    var i = 0;
    for (final m in _wordRun.allMatches(text)) {
      if (m.start > i) {
        out.add((text: text.substring(i, m.start), isWord: false));
      }
      out.add((text: m.group(0)!, isWord: true));
      i = m.end;
    }
    if (i < text.length) out.add((text: text.substring(i), isWord: false));
    return out;
  }

  static const _editableFields = {
    'zh', 'examples', 'mnemonic', 'derivations', 'mnemonic_images',

    'quiz_zh',
  };

  static const Map<String, String> kMergedCards = {

    'ku': 'aku',
    'mu': 'kamu',
    'nya': 'dia',

    'pasaгan': 'pasaran',
    'pengᥙndian': 'pengundian',

    'ibu-bapak': 'ibu bapak',
    'buku-toko': 'toko buku',

    'hiruk pikuk': 'hiruk-pikuk',
    'kacau balau': 'kacau-balau',
    'ciak-ciap': 'ciak ciap',

    'adek': 'adik',
    'aih': 'ai',
    'aji-ajian': 'aji-aji',
    'aksesoris': 'aksesori',
    'akte': 'akta',
    'aktifitas': 'aktivitas',
    'akupuntur': 'akupunktur',
    'almari': 'lemari',
    'alumunium': 'aluminium',
    'analisa': 'analisis',
    'anduk': 'handuk',
    'antri': 'antre',
    'anugrah': 'anugerah',
    'apotik': 'apotek',
    'artifak': 'artefak',
    'asem': 'asam',
    'asik': 'asyik',
    'atheis': 'ateis',
    'atlit': 'atlet',
    'atmosfir': 'atmosfer',
    'bahu membahu': 'bahu-membahu',
    'banker': 'bunker',
    'baris berbaris': 'baris-berbaris',
    'baterei': 'baterai',
    'bazaar': 'bazar',
    'begadang': 'bergadang',
    'bemper': 'bumper',
    'bernegoisasi': 'bernegosiasi',
    'betonisasi': 'pembetonan',
    'bihari': 'bahari',
    'bilyar': 'biliar',
    'birahi': 'berahi',
    'bolpen': 'bolpoin',
    'brandal': 'berandal',
    'brangkas': 'brankas',
    'brengsek': 'berengsek',
    'brewok': 'berewok',
    'budha': 'buddha',
    'celcius': 'celsius',
    'cemilan': 'camilan',
    'centimeter': 'sentimeter',
    'cicak': 'cecak',
    'coklat': 'cokelat',
    'detil': 'detail',
    'diagnosa': 'diagnosis',
    'disain': 'desain',
    'dollar': 'dolar',
    'dos': 'dus',
    'ekstrim': 'ekstrem',
    'elit': 'elite',
    'essay': 'esai',
    'faham': 'paham',
    'feminim': 'feminin',
    'fikir': 'pikir',
    'filem': 'film',
    'form': 'formulir',
    'frase': 'frasa',
    'frustasi': 'frustrasi',
    'gementar': 'gemetar',
    'gemericik': 'gemercik',
    'genteng': 'genting',
    'ghaib': 'gaib',
    'gimana': 'bagaimana',
    'gini': 'begini',
    'gitu': 'begitu',
    'glamour': 'glamor',
    'goa': 'gua',
    'grafitasi': 'gravitasi',
    'handal': 'andal',
    'hapal': 'hafal',
    'harafiah': 'harfiah',
    'hektar': 'hektare',
    'helmet': 'helm',
    'hipotesa': 'hipotesis',
    'hipotik': 'hipotek',
    'hisap': 'isap',
    'horisontal': 'horizontal',
    'hutang': 'utang',
    'ijin': 'izin',
    'ilmuan': 'ilmuwan',
    'import': 'impor',
    'indera': 'indra',
    'infantri': 'infanteri',
    'influensa': 'influenza',
    'inggeris': 'inggris',
    'isha': 'isya',
    'isteri': 'istri',
    'jadual': 'jadwal',
    'jagad': 'jagat',
    'jamrud': 'zamrud',
    'jenasah': 'jenazah',
    'jendral': 'jenderal',
    'jengkerik': 'jangkrik',
    'jenius': 'genius',
    'jipsi': 'gipsi',
    'jogi': 'yogi',
    'kadaluarsa': 'kedaluwarsa',
    'kadaluwarsa': 'kedaluwarsa',
    'kahwin': 'kawin',
    'kameramen': 'kamerawan',
    'kampak': 'kapak',
    'kangguru': 'kanguru',
    'kangker': 'kanker',
    'karir': 'karier',
    'katholik': 'katolik',
    'kawatir': 'khawatir',
    'kecapean': 'kecapaian',
    'kecoa': 'kecoak',
    'keduluan': 'kedahuluan',
    'keefektivitasan': 'efektivitas',
    'kefakuman': 'kevakuman',
    'kefleksibilitasan': 'fleksibilitas',
    'kemaren': 'kemarin',
    'kempes': 'kempis',
    'kenampakan': 'ketampakan',
    'kendor': 'kendur',
    'ketapel': 'katapel',
    'khabar': 'kabar',
    'kharisma': 'karisma',
    'kin': 'ken',
    'klab': 'klub',
    'klas': 'kelas',
    'koboy': 'koboi',
    'kokain': 'kokaina',
    'komersil': 'komersial',
    'komoditi': 'komoditas',
    'komplek': 'kompleks',
    'konggres': 'kongres',
    'konkrit': 'konkret',
    'kopor': 'koper',
    'kran': 'keran',
    'kreatifitas': 'kreativitas',
    'ksatria': 'kesatria',
    'kuatir': 'khawatir',
    'kwantitas': 'kuantitas',
    'kwitansi': 'kuitansi',
    'labah-labah': 'laba-laba',
    'lagipula': 'lagi pula',
    'lansekap': 'lanskap',
    'leukimia': 'leukemia',
    'lobang': 'lubang',
    'lotere': 'lotre',
    'mabok': 'mabuk',
    'magik': 'magis',
    'mahluk': 'makhluk',
    'majlis': 'majelis',
    'mall': 'mal',
    'managemen': 'manajemen',
    'manager': 'manajer',
    'mantab': 'mantap',
    'mantera': 'mantra',
    'marathon': 'maraton',
    'masal': 'massal',
    'mekah': 'makkah',
    'mekkah': 'makkah',
    'memeratakan': 'memperatakan',
    'memeroleh': 'memperoleh',
    'meminimalisir': 'meminimalkan',
    'mempacari': 'memacari',
    'mempacu': 'memacu',
    'mempadamkan': 'memadamkan',
    'mempadati': 'memadati',
    'mempadatkan': 'memadatkan',
    'mempagari': 'memagari',
    'mempahami': 'memahami',
    'mempahamkan': 'memahamkan',
    'mempailitkan': 'memailitkan',
    'mempajaki': 'memajaki',
    'mempaket': 'memaket',
    'mempaketkan': 'memaketkan',
    'mempaksa': 'memaksa',
    'mempaku': 'memaku',
    'mempalang': 'memalang',
    'mempalingkan': 'memalingkan',
    'mempalsukan': 'memalsukan',
    'mempamerkan': 'memamerkan',
    'mempamitkan': 'memamitkan',
    'mempanaskan': 'memanaskan',
    'mempangkas': 'memangkas',
    'mempantau': 'memantau',
    'memparodikan': 'memarodikan',
    'mempastikan': 'memastikan',
    'mempatuhi': 'mematuhi',
    'memperkarai': 'memerkarai',
    'memperkarakan': 'memerkarakan',
    'mempolisikan': 'memolisikan',
    'mempopulerkan': 'memopulerkan',
    'memposting': 'memosting',
    'mendului': 'mendahului',
    'mengada-ngada': 'mengada-ada',
    'menganalisa': 'menganalisis',
    'mengeliminir': 'mengeliminasi',
    'mengkafani': 'mengafani',
    'mengkampanyekan': 'mengampanyekan',
    'mengkategorikan': 'mengategorikan',
    'mengklaim': 'mengeklaim',
    'mengkocok': 'mengocok',
    'mengkodekan': 'mengodekan',
    'mengkombinasikan': 'mengombinasikan',
    'mengkomunikasikan': 'mengomunikasikan',
    'mengkondisikan': 'mengondisikan',
    'mengkonsultasikan': 'mengonsultasikan',
    'mengkontribusi': 'mengontribusi',
    'mengkotak-kotakkan': 'mengotak-ngotakkan',
    'menraktir': 'mentraktir',
    'menraktor': 'mentraktor',
    'menransaksikan': 'mentransaksikan',
    'menransfer': 'mentransfer',
    'menransformasi': 'mentransformasi',
    'menransformasikan': 'mentransformasikan',
    'menransmisikan': 'mentransmisikan',
    'menransplantasikan': 'mentransplantasikan',
    'mensadap': 'menyadap',
    'mensadari': 'menyadari',
    'mensahkan': 'mengesahkan',
    'mensearahkan': 'menyearahkan',
    'mensejahterakan': 'menyejahterakan',
    'menservis': 'menyervis',
    'mensia-siakan': 'menyia-nyiakan',
    'mensiasati': 'menyiasati',
    'mensikapi': 'menyikapi',
    'mensinergikan': 'menyinergikan',
    'mensinkronkan': 'menyinkronkan',
    'mensomasi': 'menyomasi',
    'mensosialisasikan': 'menyosialisasikan',
    'mensubsidi': 'menyubsidi',
    'mensugesti': 'menyugesti',
    'mensukseskan': 'menyukseskan',
    'mentakdirkan': 'menakdirkan',
    'mentri': 'menteri',
    'menunjukan': 'menunjukkan',
    'menyetok': 'menstok',
    'merk': 'merek',
    'merubah': 'mengubah',
    'mesjid': 'masjid',
    'metafisik': 'metafisika',
    'mie': 'mi',
    'milioner': 'miliuner',
    'milyar': 'miliar',
    'mirai': 'tirai',
    'moderen': 'modern',
    'mong': 'mung',
    'motto': 'moto',
    'muasal': 'asal',
    'mujizat': 'mukjizat',
    'muk': 'mok',
    'musium': 'museum',
    'nafas': 'napas',
    'nahkoda': 'nakhoda',
    'nampak': 'tampak',
    'nanda': 'ananda',
    'napsu': 'nafsu',
    'narkotik': 'narkotika',
    'nasehat': 'nasihat',
    'negoisasi': 'negosiasi',
    'negri': 'negeri',
    'nekad': 'nekat',
    'nomer': 'nomor',
    'nopember': 'november',
    'nyah': 'enyah',
    'obyek': 'objek',
    'obyektif': 'objektif',
    'on': 'ons',
    'onta': 'unta',
    'original': 'orisinal',
    'orisinil': 'orisinal',
    'otentik': 'autentik',
    'otobiografi': 'autobiografi',
    'otopsi': 'autopsi',
    'pake': 'pakai',
    'palm': 'palem',
    'paro': 'paruh',
    'pebruari': 'februari',
    'pembom': 'pengebom',
    'pemboman': 'pengeboman',
    'pendulu': 'pendahulu',
    'pengkondisian': 'pengondisian',
    'pengkoordinasian': 'pengoordinasian',
    'pengkudetaan': 'pengudetaan',
    'penglaris': 'pelaris',
    'perancis': 'prancis',
    'perangko': 'prangko',
    'perduli': 'peduli',
    'peribadi': 'pribadi',
    'personil': 'personel',
    'photo': 'foto',
    'pinalti': 'penalti',
    'pinguin': 'penguin',
    'piranti': 'peranti',
    'piyama': 'piama',
    'plat': 'pelat',
    'pondasi': 'fondasi',
    'popular': 'populer',
    'poto': 'foto',
    'praktek': 'praktik',
    'prilaku': 'perilaku',
    'propinsi': 'provinsi',
    'puteri': 'putri',
    'rahsia': 'rahasia',
    'rame': 'ramai',
    'rapih': 'rapi',
    'realita': 'realitas',
    'rejeki': 'rezeki',
    'relawan': 'sukarelawan',
    'rena': 'rona',
    'resiko': 'risiko',
    'resleting': 'ritsleting',
    'respon': 'respons',
    'rincian': 'perincian',
    'rizki': 'rezeki',
    'ronsen': 'rontgen',
    'ruh': 'roh',
    'rumputan': 'rerumputan',
    'said': 'sayid',
    'saklar': 'sakelar',
    'samudera': 'samudra',
    'saos': 'saus',
    'segitu': 'sebegitu',
    'sekedar': 'sekadar',
    'sekering': 'sekring',
    'sekertaris': 'sekretaris',
    'seksama': 'saksama',
    'selular': 'seluler',
    'semakin': 'makin',
    'semberono': 'sembrono',
    'sensitifitas': 'sensitivitas',
    'sentiasa': 'senantiasa',
    'sentimentil': 'sentimental',
    'seprei': 'seprai',
    'seringkali': 'sering kali',
    'sesembahan': 'sembahan',
    'shalat': 'salat',
    'sholat': 'salat',
    'silahkan': 'silakan',
    'simbolik': 'simbolis',
    'sipilis': 'sifilis',
    'sistim': 'sistem',
    'sorga': 'surga',
    'souvenir': 'suvenir',
    'staff': 'staf',
    'standard': 'standar',
    'standart': 'standar',
    'stress': 'stres',
    'subyek': 'subjek',
    'subyektif': 'subjektif',
    'suk': 'syok',
    'supir': 'sopir',
    'survey': 'survei',
    'sutera': 'sutra',
    'switer': 'sweter',
    'syaitan': 'setan',
    'syaraf': 'saraf',
    'syurga': 'surga',
    'tahta': 'takhta',
    'taufan': 'topan',
    'tehnik': 'teknik',
    'teka': 'terka',
    'telfon': 'telepon',
    'telpon': 'telepon',
    'tendo': 'tendon',
    'tentera': 'tentara',
    'tentram': 'tenteram',
    'terberkahi': 'teberkahi',
    'tereliminir': 'tereliminasi',
    'terlanjur': 'telanjur',
    'terlantar': 'telantar',
    'terompet': 'trompet',
    'tips': 'tip',
    'tipus': 'tifus',
    'toples': 'stoples',
    'trend': 'tren',
    'trilyun': 'triliun',
    'tropi': 'trofi',
    'ubat': 'obat',
    'ujan': 'hujan',
    'urin': 'urine',
    'vidio': 'video',
    'yunior': 'junior',
    'zone': 'zona',

    'sanya': 'bahwasanya',
    'yoghurt': 'yogurt',
    'omset': 'omzet',
    'lalim': 'zalim',
    'menghimbau': 'mengimbau',
    'barangan': 'berangan',
    'hirarki': 'hierarki',
    'legalisir': 'legalisasi',

    'berfikir': 'berpikir',
    'berterbangan': 'beterbangan',
    'ketrampilan': 'keterampilan',
    'memerhatikan': 'memperhatikan',
    'mencontek': 'menyontek',
    'mentaati': 'menaati',
    'menterjemahkan': 'menerjemahkan',
    'projek': 'proyek',
    'tandatangan': 'tanda tangan',
    'lohor': 'zuhur',
    'losin': 'lusin',
    'mengkarantina': 'mengarantina',
    'mengkerut': 'mengerut',
    'mengkompensasi': 'mengompensasi',
    'mengkonsolidasikan': 'mengonsolidasikan',
    'mensabotase': 'menyabotase',
    'mensucikan': 'menyucikan',
    'mentato': 'menato',
    'mentoleransi': 'menoleransi',
    'pekuburan': 'perkuburan',
    'tauge': 'taoge',
    'terpedaya': 'teperdaya',
    'terperdaya': 'teperdaya',

    'beritahu': 'beri tahu',
    'walikota': 'wali kota',
    'kerjasama': 'kerja sama',
    'ibukota': 'ibu kota',
    'bertanggungjawab': 'bertanggung jawab',
    'sepakbola': 'sepak bola',
    'batubara': 'batu bara',
    'tanggungjawab': 'tanggung jawab',
    'budidaya': 'budi daya',
    'marabahaya': 'mara bahaya',
    'andaikata': 'andai kata',
    'sumberdaya': 'sumber daya',
    'ada kalanya': 'adakalanya',
    'apa bila': 'apabila',
    'belase': 'sumpit',
    'berkerjasama': 'bekerja sama',
    'bumi putra': 'bumiputra',
    'daun bawang': 'bawang daun',
    'deria': 'indra',
    'dolat': 'daulat',
    'duka cita': 'dukacita',
    'fan fiksi': 'fiksi fan',
    'frasa nomina': 'frasa nominal',
    'frasa numeralia': 'frasa numeral',
    'frasa preposisi': 'frasa preposisional',
    'gula alkohol': 'alkohol gula',
    'herpes labialis': 'herpes mulut',
    'herpes oral': 'herpes mulut',
    'ikan lumba-lumba': 'lumba-lumba',
    'ikan paus': 'paus',
    'imang': 'timang',
    'kerak telor': 'kerak telur',
    'kue mangkok': 'kue mangkuk',
    'kue tart': 'kue tar',
    'limonade': 'limun',
    'mana kala': 'manakala',
    'mata hari': 'matahari',
    'mim': 'meme',
    'palu godam': 'godam',
    'pameran dirgantara': 'pameran udara',
    'papan ketik': 'papan tik',
    'paus beluga': 'beluga',
    'perwatin': 'batin',
    'roti cane': 'roti canai',
    'salah ketik': 'salah tik',
    'segi tiga': 'segitiga',
    'surung': 'sorong',
    'syagar': 'sakar',
    'syakar': 'sakar',
    'tolak ukur': 'tolok ukur',
    'tuas transmisi': 'tuas persneling',
    'wedam': 'weda',
  };

  static const Set<String> kRetiredCards = {
    'kan', 'me', 'in', 'is', 'se', 'an', 'wan', 'peng', 'ber', 'meng', 'pen', 'mem',
    'wati', 'isasi', 'isme',
  };

  static const String enrolledSql =
      '(pl.card_id IS NOT NULL OR s.card_id IS NOT NULL)';

  static DateTime dayStartOf([DateTime? at]) {
    final t = at ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  static int dayStartMs([DateTime? at]) =>
      dayStartOf(at).millisecondsSinceEpoch;

  static int dayEndMs([DateTime? at]) =>
      dayStartOf(at).add(const Duration(days: 1)).millisecondsSinceEpoch;

  static String checkinKey(DateTime day) => 'checkin:${_dayKey(day)}';

  static const String inMemorySql = 'w.enabled = 1 AND $enrolledSql';

  static const String listVisibleSql =
      "(tier NOT IN ('derived', 'redup', 'lookup') OR enabled = 1)";

  static String _bandCols([String gate = '']) {
    final g = gate.isEmpty ? '' : '$gate AND ';
    final names = ['b_mastered', 'b_familiar', 'b_fair', 'b_weak', 'b_new'];
    return [
      for (var i = 0; i < names.length; i++)
        'SUM(CASE WHEN $g${_kBandExprs[i]} THEN 1 ELSE 0 END) AS ${names[i]}'
    ].join(', ');
  }

  static const List<String> _kBandExprs = [
    'COALESCE(s.reps,0) > 0 AND s.stability >= 180',
    'COALESCE(s.reps,0) > 0 AND s.stability >= 60 AND s.stability < 180',
    'COALESCE(s.reps,0) > 0 AND s.stability >= 7 AND s.stability < 60',

    'COALESCE(s.reps,0) > 0 AND COALESCE(s.stability,0) < 7',

    'COALESCE(s.reps,0) = 0',
  ];

  static MemoryBands _bandsOf(Map<String, Object?> r) => (
        mastered: (r['b_mastered'] as int?) ?? 0,
        familiar: (r['b_familiar'] as int?) ?? 0,
        fair: (r['b_fair'] as int?) ?? 0,
        weak: (r['b_weak'] as int?) ?? 0,
        newSel: (r['b_new'] as int?) ?? 0,
      );

  static String _bandWhere(int band) =>
      _kBandExprs[band.clamp(0, _kBandExprs.length - 1)];

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _asDay(String? s) {
    if (s == null || s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  static int _intervalBin(int gap) {
    if (gap < 1) return -1;
    if (gap <= 3) return gap - 1;
    if (gap <= 7) return 3;
    if (gap <= 14) return 4;
    if (gap <= 30) return 5;
    if (gap <= 90) return 6;
    return 7;
  }
}

class GrammarProgressRow {
  const GrammarProgressRow({
    required this.cardId,
    this.seenAt,
    this.starred = false,
    this.drillOk = 0,
    this.drillTotal = 0,
  });

  final String cardId;
  final int? seenAt;
  final bool starred;
  final int drillOk;
  final int drillTotal;

  bool get seen => seenAt != null;

  GrammarProgressRow copyWith(
          {int? seenAt, bool? starred, int? drillOk, int? drillTotal}) =>
      GrammarProgressRow(
        cardId: cardId,
        seenAt: seenAt ?? this.seenAt,
        starred: starred ?? this.starred,
        drillOk: drillOk ?? this.drillOk,
        drillTotal: drillTotal ?? this.drillTotal,
      );

  Map<String, Object?> toRow() => {
        'card_id': cardId,
        'seen_at': seenAt,
        'starred': starred ? 1 : 0,
        'drill_ok': drillOk,
        'drill_total': drillTotal,
      };

  factory GrammarProgressRow.fromRow(Map<String, Object?> r) =>
      GrammarProgressRow(
        cardId: r['card_id'] as String,
        seenAt: (r['seen_at'] as num?)?.toInt(),
        starred: ((r['starred'] as num?)?.toInt() ?? 0) != 0,
        drillOk: (r['drill_ok'] as num?)?.toInt() ?? 0,
        drillTotal: (r['drill_total'] as num?)?.toInt() ?? 0,
      );
}

class _GramPending {
  int? seenAt;
  bool? starred;
  int okAdd = 0;
  int totalAdd = 0;
}

int? _maxInt2(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a > b ? a : b;
}
