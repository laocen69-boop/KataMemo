import 'package:flutter_test/flutter_test.dart';
import 'package:katamemo/ai_chat.dart';
import 'package:katamemo/ai_tools.dart';

void main() {
  test('local_dictionary 声明存在，且是只读工具', () {
    expect(kAiToolSpecList.map((s) => s.name), contains(kLocalDictTool));
    expect(aiToolKind(kLocalDictTool), AiToolKind.read);
  });

  test('一次最多查 15 个词', () {
    expect(kLocalDictMaxWords, 15);
  });

  test('参数是字符串数组，且 words 必填', () {
    final spec = kAiToolSpecList.firstWhere((s) => s.name == kLocalDictTool);
    final params = spec.parameters;
    expect(params['required'], ['words']);
    final props = params['properties'] as Map<String, Object?>;
    final words = props['words'] as Map<String, Object?>;
    expect(words['type'], 'array');
  });

  test('工具说明写明 authority=kbbi 优先', () {
    final spec = kAiToolSpecList.firstWhere((s) => s.name == kLocalDictTool);
    expect(spec.description, contains('authority=kbbi'));
    expect(spec.description, contains('释义以它为准'));
  });

  test('Agent 规则要求问词义时先查本地词典', () {
    expect(kAiAgentRules, contains('local_dictionary'));
    expect(kAiAgentRules, contains('先调它查这个词'));
    expect(kAiAgentRules, contains('authority=kbbi'));
  });
}
