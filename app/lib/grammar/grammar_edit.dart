library;

import 'dart:convert';

import 'grammar_models.dart';

const String kGScopeGrammar = 'grammar';
const String kGScopeWriting = 'writing';

const String kGKindOverride = 'override';
const String kGKindLayout = 'layout';
const String kGKindNote = 'note';
const String kGLayoutKey = '#layout';

const Map<String, String> kGBlockTypeNames = {
  'text': '段落',
  'h': '小标题',
  'lead': '结论',
  'steps': '步骤',
  'pit': '易错',
  'ex': '例句',
  'table': '表格',
  'vs': '对照',
  'words': '词表',
  'tree': '决策树',
};

const Map<String, String> kGBlockTypeHelp = {
  'text': '正文，支持 **粗体**。只存本机，不改词库。',
  'h': '小标题，进页内目录。',
  'lead': '绿底一句话结论框。',
  'steps': '每行一条；可选首行「标题：X」。',
  'pit': '每行一条，黄底提醒。',
  'ex': '每行一句；中文用 | 隔开。在句子里原样写上这个词（与词卡例句同一约定）。',
  'table': '第一行是表头，其余每行一条；单元格用 | 分隔。增删行 = 增删行；列数跟表头走。可选首行「标题：X」。',
  'vs': '[A] / [B] 起两段（行内为标题）；段内普通行 = 正文，「> 」行 = 例句（i | z）；[注] = 底部说明。',
  'words': '每行一个词库 id，可点词；可选首行「标题：X」。',
  'tree': '[问] = 问题；[选] label | hint 起一个选项；答：/ 规则：/ 例： 挂到当前选项，例可多行。',
};

String gBlockTypeOf(GBlock b) => switch (b) {
      GLeadBlock() => 'lead',
      GHeadingBlock() => 'h',
      GTextBlock() => 'text',
      GStepsBlock() => 'steps',
      GPitBlock() => 'pit',
      GTableBlock() => 'table',
      GExBlock() => 'ex',
      GVsBlock() => 'vs',
      GWordsBlock() => 'words',
      GTreeBlock() => 'tree',
      GUnknownBlock() => 'unknown',
    };

Map<String, dynamic> gBlockToJson(GBlock b) => switch (b) {
      GLeadBlock(:final text) => {'t': 'lead', 'text': text},
      GHeadingBlock(:final text) => {'t': 'h', 'text': text},
      GTextBlock(:final text) => {'t': 'text', 'text': text},
      GStepsBlock(:final title, :final items) =>
        {'t': 'steps', 'title': title, 'items': items},
      GPitBlock(:final items) => {'t': 'pit', 'items': items},
      GTableBlock(:final title, :final cols, :final rows) =>
        {'t': 'table', 'title': title, 'cols': cols, 'rows': rows},
      GExBlock(:final items) => {
          't': 'ex',
          'items': [for (final e in items) {'i': e.i, 'z': e.z}]
        },
      GVsBlock(:final a, :final b, :final note) => {
          't': 'vs',
          'a': _vsSideJson(a),
          'b': _vsSideJson(b),
          'note': note
        },
      GWordsBlock(:final title, :final list) =>
        {'t': 'words', 'title': title, 'list': list},
      GTreeBlock(:final q, :final opts) => {
          't': 'tree',
          'q': q,
          'opts': [
            for (final o in opts)
              {
                'label': o.label,
                'hint': o.hint,
                'result': {
                  'answer': o.result.answer,
                  'rule': o.result.rule,
                  'examples': o.result.examples
                }
              }
          ]
        },
      GUnknownBlock(:final t) => {'t': 'unknown', 'x': t},
    };

Map<String, dynamic> _vsSideJson(GVsSide s) => {
      'title': s.title,
      'text': s.text,
      'ex': [for (final e in s.ex) {'i': e.i, 'z': e.z}]
    };

String _fnv1a64(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String gBlockKey(GBlock b) => _fnv1a64(jsonEncode(gBlockToJson(b)));

String gBlockToText(GBlock b) {
  switch (b) {
    case GLeadBlock(:final text) ||
          GHeadingBlock(:final text) ||
          GTextBlock(:final text):
      return text;
    case GStepsBlock(:final title, :final items):
      return [if (title.isNotEmpty) '标题：$title', ...items].join('\n');
    case GPitBlock(:final items):
      return items.join('\n');
    case GExBlock(:final items):
      return [
        for (final e in items) e.z.isEmpty ? e.i : '${e.i} | ${e.z}'
      ].join('\n');
    case GTableBlock(:final title, :final cols, :final rows):
      return [
        if (title.isNotEmpty) '标题：$title',
        cols.join(' | '),
        for (final r in rows) r.join(' | ')
      ].join('\n');
    case GVsBlock(:final a, :final b, :final note):
      final out = <String>[];
      for (final (tag, s) in [('A', a), ('B', b)]) {
        out.add('[$tag] ${s.title}'.trimRight());
        if (s.text.isNotEmpty) out.add(s.text);
        for (final e in s.ex) {
          out.add('> ${e.z.isEmpty ? e.i : '${e.i} | ${e.z}'}');
        }
      }
      if (note.isNotEmpty) out.add('[注] $note');
      return out.join('\n');
    case GWordsBlock(:final title, :final list):
      return [if (title.isNotEmpty) '标题：$title', ...list].join('\n');
    case GTreeBlock(:final q, :final opts):
      final out = <String>['[问] $q'];
      for (final o in opts) {
        out.add('[选] ${o.hint.isEmpty ? o.label : '${o.label} | ${o.hint}'}');
        if (o.result.answer.isNotEmpty) out.add('答：${o.result.answer}');
        if (o.result.rule.isNotEmpty) out.add('规则：${o.result.rule}');
        for (final e in o.result.examples) {
          out.add('例：$e');
        }
      }
      return out.join('\n');
    case GUnknownBlock():
      return '';
  }
}

class GParseResult {
  const GParseResult(this.block, [this.error]);
  final GBlock? block;
  final String? error;
  bool get ok => block != null;
}

List<String> _lines(String text) =>
    [for (final l in text.split('\n')) l.trimRight()]
        .where((l) => l.trim().isNotEmpty)
        .toList();

GParseResult gParseBlock(String type, String text) {
  final ls = _lines(text);
  switch (type) {
    case 'text' || 'h' || 'lead':
      final t = text.trim();
      if (t.isEmpty) return const GParseResult(null, '内容不能为空');
      return GParseResult(switch (type) {
        'h' => GHeadingBlock(t),
        'lead' => GLeadBlock(t),
        _ => GTextBlock(t),
      });
    case 'steps':
      var title = '';
      var items = ls;
      if (ls.isNotEmpty && ls.first.startsWith('标题：')) {
        title = ls.first.substring(3).trim();
        items = ls.sublist(1);
      }
      if (items.isEmpty) return const GParseResult(null, '至少一条步骤');
      return GParseResult(GStepsBlock(title: title, items: items));
    case 'pit':
      if (ls.isEmpty) return const GParseResult(null, '至少一条提醒');
      return GParseResult(GPitBlock([
        for (final l in ls) l.startsWith('· ') ? l.substring(2) : l
      ]));
    case 'ex':
      if (ls.isEmpty) return const GParseResult(null, '至少一条例句');
      return GParseResult(GExBlock([
        for (final l in ls)
          () {
            final i = l.indexOf('|');
            return i < 0
                ? GEx(i: l.trim())
                : GEx(i: l.substring(0, i).trim(), z: l.substring(i + 1).trim());
          }()
      ]));
    case 'table':
      var title = '';
      var rest = ls;
      if (rest.isNotEmpty && rest.first.startsWith('标题：')) {
        title = rest.first.substring(3).trim();
        rest = rest.sublist(1);
      }
      if (rest.isEmpty) return const GParseResult(null, '第一行要是表头');
      final cols = [for (final c in rest.first.split('|')) c.trim()];
      if (cols.isEmpty || cols.every((c) => c.isEmpty)) {
        return const GParseResult(null, '表头不能为空');
      }
      final rows = [
        for (final l in rest.sublist(1))
          [for (final c in l.split('|')) c.trim()]
      ];
      return GParseResult(GTableBlock(title: title, cols: cols, rows: rows));
    case 'vs':
      GVsSide? a, b;
      var note = '';
      var cur = <String>[];
      var curEx = <GEx>[];
      var curTitle = '';
      var side = 0;
      void flush() {
        if (side == 0) return;
        final s = GVsSide(
            title: curTitle, text: cur.join('\n'), ex: List.of(curEx));
        if (side == 1) {
          a = s;
        } else {
          b = s;
        }
        cur = [];
        curEx = [];
      }

      for (final l in ls) {
        if (l.startsWith('[A]')) {
          flush();
          side = 1;
          curTitle = l.substring(3).trim();
        } else if (l.startsWith('[B]')) {
          flush();
          side = 2;
          curTitle = l.substring(3).trim();
        } else if (l.startsWith('[注]')) {
          flush();
          side = 0;
          note = l.substring(3).trim();
        } else if (side == 0) {
          return const GParseResult(null, '先写 [A] 段');
        } else if (l.startsWith('> ')) {
          final e = l.substring(2);
          final i = e.indexOf('|');
          curEx.add(i < 0
              ? GEx(i: e.trim())
              : GEx(i: e.substring(0, i).trim(), z: e.substring(i + 1).trim()));
        } else {
          cur.add(l);
        }
      }
      flush();
      if (a == null || b == null) return const GParseResult(null, '[A] 与 [B] 两段都要有');
      return GParseResult(GVsBlock(a: a!, b: b!, note: note));
    case 'words':
      var title = '';
      var rest = ls;
      if (rest.isNotEmpty && rest.first.startsWith('标题：')) {
        title = rest.first.substring(3).trim();
        rest = rest.sublist(1);
      }
      if (rest.isEmpty) return const GParseResult(null, '至少一个词');
      return GParseResult(
          GWordsBlock(title: title, list: [for (final l in rest) l.trim()]));
    case 'tree':
      var q = '';
      final opts = <GTreeOpt>[];
      var label = '', hint = '', answer = '', rule = '';
      var examples = <String>[];
      var has = false;
      void flush() {
        if (!has) return;
        opts.add(GTreeOpt(
            label: label,
            hint: hint,
            result: GTreeOptResult(
                answer: answer, rule: rule, examples: List.of(examples))));
        examples = [];
        answer = '';
        rule = '';
      }

      for (final l in ls) {
        if (l.startsWith('[问]')) {
          q = l.substring(3).trim();
        } else if (l.startsWith('[选]')) {
          flush();
          has = true;
          final body = l.substring(3);
          final i = body.indexOf('|');
          label = i < 0 ? body.trim() : body.substring(0, i).trim();
          hint = i < 0 ? '' : body.substring(i + 1).trim();
        } else if (!has) {
          return const GParseResult(null, '先写 [选] 选项');
        } else if (l.startsWith('答：')) {
          answer = l.substring(2).trim();
        } else if (l.startsWith('规则：')) {
          rule = l.substring(3).trim();
        } else if (l.startsWith('例：')) {
          examples.add(l.substring(2).trim());
        } else {
          return GParseResult(null, '认不出的行：$l');
        }
      }
      flush();
      if (opts.isEmpty) return const GParseResult(null, '至少一个 [选] 选项');
      return GParseResult(GTreeBlock(q: q, opts: opts));
    default:
      return const GParseResult(null, '未知块类型');
  }
}

GBlock gTemplateBlock(String type) => switch (type) {
      'lead' => const GLeadBlock(''),
      'h' => const GHeadingBlock(''),
      'steps' => const GStepsBlock(),
      'pit' => const GPitBlock([]),
      'ex' => const GExBlock([]),
      'table' => const GTableBlock(cols: ['列1', '列2'], rows: []),
      'vs' => const GVsBlock(a: GVsSide(), b: GVsSide()),
      'words' => const GWordsBlock(),
      'tree' => const GTreeBlock(),
      _ => const GTextBlock(''),
    };

class GEditRow {
  const GEditRow({
    required this.scope,
    required this.pageId,
    required this.blockKey,
    required this.kind,
    required this.payload,
    required this.ts,
  });

  final String scope;
  final String pageId;
  final String blockKey;
  final String kind;
  final String payload;
  final int ts;

  factory GEditRow.fromRow(Map<String, Object?> r) => GEditRow(
        scope: r['scope'] as String,
        pageId: r['page_id'] as String,
        blockKey: r['block_key'] as String,
        kind: r['kind'] as String,
        payload: r['payload'] as String,
        ts: (r['ts'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toRow() => {
        'scope': scope,
        'page_id': pageId,
        'block_key': blockKey,
        'kind': kind,
        'payload': payload,
        'ts': ts,
      };
}

class GEffectivePage {
  const GEffectivePage({
    required this.blocks,
    required this.keys,
    required this.added,
    required this.entries,
    required this.editedKeys,
    required this.notes,
    required this.orphans,
  });

  final List<GBlock> blocks;
  final List<String> keys;
  final List<bool> added;

  final List<Map<String, dynamic>> entries;
  final Set<String> editedKeys;
  final List<GEditRow> notes;
  final List<GEditRow> orphans;
}

GEffectivePage applyGrammarEdits(GPage page, List<GEditRow> rows) {
  final overrides = <String, GEditRow>{};
  final notes = <GEditRow>[];
  GEditRow? layout;
  for (final r in rows) {
    switch (r.kind) {
      case kGKindOverride:
        overrides[r.blockKey] = r;
      case kGKindNote:
        notes.add(r);
      case kGKindLayout:
        layout = r;
    }
  }
  notes.sort((a, b) => a.ts.compareTo(b.ts));

  final originalByKey = <String, GBlock>{
    for (final b in page.blocks) gBlockKey(b): b
  };

  final blocks = <GBlock>[];
  final keys = <String>[];
  final added = <bool>[];
  final entries = <Map<String, dynamic>>[];
  final editedKeys = <String>{};
  final usedKeys = <String>{};

  void takeOriginal(String k) {
    final orig = originalByKey[k];
    if (orig == null) return;
    usedKeys.add(k);
    final ov = overrides[k];
    if (ov != null) {
      blocks.add(GBlock.fromJson(jsonDecode(ov.payload) as Map<String, dynamic>));
      editedKeys.add(k);
    } else {
      blocks.add(orig);
    }
    keys.add(k);
    added.add(false);
    entries.add({'k': k});
  }

  void takeAdded(Map<String, dynamic> json) {
    final b = GBlock.fromJson(json);
    final k = gBlockKey(b);
    usedKeys.add(k);
    final ov = overrides[k];
    blocks.add(ov != null
        ? GBlock.fromJson(jsonDecode(ov.payload) as Map<String, dynamic>)
        : b);
    if (ov != null) editedKeys.add(k);
    keys.add(k);
    added.add(true);
    entries.add({'a': json});
  }

  if (layout != null) {
    final list = jsonDecode(layout.payload) as List;
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      if (m.containsKey('k')) {
        takeOriginal(m['k'] as String);
      } else if (m.containsKey('a')) {
        takeAdded(m['a'] as Map<String, dynamic>);
      }
    }
  } else {
    for (final b in page.blocks) {
      takeOriginal(gBlockKey(b));
    }
  }

  final orphans = [
    for (final r in overrides.values)
      if (!usedKeys.contains(r.blockKey)) r
  ]..sort((a, b) => a.ts.compareTo(b.ts));

  return GEffectivePage(
    blocks: blocks,
    keys: keys,
    added: added,
    entries: entries,
    editedKeys: editedKeys,
    notes: notes,
    orphans: orphans,
  );
}

String gNotePayload(String text) => jsonEncode({'text': text});
String gNoteText(String payload) =>
    (jsonDecode(payload) as Map<String, dynamic>)['text'] as String? ?? '';