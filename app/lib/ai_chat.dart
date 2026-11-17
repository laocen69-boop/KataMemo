library;

import 'dart:async';
import 'dart:convert';

import 'platform/io_shim.dart';

import 'ai_context.dart';
import 'ai_skill.dart';
import 'version.dart' show kKbbiLocal;
import 'models.dart';

export 'ai_context.dart';
export 'ai_skill.dart';

const String kAiRecommendedAsOf = '2026-11';

enum AiProtocol { openai, anthropic }

class AiProvider {
  final String id;
  final String name;
  final String vendor;
  final String base;
  final AiProtocol protocol;

  final String console;

  final String modelHint;

  final List<(String id, String label)> extraModels;

  final bool nativeSearch;

  final String searchNote;

  final bool overseas;

  final int color;
  final String badge;

  final String note;

  final bool recommended;

  const AiProvider({
    required this.id,
    required this.name,
    required this.vendor,
    required this.base,
    required this.console,
    required this.modelHint,
    required this.color,
    required this.badge,
    this.extraModels = const [],
    this.nativeSearch = false,
    this.searchNote = '',
    this.protocol = AiProtocol.openai,
    this.overseas = false,
    this.note = '',
    this.recommended = false,
  });

  bool get isCustom => id == 'custom';
}

const List<AiProvider> kAiProviders = [
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    vendor: '深度求索',
    base: 'https://api.deepseek.com',
    console: 'https://platform.deepseek.com/api_keys',
    modelHint: 'deepseek-flash',
    nativeSearch: true,
    searchNote: '填入 Key 后默认自动开启按需上网查询（直接复用同一把 Key，无需分开配置）；也可在「对话与入口 → 联网搜索」随时关闭',
    color: 0xFF4D6BFE,
    badge: 'D',
    recommended: true,
  ),
  AiProvider(
    id: 'ark',
    name: '豆包 Seed',
    vendor: '字节跳动 · 火山方舟',
    base: 'https://ark.cn-beijing.volces.com/api/v3',
    console: 'https://console.volcengine.com/ark',
    modelHint: 'doubao-seed-2-1-lite-260915',
    nativeSearch: true,
    searchNote: '火山方舟原生 web_search_options 在携带本 App 词库工具时会被接口忽略；请到「对话与入口 → 联网搜索」配置博查 / Tavily / 自定义搜索以兼顾联网与查词',
    color: 0xFF1F6FFF,
    badge: '豆',
    note: '模型名填方舟控制台「开通管理」里的模型 ID 或推理接入点 ID',
  ),
  AiProvider(
    id: 'qwen',
    name: '通义千问 Qwen',
    vendor: '阿里云百炼',
    base: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    console: 'https://bailian.console.aliyun.com/',
    modelHint: 'qwen3.5-flash',
    extraModels: [
      ('qwen3.5-35b-a3b', '轻量 MoE（仅激活 3B · 东南亚多语强）'),
      ('qwen3.5-9b', '9B 小模型 · 极低成本'),
    ],
    nativeSearch: true,
    searchNote: '官方百炼接口（dashscope）填入 Key 后默认附带原生联网（enable_search: true），可与本 App 词库工具共存；也可在「对话与入口 → 联网搜索」改用外部搜索或关闭',
    color: 0xFF615CED,
    badge: '千',
  ),
  AiProvider(
    id: 'glm',
    name: '智谱 GLM',
    vendor: '智谱 AI · 开放平台',
    base: 'https://open.bigmodel.cn/api/paas/v4',
    console: 'https://open.bigmodel.cn/usercenter/apikeys',
    modelHint: 'glm-5.3-flash',
    nativeSearch: true,
    searchNote: '填入 Key 后默认自动开启按需上网查询（直接复用同一把 Key，无需分开配置）；也可在「对话与入口 → 联网搜索」随时关闭',
    color: 0xFF2E5BFF,
    badge: '智',
  ),
  AiProvider(
    id: 'minimax',
    name: 'MiniMax',
    vendor: '稀宇科技',
    base: 'https://api.minimaxi.com/v1',
    console: 'https://platform.minimaxi.com/',
    modelHint: 'MiniMax-M3.1-Flash',
    color: 0xFFE8453C,
    badge: 'M',
    note: '国内账号用 api.minimaxi.com；海外账号把地址改成 https://api.minimax.io/v1',
  ),
  AiProvider(
    id: 'mimo',
    name: '小米 MiMo',
    vendor: '小米 · MiMo 开放平台',
    base: 'https://api.xiaomimimo.com/v1',
    console: 'https://platform.xiaomimimo.com/#/console/api-keys',
    modelHint: 'mimo-v2.6-flash',
    color: 0xFFFF6900,
    badge: '米',
    note: '按量付费 Key（sk- 开头）用这个地址；Token Plan 套餐（tp- 开头）的地址不同，'
        '请按控制台说明改',
  ),
  AiProvider(
    id: 'openai',
    name: 'ChatGPT',
    vendor: 'OpenAI',
    base: 'https://api.openai.com/v1',
    console: 'https://platform.openai.com/api-keys',
    modelHint: 'gpt-6-luna',
    nativeSearch: true,
    searchNote: 'OpenAI 的 Chat Completions 搜索模型不支持同时挂接本 App 词库工具；如需联网请到「对话与入口 → 联网搜索」配置博查 / Tavily / 自定义搜索',
    color: 0xFF10A37F,
    badge: 'G',
    overseas: true,
  ),
  AiProvider(
    id: 'claude',
    name: 'Claude',
    vendor: 'Anthropic',
    base: 'https://api.anthropic.com/v1',
    console: 'https://console.anthropic.com/settings/keys',
    modelHint: 'claude-haiku-5-5',
    color: 0xFFD97757,
    badge: 'C',
    protocol: AiProtocol.anthropic,
    overseas: true,
  ),
  AiProvider(
    id: 'gemini',
    name: 'Gemini',
    vendor: 'Google AI Studio',
    base: 'https://generativelanguage.googleapis.com/v1beta/openai',
    console: 'https://aistudio.google.com/apikey',
    modelHint: 'gemini-4-hydrogen',
    extraModels: [
      ('gemma-4-31b-it', 'Gemma 4 · 印尼语等东南亚多语特化'),
      ('gemma-4-4b-it', 'Gemma 4 · 轻量快速'),
    ],
    nativeSearch: true,
    searchNote: 'Gemini 的 OpenAI 兼容接口使用非标 google_search 工具且与自定义函数工具冲突；如需联网请到「对话与入口 → 联网搜索」配置外部搜索。同一把 AI Studio Key 也可直接调 Gemma 4',
    color: 0xFF4285F4,
    badge: 'G',
    overseas: true,
  ),
  AiProvider(
    id: 'custom',
    name: '自定义',
    vendor: '任意 OpenAI 兼容接口',
    base: '',
    console: '',
    modelHint: '',
    color: 0xFF607D8B,
    badge: '+',
    note: '填 /chat/completions 之前的那段地址（必须 https）',
  ),
];

class AiSpeechConfig {
  final bool enabled;
  final String endpoint;
  final String model;
  final String apiKey;

  const AiSpeechConfig({
    this.enabled = false,
    this.endpoint = '',
    this.model = '',
    this.apiKey = '',
  });

  bool get configured =>
      enabled && (endpoint.trim().isNotEmpty || model.trim().isNotEmpty);
}

String aiVendorNames({bool overseas = false, int? max, String sep = '、'}) {
  final names = [
    for (final p in kAiProviders)
      if (!p.isCustom && (!overseas || p.overseas)) p.name,
  ];
  final shown = max == null || names.length <= max ? names : names.take(max);
  final more = max != null && names.length > max ? ' 等' : '';
  return '${shown.join(sep)}$more';
}

AiProvider aiProviderById(String? id) => kAiProviders.firstWhere(
      (p) => p.id == id,
      orElse: () => kAiProviders.first,
    );

const String kAnthropicVersion = '2026-10-21';

class AiConfig {
  final AiProvider provider;
  final String apiKey;
  final String model;

  final String baseOverride;

  const AiConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseOverride = '',
  });

  String get base =>
      baseOverride.trim().isNotEmpty ? baseOverride.trim() : provider.base;

  String? get root => provider.isCustom && base.trim().isEmpty
      ? null
      : normalizeAiBase(base);

  bool get ready =>
      apiKey.trim().isNotEmpty && model.trim().isNotEmpty && root != null;

  String? get missing {
    if (apiKey.trim().isEmpty) return '还没填 API Key';
    if (root == null) {
      return provider.isCustom && base.trim().isEmpty
          ? '自定义服务商要填接口地址'
          : '接口地址必须是 https:// 开头';
    }
    if (model.trim().isEmpty) return '还没填模型名（可点「测试连接」从列表里选）';
    return null;
  }
}

enum AiLinkState { unknown, ok, fail }

class AiStatus {
  final AiLinkState state;
  final int at;
  final String message;
  final String model;
  final int latencyMs;

  const AiStatus(this.state,
      {this.at = 0, this.message = '', this.model = '', this.latencyMs = 0});

  static const unknown = AiStatus(AiLinkState.unknown);

  String encode() => jsonEncode({
        's': state.name,
        'at': at,
        'm': message,
        'mo': model,
        'ms': latencyMs,
      });

  static AiStatus decode(String? raw) {
    if (raw == null || raw.isEmpty) return unknown;
    try {
      final j = jsonDecode(raw) as Map;
      return AiStatus(
        AiLinkState.values.firstWhere((e) => e.name == j['s'],
            orElse: () => AiLinkState.unknown),
        at: (j['at'] as num?)?.toInt() ?? 0,
        message: j['m'] as String? ?? '',
        model: j['mo'] as String? ?? '',
        latencyMs: (j['ms'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return unknown;
    }
  }

  String get label => switch (state) {
        AiLinkState.ok => '已连接',
        AiLinkState.fail => '连接失败',
        AiLinkState.unknown => '未测试',
      };
}

class AiToolCall {
  final String id;
  final String name;
  final String args;
  const AiToolCall(this.id, this.name, this.args);

  Map<String, dynamic> get argMap {
    try {
      final v = jsonDecode(args.isEmpty ? '{}' : args);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class AiToolSpec {
  final String name;
  final String description;
  final Map<String, Object?> parameters;
  const AiToolSpec(this.name, this.description, this.parameters);
}

class AiMessage {
  final String role;
  final String content;
  final List<AiToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final String? imageB64;
  final String imageMime;
  final String? label;

  const AiMessage(
    this.role,
    this.content, {
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.imageB64,
    this.imageMime = 'image/jpeg',
    this.label,
  });

  Map<String, String> toJson() => {'role': role, 'content': content};

  bool get visible =>
      role == 'user' || (role == 'assistant' && content.trim().isNotEmpty);
}

class AiChatContext {

  final String key;
  final String title;
  final String subtitle;
  final String system;
  final List<(String, String)> quick;
  final WordCard? card;

  const AiChatContext({
    required this.key,
    required this.title,
    required this.system,
    required this.quick,
    this.subtitle = '',
    this.card,
  });
}

const String _kRules = '规则：\n'
    '1. 用简体中文回答，简洁口语化。用轻量 Markdown 排版（App 会渲染）：小标题用 ###，要点用列表，'
    '印尼语词和例句用 **粗体**，批改用表格 | 原句 | 改后 | 原因 |，规则提示用引用块 >；'
    '不要用 # 或 ## 大标题，不要代码块。\n'
    '2. 涉及释义时，以下面提供的资料为准（${kKbbiLocal ? '参考 KBBI 官方词典与本词库' : '来自本词库和学生导入的笔记；本版本没有内置 KBBI，学生自己导入的 KBBI 词典不在此列'}）；'
    '学生导入并被标为 KBBI 的词典，释义优先于其它导入资料；资料没覆盖的，'
    '要说明是你的补充；没有把握的，直接说「我没有查到可靠依据」，不要编造释义、规则、出处、例句来源或数据。\n'
    '3. 举的印尼语例句要符合标准印尼语（bahasa baku），后面附中文；口语或俚语要标明。\n'
    '4. 批改句子时先指出错误，再给正确写法和简短理由。\n'
    '5. 回答控制在 250 字以内，除非学生要求详细。';

const String _kPersona = '你是一位耐心、专业的印尼语老师，学生是以中文为母语的印尼语学习者。'
    '你同时是这个背单词 App（$_kAppNameForAi）里的学习助手。';
const String _kAppNameForAi = 'KataMemo';

const String kAiAgentRules = '''【操作 App】
你可以调用工具查询学生的学习数据、查词、整理词单、打开页面。原则：
1. 需要数据时先调工具，不要凭空编造单词 id、数量或学习记录；工具返回空就如实说。
2. 加入记忆、新建/补充词单、存助记、改今日卡量这类会改数据的工具，App 会先让学生确认；学生拒绝就不要再试。
3. 一次只做学生要求的事；批量操作前先说清楚要处理哪些词。
4. 学生问「怎么用 / 在哪里」时先调 app_guide 再回答，必要时用 open_screen 帮他打开对应页面。
5. 讲专业语法（词缀变体与例外、语态、-kan/-i、体与情态、规范用法等）前先调 indonesian_reference 查知识库；如果学生一次问了多个问题或语法点，先拆成多个独立的子问题放进 topics 一次查完（省步数，工具会按问题数量分配额度）；查到的条目没讲到要问的点，就换个主题再查一次，仍然没有就明说「我手头的资料里没有这一条」（不要提知识库、工具这些内部说法）：有把握的补充要标明是你自己的补充，没有把握的就不要说，更不要编。
6. 工具做完后用一两句话告诉学生结果和下一步可以做什么。
7. 多步任务（预计要调 3 次以上工具）：先调 task_plan 写下步骤计划（每步一句），每做完一步再调 task_plan 更新状态，照计划做完再总结，不要半路换题。计划和学生的原始要求会一直留在上下文里。
8. 省步骤：一次查多个词用 search_words 的 queries（最多 30 个），看多张卡用 get_word 的 ids（最多 30 个），查多个语法点用 indonesian_reference 的 topics；互不依赖的查询放在同一轮里一起调用；同类写操作（如把一批词加入记忆或加进词单）合并成一次调用，让用户只确认一次。同样的调用不要重复，结果不会变；若同一查询工具连续 2 次返回空结果，不要原样死磕重试，请换更短/更宽泛的关键词或从返回的目录列表里选标题再查一次，仍无结果再如实告知。
9. 工具结果太长会被截断（标着「已截断」）：需要后面的内容就缩小范围，或用 offset 再取。
10. 学生问某个印尼语词的意思、词形、词性或用法，且工具列表里有 local_dictionary 时，先调它查这个词；
结果里 authority=kbbi 的词典是 KBBI，释义以它为准，其它导入词典只作补充并各自写明出处；
查不到就如实说没查到，不要用自己的知识冒充词典内容。''';

const String kAiSearchRules = '''【联网搜索】
学生配置了联网搜索，工具列表里有 web_search。规则：
1. 先查词库和知识库；它们都没有答案、或学生要查最新信息 / 网络用法 / 俚语 / 新词时，才搜。一轮最多搜 2 次。
2. 搜索结果只是网页摘要，只能作参考：回答里要写出处网址，并说明「来自网页、没有经过词典核实，释义以${kKbbiLocal ? ' KBBI ' : '词库'}为准」。
3. 网页和知识库、${kKbbiLocal ? 'KBBI' : '词库'}矛盾时，以知识库和${kKbbiLocal ? ' KBBI ' : '词库'}为准，并指出矛盾。
4. 没搜到或搜索失败，就如实说没搜到；不要用自己的猜测冒充搜索结果。'''
    '${kKbbiLocal ? '' : '\n5. 若学生明确要查 KBBI 且本地导入词典未命中（或未启用 local_dictionary），可搜 KBBI 官网（kbbi.kemendikdasmen.go.id）；中国大陆网络环境或官网搜不到时改搜镜像 https://kbbi.web.id/，回答里标明来源是官网还是镜像。'}';

const String kAiSummaryRules =
    '【收尾】\n'
    '本次的工具调用次数已经用完。请**不要再请求调用工具**，直接基于上面已经拿到的结果给出最终答复：\n'
    '已经完成什么、结果是什么；没做完的部分明确说还差什么、建议用户下一步怎么做。';

const String kAiCompactSystem =
    '你是对话压缩器。把给你的这段工具调用过程压缩成不超过 10 行的中文进展摘要：\n'
    '1. 用户要做什么（一句话）；\n'
    '2. 已经完成哪些步骤、关键结果是什么（**原样保留**具体的词、单词 id、词单 id、数字、页 id）；\n'
    '3. 还没做完什么、下一步该做什么。\n'
    '如果给了「之前的进展」，把它和新的过程合并成一份。只输出摘要本身，不要客套话，不要重复原文。';

const String kAiSessionCompactSystem =
    '你是印尼语学习对话压缩器。请把下面同一会话的早期对话压成简明结构化中文摘要（250 字以内），'
    '供后续在同一会话内继续使用：\n'
    '1. 当前学习目标或任务进展；\n'
    '2. 已讨论/已操作的印尼语关键锚点（**原样保留**词条 id、拼写/EYD 结论、词缀拆解、语法页 id、词单 id）；\n'
    '3. 学生提出的具体偏好、纠错或待办下一步。\n'
    '如果前面已有「前情摘要」，请将其与新轮次合并。只输出摘要正文，不要客套话。';

const String kAiMemoryExtractSystem =
    '你是印尼语学习记忆整理器。请从下面对话中提炼对**未来所有新会话**都有价值的长期学习画像，'
    '并与「已有记忆」合并去重（500 字以内中文要点）：\n'
    '仅保留：印尼语水平、讲解/例句偏好、反复混淆的词缀/语法/易错点、学习目标。\n'
    '不要记录一次性查过的普通单词或临时操作步骤。\n'
    '如果本段对话没有值得新增或更新的长期记忆，只回复：NONE。';

const String kAiContinueAsk = '（你上一条回答因为长度上限被截断了。请从断开的地方直接接着写，'
    '不要重复已经写过的内容，不要加开场白。）';

AiChatContext aiWordContext(WordCard card) => AiChatContext(
      key: 'word:${card.id}',
      title: card.word,
      subtitle: card.zhClean ?? '',
      system: aiSystemPrompt(card),
      card: card,
      quick: [
        for (final (l, t) in kAiQuickPrompts) (l, aiQuickPrompt(t, card)),
      ],
    );

AiChatContext aiGrammarContext(
        {required String id, required String title, required String text}) =>
    AiChatContext(
      key: 'grammar:$id',
      title: title,
      subtitle: '语法',
      system: '$_kPersona\n$_kRules\n\n$kIndoTutorSkill\n\n【当前语法页】\n${_cut(text, 3000)}',
      quick: kAiGrammarQuick,
    );

const List<(String, String)> kAiGrammarQuick = [
  ('换个说法讲', '用更简单的话把这一页的要点讲一遍，并各配一个新例句。'),
  ('出几道题', '根据这一页出 3 道小练习，先只给题目，等我作答后再批改。'),
  ('常见错误', '中国学生学这一点最容易犯什么错？各举一个错句和正确写法。'),
  ('和中文对比', '这一语法点和中文的说法有什么异同？'),
];

AiChatContext aiGeneralContext({List<(String, String)> recent = const []}) {
  final b = StringBuffer('$_kPersona\n$_kRules\n\n$kIndoTutorSkill');
  if (recent.isNotEmpty) {
    b.writeln('\n\n【学生今天学过的词】');
    for (final (w, zh) in recent.take(30)) {
      b.writeln('- $w：${_cut(zh, 40)}');
    }
  }
  return AiChatContext(
    key: 'general',
    title: '印尼语助手',
    subtitle: recent.isEmpty ? '随便问' : '已读入今天学过的 ${recent.length} 个词',
    system: b.toString().trimRight(),
    quick: [
      if (recent.isNotEmpty)
        ('考考今天的词', '从我今天学过的词里挑 5 个出题（中译印或填空），先只给题目，等我回答后再批改。'),
      ('复盘今天的错词', '看看我今天学习时答错（困难/模糊）的词，帮我分析容易混的原因，给每个词一个好记的提示。'),
      ('搜过的词建词单', '把我今天搜索过的单词整理成一个词单，词单名用今天的日期。'),
      ('语法错题', '统计我今天做错的语法练习题，按语法点归类讲解，并各出一道类似的题。'),
      ('教我用 App', '我是新用户，用三五句话告诉我这个 App 最重要的用法，然后问我想先做什么。'),
      ('帮我翻译', '我接下来发一段中文，请翻译成自然的印尼语，并解释用词。'),
      ('批改句子', '我接下来发一个印尼语句子，请帮我批改并说明原因。'),
      ('情景对话', '我们用印尼语模拟一段在餐馆点菜的对话，你扮演服务员，每次只说一句，'
          '我说错时在括号里用中文纠正。'),
      ('词缀小课', '用 5 分钟讲清 me- 和 ber- 前缀的区别，各给 3 个常用词。'),
    ],
  );
}

const Map<String, String> kAiQuickHints = {
  '讲讲用法': '常见搭配 + 2 个日常例句',
  '近义词辨析': '容易混的词，各给一个例句',
  '怎么记': '拆词缀、同源词或联想',
  '考考我': '出一道小题，答完再批改',
  '批改我的句子': '发一句印尼语，帮你指出错在哪',
  '换个说法讲': '用更简单的话重讲这一页',
  '出几道题': '3 道小练习，答完再批改',
  '常见错误': '中国学生最容易犯的错',
  '和中文对比': '这一语法点和中文的异同',
  '考考今天的词': '从今天学过的词里抽 5 个出题',
  '复盘今天的错词': '看错因，并给每个词一个好记的提示',
  '搜过的词建词单': '按今天的日期整理成一个词单',
  '语法错题': '按语法点归类讲解，再各出一题',
  '教我用 App': '三句话讲清最重要的用法',
  '帮我翻译': '中译印，并解释用词',
  '批改句子': '发一句印尼语，指出错在哪',
  '情景对话': '在餐馆点菜的印尼语对话',
  '词缀小课': 'me- 和 ber- 的区别',
};

const List<(String, String)> kAiQuickPrompts = [
  ('讲讲用法', '用中文简单讲讲「{w}」最常见的用法和搭配，给 2 个日常例句（附中文）。'),
  ('近义词辨析', '「{w}」有哪些容易混的近义词？用中文说清区别，各给一个例句。'),
  ('怎么记', '给「{w}」想一个好记的助记方法（拆词缀、同源词或联想都行），控制在 60 字以内。'),
  ('考考我', '用「{w}」给我出一道小题（翻译或填空），先别给答案，等我回答后再批改。'),
  ('批改我的句子', '我想用「{w}」造句，我下一条发给你，请帮我批改并说明原因。'),
];

String aiSystemPrompt(WordCard card) {
  final b = StringBuffer()
    ..writeln(_kPersona)
    ..writeln(_kRules)
    ..writeln()
    ..writeln(kIndoTutorSkill)
    ..writeln()
    ..writeln('【词条资料】')
    ..writeln('词头：${card.word}');
  final cls = card.wordClassLabelsCombined;
  if (cls.isNotEmpty) b.writeln('词性：$cls');
  final zh = card.zhClean;
  if (zh != null && zh.isNotEmpty) b.writeln('中文释义：${_cut(zh, 300)}');
  if (card.fullName != null) b.writeln('全称：${card.fullName}');
  if (card.baseWord != null && card.baseWord != card.id) {
    b.writeln('词根：${card.baseWord}');
  }
  final senses = card.senses.take(6).toList();
  if (senses.isNotEmpty) {
    b.writeln('KBBI 释义：');
    for (var i = 0; i < senses.length; i++) {
      final p = senses[i].pos;
      b.writeln('  ${i + 1}. ${p == null || p.isEmpty ? '' : '[$p] '}'
          '${_cut(senses[i].def, 200)}');
    }
  }
  final exs = card.examples.take(4).toList();
  if (exs.isNotEmpty) {
    b.writeln('例句：');
    for (final e in exs) {
      b.writeln('  - ${_cut(e.text, 200)}'
          '${e.zh == null || e.zh!.isEmpty ? '' : '（${_cut(e.zh!, 120)}）'}');
    }
  }
  final notes = card.grammarNotes.take(3).toList();
  if (notes.isNotEmpty) {
    b.writeln('用法说明：');
    for (final n in notes) {
      b.writeln('  - ${_cut(n.zh, 160)}');
    }
  }
  if (card.gabunganKata.isNotEmpty) {
    b.writeln('常见搭配：${card.gabunganKata.take(12).join('、')}');
  }
  return b.toString().trimRight();
}

String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

String aiQuickPrompt(String template, WordCard card) =>
    template.replaceAll('{w}', card.word);

String aiPlainText(String s) => s
    .replaceAll('**', '')
    .replaceAll('__', '')
    .replaceAll('`', '')
    .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
    .replaceAll(RegExp(r'^>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$\n?', multiLine: true), '')
    .replaceAllMapped(RegExp(r'^\|(.*)\|\s*$', multiLine: true),
        (m) => m[1]!.split('|').map((c) => c.trim()).join('  '));

class AiSessionCache {
  AiSessionCache._();
  static const int cap = 20;
  static final Map<String, List<AiMessage>> _m = {};

  static List<AiMessage> get(String key) => List.of(_m[key] ?? const []);

  static void put(String key, List<AiMessage> msgs) {
    _m.remove(key);
    if (msgs.isEmpty) return;
    _m[key] = List.of(msgs);
    while (_m.length > cap) {
      _m.remove(_m.keys.first);
    }
  }

  static void clearAll() {
    _m.clear();
    _ids.clear();
  }

  static final Map<String, int> _ids = {};
  static int? idOf(String key) => _ids[key];
  static void setId(String key, int? id) {
    if (id == null) {
      _ids.remove(key);
    } else {
      _ids[key] = id;
    }
  }
}

List<AiMessage> aiTrimHistory(List<AiMessage> history, {int maxTurns = 16}) {
  if (history.isEmpty) return const [];
  var lastUser = -1;
  for (var i = history.length - 1; i >= 0; i--) {
    if (history[i].role == 'user') {
      lastUser = i;
      break;
    }
  }

  if (lastUser < 0) return const [];
  var start = lastUser;
  final currentTurn = history.length - lastUser;
  if (currentTurn < maxTurns) {
    var room = maxTurns - currentTurn;
    var older = lastUser;
    while (older > 0) {
      var prev = older - 1;
      while (prev > 0 && history[prev].role != 'user') {
        prev--;
      }
      if (history[prev].role != 'user') break;
      final len = older - prev;
      if (len > room) break;
      room -= len;
      older = prev;
    }
    start = older;
  }
  return history.sublist(start);
}

const int _kKeepImages = 1;

const int kAiMaxOutput = 16384;

const List<int?> kAiCustomMaxOutputChoices = [
  null,
  8192,
  16384,
  32768,
  65536,
  131072,
  262144,
  393216,
];

int? aiMaxOutputFor(AiConfig cfg, {int? customMaxOutput}) {
  if (customMaxOutput != null && customMaxOutput >= 1024) {
    return customMaxOutput;
  }
  if (cfg.provider.protocol == AiProtocol.anthropic) {
    return kAiMaxOutput;
  }
  return null;
}

bool aiShouldEnableNativeSearch(
  AiConfig cfg, {
  bool searchExplicitlyOff = false,
}) {
  if (searchExplicitlyOff) return false;
  if (cfg.provider.id != 'qwen') return false;
  final root = cfg.root ?? '';
  return root.contains('dashscope');
}

Map<String, Object?> aiRequestBody(
  AiProtocol protocol,
  String model,
  String system,
  List<AiMessage> history, {
  int maxTurns = 16,
  List<AiToolSpec> tools = const [],
  int? budget,
  bool trim = true,
  int toolChars = 6000,
  int? maxOutput,
  bool enableSearch = false,
}) {
  final picked = !trim
      ? history
      : budget != null
          ? aiPackHistory(history, budget: budget, toolChars: toolChars).msgs
          : aiTrimHistory(history, maxTurns: maxTurns);

  final tail = tools.isNotEmpty ? picked : aiFlattenTools(picked);
  var imagesLeft = _kKeepImages;
  final withImage = <int>{};
  for (var i = tail.length - 1; i >= 0 && imagesLeft > 0; i--) {
    if (tail[i].imageB64 != null) {
      withImage.add(i);
      imagesLeft--;
    }
  }
  if (protocol == AiProtocol.anthropic) {
    final msgs = <Map<String, Object?>>[];
    for (var i = 0; i < tail.length; i++) {
      final m = tail[i];
      if (m.role == 'tool') {
        final block = {
          'type': 'tool_result',
          'tool_use_id': m.toolCallId,
          'content': m.content,
        };

        final last = msgs.isEmpty ? null : msgs.last;
        if (last != null &&
            last['role'] == 'user' &&
            last['content'] is List &&
            (last['content'] as List).every(
                (b) => b is Map && b['type'] == 'tool_result')) {
          (last['content'] as List).add(block);
        } else {
          msgs.add({
            'role': 'user',
            'content': [block]
          });
        }
      } else if (m.role == 'assistant' && m.toolCalls.isNotEmpty) {
        msgs.add({
          'role': 'assistant',
          'content': [
            if (m.content.trim().isNotEmpty) {'type': 'text', 'text': m.content},
            for (final c in m.toolCalls)
              {'type': 'tool_use', 'id': c.id, 'name': c.name, 'input': c.argMap},
          ],
        });
      } else if (m.role == 'user' && m.imageB64 != null) {
        msgs.add({
          'role': 'user',
          'content': [
            if (withImage.contains(i))
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': m.imageMime,
                  'data': m.imageB64,
                },
              }
            else
              {'type': 'text', 'text': '[图片]'},
            {'type': 'text', 'text': m.content.isEmpty ? '请看这张图。' : m.content},
          ],
        });
      } else {

        msgs.add({'role': m.role, 'content': m.content});
      }
    }

    if (msgs.isNotEmpty) {
      final last = msgs.last;
      final c = last['content'];
      if (c is String) {
        last['content'] = <Object?>[
          {'type': 'text', 'text': c, 'cache_control': _kEphemeral},
        ];
      } else if (c is List && c.isNotEmpty && c.last is Map) {
        last['content'] = <Object?>[
          ...c.take(c.length - 1),
          {...Map<String, Object?>.from(c.last as Map), 'cache_control': _kEphemeral},
        ];
      }
    }
    return {
      'model': model,
      'max_tokens': maxOutput ?? kAiMaxOutput,
      'stream': true,
      'system': [
        {'type': 'text', 'text': system, 'cache_control': _kEphemeral},
      ],
      'messages': msgs,
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools)
            {
              'name': t.name,
              'description': t.description,
              'input_schema': t.parameters,
            },
        ],
    };
  }
  return {
    'model': model,
    'stream': true,
    if (maxOutput != null) 'max_tokens': maxOutput,
    if (enableSearch) 'enable_search': true,
    'temperature': 0.7,
    'messages': [
      {'role': 'system', 'content': system},
      for (var i = 0; i < tail.length; i++)
        if (tail[i].role == 'tool')
          {
            'role': 'tool',
            'tool_call_id': tail[i].toolCallId,
            'content': tail[i].content,
          }
        else if (tail[i].role == 'assistant' && tail[i].toolCalls.isNotEmpty)
          {
            'role': 'assistant',

            'content': tail[i].content.isEmpty ? null : tail[i].content,
            'tool_calls': [
              for (final c in tail[i].toolCalls)
                {
                  'id': c.id,
                  'type': 'function',
                  'function': {'name': c.name, 'arguments': c.args},
                },
            ],
          }
        else if (tail[i].role == 'user' && tail[i].imageB64 != null)
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': tail[i].content.isEmpty ? '请看这张图。' : tail[i].content,
              },
              if (withImage.contains(i))
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:${tail[i].imageMime};base64,${tail[i].imageB64}',
                  },
                }
              else
                {'type': 'text', 'text': '[图片]'},
            ],
          }
        else
          tail[i].toJson(),
    ],
    if (tools.isNotEmpty)
      'tools': [
        for (final t in tools)
          {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          },
      ],
  };
}

const Map<String, String> _kEphemeral = {'type': 'ephemeral'};

class AiStreamInfo {
  final String? finish;
  final int inputTokens;
  final int outputTokens;
  final int cachedTokens;
  const AiStreamInfo(
      {this.finish, this.inputTokens = 0, this.outputTokens = 0, this.cachedTokens = 0});

  bool get truncated => finish == 'length';
}

class SseDecoder {
  final StringBuffer _buf = StringBuffer();
  bool done = false;

  bool thinking = false;

  String? finish;
  int inputTokens = 0, outputTokens = 0, cachedTokens = 0;

  AiStreamInfo get info => AiStreamInfo(
      finish: finish,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cachedTokens: cachedTokens);

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  void _usage(Object? u) {
    if (u is! Map) return;

    final inp = _int(u['prompt_tokens']) + _int(u['input_tokens']);
    final out = _int(u['completion_tokens']) + _int(u['output_tokens']);
    final det = u['prompt_tokens_details'];
    final cached = _int(u['prompt_cache_hit_tokens']) +
        _int(u['cache_read_input_tokens']) +
        (det is Map ? _int(det['cached_tokens']) : 0);
    if (inp > 0) inputTokens = inp;
    if (out > 0) outputTokens = out;
    if (cached > 0) cachedTokens = cached;
  }

  final Map<int, (String, String, StringBuffer)> _calls = {};

  List<AiToolCall> get toolCalls => [
        for (final k in (_calls.keys.toList()..sort()))
          if (_calls[k]!.$2.isNotEmpty)
            AiToolCall(
              _calls[k]!.$1.isEmpty ? 'call_$k' : _calls[k]!.$1,
              _calls[k]!.$2,
              _calls[k]!.$3.toString(),
            ),
      ];

  void _call(int idx, {String? id, String? name, String? args}) {
    final cur = _calls[idx] ?? ('', '', StringBuffer());
    _calls[idx] = (
      (id != null && id.isNotEmpty) ? id : cur.$1,
      (name != null && name.isNotEmpty) ? name : cur.$2,
      cur.$3..write(args ?? ''),
    );
  }

  List<String> add(String chunk) {
    _buf.write(chunk);
    final all = _buf.toString();
    final cut = all.lastIndexOf('\n');
    if (cut < 0) return const [];
    _buf
      ..clear()
      ..write(all.substring(cut + 1));
    final out = <String>[];
    for (final raw in all.substring(0, cut).split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') {
        done = true;
        continue;
      }
      Object? j;
      try {
        j = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (j is! Map) continue;
      final err = j['error'];
      if (err != null) {
        final msg = err is Map ? (err['message'] ?? err['type']) : err;
        throw AiException('服务商返回错误：${_cut('$msg', 120)}');
      }
      _usage(j['usage']);
      switch (j['type']) {
        case 'message_start':
          final msg = j['message'];
          if (msg is Map) _usage(msg['usage']);
          continue;
        case 'message_delta':
          final d = j['delta'];
          if (d is Map && d['stop_reason'] is String) {
            finish = switch (d['stop_reason'] as String) {
              'max_tokens' => 'length',
              'tool_use' => 'tool_calls',
              _ => 'stop',
            };
          }
          continue;
        case 'content_block_start':
          final b = j['content_block'];
          if (b is Map && b['type'] == 'tool_use') {
            _call((j['index'] as num?)?.toInt() ?? 0,
                id: b['id'] as String?, name: b['name'] as String?);
          }
          continue;
        case 'content_block_delta':
          final d = j['delta'];
          if (d is Map) {
            if (d['type'] == 'text_delta' && d['text'] is String) {
              final t = d['text'] as String;
              if (t.isNotEmpty) out.add(t);
            } else if (d['type'] == 'thinking_delta') {
              thinking = true;
            } else if (d['type'] == 'input_json_delta') {
              _call((j['index'] as num?)?.toInt() ?? 0,
                  args: d['partial_json'] as String?);
            }
          }
          continue;
        case 'message_stop':
          done = true;
          continue;
      }
      final choices = j['choices'];
      if (choices is List && choices.isNotEmpty) {
        final fr = (choices.first as Map)['finish_reason'];
        if (fr is String && fr.isNotEmpty) finish = fr;
        final delta = (choices.first as Map)['delta'];
        if (delta is Map) {
          final c = delta['content'];
          if (c is String && c.isNotEmpty) out.add(c);
          final r = delta['reasoning_content'];
          if (r is String && r.isNotEmpty) thinking = true;
          final tcs = delta['tool_calls'];
          if (tcs is List) {
            for (final t in tcs) {
              if (t is! Map) continue;
              final f = t['function'];
              _call((t['index'] as num?)?.toInt() ?? 0,
                  id: t['id'] as String?,
                  name: f is Map ? f['name'] as String? : null,
                  args: f is Map ? f['arguments'] as String? : null);
            }
          }
        }
      }
    }
    return out;
  }
}

class AiException implements Exception {
  final String message;

  final bool linkProblem;

  final int? statusCode;
  AiException(this.message, {this.linkProblem = true, this.statusCode});
  @override
  String toString() => message;
}

String redactKey(String s, String key) =>
    key.length < 6 ? s : s.replaceAll(key, '***');

String? normalizeAiBase(String raw) {
  var s = raw.trim();
  if (s.isEmpty) s = kAiProviders.first.base;
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  final u = Uri.tryParse(s);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  return s;
}

String aiErrorDetail(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map) {
      final e = j['error'];
      if (e is Map && e['message'] is String) return e['message'] as String;
      if (e is String) return e;
      if (j['message'] is String) return j['message'] as String;
    }
  } catch (_) {}
  return body;
}

final RegExp _kOverflowRe = RegExp(
  r'context[_\s-]?length|maximum context|too many tokens|token limit|'
  r'prompt is too long|reduce (?:the )?length|exceeds? (?:the )?(?:context|max|model)',
  caseSensitive: false,
);

final RegExp _kMaxTokensErrRe = RegExp(
  r'max_tokens|max_completion_tokens|max_output_tokens',
  caseSensitive: false,
);

bool aiIsContextOverflow(AiException e) =>
    e.statusCode == 413 ||
    (e.statusCode == 400 && _kOverflowRe.hasMatch(e.message));

bool aiIsMaxTokensError(AiException e) =>
    e.statusCode == 400 && _kMaxTokensErrRe.hasMatch(e.message);

bool aiIsTransientError(AiException e) {
  final c = e.statusCode;
  if (c == 429 || c == 502 || c == 503 || c == 529) return true;
  if (c == null && e.linkProblem && !e.message.contains('安全连接失败')) {
    return true;
  }
  return false;
}

String aiErrorText(int status, String body) {
  final raw = aiErrorDetail(body).trim();
  final d = _cut(raw, 120);
  final tail = d.isEmpty ? '' : '\n服务商说明：$d';
  return switch (status) {
    400 => _kOverflowRe.hasMatch(raw)
        ? '对话或单次内容太长（400）$tail'
        : '请求被拒绝（400），多半是模型名不对$tail',
    401 => 'API Key 不对或已失效，请到设置里重新填写$tail',
    402 => '账户余额不足，请到服务商控制台充值$tail',
    403 => '没有权限调用这个模型（或所在地区不支持）$tail',
    404 => '接口地址或模型名不对（404）$tail',
    413 => '请求内容太长（413）$tail',
    429 => '请求太频繁或额度用完了，稍后再试$tail',
    >= 500 => '服务商那边出错了（$status），稍后再试',
    _ => '请求失败（$status）$tail',
  };
}

Map<String, String> _authHeaders(AiConfig cfg) {
  final key = cfg.apiKey.trim();
  if (cfg.provider.protocol == AiProtocol.anthropic) {
    return {'x-api-key': key, 'anthropic-version': kAnthropicVersion};
  }
  return {
    HttpHeaders.authorizationHeader: 'Bearer $key',

    if (cfg.provider.id == 'mimo') 'api-key': key,
  };
}

String _chatPath(AiProtocol p) =>
    p == AiProtocol.anthropic ? '/messages' : '/chat/completions';

AiException _netError(Object e) => switch (e) {
      TimeoutException() => AiException('等太久没响应，检查一下网络再试'),
      HandshakeException() => AiException('安全连接失败（证书问题或网络被拦截）'),
      SocketException() => AiException('连不上服务器（网络不通或接口地址不对）'),
      _ => AiException('网络出错：$e'),
    };

Stream<String> aiChatStream({
  required AiConfig config,
  required String system,
  required List<AiMessage> history,
  List<AiToolSpec> tools = const [],
  void Function(List<AiToolCall> calls)? onToolCalls,
  void Function()? onThinking,
  HttpClient? client,

  int maxTurns = 16,
  int? budget,
  bool trim = true,
  int toolChars = 6000,
  int? maxOutput,
  bool enableSearch = false,

  void Function(AiStreamInfo info)? onDone,
}) async* {
  final miss = config.missing;
  if (miss != null) throw AiException(miss);
  final root = config.root!;
  final proto = config.provider.protocol;
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 15);
  try {
    final HttpClientResponse resp;
    try {
      final req = await http.postUrl(Uri.parse('$root${_chatPath(proto)}'));
      req.headers
          .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      _authHeaders(config).forEach(req.headers.set);
      req.followRedirects = false;
      req.add(utf8.encode(jsonEncode(aiRequestBody(
          proto, config.model.trim(), system, history,
          tools: tools,
          maxTurns: maxTurns,
          budget: budget,
          trim: trim,
          toolChars: toolChars,
          maxOutput: maxOutput ?? aiMaxOutputFor(config),
          enableSearch: enableSearch))));
      resp = await req.close().timeout(const Duration(seconds: 60));
    } catch (e) {
      throw _netError(e);
    }
    if (resp.statusCode != 200) {
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10), onTimeout: () => '');
      throw AiException(
        aiErrorText(resp.statusCode, redactKey(body, config.apiKey.trim())),
        linkProblem: resp.statusCode != 429 && resp.statusCode < 500,
        statusCode: resp.statusCode,
      );
    }
    final dec = SseDecoder();
    var told = false;
    try {
      await for (final chunk in resp
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 90))) {
        final pieces = dec.add(chunk);
        if (dec.thinking && !told) {
          told = true;
          onThinking?.call();
        }
        for (final piece in pieces) {
          yield piece;
        }
        if (dec.done) break;
      }
    } on AiException {
      rethrow;
    } catch (e) {
      throw _netError(e);
    }

    for (final piece in dec.add('\n')) {
      yield piece;
    }
    onToolCalls?.call(dec.toolCalls);
    onDone?.call(dec.info);
  } finally {
    if (client == null) http.close(force: true);
  }
}

class AiTestResult {
  final bool ok;
  final String message;
  final List<String> models;
  final int latencyMs;

  final Map<String, int> windows;
  const AiTestResult(this.ok, this.message,
      {this.models = const [], this.latencyMs = 0, this.windows = const {}});
}

Future<AiTestResult> aiTestConnection(AiConfig cfg) async {
  if (cfg.apiKey.trim().isEmpty) {
    return const AiTestResult(false, '还没填 API Key');
  }
  final root = cfg.root;
  if (root == null) return AiTestResult(false, cfg.missing ?? '接口地址不对');
  final models = await _listModels(cfg, root);
  final wins = models.$3;
  final sw = Stopwatch()..start();
  if (cfg.model.trim().isEmpty) {

    if (models.$2 != null) return AiTestResult(false, models.$2!);
    return AiTestResult(
      models.$1.isNotEmpty,
      models.$1.isNotEmpty ? 'Key 有效。再从下面选一个模型就能用了' : '服务商没有返回模型列表，请手动填模型名',
      models: models.$1,
      windows: wins,
    );
  }
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await http
        .postUrl(Uri.parse('$root${_chatPath(cfg.provider.protocol)}'));
    req.headers
        .set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    _authHeaders(cfg).forEach(req.headers.set);
    req.followRedirects = false;
    req.add(utf8.encode(jsonEncode(aiRequestBody(cfg.provider.protocol,
        cfg.model.trim(), '回答「好」。', const [AiMessage('user', 'ping')]))));
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final ms = sw.elapsedMilliseconds;
    if (resp.statusCode == 200) {
      final win = wins[cfg.model.trim()];
      return AiTestResult(
          true,
          '连接成功 · ${cfg.model.trim()} · 首包 $ms ms'
          '${win == null ? '' : ' · 上下文 ${aiTokensShort(win)}'}',
          models: models.$1,
          latencyMs: ms,
          windows: wins);
    }
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10), onTimeout: () => '');
    return AiTestResult(
        false, aiErrorText(resp.statusCode, redactKey(body, cfg.apiKey.trim())),
        models: models.$1, windows: wins);
  } catch (e) {
    return AiTestResult(false, _netError(e).message, models: models.$1, windows: wins);
  } finally {
    http.close(force: true);
  }
}

Future<(List<String>, String?, Map<String, int>)> _listModels(
    AiConfig cfg, String root) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await http.getUrl(Uri.parse('$root/models'));
    _authHeaders(cfg).forEach(req.headers.set);
    req.followRedirects = false;
    final resp = await req.close().timeout(const Duration(seconds: 15));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return (
        const <String>[],
        aiErrorText(resp.statusCode, redactKey(body, cfg.apiKey.trim())),
        const <String, int>{},
      );
    }
    if (resp.statusCode != 200) return (const <String>[], null, const <String, int>{});
    return (aiParseModelList(body), null, aiParseModelWindows(body));
  } catch (_) {
    return (const <String>[], null, const <String, int>{});
  } finally {
    http.close(force: true);
  }
}

Map<String, int> aiParseModelWindows(String body) {
  try {
    final data = (jsonDecode(body) as Map)['data'];
    if (data is! List) return const {};
    const keys = [
      'context_length',
      'context_window',
      'max_context_length',
      'max_model_len',
      'max_input_tokens',
      'input_token_limit',
      'inputTokenLimit',
    ];
    final out = <String, int>{};
    for (final m in data) {
      if (m is! Map || m['id'] is! String) continue;
      final id = (m['id'] as String).replaceFirst(RegExp(r'^models/'), '');
      for (final k in keys) {
        final v = m[k];
        final n = v is num ? v.toInt() : int.tryParse('$v');
        if (n != null && n >= 2048) {
          out[id] = n;
          break;
        }
      }
    }
    return out;
  } catch (_) {
    return const {};
  }
}

List<String> aiParseModelList(String body) {
  try {
    final data = (jsonDecode(body) as Map)['data'];
    if (data is! List) return const [];
    final skip = RegExp(r'embed|whisper|tts|dall-e|moderation|rerank|image|'
        r'audio|speech|vision-preview|search|transcribe|realtime',
        caseSensitive: false);
    final out = <String>{
      for (final m in data)
        if (m is Map && m['id'] is String)
          (m['id'] as String).replaceFirst(RegExp(r'^models/'), ''),
    }.where((id) => !skip.hasMatch(id)).toList()
      ..sort();
    return out.take(40).toList();
  } catch (_) {
    return const [];
  }
}
