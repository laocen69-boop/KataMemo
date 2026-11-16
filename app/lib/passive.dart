library;

const int kPassiveMinStemLen = 3;

const List<String> kParticleSuffixes = [
  'nya',
  'lah',
  'kah',
  'tah',
  'pun',
  'ku',
  'mu'
];

class PassiveParse {

  final String clicked;

  final String form;

  final String particle;

  final String stem;

  final String active;

  final String ownCard;

  const PassiveParse({
    required this.clicked,
    required this.form,
    required this.particle,
    required this.stem,
    required this.active,
    this.ownCard = '',
  });

  String get withoutParticle => particle.isEmpty
      ? clicked
      : clicked.substring(0, clicked.length - particle.length + 1);

  String get equation => '$form = di- + $stem';

  bool get strippedParticle => particle.isNotEmpty && clicked != form;

  @override
  String toString() => '$clicked → $form = di- + $stem → $active';
}

List<String> activeCandidates(String stem) {
  final out = <String>[];
  if (stem.length < kPassiveMinStemLen) return out;

  final h2 = stem.length >= 2 ? stem.substring(0, 2) : stem;
  if (h2 == 'kh') out.add('meng$stem');
  if (h2 == 'sy') out.add('men$stem');

  final c0 = stem[0];
  if ('aeiou'.contains(c0) || c0 == 'g' || c0 == 'h') {
    out.add('meng$stem');
  } else if ('bfv'.contains(c0)) {
    out.add('mem$stem');
  } else if ('cdjz'.contains(c0)) {
    out.add('men$stem');
  } else if (c0 == 'p') {
    out.add('mem${stem.substring(1)}');
    out.add('mem$stem');
  } else if (c0 == 't') {
    out.add('men${stem.substring(1)}');
    out.add('men$stem');
  } else if (c0 == 's') {
    out.add('meny${stem.substring(1)}');
    out.add('men$stem');
  } else if (c0 == 'k') {
    out.add('meng${stem.substring(1)}');
    out.add('meng$stem');
  } else {
    out.add('me$stem');
  }
  if (stem.startsWith('per')) {
    out.insert(0, 'memper${stem.substring(3)}');
  }
  if (stem.length <= 4) {
    out.add('menge$stem');
  }

  final uniq = <String>[];
  for (final c in out) {
    if (c != stem && !uniq.contains(c)) uniq.add(c);
  }
  return uniq;
}

List<PassiveParse> passiveParses(String folded) {
  final out = <PassiveParse>[];
  if (!folded.startsWith('di') || folded.length < 2 + kPassiveMinStemLen) {
    return out;
  }

  for (final p in kParticleSuffixes) {
    if (!folded.endsWith(p)) continue;
    final inner = folded.substring(0, folded.length - p.length);
    if (inner.length < 2 + kPassiveMinStemLen || !inner.startsWith('di')) {
      continue;
    }
    final stem = inner.substring(2);
    for (final a in activeCandidates(stem)) {
      out.add(PassiveParse(
          clicked: folded,
          form: inner,
          particle: '-$p',
          stem: stem,
          active: a));
    }
  }

  final stem = folded.substring(2);
  for (final a in activeCandidates(stem)) {
    out.add(PassiveParse(
        clicked: folded, form: folded, particle: '', stem: stem, active: a));
  }
  return out;
}
