import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/theme/k_colors.dart';
import 'package:katamemo/widgets/ai_bench_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('14 条链接：7 榜单 + 7 机构，全 https，描述非空', () {
    expect(kAiBenchLeaderboards.length, 7);
    expect(kAiBenchOrgs.length, 7);
    for (final l in [...kAiBenchLeaderboards, ...kAiBenchOrgs]) {
      expect(l.url, startsWith('https://'), reason: l.name);
      expect(l.name, isNotEmpty);
      expect(l.desc, isNotEmpty);
    }

    final stripped = kAiBenchLeaderboards.every((l) => l.hint.isEmpty);
    for (final l in kAiBenchLeaderboards) {
      expect(l.hint.isNotEmpty, !stripped, reason: l.name);
    }
    for (final l in kAiBenchOrgs) {
      expect(l.hint, isEmpty, reason: l.name);
    }
    expect(kAiBenchDisclaimer, contains('第三方'));
    expect(kAiBenchDisclaimer, contains('无关联'));
  });

  testWidgets('卡片渲染 14 行；长按复制；点击在浏览器不可用时回退复制', (tester) async {

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData().copyWith(
          splashFactory: NoSplash.splashFactory, extensions: [KColors.light]),
      home: const Scaffold(body: SingleChildScrollView(child: AiBenchLinksCard())),
    ));
    expect(find.text('SEA-HELM 印尼语排行榜'), findsOneWidget);
    expect(find.text('Hugging Face Benchmarks'), findsOneWidget);
    expect(find.text('榜单'), findsOneWidget);
    expect(find.text('研究机构与社区'), findsOneWidget);
    expect(find.textContaining('本项目与它们无关联'), findsOneWidget);

    final row = find.text('SEA-HELM 印尼语排行榜');
    await tester.longPress(row);
    await tester.pump();
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('点击在浏览器不可用时回退复制', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('katamemo/picker'),
            (call) async => null);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData().copyWith(
          splashFactory: NoSplash.splashFactory, extensions: [KColors.light]),
      home: const Scaffold(body: SingleChildScrollView(child: AiBenchLinksCard())),
    ));
    await tester.tap(find.text('ibahasa 印尼语 Benchmark'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('浏览器不可用，链接已复制'), findsOneWidget);
  });
}