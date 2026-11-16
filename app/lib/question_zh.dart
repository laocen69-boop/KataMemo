library;

final RegExp _kLatinRun = RegExp(r"[A-Za-z][A-Za-z'\-]*");

final RegExp _kCJK = RegExp(r'[\u4e00-\u9fff]');

final RegExp _kNoise = RegExp(
    r"/[A-Za-z][A-Za-z\s'\-]{0,20}/|\[[^\]]{0,20}\]|<[^>]{0,20}>|\{[^}]{0,20}\}");

final RegExp _kLatinPair =
    RegExp(r"[A-Za-z\u00C0-\u024F][A-Za-z\u00C0-\u024F'\-]*\s*"
        r"/\s*"
        r"[A-Za-z\u00C0-\u024F][A-Za-z\u00C0-\u024F'\-]*");

final RegExp _kParen = RegExp(r'（[^（）]*）|\([^()]*\)');

final RegExp _kOrphanPunc = RegExp(r'(?<=\s)[?!,，＝=;；]+|[?!,，＝=;；]+(?=\s)');

final RegExp _kEdgeJunk = RegExp(r'^[\s=＝：:、,，\-–—]+|[\s=＝：:、,，\-–—]+$');

const String kRareMark = '（僻）';

String _cleanSegment(String seg) {
  var t = seg.replaceAll(_kNoise, ' ');

  t = t.replaceAll(_kLatinPair, ' ');

  t = t.replaceAllMapped(_kLatinRun, (m) {
    final w = m.group(0)!;
    final after = t.substring(m.end);
    return (w.length <= 6 && after.startsWith('.')) ? w : ' ';
  });

  t = t.replaceAll(RegExp(r"(?<=[，,（(：:；;、\s])/(?=[\u4e00-\u9fff])"), ' ');

  t = t.replaceAllMapped(_kParen, (m) {
    final full = m.group(0)!;
    final inner = full
        .substring(1, full.length - 1)
        .replaceAll(_kEdgeJunk, '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (inner.isEmpty || !_kCJK.hasMatch(inner)) return ' ';
    return '${full[0]}$inner${full[full.length - 1]}';
  });
  t = t.replaceAll(_kOrphanPunc, ' ');

  t = t.replaceAll(RegExp(r'（\s+'), '（').replaceAll(RegExp(r'\s+）'), '）');
  t = t.replaceAll(RegExp(r'\(\s+'), '(').replaceAll(RegExp(r'\s+\)'), ')');
  t = t.replaceAll(RegExp(r'[：:]\s+'), '：');

  t = t.replaceAll(RegExp(r'（\s*）|\(\s*\)'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(_kEdgeJunk, '');
  return t;
}

String? questionZhOf(String? zh) {
  final src = zh?.trim();
  if (src == null || src.isEmpty) return null;
  final segs = src.split(RegExp(r'[；;]'));
  final out = <String>[];
  final rare = <String>[];
  for (final s in segs) {
    final isRare = s.trim().endsWith(kRareMark);
    final t = _cleanSegment(isRare ? s.replaceAll(kRareMark, '') : s);
    if (t.isEmpty || !_kCJK.hasMatch(t)) continue;
    (isRare ? rare : out).add(t);
  }

  if (out.isEmpty) out.addAll(rare);
  if (out.isEmpty) return src;
  var joined = out.join('；');

  joined = joined.replaceAllMapped(
      RegExp(r'\b([a-z]{1,4}\.)(?=[^\s])'), (m) => '${m.group(1)} ');
  return joined;
}
