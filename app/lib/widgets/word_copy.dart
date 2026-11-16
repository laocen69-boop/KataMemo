import '../models.dart';

String wordCopyText(
  WordCard card, {
  bool withExamples = false,
  int maxExamples = 3,
}) {
  final b = StringBuffer();
  b.write(card.word);
  final ph = (card.phonetic ?? '').trim();
  if (ph.isNotEmpty) b.write('  $ph');
  b.writeln();

  final cls = card.wordClassLabelsCombined.trim();
  final zh = (card.zhClean ?? '').trim();
  final line = [
    if (cls.isNotEmpty) cls,
    if (zh.isNotEmpty) zh,
  ].join(' · ');
  if (line.isNotEmpty) b.writeln(line);

  if (withExamples && card.examples.isNotEmpty) {
    b.writeln();
    b.writeln('例句：');
    final ex = card.examples.take(maxExamples).toList();
    for (var i = 0; i < ex.length; i++) {
      b.writeln('${i + 1}. ${ex[i].text.trim()}');
      final z = (ex[i].zh ?? '').trim();
      if (z.isNotEmpty) b.writeln('   $z');
    }
  }
  return b.toString().trimRight();
}
