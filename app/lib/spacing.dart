library;

const Map<String, (String, String)> kSpacingVariants = {
  'dimana': ('di', 'mana'),
  'disini': ('di', 'sini'),
  'disana': ('di', 'sana'),
  'diatas': ('di', 'atas'),
  'dibawah': ('di', 'bawah'),
  'kemana': ('ke', 'mana'),
  'kesini': ('ke', 'sini'),
  'kesana': ('ke', 'sana'),
  'darimana': ('dari', 'mana'),
  'darisini': ('dari', 'sini'),
  'darisana': ('dari', 'sana'),
};

class SpacingParse {

  final String clicked;

  final String prefix;

  final String rest;

  final String target;

  final bool phraseCard;

  const SpacingParse({
    required this.clicked,
    required this.prefix,
    required this.rest,
    required this.target,
    required this.phraseCard,
  });

  String get phrase => '$prefix $rest';

  String get equation => '$clicked = $prefix + $rest';

  @override
  String toString() => '$equation → $target';
}
