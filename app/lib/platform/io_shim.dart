library;

export 'dart:io' if (dart.library.js_interop) 'io_shim_web.dart';
export 'io_helpers_native.dart'
    if (dart.library.js_interop) 'io_helpers_web.dart';
