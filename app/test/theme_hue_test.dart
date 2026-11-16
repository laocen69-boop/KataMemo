import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/theme/k_colors.dart';

double hueOf(Color c) => HSLColor.fromColor(c).hue;

void main() {
  group('主题换色（2026-11-08：Pro 绿 / 开源蓝）', () {
    test('withBrandHue 只换色相，保留饱和度与明度', () {
      const g = KColors.light;
      final b = g.withBrandHue(220);
      expect(hueOf(b.brand).round(), 220);
      expect(HSLColor.fromColor(b.brand).saturation,
          closeTo(HSLColor.fromColor(g.brand).saturation, 0.001));
      expect(HSLColor.fromColor(b.brand).lightness,
          closeTo(HSLColor.fromColor(g.brand).lightness, 0.001));
    });

    test('品牌色族 30+ 字段全部跟着换（防「签到还是绿圈」回归）', () {
      const g = KColors.light;
      final b = KColorsBlue.light;
      final pairs = <String, (Color, Color)>{
        'brand': (g.brand, b.brand),
        'brand2b（学习页进度条新学段）': (g.brand2b, b.brand2b),
        'catEdge（词库进度条新学段）': (g.catEdge, b.catEdge),
        'catDeep': (g.catDeep, b.catDeep),
        'catTint': (g.catTint, b.catTint),
        'hl2': (g.hl2, b.hl2),
        'cur': (g.cur, b.cur),
        'curTrack': (g.curTrack, b.curTrack),
        'bandGradTop': (g.bandGradTop, b.bandGradTop),
        'bandChipText': (g.bandChipText, b.bandChipText),
        'tint': (g.tint, b.tint),
      };
      for (final e in pairs.entries) {

        expect(hueOf(e.value.$2), closeTo(205, 6), reason: '${e.key} 没换色相');
        expect(e.value.$2, isNot(e.value.$1), reason: '${e.key} 仍是绿色');
      }
      expect(KColorsBlue.dark.brand, isNot(KColors.dark.brand),
          reason: '夜间主题也要跟着换');
    });

    test('语义色不随品牌色走（记忆强度 / 错误红）', () {
      const g = KColors.light;
      final b = KColorsBlue.light;
      expect(b.danger, g.danger);
      expect(b.mStrong, g.mStrong);

      expect(b.s1, g.s1,
          reason: '熟悉（s1）是语义色，不跟着品牌色整体换相');
      expect(b.s0, isNot(g.s0), reason: '已掌握（s0）在开源版要是蓝的');
      expect(b.s0, b.brand,
          reason: '已掌握用「去学习」按钮同款蓝，而不是深绿硬转出来的藏青');
      expect(hueOf(b.s0), closeTo(205, 6));
      expect(KColorsBlue.dark.s0, KColorsBlue.dark.brand,
          reason: '夜间同样跟按钮蓝');
    });

    test('UI 层不许再出现品牌绿字面量', () {
      final allowed = {'theme/k_colors.dart', 'ratings.dart'};
      final bad = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final rel = e.path.replaceAll('\\', '/').replaceFirst('lib/', '');
        if (allowed.any((a) => rel.endsWith(a))) continue;
        final t = e.readAsStringSync();
        if (t.contains('0xFF4CAF8D') || t.contains('0xFF22A06B')) bad.add(rel);
      }
      expect(bad, isEmpty,
          reason: '品牌色要走 KColors（或用 kSpeakGreen getter），不许写死绿色');
    });
  });
}
