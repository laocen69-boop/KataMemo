library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart' show ThemeMode;

import 'db.dart';

export 'db.dart'
    show
        AppDbGrammar,
        AppDbWords,
        AppDbSearch,
        AppDbCard,
        AppDbStudy,
        AppDbStats;
import 'activity_log.dart' show primeActivityLogs;
import 'ai_chat.dart';
import 'ai_search.dart';
import 'data_repo.dart';
import 'grammar/grammar_repo.dart';
import 'fsrs.dart';
import 'fsrs_personalize.dart';
import 'models.dart';
import 'notifications.dart';

class AppState extends ChangeNotifier {
  final AppDb db;
  late final DataRepo repo;

  late final GrammarRepo grammar;

  late final GrammarRepo writing;

  AppState(this.db, {GrammarRepo? grammar, GrammarRepo? writing}) {
    repo = DataRepo(db);
    this.grammar = grammar ?? GrammarRepo();
    this.writing = writing ?? GrammarRepo(assetPath: kWritingAssetPath);
  }

  bool _ready = false;
  bool get ready => _ready;

  static const int kMaxDailyQuota = 9999;

  int _dailyQuota = 20;
  int get dailyQuota => _dailyQuota;
  bool _autoSpeak = true;

  String _librarySort = 'rank';
  String get librarySort => _librarySort;

  bool _onboardSeen = false;
  bool get onboardSeen => _onboardSeen;

  bool _noticeSeen = false;
  bool get noticeSeen => _noticeSeen;

  bool _swipeTipDismissed = false;
  bool get swipeTipDismissed => _swipeTipDismissed;

  bool get autoSpeak => _autoSpeak;

  double _retention = 0.9;
  double get retention => _retention;
  bool _loadBalance = true;
  bool get loadBalance => _loadBalance;

  bool _darkMode = false;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get darkMode => _darkMode;

  String _studyMode = 'id2zh';
  String get studyMode => _studyMode;

  bool _showIntervals = true;
  bool get showIntervals => _showIntervals;

  bool _reminderOn = true;
  bool get reminderOn => _reminderOn;

  String _aiProvider = 'deepseek';
  final Map<String, String> _aiKeys = {};
  final Map<String, String> _aiModels = {};
  final Map<String, String> _aiBases = {};
  final Map<String, AiStatus> _aiStatus = {};

  bool _aiFab = true;
  double _aiFabX = 1, _aiFabY = 0.62;

  bool _aiNoticeSeen = false;

  bool _aiTools = true;
  bool get aiTools => _aiTools;

  String _aiSearchProvider = '';
  bool _aiSearchExplicit = false;
  String _aiSearchCustomEndpoint = '';
  final Map<String, String> _aiSearchKeys = {};
  int _aiSearchUsed = 0;
  String _aiSearchUsedMonth = '';

  String get aiSearchCustomEndpoint => _aiSearchCustomEndpoint;
  bool get aiSearchExplicitlyOff =>
      _aiSearchExplicit && _aiSearchProvider.isEmpty;

  String get aiSearchProviderId {
    if (_aiSearchExplicit) return _aiSearchProvider;
    final p = _aiProvider;
    if (p == 'deepseek' && (_aiKeys['deepseek'] ?? '').trim().isNotEmpty) {
      return 'deepseek';
    }
    if (p == 'glm' && (_aiKeys['glm'] ?? '').trim().isNotEmpty) {
      return 'zhipu';
    }
    return _aiSearchProvider;
  }

  AiSearchProvider? get aiSearchProvider => aiSearchProviderById(aiSearchProviderId);

  String aiSearchKeyFor(String id) {
    final p = aiSearchProviderById(id);
    if (p == null) return '';
    final reuse = p.reuseAiKeyOf;
    return reuse != null ? (_aiKeys[reuse] ?? '') : (_aiSearchKeys[id] ?? '');
  }

  bool aiSearchConfigured(String id) {
    if (aiSearchKeyFor(id).trim().isEmpty) return false;
    if (id == 'custom') {
      return aiValidCustomSearchEndpoint(_aiSearchCustomEndpoint);
    }
    return true;
  }

  bool get aiSearchReady {
    final id = aiSearchProviderId;
    return aiSearchProviderById(id) != null && aiSearchConfigured(id);
  }

  int get aiSearchUsedThisMonth =>
      _aiSearchUsedMonth == aiSearchMonthKey() ? _aiSearchUsed : 0;

  AiSpeechConfig _aiAsr = const AiSpeechConfig();
  AiSpeechConfig _aiTts = const AiSpeechConfig();
  AiSpeechConfig get aiAsrConfig => _aiAsr;
  AiSpeechConfig get aiTtsConfig => _aiTts;
  bool get aiAsrConfigured => _aiAsr.configured;
  bool get aiTtsConfigured => _aiTts.configured;

  int? _aiCustomMaxOutput;
  int? get aiCustomMaxOutput => _aiCustomMaxOutput;
  int? get aiMaxOutput =>
      aiMaxOutputFor(aiConfig, customMaxOutput: _aiCustomMaxOutput);

  AiLevel _aiLevel = AiLevel.intermediate;
  AiLevel get aiLevel => _aiLevel;
  Future<void> setAiLevel(AiLevel v) async {
    if (v == _aiLevel) return;
    _aiLevel = v;
    await db.metaSet('ai_level', v.name);
    notifyListeners();
  }
  Future<void> setAiTools(bool v) async {
    if (v == _aiTools) return;
    _aiTools = v;
    await db.metaSet('ai_tools', v ? '1' : '0');
    notifyListeners();
  }

  AiCtxTier _aiCtx = AiCtxTier.auto;
  AiCtxTier get aiCtxTier => _aiCtx;
  Future<void> setAiCtxTier(AiCtxTier v) async {
    if (v == _aiCtx) return;
    _aiCtx = v;
    await db.metaSet('ai_ctx', v.name);
    notifyListeners();
  }

  final Map<String, Map<String, int>> _aiCtxWin = {};
  Future<void> setAiModelWindows(String id, Map<String, int> wins) async {
    if (wins.isEmpty) return;
    _aiCtxWin[id] = Map.of(wins);
    await db.metaSet('ai_ctx_win.$id', jsonEncode(wins));
    notifyListeners();
  }

  AiModelWindow get aiWindow {
    final cfg = aiConfig;
    return aiModelWindow(cfg.model, detected: _aiCtxWin[cfg.provider.id]?[cfg.model.trim()]);
  }

  AiBudget get aiBudget => aiBudgetFor(_aiCtx, aiWindow);
  AiBudget aiBudgetForTurn({bool forTools = false}) =>
      aiBudgetFor(_aiCtx, aiWindow, forTools: forTools);

  bool _aiMemoryEnabled = true;
  bool get aiMemoryEnabled => _aiMemoryEnabled;
  Future<void> setAiMemoryEnabled(bool v) async {
    if (v == _aiMemoryEnabled) return;
    _aiMemoryEnabled = v;
    await db.metaSet('ai_memory_enabled', v ? '1' : '0');
    notifyListeners();
  }

  String _aiLearningMemory = '';
  String get aiLearningMemory => _aiLearningMemory;
  Future<void> setAiLearningMemory(String v) async {
    final c = aiClipMemory(v);
    if (c == _aiLearningMemory) return;
    _aiLearningMemory = c;
    await _metaPut('ai_learning_memory', c);
    notifyListeners();
  }

  bool get aiDiag => AiDiag.enabled;
  Future<void> setAiDiag(bool v) async {
    if (v == AiDiag.enabled) return;
    AiDiag.enabled = v;
    if (!v) AiDiag.clear();
    await db.metaSet('ai_diag', v ? '1' : '0');
    notifyListeners();
  }

  String get aiProviderId => _aiProvider;
  AiProvider get aiProvider => aiProviderById(_aiProvider);
  AiConfig aiConfigFor(String id) => AiConfig(
        provider: aiProviderById(id),
        apiKey: _aiKeys[id] ?? '',
        model: _aiModels[id] ?? '',
        baseOverride: _aiBases[id] ?? '',
      );
  AiConfig get aiConfig => aiConfigFor(_aiProvider);
  bool get aiReady => aiConfig.ready;
  AiStatus aiStatusFor(String id) => _aiStatus[id] ?? AiStatus.unknown;
  AiStatus get aiStatus => aiStatusFor(_aiProvider);
  bool aiConfigured(String id) => (_aiKeys[id] ?? '').isNotEmpty;
  bool get aiFab => _aiFab;
  double get aiFabX => _aiFabX;
  double get aiFabY => _aiFabY;
  bool get aiNoticeSeen => _aiNoticeSeen;

  int _queueRevision = 0;
  int get queueRevision => _queueRevision;

  int _planRevision = 0;
  int get planRevision => _planRevision;
  void bumpPlan() {
    _planRevision++;
    notifyListeners();
  }

  BookNode? _book;
  BookNode? get book => _book;
  Map<String, dynamic>? get bookFilter => _book?.filter;

  static const _kQuota = 'new_quota';
  static const _kAutoSpeak = 'auto_speak';
  static const _kRetention = 'retention';
  static const _kLoadBalance = 'fsrs_load_balance';
  static const _kDark = 'dark_mode';
  static const _kThemeMode = 'theme_mode';
  static const _kStudyMode = 'study_mode';
  static const _kIntervals = 'show_intervals';
  static const _kLibSort = 'library_sort';
  static const _kOnboard = 'onboard_seen';
  static const _kNotice = 'first_notice_seen_v3';
  static const _kReminder = 'reminder_on';

  Future<void> init() {
    return _initFuture ??= _initOnce().catchError((Object e, StackTrace st) {
      _initFuture = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<void>? _initFuture;

  Future<void> _initOnce() async {
    await repo.ensureImported();

    await grammar.ensureLoaded();
    await _loadSettings();
    final bid = await db.currentBook();
    if (bid != null) {
      final books = await repo.loadBooks();
      for (final b in books) {
        if (b.id == bid) {
          _book = b;
          break;
        }
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final q = int.tryParse(await db.metaGet(_kQuota) ?? '');
    if (q != null) _dailyQuota = q.clamp(0, kMaxDailyQuota);
    final a = await db.metaGet(_kAutoSpeak);
    if (a != null) _autoSpeak = a == '1';

    final r = double.tryParse(await db.metaGet(_kRetention) ?? '');
    if (r != null) _retention = r.clamp(0.80, 0.95);
    final lb = await db.metaGet(_kLoadBalance);
    if (lb != null) _loadBalance = lb == '1';

    final tm = await db.metaGet(_kThemeMode);
    if (tm == 'light' || tm == 'dark' || tm == 'system') {
      _themeMode = tm == 'light'
          ? ThemeMode.light
          : (tm == 'dark' ? ThemeMode.dark : ThemeMode.system);
    } else {
      final dk = await db.metaGet(_kDark);
      if (dk == '1') {
        _themeMode = ThemeMode.dark;
      } else if (dk == '0') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }
    }
    _darkMode = _themeMode == ThemeMode.dark;
    final sm = await db.metaGet(_kStudyMode);
    if (sm == 'id2zh' || sm == 'zh2id') _studyMode = sm!;
    final si = await db.metaGet(_kIntervals);
    if (si != null) _showIntervals = si == '1';
    final ls = await db.metaGet(_kLibSort);
    if (ls != null && AppDb.kSortModes.contains(ls)) _librarySort = ls;
    final rm = await db.metaGet(_kReminder);
    if (rm != null) _reminderOn = rm == '1';

    final ob = await db.metaGet(_kOnboard);
    if (ob != null) _onboardSeen = ob == '1';
    _noticeSeen = await db.metaGet(_kNotice) == '1';
    _swipeTipDismissed = (await db.metaGet('swipe_target_tip')) == '1';
    await _loadAi();
    await _loadFsrsWeights();
  }

  int? _fsrsWTs;

  int? get fsrsWeightsTs => _fsrsWTs;
  bool get fsrsPersonalized => _fsrsWTs != null;

  Future<void> _loadFsrsWeights() async {
    Fsrs.useWeights(null);
    _fsrsWTs = null;
    try {
      final raw = await db.metaGet('fsrs_w');
      if (raw != null) {
        final w = FsrsPersonalize.parseWeights(raw);
        if (FsrsPersonalize.validateWeights(w) == null) {
          Fsrs.useWeights(w);
          _fsrsWTs = int.tryParse(await db.metaGet('fsrs_w_ts') ?? '') ?? 0;
        }
      }
    } catch (_) {}
  }

  Future<void> applyFsrsWeights(List<double> w) async {
    final prev = await db.metaGet('fsrs_w');
    await db.metaSet('fsrs_w_prev', prev ?? '');
    await _writeWeights(w);
  }

  Future<void> _writeWeights(List<double>? w) async {
    if (w == null) {
      await db.metaDelete('fsrs_w');
      await db.metaDelete('fsrs_w_ts');
    } else {
      await db.metaSet('fsrs_w', '[${w.join(',')}]');
      await db.metaSet('fsrs_w_ts', '${DateTime.now().millisecondsSinceEpoch}');
    }
    Fsrs.useWeights(w);
    _fsrsWTs = w == null ? null : DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  Future<bool> fsrsHasUndo() async => await db.metaGet('fsrs_w_prev') != null;

  Future<bool> undoFsrsWeights() async {
    final prev = await db.metaGet('fsrs_w_prev');
    if (prev == null) return false;
    List<double>? w;
    if (prev.isNotEmpty) {
      final parsed = FsrsPersonalize.parseWeights(prev);
      if (FsrsPersonalize.validateWeights(parsed) != null) {

        await db.metaDelete('fsrs_w_prev');
        return false;
      }
      w = parsed;
    }
    await _writeWeights(w);
    await db.metaDelete('fsrs_w_prev');
    return true;
  }

  Future<void> resetFsrsWeights() async {
    await db.metaDelete('fsrs_w_prev');
    await _writeWeights(null);
  }

  Future<void> reloadAfterRestore() async {
    await db.applyUserEdits();
    await db.replayPlannedDerived();
    await _loadSettings();
    Fsrs.requestedRetention = _retention;
    final bid = await db.currentBook();
    _book = null;
    if (bid != null) {
      final books = await repo.loadBooks();
      for (final b in books) {
        if (b.id == bid) {
          _book = b;
          break;
        }
      }
    }
    _queueRevision++;
    notifyListeners();
  }

  Future<void> setBook(BookNode? b) async {
    _book = (b == null || b.id == 'all') ? null : b;
    await db.setCurrentBook(_book?.id);
    _queueRevision++;
    notifyListeners();
  }

  Future<void> setQuota(int v) async {
    final nv = v.clamp(0, kMaxDailyQuota);
    if (nv == _dailyQuota) return;
    _dailyQuota = nv;
    await db.metaSet(_kQuota, '$nv');
    _queueRevision++;
    notifyListeners();
  }

  Future<void> setLibrarySort(String v) async {
    if (!AppDb.kSortModes.contains(v) || v == _librarySort) return;
    _librarySort = v;
    await db.metaSet(_kLibSort, v);
    notifyListeners();
  }

  Future<void> markOnboardSeen() async {
    if (_onboardSeen) return;
    _onboardSeen = true;
    await db.metaSet(_kOnboard, '1');
    notifyListeners();
  }

  Future<void> markNoticeSeen() async {
    if (_noticeSeen) return;
    _noticeSeen = true;
    await db.metaSet(_kNotice, '1');
  }

  Future<void> dismissSwipeTargetTip() async {
    if (_swipeTipDismissed) return;
    _swipeTipDismissed = true;
    await db.metaSet('swipe_target_tip', '1');
    notifyListeners();
  }

  Future<void> _loadAi() async {
    _aiKeys.clear();
    _aiCtxWin.clear();
    _aiModels.clear();
    _aiBases.clear();
    _aiStatus.clear();
    _aiSearchKeys.clear();
    _aiSearchUsed = 0;
    _aiSearchUsedMonth = '';
    final raw = await db.db;
    final rows = await raw.rawQuery(
        "SELECT k, v FROM meta WHERE k LIKE 'ai\\_%' ESCAPE '\\' OR k LIKE 'log.%'");
    final m = {for (final r in rows) r['k'] as String: (r['v'] as String?) ?? ''};

    primeActivityLogs(m);

    if ((m['ai_key'] ?? '').isNotEmpty) {
      final base = m['ai_base'] ?? '';
      final pid = base.isEmpty || base.contains('api.deepseek.com')
          ? 'deepseek'
          : 'custom';
      final model = (m['ai_model'] ?? '').isEmpty && pid == 'deepseek'
          ? 'deepseek-flash'
          : (m['ai_model'] ?? '');
      m['ai_key.$pid'] = m['ai_key']!;
      m['ai_model.$pid'] = model;
      if (pid == 'custom') m['ai_base.$pid'] = base;
      m['ai_provider'] = pid;
      for (final e in [
        ('ai_key.$pid', m['ai_key']!),
        ('ai_model.$pid', model),
        if (pid == 'custom') ('ai_base.$pid', base),
        ('ai_provider', pid),
      ]) {
        await db.metaSet(e.$1, e.$2);
      }
      for (final k in ['ai_key', 'ai_base', 'ai_model']) {
        await db.metaDelete(k);
      }
    }
    for (final e in m.entries) {
      final dot = e.key.indexOf('.');
      if (dot < 0) continue;
      final kind = e.key.substring(0, dot);
      final id = e.key.substring(dot + 1);
      switch (kind) {
        case 'ai_key':
          _aiKeys[id] = e.value;
        case 'ai_model':
          _aiModels[id] = e.value;
        case 'ai_base':
          _aiBases[id] = e.value;
        case 'ai_status':
          _aiStatus[id] = AiStatus.decode(e.value);
        case 'ai_search_key':
          _aiSearchKeys[id] = e.value;
        case 'ai_ctx_win':
          try {
            final j = jsonDecode(e.value) as Map;
            _aiCtxWin[id] = {
              for (final x in j.entries)
                if (x.value is num) '${x.key}': (x.value as num).toInt(),
            };
          } catch (_) {}
        case 'ai_search_used':
          if (id == aiSearchMonthKey()) {
            _aiSearchUsedMonth = id;
            _aiSearchUsed = int.tryParse(e.value) ?? 0;
          }
      }
    }
    _aiSearchExplicit = m.containsKey('ai_search_provider');
    _aiSearchProvider = aiSearchProviderById(m['ai_search_provider'])?.id ?? '';
    _aiSearchCustomEndpoint = m['ai_search_custom_endpoint'] ?? '';
    _aiLocalDict = m['ai_local_dict'] == '1';
    _aiProvider = aiProviderById(m['ai_provider']).id;
    _aiFab = m['ai_fab'] != '0';
    final pos = (m['ai_fab_pos'] ?? '').split(',');
    if (pos.length == 2) {
      _aiFabX = (double.tryParse(pos[0]) ?? 1).clamp(0.0, 1.0);
      _aiFabY = (double.tryParse(pos[1]) ?? 0.62).clamp(0.0, 1.0);
    }
    _aiNoticeSeen = m['ai_notice'] == '1';
    _aiTools = m['ai_tools'] != '0';
    _aiLevel = aiLevelFromName(m['ai_level']);
    _aiCtx = aiCtxTierFromName(m['ai_ctx']);
    _aiMemoryEnabled = m['ai_memory_enabled'] != '0';
    _aiLearningMemory = aiClipMemory(m['ai_learning_memory'] ?? '');
    final customOut = int.tryParse(m['ai_custom_max_output'] ?? '');
    _aiCustomMaxOutput = customOut != null && customOut >= 1024 ? customOut : null;
    _aiAsr = AiSpeechConfig(
      enabled: m['ai_asr_on'] == '1',
      endpoint: m['ai_asr_base'] ?? '',
      model: m['ai_asr_model'] ?? '',
      apiKey: m['ai_asr_key'] ?? '',
    );
    _aiTts = AiSpeechConfig(
      enabled: m['ai_tts_on'] == '1',
      endpoint: m['ai_tts_base'] ?? '',
      model: m['ai_tts_model'] ?? '',
      apiKey: m['ai_tts_key'] ?? '',
    );
    AiDiag.enabled = m['ai_diag'] == '1';
  }

  Future<void> _metaPut(String k, String v) =>
      v.isEmpty ? db.metaDelete(k) : db.metaSet(k, v);

  Future<void> saveAiProvider(
    String id, {
    required String key,
    required String model,
    required String base,
    bool select = true,
  }) async {
    final k = key.trim(), mo = model.trim(), b = base.trim();
    final changed = (_aiKeys[id] ?? '') != k ||
        (_aiModels[id] ?? '') != mo ||
        (_aiBases[id] ?? '') != b;
    _aiKeys[id] = k;
    _aiModels[id] = mo;
    _aiBases[id] = b;
    await _metaPut('ai_key.$id', k);
    await _metaPut('ai_model.$id', mo);
    await _metaPut('ai_base.$id', b);
    if (changed && _aiStatus.containsKey(id)) {
      _aiStatus.remove(id);
      await db.metaDelete('ai_status.$id');
    }
    if (select) {
      _aiProvider = id;
      await db.metaSet('ai_provider', id);
    }
    notifyListeners();
  }

  Future<void> selectAiProvider(String id) async {
    if (id == _aiProvider) return;
    _aiProvider = aiProviderById(id).id;
    await db.metaSet('ai_provider', _aiProvider);
    notifyListeners();
  }

  Future<void> setAiStatus(String id, AiStatus s) async {
    _aiStatus[id] = s;
    await db.metaSet('ai_status.$id', s.encode());
    notifyListeners();
  }

  Future<void> setAiFab(bool v) async {
    if (v == _aiFab) return;
    _aiFab = v;
    await db.metaSet('ai_fab', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setAiFabPos(double x, double y) async {
    _aiFabX = x.clamp(0.0, 1.0);
    _aiFabY = y.clamp(0.0, 1.0);
    await db.metaSet('ai_fab_pos',
        '${_aiFabX.toStringAsFixed(3)},${_aiFabY.toStringAsFixed(3)}');
  }

  bool _aiLocalDict = false;
  bool get aiLocalDictOn => _aiLocalDict;

  Future<void> setAiLocalDict(bool on) async {
    _aiLocalDict = on;
    await _metaPut('ai_local_dict', on ? '1' : '0');
    notifyListeners();
  }

  Future<void> saveAiSearch(
    String id, {
    String? key,
    String? endpoint,
    bool select = true,
  }) async {
    if (id.isNotEmpty && aiSearchProviderById(id) == null) return;
    if (id.isNotEmpty && key != null) {
      final k = key.trim();
      _aiSearchKeys[id] = k;
      await _metaPut('ai_search_key.$id', k);
    }
    if (id == 'custom' && endpoint != null) {
      final ep = endpoint.trim();
      _aiSearchCustomEndpoint = ep;
      await _metaPut('ai_search_custom_endpoint', ep);
    }
    if (select) {
      _aiSearchExplicit = true;
      _aiSearchProvider = id;
      await _metaPut('ai_search_provider', id);
    }
    notifyListeners();
  }

  Future<void> saveAiSpeech({
    required bool isAsr,
    required bool enabled,
    required String endpoint,
    required String model,
    required String apiKey,
  }) async {
    final cfg = AiSpeechConfig(
      enabled: enabled,
      endpoint: endpoint.trim(),
      model: model.trim(),
      apiKey: apiKey.trim(),
    );
    final pfx = isAsr ? 'ai_asr' : 'ai_tts';
    if (isAsr) {
      _aiAsr = cfg;
    } else {
      _aiTts = cfg;
    }
    await _metaPut('${pfx}_on', cfg.enabled ? '1' : '0');
    await _metaPut('${pfx}_base', cfg.endpoint);
    await _metaPut('${pfx}_model', cfg.model);
    await _metaPut('${pfx}_key', cfg.apiKey);
    notifyListeners();
  }

  Future<void> setAiCustomMaxOutput(int? v) async {
    _aiCustomMaxOutput = v != null && v >= 1024 ? v : null;
    await _metaPut('ai_custom_max_output', _aiCustomMaxOutput?.toString() ?? '');
    notifyListeners();
  }

  Future<void> bumpAiSearchUsed() async {
    final mk = aiSearchMonthKey();
    if (_aiSearchUsedMonth != mk) {
      _aiSearchUsedMonth = mk;
      _aiSearchUsed = 0;
    }
    _aiSearchUsed++;
    try {
      await db.metaSet('ai_search_used.$mk', '$_aiSearchUsed');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> markAiNoticeSeen() async {
    if (_aiNoticeSeen) return;
    _aiNoticeSeen = true;
    await db.metaSet('ai_notice', '1');
  }

  Future<void> setAutoSpeak(bool v) async {
    _autoSpeak = v;
    await db.metaSet(_kAutoSpeak, v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setRetention(double v) async {
    _retention = v.clamp(0.80, 0.95);
    await db.metaSet(_kRetention, '$_retention');
    notifyListeners();
  }

  Future<void> setLoadBalance(bool v) async {
    _loadBalance = v;
    await db.metaSet(_kLoadBalance, v ? '1' : '0');
    notifyListeners();
  }

  Future<int> postponeOverdue({required int days, double ratio = 0.5}) async {
    final moved =
        await db.postponeOverdueReviews(postponeDays: days, ratio: ratio);
    if (moved > 0) {
      _queueRevision++;
      _planRevision++;
      notifyListeners();
    }
    return moved;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    _themeMode = m;
    _darkMode = m == ThemeMode.dark;
    await db.metaSet(
        _kThemeMode,
        m == ThemeMode.light
            ? 'light'
            : (m == ThemeMode.dark ? 'dark' : 'system'));
    notifyListeners();
  }

  Future<void> setDarkMode(bool v) =>
      setThemeMode(v ? ThemeMode.dark : ThemeMode.light);

  Future<void> setStudyMode(String v) async {
    _studyMode = v;
    await db.metaSet(_kStudyMode, v);
    notifyListeners();
  }

  Future<void> setShowIntervals(bool v) async {
    _showIntervals = v;
    await db.metaSet(_kIntervals, v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setReminderOn(bool v) async {
    if (v == _reminderOn) return;
    _reminderOn = v;
    await db.metaSet(_kReminder, v ? '1' : '0');
    notifyListeners();
    await NotificationService.setEnabled(v);
  }

  Future<void> remember(List<String> ids) async {
    await db.planWord(ids);
    notifyListeners();
  }

  Future<void> forget(List<String> ids) async {
    await db.unenroll(ids);
    notifyListeners();
  }
}
