library;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String kImageDir = 'mnemonic';

const Set<String> kImageExt = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.heic',
  '.gif'
};

const int kMaxImageBytes = 4 * 1024 * 1024;

class ImageStore {

  static Directory? debugDocsDir;

  static final Map<String, File> _cache = {};

  static File? cached(String rel) {
    final f = _cache[rel];
    if (f == null) return null;
    if (f.existsSync()) return f;
    _cache.remove(rel);
    return null;
  }

  static Future<({String? rel, String? error})> pick({
    required ImageSource source,
  }) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,

        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      return (rel: null, error: '打开相册/相机失败：$e');
    }
    if (picked == null) return (rel: null, error: null);

    final ext = p.extension(picked.path).toLowerCase();

    final useExt = kImageExt.contains(ext) ? ext : '.jpg';

    final bytes = await picked.readAsBytes();
    if (bytes.length > kMaxImageBytes) {
      return (
        rel: null,
        error: '图片太大（${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB），'
            '请选小于 ${kMaxImageBytes ~/ 1024 ~/ 1024} MB 的'
      );
    }

    final docs = debugDocsDir ?? await getApplicationDocumentsDirectory();
    final dir = await Directory(p.join(docs.path, kImageDir))
        .create(recursive: true);

    final name = '${DateTime.now().microsecondsSinceEpoch}$useExt';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    final rel = p.join(kImageDir, name);
    _cache[rel] = file;
    return (rel: rel, error: null);
  }

  static Future<File?> resolve(String rel) async {
    if (rel.isEmpty) return null;
    final hit = cached(rel);
    if (hit != null) return hit;

    if (p.isAbsolute(rel) || rel.contains('..')) return null;
    if (p.dirname(rel) != kImageDir) return null;
    try {
      final docs = debugDocsDir ?? await getApplicationDocumentsDirectory();
      final f = File(p.join(docs.path, rel));
      if (!await f.exists()) return null;
      _cache[rel] = f;
      return f;
    } catch (_) {

      return null;
    }
  }

  static Future<void> delete(String rel) async {
    _cache.remove(rel);
    try {
      final f = await resolve(rel);
      if (f != null) await f.delete();
    } catch (_) {}
  }

  static Future<bool> exists(String rel) async => (await resolve(rel)) != null;
}
