library;

import 'package:flutter_test/flutter_test.dart';

import 'package:katamemo/question_zh.dart';

void main() {
  test('括号里的印尼语举例摘掉，括号里的中文留着', () {

    expect(questionZhOf('在…里（dalam kulkas 在冰箱里）；在…中（书面，抽象）；深'),
        '在…里（在冰箱里）；在…中（书面，抽象）；深');

    expect(questionZhOf('在（表处所）'), '在（表处所）');

    expect(questionZhOf('可以；行（Boleh!）'), '可以；行');
    expect(questionZhOf('动词后缀：使动（KBBI: menjadikan）'), '动词后缀：使动');
  });

  test('括号**成对**保留：摘掉里面的印尼语别把括号削成半边', () {

    expect(questionZhOf('（疑问）哪个、哪些；apakah 才是问句助词'), '（疑问）哪个、哪些；才是问句助词');
  });

  test('音标串摘掉；词性码留着（题面要有词性）', () {

    expect(questionZhOf('1.豆腐/ta hu/；2.知道/ta u/'), '1.豆腐；2.知道');

    expect(questionZhOf('拥有；n.所有'), '拥有；n. 所有');
    expect(questionZhOf('adv. 刚；才'), 'adv. 刚；才');

    expect(questionZhOf('与/同（伴同）；用/以（工具方式）'), '与/同（伴同）；用/以（工具方式）');
  });

  test('用词对比里的印尼语摘掉，剩下的中文仍是一句完整的话', () {

    final out = questionZhOf('像，如同，正如（比作）；sebagai 才是"作为"')!;
    expect(out, contains('像，如同，正如（比作）'));
    expect(out, isNot(contains('sebagai')));
    expect(out, contains('才是'));
  });

  test('摘干净了也别把题面清空（退回原文，宁可长一点）', () {

    expect(questionZhOf('kata bantu'), 'kata bantu');
    expect(questionZhOf('n.'), 'n.');
    expect(questionZhOf(null), isNull);
    expect(questionZhOf('   '), isNull);
  });

  test('中文里出现的英文单词不会被误当成词性码留着', () {
    final out = questionZhOf('（疑问）哪个、哪些；apakah 才是问句助词')!;
    expect(out, isNot(contains('apakah')));
    expect(out, contains('哪个、哪些'));
  });

  test('斜杠组合剥词后不剩悬空的 /（第四十四轮全量检测补）', () {

    expect(questionZhOf('因果连词：表结果或承接（「于是、因此」）：常与 karena/jika 前后呼应'),
        '因果连词：表结果或承接（「于是、因此」）：常与 前后呼应');

    expect(questionZhOf('只、仅仅（cuma / hanya 的口语强调式）'), '只、仅仅（的口语强调式）');

    expect(questionZhOf('清酒（日语借词，demi/酒）；每一（逐）'), '清酒（日语借词 酒）；每一（逐）');

    expect(questionZhOf('证人 / 目击者'), '证人 / 目击者');
    expect(questionZhOf('1.价值（最常用）；2.数值 / 值'), '1.价值（最常用）；2.数值 / 值');
  });
  test('冷僻义项（僻）不进拼写题面；全是冷僻时退回去用', () {
    expect(questionZhOf('他；她；它；穿透（僻）'), '他；她；它');
    expect(questionZhOf('从；自；由；达里语（僻）'), '从；自；由');
    expect(questionZhOf('阴茎（僻）'), '阴茎');
  });
}
