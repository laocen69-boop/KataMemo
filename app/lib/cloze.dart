library;

import 'models.dart';

const List<String> kClozeParticles = [
  'nya',
  'lah',
  'kah',
  'tah',
  'pun',
  'ku',
  'mu'
];

const int kClozeMinWords = 4;
const int kClozeMaxWords = 28;

const Map<String, String> _kAccents = {
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
};

String foldCloze(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final m = _kAccents[ch] ?? ch;
    if (m.codeUnitAt(0) >= 0x61 && m.codeUnitAt(0) <= 0x7a) b.write(m);
  }
  return b.toString();
}

class ClozeToken {
  final int start;
  final int end;
  final String text;
  const ClozeToken(this.start, this.end, this.text);
  String get folded => foldCloze(text);
}

final RegExp _kTokRe = RegExp(r"[A-Za-z\u00C0-\u024F']+");

List<ClozeToken> clozeTokens(String text) => [
      for (final m in _kTokRe.allMatches(text))
        ClozeToken(m.start, m.end, m.group(0)!)
    ];

class ClozeSpan {
  final int start;
  final int end;
  final String text;
  const ClozeSpan(this.start, this.end, this.text);

  String before(String src) => src.substring(0, start);
  String after(String src) => src.substring(end);
}

ClozeSpan? clozeSpan(String text, String cardId) {
  if (text.isEmpty || cardId.trim().isEmpty) return null;

  if (cardId.endsWith('-abbr')) cardId = cardId.substring(0, cardId.length - 5);
  final parts = cardId
      .split(RegExp(r"[^A-Za-z\u00C0-\u024F]+"))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length > 1) {

    final pat = RegExp(
        r'(?<![A-Za-z\u00C0-\u024F])' +
            parts.map(RegExp.escape).join(r'[-\s]+') +
            r'(?![A-Za-z\u00C0-\u024F])',
        caseSensitive: false);
    final m = pat.firstMatch(text);
    if (m == null) return null;
    return ClozeSpan(m.start, m.end, m.group(0)!);
  }
  final wid = foldCloze(cardId);
  if (wid.isEmpty) return null;
  final cands = <String>{wid};
  for (final p in kClozeParticles) {
    cands.add('$wid$p');
  }
  for (final t in clozeTokens(text)) {
    if (cands.contains(t.folded)) return ClozeSpan(t.start, t.end, t.text);
  }
  return null;
}

bool clozeLooksUsable(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  final n = _kTokRe.allMatches(t).length;
  if (n < kClozeMinWords || n > kClozeMaxWords) return false;
  if (t.contains('[') || t.contains(']') || t.contains('~')) return false;
  return !t.contains('--');
}

class ClozeQuestion {
  final int index;
  final String text;
  final String? zh;
  final ClozeSpan span;
  const ClozeQuestion(
      {required this.index, required this.text, this.zh, required this.span});

  String get answer => span.text;
}

List<ClozeQuestion> clozeQuestions(List<WordExample> examples, String cardId,
    {int limit = 3}) {
  final strict = <ClozeQuestion>[];
  for (var i = 0; i < examples.length; i++) {
    final e = examples[i];
    final q = e.quiz;
    if (q == null || q.isEmpty) continue;
    final span = clozeSpan(e.text, cardId) ??

        _spanOfAnswer(e.text, q);
    if (span == null) continue;
    strict.add(ClozeQuestion(index: i, text: e.text, zh: e.zh, span: span));
    if (strict.length >= limit) return strict;
  }
  if (strict.isNotEmpty) return strict;
  for (var i = 0; i < examples.length; i++) {
    final e = examples[i];
    if (!clozeLooksUsable(e.text)) continue;
    final span = clozeSpan(e.text, cardId);
    if (span == null) continue;
    strict.add(ClozeQuestion(index: i, text: e.text, zh: e.zh, span: span));
    if (strict.length >= limit) break;
  }
  return strict;
}

ClozeSpan? _spanOfAnswer(String text, String answer) {
  final a = answer.trim();
  if (a.isEmpty) return null;
  final m = RegExp(
    '(?<![A-Za-z0-9\\u00C0-\\u024F])${RegExp.escape(a)}(?![A-Za-z0-9\\u00C0-\\u024F])',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  return ClozeSpan(m.start, m.end, text.substring(m.start, m.end));
}

bool clozeAnswerOk(String input,
    {required String cardId, String? cardWord, String? answer}) {
  final x = foldCloze(input);
  if (x.isEmpty) return false;
  if (x == foldCloze(cardId)) return true;
  if (cardWord != null && x == foldCloze(cardWord)) return true;
  if (answer != null && x == foldCloze(answer)) return true;
  return false;
}
