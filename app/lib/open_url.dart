library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'native_channel.dart';
import 'platform/io_shim.dart' show openWebExternalUrl;

Future<bool> openExternalUrl(String url) async {
  if (!url.startsWith('https://')) return false;
  if (kIsWeb) return openWebExternalUrl(url);
  try {
    return await kNativeChannel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
