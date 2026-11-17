library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetManifest, MethodChannel, rootBundle;

import 'platform/io_shim.dart';

const String kUserAudioPrefix = 'user:';

enum PlayOutcome {

  asset,

  userAudio,

  none,
}

class AudioService {
  static final AudioService instance = AudioService._();
  AudioService._();

  static final bool _isTest = Platform.environment.containsKey('FLUTTER_TEST');
  late final AudioPlayer? _player = _isTest ? null : AudioPlayer();

  void Function(String? word)? debugOnPlayCard;

  static Future<Directory> userAudioDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/user_audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String?> userAudioPath(String? au) async {
    if (au == null || !au.startsWith(kUserAudioPrefix)) return null;
    final name = au.substring(kUserAudioPrefix.length);
    if (name.isEmpty) return null;
    final dir = await userAudioDir();
    return '${dir.path}/$name';
  }

  static const Duration partGap = Duration(milliseconds: 90);

  int _seq = 0;

  static const _packCh = MethodChannel('katamemo/picker');

  Set<String>? _builtInArdi;
  Future<Set<String>>? _builtInLoading;
  Map<String, ({int bucket, int offset, int length})>? _packIndex;
  Future<Map<String, ({int bucket, int offset, int length})>>? _packLoading;

  @visibleForTesting
  set debugBuiltInAssets(Set<String>? assets) => _builtInArdi = assets;

  Future<Map<String, ({int bucket, int offset, int length})>> _loadPackIndex() {
    if (_packIndex != null) return Future.value(_packIndex!);
    return _packLoading ??= () async {
      try {
        final raw = await rootBundle.loadString(
            'assets/audio_pack/ardi_idx.tsv',
            cache: false);
        final map = <String, ({int bucket, int offset, int length})>{};
        final builtIn = <String>{};
        for (final line in raw.split('\n')) {
          if (line.isEmpty) continue;
          final parts = line.split('\t');
          if (parts.length != 4) continue;
          final name = parts[0];
          final b = int.tryParse(parts[1]);
          final off = int.tryParse(parts[2]);
          final len = int.tryParse(parts[3]);
          if (b == null || off == null || len == null) continue;
          map[name] = (bucket: b, offset: off, length: len);
          builtIn.add('edge/ardi/$name');
        }
        _packIndex = map;
        _builtInArdi ??= builtIn;
        return map;
      } catch (_) {
        const empty = <String, ({int bucket, int offset, int length})>{};
        _packIndex = empty;
        return empty;
      } finally {
        _packLoading = null;
      }
    }();
  }

  Future<Set<String>> _loadBuiltInArdi() {
    if (_builtInArdi != null) return Future.value(_builtInArdi!);
    return _builtInLoading ??= () async {
      try {
        final idx = await _loadPackIndex();
        if (idx.isNotEmpty && _builtInArdi != null) return _builtInArdi!;
        final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
        const prefix = 'assets/audio/edge/ardi/';
        final set = <String>{};
        for (final key in manifest.listAssets()) {
          if (key.startsWith(prefix) && key.endsWith('.ogg')) {
            set.add(key.substring('assets/audio/'.length));
          }
        }
        _builtInArdi = set;
        return set;
      } catch (_) {

        return <String>{};
      } finally {
        _builtInLoading = null;
      }
    }();
  }

  static String _foldWord(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const map = {
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    };
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  Future<String?> resolveBuiltInAudio(String word, {String? folded}) async {
    final f = (folded ?? _foldWord(word)).trim();
    if (f.isEmpty) return null;
    final set = await _loadBuiltInArdi();
    if (set.isEmpty) return null;

    final slug = f
        .replaceAll(RegExp(r'[^a-z0-9\-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final candidates = <String>[
      if (slug.isNotEmpty) 'edge/ardi/id-$slug.ogg',
      'edge/ardi/id-$f.ogg',
    ];
    for (final c in candidates) {
      if (set.contains(c)) return c;
    }
    return null;
  }

  Future<PlayOutcome> playCard({
    String? audio,
    List<String> parts = const [],
    String? word,
  }) async {
    debugOnPlayCard?.call(word);
    if (audio != null && audio.isNotEmpty) return playWord(audio);
    if (parts.isNotEmpty) return playParts(parts);
    if (word != null && word.trim().isNotEmpty) {
      final fallback = await resolveBuiltInAudio(word);
      if (fallback != null) return playWord(fallback);
    }
    return PlayOutcome.none;
  }

  Future<PlayOutcome> playParts(List<String> parts) async {
    if (parts.isEmpty) return PlayOutcome.none;
    final my = ++_seq;
    for (var i = 0; i < parts.length; i++) {
      if (my != _seq) return PlayOutcome.none;
      if (!await _playAssetWait(parts[i], my)) return PlayOutcome.none;
      if (i < parts.length - 1) await Future<void>.delayed(partGap);
    }
    return PlayOutcome.asset;
  }

  Future<bool> _playAssetWait(String path, int seq) async {
    final player = _player;
    if (player == null) return false;
    for (final p in audioAssetCandidates(path)) {
      if (seq != _seq) return false;
      try {

        await player.stop();
        if (seq != _seq) return false;
        final src = await _sourceForAsset(p);
        if (seq != _seq) return false;
        final done = player.onPlayerComplete.first;
        await player.play(src);
        await done.timeout(const Duration(seconds: 10));
        return true;
      } catch (_) {

        if (seq != _seq) return false;
      }
    }
    return false;
  }

  Future<PlayOutcome> playWord(String? audioFile) async {
    ++_seq;
    if (audioFile == null || audioFile.isEmpty) return PlayOutcome.none;

    final userPath = await userAudioPath(audioFile);
    if (userPath != null) {
      return await _playFile(userPath)
          ? PlayOutcome.userAudio
          : PlayOutcome.none;
    }

    for (final p in audioAssetCandidates(audioFile)) {
      if (await _playAsset(p)) return PlayOutcome.asset;
    }

    final alt = swapAudioExt(audioFile);
    if (alt != null) {
      for (final p in audioAssetCandidates(alt)) {
        if (await _playAsset(p)) return PlayOutcome.asset;
      }
    }
    return PlayOutcome.none;
  }

  static String? swapAudioExt(String rel) {
    final low = rel.toLowerCase();
    if (low.endsWith('.mp3')) return '${rel.substring(0, rel.length - 4)}.ogg';
    if (low.endsWith('.ogg')) return '${rel.substring(0, rel.length - 4)}.mp3';
    return null;
  }

  static List<String> audioAssetCandidates(String rel, {bool? isIOS}) {
    final ios = isIOS ?? Platform.isIOS;
    final out = <String>[];
    if (ios) {
      final m4a = iosAudioPath(rel);
      if (m4a != null) out.add('audio/$m4a');
    }
    out.add('audio/$rel');
    return out;
  }

  static String? iosAudioPath(String rel) {
    const from = 'edge/ardi/';
    if (!rel.startsWith(from) || !rel.toLowerCase().endsWith('.ogg')) return null;
    final name = rel.substring(from.length, rel.length - 4);
    return 'edge/ardi_m4a/$name.m4a';
  }

  Future<Source> _sourceForAsset(String path) async {
    const ardiPrefix = 'audio/edge/ardi/';
    if (path.startsWith(ardiPrefix)) {
      final name = path.substring(ardiPrefix.length);
      final idx = await _loadPackIndex();
      final entry = idx[name];
      if (entry != null) {
        final b = entry.bucket.toString().padLeft(2, '0');
        final packRel = 'assets/audio_pack/ardi_$b.pak';
        final webBytes =
            await fetchWebPackSlice(packRel, entry.offset, entry.length);
        if (webBytes != null && webBytes.isNotEmpty) {
          return BytesSource(webBytes, mimeType: 'audio/ogg');
        }
        final bytes = await _packCh.invokeMethod<Uint8List>('readPackAudio', {
          'pack': packRel,
          'offset': entry.offset,
          'length': entry.length,
        });
        if (bytes != null && bytes.isNotEmpty) {
          return BytesSource(bytes, mimeType: 'audio/ogg');
        }
      }
    }
    return AssetSource(path);
  }

  Future<bool> _playAsset(String path) async {
    final player = _player;
    if (player == null) return false;
    try {
      await player.stop();
      await player.play(await _sourceForAsset(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _playFile(String path) async {
    final player = _player;
    if (player == null) return false;
    try {
      if (!await File(path).exists()) return false;
      await player.stop();
      await player.play(DeviceFileSource(path));
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<String> importUserAudio(String id, String srcPath) async {
  final dir = await AudioService.userAudioDir();
  final dot = srcPath.lastIndexOf('.');
  final ext = dot >= 0 ? srcPath.substring(dot).toLowerCase() : '.mp3';
  final name = '$id$ext';
  await File(srcPath).copy('${dir.path}/$name');
  return '$kUserAudioPrefix$name';
}

Future<void> removeUserAudio(String? au) async {
  final path = await AudioService.userAudioPath(au);
  if (path == null) return;
  final f = File(path);
  if (await f.exists()) await f.delete();
}
