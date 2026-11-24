/// AI 助手印尼语朗读模块（仅走用户自配的 OpenAI 兼容 `/audio/speech` + `audioplayers`，
/// 严禁接入系统 TTS 兜底，与 `pubspec.yaml` 纪律一致）。
library;

import 'dart:convert';
import 'platform/io_shim.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'ai_chat.dart' show AiSpeechConfig, redactKey;

final RegExp _reFencedCode = RegExp(r'```[\s\S]*?```');
final RegExp _reQuizBlock = RegExp(r'^:::quiz\b[\s\S]*?^:::\s*$', multiLine: true);
final RegExp _reMdLink = RegExp(r'\[([^\]]+)\]\([^)]+\)');
final RegExp _reUrl = RegExp(r'https?://\S+');
final RegExp _reMdTableSep = RegExp(r'^\|?[\s:|-]+\|[\s:|-]*$');
final RegExp _reCjkParen = RegExp(r'[（(][^）)]*[\u4e00-\u9fff][^）)]*[）)]');
final RegExp _reCjk = RegExp(r'[\u4e00-\u9fff]');
final RegExp _reCjkOrFullwidth = RegExp(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+');
final RegExp _reLatinWord = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{2,}');
final RegExp _reLatinChar = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');
final RegExp _reMdBold = RegExp(r'\*\*([^*]+)\*\*');
final RegExp _reMdItalic = RegExp(r'(?<!\*)\*([^*\s][^*\n]*?)(?<!\s)\*(?![*A-Za-zÀ-ÖØ-öø-ÿ])');
final RegExp _reStarUngrammatical = RegExp(r'(?:^|(?<=[\s（(「『，、：:]))\*[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ-]*');
// 仅按冒号、破折号或「两侧带空格的连字符」切分「印尼语 — 中文释义」，绝不切开 Anak-anak / hati-hati 等词内连字符！
final RegExp _rePrefixGloss = RegExp(
    r'^([A-Za-zÀ-ÖØ-öø-ÿ][^\n：:—–]*?)\s*(?:[：:—–]+|\s+-\s+)\s*[^\n]*[\u4e00-\u9fff].*$');

/// 从 AI 混合中印回复中抽取可朗读的印尼语正文，自动剥离中文解释、错误示例（*merubah）、Markdown 标记、链接与题卡块。
String extractIndonesianForTts(String raw, {int maxChars = 1200}) {
  if (raw.trim().isEmpty) return '';
  var s = raw
      .replaceAll(_reQuizBlock, '\n')
      .replaceAll(_reFencedCode, '\n')
      .replaceAllMapped(_reMdLink, (m) => m.group(1)!)
      .replaceAll(_reUrl, ' ');

  final out = <String>[];
  for (final rawLine in s.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || _reMdTableSep.hasMatch(line)) continue;
    line = line
        .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^[-*+•]\s+'), '')
        .replaceFirst(RegExp(r'^\d+[.)]\s+'), '')
        .replaceAllMapped(_reMdBold, (m) => m.group(1)!)
        .replaceAllMapped(_reMdItalic, (m) => m.group(1)!)
        .replaceAll(_reStarUngrammatical, ' ')
        .replaceAll(RegExp(r'[*_`~>|]'), ' ')
        .replaceAll(_reCjkParen, ' ')
        .trim();
    if (line.isEmpty) continue;

    final glossMatch = _rePrefixGloss.firstMatch(line);
    if (glossMatch != null) {
      line = glossMatch.group(1)!.trim();
    }

    // 按句号/问号/感叹号或中文句读拆句后再过滤，保留混合段落里的完整印尼语句（含复叠词连字符）
    for (final segRaw in line.split(RegExp(r'(?<=[.!?])\s+|(?<=[。！？；])\s*'))) {
      final seg = segRaw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (seg.isEmpty) continue;
      if (!_reLatinWord.hasMatch(seg)) continue;
      final latinCount = _reLatinChar.allMatches(seg).length;
      final cjkCount = _reCjk.allMatches(seg).length;
      if (cjkCount == 0 || latinCount >= cjkCount * 2) {
        final cleaned = seg
            .replaceAll(_reCjkOrFullwidth, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (_reLatinWord.hasMatch(cleaned)) {
          out.add(cleaned);
        }
      }
    }
  }

  final joined = out.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (joined.length <= maxChars) return joined;
  final cut = joined.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  return (lastSpace > maxChars ~/ 2 ? cut.substring(0, lastSpace) : cut).trim();
}

/// 校验并补全 `/audio/speech` 接口地址。仅允许 HTTPS（或本地 localhost/127.0.0.1）。
Uri? resolveAiTtsUri(String endpoint) {
  final raw = endpoint.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasAuthority) return null;
  final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && isLocal)) {
    return null;
  }
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.endsWith('/audio/speech') || path.endsWith('/tts')) {
    return uri.replace(path: path);
  }
  return uri.replace(path: '$path/audio/speech');
}

/// 构造 OpenAI 兼容 `/audio/speech` 请求体。
Map<String, Object?> buildAiTtsPayload(
  AiSpeechConfig cfg,
  String text, {
  double speed = 1.0,
}) =>
    {
      'model': cfg.model.trim().isNotEmpty ? cfg.model.trim() : 'tts-1',
      'input': text,
      'voice': 'alloy',
      'response_format': 'mp3',
      'speed': speed.clamp(0.5, 2.0),
    };

/// AI 回复印尼语朗读播放器（支持 1.0× / 0.75× 语速与单活停止）。
class AiTtsPlayer extends ChangeNotifier {
  AudioPlayer? _player;
  bool _loading = false;
  bool _playing = false;
  String? _activeKey;
  double _speed = 1.0;

  bool get loading => _loading;
  bool get playing => _playing;
  String? get activeKey => _activeKey;
  double get speed => _speed;

  bool isActive(String key) => _activeKey == key && (_loading || _playing);

  void toggleSpeed() {
    _speed = (_speed - 0.75).abs() < 0.05 ? 1.0 : 0.75;
    notifyListeners();
  }

  AudioPlayer _ensurePlayer() {
    if (_player != null) return _player!;
    final p = AudioPlayer();
    p.onPlayerComplete.listen((_) {
      _playing = false;
      _activeKey = null;
      notifyListeners();
    });
    _player = p;
    return p;
  }

  Future<void> stop() async {
    _loading = false;
    _playing = false;
    _activeKey = null;
    try {
      await _player?.stop();
    } catch (_) {}
    notifyListeners();
  }

  /// 播放或停止指定气泡的印尼语正文；返回错误提示（成功为 null）。
  Future<String?> toggleSpeak({
    required String key,
    required String rawText,
    required AiSpeechConfig config,
    double? speed,
  }) async {
    final targetSpeed = speed ?? _speed;
    if (isActive(key) && (speed == null || (speed - _speed).abs() < 0.01)) {
      await stop();
      return null;
    }

    final text = extractIndonesianForTts(rawText);
    if (text.isEmpty) {
      return '这条回复里没有可朗读的印尼语内容';
    }
    final uri = resolveAiTtsUri(config.endpoint);
    if (uri == null) {
      return '请先在 AI 设置里填写有效的 HTTPS 语音接口地址';
    }

    await stop();
    _activeKey = key;
    _loading = true;
    _speed = targetSpeed;
    notifyListeners();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(uri);
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      final apiKey = config.apiKey.trim();
      if (apiKey.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $apiKey');
      }
      req.write(jsonEncode(buildAiTtsPayload(config, text, speed: targetSpeed)));
      final resp = await req.close();
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

      if (_activeKey != key) return null; // 用户已取消或切到另一条

      if (resp.statusCode != 200) {
        final msg = redactKey(utf8.decode(bytes, allowMalformed: true), apiKey);
        await stop();
        return '语音合成失败（HTTP ${resp.statusCode}）${msg.isEmpty ? '' : '：${msg.length > 80 ? msg.substring(0, 80) : msg}'}';
      }
      if (bytes.isEmpty) {
        await stop();
        return '语音接口返回了空音频';
      }

      _loading = false;
      _playing = true;
      notifyListeners();

      final player = _ensurePlayer();
      await player.play(BytesSource(Uint8List.fromList(bytes)));
      return null;
    } catch (e) {
      final clean = redactKey('$e', config.apiKey.trim());
      await stop();
      return '朗读出错：$clean';
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _player = null;
    super.dispose();
  }
}
