library;

import 'package:flutter/services.dart';

import 'native_channel.dart';
import 'platform/io_shim.dart' show Platform;

Future<String?> pickAudioFile() {
  if (Platform.isIOS) {
    throw PlatformException(
        code: 'unsupported', message: 'iPhone 版暂不支持导入自定义音频');
  }
  return kNativeChannel.invokeMethod<String>('pickAudio');
}
