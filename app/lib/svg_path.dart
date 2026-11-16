library;

import 'dart:ui';

Path parseSvgPath(String d) {
  final p = _Parser(d);
  final path = Path();
  var cur = Offset.zero, start = Offset.zero;
  Offset? lastCtrl;
  Offset? lastQuad;
  String cmd = '';
  while (true) {
    p.skipSep();
    if (p.done) break;
    if (p.isCommand) {
      cmd = p.take();
    } else if (cmd.isEmpty) {
      throw FormatException('SVG path 缺命令：$d');
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    Offset pt(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);
    final c = cmd.toUpperCase();
    switch (c) {
      case 'M':
        cur = pt(p.num(), p.num());
        start = cur;
        path.moveTo(cur.dx, cur.dy);
        lastCtrl = lastQuad = null;
      case 'L':
        cur = pt(p.num(), p.num());
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = lastQuad = null;
      case 'H':
        final x = p.num();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = lastQuad = null;
      case 'V':
        final y = p.num();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
        lastCtrl = lastQuad = null;
      case 'C':
        final c1 = pt(p.num(), p.num());
        final c2 = pt(p.num(), p.num());
        final e = pt(p.num(), p.num());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        lastQuad = null;
        cur = e;
      case 'S':
        final c1 = lastCtrl == null ? cur : cur * 2 - lastCtrl;
        final c2 = pt(p.num(), p.num());
        final e = pt(p.num(), p.num());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        lastQuad = null;
        cur = e;
      case 'Q':
        final q = pt(p.num(), p.num());
        final e = pt(p.num(), p.num());
        path.quadraticBezierTo(q.dx, q.dy, e.dx, e.dy);
        lastQuad = q;
        lastCtrl = null;
        cur = e;
      case 'T':
        final q = lastQuad == null ? cur : cur * 2 - lastQuad;
        final e = pt(p.num(), p.num());
        path.quadraticBezierTo(q.dx, q.dy, e.dx, e.dy);
        lastQuad = q;
        lastCtrl = null;
        cur = e;
      case 'A':
        final rx = p.num(), ry = p.num(), rot = p.num();
        final large = p.flag(), sweep = p.flag();
        final e = pt(p.num(), p.num());
        path.arcToPoint(e,
            radius: Radius.elliptical(rx.abs(), ry.abs()),
            rotation: rot,
            largeArc: large,
            clockwise: sweep);
        lastCtrl = lastQuad = null;
        cur = e;
      case 'Z':
        path.close();
        cur = start;
        lastCtrl = lastQuad = null;
      default:
        throw FormatException('不支持的 SVG 命令 $cmd');
    }
  }
  return path;
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get done => i >= s.length;
  bool get isCommand => 'MmLlHhVvCcSsQqTtAaZz'.contains(s[i]);

  String take() => s[i++];

  void skipSep() {
    while (i < s.length && (s[i] == ' ' || s[i] == ',' || s[i] == '\n' || s[i] == '\t')) {
      i++;
    }
  }

  bool flag() {
    skipSep();
    final ch = s[i++];
    if (ch != '0' && ch != '1') throw FormatException('弧线标志位不对：$ch');
    return ch == '1';
  }

  double num() {
    skipSep();
    final st = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var dot = false, exp = false;
    while (i < s.length) {
      final ch = s[i];
      if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        i++;
      } else if (ch == '.' && !dot && !exp) {
        dot = true;
        i++;
      } else if ((ch == 'e' || ch == 'E') && !exp) {
        exp = true;
        i++;
        if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
      } else {
        break;
      }
    }
    if (i == st) throw FormatException('这里应该是数字：${s.substring(st)}');
    return double.parse(s.substring(st, i));
  }
}
