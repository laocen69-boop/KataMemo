library;

class DerivedParse {

  final String clicked;

  final String root;

  final String suffix;

  const DerivedParse({
    required this.clicked,
    required this.root,
    required this.suffix,
  });

  String get equation => '$clicked = $root + -$suffix';
}

List<DerivedParse> derivedParses(String word) {
  final out = <DerivedParse>[];
  for (final suffix in const ['kan', 'i']) {
    if (!word.endsWith(suffix)) continue;
    final root = word.substring(0, word.length - suffix.length);
    if (root.length < 3 || root == word) continue;
    out.add(DerivedParse(clicked: word, root: root, suffix: suffix));
  }
  return out;
}
