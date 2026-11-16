import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/kbbi_link.dart';

void main() {
  test('单词页地址：官网根 + /entri/ + 去首尾空格', () {
    expect(kbbiEntryUrl(' apel '),
        'https://kbbi.kemendikdasmen.go.id/entri/apel');
  });

  test('短语里的空格按 URL 编码成 %20，不变成加号或裸空格', () {
    expect(kbbiEntryUrl('mata hari'),
        'https://kbbi.kemendikdasmen.go.id/entri/mata%20hari');
  });

  test('带撇号或连字符的词保持可用（不出现未编码的字符）', () {
    final u = kbbiEntryUrl("ter-tawa");
    expect(u.startsWith('https://kbbi.kemendikdasmen.go.id/entri/'), isTrue);
    expect(u.contains(' '), isFalse);
  });
}
