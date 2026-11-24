library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Headers')
extension type _JSHeaders._(JSObject _) implements JSObject {
  external factory _JSHeaders();
  external void set(String name, String value);
}

@JS()
@anonymous
extension type _JSRequestInit._(JSObject _) implements JSObject {
  external factory _JSRequestInit({
    String method,
    _JSHeaders headers,
    JSAny? body,
  });
}

@JS('Response')
extension type _JSResponse._(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('fetch')
external JSPromise<_JSResponse> _jsFetch(JSString url, _JSRequestInit init);

@JS('Blob')
extension type _JSBlob._(JSObject _) implements JSObject {
  external factory _JSBlob(JSArray<JSAny> parts);
}

@JS('URL.createObjectURL')
external String _createObjectURL(_JSBlob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(String url);

@JS('document.createElement')
external _JSAnchor _createElement(String tag);

extension type _JSAnchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

class Platform {
  static bool get isIOS => false;
  static bool get isAndroid => false;
  static String get pathSeparator => '/';
  static Map<String, String> get environment => const <String, String>{};
}

abstract class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);

  Uri get uri => Uri.parse('file://${path.startsWith('/') ? '' : '/'}$path');
}

class File extends FileSystemEntity {
  static final Map<String, ({Uint8List bytes, DateTime modified})> _store = {};

  const File(super.path);

  static void registerMemoryFile(String path, Uint8List bytes) {
    _store[path] = (bytes: bytes, modified: DateTime.now());
  }

  Future<bool> exists() async => existsSync();

  bool existsSync() => _store.containsKey(path);

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _store[path] = (bytes: data, modified: DateTime.now());
    _maybeTriggerDownload(path, data);
    return this;
  }

  Future<File> writeAsString(String contents, {bool flush = false}) =>
      writeAsBytes(utf8.encode(contents), flush: flush);

  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  Uint8List readAsBytesSync() => _store[path]?.bytes ?? Uint8List(0);

  Future<String> readAsString() async => readAsStringSync();

  String readAsStringSync() =>
      utf8.decode(readAsBytesSync(), allowMalformed: true);

  Future<int> length() async => lengthSync();

  int lengthSync() => _store[path]?.bytes.length ?? 0;

  DateTime lastModifiedSync() => _store[path]?.modified ?? DateTime.now();

  Future<File> copy(String newPath) async {
    final dst = File(newPath);
    final cur = _store[path];
    if (cur != null) {
      _store[newPath] = (bytes: cur.bytes, modified: DateTime.now());
    }
    return dst;
  }

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    _store.remove(path);
    return this;
  }

  static void _maybeTriggerDownload(String filePath, Uint8List data) {
    final name = filePath.split('/').last.split(r'\').last;
    if (!(name.startsWith('katamemo-') &&
        (name.endsWith('.json') || name.endsWith('.csv')))) {
      return;
    }
    try {
      final blob = _JSBlob(<JSAny>[data.toJS].toJS);
      final url = _createObjectURL(blob);
      final a = _createElement('a');
      a.href = url;
      a.download = name;
      a.click();
      _revokeObjectURL(url);
    } catch (_) {}
  }
}

class Directory extends FileSystemEntity {
  const Directory(super.path);

  Future<bool> exists() async => true;

  bool existsSync() => true;

  Future<Directory> create({bool recursive = false}) async => this;

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    final prefix = path.endsWith('/') ? path : '$path/';
    return [
      for (final k in File._store.keys)
        if (k.startsWith(prefix) || k.startsWith(path)) File(k),
    ];
  }
}

class SocketException implements Exception {
  final String message;
  const SocketException([this.message = '']);
  @override
  String toString() => 'SocketException: $message';
}

class HandshakeException implements Exception {
  final String message;
  const HandshakeException([this.message = '']);
  @override
  String toString() => 'HandshakeException: $message';
}

class ContentType {
  final String primaryType;
  final String subType;
  final String? charset;

  const ContentType(this.primaryType, this.subType, {this.charset});

  static const ContentType json =
      ContentType('application', 'json', charset: 'utf-8');

  @override
  String toString() =>
      charset != null ? '$primaryType/$subType; charset=$charset' : '$primaryType/$subType';
}

class HttpHeaders {
  static const String authorizationHeader = 'authorization';
  static const String contentTypeHeader = 'content-type';
  static const String acceptHeader = 'accept';

  final Map<String, String> _map = {};

  set contentType(ContentType? value) {
    if (value != null) set(contentTypeHeader, value.toString());
  }

  void set(String name, Object value) {
    _map[name] = value.toString();
  }

  Map<String, String> get values => _map;
}

class HttpClient {
  Duration? connectionTimeout;

  Future<HttpClientRequest> postUrl(Uri url) async =>
      HttpClientRequest._('POST', url);

  Future<HttpClientRequest> getUrl(Uri url) async =>
      HttpClientRequest._('GET', url);

  void close({bool force = false}) {}
}

class HttpClientRequest {
  final String method;
  final Uri url;
  final HttpHeaders headers = HttpHeaders();
  bool followRedirects = true;
  final BytesBuilder _body = BytesBuilder(copy: false);

  HttpClientRequest._(this.method, this.url);

  void add(List<int> data) => _body.add(data);

  void write(Object? object) {
    if (object != null) add(utf8.encode(object.toString()));
  }

  Future<HttpClientResponse> close() async {
    try {
      final hdrObj = _JSHeaders();
      headers.values.forEach((k, v) => hdrObj.set(k, v));
      final bytes = _body.takeBytes();
      final init = _JSRequestInit(
        method: method,
        headers: hdrObj,
        body: method == 'GET' || bytes.isEmpty ? null : bytes.toJS,
      );
      final resp = await _jsFetch(url.toString().toJS, init).toDart;
      final ab = await resp.arrayBuffer().toDart;
      final outBytes = ab.toDart.asUint8List();
      return HttpClientResponse._(resp.status, outBytes);
    } catch (e) {
      throw SocketException('$e');
    }
  }
}

class HttpClientResponse extends Stream<List<int>> {
  final int statusCode;
  final Uint8List _bytes;

  HttpClientResponse._(this.statusCode, this._bytes);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(_bytes).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}
