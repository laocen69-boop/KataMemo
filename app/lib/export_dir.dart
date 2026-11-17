library;

import 'platform/io_shim.dart';
import 'version.dart' show kAppName;

Future<Directory> exportBaseDir() async {
  if (Platform.isAndroid) {
    try {
      final d = await getExternalStorageDirectory();
      if (d != null) return d;
    } catch (_) {}
  }
  return getApplicationDocumentsDirectory();
}

String exportWhereHint(String path) => Platform.isIOS
    ? '在「文件」App → 我的 iPhone → $kAppName 里可以找到'
    : '路径已复制：\n$path';
