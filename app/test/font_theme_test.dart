import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/main.dart';

void main() {
  test('全局主字体为 PlusJakartaSans，回退链以 NotoSans 开头含中文回退', () {
    expect(kAppFontFamily, 'PlusJakartaSans');
    expect(kAppFontFallback.first, 'NotoSans');
    expect(
      kAppFontFallback,
      containsAll(['NotoSans', 'Noto Sans SC', 'PingFang SC', 'Microsoft YaHei']),
    );
  });

  test('11 个官方 TTF 字体文件存在且已在 pubspec.yaml 声明', () {
    const files = [
      'PlusJakartaSans-Regular.ttf',
      'PlusJakartaSans-Italic.ttf',
      'PlusJakartaSans-Medium.ttf',
      'PlusJakartaSans-SemiBold.ttf',
      'PlusJakartaSans-Bold.ttf',
      'PlusJakartaSans-ExtraBold.ttf',
      'NotoSans-Regular.ttf',
      'NotoSans-Italic.ttf',
      'NotoSans-Medium.ttf',
      'NotoSans-SemiBold.ttf',
      'NotoSans-Bold.ttf',
    ];
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: PlusJakartaSans'));
    expect(pubspec, contains('family: NotoSans'));
    for (final name in files) {
      final rel = 'assets/fonts/$name';
      expect(File(rel).existsSync(), isTrue, reason: '$rel missing');
      expect(pubspec, contains(rel), reason: '$rel not declared in pubspec.yaml');
    }
  });
}
