import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:katamemo/ai_chat.dart';
import 'package:katamemo/ai_history.dart';
import 'package:katamemo/db.dart';
import 'package:katamemo/widgets/ai_chat_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<AppDb> freshDb() async {
    await databaseFactory.deleteDatabase(inMemoryDatabasePath);
    final db = AppDb(dbPath: inMemoryDatabasePath);
    await db.db;
    return db;
  }

  const q1 = AiMessage('user', 'daripada 怎么用？');
  const a1 = AiMessage('assistant', '**daripada** 只用于比较。');

  group('消息序列化', () {
    test('工具调用与工具结果往返不丢；图片不落库只留「（附图）」', () {
      final msgs = [
        const AiMessage('user', '看看这张图', imageB64: 'AAAA'),
        const AiMessage('assistant', '',
            toolCalls: [AiToolCall('c1', 'lookup_word', '{"w":"makan"}')]),
        const AiMessage('tool', '{"n":3}',
            toolCallId: 'c1', toolName: 'lookup_word', label: '查了词库：makan（3 个）'),
        const AiMessage('assistant', '好的'),
      ];
      final back = aiMessagesDecode(aiMessagesEncode(msgs));
      expect(back.length, 4);
      expect(back[0].content, '看看这张图（附图）');
      expect(back[0].imageB64, isNull);
      expect(back[1].toolCalls.single.name, 'lookup_word');
      expect(back[1].toolCalls.single.args, '{"w":"makan"}');
      expect(back[2].toolCallId, 'c1');
      expect(back[2].label, '查了词库：makan（3 个）');
    });

    test('坏 JSON 当空对话，不抛', () {
      expect(aiMessagesDecode('不是 json'), isEmpty);
      expect(aiMessagesDecode('{"a":1}'), isEmpty);
    });

    test('预览取第一条用户提问并压成一行', () {
      expect(aiPreviewOf([const AiMessage('user', '  第一行\n第二行  '), a1]), '第一行 第二行');
      expect(aiPreviewOf([a1]), '');
    });
  });

  group('历史库', () {
    test('存 → 列表 → 取回 → 接着存同一行 → 删除', () async {
      final db = await freshDb();
      final id = await db.aiChatSave(
          key: 'word:makan',
          title: 'makan',
          subtitle: '吃',
          system: 'SYS',
          msgs: [q1, a1]);
      expect(id, isNotNull);

      var list = await db.aiChatList();
      expect(list.single.title, 'makan');
      expect(list.single.kind, 'word');
      expect(list.single.count, 2);
      expect(list.single.preview, 'daripada 怎么用？');

      final id2 = await db.aiChatSave(
          id: id,
          key: 'word:makan',
          title: 'makan',
          subtitle: '吃',
          system: 'SYS',
          msgs: [q1, a1, const AiMessage('user', '再举个例子')]);
      expect(id2, id);
      expect((await db.aiChatList()).length, 1);
      final full = await db.aiChatGet(id!);
      expect(full!.msgs.length, 3);
      expect(full.system, 'SYS');

      await db.aiChatDelete(id);
      expect(await db.aiChatList(), isEmpty);
    });

    test('行被删后再保存会重新插入（历史页里删掉了当前这段）', () async {
      final db = await freshDb();
      final id = await db.aiChatSave(
          key: 'general', title: '印尼语助手', subtitle: '', system: '', msgs: [q1]);
      await db.aiChatDelete(id!);
      final id2 = await db.aiChatSave(
          id: id, key: 'general', title: '印尼语助手', subtitle: '', system: '', msgs: [q1, a1]);
      expect(id2, isNotNull);
      expect((await db.aiChatList()).length, 1);
    });

    test('空对话不存；已有的行存成空 = 删除', () async {
      final db = await freshDb();
      expect(
          await db.aiChatSave(
              key: 'general', title: 't', subtitle: '', system: '', msgs: const []),
          isNull);
      final id = await db.aiChatSave(
          key: 'general', title: 't', subtitle: '', system: '', msgs: [q1]);
      await db.aiChatSave(
          id: id, key: 'general', title: 't', subtitle: '', system: '', msgs: const []);
      expect(await db.aiChatCount(), 0);
    });

    test('同一话题取最近的一段；搜索能搜到对话正文', () async {
      final db = await freshDb();
      await db.aiChatSave(
          key: 'word:makan', title: 'makan', subtitle: '', system: '', msgs: [q1]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newer = await db.aiChatSave(
          key: 'word:makan',
          title: 'makan',
          subtitle: '',
          system: '',
          msgs: [const AiMessage('user', '近义词有哪些')]);
      final latest = await db.aiChatLatestForKey('word:makan');
      expect(latest!.head.id, newer);
      expect(await db.aiChatLatestForKey('word:minum'), isNull);

      expect((await db.aiChatList(q: 'daripada')).length, 1);
      expect((await db.aiChatList(q: '近义词')).length, 1);
      expect(await db.aiChatList(q: '根本没有这个词'), isEmpty);
    });

    test('超过上限时丢最旧的', () async {
      final db = await freshDb();
      for (var i = 0; i < kAiChatKeep + 3; i++) {
        await db.aiChatSave(
            key: 'k$i', title: 't$i', subtitle: '', system: '', msgs: [q1]);
      }
      expect(await db.aiChatCount(), kAiChatKeep);
    });

    test('清空', () async {
      final db = await freshDb();
      await db.aiChatSave(
          key: 'general', title: 't', subtitle: '', system: '', msgs: [q1]);
      await db.aiChatClear();
      expect(await db.aiChatCount(), 0);
    });
  });

  group('防止重复打开', () {
    test('第一个还没结束时，第二个直接丢掉；结束后可以再开', () async {
      var ran = 0;
      final gate = Completer<void>();
      final first = aiOpenGuarded(() async {
        ran++;
        await gate.future;
      });
      expect(aiChatOpening, isTrue);
      await aiOpenGuarded(() async => ran++);
      await aiOpenGuarded(() async => ran++);
      expect(ran, 1);
      gate.complete();
      await first;
      expect(aiChatOpening, isFalse);
      await aiOpenGuarded(() async => ran++);
      expect(ran, 2);
    });

    test('里面抛错也会放开闸门', () async {
      await expectLater(
          aiOpenGuarded(() async => throw StateError('x')), throwsStateError);
      expect(aiChatOpening, isFalse);
    });
  });

  test('DeepSeek 是推荐服务商，其余都不是', () {
    expect(kAiProviders.where((p) => p.recommended).map((p) => p.id), ['deepseek']);
  });
}
