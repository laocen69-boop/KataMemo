library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'db.dart';
import 'models.dart';
import 'perf_log.dart';
import 'platform/io_shim.dart'
    show loadWebGzipTextAsset, seedWebDatabaseFromAsset;
import 'version.dart' show kKbbiLocal, kNoKbbiBuild;

const int kDataVersionEffective =
    kNoKbbiBuild ? kDataVersion + 500000 : kDataVersion;

class DataRepo {
  final AppDb db;
  DataRepo(this.db);

  bool _imported = false;
  List<BookNode>? _books;

  final ValueNotifier<double?> importProgress = ValueNotifier<double?>(null);

  bool importIsUpdate = false;

  Future<List<BookNode>> loadBooks() async {
    if (_books != null) return _books!;
    final raw = await rootBundle.loadString('assets/data/books.json');
    final list =
        (jsonDecode(raw) as Map<String, dynamic>)['books'] as List<dynamic>;
    _books = [
      for (final item in list) BookNode.fromJson(item as Map<String, dynamic>),
    ];
    return _books!;
  }

  Future<void> ensureImported() async {
    if (_imported) return;
    final installed = await db.dataVersion();
    if (installed == kDataVersionEffective && await db.wordCount() > 0) {
      if (kIsWeb) {
        final probe = await db.getWord('sudah');
        if (probe != null && probe.examples.isNotEmpty) {
          _imported = true;
          return;
        }
      } else {
        _imported = true;
        return;
      }
    }
    if (await db.wordCount() > 0) {
      importIsUpdate = true;
      await db.clearWords();
    } else if (kIsWeb) {
      await db.close();
      final seeded = await seedWebDatabaseFromAsset(
        'assets/data/web_seed.db.gz',
        cacheBust: '$kDataVersionEffective',
        onProgress: (v) => importProgress.value = v,
      );
      if (seeded &&
          await db.dataVersion() == kDataVersionEffective &&
          await db.wordCount() > 0) {
        _imported = true;
        return;
      }
    }
    final sw = Stopwatch()..start();
    final raw = (kIsWeb
            ? await loadWebGzipTextAsset(
                'assets/data/words.json.gz',
                cacheBust: '$kDataVersionEffective',
              )
            : null) ??
        await rootBundle.loadString('assets/data/words.json');
    final list = jsonDecode(raw) as List<dynamic>;
    perfLog('import.parse', sw, 'bytes=${raw.length}');
    final batch = <Map<String, Object?>>[];
    var done = 0;
    importProgress.value = 0;
    const batchSize = kIsWeb ? 2000 : 500;
    for (final item in list) {
      batch.add(_toRow(item));
      if (batch.length >= batchSize) {
        await db.upsertWords(batch);
        done += batch.length;
        batch.clear();

        importProgress.value = 0.95 * done / list.length;
        if (kIsWeb) await Future<void>.delayed(Duration.zero);
      }
    }
    if (batch.isNotEmpty) await db.upsertWords(batch);
    importProgress.value = 0.95;
    perfLog('import.words', sw, 'n=${list.length}');

    final restored = await db.applyUserEdits();
    if (restored > 0) {
      // ignore: avoid_print
      print('已恢复 $restored 处用户修改');
    }

    await db.replayPlannedDerived();

    final moved = await db.remapMergedCards();
    if (moved > 0) {
      // ignore: avoid_print
      print('已迁移 $moved 条并入卡的复习进度');
    }

    final purged = await db.purgeRetiredCards();
    if (purged > 0) {
      // ignore: avoid_print
      print('已清除 $purged 行词缀卡（仅查词）的学习进度');
    }
    await db.setDataVersion(kDataVersionEffective);
    perfLog('import.total', sw);
    importProgress.value = 1;
    _imported = true;
  }

  Map<String, Object?> _toRow(dynamic item) {
    final m = item as Map<String, dynamic>;

    final folded = (m['id'] as String?) ?? (m['w'] as String);

    final senses = <Map<String, Object?>>[
      if (kKbbiLocal)
      for (final s in (m['s'] as List?) ?? const [])
        {
          'def': (s as Map<String, dynamic>)['d'] as String? ?? '',

          'pos': s['p'] as String?,
        },
    ];
    final examples = <Map<String, Object?>>[
      for (final e in (m['ex'] as List?) ?? const [])
        {
          'i': (e as Map<String, dynamic>)['i'] as String? ?? '',
          'z': e['z'] as String?,

          's': e['s'] as String?,
          'q': e['q'] as String?,
        },
    ];
    final derivations = <Map<String, Object?>>[
      for (final d in (m['dv'] as List?) ?? const [])
        {
          'f': (d as Map<String, dynamic>)['f'] as String? ?? '',
          'p': d['p'] as String?,
          'g': d['g'] as String?,

          'd': kKbbiLocal ? d['d'] as String? : null,
        },
    ];

    final gabungan = <String>[
      if (kKbbiLocal)
      for (final g in (m['gk'] as List?) ?? const []) g.toString(),
    ];

    final affixes = <Map<String, Object?>>[];
    final ax = m['ax'];
    if (ax is Map<String, dynamic>) {
      for (final a in (ax['a'] as List?) ?? const []) {
        final am = a as Map<String, dynamic>;
        affixes.add({
          'type': am['t'] as String? ?? '',
          'morph': am['m'] as String? ?? '',
          'name': am['n'] as String? ?? '',
          'meaning': am['g'] as String? ?? '',
        });
      }
    }

    final au = m['au'];
    String? audioA, audioG, audioH;
    if (au is Map<String, dynamic>) {
      audioA = au['a'] as String?;
      audioG = au['g'] as String?;
      audioH = au['h'] as String?;
    }

    final audioParts = <String>[
      for (final p in (m['ap'] as List?) ?? const []) p.toString(),
    ];

    return {
      'id': folded,
      'word': m['w'] as String,
      'tier': m['t'] as String? ?? 'core',
      'rank': m['r'] as int?,
      'frequency': m['f'] as int? ?? 0,
      'phonetic': m['ph'] as String?,
      'word_class': m['c'] as String?,

      'full_name': m['fl'] as String?,

      'affix_type': m['af'] as String?,

      'pos_all': m['pa'] as String?,

      'proper_kind': m['pk'] as String?,

      'no_freq': (m['nf'] as num?)?.toInt() == 1 ? 1 : 0,
      'domains': m['d'] is List ? (m['d'] as List).join(',') : null,
      'topics': m['tp'] is List ? (m['tp'] as List).join(',') : null,
      'origin': m['o'] as String?,

      'root_count': (m['rc'] as num?)?.toInt(),
      'base_word': m['b'] as String?,
      'non_standard': m['n'] as String?,
      'variants': m['v'] is List ? (m['v'] as List).join(',') : null,
      'non_standard_forms':
          m['ns'] is List ? (m['ns'] as List).join(',') : null,

      'clitics': m['cl'] is List
          ? WordCard.encodeMaps([
              for (final c in m['cl'] as List)
                Clitic.fromMap((c as Map).cast<String, Object?>()).toMap(),
            ])
          : null,
      'senses': WordCard.encodeMaps(senses),
      'examples': WordCard.encodeMaps(examples),
      'derivations': WordCard.encodeMaps(derivations),

      'gabungan': gabungan.isEmpty ? null : jsonEncode(gabungan),

      'phrase_tier': m['pt'] as String?,

      'phrase_kind': m['phk'] as String?,

      'zh_pos': m['zp'] as String?,
      'zh': m['zh'] as String?,
      'affix_base': ax is Map<String, dynamic> ? ax['b'] as String? : null,
      'affixes': WordCard.encodeMaps(affixes),

      'grammar_function': m['gf'] as String?,

      'grammar_notes': GrammarNote.encodeList(m['gn']),
      'audio_ardi': audioA,
      'audio_gadis': audioG,
      'audio_human': audioH,

      'audio_parts': audioParts.isEmpty ? null : jsonEncode(audioParts),

      'mnemonic_default': m['mn'] as String?,

      'quiz_zh': m['qz'] as String?,

      'enabled': (m['en'] as int?) ?? 1,
      'favorite': 0,
    };
  }
}
