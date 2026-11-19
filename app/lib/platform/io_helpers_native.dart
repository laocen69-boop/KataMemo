library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

export 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory, getExternalStorageDirectory;

void ensureWebDatabaseFactory() {}

Future<bool> seedWebDatabaseFromAsset(
  String assetRelPath, {
  void Function(double progress)? onProgress,
}) async =>
    false;

Future<String?> loadWebGzipTextAsset(String assetRelPath) async => null;

Future<Uint8List?> fetchWebPackSlice(
        String packAsset, int offset, int length) async =>
    null;

Future<R> runCompute<R>(R Function() fn) => Isolate.run(fn);

Widget buildFileImage(
  File file, {
  double? width,
  double? height,
  BoxFit? fit,
  int? cacheWidth,
  bool gaplessPlayback = false,
  ImageErrorWidgetBuilder? errorBuilder,
}) =>
    Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: gaplessPlayback,
      errorBuilder: errorBuilder,
    );
