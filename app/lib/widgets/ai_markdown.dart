library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/k_colors.dart';

class _CjkStrong extends md.InlineSyntax {
  _CjkStrong() : super(r'\*\*(?=\S)(.+?)(?<=\S)\*\*');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('strong', match[1]!));
    return true;
  }
}

String normalizeMarkdownTables(String src) {
  final normalizedNewlines = src.replaceAll('\r\n', '\n');
  final lines = normalizedNewlines.split('\n');
  final out = <String>[];
  var inFence = false;
  var fenceChar = '';

  bool isFenceLine(String line) {
    final t = line.trimLeft();
    return t.startsWith('```') || t.startsWith('~~~');
  }

  bool isSeparatorLine(String line) {
    final t = line.trim();
    if (!t.contains('|') && !t.contains('-') && !t.contains('─') && !t.contains('—')) {
      return false;
    }
    if (!t.contains('|')) return false;
    final cleaned = t.replaceAll('─', '-').replaceAll('—', '-');
    return RegExp(r'^\|?[\s:]*-{1,}[\s:]*(\|[\s:]*-{1,}[\s:]*)*\|?$').hasMatch(cleaned);
  }

  List<String> splitPipeCells(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|') && !t.endsWith(r'\|')) {
      t = t.substring(0, t.length - 1);
    }
    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (ch == r'\' && i + 1 < t.length && t[i + 1] == '|') {
        buf.write(r'\|');
        i++;
      } else if (ch == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  String formatRow(List<String> cells, int cols) {
    final fixed = List<String>.generate(
      cols,
      (idx) => idx < cells.length ? cells[idx] : '',
    );
    return '| ${fixed.join(' | ')} |';
  }

  String formatSeparator(List<String> rawCells, int cols) {
    final segs = List<String>.generate(cols, (idx) {
      final raw = idx < rawCells.length
          ? rawCells[idx].replaceAll('─', '-').replaceAll('—', '-').replaceAll(' ', '')
          : '';
      final leftColon = raw.startsWith(':');
      final rightColon = raw.endsWith(':') && raw.length > 1;
      if (leftColon && rightColon) return ':---:';
      if (rightColon) return '---:';
      if (leftColon) return ':---';
      return '---';
    });
    return '| ${segs.join(' | ')} |';
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (isFenceLine(line)) {
      final t = line.trimLeft();
      final marker = t.startsWith('```') ? '```' : '~~~';
      if (!inFence) {
        inFence = true;
        fenceChar = marker;
      } else if (marker == fenceChar) {
        inFence = false;
        fenceChar = '';
      }
      out.add(line);
      i++;
      continue;
    }

    if (!inFence &&
        i + 1 < lines.length &&
        line.contains('|') &&
        isSeparatorLine(lines[i + 1])) {
      final headCells = splitPipeCells(line);
      final sepCells = splitPipeCells(lines[i + 1]);
      final cols = headCells.length >= 2 ? headCells.length : sepCells.length;
      if (cols >= 2) {
        if (out.isNotEmpty && out.last.trim().isNotEmpty) {
          out.add('');
        }
        out.add(formatRow(headCells, cols));
        out.add(formatSeparator(sepCells, cols));
        i += 2;
        while (i < lines.length &&
            !isFenceLine(lines[i]) &&
            lines[i].trim().isNotEmpty &&
            lines[i].contains('|')) {
          out.add(formatRow(splitPipeCells(lines[i]), cols));
          i++;
        }
        if (i < lines.length && lines[i].trim().isNotEmpty) {
          out.add('');
        }
        continue;
      }
    }

    out.add(line);
    i++;
  }

  return out.join('\n');
}

class AiMarkdown extends StatelessWidget {
  final String data;
  const AiMarkdown(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final base = TextStyle(fontSize: 14.5, height: 1.6, color: k.text);
    return MarkdownBody(
      data: normalizeMarkdownTables(data),
      softLineBreak: true,
      inlineSyntaxes: [_CjkStrong()],
      styleSheet: MarkdownStyleSheet(
        p: base,
        h1: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: k.deep),
        h2: base.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700, color: k.deep),
        h3: base.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700, color: k.deep),
        h4: base.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: k.text),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
        strong: TextStyle(fontWeight: FontWeight.w700, color: k.deep),
        em: const TextStyle(fontStyle: FontStyle.italic),
        listBullet: base.copyWith(color: k.deep),
        listIndent: 20,
        blockSpacing: 8,
        blockquote: base.copyWith(fontSize: 14, color: k.t2),
        blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        blockquoteDecoration: BoxDecoration(
          color: k.tint,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: k.brand, width: 3)),
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13.5,
          color: k.text,
          backgroundColor: k.alt,
        ),
        codeblockDecoration: BoxDecoration(
          color: k.alt,
          borderRadius: BorderRadius.circular(8),
        ),
        tableHead: base.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
        tableBody: base.copyWith(fontSize: 13.5, height: 1.45),
        tableBorder: TableBorder.all(color: k.line, width: 1),
        tableHeadAlign: TextAlign.left,
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        tableCellsDecoration: BoxDecoration(color: k.surface),
        tableColumnWidth: const FlexColumnWidth(),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: k.line, width: 1)),
        ),
        a: TextStyle(color: k.deep, decoration: TextDecoration.underline),
      ),
    );
  }
}
