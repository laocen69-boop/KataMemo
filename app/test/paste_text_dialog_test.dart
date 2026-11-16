import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/screens/scan_screen.dart' show PasteTextDialog;

void main() {
  testWidgets('PasteTextDialog：确认后返回输入内容，退场动画全程不报错', (tester) async {
    String? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            got = await showDialog<String>(
              context: ctx,
              builder: (_) => const PasteTextDialog(initial: 'tesalfa 测试'),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('tesalfa 测试'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tesbeta 义丙');
    await tester.tap(find.text('识别'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(got, 'tesbeta 义丙');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('PasteTextDialog：取消返回 null，不报错', (tester) async {
    String? got = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            got = await showDialog<String>(
              context: ctx,
              builder: (_) => const PasteTextDialog(),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(got, isNull);
  });
}
