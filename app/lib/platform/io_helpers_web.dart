library;

import 'dart:convert' show utf8;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart' show databaseFactoryOrNull, databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'io_shim_web.dart';

@JS('Headers')
extension type _RangeHeaders._(JSObject _) implements JSObject {
  external factory _RangeHeaders();
  external void set(String name, String value);
}

@JS()
@anonymous
extension type _RangeReqInit._(JSObject _) implements JSObject {
  external factory _RangeReqInit({String method, _RangeHeaders headers});
}

@JS('DecompressionStream')
extension type _JSDecompressionStream._(JSObject _) implements JSObject {
  external factory _JSDecompressionStream(String format);
}

@JS('ReadableStream')
extension type _JSReadableStream._(JSObject _) implements JSObject {
  external _JSReadableStream pipeThrough(JSObject transform);
}

@JS('Response')
extension type _RangeResp._(JSObject _) implements JSObject {
  external factory _RangeResp(_JSReadableStream stream);
  external int get status;
  external bool get ok;
  external _JSReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('fetch')
external JSPromise<_RangeResp> _webFetch(JSString url, [_RangeReqInit? init]);

bool _webDbInited = false;

void ensureWebDatabaseFactory() {
  if (_webDbInited) return;
  _webDbInited = true;
  if (databaseFactoryOrNull == null) {
    databaseFactory = databaseFactoryFfiWeb;
  }
}

Future<bool> seedWebDatabaseFromAsset(
  String assetRelPath, {
  void Function(double progress)? onProgress,
}) async {
  ensureWebDatabaseFactory();
  try {
    onProgress?.call(0.1);
    final resp = await _webFetch('assets/$assetRelPath'.toJS).toDart;
    if (!resp.ok || resp.body == null) return false;
    onProgress?.call(0.45);
    final decompressed =
        resp.body!.pipeThrough(_JSDecompressionStream('gzip'));
    final ab = await _RangeResp(decompressed).arrayBuffer().toDart;
    final dbBytes = ab.toDart.asUint8List();
    if (dbBytes.length < 1024) return false;
    onProgress?.call(0.75);
    await databaseFactory.writeDatabaseBytes('katamemo.db', dbBytes);
    onProgress?.call(1.0);
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> loadWebGzipTextAsset(String assetRelPath) async {
  try {
    final resp = await _webFetch('assets/$assetRelPath'.toJS).toDart;
    if (!resp.ok || resp.body == null) return null;
    final decompressed =
        resp.body!.pipeThrough(_JSDecompressionStream('gzip'));
    final ab = await _RangeResp(decompressed).arrayBuffer().toDart;
    return utf8.decode(ab.toDart.asUint8List());
  } catch (_) {
    return null;
  }
}

final Map<String, Uint8List> _fullShardCache = {};

Future<Uint8List?> fetchWebPackSlice(
  String packAsset,
  int offset,
  int length,
) async {
  final cached = _fullShardCache[packAsset];
  if (cached != null) {
    if (offset >= 0 && offset + length <= cached.length) {
      return Uint8List.sublistView(cached, offset, offset + length);
    }
    return null;
  }

  final url = 'assets/$packAsset';
  try {
    final hdr = _RangeHeaders();
    hdr.set('Range', 'bytes=$offset-${offset + length - 1}');
    final resp =
        await _webFetch(url.toJS, _RangeReqInit(method: 'GET', headers: hdr))
            .toDart;
    if (resp.status == 206) {
      final ab = await resp.arrayBuffer().toDart;
      final bytes = ab.toDart.asUint8List();
      if (bytes.length == length) return bytes;
    } else if (resp.status == 200) {
      final ab = await resp.arrayBuffer().toDart;
      final full = ab.toDart.asUint8List();
      _fullShardCache[packAsset] = full;
      if (offset >= 0 && offset + length <= full.length) {
        return Uint8List.sublistView(full, offset, offset + length);
      }
    }
  } catch (_) {}
  return null;
}

Future<Directory> getApplicationDocumentsDirectory() async =>
    const Directory('/web_docs');

Future<Directory?> getExternalStorageDirectory() async =>
    const Directory('/web_ext');

Future<R> runCompute<R>(R Function() fn) async => fn();

Widget buildFileImage(
  File file, {
  double? width,
  double? height,
  BoxFit? fit,
  int? cacheWidth,
  bool gaplessPlayback = false,
  ImageErrorWidgetBuilder? errorBuilder,
}) =>
    Image.memory(
      file.readAsBytesSync(),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
