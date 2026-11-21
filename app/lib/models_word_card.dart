part of 'models.dart';

class UserBlock {
  final String type;
  final List<String> lines;
  final String? text;
  const UserBlock({required this.type, this.lines = const [], this.text});

  factory UserBlock.fromMap(Map<String, Object?> m) => UserBlock(
        type: (m['t'] as String?) ?? 'text',
        lines: [
          if (m['lines'] is List)
            for (final x in (m['lines'] as List))
              if (x is String) x
        ],
        text: m['c'] as String?,
      );

  Map<String, Object?> toMap() => {
        't': type,
        if (lines.isNotEmpty) 'lines': lines,
        if (text != null && text!.isNotEmpty) 'c': text,
      };

  String get label => switch (type) {
        'derivation' => '派生词形',
        'synonym' => '近义词',
        'antonym' => '反义词',
        _ => '笔记',
      };
}

class WordCard {
  final String id;
  final String word;
  final String tier;
  final int? rank;
  final int frequency;
  final String? phonetic;
  final String? wordClass;
  final List<String> domains;

  final List<String> topics;
  final String? origin;
  final String? baseWord;
  final String? nonStandard;
  final List<String> variants;

  final List<String> nonStandardForms;

  final List<Clitic> clitics;
  final List<WordSense> senses;
  final List<WordExample> examples;
  final List<Derivation> derivations;

  final List<String> gabunganKata;

  final String? zhPos;
  final String? zh;
  final String? affixBase;
  final List<AffixPart> affixes;
  final String? audioArdi;

  final String? audioGadis;

  final String? audioHuman;

  final List<String> audioParts;
  final String? mnemonic;

  final String? mnemonicDefault;

  final String? quizZh;

  String? get mnemonicShown => hasOwnMnemonic ? mnemonic : mnemonicDefault;

  bool get hasOwnMnemonic => mnemonic != null && mnemonic!.isNotEmpty;

  bool get showsDefaultMnemonic => !hasOwnMnemonic && mnemonicDefault != null;

  bool get isProperNoun => tier == 'proper' || properKind != null;

  String get mnemonicDefaultKind {
    if (isProperNoun) return '专名科普';
    if (tier == 'phrase') return '详细释义';
    if (mnemonicDefault?.contains('（维基：') == true) return '百科';
    return '用法提示';
  }

  final List<String> mnemonicImages;

  final String? grammarFunction;

  final List<GrammarNote> grammarNotes;

  final String? fullName;

  final String? affixType;

  final String? posAll;

  final String? properKind;

  final String? phraseKind;

  bool enabled;
  bool favorite;

  final bool userWord;

  final List<UserBlock> userBlocks;

  final String? cardOrder;

  WordCard({
    required this.id,
    required this.word,
    this.tier = 'core',
    this.rank,
    this.frequency = 0,
    this.phonetic,
    this.wordClass,
    this.domains = const [],
    this.topics = const [],
    this.origin,
    this.baseWord,
    this.nonStandard,
    this.variants = const [],
    this.nonStandardForms = const [],
    this.clitics = const [],
    this.senses = const [],
    this.examples = const [],
    this.derivations = const [],
    this.gabunganKata = const [],
    this.zhPos,
    this.zh,
    this.affixBase,
    this.affixes = const [],
    this.grammarFunction,
    this.grammarNotes = const [],
    this.fullName,
    this.affixType,
    this.posAll,
    this.properKind,
    this.phraseKind,
    this.audioArdi,
    this.audioGadis,
    this.audioHuman,
    this.audioParts = const [],
    this.mnemonic,

    this.mnemonicDefault,
    this.quizZh,
    this.mnemonicImages = const [],
    this.enabled = true,
    this.favorite = false,
    this.userWord = false,
    this.userBlocks = const [],
    this.cardOrder,
  });

  String get tierLabel => switch (tier) {
        't1' => '最高频',
        't2' => '高频',
        't3' => '中高频',
        't4' => '中频',
        't5' => '常用',
        't6' => '较少用',
        't7' => '低频',

        'core' => '高频',
        'common' => '常用',
        'advanced' => '低频',

        'derived' => '派生词',
        'phrase' => '短语',
        'proper' => '专有名词',
        'abbrev' => '缩写',
        'redup' => '重叠式',
        'lookup' => '仅查词',
        _ => tier,
      };

  bool get isNonStandardVariantCard =>
      tier == 'lookup' && (zh ?? '').contains('非标准写法；标准写法：');

  bool get isFreqBand =>
      const {'t1', 't2', 't3', 't4', 't5', 't6', 't7'}.contains(tier);

  String? get grammarFunctionLabel => switch (grammarFunction) {
        'prep' => '介词',
        'conj' => '连词',
        'adv' => '副词',
        'particle' => '语气词',
        'article' => '冠词',
        'quantifier' => '量词',
        _ => null,
      };

  String get wordClassLabel => switch (wordClass) {
        'n' => '名词',
        'v' => '动词',
        'a' => '形容词',
        'adv' => '副词',
        'num' => '数词',
        'pron' => '代词',
        'prep' => '介词',
        'conj' => '连词',
        'interj' => '感叹词',
        'part' => '助词',
        'prakat' => '词根',
        _ => wordClass ?? '',
      };

  static String _posCodeLabel(String code) => switch (code) {
        'n' => '名词',
        'v' => '动词',
        'a' => '形容词',
        'adv' => '副词',
        'num' => '数词',
        'pron' => '代词',
        'prep' => '介词',
        'conj' => '连词',
        'interj' => '感叹词',
        'part' => '助词',
        _ => code,
      };

  List<String> get wordClassLabels {
    final codes = (posAll ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (codes.isEmpty) {
      final l = wordClassLabel;
      return l.isEmpty ? const [] : [l];
    }
    return [for (final c in codes) _posCodeLabel(c)];
  }

  String get wordClassLabelsCombined {
    final xs = wordClassLabels;
    return xs.isEmpty ? '' : (xs.length == 1 ? xs.first : xs.join(' · '));
  }

  String? get posCodePrefix {
    final codes = (posAll ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (codes.isEmpty) return wordClass;
    return codes.join('/');
  }

  String? get zhClean {
    final z = zh?.trim();
    if (z == null || z.isEmpty) return null;
    return z;
  }

  List<String> get zhSegments => (zhClean ?? '')
      .split(RegExp(r'[；;]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  List<String>? get zhPosSegments {
    final z = zhPos?.trim();
    if (z == null || z.isEmpty) return null;
    final ps = z.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return ps.length == zhSegments.length ? ps : null;
  }

  String? get zhPosLabeled {
    final ps = zhPosSegments;
    if (ps == null) return null;
    final segs = zhSegments;
    return [for (var i = 0; i < segs.length; i++) '${ps[i]}. ${segs[i]}'].join('；');
  }

  String? get originLabel => switch (origin) {
        'Sanskerta' || 'Skt' => '梵语',
        'Arab' || 'Ar' => '阿拉伯语',
        'Belanda' || 'Bel' => '荷兰语',
        'Portugis' || 'Pr' => '葡萄牙语',
        'Cina' => '汉语',
        'Inggris' => '英语',
        'Jepang' || 'Jp' => '日语',
        'Jawa' => '爪哇语',
        'Jawa Kuno' => '爪哇古语',
        'Sunda' || 'Sd' => '巽他语',
        'Minangkabau' || 'Min' => '米南加保语',
        'Klasik' => '古典',
        'Persia' => '波斯语',
        _ => null,
      };

  String? get properKindLabel => switch (properKind) {
        'people' => '人名',
        'place' => '地名',
        'org' => '机构',
        'work' => '作品',
        'deity' => '宗教',
        'other' => '其他',
        _ => null,
      };

  String? get phraseKindLabel => switch (phraseKind) {
        'peribahasa' => '谚语俗语',
        'idiom' => '习语比喻',
        'func' => '语法与功能短语',
        'term' => '学科专业术语',
        'verbal' => '动词词组',
        'adj' => '形容词词组',
        'nominal' => '通用名词词组',
        _ => null,
      };

  String get affixBreakdown {
    if (affixBase == null || affixes.isEmpty) return word;
    final bs = StringBuffer();
    for (final a in affixes) {
      if (a.type == 'circumfix') {
        final parts = a.morph.split('…');
        if (parts.length == 2) {
          bs.write(parts[0].replaceAll('-', ''));
          bs.write(affixBase);
          bs.write(parts[1].replaceAll('-', ''));
        }
      } else if (a.type == 'prefix') {
        bs.write(a.morph.replaceAll('-', ''));
        bs.write(affixBase);
      } else if (a.type == 'suffix') {
        bs.write(affixBase);
        bs.write(a.morph.replaceAll('-', ''));
      } else if (a.type == 'infix') {

        final inf = a.morph.replaceAll('-', '');
        final base = affixBase!;
        if (base.isNotEmpty && inf.isNotEmpty) {
          bs.write(base[0]);
          bs.write(inf);
          bs.write(base.substring(1));
        } else {
          bs.write(base);
        }
      } else {
        bs.write(word);
      }
    }
    final s = bs.toString();
    if (s == word) return s;
    return id == s ? s : word;
  }

  String? get audio => audioArdi ?? audioGadis;

  Map<String, Object?> toMap() => {
        'id': id,
        'word': word,
        'tier': tier,
        'rank': rank,
        'frequency': frequency,
        'phonetic': phonetic,
        'word_class': wordClass,
        'pos_all': posAll,
        'proper_kind': properKind,
        'phrase_kind': phraseKind,
        'domains': domains.isEmpty ? null : domains.join(','),
        'topics': topics.isEmpty ? null : topics.join(','),
        'origin': origin,
        'base_word': baseWord,
        'non_standard': nonStandard,
        'variants': variants.isEmpty ? null : variants.join(','),
        'non_standard_forms':
            nonStandardForms.isEmpty ? null : nonStandardForms.join(','),
        'clitics': encodeMaps([for (final c in clitics) c.toMap()]),
        'senses': encodeMaps([for (final s in senses) s.toMap()]),
        'examples': encodeMaps([for (final e in examples) e.toMap()]),
        'derivations': encodeMaps([for (final d in derivations) d.toMap()]),

        'gabungan': gabunganKata.isEmpty ? null : jsonEncode(gabunganKata),
        'zh': zh,
        'affix_base': affixBase,
        'affixes': encodeMaps([for (final a in affixes) a.toMap()]),
        'grammar_function': grammarFunction,

        'grammar_notes': encodeMaps([for (final g in grammarNotes) g.toMap()]),
        'audio_ardi': audioArdi,
        'audio_gadis': audioGadis,
        'audio_human': audioHuman,
        'audio_parts': audioParts.isEmpty ? null : jsonEncode(audioParts),
        'mnemonic': mnemonic,
        'mnemonic_images':
            mnemonicImages.isEmpty ? null : mnemonicImages.join(','),

        'quiz_zh': quizZh,
        'enabled': enabled ? 1 : 0,
        'favorite': favorite ? 1 : 0,
        if (userBlocks.isNotEmpty)
          'user_blocks': jsonEncode([for (final b in userBlocks) b.toMap()]),
        if (cardOrder != null && cardOrder!.isNotEmpty) 'card_order': cardOrder,
      };

  static String? encodeMaps(List<Map<String, Object?>> list) {
    final kept = [
      for (final m in list)
        if (m.values.any((v) => v != null && '$v'.isNotEmpty)) m
    ];
    if (kept.isEmpty) return null;
    return kept
        .map((m) => m.entries
            .where((e) => e.value != null && '${e.value}'.isNotEmpty)
            .map((e) => '${e.key}=${e.value}')
            .join('\u0002'))
        .join('\u0001');
  }

  factory WordCard.fromDb(Map<String, Object?> m) => WordCard(
        id: m['id'] as String,
        word: m['word'] as String,
        tier: m['tier'] as String? ?? 'core',
        rank: m['rank'] as int?,
        frequency: m['frequency'] as int? ?? 0,
        phonetic: m['phonetic'] as String?,
        wordClass: m['word_class'] as String?,
        domains: _splitList(m['domains']),
        topics: _splitList(m['topics']),
        origin: m['origin'] as String?,
        baseWord: m['base_word'] as String?,
        nonStandard: m['non_standard'] as String?,
        variants: _splitList(m['variants']),
        nonStandardForms: _splitList(m['non_standard_forms']),
        clitics: _parseMaps(m['clitics']).map(Clitic.fromMap).toList(),
        senses: _parseMaps(m['senses']).map(WordSense.fromMap).toList(),
        examples: _parseMaps(m['examples']).map(WordExample.fromMap).toList(),
        derivations:
            _parseMaps(m['derivations']).map(Derivation.fromMap).toList(),
        gabunganKata: _parseStringList(m['gabungan']),
        zh: m['zh'] as String?,
        zhPos: m['zh_pos'] as String?,
        affixBase: m['affix_base'] as String?,
        affixes: _parseMaps(m['affixes']).map(AffixPart.fromMap).toList(),
        grammarFunction: m['grammar_function'] as String?,
        grammarNotes: GrammarNote.decodeList(m['grammar_notes']),
        fullName: m['full_name'] as String?,
        affixType: m['affix_type'] as String?,
        posAll: m['pos_all'] as String?,
        properKind: m['proper_kind'] as String?,
        phraseKind: m['phrase_kind'] as String?,
        audioArdi: m['audio_ardi'] as String?,
        audioGadis: m['audio_gadis'] as String?,
        audioHuman: m['audio_human'] as String?,
        audioParts: _parseStringList(m['audio_parts']),
        mnemonic: m['mnemonic'] as String?,
        mnemonicDefault: m['mnemonic_default'] as String?,
        quizZh: m['quiz_zh'] as String?,
        mnemonicImages: _splitList(m['mnemonic_images']),
        enabled: (m['enabled'] as int? ?? 1) == 1,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        userWord: (m['user_word'] as int? ?? 0) == 1,
        userBlocks:
            _parseMaps(m['user_blocks']).map(UserBlock.fromMap).toList(),
        cardOrder: m['card_order'] as String?,
      );

  static List<String> _splitList(Object? v) {
    if (v is! String || v.isEmpty) return const [];
    return v.split(',').where((s) => s.isNotEmpty).toList();
  }

  static List<String> _parseStringList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      return [
        if (v is List)
          for (final e in v) e.toString()
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, Object?>> _parseMaps(Object? raw) {
    if (raw is List) {
      return [
        for (final x in raw)
          if (x is Map) x.cast<String, Object?>()
      ];
    }
    if (raw is! String || raw.isEmpty) return const [];

    if (raw.trimLeft().startsWith('[')) {
      try {
        final d = jsonDecode(raw);
        if (d is List) {
          return [
            for (final x in d)
              if (x is Map) x.cast<String, Object?>()
          ];
        }
      } catch (_) {}
      return const [];
    }
    return raw.split('\u0001').map((part) {
      final map = <String, Object?>{};
      for (final kv in part.split('\u0002')) {
        final i = kv.indexOf('=');
        if (i > 0) map[kv.substring(0, i)] = kv.substring(i + 1);
      }
      return map;
    }).toList();
  }
}
