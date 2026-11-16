import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/version.dart';

void main() {
  test('version.dart 的显示版本与 build 号 == pubspec 的 version', () {
    expect(File('pubspec.yaml').existsSync(), isTrue,
        reason: '测试的当前目录应是 app/（`cd X:\\app && flutter test`）');
    final ps = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+([0-9]+)\s*$', multiLine: true)
        .firstMatch(ps);
    expect(m, isNotNull, reason: 'pubspec 的 version 行要写成 `x.y.z+build`');

    expect(kAppVersion, m!.group(1), reason: '改了 pubspec 忘了改 kAppVersion');
    expect(kBuildNumber, m.group(2), reason: '改了 pubspec 忘了改 kBuildNumber');
  });
}
