import 'package:flutter/foundation.dart';

const bool kFrameLog = bool.fromEnvironment('KM_FRAME_LOG');

void perfLog(String tag, Stopwatch sw, [String extra = '']) {
  if (!kFrameLog) return;
  debugPrint('KMP $tag ms=${sw.elapsedMilliseconds} $extra');
}
