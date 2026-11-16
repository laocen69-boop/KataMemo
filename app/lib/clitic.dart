

library;

const Set<String> kCliticBaseClasses = {'n', 'v'};

const int kCliticMinBaseLen = 3;

const Map<String, String> kCliticHosts = {
  '-ku': 'aku',
  '-mu': 'kamu',
  '-nya': 'dia',
};

class CliticParse {

  final String form;

  final String base;

  final String clitic;

  const CliticParse(
      {required this.form, required this.base, required this.clitic});

  String get host => kCliticHosts[clitic] ?? '';

  @override
  String toString() => '$form = $base + $clitic';
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
