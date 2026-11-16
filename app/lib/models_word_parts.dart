part of 'models.dart';

class AffixPart {
  final String type;
  final String morph;
  final String name;
  final String meaning;

  const AffixPart(
      {required this.type,
      required this.morph,
      required this.name,
      required this.meaning});

  Map<String, Object?> toMap() =>
      {'type': type, 'morph': morph, 'name': name, 'meaning': meaning};

  factory AffixPart.fromMap(Map<String, Object?> m) => AffixPart(
        type: m['type'] as String? ?? '',
        morph: m['morph'] as String? ?? '',
        name: m['name'] as String? ?? '',
        meaning: m['meaning'] as String? ?? '',
      );
}

class WordSense {
  final String def;
  final String? example;

  final String? pos;

  const WordSense({required this.def, this.example, this.pos});

  Map<String, Object?> toMap() =>
      {'def': def, 'example': example, 'pos': pos};

  factory WordSense.fromMap(Map<String, Object?> m) {
    final pos = m['pos'] as String?;
    var def = m['def'] as String? ?? '';

    if (pos != null && pos.isNotEmpty) {
      def = def.replaceFirst(RegExp(r'^\s*\[[a-z]+\]\s*'), '');
    }
    return WordSense(
      def: def,
      example: m['example'] as String?,
      pos: pos,
    );
  }
}

class WordExample {
  final String text;
  final String? zh;

  final String? src;

  final String? quiz;

  const WordExample({required this.text, this.zh, this.src, this.quiz});

  Map<String, Object?> toMap() => {
        'i': text,
        'z': zh,
        if (src != null) 's': src,
        if (quiz != null) 'q': quiz,
      };

  factory WordExample.fromMap(Map<String, Object?> m) => WordExample(
        text: m['i'] as String? ?? '',
        zh: m['z'] as String?,
        src: m['s'] as String?,
        quiz: m['q'] as String?,
      );
}

class Derivation {
  final String form;
  final String? pos;
  final String? gloss;

  final String? def;

  const Derivation({
    required this.form,
    this.pos,
    this.gloss,
    this.def,
  });

  Map<String, Object?> toMap() => {'f': form, 'p': pos, 'g': gloss, 'd': def};

  factory Derivation.fromMap(Map<String, Object?> m) => Derivation(
        form: m['f'] as String? ?? '',
        pos: m['p'] as String?,
        gloss: m['g'] as String?,
        def: m['d'] as String?,
      );
}

class Clitic {

  final String form;

  final String zh;

  final String rule;

  final List<WordExample> examples;

  final String? note;

  const Clitic({
    required this.form,
    required this.zh,
    this.rule = '',
    this.examples = const [],
    this.note,
  });

  Map<String, Object?> toMap() => {
        'f': form,
        'zh': zh,
        'rule': rule,
        'ex': jsonEncode([for (final e in examples) e.toMap()]),
        'note': note,
      };

  factory Clitic.fromMap(Map<String, Object?> m) => Clitic(
        form: m['f'] as String? ?? '',
        zh: m['zh'] as String? ?? '',
        rule: m['rule'] as String? ?? '',
        examples: _decodeExamples(m['ex']),
        note: m['note'] as String?,
      );

  static List<WordExample> _decodeExamples(Object? raw) {
    List<dynamic>? list;
    if (raw is List) {
      list = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final v = jsonDecode(raw);
        if (v is List) list = v;
      } catch (_) {
        return const [];
      }
    }
    if (list == null) return const [];
    return [
      for (final e in list)
        if (e is Map) WordExample.fromMap(e.cast<String, Object?>()),
    ];
  }
}

class GrammarNote {

  final String tag;

  final String zh;
  final List<WordExample> examples;

  final String src;

  const GrammarNote({
    required this.tag,
    this.zh = '',
    this.examples = const [],
    this.src = '',
  });

  Map<String, Object?> toMap() => {
        'u': tag,
        'zh': zh,
        'ex': jsonEncode([for (final e in examples) e.toMap()]),
        'src': src,
      };

  factory GrammarNote.fromMap(Map<String, Object?> m) => GrammarNote(
        tag: m['u'] as String? ?? '',
        zh: m['zh'] as String? ?? '',
        examples: Clitic._decodeExamples(m['ex']),
        src: m['src'] as String? ?? '',
      );

  static String? encodeList(Object? raw) {
    if (raw is! List || raw.isEmpty) return null;
    final maps = <Map<String, Object?>>[];
    for (final g in raw) {
      if (g is Map) {
        maps.add(GrammarNote.fromMap(g.cast<String, Object?>()).toMap());
      }
    }
    return maps.isEmpty ? null : WordCard.encodeMaps(maps);
  }

  static List<GrammarNote> decodeList(Object? raw) {
    if (raw is List) {
      return [
        for (final g in raw)
          if (g is Map) GrammarNote.fromMap(g.cast<String, Object?>()),
      ];
    }
    return WordCard._parseMaps(raw).map(GrammarNote.fromMap).toList();
  }
}
