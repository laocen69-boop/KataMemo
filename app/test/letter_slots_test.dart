import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/letter_slots.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(extensions: const [KColors.light]),
        home: Scaffold(body: Center(child: child)),
      );

  int tiles(WidgetTester t) => find
      .descendant(
          of: find.byType(LetterSlots), matching: find.byType(Container))
      .evaluate()
      .where((e) {
    final c = e.widget as Container;
    return c.decoration is BoxDecoration &&
        (c.decoration as BoxDecoration).border != null;
  }).length;

  testWidgets('一格一个字母：音标符 / 大小写 / 空格不影响格数', (t) async {
    await t.pumpWidget(host(const LetterSlots(target: 'Témbok')));
    expect(tiles(t), 6);
    await t.pumpWidget(host(const LetterSlots(target: 'toko buku')));
    expect(tiles(t), 8, reason: '空格是间隔，不占格');
    await t.pumpWidget(host(const LetterSlots(target: 'ke-mana')));
    expect(tiles(t), 6, reason: '连字符是短线，不占格');
  });

  testWidgets('正面不泄漏字母；输入时逐格填上', (t) async {
    await t.pumpWidget(host(const LetterSlots(target: 'rumah')));
    for (final ch in 'rumah'.split('')) {
      expect(find.text(ch), findsNothing);
    }
    await t.pumpWidget(host(const LetterSlots(target: 'rumah', typed: 'Ru')));
    expect(find.text('r'), findsOneWidget);
    expect(find.text('u'), findsOneWidget);
    expect(find.text('m'), findsNothing);
  });

  testWidgets('多打的字母多出格子；判完后错格标红', (t) async {
    await t.pumpWidget(host(const LetterSlots(
        target: 'rumah', typed: 'rumahh', verdict: true)));
    expect(tiles(t), 6, reason: '多打的一个字母也要有格子');
    await t.pumpWidget(host(const LetterSlots(
        target: 'rumah', typed: 'rumeh', verdict: true)));
    final red = find
        .descendant(
            of: find.byType(LetterSlots), matching: find.byType(Container))
        .evaluate()
        .where((e) {
      final d = (e.widget as Container).decoration;
      return d is BoxDecoration &&
          d.border is Border &&
          (d.border as Border).top.color == const Color(0xFFD96A5A);
    }).length;
    expect(red, 1, reason: '只有第 4 格（e ≠ a）是红的');
  });
}
