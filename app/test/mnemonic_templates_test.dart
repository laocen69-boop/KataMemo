library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/mnemonic_templates.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: const <ThemeExtension<dynamic>>[KColors.light],
        ),
        home: Scaffold(body: child),
      );

  testWidgets('点芯片插入骨架；再点另一个则另起一行', (tester) async {
    final ctl = TextEditingController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(wrap(MnemonicTemplates(controller: ctl)));

    expect(find.text('＋ 拆词缀'), findsOneWidget);
    expect(find.text('＋ 同源词'), findsOneWidget);
    expect(find.text('＋ 画面'), findsOneWidget);

    await tester.tap(find.text('＋ 拆词缀'));
    await tester.pump();
    expect(ctl.text, '词根 ___ + 词缀 ___ → ___');

    await tester.tap(find.text('＋ 画面'));
    await tester.pump();
    expect(ctl.text, '词根 ___ + 词缀 ___ → ___\n画面：___');
  });

  testWidgets('插完光标落在末尾（接着打字就是往下写）', (tester) async {
    final ctl = TextEditingController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(wrap(MnemonicTemplates(controller: ctl)));

    await tester.tap(find.text('＋ 同源词'));
    await tester.pump();
    expect(ctl.selection.baseOffset, ctl.text.length);
    expect(ctl.selection.isCollapsed, isTrue);
  });
}
