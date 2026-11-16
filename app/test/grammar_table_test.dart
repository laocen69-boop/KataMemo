import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/widgets/grammar/g_table.dart';

void main() {
  testWidgets('多行首列不会让后续行错位', (tester) async {
    const block = GTableBlock(cols: ['词根首音', '变成', '首字母'], rows: [
      ['l\u3000m\u3000n\u3000ng\u3000ny\u3000r\u3000y\u3000w', 'me-', '保留'],
      ['b\u3000f\u3000v', 'mem-', '保留'],
    ]);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GTable(block: block)),
    ));

    final l = tester.getRect(find.text('l'));
    final me = tester.getRect(find.text('me-'));
    final w = tester.getRect(find.text('w'));
    final mem = tester.getRect(find.text('mem-'));

    expect(me.center.dy, closeTo((l.top + w.bottom) / 2, 8),
        reason: '同行的短格应在分组行里垂直居中（不会全挤在顶部）');
    expect(mem.top, greaterThanOrEqualTo(w.bottom - 0.5),
        reason: '第二行必须从第一行最高格之后开始（旧实现会错位到 me- 下面）');
  });
}
