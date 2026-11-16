import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/ai_chat.dart';
import 'package:katamemo/ai_tools.dart';
import 'package:katamemo/app_state.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/screens/ai_settings_screen.dart';
import 'package:katamemo/widgets/ai_chat_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AiMessage u(String t) => AiMessage('user', t);
  AiMessage say(String t) => AiMessage('assistant', t);
  AiMessage calls(String id, [String name = 'search_words']) =>
      AiMessage('assistant', '', toolCalls: [AiToolCall(id, name, '{"q":"$id"}')]);
  AiMessage result(String id, String body) =>
      AiMessage('tool', body, toolCallId: id, toolName: 'search_words', label: '查了 $id');

  void expectPaired(List<AiMessage> ms) {
    final open = <String>{};
    for (final m in ms) {
      if (m.role == 'assistant') open.addAll(m.toolCalls.map((c) => c.id));
      if (m.role == 'tool') expect(open, contains(m.toolCallId), reason: '孤立的 tool 消息');
    }
  }

  group('模型窗口与档位', () {
    test('服务商报的长度优先；名字里写明的长度其次；再按家族；认不出按 32K', () {
      expect(aiModelWindow('deepseek-flash', detected: 64000).tokens, 64000);
      expect(aiModelWindow('deepseek-flash', detected: 64000).source, contains('模型列表'));
      expect(aiModelWindow('moonshot-v1-8k').tokens, 8000);
      expect(aiModelWindow('qwen-long').tokens, 1000000);
      expect(aiModelWindow('qwen3.5-flash').tokens, 1000000);
      expect(aiModelWindow('qwen3.5-9b').tokens, 262144);
      expect(aiModelWindow('deepseek-flash').tokens, 1000000);
      expect(aiModelWindow('gemini-4-hydrogen').tokens, 1000000);
      expect(aiModelWindow('gemma-4-31b-it').tokens, 256000);
      expect(aiModelWindow('gemma-4-4b-it').tokens, 128000);
      expect(aiModelWindow('claude-haiku-5-5').tokens, 200000);
      expect(aiModelWindow('my-local-model').tokens, kAiUnknownWindow);
      expect(aiModelWindow('my-local-model').source, contains('未识别'));
    });

    test('自动 = 直接按模型各自最大安全上下文（75% 窗口），不再人为设 48K 封顶', () {
      final big = aiBudgetFor(AiCtxTier.auto, const AiModelWindow(128000, 'x'));
      expect(big.input, 96000);
      expect(big.rounds, 60);
      expect(big.toolChars, 12000);
      final big1m = aiBudgetFor(AiCtxTier.auto, const AiModelWindow(1000000, 'x'));
      expect(big1m.input, 750000);
      final bigTools =
          aiBudgetFor(AiCtxTier.auto, const AiModelWindow(128000, 'x'), forTools: true);
      expect(bigTools.input, 96000);
      expect(bigTools.rounds, 80);
      expect(bigTools.toolChars, 12000);

      final small = aiBudgetFor(AiCtxTier.auto, const AiModelWindow(32000, 'x'));
      expect(small.input, 24000);
      expect(small.rounds, 60);

      final eco = aiBudgetFor(AiCtxTier.economy, const AiModelWindow(128000, 'x'));
      expect(eco.input, 16000);
      expect(eco.toolChars, 3000);
      final ecoTools =
          aiBudgetFor(AiCtxTier.economy, const AiModelWindow(128000, 'x'), forTools: true);
      expect(ecoTools.input, 48000);
      expect(ecoTools.rounds, 45);
      expect(ecoTools.toolChars, 4000);

      expect(kAiCtxUiTiers, [AiCtxTier.auto, AiCtxTier.economy]);
      expect(aiCtxTierFromName('long'), AiCtxTier.long);
      expect(aiCtxTierFromName('full'), AiCtxTier.full);
      expect(aiCtxTierFromName('乱写'), AiCtxTier.auto);
      expect(aiTokensShort(128000), '128K');
      expect(aiTokensShort(1000000), '1M');
    });

    test('同会话跨轮压缩 aiSessionCompactRange 与长期记忆裁剪 aiClipMemory', () {
      final h = <AiMessage>[
        u('第一问：apa artinya makan'),
        say('吃。' * 100),
        u('第二问：imbuhan me-'),
        calls('c1'),
        result('c1', '词缀资料' * 100),
        say('解释完毕。'),
        u('第三问：contoh kalimat'),
        say('Saya makan nasi.'),
        u('第四问：terima kasih'),
        say('Sama-sama.'),
      ];

      expect(
          aiSessionCompactRange(h, budget: 48000, maxTokens: 99999), isNull);

      final r = aiSessionCompactRange(h,
          budget: 48000, keepRecentTurns: 2, maxTokens: 99999, force: true);
      expect(r, isNotNull);
      expect(r!.start, 0);
      expect(r.end, 6);
      expect(r.turns, 2);
      expect(h[r.end].role, 'user');
      expect(h[r.end].content, contains('第三问'));
      expectPaired(h.sublist(r.end));

      expect(aiClipMemory('a' * 600).length, lessThanOrEqualTo(kAiMemoryMaxChars));
    });

    test('token 估算：汉字约 1 个，其余约 3.6 字符 1 个', () {
      expect(aiEstimateTokens('你好'), 2);
      expect(aiEstimateTokens('a' * 36), 10);
      expect(aiMessageTokens(const AiMessage('user', '', imageB64: 'x')), greaterThan(1000));
    });

    test('模型列表里的上下文长度：认得几种字段名，去 models/ 前缀', () {
      const body = '{"data":[{"id":"a","context_length":131072},'
          '{"id":"models/b","inputTokenLimit":1048576},{"id":"c","max_model_len":"32768"},'
          '{"id":"d"},{"id":"e","context_length":100}]}';
      expect(aiParseModelWindows(body), {'a': 131072, 'b': 1048576, 'c': 32768});
      expect(aiParseModelWindows('不是 JSON'), isEmpty);
    });
  });

  group('aiPackHistory · 按 token 装箱', () {
    test('当前这一轮整段保留，首条是用户原话', () {
      final h = <AiMessage>[u('帮我把今天错的语法题整理成清单')];
      for (var i = 0; i < 20; i++) {
        h
          ..add(calls('c$i'))
          ..add(result('c$i', '结果$i'));
      }
      final p = aiPackHistory(h, budget: 100000);
      expect(p.msgs.length, h.length);
      expect(p.msgs.first.content, contains('语法题'));
      expect(p.over, isFalse);
      expectPaired(p.msgs);
    });

    test('超预算：先缩短较早的工具结果，最近 4 条不动；仍保留成对', () {
      final h = <AiMessage>[u('长任务')];
      for (var i = 0; i < 10; i++) {
        h
          ..add(calls('c$i'))
          ..add(result('c$i', '字' * 3000));
      }
      final p = aiPackHistory(h, budget: 16000);
      expect(p.shrunk, greaterThan(0));
      final tools = p.msgs.where((m) => m.role == 'tool').toList();
      expect(tools.length, 10, reason: '一条都不丢，只是变短');
      expect(tools.first.content, contains('已截断'));
      expect(tools.last.content.length, 3000, reason: '最近的结果原样保留');
      expect(p.tokens, lessThanOrEqualTo(16000));
      expectPaired(p.msgs);
    });

    test('旧对话按整轮丢；上一轮的工具结果最多 1500 字', () {
      final h = <AiMessage>[
        u('第一轮'), calls('a'), result('a', '旧' * 5000), say('答一'),
        u('第二轮'), calls('b'), result('b', '中' * 5000), say('答二'),
        u('第三轮'),
      ];
      final p = aiPackHistory(h, budget: 1700);
      expect(p.msgs.first.content, '第二轮');
      expect(p.droppedTurns, 1);
      final prev = p.msgs.firstWhere((m) => m.role == 'tool');
      expect(prev.content, contains('已截断'));
      expect(prev.content.length, lessThan(1600));
      expectPaired(p.msgs);
    });

    test('单条工具结果超过 toolChars 也会截断并注明', () {
      final p = aiPackHistory([u('q'), calls('x'), result('x', 'y' * 9000)],
          budget: 100000, toolChars: 6000);
      expect(p.msgs.last.content, contains('原文 9000 字'));
    });

    test('没有 user：返回空', () {
      expect(aiPackHistory([say('孤立')], budget: 1000).msgs, isEmpty);
    });

    test('请求体给了 budget 就按 token 装箱', () {
      final h = <AiMessage>[
        for (var i = 0; i < 30; i++) ...[u('问$i ${'长' * 400}'), say('答$i ${'长' * 400}')],
        u('最后一问'),
      ];
      final b = aiRequestBody(AiProtocol.openai, 'm', 'S', h, budget: 3000);
      final msgs = b['messages'] as List;
      expect((msgs[1] as Map)['role'], 'user');
      expect((msgs.last as Map)['content'], '最后一问');
      expect(msgs.length, lessThan(h.length));
    });
  });

  group('压缩区间 · aiCompactRangeTokens', () {
    List<AiMessage> long(int n, int size) => [
          u('很长的任务'),
          for (var i = 0; i < n; i++) ...[calls('c$i'), result('c$i', '字' * size)],
        ];

    test('不到预算的 60% 不压', () {
      expect(aiCompactRangeTokens(long(3, 100), budget: 20000), isNull);
      expect(aiCompactRangeTokens(const [], budget: 20000), isNull);
      expect(aiCompactRangeTokens([say('孤立')], budget: 10), isNull);
    });

    test('超过就压：从 user 之后开始，尾部不以 tool 开头，至少留 2 条', () {
      final h = long(12, 2000);
      final r = aiCompactRangeTokens(h, budget: 20000);
      expect(r, isNotNull);
      expect(r!.start, 1);
      expect(h[r.end].role, isNot('tool'));
      expect(h.length - r.end, greaterThanOrEqualTo(2));
      expect(aiMessagesTokens(h.sublist(r.end)), lessThanOrEqualTo(20000 * 0.3 + 3000));
    });

    test('压过一次后从上次的终点接着算', () {
      final h = long(12, 2000);
      final first = aiCompactRangeTokens(h, budget: 20000)!;
      h.addAll([for (var i = 20; i < 30; i++) ...[calls('d$i'), result('d$i', '字' * 2000)]]);
      final second = aiCompactRangeTokens(h, budget: 20000, from: first.end)!;
      expect(second.start, first.end);
      expect(second.end, greaterThan(first.end));
    });
  });

  group('不带工具时改写工具记录 · aiFlattenTools', () {
    test('调用 → 助手说明；结果 → 用户资料；相邻同角色合并', () {
      final f = aiFlattenTools([
        u('查两个词'),
        const AiMessage('assistant', '我查一下', toolCalls: [
          AiToolCall('1', 'get_word', '{"id":"a"}'),
          AiToolCall('2', 'get_word', '{"id":"b"}'),
        ]),
        const AiMessage('tool', '{"word":"a"}', toolCallId: '1', toolName: 'get_word'),
        const AiMessage('tool', '{"word":"b"}', toolCallId: '2', toolName: 'get_word'),
      ]);
      expect(f.map((m) => m.role).toList(), ['user', 'assistant', 'user']);
      expect(f[1].content, contains('我查一下'));
      expect(f[1].content, contains('〔调用工具 get_word'));
      expect(f[2].content, allOf(contains('"word":"a"'), contains('"word":"b"')));
      expect(f.any((m) => m.toolCalls.isNotEmpty || m.role == 'tool'), isFalse);
    });

    test('Claude 收尾请求：没有 tool_use / tool_result，最后一条打缓存标记', () {
      final b = aiRequestBody(AiProtocol.anthropic, 'm', 'S',
          [u('任务'), calls('x'), result('x', '{"n":1}')]);
      final s = '${b['messages']}';
      expect(s.contains('tool_use'), isFalse);
      expect(s.contains('tool_result'), isFalse);
      expect(s, contains('"n":1'));
      final last = ((b['messages'] as List).last as Map)['content'] as List;
      expect((last.last as Map)['cache_control'], {'type': 'ephemeral'});
      expect(b['max_tokens'], kAiMaxOutput);
    });
  });

  group('SSE：为什么停、用了多少', () {
    test('OpenAI：finish_reason=length 判为截断；DeepSeek 的缓存命中数', () {
      final d = SseDecoder()
        ..add('data: {"choices":[{"delta":{"content":"半句"},"finish_reason":null}]}\n')
        ..add('data: {"choices":[{"delta":{},"finish_reason":"length"}],'
            '"usage":{"prompt_tokens":900,"completion_tokens":4096,"prompt_cache_hit_tokens":640}}\n');
      expect(d.info.truncated, isTrue);
      expect(d.info.inputTokens, 900);
      expect(d.info.outputTokens, 4096);
      expect(d.info.cachedTokens, 640);
    });

    test('Claude：message_delta 的 stop_reason=max_tokens → length；用量分两处报', () {
      final d = SseDecoder()
        ..add('data: {"type":"message_start","message":{"usage":{"input_tokens":1200,'
            '"cache_read_input_tokens":1000}}}\n')
        ..add('data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},'
            '"usage":{"output_tokens":8192}}\n');
      expect(d.finish, 'length');
      expect(d.inputTokens, 1200);
      expect(d.cachedTokens, 1000);
      expect(d.outputTokens, 8192);
      final ok = SseDecoder()
        ..add('data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n');
      expect(ok.info.truncated, isFalse);
    });
  });

  group('任务清单', () {
    test('认字符串和对象；状态不认识就当 pending；最多 12 步', () {
      final p = aiParsePlan([
        '查错题',
        {'text': '归类', 'status': 'done'},
        {'text': '出题', 'status': 'doing'},
        {'text': '总结', 'status': '乱写'},
        {'status': 'done'},
      ]);
      expect(p.map((s) => s.status).toList(), ['pending', 'done', 'doing', 'pending']);
      expect(aiPlanText(p), contains('2. [✓] 归类'));
      expect(aiParsePlan('不是列表'), isEmpty);
      expect(aiParsePlan(List.generate(25, (i) => '步$i')).length, 20);
    });

    test('工具声明里有 task_plan，search_words 支持 queries、get_word 支持 ids', () {
      final names = kAiToolSpecList.map((s) => s.name).toSet();
      expect(names, contains('task_plan'));
      final sw = kAiToolSpecList.firstWhere((s) => s.name == 'search_words');
      expect('${sw.parameters}', contains('queries'));
      final gw = kAiToolSpecList.firstWhere((s) => s.name == 'get_word');
      expect('${gw.parameters}', contains('ids'));
      expect(kAiAgentRules, contains('task_plan'));
    });
  });

  group('弹层 · 长任务', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(AiSessionCache.clearAll);

    Future<AppState> state() async {
      await databaseFactory.deleteDatabase(inMemoryDatabasePath);
      return AppState(AppDb(dbPath: inMemoryDatabasePath));
    }

    Widget host(AppState app, Widget child) => ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, splashFactory: InkRipple.splashFactory),
            home: Scaffold(body: child),
          ),
        );

    Future<void> settle(WidgetTester tester, [int n = 30]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await tester.pump();
      }
    }

    testWidgets('同样的只读调用：第二次直接给上次结果，第三次叫停', (tester) async {
      final app = (await tester.runAsync(state))!;
      final seen = <List<AiMessage>>[];
      var round = 0;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            seen.add(h);
            round++;
            if (round <= 3) {
              onCalls([AiToolCall('g$round', 'app_guide', '{"topic":"对话历史"}')]);
              return const Stream<String>.empty();
            }
            return Stream<String>.value('好了。');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '怎么看历史');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await settle(tester);
      expect(round, 4);
      String toolAt(int r, int nth) =>
          seen[r].where((m) => m.role == 'tool').elementAt(nth).content;
      expect(toolAt(1, 0), contains('对话历史'), reason: '第一次真执行');
      expect(toolAt(2, 1), contains('"repeat":2'));
      expect(toolAt(2, 1), contains('对话历史'), reason: '第二次附上次的结果');
      expect(toolAt(3, 2), contains('不要再调用'));
      expect(find.text('好了。', findRichText: true), findsOneWidget);
    });

    testWidgets('步数用完：带着工具结果收尾，显示清单与「继续完成」；点它接着做', (tester) async {

      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(state))!;
      final rounds = app.aiBudgetForTurn(forTools: true).rounds;
      var n = 0;
      late List<AiMessage> summaryHist;
      late List<AiMessage> after;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            n++;
            if (n == 1) {
              onCalls(const [
                AiToolCall('p', 'task_plan',
                    '{"steps":[{"text":"查","status":"done"},{"text":"整理","status":"doing"},'
                        '{"text":"总结","status":"pending"}]}'),
              ]);
              return const Stream<String>.empty();
            }
            if (n <= rounds) {
              onCalls([AiToolCall('g$n', 'app_guide', '{"topic":"t$n"}')]);
              return const Stream<String>.empty();
            }
            if (n == rounds + 1) {
              summaryHist = h;
              return Stream<String>.value('先做到这里：查完了，还差总结。');
            }
            after = h;
            return Stream<String>.value('全部做完。');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '帮我做个长任务');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await settle(tester, 100);
      expect(n, rounds + 1, reason: '$rounds 步工具 + 1 次收尾');
      expect(summaryHist.where((m) => m.role == 'tool').length, rounds,
          reason: '收尾请求带着全部工具结果（发出去时再改写成文字）');
      expect(find.text('先做到这里：查完了，还差总结。', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.plan')), findsOneWidget);
      expect(find.text('任务清单 · 1/3'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.continue')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai.continue')));
      await settle(tester);
      expect(after.last.content, '继续完成剩下的步骤。');
      expect(find.text('全部做完。', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.continue')), findsNothing);
    });

    testWidgets('任务清单有进展时自动续跑：超过单轮步数也不中断，直到做完', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.setAiCtxTier(AiCtxTier.economy);
        return a;
      }))!;
      final rounds = app.aiBudgetForTurn(forTools: true).rounds;
      var n = 0;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            n++;
            if (n == 1) {
              onCalls(const [
                AiToolCall(
                  'p1',
                  'task_plan',
                  '{"steps":[{"text":"第1批","status":"doing"},{"text":"第2批","status":"pending"}]}',
                ),
              ]);
              return const Stream<String>.empty();
            }
            if (n == 2) {
              onCalls(const [
                AiToolCall(
                  'p1b',
                  'task_plan',
                  '{"steps":[{"text":"第1批","status":"done"},{"text":"第2批","status":"doing"}]}',
                ),
              ]);
              return const Stream<String>.empty();
            }
            if (n <= rounds) {
              onCalls([AiToolCall('g$n', 'app_guide', '{"topic":"t$n"}')]);
              return const Stream<String>.empty();
            }
            if (n == rounds + 1) {

              onCalls(const [
                AiToolCall(
                  'p2',
                  'task_plan',
                  '{"steps":[{"text":"第1批","status":"done"},{"text":"第2批","status":"done"}]}',
                ),
              ]);
              return const Stream<String>.empty();
            }
            return Stream<String>.value('自动续跑全部做完！');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '帮我批量处理两批任务');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await settle(tester, 100);
      expect(n, rounds + 2, reason: '第 $rounds 步后因为清单有进展自动续跑，无需手工点继续');
      expect(find.text('自动续跑全部做完！', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.continue')), findsNothing);
    });

    testWidgets('连续 $kAiStallRounds 步重复原地打转：自动触发打转保护提前收尾', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(state))!;
      var n = 0;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            n++;

            if (n <= 1 + kAiStallRounds) {
              onCalls(const [AiToolCall('g', 'app_guide', '{"topic":"same"}')]);
              return const Stream<String>.empty();
            }
            return Stream<String>.value('检测到重复调用，提前收尾。');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '测试打转保护');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await settle(tester, 30);
      expect(n, 1 + kAiStallRounds + 1, reason: '首次正常 + 连续 $kAiStallRounds 次重复 + 1 次收尾');
      expect(find.text('检测到重复调用，提前收尾。', findRichText: true), findsOneWidget);
    });

    testWidgets('设置页：精简两档可选（Auto/省钱优先）、显示窗口来源、长期学习记忆与诊断开关', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(() async {
        final a = await state();
        await a.init();
        await a.saveAiProvider('deepseek', key: 'sk-1', model: 'deepseek-flash', base: '');
        return a;
      }))!;
      await tester.pumpWidget(host(app, const AiSettingsScreen()));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai.tab.1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('上下文窗口约 1M（按型号名估计）'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.ctx.auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.ctx.economy')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.ctx.long')), findsNothing);
      expect(find.byKey(const ValueKey('ai.ctx.full')), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.ctx.economy')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(app.aiCtxTier, AiCtxTier.economy);
      expect(app.aiBudgetForTurn().input, 16000);
      expect(app.aiBudgetForTurn(forTools: true).input, 48000);

      expect(app.aiMemoryEnabled, isTrue);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.memory.switch')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(app.aiMemoryEnabled, isFalse);
      expect(aiToolSpecsFor(app).any((s) => s.name == kLearningMemoryTool), isFalse);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.memory.switch')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(app.aiMemoryEnabled, isTrue);
      expect(aiToolSpecsFor(app).any((s) => s.name == kLearningMemoryTool), isTrue);

      await tester.tap(find.byKey(const ValueKey('ai.memory.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('ai.memory.field')), 'B1 水平，常混淆 me- 与 ber-');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(app.aiLearningMemory, 'B1 水平，常混淆 me- 与 ber-');
      expect(find.byKey(const ValueKey('ai.memory.text')), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ai.diagSwitch')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      expect(app.aiDiag, isTrue);
      expect(find.byKey(const ValueKey('ai.diagView')), findsOneWidget);
      await tester.runAsync(() async {
        await app.setAiModelWindows('deepseek', {'deepseek-flash': 64000});
      });
      await tester.pump();
      expect(find.textContaining('约 64K（服务商的模型列表）'), findsOneWidget);
      expect(app.aiBudgetForTurn(forTools: true).input, 32000);
      await tester.runAsync(() => app.setAiDiag(false));
    });

    testWidgets('save_learning_memory 工具与任务完成后新开会话轻提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = (await tester.runAsync(state))!;
      final toolbox = AiToolbox(app);
      final out = await tester.runAsync(() => toolbox.run(
            const AiToolCall('m1', 'save_learning_memory', '{"memory":"偏爱口语例句"}'),
            confirm: (_) async => true,
          ));
      expect(out!.result, contains('偏爱口语例句'));
      expect(app.aiLearningMemory, '偏爱口语例句');

      var n = 0;
      await tester.pumpWidget(host(
        app,
        AiChatSheet(
          context: aiGeneralContext(),
          debugTurn: (h, onCalls) {
            n++;
            if (n == 1) {
              onCalls(const [
                AiToolCall('p', 'task_plan',
                    '{"steps":[{"text":"查词","status":"done"}]}'),
              ]);
              return const Stream<String>.empty();
            }
            return Stream<String>.value('已完成全部步骤。');
          },
        ),
      ));
      await tester.enterText(find.byKey(const ValueKey('ai.input')), '帮我查完');
      await tester.tap(find.byKey(const ValueKey('ai.send')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ai.nudge.banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai.nudge.new')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai.nudge.dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ai.nudge.banner')), findsNothing);
    });
  });
}
