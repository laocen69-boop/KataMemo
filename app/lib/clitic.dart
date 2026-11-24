

library;

const Set<String> kCliticBaseClasses = {'n', 'v'};

const int kCliticMinBaseLen = 3;

const Map<String, String> kCliticHosts = {
  '-ku': 'aku',
  '-mu': 'kamu',
  '-nya': 'dia',
  'ku-': 'aku',
  'kau-': 'kamu',
};

class CliticParse {

  final String form;

  final String base;

  final String clitic;

  const CliticParse(
      {required this.form, required this.base, required this.clitic});

  String get host => kCliticHosts[clitic] ?? '';

  /// 是否前附着代词（`ku-` / `kau-`）。
  bool get isProclitic => clitic.endsWith('-');

  @override
  String toString() =>
      isProclitic ? '$form = $clitic + $base' : '$form = $base + $clitic';
}

/// 拆前附着代词 `ku-` / `kau-`（如 `kubaca` → `ku- + baca`，`kaubaca` → `kau- + baca`）。
List<CliticParse> procliticParses(String folded) {
  final out = <CliticParse>[];
  for (final clitic in const ['kau-', 'ku-']) {
    final pfx = clitic.substring(0, clitic.length - 1);
    if (!folded.startsWith(pfx)) continue;
    final base = folded.substring(pfx.length);
    if (base.length < kCliticMinBaseLen) continue;
    out.add(CliticParse(form: folded, base: base, clitic: clitic));
  }
  return out;
}

List<CliticParse> cliticParses(String folded) {
  final out = <CliticParse>[];
  for (final clitic in const ['-nya', '-mu', '-ku']) {
    final sfx = clitic.substring(1);
    if (!folded.endsWith(sfx)) continue;
    final base = folded.substring(0, folded.length - sfx.length);
    if (base.length < kCliticMinBaseLen) continue;
    out.add(CliticParse(form: folded, base: base, clitic: clitic));
  }
  return out;
}
