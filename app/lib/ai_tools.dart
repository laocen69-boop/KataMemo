library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'activity_log.dart';
import 'version.dart' show kKbbiLocal;
import 'ai_chat.dart';
import 'ai_search.dart';
import 'app_state.dart';
import 'dict_import/dict_model.dart' show dictFold;
import 'dict_import/dict_store.dart';
import 'db.dart' show TodayPlanX;
import 'grammar/grammar_models.dart' show GPage;
import 'grammar/grammar_repo.dart' show GrammarRepo;
import 'models.dart';
import 'screens/ai_settings_screen.dart' show AiSettingsScreen;
import 'screens/favorites_screen.dart';
import 'screens/grammar/grammar_hub_screen.dart';
import 'screens/grammar/grammar_page_screen.dart' show openGrammarPage;
import 'screens/my_words_screen.dart' show MyScreen;
import 'screens/scan_screen.dart';
import 'screens/search_screen.dart';
import 'screens/select_screen.dart' show WordListDetailScreen;
import 'screens/settings_screen.dart';
import 'screens/word_detail_screen.dart';

enum AiToolKind { read, write, nav }

class AiPendingAction {
  final String title;
  final List<String> lines;
  final String confirmLabel;
  const AiPendingAction(this.title, this.lines, {this.confirmLabel = '同意'});
}

class AiNavAction {
  final String label;
  final bool closeSheet;
  final void Function(BuildContext context) go;
  const AiNavAction(this.label, this.go, {this.closeSheet = false});
}

class AiToolOutcome {
  final String result;
  final String label;
  final AiNavAction? nav;

  final List<AiPlanStep>? plan;
  const AiToolOutcome(this.result, this.label, {this.nav, this.plan});
}

class AiPlanStep {
  final String text;
  final String status;
  const AiPlanStep(this.text, this.status);

  bool get done => status == 'done';
}

String aiPlanText(List<AiPlanStep> plan) => [
      for (final (i, s) in plan.indexed)
        '${i + 1}. [${s.done ? '✓' : s.status == 'doing' ? '进行中' : ' '}] ${s.text}',
    ].join('\n');

const kTaskPlanMaxSteps = 20;

List<AiPlanStep> aiParsePlan(Object? steps) {
  if (steps is! List) return const [];
  final out = <AiPlanStep>[];
  for (final s in steps.take(kTaskPlanMaxSteps)) {
    if (s is String && s.trim().isNotEmpty) {
      out.add(AiPlanStep(s.trim(), 'pending'));
    } else if (s is Map) {
      final t = '${s['text'] ?? s['step'] ?? ''}'.trim();
      if (t.isEmpty) continue;
      final st = '${s['status'] ?? ''}';
      out.add(AiPlanStep(_cut(t, 60), const {'done', 'doing'}.contains(st) ? st : 'pending'));
    }
  }
  return out;
}

class AiHomeTabs {
  AiHomeTabs._();
  static void Function(int index)? select;
}

typedef AiConfirm = Future<bool> Function(AiPendingAction action);

Map<String, Object?> _obj(Map<String, Object?> props, [List<String> req = const []]) =>
    {'type': 'object', 'properties': props, 'required': req};
const _str = {'type': 'string'};
Map<String, Object?> _strDesc(String d) => {'type': 'string', 'description': d};
Map<String, Object?> _intDesc(String d) => {'type': 'integer', 'description': d};
const _ids = {
  'type': 'array',
  'items': _str,
  'description': '单词 id 列表（从 search_words / today_mistakes 等工具的结果里取）',
};

List<(AiToolKind, AiToolSpec)> get kAiToolSpecs => [
      (
        AiToolKind.read,
        AiToolSpec('task_plan',
            '写下或更新本次任务的步骤清单（多步任务开头调一次，每做完一步再调一次改状态）。'
                '清单会显示给学生，并一直留在你的上下文里。每次都传完整清单。',
            _obj({
              'steps': {
                'type': 'array',
                'description': '3–20 步，每步一句话',
                'items': _obj({
                  'text': _strDesc('这一步做什么'),
                  'status': {
                    'type': 'string',
                    'enum': ['pending', 'doing', 'done'],
                  },
                }, ['text', 'status']),
              },
            }, ['steps'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec(
            'save_learning_memory',
            '记录或更新学生的长期学习记忆（学习目标、讲解偏好、反复混淆的印尼语薄弱点）。'
                '仅在学生明确提出长期偏好或反复出现同一类错误时调用；传更新后的完整精简文本（500 字以内），'
                '不要记一次性查词记录。',
            _obj({'memory': _strDesc('更新后的完整学习记忆（500 字以内；传空串可清空）')}, ['memory'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec('search_words',
            '在 App 词库里查词（印尼语或中文都行），返回 id、词形、中文、词性、是否已加入记忆。'
                '查一个用 query；一次查多个用 queries（最多 30 个，比逐个调用快）。',
            _obj({
              'query': _strDesc('要查的词或中文'),
              'queries': {
                'type': 'array',
                'items': _str,
                'description': '一次查多个词（最多 30 个），每个只返回最匹配的几条',
              },
              'limit': _intDesc('每个词最多返回几个，默认 8（用 queries 时默认 3），上限 30'),
            })),
      ),
      (
        AiToolKind.read,
        AiToolSpec('get_word',
            '取单词卡片：${kKbbiLocal ? 'KBBI 释义、' : '中文释义、'}例句、助记、派生词、复习次数。一个用 id；多个用 ids（最多 30 个，内容会精简）。',
            _obj({
              'id': _strDesc('单词 id'),
              'ids': {'type': 'array', 'items': _str, 'description': '一次取多张卡（最多 30 个）'},
            })),
      ),
      (
        AiToolKind.read,
        AiToolSpec('today_overview', '今天的学习概况：今日卡量、已完成、剩余任务、今天碰过的词数、四档评分分布（轻松/记得/模糊/困难）。',
            _obj({})),
      ),
      (
        AiToolKind.read,
        AiToolSpec('today_mistakes', '最近几天学习时答「困难/模糊」的词（错词），按出错次数排序。',
            _obj({'days': _intDesc('往前看几天，默认 1 = 今天，上限 7')})),
      ),
      (
        AiToolKind.read,
        AiToolSpec('recent_searches', '最近几天在搜索页搜过的词（已对上词库的带 id）。',
            _obj({'days': _intDesc('往前看几天，默认 1 = 今天，上限 7')})),
      ),
      (
        AiToolKind.read,
        AiToolSpec('grammar_mistakes', '最近几天语法练习里做错的题：题干、选了什么、正确答案、讲解、所属语法页。',
            _obj({'days': _intDesc('往前看几天，默认 1 = 今天，上限 7')})),
      ),
      (
        AiToolKind.read,
        AiToolSpec('list_word_lists', '列出学生自己建的词单（id、名字、词数）。', _obj({})),
      ),
      (
        AiToolKind.read,
        AiToolSpec('word_list_words', '取一个词单里的词（一次最多 100 个，用 offset 往后翻）。',
            _obj({
              'list_id': _intDesc('词单 id'),
              'offset': _intDesc('从第几个开始，默认 0'),
              'limit': _intDesc('取几个，默认 100，上限 200'),
            }, ['list_id'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec('search_grammar', '在 App 的语法讲解页里找相关页面（返回页 id、标题、摘要）。',
            _obj({'query': _strDesc('语法点，如「被动」「me-」「yang」')}, ['query'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec(
            'indonesian_reference',
            '印尼语专业语法参考资料${kKbbiLocal ? '（含 KBBI 词典参考）' : ''}。讲词缀变体与例外、语态与被动、-kan/-i、'
                '时体情态、句法语序、小品词与语域、近义词与借词、规范用法与常见误用之前先查它，不要凭印象编规则。'
                '查单个问题用 topic；学生一次问了多个问题或语法点时，先拆成独立子问题放进 topics 一次查完。',
            _obj({
              'topic': _strDesc('学生问的词、词组或语法点（如 hang dang、tangan kotor、sirup、berhias diri、被动），'
                  '也可以从下列主题名里选：${kIndoReference.keys.join('、')}'),
              'topics': {
                'type': 'array',
                'items': _str,
                'description': '学生一次问多个问题时，拆成多个独立查询词放这里一次批量检索',
              },
            })),
      ),
      (
        AiToolKind.read,
        AiToolSpec(
            kLocalDictTool,
            '查学生自己导入的本地词典（老师的词表、KBBI 等）。**只在学生开启「允许问 AI 参考本地词典」后才会出现**。'
                '每次最多查 15 个词；结果里 authority=kbbi 的是 KBBI 词典，释义以它为准，'
                '其余导入词典并列列出、各注明出处。查不到就如实说没有，不要编造。',
            _obj({
              'words': {
                'type': 'array',
                'items': _str,
                'description': '要查的印尼语词，最多 15 个',
              },
            }, ['words'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec(
            kWebSearchTool,
            '联网搜索网页（只有学生在设置里配置了搜索服务才会出现）。**只在知识库、${kKbbiLocal ? 'KBBI ' : ''}词库都没有答案时用**，'
                '或学生明确要查最新信息、网络用法、俚语、新词'
                '${kKbbiLocal ? '' : '，以及查询 KBBI 官网（kbbi.kemendikdasmen.go.id）或国内镜像（kbbi.web.id，当本地导入的 KBBI 未命中时）'}。'
                '一轮回答最多搜 2 次；搜索词要具体，印尼语词配上「arti」「artinya」之类。'
                '结果只是网页摘要，只能作参考：回答里要写出处网址，说明没有经过词典核实。',
            _obj({'query': _strDesc('搜索词，128 字以内'), 'count': _intDesc('要几条，默认 5，上限 8')}, ['query'])),
      ),
      (
        AiToolKind.read,
        AiToolSpec('app_guide', 'App 使用说明。学生问「怎么用 / 在哪里 / 能不能」时先查它。不传 topic 返回全部主题。',
            _obj({'topic': _strDesc('主题：${kAppGuide.keys.join('、')}')})),
      ),
      (
        AiToolKind.write,
        AiToolSpec('add_to_memory', '把词加入记忆（之后会出现在学习页）。会先请学生确认。',
            _obj({'ids': _ids}, ['ids'])),
      ),
      (
        AiToolKind.write,
        AiToolSpec('create_word_list', '新建一个词单（待学清单，不影响学习进度）。会先请学生确认。',
            _obj({'name': _strDesc('词单名'), 'ids': _ids}, ['name', 'ids'])),
      ),
      (
        AiToolKind.write,
        AiToolSpec('add_to_word_list', '往已有词单里追加词。会先请学生确认。',
            _obj({'list_id': _intDesc('词单 id'), 'ids': _ids}, ['list_id', 'ids'])),
      ),
      (
        AiToolKind.write,
        AiToolSpec('save_mnemonic', '把一段助记存到某个词的卡片上（已有助记时接在后面）。会先请学生确认。',
            _obj({'id': _strDesc('单词 id'), 'text': _strDesc('助记内容，60 字以内为宜')}, ['id', 'text'])),
      ),
      (
        AiToolKind.write,
        AiToolSpec('set_daily_quota', '修改今日卡量（复习 + 新词一共几张）。会先请学生确认。',
            _obj({'quota': _intDesc('新的卡量，0–9999')}, ['quota'])),
      ),
      (
        AiToolKind.nav,
        AiToolSpec('open_word', '回答结束后打开某个词的详情页。', _obj({'id': _strDesc('单词 id')}, ['id'])),
      ),
      (
        AiToolKind.nav,
        AiToolSpec('open_grammar_page', '回答结束后打开某个语法讲解页。',
            _obj({'id': _strDesc('语法页 id（search_grammar 的结果）')}, ['id'])),
      ),
      (
        AiToolKind.nav,
        AiToolSpec('open_word_list', '回答结束后打开某个词单。', _obj({'list_id': _intDesc('词单 id')}, ['list_id'])),
      ),
      (
        AiToolKind.nav,
        AiToolSpec(
            'open_screen',
            '回答结束后打开 App 的某个页面。',
            _obj({
              'screen': {
                'type': 'string',
                'enum': _kScreens.keys.toList(),
                'description': _kScreens.entries.map((e) => '${e.key}=${e.value}').join('，'),
              },
            }, ['screen'])),
      ),
    ];

const Map<String, String> _kScreens = {
  'study': '学习 Tab',
  'library': '词库 Tab',
  'grammar': '语法 Tab',
  'stats': '统计 Tab',
  'profile': '我的 Tab',
  'search': '搜索页',
  'scan': '拍照抓词',
  'my_cards': '自建卡片与词单',
  'favorites': '我的收藏',
  'writing': '写作',
  'settings': '设置',
  'ai_settings': 'AI 设置',
};

const String kWebSearchTool = 'web_search';
const String kLearningMemoryTool = 'save_learning_memory';

List<AiToolSpec> get kAiToolSpecList => [for (final (_, s) in kAiToolSpecs) s];

List<AiToolSpec> aiToolSpecsFor(AppState app) => [
      for (final (_, s) in kAiToolSpecs)
        if ((s.name != kLocalDictTool || app.aiLocalDictOn) &&
            (s.name != kWebSearchTool || app.aiSearchReady) &&
            (s.name != kLearningMemoryTool || app.aiMemoryEnabled))
          s,
    ];

AiToolKind? aiToolKind(String name) {
  for (final (k, s) in kAiToolSpecs) {
    if (s.name == name) return k;
  }
  return null;
}

String _j(Object? v) => jsonEncode(v);

const kLocalDictTool = 'local_dictionary';

const kLocalDictMaxWords = 15;

const kSearchWordsMaxQueries = 30;

const kGetWordMaxIds = 30;

const kReferenceMaxHits = 3;

final _latinWord = RegExp(r'^[A-Za-z-]+$');
final _latinTokens = RegExp(r'[A-Za-z-]+');
final _cjkRun = RegExp(r'[\u4e00-\u9fff]+');
final _cjk2 = RegExp(r'^[\u4e00-\u9fff]{1,2}$');
const _cjkStop2 = {
  '什么', '怎么', '为什', '可以', '还是', '哪个', '哪些', '意思', '区别', '使用', '用法', '句子', '这句', '印尼', '尼语'
};

Set<String> indonesianStem(String word) {
  final w = word.toLowerCase().trim();
  final out = <String>{if (w.length >= 3) w};
  if (w.length < 4 || !_latinWord.hasMatch(w)) return out;
  if (w == 'belajar' || w == 'pelajar' || w == 'pelajaran') out.add('ajar');
  if (w == 'bekerja' || w == 'pekerja' || w == 'pekerjaan') out.add('kerja');
  if (w.contains('tanggungjawab')) {
    out.addAll(['tanggung', 'jawab']);
  }

  String stripParticles(String s) {
    for (final p in const ['lah', 'kah', 'tah', 'pun']) {
      if (s.endsWith(p) && s.length - p.length >= 4) {
        s = s.substring(0, s.length - p.length);
        break;
      }
    }
    for (final p in const ['nya', 'ku', 'mu']) {
      if (s.endsWith(p) && s.length - p.length >= 4) {
        s = s.substring(0, s.length - p.length);
        break;
      }
    }
    return s;
  }

  List<String> stripSuffixes(String s) {
    final res = <String>{s};
    final p = stripParticles(s);
    res.add(p);
    for (final base in [s, p]) {
      for (final suf in const ['kan', 'an', 'i']) {
        if (base.endsWith(suf) && base.length - suf.length >= 3) {
          final sub = base.substring(0, base.length - suf.length);
          res.add(sub);
          if (suf == 'kan' && sub.endsWith('i') && sub.length - 1 >= 3) {
            res.add(sub.substring(0, sub.length - 1));
          }
        }
      }
    }
    return res.toList();
  }

  const vowels = {'a', 'e', 'i', 'o', 'u'};
  void stripPrefix(String s) {
    if (s.length >= 3) out.add(s);
    for (final pre in const ['memper', 'diper', 'keber']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        out.add(s.substring(pre.length));
      }
    }
    for (final pre in const ['menge', 'penge']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        out.add(s.substring(pre.length));
      }
    }
    for (final pre in const ['meny', 'peny']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        final rest = s.substring(pre.length);
        out.add(rest);
        if (vowels.contains(rest[0])) out.add('s$rest');
      }
    }
    for (final pre in const ['mem', 'pem']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        final rest = s.substring(pre.length);
        out.add(rest);
        if (vowels.contains(rest[0])) out.add('p$rest');
      }
    }
    for (final pre in const ['men', 'pen']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        final rest = s.substring(pre.length);
        out.add(rest);
        if (vowels.contains(rest[0])) out.add('t$rest');
      }
    }
    for (final pre in const ['meng', 'peng']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        final rest = s.substring(pre.length);
        out.add(rest);
        if (vowels.contains(rest[0])) out.add('k$rest');
      }
    }
    for (final pre in const ['me', 'pe', 'di', 'ter', 'ber', 'per', 'ke', 'se']) {
      if (s.startsWith(pre) && s.length - pre.length >= 3) {
        out.add(s.substring(pre.length));
      }
    }
  }

  for (final cand in stripSuffixes(w)) {
    stripPrefix(cand);
  }
  return out.where((s) => s.length >= 3).toSet();
}

bool referenceWordIn(String w, String topic) {
  if (!_latinWord.hasMatch(w)) return topic.contains(w);
  final lw = w.toLowerCase();
  return _latinTokens.allMatches(topic).any((m) => m.group(0)!.toLowerCase() == lw);
}

bool _queryHasSpecific(String topic) =>
    _latinTokens.allMatches(topic).any((m) => m.group(0)!.length >= 3) ||
    _cjkRun.allMatches(topic).any((m) => m.group(0)!.length >= 3);

bool referenceKeyWordIn(String w, String topic) {
  if (w == 'TBBBI') return false;
  if (_queryHasSpecific(topic) &&
      ((_latinWord.hasMatch(w) && w.length <= 2) || _cjk2.hasMatch(w))) {
    return false;
  }
  return referenceWordIn(w, topic);
}

Map<String, double> _referenceQueryTerms(String topic) {
  final terms = <String, double>{};
  void put(String k, double w) {
    if (k.isEmpty) return;
    final prev = terms[k];
    if (prev == null || w > prev) terms[k] = w;
  }

  for (final m in _latinTokens.allMatches(topic.toLowerCase())) {
    final w = m.group(0)!;
    if (w.length >= 3) {
      put(w, 1.0);
      for (final st in indonesianStem(w)) {
        if (st != w && st.length >= 3) put(st, 0.65);
      }
    }
  }
  for (final m in _cjkRun.allMatches(topic)) {
    final s = m.group(0)!;
    if (s.length >= 2 && s.length <= 4 && !_cjkStop2.contains(s)) {
      put(s, 1.1);
    }
    for (var i = 0; i + 2 <= s.length; i++) {
      final bg = s.substring(i, i + 2);
      if (!_cjkStop2.contains(bg)) put(bg, 0.8);
    }
  }
  return terms;
}

Map<String, double> referenceBm25Scores(
  String topic, [
  Iterable<String>? candidateKeys,
]) {
  final terms = _referenceQueryTerms(topic);
  if (terms.isEmpty || kIndoReference.isEmpty) return const {};
  final allEntries = kIndoReference.entries.toList();
  final nDocs = allEntries.length;
  var totalLen = 0;
  final docText = <String, String>{};
  final metaText = <String, String>{};
  for (final e in allEntries) {
    final t = e.value.toLowerCase();
    final tr = (kIndoReferenceTriggers[e.key] ?? const <String>[]).join(' ').toLowerCase();
    docText[e.key] = t;
    metaText[e.key] = '${e.key.toLowerCase()} $tr';
    totalLen += t.length;
  }
  final avgdl = totalLen / nDocs;
  const k1 = 1.5;
  const b = 0.75;

  final idf = <String, double>{};
  for (final term in terms.keys) {
    var df = 0;
    for (final e in allEntries) {
      if (docText[e.key]!.contains(term) || metaText[e.key]!.contains(term)) {
        df++;
      }
    }
    if (df > 0) {
      idf[term] = math.log(1.0 + (nDocs - df + 0.5) / (df + 0.5));
    }
  }

  final keys = candidateKeys ?? kIndoReference.keys;
  final scores = <String, double>{};
  for (final k in keys) {
    final body = docText[k];
    final meta = metaText[k];
    if (body == null || meta == null) continue;
    final dl = body.length;
    var score = 0.0;
    for (final entry in terms.entries) {
      final term = entry.key;
      final termIdf = idf[term];
      if (termIdf == null) continue;
      final bodyTf = term.allMatches(body).length;
      final metaTf = term.allMatches(meta).length;
      final tf = bodyTf + metaTf * 2.5;
      if (tf <= 0) continue;
      final tfNorm = (tf * (k1 + 1.0)) / (tf + k1 * (1.0 - b + b * (dl / avgdl)));
      score += entry.value * termIdf * tfNorm;
    }
    if (score > 0) scores[k] = score;
  }
  return scores;
}

List<MapEntry<String, String>> referenceFullText(String topic) {
  final words = topic
      .toLowerCase()
      .split(RegExp(r'[\s,，、/?？。.!！:：;；…]+'))
      .where((w) => RegExp(r'^[\x00-\x7f]+$').hasMatch(w) ? w.length >= 3 : w.length >= 2)
      .toSet();
  final bm25 = referenceBm25Scores(topic);
  final scored = <(MapEntry<String, String>, int, int, double, int)>[];
  var i = 0;
  for (final e in kIndoReference.entries) {
    final text = e.value.toLowerCase();
    var n = 0, times = 0;
    for (final w in words) {
      final c = w.allMatches(text).length;
      if (c > 0) n++;
      times += c;
    }
    final bScore = bm25[e.key] ?? 0.0;
    if (n > 0 || bScore > 0) {
      scored.add((e, n, times, bScore, i));
    }
    i++;
  }
  if (scored.isEmpty) return [];
  scored.sort((a, b) {
    if (a.$2 != b.$2) return b.$2 - a.$2;
    if (a.$2 > 0 && a.$3 != b.$3) return b.$3 - a.$3;
    if ((b.$4 - a.$4).abs() > 1e-6) return b.$4 > a.$4 ? 1 : -1;
    return a.$5 - b.$5;
  });
  final bestN = scored.first.$2;
  if (bestN > 0) {
    return [for (final s in scored.where((s) => s.$2 == bestN).take(2)) s.$1];
  }
  return [for (final s in scored.take(2)) s.$1];
}

List<MapEntry<String, String>> referenceHitsFor(String topic) {
  final exact = kIndoReference[topic];
  if (exact != null) return [MapEntry(topic, exact)];
  var hit = kIndoReference.entries
      .where((e) =>
          topic.isNotEmpty &&
          (e.key.contains(topic) ||
              e.key.split(' ').any((w) => referenceKeyWordIn(w, topic)) ||
              (kIndoReferenceTriggers[e.key] ?? const <String>[])
                  .any((w) => referenceWordIn(w, topic))))
      .toList();
  if (hit.isEmpty) return referenceFullText(topic);

  if (hit.length > kReferenceMaxHits && _queryHasSpecific(topic)) {
    final bm25 = referenceBm25Scores(topic, [for (final e in hit) e.key]);
    final indexed = [for (var i = 0; i < hit.length; i++) (hit[i], bm25[hit[i].key] ?? 0.0, i)];
    indexed.sort((a, b) =>
        (b.$2 - a.$2).abs() > 1e-6 ? (b.$2 > a.$2 ? 1 : -1) : a.$3 - b.$3);
    return [for (final x in indexed.take(kReferenceMaxHits)) x.$1];
  }
  return hit;
}

String sliceReferenceText(String rawText, String topic, int maxChars) {
  final clean = sanitizeReferenceText(rawText);
  if (clean.length <= maxChars) return clean;
  final parts = clean
      .split(RegExp(r'(?<=[。！？；\n])'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length <= 1) return _cut(clean, maxChars);
  final terms = _referenceQueryTerms(topic);
  final scored = <(int idx, double score, String text)>[];
  for (var i = 1; i < parts.length; i++) {
    final pLow = parts[i].toLowerCase();
    var sc = 0.0;
    for (final e in terms.entries) {
      if (pLow.contains(e.key)) sc += e.value * 2.0;
    }
    scored.add((i, sc, parts[i]));
  }
  scored.sort((a, b) =>
      (b.$2 - a.$2).abs() > 1e-6 ? (b.$2 > a.$2 ? 1 : -1) : a.$1 - b.$1);
  final chosen = <int>{0};
  var used = parts[0].length;
  for (final s in scored) {
    if (used + s.$3.length + 1 > maxChars) continue;
    chosen.add(s.$1);
    used += s.$3.length + 1;
  }
  final ordered = chosen.toList()..sort();
  return [for (final idx in ordered) parts[idx]].join();
}

String sanitizeReferenceText(String text) {
  var out = text;

  out = out.replaceAllMapped(RegExp(r'依据：[^。\n]*[。\n]?'), (m) {
    final s = m.group(0)!;
    return s.contains('KBBI') ? '依据：KBBI。' : '';
  });

  out = out.replaceAll(RegExp(r'（TBBBI[^）]*）'), '');
  out = out.replaceAll(RegExp(r'（§[\d.\–\-]+[^）]*）'), '');

  out = out.replaceAll(RegExp(r'TBBBI\s*第[一二三四五六七八九十\d]+章(?:\s*§[\d.\–\-]+)?'), '印尼语规范语法');
  out = out.replaceAll(RegExp(r'TBBBI\s*§[\d.\–\-]+(?:\s*[A-Za-z ]+)?'), '印尼语规范语法');
  out = out.replaceAll('TBBBI', '印尼语规范语法');
  out = out.replaceAll(
      RegExp(r'Kridalaksana dkk\.?\s*\d{4}《Tata Bahasa[^》]*》[^。；\n]*'), '印尼语语法规范');
  out = out.replaceAll(RegExp(r'Tata Bahasa[^。；\n]*'), '印尼语语法规范');
  out = out.replaceAll('morphology.md', '构词规范');
  return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

String _cut(String? s, int n) {
  final t = (s ?? '').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

int _clampInt(Object? v, int def, int lo, int hi) {
  final n = v is num ? v.toInt() : int.tryParse('$v') ?? def;
  return n.clamp(lo, hi);
}

List<String> _idList(Object? v) => [
      if (v is List)
        for (final e in v)
          if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];

DateTime _dayStart(int daysBack) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).subtract(Duration(days: daysBack - 1));
}

class AiToolbox {
  final AppState app;
  AiToolbox(this.app);

  Future<Set<String>> _inMemory(List<String> ids) async {
    if (ids.isEmpty) return {};
    final d = await app.db.db;
    final q = List.filled(ids.length, '?').join(',');
    final rows = await d.rawQuery(
        'SELECT card_id FROM plan WHERE card_id IN ($q) '
        'UNION SELECT card_id FROM srs WHERE card_id IN ($q)',
        [...ids, ...ids]);
    return {for (final r in rows) r['card_id'] as String};
  }

  Future<WordCard?> _card(String id) async =>
      await app.db.getWord(id) ?? await app.db.searchWords(id);

  Future<List<WordCard>> _cards(List<String> ids) async {
    final out = <WordCard>[];
    for (final id in ids.take(500)) {
      final c = await _card(id);
      if (c != null && !out.any((x) => x.id == c.id)) out.add(c);
    }
    return out;
  }

  Map<String, Object?> _brief(WordCard c, {bool? inMemory}) => {
        'id': c.id,
        'word': c.word,
        'zh': _cut(c.zhClean, 60),
        if (c.wordClassLabelsCombined.isNotEmpty) 'pos': c.wordClassLabelsCombined,
        if (inMemory != null) 'in_memory': inMemory,
      };

  List<String> _preview(List<WordCard> cs, {int max = 8}) => [
        for (final c in cs.take(max)) '${c.word}  ${_cut(c.zhClean, 18)}',
        if (cs.length > max) '……共 ${cs.length} 个',
      ];

  Future<AiToolOutcome> run(AiToolCall call, {required AiConfirm confirm}) async {
    final a = call.argMap;
    try {
      switch (call.name) {
        case 'task_plan':
          final plan = aiParsePlan(a['steps']);
          if (plan.isEmpty) return AiToolOutcome(_j({'error': '缺少 steps'}), '任务清单：没写步骤');
          final done = plan.where((s) => s.done).length;
          return AiToolOutcome(_j({'ok': true, 'steps': plan.length, 'done': done}),
              '任务清单：$done/${plan.length} 步', plan: plan);

        case 'save_learning_memory':
          if (!app.aiMemoryEnabled) {
            return AiToolOutcome(_j({'ok': false, 'disabled': true}), '学习记忆已关闭，未写入');
          }
          final m = aiClipMemory('${a['memory'] ?? ''}');
          await app.setAiLearningMemory(m);
          return AiToolOutcome(
              _j({'ok': true, 'chars': m.length, 'memory': m}),
              m.isEmpty ? '学习记忆：已清空' : '已记下学习偏好（${m.length} 字）');

        case 'search_words':
          final qs = <String>{
            for (final q in _idList(a['queries']).take(kSearchWordsMaxQueries)) q,
            if ('${a['query'] ?? ''}'.trim().isNotEmpty) '${a['query']}'.trim(),
          }.toList();
          if (qs.isEmpty) return AiToolOutcome(_j({'error': '缺少 query'}), '查词：没给词');
          if (qs.length == 1) {
            final q = qs.single;
            final cs = await app.db.searchAll(q, limit: _clampInt(a['limit'], 8, 1, 30));
            final mem = await _inMemory([for (final c in cs) c.id]);
            return AiToolOutcome(
                _j({'results': [for (final c in cs) _brief(c, inMemory: mem.contains(c.id))]}),
                '查了词库：$q（${cs.length} 个）');
          }
          final per = _clampInt(a['limit'], 3, 1, 10);
          final found = <String, List<WordCard>>{};
          for (final q in qs) {
            found[q] = await app.db.searchAll(q, limit: per);
          }
          final mem = await _inMemory([for (final l in found.values) for (final c in l) c.id]);
          return AiToolOutcome(
              _j({
                'results': {
                  for (final e in found.entries)
                    e.key: [for (final c in e.value) _brief(c, inMemory: mem.contains(c.id))],
                },
              }),
              '查了词库：${_cut(qs.join('、'), 24)}（${qs.length} 个词）');

        case 'get_word' when _idList(a['ids']).isNotEmpty:
          final reqIds = _idList(a['ids']).take(kGetWordMaxIds).toList();
          final cs = await _cards(reqIds);
          final mem = await _inMemory([for (final c in cs) c.id]);
          return AiToolOutcome(
              _j({
                'cards': [
                  for (final c in cs)
                    {
                      ..._brief(c, inMemory: mem.contains(c.id)),
                      if (kKbbiLocal) 'kbbi': [
                        for (final s in c.senses.take(2)) {'pos': s.pos, 'def': _cut(s.def, 100)},
                      ],
                      'examples': [
                        for (final e in c.examples.take(1)) {'id': e.text, 'zh': e.zh},
                      ],
                      if (c.mnemonicShown != null) 'mnemonic': _cut(c.mnemonicShown, 80),
                    },
                ],
                if (cs.length < reqIds.length) 'note': '有的 id 在词库里没找到',
              }),
              '看了 ${cs.length} 张卡片');

        case 'get_word':
          final c = await _card('${a['id'] ?? ''}');
          if (c == null) return AiToolOutcome(_j({'error': '词库里没有这个词'}), '查卡片：没找到');
          final srs = await app.db.getSrs(c.id);
          final mem = await _inMemory([c.id]);
          return AiToolOutcome(
              _j({
                ..._brief(c, inMemory: mem.contains(c.id)),
                if (c.phonetic != null) 'phonetic': c.phonetic,
                if (kKbbiLocal) 'kbbi': [
                  for (final s in c.senses.take(4)) {'pos': s.pos, 'def': _cut(s.def, 160)},
                ],
                'examples': [
                  for (final e in c.examples.take(3)) {'id': e.text, 'zh': e.zh},
                ],
                if (c.mnemonicShown != null) 'mnemonic': _cut(c.mnemonicShown, 200),
                'derived': [
                  for (final d in c.derivations.take(8)) {'form': d.form, 'zh': d.gloss},
                ],
                'reviews': srs?.reps ?? 0,
                'lapses': srs?.lapses ?? 0,
              }),
              '看了卡片：${c.word}');

        case 'today_overview':
          final p = await app.db.todayPlan(dailyQuota: app.dailyQuota);
          final ds = await app.db.dayStatsAt(DateTime.now());
          return AiToolOutcome(
              _j({
                'daily_quota': app.dailyQuota,
                'finished_today': p.finished,
                'tasks_left': p.taskLeft,
                'review_today': p.reviewShown,
                'new_today': p.newPlan,
                'new_words_waiting': p.poolLeft,
                'words_touched': ds.words,
                'answers': ds.answers,
                'first_try': {
                  'easy': ds.easy,
                  'know': ds.know,
                  'fuzzy': ds.fuzzy,
                  'forget': ds.forget
                },
              }),
              '看了今天的学习概况');

        case 'today_mistakes':
          final days = _clampInt(a['days'], 1, 1, 7);
          final d = await app.db.db;
          final rows = await d.rawQuery(
              'SELECT w.id AS id, w.word AS word, w.zh AS zh, '
              'SUM(CASE WHEN l.rating <= 1 THEN 1 ELSE 0 END) AS bad, COUNT(*) AS n '
              'FROM study_log l JOIN words w ON w.id = l.card_id WHERE l.ts >= ? '
              'GROUP BY l.card_id HAVING bad > 0 ORDER BY bad DESC, n DESC LIMIT 60',
              [_dayStart(days).millisecondsSinceEpoch]);
          return AiToolOutcome(
              _j({
                'days': days,
                'words': [
                  for (final r in rows)
                    {
                      'id': r['id'],
                      'word': r['word'],
                      'zh': _cut(r['zh'] as String?, 40),
                      'wrong_times': r['bad'],
                      'answers': r['n'],
                    },
                ],
              }),
              '看了${days == 1 ? '今天' : '最近 $days 天'}的错词（${rows.length} 个）');

        case 'recent_searches':
          final days = _clampInt(a['days'], 1, 1, 7);
          final terms = await searchesSince(app.db, _dayStart(days));
          final found = <Map<String, Object?>>[];
          final missing = <String>[];
          for (final t in terms.take(80)) {
            final c = await app.db.searchWords(t);
            if (c == null) {
              missing.add(t);
            } else if (!found.any((f) => f['id'] == c.id)) {
              found.add(_brief(c));
            }
          }
          return AiToolOutcome(
              _j({'days': days, 'words': found, 'not_in_dictionary': missing}),
              '看了${days == 1 ? '今天' : '最近 $days 天'}搜过的词（${terms.length} 个）');

        case 'grammar_mistakes':
          final days = _clampInt(a['days'], 1, 1, 7);
          await app.db.flushGrammarWrites();
          final rows = await grammarWrongSince(app.db, _dayStart(days));
          String opt(Map r, String k) {
            final os = (r['opts'] as List?) ?? const [];
            final i = (r[k] as num?)?.toInt() ?? -1;
            return i >= 0 && i < os.length ? '${os[i]}' : '';
          }
          return AiToolOutcome(
              _j({
                'days': days,
                'mistakes': [
                  for (final r in rows.take(40))
                    {
                      'page_id': r['page'],
                      'page': app.grammar.pageById['${r['page']}']?.title ?? '',
                      'question': r['q'],
                      'picked': opt(r, 'pick'),
                      'correct': opt(r, 'ans'),
                      'why': _cut(r['why'] as String?, 200),
                    },
                ],
              }),
              '看了${days == 1 ? '今天' : '最近 $days 天'}的语法错题（${rows.length} 道）');

        case 'list_word_lists':
          final ls = await app.db.listWordLists();
          return AiToolOutcome(
              _j({
                'lists': [for (final (id, name, n) in ls) {'id': id, 'name': name, 'count': n}],
              }),
              '看了词单（${ls.length} 个）');

        case 'word_list_words':
          final id = _clampInt(a['list_id'], -1, -1, 1 << 30);
          final ids = await app.db.wordListIds(id);
          final off = _clampInt(a['offset'], 0, 0, 1 << 20);
          final lim = _clampInt(a['limit'], 100, 1, 200);
          final cs = await _cards(ids.skip(off).take(lim).toList());
          final more = off + lim < ids.length;
          return AiToolOutcome(
              _j({
                'count': ids.length,
                'offset': off,
                'words': [for (final c in cs) _brief(c)],
                if (more) 'next_offset': off + lim,
              }),
              '看了词单里的词（${ids.length} 个${off > 0 ? '，从第 ${off + 1} 个起' : ''}）');

        case 'search_grammar':
          final rawQ = '${a['query'] ?? ''}'.trim();
          final hits = searchGrammarPages(app.grammar, rawQ);
          return AiToolOutcome(
              _j({
                'pages': [
                  for (final p in hits.take(8))
                    {
                      'id': p.id,
                      'title': p.title,
                      'section': app.grammar.sectionById[p.section]?.title ?? '',
                      'summary': _cut(p.summary, 120),
                    },
                ],
                if (hits.isEmpty) ...{
                  'all_titles': [
                    for (final p in app.grammar.pageById.values)
                      {'id': p.id, 'title': p.title},
                  ],
                  'note': '未精确命中。请从 all_titles 里挑最接近的标题或换更短关键词重试；若连续 2 次仍无相关内容再如实说明',
                },
              }),
              '查了语法页：$rawQ（${hits.length} 页）');

        case 'indonesian_reference':
          final batchTopics = [
            for (final t in _idList(a['topics']))
              if (t.trim().isNotEmpty) t.trim(),
          ];
          final singleMaxChars = app.aiBudget.input <= 16000 ? 3600 : 6000;
          if (batchTopics.length > 1) {
            final inTok = app.aiBudget.input;
            final (maxTopics, perTopicChars) = inTok <= 16000
                ? (4, 1200)
                : (inTok <= 48000 ? (6, 1600) : (10, 2200));
            final active = batchTopics.take(maxTopics).toList();
            final deferred = batchTopics.skip(maxTopics).toList();
            final emittedKeys = <String>{};
            final results = <String, Object>{};
            for (final q in active) {
              final hits = referenceHitsFor(q).take(2).toList();
              if (hits.isEmpty) {
                results[q] = {'note': '未命中，可从 topics 目录中重选'};
                continue;
              }
              final eachCap = (perTopicChars ~/ hits.length).clamp(500, perTopicChars);
              results[q] = {
                for (final e in hits)
                  e.key: emittedKeys.add(e.key)
                      ? sliceReferenceText(e.value, q, eachCap)
                      : '（见上方「${e.key}」条）',
              };
            }
            return AiToolOutcome(
                _j({
                  'results': results,
                  if (deferred.isNotEmpty) 'deferred': deferred,
                  if (deferred.isNotEmpty)
                    'note': '当前档位一次最多查 $maxTopics 个子问题，其余已放入 deferred，可下一轮继续查',
                }),
                '批量查了语法知识库（${active.length} 个问题）');
          }
          final topic = batchTopics.isNotEmpty
              ? batchTopics.single
              : '${a['topic'] ?? ''}'.trim();
          final hit = referenceHitsFor(topic);

          if (hit.length > kReferenceMaxHits) {
            return AiToolOutcome(
                _j({
                  'topics': [for (final e in hit) e.key],
                  'note': '这个主题太宽，命中 ${hit.length} 条；请从 topics 里选最相关的一个再查'
                }),
                '查了语法知识库：主题太宽，先列目录');
          }
          return AiToolOutcome(
              _j(hit.isEmpty
                  ? {'topics': kIndoReference.keys.toList(), 'note': '没对上主题，请从 topics 里选'}
                  : {
                      for (final e in hit)
                        e.key: sliceReferenceText(e.value, topic, singleMaxChars),
                    }),
              '查了语法知识库${hit.isEmpty ? '' : '：${hit.map((e) => e.key.split(' ').first).join('、')}'}');

        case kLocalDictTool:
          if (!app.aiLocalDictOn) {
            return AiToolOutcome(
                _j({'error': '学生没有开启「允许问 AI 参考本地词典」，不能查。请直接说明。'}),
                '本地词典：未开启');
          }
          final words = [
            for (final w in (a['words'] is List ? a['words'] as List : const []))
              if (w is String && w.trim().isNotEmpty) w.trim(),
          ].take(kLocalDictMaxWords).toList();
          if (words.isEmpty) {
            return AiToolOutcome(_j({'error': '没有给出要查的词'}), '本地词典：没有词');
          }
          final results = <Map<String, Object?>>[];
          for (final w in words) {
            final hits = await app.db.dictLookup(dictFold(w));
            results.add({
              'word': w,
              'hits': [
                for (final h in hits.take(3))
                  {
                    'dictionary': h.sourceName,
                    'authority': h.isKbbi ? 'kbbi' : 'local',
                    'homograph': h.entry.homographIndex,
                    'senses': [
                      for (final s in h.entry.senses.take(3))
                        {
                          'pos': s.pos,
                          'definition': _cut(s.definition, 200),
                          'examples': [
                            for (final e in s.examples.take(2))
                              {
                                'text': _cut(e.text, 200),
                                if (e.translation != null)
                                  'translation': _cut(e.translation!, 200),
                              },
                          ],
                        },
                    ],
                  },
              ],
            });
          }
          return AiToolOutcome(
              _j({
                'results': results,
                'note': '这些是学生自己导入的词典内容。authority=kbbi 的是 KBBI：'
                    '释义以它为准，其余导入词典只作补充，回答时逐个注明词典名；'
                    '没有命中的词如实说没查到，不要编造。'
                    '${kKbbiLocal ? '' : '若本地没有命中 KBBI，需要查 KBBI 时可改用 web_search 查官网（kbbi.kemendikdasmen.go.id）或国内镜像（kbbi.web.id），未开联网时直接给出官网/镜像查询链接。'}'
                    'KBBI 与知识库冲突时两种说法都列出并指出差异；'
                    '其它导入资料与知识库冲突时，以知识库为准并指出差异。',
              }),
              '查了本地词典：${words.join('、')}');

        case 'web_search':
          final prov = app.aiSearchProvider;
          if (prov == null || !app.aiSearchReady) {
            return AiToolOutcome(
                _j({'error': '学生没有配置联网搜索，不能搜索。请直接说明资料里没有，不要编造。'}),
                '联网搜索：没配置');
          }
          final q = '${a['query'] ?? ''}'.trim();
          try {
            final hits = await aiWebSearch(prov, app.aiSearchKeyFor(prov.id), q,
                count: _clampInt(a['count'], 5, 1, 8),
                customEndpoint: app.aiSearchCustomEndpoint);
            await app.bumpAiSearchUsed();
            return AiToolOutcome(
                _j({
                  'query': q,
                  'results': [for (final h in hits) h.toJson()],
                  'note': hits.isEmpty
                      ? '没搜到结果。如实告诉学生没搜到，不要编造。'
                      : '网页搜索摘要，只能作参考，没有经过词典核实；回答里要写出处网址，'
                          '并提醒学生释义以${kKbbiLocal ? ' KBBI ' : '词库'}为准。结果之间矛盾或和知识库不一致时，以知识库和${kKbbiLocal ? ' KBBI ' : '词库'}为准。',
                }),
                '联网搜索：${_cut(q, 24)}（${hits.length} 条）');
          } on AiException catch (e) {
            return AiToolOutcome(
                _j({'error': e.message, 'note': '搜索没成功，如实告诉学生；不要编造搜索结果。'}),
                '联网搜索失败');
          }

        case 'app_guide':
          final topic = '${a['topic'] ?? ''}'.trim();
          final hit = kAppGuide.entries
              .where((e) => topic.isNotEmpty && (e.key.contains(topic) || topic.contains(e.key)))
              .toList();
          return AiToolOutcome(
              _j(hit.isEmpty ? kAppGuide : {for (final e in hit) e.key: e.value}),
              '看了使用说明${topic.isEmpty ? '' : '：$topic'}');

        case 'add_to_memory':
          final cs = await _cards(_idList(a['ids']));
          final mem = await _inMemory([for (final c in cs) c.id]);
          final todo = [for (final c in cs) if (c.enabled && !mem.contains(c.id)) c];
          if (todo.isEmpty) {
            return AiToolOutcome(_j({'added': 0, 'note': '这些词都已在记忆里或不可学'}), '加入记忆：都已在记忆里');
          }
          final ok = await confirm(AiPendingAction(
              '把 ${todo.length} 个词加入记忆', _preview(todo),
              confirmLabel: '加入记忆'));
          if (!ok) return AiToolOutcome(_j({'declined': true}), '加入记忆：已取消');
          await app.remember([for (final c in todo) c.id]);
          return AiToolOutcome(
              _j({'added': todo.length, 'already': mem.length}),
              '已加入记忆：${todo.length} 个');

        case 'create_word_list':
          final name = '${a['name'] ?? ''}'.trim();
          final cs = await _cards(_idList(a['ids']));
          if (name.isEmpty || cs.isEmpty) {
            return AiToolOutcome(_j({'error': '词单名或词为空'}), '新建词单：缺名字或词');
          }
          final ok = await confirm(AiPendingAction(
              '新建词单「$name」，共 ${cs.length} 个词', _preview(cs),
              confirmLabel: '新建'));
          if (!ok) return AiToolOutcome(_j({'declined': true}), '新建词单：已取消');
          final id = await app.db.createWordList(name, [for (final c in cs) c.id]);
          if (id == null) {
            return AiToolOutcome(_j({'error': '已有同名词单，换个名字或用 add_to_word_list'}), '新建词单：重名');
          }
          return AiToolOutcome(
              _j({'list_id': id, 'count': cs.length}),
              '已新建词单「$name」（${cs.length} 个词）',
              nav: AiNavAction('打开词单「$name」',
                  (ctx) => Navigator.push(ctx, MaterialPageRoute(
                      builder: (_) => WordListDetailScreen(listId: id, title: name)))));

        case 'add_to_word_list':
          final id = _clampInt(a['list_id'], -1, -1, 1 << 30);
          final lists = await app.db.listWordLists();
          final hit = lists.where((l) => l.$1 == id).toList();
          if (hit.isEmpty) return AiToolOutcome(_j({'error': '没有这个词单'}), '补充词单：没找到');
          final old = await app.db.wordListIds(id);
          final cs = [for (final c in await _cards(_idList(a['ids']))) if (!old.contains(c.id)) c];
          if (cs.isEmpty) return AiToolOutcome(_j({'added': 0}), '补充词单：没有新词');
          final ok = await confirm(AiPendingAction(
              '往词单「${hit.first.$2}」追加 ${cs.length} 个词', _preview(cs),
              confirmLabel: '追加'));
          if (!ok) return AiToolOutcome(_j({'declined': true}), '补充词单：已取消');
          await app.db.updateWordListIds(id, [...old, for (final c in cs) c.id]);
          return AiToolOutcome(_j({'added': cs.length}), '已往「${hit.first.$2}」追加 ${cs.length} 个词');

        case 'save_mnemonic':
          final c = await _card('${a['id'] ?? ''}');
          final text = '${a['text'] ?? ''}'.trim();
          if (c == null || text.isEmpty) return AiToolOutcome(_j({'error': '词或内容为空'}), '存助记：缺内容');
          final old = c.hasOwnMnemonic ? c.mnemonic!.trim() : '';
          final full = _cut(old.isEmpty ? text : '$old\n$text', 500);
          final ok = await confirm(AiPendingAction('存为「${c.word}」的助记', [full], confirmLabel: '保存'));
          if (!ok) return AiToolOutcome(_j({'declined': true}), '存助记：已取消');
          await app.db.saveMnemonic(c.id, full);
          return AiToolOutcome(_j({'saved': true}), '已存助记：${c.word}');

        case 'set_daily_quota':
          final q = _clampInt(a['quota'], app.dailyQuota, 0, AppState.kMaxDailyQuota);
          if (q == app.dailyQuota) return AiToolOutcome(_j({'quota': q, 'note': '没有变化'}), '卡量没变');
          final ok = await confirm(AiPendingAction(
              '把今日卡量从 ${app.dailyQuota} 改成 $q', ['复习 + 新词一共 $q 张，到期复习优先占卡量'],
              confirmLabel: '修改'));
          if (!ok) return AiToolOutcome(_j({'declined': true}), '改卡量：已取消');
          await app.setQuota(q);
          return AiToolOutcome(_j({'quota': q}), '已把今日卡量改成 $q');

        case 'open_word':
          final c = await _card('${a['id'] ?? ''}');
          if (c == null) return AiToolOutcome(_j({'error': '没有这个词'}), '打开单词：没找到');
          return AiToolOutcome(_j({'will_open': c.word}), '将打开：${c.word}',
              nav: AiNavAction('打开「${c.word}」', (ctx) => Navigator.push(
                  ctx, MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: c.id)))));

        case 'open_grammar_page':
          final p = app.grammar.pageById['${a['id'] ?? ''}'];
          if (p == null) return AiToolOutcome(_j({'error': '没有这个语法页'}), '打开语法页：没找到');
          return AiToolOutcome(_j({'will_open': p.title}), '将打开语法页：${p.title}',
              nav: AiNavAction('打开「${p.title}」', (ctx) => openGrammarPage(ctx, app.grammar, p.id)));

        case 'open_word_list':
          final id = _clampInt(a['list_id'], -1, -1, 1 << 30);
          final hit = (await app.db.listWordLists()).where((l) => l.$1 == id).toList();
          if (hit.isEmpty) return AiToolOutcome(_j({'error': '没有这个词单'}), '打开词单：没找到');
          final name = hit.first.$2;
          return AiToolOutcome(_j({'will_open': name}), '将打开词单：$name',
              nav: AiNavAction('打开词单「$name」', (ctx) => Navigator.push(ctx,
                  MaterialPageRoute(builder: (_) => WordListDetailScreen(listId: id, title: name)))));

        case 'open_screen':
          final s = '${a['screen'] ?? ''}';
          final nav = _screenNav(s);
          if (nav == null) return AiToolOutcome(_j({'error': '没有这个页面：$s'}), '打开页面：不认识');
          return AiToolOutcome(_j({'will_open': _kScreens[s]}), '将打开：${_kScreens[s]}', nav: nav);
      }
      return AiToolOutcome(_j({'error': '没有这个工具：${call.name}'}), '未知工具 ${call.name}');
    } catch (e) {
      return AiToolOutcome(_j({'error': '执行出错：$e'}), '${call.name} 出错');
    }
  }

  AiNavAction? _screenNav(String s) {
    const tabs = {'study': 0, 'library': 1, 'grammar': 2, 'stats': 3, 'profile': 4};
    final label = '打开${_kScreens[s] ?? s}';
    if (tabs.containsKey(s)) {
      return AiNavAction(label, (_) => AiHomeTabs.select?.call(tabs[s]!), closeSheet: true);
    }
    Widget? page = switch (s) {
      'search' => const SearchScreen(),
      'scan' => const ScanScreen(),
      'my_cards' => const MyScreen(),
      'favorites' => const FavoritesScreen(),
      'writing' => const GrammarHubScreen(writing: true),
      'settings' => const SettingsScreen(),
      'ai_settings' => const AiSettingsScreen(),
      _ => null,
    };
    if (page == null) return null;
    final p = page;
    return AiNavAction(label, (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => p)));
  }
}

List<GPage> searchGrammarPages(GrammarRepo grammar, String rawQuery) {
  final q = rawQuery.trim().toLowerCase();
  if (q.isEmpty) return const [];
  String hayOf(GPage p) =>
      '${p.title} ${p.titleId} ${p.summary} ${p.aliases.join(' ')}'.toLowerCase();

  final exact = [
    for (final p in grammar.pageById.values)
      if (hayOf(p).contains(q)) p,
  ];
  if (exact.isNotEmpty) return exact;

  final tokens = <String>{
    for (final part in q.split(RegExp(r'\s+')))
      if (part.length >= 2) part,
  };
  for (final m in RegExp(r'[\u4e00-\u9fff]{3,}').allMatches(q)) {
    final s = m.group(0)!;
    for (var i = 0; i <= s.length - 2; i++) {
      tokens.add(s.substring(i, i + 2));
    }
  }
  if (tokens.isEmpty) return const [];

  final scored = <(GPage, int)>[];
  for (final p in grammar.pageById.values) {
    final hay = hayOf(p);
    var score = 0;
    for (final t in tokens) {
      if (hay.contains(t)) score++;
    }
    if (score > 0) scored.add((p, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final s in scored) s.$1];
}
