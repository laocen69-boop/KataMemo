import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/ai_chat.dart';
import 'package:katamemo/ai_tools.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/backup_pack.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/grammar/grammar_repo.dart';
import 'package:katamemo/models.dart';
import 'package:katamemo/screens/ai_settings_screen.dart';
import 'package:katamemo/widgets/ai_chat_sheet.dart';
import 'package:katamemo/widgets/ai_markdown.dart';
import 'package:katamemo/widgets/ai_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WordCard card() => WordCard(
        id: 'makan',
        word: 'makan',
        wordClass: 'v',
        zh: '吃',
        senses: const [
          WordSense(def: 'memasukkan makanan ke dalam mulut', pos: 'v'),
        ],
        examples: const [
          WordExample(text: 'Saya makan nasi.', zh: '我吃米饭。'),
        ],
        gabunganKata: const ['makan angin', 'makan hati'],
      );

  group('服务商', () {
    test('十家都在、id 唯一、默认地址都是 https（自定义除外）', () {
      final ids = kAiProviders.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(
          ids,
          containsAll(<String>[
            'deepseek', 'ark', 'qwen', 'glm', 'minimax', 'mimo',
            'openai', 'claude', 'gemini', 'custom',
          ]));
      for (final p in kAiProviders.where((p) => !p.isCustom)) {
        expect(normalizeAiBase(p.base), isNotNull, reason: p.id);
        expect(p.console, startsWith('https://'), reason: p.id);
      }
      expect(aiProviderById('claude').protocol, AiProtocol.anthropic);
      expect(aiProviderById('不存在').id, 'deepseek');
    });

    test('AiConfig：缺 key / 缺模型 / 自定义缺地址都说清楚', () {
      final ds = aiProviderById('deepseek');
      expect(AiConfig(provider: ds, apiKey: '', model: 'm').missing,
          contains('API Key'));
      expect(AiConfig(provider: ds, apiKey: 'k', model: '').missing,
          contains('模型'));
      expect(AiConfig(provider: ds, apiKey: 'k', model: 'm').ready, isTrue);
      final cu = aiProviderById('custom');
      expect(AiConfig(provider: cu, apiKey: 'k', model: 'm').missing,
          contains('接口地址'));
      expect(
          AiConfig(
                  provider: cu,
                  apiKey: 'k',
                  model: 'm',
                  baseOverride: 'https://x.example.com/v1')
              .ready,
          isTrue);
    });
  });

  group('提示词与话题', () {
    test('单词话题：带 KBBI 释义、例句、搭配，并要求以资料为准', () {
      final c = aiWordContext(card());
      expect(c.key, 'word:makan');
      expect(c.system, contains('词头：makan'));
      expect(c.system, contains('中文释义：吃'));
      expect(c.system, contains('[v] memasukkan makanan ke dalam mulut'));
      expect(c.system, contains('Saya makan nasi.（我吃米饭。）'));
      expect(c.system, contains('makan angin、makan hati'));
      expect(c.system, contains('以下面提供的资料为准'));
      for (final (_, q) in c.quick) {
        expect(q, contains('makan'));
        expect(q, isNot(contains('{w}')));
      }
    });

    test('语法话题带页面正文；通用话题按需带今天学过的词', () {
      final g = aiGrammarContext(id: 'p1', title: '被动句', text: 'di- 被动……');
      expect(g.key, 'grammar:p1');
      expect(g.system, contains('di- 被动'));
      final none = aiGeneralContext();
      expect(none.quick.any((q) => q.$1 == '考考今天的词'), isFalse);
      final some = aiGeneralContext(recent: const [('rumah', '房子')]);
      expect(some.system, contains('rumah：房子'));
      expect(some.quick.first.$1, '考考今天的词');
    });

    test('显示前去掉 Markdown 记号', () {
      expect(aiPlainText('## 标题\n**makan** 是 `吃`'), '标题\nmakan 是 吃');
    });
  });

  group('请求体', () {
    final hist = [
      const AiMessage('assistant', '多出来的开头'),
      for (var i = 0; i < 20; i++) AiMessage(i.isEven ? 'user' : 'assistant', 'q$i'),
    ];

    test('OpenAI 兼容：system 作第一条、只留最近 N 条、开流式', () {
      final b = aiRequestBody(AiProtocol.openai, 'm', 'SYS', hist, maxTurns: 4);
      final msgs = b['messages'] as List;
      expect(b['stream'], true);
      expect((msgs.first as Map)['role'], 'system');
      expect((msgs[1] as Map)['role'], 'user', reason: '截断后首条必须是 user');
      expect((msgs.last as Map)['content'], 'q19');
    });

    test('Claude：顶层 system、带 max_tokens、不带 temperature', () {
      final b = aiRequestBody(AiProtocol.anthropic, 'm', 'SYS', hist, maxTurns: 4);

      final sys = (b['system'] as List).single as Map;
      expect(sys['text'], 'SYS');
      expect(sys['cache_control'], {'type': 'ephemeral'});
      expect(b['max_tokens'], isA<int>());
      expect(b.containsKey('temperature'), isFalse);
      final msgs = b['messages'] as List;
      expect((msgs.first as Map)['role'], 'user');
      expect(msgs.any((m) => (m as Map)['role'] == 'system'), isFalse);
    });
  });

  group('工具与图片的请求体', () {
    const spec = AiToolSpec('get_word', '取卡', {'type': 'object', 'properties': {}});
    final hist = [
      const AiMessage('user', '看看 makan', imageB64: 'QUJD', imageMime: 'image/png'),
      const AiMessage('assistant', '',
          toolCalls: [AiToolCall('t1', 'get_word', '{"id":"makan"}')]),
      const AiMessage('tool', '{"word":"makan"}', toolCallId: 't1', toolName: 'get_word'),
    ];

    test('OpenAI：tools / tool_calls / role tool / image_url', () {
      final b = aiRequestBody(AiProtocol.openai, 'm', 'S', hist, tools: const [spec]);
      expect(((b['tools'] as List).single as Map)['type'], 'function');
      final msgs = b['messages'] as List;
      final user = msgs[1] as Map;
      expect((user['content'] as List).any((p) => (p as Map)['type'] == 'image_url'), isTrue);
      final asst = msgs[2] as Map;
      expect(asst['content'], isNull);
      expect(((asst['tool_calls'] as List).single as Map)['id'], 't1');
      expect((msgs[3] as Map)['role'], 'tool');
      expect((msgs[3] as Map)['tool_call_id'], 't1');
    });

    test('Claude：tool_use / tool_result 块 / base64 图片 / input_schema', () {
      final b = aiRequestBody(AiProtocol.anthropic, 'm', 'S', hist, tools: const [spec]);
      expect(((b['tools'] as List).single as Map).containsKey('input_schema'), isTrue);
      final msgs = b['messages'] as List;
      final img = ((msgs[0] as Map)['content'] as List).first as Map;
      expect(img['type'], 'image');
      expect((img['source'] as Map)['media_type'], 'image/png');
      final use = ((msgs[1] as Map)['content'] as List).single as Map;
      expect(use['type'], 'tool_use');
      expect((use['input'] as Map)['id'], 'makan');
      final res = ((msgs[2] as Map)['content'] as List).single as Map;
      expect((msgs[2] as Map)['role'], 'user');
      expect(res['type'], 'tool_result');
      expect(res['tool_use_id'], 't1');
    });

    test('不带工具时：工具记录改写成文字，不原样发、也不丢', () {
      final b = aiRequestBody(AiProtocol.openai, 'm', 'S', hist);
      final msgs = b['messages'] as List;
      expect(b.containsKey('tools'), isFalse);
      expect(msgs.any((m) => (m as Map)['role'] == 'tool'), isFalse);
      expect(msgs.any((m) => (m as Map).containsKey('tool_calls')), isFalse);
      final all = '$msgs';
      expect(all, contains('〔调用工具 get_word'));
      expect(all, contains('〔工具结果 · get_word〕'));
      expect(all, contains('"word":"makan"'), reason: '工具结果的内容还在');
    });

    test('图片只随最近一条带图的消息发，更早的换成「[图片]」', () {
      final two = [
        const AiMessage('user', 'a', imageB64: 'AAA'),
        const AiMessage('assistant', 'x'),
        const AiMessage('user', 'b', imageB64: 'BBB'),
      ];
      final s = '${aiRequestBody(AiProtocol.openai, 'm', 'S', two)['messages']}';
      expect(s.contains('AAA'), isFalse);
      expect(s.contains('BBB'), isTrue);
      expect(s.contains('[图片]'), isTrue);
    });
  });

  group('SSE 解码', () {
    test('OpenAI：一行被切成两半也能拼对；[DONE] 置完成；推理增量置 thinking', () {
      final d = SseDecoder();
      const l1 = 'data: {"choices":[{"delta":{"content":"Sel"}}]}\n';
      const l2 = 'data: {"choices":[{"delta":{"content":"amat"}}]}\n\n';
      final out = <String>[
        ...d.add('data: {"choices":[{"delta":{"reasoning_content":"嗯"}}]}\n'),
        ...d.add(l1.substring(0, 20)),
        ...d.add(l1.substring(20) + l2.substring(0, 7)),
        ...d.add(l2.substring(7)),
        ...d.add(': keep-alive\n\ndata: [DONE]\n'),
      ];
      expect(out.join(), 'Selamat');
      expect(d.thinking, isTrue);
      expect(d.done, isTrue);
    });

    test('Claude：content_block_delta 的 text_delta；message_stop 置完成', () {
      final d = SseDecoder();
      final out = d.add('event: message_start\n'
          'data: {"type":"message_start","message":{}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hal"}}\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"o"}}\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n');
      expect(out.join(), 'Halo');
      expect(d.done, isTrue);
    });

    test('OpenAI 流式工具调用：按 index 拼 id / 名字 / 分段参数', () {
      final d = SseDecoder();
      d.add('data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"search_words","arguments":"{\\"que"}}]}}]}\n'
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"ry\\":\\"makan\\"}"}}]}}]}\n'
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n'
          'data: [DONE]\n');
      final c = d.toolCalls.single;
      expect(c.id, 'c1');
      expect(c.name, 'search_words');
      expect(c.argMap['query'], 'makan');
    });

    test('Claude 流式工具调用：content_block_start + input_json_delta', () {
      final d = SseDecoder();
      final text = d.add(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"我查一下"}}\n'
          'data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tu_1","name":"get_word","input":{}}}\n'
          'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"id\\": "}}\n'
          'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\\"makan\\"}"}}\n'
          'data: {"type":"message_stop"}\n');
      expect(text.join(), '我查一下');
      final c = d.toolCalls.single;
      expect(c.id, 'tu_1');
      expect(c.argMap['id'], 'makan');
    });

    test('流里的错误事件抛 AiException；坏 JSON / 空 content 跳过', () {
      final d = SseDecoder();
      expect(
          d.add('data: {"choices":[{"delta":{"content":""}}]}\n'
              'data: {oops\n'),
          isEmpty);
      expect(
          () => d.add('event: error\n'
              'data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}\n'),
          throwsA(isA<AiException>()));
    });
  });

  group('安全与杂项', () {
    test('地址必须 https；空 = 默认 DeepSeek；去尾斜杠', () {
      expect(normalizeAiBase(''), 'https://api.deepseek.com');
      expect(normalizeAiBase('https://api.example.com/v1/'),
          'https://api.example.com/v1');
      expect(normalizeAiBase('http://api.example.com'), isNull);
      expect(normalizeAiBase('api.example.com'), isNull);
    });

    test('错误信息：key 被抹掉；服务商的 error.message 被抠出来', () {
      const key = 'sk-test-1234567890';
      expect(redactKey('bad key sk-test-1234567890 !', key), 'bad key *** !');
      final t = aiErrorText(401, '{"error":{"message":"Invalid key"}}');
      expect(t, contains('API Key'));
      expect(t, contains('Invalid key'));
    });

    test('数据包设置白名单不含任何 ai_ 键（导出不能带走 key）', () {
      expect(kPackSettingKeys.where((k) => k.startsWith('ai')), isEmpty);
    });

    test('模型列表：去掉 embedding 等非对话模型、去 models/ 前缀、排序去重', () {
      final ms = aiParseModelList('{"data":[{"id":"models/gemini-x"},'
          '{"id":"text-embedding-3"},{"id":"gpt-a"},{"id":"gpt-a"}]}');
      expect(ms, ['gemini-x', 'gpt-a']);
      expect(aiParseModelList('not json'), isEmpty);
    });

    test('连接状态编解码；坏值回落「未测试」', () {
      const s = AiStatus(AiLinkState.ok, at: 5, model: 'm', latencyMs: 300);
      final back = AiStatus.decode(s.encode());
      expect(back.state, AiLinkState.ok);
      expect(back.latencyMs, 300);
      expect(AiStatus.decode('{坏').state, AiLinkState.unknown);
      expect(AiStatus.decode(null).label, '未测试');
    });

    test('会话缓存：按话题存取、超过上限丢最旧的', () {
      AiSessionCache.clearAll();
      AiSessionCache.put('a', const [AiMessage('user', 'hi')]);
      expect(AiSessionCache.get('a').single.content, 'hi');
      for (var i = 0; i < AiSessionCache.cap; i++) {
        AiSessionCache.put('k$i', const [AiMessage('user', 'x')]);
      }
      expect(AiSessionCache.get('a'), isEmpty);
      AiSessionCache.clearAll();
    });
  });

  group('设置存取', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('上午最小版的三键迁移到 DeepSeek；按服务商分开存；改了 key 状态作废', () async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final db = AppDb(dbPath: inMemoryDatabasePath);
      await db.metaSet('ai_key', 'sk-old-123456');
      final app = AppState(db);
      await app.init();
      expect(app.aiProviderId, 'deepseek');
      expect(app.aiConfig.apiKey, 'sk-old-123456');
      expect(app.aiConfig.model, 'deepseek-flash');
      expect(await db.metaGet('ai_key'), isNull, reason: '旧键迁移后删掉');

      await app.saveAiProvider('qwen', key: 'k2', model: 'qwen-plus', base: '');
      expect(app.aiProviderId, 'qwen');
      expect(app.aiConfigFor('deepseek').apiKey, 'sk-old-123456',
          reason: '切服务商不丢另一家的 key');
      await app.setAiStatus('qwen', const AiStatus(AiLinkState.ok, at: 1));
      expect(app.aiStatus.state, AiLinkState.ok);
      await app.saveAiProvider('qwen', key: 'k3', model: 'qwen-plus', base: '');
      expect(app.aiStatus.state, AiLinkState.unknown, reason: '换了 key 要重新验证');
    });
  });

  group('弹层', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(AiSessionCache.clearAll);

    Future<AppState> state() async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      return AppState(AppDb(dbPath: inMemoryDatabasePath));
    }

    Widget host(AppState app, Widget child) =>
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: ThemeData(
                useMaterial3: true, splashFactory: InkRipple.splashFactory),
            home: Scaffold(body: child),
          ),
        );

    testWidgets('没设置：显示「去设置」与支持的服务商，不出输入框', (tester) async {
      final app = (await tester.runAsync(state))!;
      await tester.pumpWidget(
          host(app, AiChatSheet(context: aiWordContext(card()))));
      await tester.pump();
      expect(find.text('去设置'), findsOneWidget);
      expect(find.textContaining('Claude'), findsWidgets);
      expect(find.byKey(const ValueKey('ai.input')), findsNothing);
    });

    testWidgets('点快捷提问：问题上屏、回答流式拼出；可重新回答；关掉再开接着聊',
        (tester) async {
      final app = (await tester.runAsync(state))!;
      late List<AiMessage> sent;
      var calls = 0;
      StreamController<String>? ctl;
      Widget sheet() => AiChatSheet(
            key: UniqueKey(),
            context: aiWordContext(card()),
            debugTurn: (h, _) {
              sent = h;
              calls++;
              ctl = StreamController<String>();
              return ctl!.stream;
            },
          );
      await tester.pumpWidget(host(app, sheet()));
      await tester.tap(find.byKey(const ValueKey('ai.quick.讲讲用法')));
      await tester.pump();
      expect(sent.single.content, contains('makan'));
      expect(find.byKey(const ValueKey('ai.thinking')), findsOneWidget);
      ctl!.add('makan 是');
      await tester.pump();
      ctl!.add('**「吃」**。');
      await ctl!.close();
      await tester.pump();
      await tester.pump();
      expect(find.text('makan 是「吃」。', findRichText: true), findsOneWidget,
          reason: 'Markdown 渲染：粗体记号不显示');
      expect(find.byKey(const ValueKey('ai.act.mn')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.act.regen')));
      await tester.pump();
      expect(calls, 2);
      expect(sent.last.role, 'user', reason: '重新回答 = 丢掉旧回答再问一次');
      ctl!.add('新回答');
      await ctl!.close();
      await tester.pump();
      await tester.pump();
      expect(find.text('新回答', findRichText: true), findsOneWidget);
      expect(find.text('makan 是「吃」。', findRichText: true), findsNothing);

      await tester.pumpWidget(host(app, const SizedBox()));
      await tester.pumpWidget(host(app, sheet()));
      await tester.pump();
      expect(find.text('新回答', findRichText: true), findsOneWidget);
    });

    testWidgets('空会话：快捷问题全部在屏；发首条即收起；新对话再回来', (tester) async {
      final app = (await tester.runAsync(state))!;
      StreamController<String>? ctl;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          key: UniqueKey(),
          context: aiWordContext(card()),
          debugTurn: (_, __) {
            ctl = StreamController<String>();
            return ctl!.stream;
          },
        ),
      ));
      await tester.pump();

      for (final label in ['讲讲用法', '近义词辨析', '怎么记', '考考我', '批改我的句子']) {
        expect(find.byKey(ValueKey('ai.quick.$label')), findsOneWidget,
            reason: '快捷问题「$label」应显示');
      }
      expect(find.text('更多问法'), findsOneWidget);
      expect(find.text('点一条开始，或直接输入问题'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.quick.讲讲用法')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.quick.讲讲用法')), findsNothing);
      expect(find.text('点一条开始，或直接输入问题'), findsNothing);

      ctl!.add('回答');
      await ctl!.close();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('ai.new')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.quick.讲讲用法')), findsOneWidget);
    });

    testWidgets('窄弹层 320dp：两行头部 + 空会话引导不溢出', (tester) async {
      final app = (await tester.runAsync(state))!;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiWordContext(card()),
          debugTurn: (_, __) => const Stream<String>.empty(),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ai.header.status')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.history')), findsOneWidget);
      expect(find.text('问一问'), findsOneWidget);
    });

    testWidgets('一个字没回就失败：报错卡 + 提问放回输入框', (tester) async {
      final app = (await tester.runAsync(state))!;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (_, __) => Stream<String>.error(AiException('连不上网络')),
        ),
      ));
      await tester.enterText(
          find.byKey(const ValueKey('ai.input')), 'Apa artinya?');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.error')), findsOneWidget);
      expect(find.text('连不上网络'), findsOneWidget);
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('ai.input')));
      expect(field.controller!.text, 'Apa artinya?');
    });

    testWidgets('工具调用：AI 想建词单 → 弹确认卡 → 同意后执行 → 第二轮回答', (tester) async {
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.db.upsertWords([
          {
            'id': 'makan',
            'word': 'makan',
            'tier': 't1',
            'rank': 1,
            'frequency': 100,
            'word_class': 'v',
            'zh': '吃',
            'senses': 'def=x',
            'enabled': 1,
            'favorite': 0,
            'user_word': 0,
          },
        ]);
        return a;
      }))!;
      var round = 0;
      late List<AiMessage> second;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            round++;
            if (round == 1) {
              onCalls(const [
                AiToolCall('c1', 'create_word_list', '{"name":"今天","ids":["makan"]}'),
              ]);
              return const Stream<String>.empty();
            }
            second = h;
            return Stream<String>.value('建好了。');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '建个词单');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('ai.confirm')), findsOneWidget);
      expect(find.textContaining('新建词单「今天」'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai.confirm.yes')));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      expect(round, 2);
      expect(second.any((m) => m.role == 'tool' && m.content.contains('list_id')), isTrue,
          reason: '第二轮带上了工具结果');
      expect(find.text('建好了。', findRichText: true), findsOneWidget);
      expect(find.textContaining('已新建词单「今天」'), findsOneWidget);
      final lists = (await tester.runAsync(() => app.db.listWordLists()))!;
      expect(lists.single.$2, '今天');
    });

    testWidgets('设置页：3 个 Tab 切换（模型配置 / 对话与入口 / 说明与参考）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        return a;
      }))!;
      await tester.pumpWidget(host(app, const AiSettingsScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.tab.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.tab.1')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.tab.2')), findsOneWidget);
      expect(find.text('选择服务商'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.tab.1')));
      await tester.pumpAndSettle();
      expect(find.text('我的印尼语水平'), findsOneWidget);
      expect(find.text('联网搜索（可选）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.tab.2')));
      await tester.pumpAndSettle();
      expect(find.text('隐私与费用'), findsOneWidget);
      expect(find.text('印尼语能力参考（第三方）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.tab.0')));
      await tester.pumpAndSettle();
      expect(find.text('选择服务商'), findsOneWidget);
    });

    testWidgets('设置页：选服务商、保存并使用；当前卡跟着变', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        return a;
      }))!;
      await tester.pumpWidget(host(app, const AiSettingsScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.current')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai.provider.claude')));
      await tester.pump();
      expect(find.text('Claude 设置'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.console')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ai.key')), 'sk-ant-x');
      await tester.enterText(
          find.byKey(const ValueKey('ai.model')), 'claude-opus-5-5');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.save')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(app.aiProviderId, 'claude');
      expect(app.aiConfig.model, 'claude-opus-5-5');
      expect(find.text('正在使用 · Claude'), findsOneWidget);
    });

    testWidgets('设置页·联网搜索：默认不联网；选 Tavily 填 Key 保存后可用，并显示免费额度', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        return a;
      }))!;
      await tester.pumpWidget(host(app, const AiSettingsScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai.tab.1')));
      await tester.pumpAndSettle();
      expect(find.text('联网搜索（可选）'), findsOneWidget);
      expect(find.textContaining('每月 1000 次免费'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.search.key')), findsNothing, reason: '没选 Tavily 不出输入框');
      expect(find.byKey(const ValueKey('ai.recommendTag')), findsWidgets);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.search.opt.tavily')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(app.aiSearchProviderId, 'tavily');
      expect(find.byKey(const ValueKey('ai.search.key')), findsOneWidget);
      expect(app.aiSearchReady, isFalse, reason: '还没填 Key');
      expect(find.byKey(const ValueKey('ai.search.used')), findsOneWidget);
      expect(find.textContaining('免费 1000 次'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('ai.search.key')), 'tvly-test');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.search.save')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(app.aiSearchReady, isTrue);
      expect(app.aiSearchKeyFor('tavily'), 'tvly-test');
    });

    testWidgets('设置页·联网搜索：选 DeepSeek 搜索时提示复用 Key；没填 DeepSeek Key 给红字提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        return a;
      }))!;
      await tester.pumpWidget(host(app, const AiSettingsScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai.tab.1')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.search.opt.deepseek')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.search.key')), findsNothing, reason: '复用 DeepSeek Key，不另填');
      expect(find.textContaining('还没填 DeepSeek 的 Key'), findsOneWidget);
      await tester.runAsync(() => app.saveAiProvider('deepseek',
          key: 'sk-1', model: 'deepseek-flash', base: '', select: false));
      await tester.pump();
      expect(find.textContaining('已用 AI 设置里的 DeepSeek Key'), findsOneWidget);
      expect(app.aiSearchReady, isTrue);
    });

    testWidgets('悬浮球：连好才出现；关掉开关就消失', (tester) async {
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        return a;
      }))!;
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          navigatorKey: kRootNavKey,
          builder: (c, child) => Stack(children: [
            Positioned.fill(child: child!),
            const Positioned.fill(child: AiFloatingBall()),
          ]),
          home: const Scaffold(body: SizedBox()),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.fab')), findsNothing, reason: '没连好');
      await tester.runAsync(() => app.saveAiProvider('deepseek',
          key: 'sk-1', model: 'deepseek-chat', base: ''));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.fab')), findsOneWidget);
      await tester.runAsync(() => app.setAiFab(false));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.fab')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('回答排版：中文旁的粗体不露星号；批改表格在窄屏不溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiMarkdown('### 批改\n这是**「吃」**的意思。\n\n'
                '| 原句 | 改后 | 原因 |\n|---|---|---|\n'
                '| Saya bukan suka makan pedas sekali | **Saya tidak suka makan pedas** | tidak 否定动词，bukan 否定名词 |\n\n'
                '> 规则：形容词前不用 adalah'),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '表格按比例收进宽度，不报溢出');
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.text('这是「吃」的意思。', findRichText: true), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
    });

    testWidgets('状态胶囊：未设置 / 已连接 / 连接失败', (tester) async {
      Widget pill(AiStatus s, {bool configured = true}) => MaterialApp(
          home: Scaffold(body: AiStatusPill(status: s, configured: configured)));
      await tester.pumpWidget(pill(AiStatus.unknown, configured: false));
      expect(find.text('未设置'), findsOneWidget);
      await tester.pumpWidget(pill(const AiStatus(AiLinkState.ok)));
      expect(find.text('已连接'), findsOneWidget);
      await tester.pumpWidget(pill(const AiStatus(AiLinkState.fail)));
      expect(find.text('连接失败'), findsOneWidget);
    });
  });

  group('aiTrimHistory · 长任务不丢原始需求', () {
    AiMessage user(String t) => AiMessage('user', t);
    AiMessage say(String t) => AiMessage('assistant', t);
    AiMessage calls(String id) =>
        AiMessage('assistant', '', toolCalls: [AiToolCall(id, 'search', '{}')]);
    AiMessage result(String id) =>
        AiMessage('tool', 'r-$id', toolCallId: id, toolName: 'search');

    test('单轮里工具往返很多：整段保留，首条仍是用户原话', () {
      final h = <AiMessage>[user('帮我把今天错的语法题整理成清单')];
      for (var i = 0; i < 10; i++) {
        h.add(calls('c$i'));
        h.add(result('c$i'));
      }
      final t = aiTrimHistory(h);
      expect(t.first.content, '帮我把今天错的语法题整理成清单');
      expect(t.length, h.length, reason: '当前这一轮一条都不许裁');
    });

    test('前面还有旧对话：旧对话整轮丢弃，不切断 tool 对', () {
      final h = <AiMessage>[
        user('旧问题一'), say('旧回答一'),
        user('旧问题二'), say('旧回答二'),
        user('当前任务'),
        calls('c1'), result('c1'),
        calls('c2'), result('c2'),
      ];

      final tight = aiTrimHistory(h, maxTurns: 6);
      expect(tight.first.role, 'user');
      expect(tight.first.content, '当前任务',
          reason: '窗口不够时，当前这一轮必须完整保留，旧对话整轮丢');
      expect(tight.last.toolCallId, 'c2');

      final wide = aiTrimHistory(h, maxTurns: 20);
      expect(wide.first.content, '旧问题一');
      expect(wide.first.role, 'user');
      expect(wide.length, h.length);
    });

    test('当前轮超过窗口：仍然全部保留（宁多勿缺）', () {
      final h = <AiMessage>[user('很长的一步一步的任务')];
      for (var i = 0; i < 30; i++) {
        h.add(calls('k$i'));
        h.add(result('k$i'));
      }
      expect(aiTrimHistory(h).length, h.length);
    });

    test('没有 user：返回空（Claude 要求以 user 开头，发出去也会被拒）', () {
      expect(aiTrimHistory([say('孤立回答'), result('x')]), isEmpty);
      expect(aiTrimHistory(const <AiMessage>[]), isEmpty);
    });
  });

  group('2026-11 模型推荐与 ASR/TTS 入口', () {
    test('Gemini 推荐 gemini-4-hydrogen + Gemma 4 备选；Qwen/DeepSeek 含备选与原生联网备注', () {
      final gem = aiProviderById('gemini');
      expect(gem.modelHint, 'gemini-4-hydrogen');
      expect(gem.extraModels.map((e) => e.$1), containsAll(['gemma-4-31b-it', 'gemma-4-4b-it']));
      expect(gem.nativeSearch, isTrue);
      expect(gem.searchNote, isNotEmpty);

      final qwen = aiProviderById('qwen');
      expect(qwen.modelHint, 'qwen3.5-flash');
      expect(qwen.extraModels.map((e) => e.$1), containsAll(['qwen3.5-35b-a3b', 'qwen3.5-9b']));
      expect(qwen.nativeSearch, isTrue);

      final ds = aiProviderById('deepseek');
      expect(ds.modelHint, 'deepseek-flash');
      expect(ds.extraModels, isEmpty);
      expect(ds.nativeSearch, isTrue);
    });

    test('AppState.saveAiSpeech 默认未接入；配置开启后变为已接入', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final app = AppState(AppDb(dbPath: inMemoryDatabasePath));
      await app.init();
      expect(app.aiAsrConfigured, isFalse);
      expect(app.aiTtsConfigured, isFalse);

      await app.saveAiSpeech(
        isAsr: true,
        enabled: true,
        endpoint: 'https://api.deepseek.com/v1/tools/asr',
        model: 'deepseek-asr',
        apiKey: '',
      );
      expect(app.aiAsrConfigured, isTrue);
      expect(app.aiAsrConfig.model, 'deepseek-asr');
      expect(app.aiTtsConfigured, isFalse);

      await app.saveAiSpeech(
        isAsr: false,
        enabled: true,
        endpoint: 'https://api.deepseek.com/v1/tools/tts',
        model: 'stella',
        apiKey: '',
      );
      expect(app.aiTtsConfigured, isTrue);
      expect(app.aiTtsConfig.model, 'stella');

      await app.saveAiSpeech(
        isAsr: true,
        enabled: false,
        endpoint: 'https://api.deepseek.com/v1/tools/asr',
        model: 'deepseek-asr',
        apiKey: '',
      );
      expect(app.aiAsrConfigured, isFalse);
    });

    test('searchGrammarPages 支持长词中文切分回退（如「被动语态」命中「被动句」）', () {
      final repo = GrammarRepo(autoLoad: false)
        ..loadFromJson(jsonEncode({
          'v': 1,
          'sections': [
            {'id': 's1', 'title': '句法', 'title_id': 'Sintaksis'}
          ],
          'pages': [
            {
              'id': 'x-passive',
              'section': 's1',
              'title': '被动句',
              'title_id': 'Kalimat Pasif',
              'summary': '三种被动构造',
              'aliases': ['被动', 'pasif', 'di-'],
              'blocks': [],
            },
          ],
        }));
      final hits = searchGrammarPages(repo, '被动语态');
      expect(hits.map((p) => p.id), contains('x-passive'));
      expect(searchGrammarPages(repo, '不存在的词'), isEmpty);
    });

    test('aiMaxOutputFor 默认跟随模型（OpenAI兼容不传 max_tokens，Claude 兜底），支持全局自选覆盖',
        () async {
      final deepseekCfg = AiConfig(
          provider: aiProviderById('deepseek'), apiKey: 'k', model: 'deepseek-flash');
      final mimoCfg = AiConfig(
          provider: aiProviderById('mimo'), apiKey: 'k', model: 'mimo-v2.6-flash');
      final qwenCfg = AiConfig(
          provider: aiProviderById('qwen'), apiKey: 'k', model: 'qwen3.5-flash');
      final claudeCfg = AiConfig(
          provider: aiProviderById('claude'), apiKey: 'k', model: 'claude-sonnet-4-6');
      final customCfg = AiConfig(
          provider: aiProviderById('custom'), apiKey: 'k', model: 'my-model');

      expect(aiMaxOutputFor(deepseekCfg), isNull);
      expect(aiMaxOutputFor(mimoCfg), isNull);
      expect(aiMaxOutputFor(qwenCfg), isNull);
      expect(aiMaxOutputFor(customCfg), isNull);
      expect(aiMaxOutputFor(claudeCfg), kAiMaxOutput);

      final openBody = aiRequestBody(
        AiProtocol.openai,
        'deepseek-flash',
        'sys',
        [const AiMessage('user', 'hi')],
        maxOutput: aiMaxOutputFor(deepseekCfg),
      );
      expect(openBody.containsKey('max_tokens'), isFalse);

      final claudeBody = aiRequestBody(
        AiProtocol.anthropic,
        'claude-sonnet-4-6',
        'sys',
        [const AiMessage('user', 'hi')],
        maxOutput: aiMaxOutputFor(claudeCfg),
      );
      expect(claudeBody['max_tokens'], kAiMaxOutput);

      expect(aiMaxOutputFor(deepseekCfg, customMaxOutput: 393216), 393216);
      expect(aiMaxOutputFor(customCfg, customMaxOutput: 131072), 131072);

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      final app = AppState(AppDb(dbPath: inMemoryDatabasePath));
      await app.init();
      await app.saveAiProvider('deepseek',
          key: 'k', model: 'deepseek-flash', base: '');
      expect(app.aiCustomMaxOutput, isNull);
      expect(app.aiMaxOutput, isNull);
      await app.setAiCustomMaxOutput(393216);
      expect(app.aiCustomMaxOutput, 393216);
      expect(app.aiMaxOutput, 393216);
      await app.setAiCustomMaxOutput(null);
      expect(app.aiCustomMaxOutput, isNull);
      expect(app.aiMaxOutput, isNull);
    });

    test('aiIsContextOverflow 与 aiIsTransientError 准确分流故障类型', () {
      expect(
          aiIsContextOverflow(
              AiException('对话太长', statusCode: 413)),
          isTrue);
      expect(
          aiIsContextOverflow(AiException(
              '请求被拒绝（400）\n服务商说明：maximum context length exceeded',
              statusCode: 400)),
          isTrue);
      expect(
          aiIsContextOverflow(AiException(
              '请求被拒绝（400）\n服务商说明：tools not supported',
              statusCode: 400)),
          isFalse);

      expect(aiIsTransientError(AiException('429', statusCode: 429)), isTrue);
      expect(aiIsTransientError(AiException('503', statusCode: 503)), isTrue);
      expect(aiIsTransientError(AiException('超时', linkProblem: true)), isTrue);
      expect(
          aiIsTransientError(
              AiException('安全连接失败（证书问题或网络被拦截）', linkProblem: true)),
          isFalse);
      expect(aiIsTransientError(AiException('401', statusCode: 401)), isFalse);

      expect(
          aiErrorText(400, '{"error":{"message":"context_length_exceeded"}}'),
          contains('太长'));
      expect(aiErrorText(413, ''), contains('413'));
      expect(
          aiIsMaxTokensError(AiException(
              '请求被拒绝（400）\n服务商说明：Invalid max_tokens value',
              statusCode: 400)),
          isTrue);
      expect(
          aiIsMaxTokensError(AiException(
              '请求被拒绝（400）\n服务商说明：tools not supported',
              statusCode: 400)),
          isFalse);
    });

    test('aiShouldEnableNativeSearch 与 enable_search 请求体参数', () {
      final qwenOfficial = AiConfig(
        provider: aiProviderById('qwen'),
        apiKey: 'k',
        model: 'qwen3.5-flash',
        baseOverride: '',
      );
      expect(aiShouldEnableNativeSearch(qwenOfficial), isTrue);
      expect(
          aiShouldEnableNativeSearch(qwenOfficial, searchExplicitlyOff: true),
          isFalse);

      final qwenCustomProxy = AiConfig(
        provider: aiProviderById('qwen'),
        apiKey: 'k',
        model: 'qwen3.5-flash',
        baseOverride: 'https://proxy.example.com/v1',
      );
      expect(aiShouldEnableNativeSearch(qwenCustomProxy), isFalse);

      final arkCfg = AiConfig(
        provider: aiProviderById('ark'),
        apiKey: 'k',
        model: 'doubao-seed',
        baseOverride: '',
      );
      expect(aiShouldEnableNativeSearch(arkCfg), isFalse);

      final withSearch = aiRequestBody(
        AiProtocol.openai,
        'qwen3.5-flash',
        'sys',
        const [AiMessage('user', 'hi')],
        enableSearch: true,
      );
      expect(withSearch['enable_search'], isTrue);

      final withoutSearch = aiRequestBody(
        AiProtocol.openai,
        'qwen3.5-flash',
        'sys',
        const [AiMessage('user', 'hi')],
      );
      expect(withoutSearch.containsKey('enable_search'), isFalse);
    });

    test('normalizeMarkdownTables 修复缺空行/4空格缩进/Unicode横线/列数不齐的 AI 表格', () {
      const messy = '对照如下：\n'
          '    原句 | 改后 | 原因\n'
          '    ───|───\n'
          '    Saya makan | Saya sudah makan | 补时间词\n'
          '接下来看例句。';
      final fixed = normalizeMarkdownTables(messy);
      expect(
        fixed,
        '对照如下：\n\n'
        '| 原句 | 改后 | 原因 |\n'
        '| --- | --- | --- |\n'
        '| Saya makan | Saya sudah makan | 补时间词 |\n\n'
        '接下来看例句。',
      );

      const fenced = '```markdown\nA | B\n---|---\n1 | 2\n```';
      expect(normalizeMarkdownTables(fenced), fenced);
    });
  });

}
