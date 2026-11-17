library;

import 'fsrs_ffi_native.dart'
    if (dart.library.js_interop) 'fsrs_ffi_stub.dart';

const int kFsrsParamCount = 21;

class FsrsFfi {
  FsrsFfi._();

  static bool get available => fsrsNativeAvailable;

  static Future<List<double>?> optimizeOnDevice(
          List<List<List<int>>> hist) =>
      fsrsNativeOptimize(hist);
}

class FsrsTrainDiagnostics {
  final int totalCards;
  final int singleReviewCards;
  final int sameDayOnlyCards;
  final int usableCards;
  final int initCards;

  const FsrsTrainDiagnostics({
    required this.totalCards,
    required this.singleReviewCards,
    required this.sameDayOnlyCards,
    required this.usableCards,
    required this.initCards,
  });
}

FsrsTrainDiagnostics diagnoseTrainData(List<List<List<int>>> hist) {
  var total = 0;
  var single = 0;
  var sameDayOnly = 0;
  var usable = 0;
  var init = 0;
  for (final ev in hist) {
    total++;
    if (ev.length < 2) {
      single++;
      continue;
    }
    var longTermCnt = 0;
    for (var i = 1; i < ev.length; i++) {
      if (ev[i][0] > ev[i - 1][0]) longTermCnt++;
    }
    if (longTermCnt == 0) {
      sameDayOnly++;
      continue;
    }
    usable++;
    if (longTermCnt == 1) init++;
  }
  return FsrsTrainDiagnostics(
    totalCards: total,
    singleReviewCards: single,
    sameDayOnlyCards: sameDayOnly,
    usableCards: usable,
    initCards: init,
  );
}

List<List<List<int>>> filterTrainableHist(List<List<List<int>>> hist) {
  final out = <List<List<int>>>[];
  for (final ev in hist) {
    if (ev.length < 2) continue;
    var hasCrossDay = false;
    for (var i = 1; i < ev.length; i++) {
      if (ev[i][0] > ev[i - 1][0]) {
        hasCrossDay = true;
        break;
      }
    }
    if (hasCrossDay) out.add(ev);
  }
  return out;
}

List<List<(int, int)>> trainSets(List<List<List<int>>> hist) => [
      for (final ev in hist)
        [
          for (var i = 0; i < ev.length; i++)
            (
              ev[i][1].clamp(1, 4),
              i == 0 ? 0 : (ev[i][0] - ev[i - 1][0]).clamp(0, 4294967295),
            ),
        ],
    ];
