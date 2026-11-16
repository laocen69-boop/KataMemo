import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/images.dart';
import 'package:katamemo/widgets/mnemonic_section.dart';

void main() {
  testWidgets('助记图解析一次后跨 rebuild 不再闪占位', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('katamemo_mn_');
    ImageStore.debugDocsDir = tmp;
    final dir = Directory('${tmp.path}${Platform.pathSeparator}mnemonic')
      ..createSync(recursive: true);

    File('${dir.path}${Platform.pathSeparator}note.png').writeAsBytesSync(
      base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII='),
    );
    const rel = 'mnemonic/note.png';

    Widget app(Widget child) => MaterialApp(
          home: Scaffold(body: child),
        );

    await tester.pumpWidget(app(const MnemonicImagesRow(relPaths: [rel])));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('图片已丢失'), findsNothing);

    await tester.pumpWidget(app(const MnemonicImagesRow(relPaths: [rel])));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('…'), findsNothing);

    ImageStore.debugDocsDir = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });
}
