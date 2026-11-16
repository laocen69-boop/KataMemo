library;

const String kGTableCellSep = '　';

class GDoc {
  const GDoc({
    this.sections = const [],
    this.pages = const [],
    this.quiz = const [],
    this.hot = const [],
    this.path = const [],
    this.about = '',
  });

  final String about;

  final List<GSection> sections;
  final List<GPage> pages;
  final List<GQuiz> quiz;

  final List<String> hot;

  final List<String> path;

  factory GDoc.fromJson(Map<String, dynamic> j) => GDoc(
        sections: [for (final s in (j['sections'] as List? ?? [])) GSection.fromJson(s)],
        pages: [for (final p in (j['pages'] as List? ?? [])) GPage.fromJson(p)],
        quiz: [for (final q in (j['quiz'] as List? ?? [])) GQuiz.fromJson(q)],
        hot: _strs(j['hot']),
        path: _strs(j['path']),
        about: j['about'] as String? ?? '',
      );
}

List<String> _strs(Object? o) =>
    o is List ? [for (final x in o) x.toString()] : const [];

class GSection {
  const GSection({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.groups = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final List<GGroup> groups;

  List<String> get pageIds => [for (final g in groups) ...g.pages];

  factory GSection.fromJson(Map<String, dynamic> j) => GSection(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        groups: [for (final g in (j['groups'] as List? ?? [])) GGroup.fromJson(g)],
      );
}

class GGroup {
  const GGroup({this.title = '', this.pages = const []});

  final String title;
  final List<String> pages;

  factory GGroup.fromJson(Map<String, dynamic> j) =>
      GGroup(title: j['title'] as String? ?? '', pages: _strs(j['pages']));
}

class GPage {
  const GPage({
    required this.id,
    required this.title,
    this.section = '',
    this.titleId = '',
    this.summary = '',
    this.aliases = const [],
    this.blocks = const [],
    this.see = const [],
    this.words = const [],
  });

  final String id;
  final String section;
  final String title;

  final String titleId;

  final String summary;

  final List<String> aliases;
  final List<GBlock> blocks;

  final List<String> see;

  final List<String> words;

  List<String> get headings =>
      [for (final b in blocks) if (b is GHeadingBlock) b.text];

  factory GPage.fromJson(Map<String, dynamic> j) => GPage(
        id: j['id'] as String,
        section: j['section'] as String? ?? '',
        title: j['title'] as String? ?? '',
        titleId: j['title_id'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        aliases: _strs(j['aliases']),
        blocks: [for (final b in (j['blocks'] as List? ?? [])) GBlock.fromJson(b)],
        see: _strs(j['see']),
        words: _strs(j['words']),
      );
}

class GQuiz {
  const GQuiz({
    required this.id,
    required this.page,
    required this.q,
    required this.opts,
    required this.ans,
    this.why = '',
  });

  final String id;
  final String page;
  final String q;
  final List<String> opts;
  final int ans;
  final String why;

  factory GQuiz.fromJson(Map<String, dynamic> j) => GQuiz(
        id: j['id'] as String,
        page: j['page'] as String? ?? '',
        q: j['q'] as String? ?? '',
        opts: _strs(j['opts']),
        ans: (j['ans'] as num?)?.toInt() ?? 0,
        why: j['why'] as String? ?? '',
      );
}

class GEx {
  const GEx({required this.i, this.z = ''});

  final String i;
  final String z;

  String get plain => i.replaceAll('**', '');

  Set<String> get highlights {
    final out = <String>{};
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(i)) {
      for (final w in m.group(1)!.split(RegExp(r'\s+'))) {
        if (w.isNotEmpty) out.add(w.toLowerCase());
      }
    }
    return out;
  }

  factory GEx.fromJson(Map<String, dynamic> j) =>
      GEx(i: j['i'] as String? ?? '', z: j['z'] as String? ?? '');
}

List<GEx> _exs(Object? o) =>
    o is List ? [for (final x in o) GEx.fromJson(x as Map<String, dynamic>)] : const [];

sealed class GBlock {
  const GBlock();

  static GBlock fromJson(Map<String, dynamic> j) {
    switch (j['t']) {
      case 'lead':
        return GLeadBlock(j['text'] as String? ?? '');
      case 'h':
        return GHeadingBlock(j['text'] as String? ?? '');
      case 'text':
        return GTextBlock(j['text'] as String? ?? '');
      case 'steps':
        return GStepsBlock(title: j['title'] as String? ?? '', items: _strs(j['items']));
      case 'pit':
        return GPitBlock(_strs(j['items']));
      case 'table':
        return GTableBlock(
          title: j['title'] as String? ?? '',
          cols: _strs(j['cols']),
          rows: [for (final r in (j['rows'] as List? ?? [])) _strs(r)],
        );
      case 'ex':
        return GExBlock(_exs(j['items']));
      case 'vs':
        return GVsBlock(
          a: GVsSide.fromJson(j['a'] as Map<String, dynamic>? ?? const {}),
          b: GVsSide.fromJson(j['b'] as Map<String, dynamic>? ?? const {}),
          note: j['note'] as String? ?? '',
        );
      case 'words':
        return GWordsBlock(title: j['title'] as String? ?? '', list: _strs(j['list']));
      case 'tree':
        return GTreeBlock(
          q: j['q'] as String? ?? '',
          opts: [
            for (final o in (j['opts'] as List? ?? []))
              GTreeOpt.fromJson(o as Map<String, dynamic>)
          ],
        );
      default:
        return GUnknownBlock(j['t']?.toString() ?? '');
    }
  }
}

class GLeadBlock extends GBlock {
  const GLeadBlock(this.text);
  final String text;
}

class GHeadingBlock extends GBlock {
  const GHeadingBlock(this.text);
  final String text;
}

class GTextBlock extends GBlock {
  const GTextBlock(this.text);
  final String text;
}

class GStepsBlock extends GBlock {
  const GStepsBlock({this.title = '', this.items = const []});
  final String title;
  final List<String> items;
}

class GPitBlock extends GBlock {
  const GPitBlock(this.items);
  final List<String> items;
}

class GTableBlock extends GBlock {
  const GTableBlock({this.title = '', this.cols = const [], this.rows = const []});
  final String title;
  final List<String> cols;
  final List<List<String>> rows;

  bool get wide => cols.length >= 4;
}

class GExBlock extends GBlock {
  const GExBlock(this.items);
  final List<GEx> items;
}

class GVsSide {
  const GVsSide({this.title = '', this.text = '', this.ex = const []});
  final String title;
  final String text;
  final List<GEx> ex;

  factory GVsSide.fromJson(Map<String, dynamic> j) => GVsSide(
        title: j['title'] as String? ?? '',
        text: j['text'] as String? ?? '',
        ex: _exs(j['ex']),
      );
}

class GVsBlock extends GBlock {
  const GVsBlock({required this.a, required this.b, this.note = ''});
  final GVsSide a;
  final GVsSide b;
  final String note;
}

class GWordsBlock extends GBlock {
  const GWordsBlock({this.title = '', this.list = const []});
  final String title;
  final List<String> list;
}

class GTreeOptResult {
  const GTreeOptResult({this.answer = '', this.rule = '', this.examples = const []});
  final String answer;
  final String rule;
  final List<String> examples;

  factory GTreeOptResult.fromJson(Map<String, dynamic> j) => GTreeOptResult(
        answer: j['answer'] as String? ?? '',
        rule: j['rule'] as String? ?? '',
        examples: _strs(j['examples']),
      );
}

class GTreeOpt {
  const GTreeOpt({this.label = '', this.hint = '', this.result = const GTreeOptResult()});
  final String label;
  final String hint;
  final GTreeOptResult result;

  factory GTreeOpt.fromJson(Map<String, dynamic> j) => GTreeOpt(
        label: j['label'] as String? ?? '',
        hint: j['hint'] as String? ?? '',
        result: GTreeOptResult.fromJson(j['result'] as Map<String, dynamic>? ?? const {}),
      );
}

class GTreeBlock extends GBlock {
  const GTreeBlock({this.q = '', this.opts = const []});
  final String q;
  final List<GTreeOpt> opts;
}

class GUnknownBlock extends GBlock {
  const GUnknownBlock(this.t);
  final String t;
}
