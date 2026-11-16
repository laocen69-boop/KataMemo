library;

import 'grammar_models.dart';

String grammarPagePlainText(GPage page) {
  final b = StringBuffer();
  b.writeln(page.title);
  if (page.titleId.isNotEmpty) b.writeln(page.titleId);
  if (page.summary.isNotEmpty) {
    b.writeln();
    b.writeln(page.summary);
  }
  var exNo = 0;
  for (final x in page.blocks) {
    b.writeln();
    switch (x) {
      case GLeadBlock(:final text):
        b.writeln('【结论】');
        b.writeln(_plain(text));
      case GHeadingBlock(:final text):
        b.writeln('【${_plain(text)}】');
        exNo = 0;
      case GTextBlock(:final text):
        b.writeln(_plain(text));
      case GStepsBlock(:final title, :final items):
        if (title.isNotEmpty) b.writeln(_plain(title));
        for (var i = 0; i < items.length; i++) {
          b.writeln('${i + 1}. ${_plain(items[i])}');
        }
      case GPitBlock(:final items):
        b.writeln('【易错】');
        for (final s in items) {
          b.writeln('- ${_plain(s)}');
        }
      case GTableBlock(:final title, :final cols, :final rows):
        if (title.isNotEmpty) b.writeln(_plain(title));
        if (cols.isNotEmpty) b.writeln(cols.join(' | '));
        for (final r in rows) {
          b.writeln(r.map((c) => c.replaceAll(kGTableCellSep, ' / ')).join(' | '));
        }
      case GExBlock(:final items):
        for (final e in items) {
          exNo++;
          b.writeln('$exNo. ${e.plain}');
          if (e.z.isNotEmpty) b.writeln('   ${e.z}');
        }
      case GVsBlock(:final a, b: final bb, :final note):
        for (final s in [a, bb]) {
          b.writeln('▸ ${_plain(s.title)}');
          if (s.text.isNotEmpty) b.writeln(_plain(s.text));
          for (final e in s.ex) {
            b.writeln('  ${e.plain}${e.z.isEmpty ? '' : '  ${e.z}'}');
          }
        }
        if (note.isNotEmpty) b.writeln(_plain(note));
      case GWordsBlock(:final title, :final list):
        if (title.isNotEmpty) b.writeln(_plain(title));
        b.writeln(list.join('、'));
      case GTreeBlock(:final q, :final opts):
        if (q.isNotEmpty) b.writeln(_plain(q));
        for (final o in opts) {
          b.writeln('- ${o.label}${o.hint.isEmpty ? '' : '（${o.hint}）'}');
          if (o.result.answer.isNotEmpty) b.writeln('  ${o.result.answer}');
          if (o.result.rule.isNotEmpty) b.writeln('  ${o.result.rule}');
          for (final e in o.result.examples) {
            b.writeln('  $e');
          }
        }
      case GUnknownBlock():
        break;
    }
  }
  return _normalize(b.toString());
}

String _plain(String s) => s.replaceAll('**', '');

String _normalize(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
    } else {
      out.add(line.trimRight());
    }
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}
