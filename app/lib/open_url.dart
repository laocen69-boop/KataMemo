library;

import 'package:flutter/services.dart';

import 'native_channel.dart';

Future<bool> openExternalUrl(String url) async {
  if (!url.startsWith('https://')) return false;
  try {
    return await kNativeChannel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
