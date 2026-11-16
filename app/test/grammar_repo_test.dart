library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/grammar/grammar_models.dart';
import 'package:katamemo/grammar/grammar_repo.dart';

GrammarRepo _fixture() => GrammarRepo(autoLoad: false)
  ..loadFromJson(File('test/fixtures/grammar_v2_sample.json').readAsStringSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('解析：分区 / 分组 / 页 / 题 / 常查 / 路线', () {
    final r = _fixture();
    expect(r.ready, isTrue);
    expect(r.doc.sections.map((s) => s.id), ['affix', 'contrast', 'wordclass']);
    expect(r.sectionById['affix']!.pageIds, ['af-me', 'af-ter']);
    expect(r.pageById.length, 4);
    expect(r.doc.quiz.length, 5);
    expect(r.doc.hot, ['af-me', 'vs-kan-i']);
    expect(r.doc.path.length, 3);
    final me = r.pageById['af-me']!;
    expect(me.titleId, 'prefiks meN-');
    expect(me.headings, ['形式与音变', '意思']);
    expect(me.blocks.whereType<GTableBlock>().single.cols.length, 3);
  });

  test('块：每种类型都解析成对应的类；未知类型不崩', () {
    final r = GrammarRepo(autoLoad: false)
      ..loadFromJson('''
{"sections": [], "pages": [{"id": "p", "title": "t", "blocks": [
  {"t": "lead", "text": "a"}, {"t": "h", "text": "b"}, {"t": "text", "text": "c"},
  {"t": "steps", "items": ["1"]}, {"t": "pit", "items": ["x"]},
  {"t": "table", "cols": ["a"], "rows": [["b"]]}, {"t": "ex", "items": [{"i": "Saya **makan**", "z": "我吃"}]},
  {"t": "vs", "a": {"title": "A"}, "b": {"title": "B"}}, {"t": "words", "list": ["makan"]},
  {"t": "tree", "q": "?", "opts": []}, {"t": "新类型"}
]}]}
''');
    final b = r.pageById['p']!.blocks;
    expect(b.map((x) => x.runtimeType.toString()).toList(), [
      'GLeadBlock', 'GHeadingBlock', 'GTextBlock', 'GStepsBlock', 'GPitBlock',
      'GTableBlock', 'GExBlock', 'GVsBlock', 'GWordsBlock', 'GTreeBlock', 'GUnknownBlock',
    ]);
    final ex = (b[6] as GExBlock).items.single;
    expect(ex.plain, 'Saya makan');
    expect(ex.highlights, {'makan'});
  });

  test('pagesForWord：按目录顺序，不存在的词返回空', () {
    final r = _fixture();
    expect(r.pagesForWord('membaca').map((p) => p.id), ['af-me']);
    expect(r.pagesForWord('yang').map((p) => p.id), ['wc-yang']);
    expect(r.pagesForWord('tidak-ada'), isEmpty);
  });

  test('pagesOf 丢掉不存在的 id', () {
    final r = _fixture();
    expect(r.pagesOf(['af-me', 'nope', 'af-ter']).map((p) => p.id), ['af-me', 'af-ter']);
  });

  test('搜索排序：标题 > 别名 > 一句话 > 小标题 > 正文', () {
    final r = _fixture();
    expect(r.search('me- 前缀').first.page.id, 'af-me', reason: '标题完全相等');
    expect(r.search('ter-').first.page.id, 'af-ter', reason: '标题前缀');
    final alias = r.search('鼻音前缀');
    expect(alias.first.page.id, 'af-me');
    expect(alias.first.why, '别名');
    final summary = r.search('最高级');
    expect(summary.first.page.id, 'af-ter');
    expect(summary.first.why, '摘要');
    final head = r.search('意思');
    expect(head.first.why, startsWith('小节'));
    final body = r.search('menanami');
    expect(body.single.page.id, 'vs-kan-i');
    expect(body.single.why, '正文');
    expect(r.search('  '), isEmpty);
    expect(r.search('完全没有的词zzz'), isEmpty);
  });

  test('about：免责版数据自带来源说明，完整版为空', () {
    expect(_fixture().doc.about, isEmpty);
    final r = GrammarRepo(autoLoad: false)
      ..loadFromJson('{"sections": [], "pages": [], "about": "独立编写"}');
    expect(r.doc.about, '独立编写');
  });

  test('loadFromJson 换数据：索引整体重建', () {
    final r = _fixture();
    r.loadFromJson('{"sections": [], "pages": [{"id": "only", "title": "只有一页"}]}');
    expect(r.pageById.keys, ['only']);
    expect(r.quizByPage, isEmpty);
    expect(r.pagesForWord('membaca'), isEmpty);
  });
}
