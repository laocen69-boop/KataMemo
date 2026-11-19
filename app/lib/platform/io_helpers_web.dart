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
  external _RangeResp clone();
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('caches')
external _JSCacheStorage? get _caches;

extension type _JSCacheStorage._(JSObject _) implements JSObject {
  external JSPromise<_JSCache> open(JSString cacheName);
  @JS('delete')
  external JSPromise<JSBoolean> remove(JSString cacheName);
}

extension type _JSCache._(JSObject _) implements JSObject {
  external JSPromise<_RangeResp?> match(JSString request);
  external JSPromise<JSAny?> put(JSString request, _RangeResp response);
  external JSPromise<JSArray<JSAny?>> keys();
}

const String _kAudioCacheName = 'katamemo-audio-v1';

Future<_JSCache?> _openAudioCache() async {
  try {
    final c = _caches;
    if (c == null) return null;
    return await c.open(_kAudioCacheName.toJS).toDart;
  } catch (_) {
    return null;
  }
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

Future<String?> loadWebGzipTextAsset(
  String assetRelPath, {
  bool persist = false,
}) async {
  final url = 'assets/$assetRelPath';
  try {
    _RangeResp? resp;
    _JSCache? cache;
    if (persist) {
      cache = await _openAudioCache();
      if (cache != null) {
        resp = await cache.match(url.toJS).toDart;
      }
    }
    if (resp == null) {
      final fetched = await _webFetch(url.toJS).toDart;
      if (!fetched.ok || fetched.body == null) return null;
      if (persist && cache != null) {
        try {
          await cache.put(url.toJS, fetched.clone()).toDart;
        } catch (_) {}
      }
      resp = fetched;
    }
    if (resp.body == null) return null;
    final decompressed =
        resp.body!.pipeThrough(_JSDecompressionStream('gzip'));
    final ab = await _RangeResp(decompressed).arrayBuffer().toDart;
    return utf8.decode(ab.toDart.asUint8List());
  } catch (_) {
    return null;
  }
}

final Map<String, Uint8List> _fullShardCache = {};
final Map<String, Future<Uint8List?>> _inFlightSlices = {};

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

  final key = '$packAsset#$offset#$length';
  final pending = _inFlightSlices[key];
  if (pending != null) return pending;

  final future = _fetchWebPackSliceOnce(packAsset, offset, length);
  _inFlightSlices[key] = future;
  try {
    return await future;
  } finally {
    // ignore: unawaited_futures
    _inFlightSlices.remove(key);
  }
}

Future<Uint8List?> _fetchWebPackSliceOnce(
  String packAsset,
  int offset,
  int length,
) async {
  final url = 'assets/$packAsset';
  try {
    final cache = await _openAudioCache();
    if (cache != null) {
      final cachedResp = await cache.match(url.toJS).toDart;
      if (cachedResp != null) {
        final ab = await cachedResp.arrayBuffer().toDart;
        final full = ab.toDart.asUint8List();
        _fullShardCache[packAsset] = full;
        if (offset >= 0 && offset + length <= full.length) {
          return Uint8List.sublistView(full, offset, offset + length);
        }
      }
    }

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
      if (cache != null) {
        try {
          await cache.put(url.toJS, resp.clone()).toDart;
        } catch (_) {}
      }
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

Future<int> webAudioCachedShardCount() async {
  final cache = await _openAudioCache();
  if (cache == null) return 0;
  try {
    final keys = await cache.keys().toDart;
    return keys.toDart.length;
  } catch (_) {
    return 0;
  }
}

Future<void> clearWebAudioCache() async {
  _fullShardCache.clear();
  try {
    await _caches?.remove(_kAudioCacheName.toJS).toDart;
  } catch (_) {}
}

Future<void> downloadWebAudioShards(
  int fromBucket,
  int toBucket, {
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final cache = await _openAudioCache();
  if (cache == null) return;
  final total = toBucket - fromBucket + 1;
  var done = 0;
  const batch = 4;
  for (var start = fromBucket; start <= toBucket; start += batch) {
    if (isCancelled?.call() ?? false) break;
    final end = (start + batch - 1) > toBucket ? toBucket : (start + batch - 1);
    await Future.wait([
      for (var b = start; b <= end; b++)
        () async {
          if (isCancelled?.call() ?? false) return;
          final tag = b.toString().padLeft(2, '0');
          final url = 'assets/assets/audio_pack/ardi_$tag.pak';
          try {
            final hit = await cache.match(url.toJS).toDart;
            if (hit == null) {
              final resp = await _webFetch(url.toJS).toDart;
              if (resp.ok) {
                await cache.put(url.toJS, resp).toDart;
              }
            }
          } catch (_) {}
          done++;
          onProgress?.call(done, total);
        }(),
    ]);
  }
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
