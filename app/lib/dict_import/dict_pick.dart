import 'package:flutter/services.dart';

import '../native_channel.dart';

class DictPickException implements Exception {
  const DictPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String?> pickDictFilePath() async {
  try {
    return await kNativeChannel.invokeMethod<String>('pickDict');
  } on PlatformException catch (e) {
    throw DictPickException(e.message ?? '打不开文件选择器');
  } on MissingPluginException {
    throw const DictPickException('当前平台暂不支持导入本地词典');
  }
}
