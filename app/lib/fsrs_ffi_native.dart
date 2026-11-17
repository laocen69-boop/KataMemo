library;

import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'fsrs_ffi.dart' show kFsrsParamCount, filterTrainableHist, trainSets;
import 'fsrs_personalize.dart';

final class _CReview extends Struct {
  @Uint32()
  external int rating;
  @Uint32()
  external int deltaT;
}

final class _CItem extends Struct {
  external Pointer<_CReview> reviews;
  @IntPtr()
  external int len;
}

final class _CItems extends Struct {
  external Pointer<_CItem> items;
  @IntPtr()
  external int len;
}

typedef _NewNative = Pointer<Void> Function(Pointer<Float>, IntPtr);
typedef _NewDart = Pointer<Void> Function(Pointer<Float>, int);
typedef _ComputeNative = Pointer<Float> Function(Pointer<Void>, Pointer<_CItems>);
typedef _ComputeDart = Pointer<Float> Function(Pointer<Void>, Pointer<_CItems>);
typedef _FreeFsrsNative = Void Function(Pointer<Void>);
typedef _FreeFsrsDart = void Function(Pointer<Void>);

DynamicLibrary? _lib;
bool _libTried = false;

DynamicLibrary? _openLib() {
  if (_libTried) return _lib;
  _libTried = true;
  try {
    _lib = DynamicLibrary.open('libfsrs.so');
  } catch (_) {
    _lib = null;
  }
  return _lib;
}

bool get fsrsNativeAvailable => _openLib() != null;

Future<List<double>?> fsrsNativeOptimize(List<List<List<int>>> hist) async {
  final sets = trainSets(filterTrainableHist(hist));
  if (sets.isEmpty) return null;
  if (!fsrsNativeAvailable) return null;
  return Isolate.run(() => _optimizeSync(sets));
}

List<double>? _optimizeSync(List<List<(int, int)>> sets) {
  final lib = _openLib();
  if (lib == null || sets.isEmpty) return null;
  final newF = lib.lookupFunction<_NewNative, _NewDart>('fsrs_new');
  final computeF =
      lib.lookupFunction<_ComputeNative, _ComputeDart>('fsrs_compute_parameters');
  final freeF = lib.lookupFunction<_FreeFsrsNative, _FreeFsrsDart>('fsrs_free');

  final pDef = calloc<Float>(kFsrsParamCount);
  for (var i = 0; i < kFsrsParamCount; i++) {
    pDef[i] = FsrsPersonalize.defaultW[i];
  }

  var total = 0;
  for (final s in sets) {
    total += s.length;
  }
  final pRev = calloc<_CReview>(total);
  final pItems = calloc<_CItem>(sets.length);
  final pTop = calloc<_CItems>();
  try {
    var r = 0;
    for (var i = 0; i < sets.length; i++) {
      final s = sets[i];
      pItems[i].reviews = pRev + r;
      pItems[i].len = s.length;
      for (final (rating, dt) in s) {
        pRev[r].rating = rating;
        pRev[r].deltaT = dt;
        r++;
      }
    }
    pTop.ref.items = pItems;
    pTop.ref.len = sets.length;

    final fsrs = newF(pDef, kFsrsParamCount);
    if (fsrs == nullptr) return null;
    try {
      final out = computeF(fsrs, pTop);
      if (out.address == 0) return null;
      return [
        for (var i = 0; i < kFsrsParamCount; i++) out[i].toDouble(),
      ];
    } finally {
      freeF(fsrs);
    }
  } finally {
    calloc.free(pTop);
    calloc.free(pItems);
    calloc.free(pRev);
    calloc.free(pDef);
  }
}
