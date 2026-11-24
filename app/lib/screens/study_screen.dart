library;

import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'
    show SchedulerBinding, SchedulerPhase, TickerCanceled;
import 'package:flutter/services.dart'
    show
        HapticFeedback,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        LogicalKeyboardKey;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../audio.dart';

import '../cloze.dart';

import '../db.dart';
import 'package:katamemo/fsrs.dart';
import '../fsrs_queue_tools.dart';
import '../models.dart';
import '../question_zh.dart';
import '../ratings.dart';
import '../theme/k_colors.dart';
import '../version.dart' show kAiChat, kKbbiLocal, kOpenStudyLayout;
import '../kbbi_link.dart';
import '../widgets/affix_section.dart';
import '../widgets/ai_chat_sheet.dart' show showAiChatSheet;
import '../widgets/ai_widgets.dart' show AiAskCard;
import '../widgets/clitic_section.dart';
import '../widgets/derivation_section.dart';
import '../widgets/grammar_note_section.dart';
import '../widgets/homograph_hint.dart';
import '../widgets/letter_slots.dart';
import '../widgets/mnemonic_section.dart';
import '../widgets/pair_list_editor.dart';
import '../widgets/mnemonic_templates.dart';
import '../widgets/postpone_sheet.dart';
import '../widgets/quota_dialog.dart';
import '../widgets/review_history.dart';
import '../widgets/speak_button.dart';
import '../widgets/target_actions.dart' show showTargetPicker;
import '../widgets/tappable_text.dart';
import '../perf_log.dart';
import '../widgets/word_sheet.dart';
import 'home_shell.dart' show HomeTabs;
import 'select_screen.dart';
import 'settings_screen.dart';
import 'text_reader_screen.dart';
import 'word_detail_screen.dart';

part 'study_edit.dart';
part 'study_header.dart';
part 'study_typing_done.dart';
part 'study_faces.dart';
part 'study_sections.dart';

BoxDecoration kStudyNewCard(BuildContext context, {Color? color}) {
  final k = context.k;
  return BoxDecoration(
    color: color ?? k.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: k.border, width: 0.5),
    boxShadow: k.shadowOn
        ? const [
            BoxShadow(
                color: Color(0x141D342C), blurRadius: 12, offset: Offset(0, 2)),
          ]
        : null,
  );
}

const Duration kRateFlash = Duration(milliseconds: 180);

Widget _newBlock(BuildContext context,
        {required Widget child, required bool hasLabel, Color? tint}) =>
    kOpenStudyLayout

        ? Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.k.bandDivider, width: 0.5),
              ),
            ),
            padding: hasLabel
                ? const EdgeInsets.fromLTRB(0, 4, 0, 12)
                : const EdgeInsets.fromLTRB(0, 12, 0, 12),
            child: child,
          )

        : Container(
            margin: const EdgeInsets.fromLTRB(15, 0, 15, 10),
            decoration: BoxDecoration(
              color: tint ?? context.k.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.k.border, width: 0.5),
            ),
            padding: hasLabel
                ? const EdgeInsets.fromLTRB(15, 4, 15, 12)
                : const EdgeInsets.fromLTRB(15, 12, 15, 12),
            child: child,
          );

class _PenIcon extends StatelessWidget {
  final double size;
  final Color color;
  const _PenIcon({this.size = 17, this.color = const Color(0xFF668078)});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _PenPainter(color),
      );
}

int _meaningLineCount(BuildContext context, String text,
    {double fontSize = 18, double rightInset = 17}) {
  final w = MediaQuery.sizeOf(context).width - 18 - 14 - 8 - rightInset;
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.3)),
    maxLines: 20,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w);
  return tp.computeLineMetrics().length;
}

class _PenPainter extends CustomPainter {
  final Color color;
  _PenPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final body = Path()
      ..moveTo(8, 15)
      ..relativeLineTo(2, -6)
      ..relativeLineTo(7, -7)
      ..relativeLineTo(4, 4)
      ..relativeLineTo(-7, 7)
      ..close();
    canvas.drawPath(body, p);

    canvas.drawLine(const Offset(7, 16), const Offset(11, 15), p);
  }

  @override
  bool shouldRepaint(covariant _PenPainter old) => old.color != color;
}

class _Undo {
  final int index;
  final String cardId;
  final FsrsState? prevSrs;
  final int logId;

  int? insertedAt;

  _Undo({
    required this.index,
    required this.cardId,
    required this.prevSrs,
    required this.logId,
  });
}

enum StudyStop { zero, quotaOut, moreGroup, nothingToLearn }

StudyStop studyStopOf(TodayPlan plan) {
  if (plan.quota == 0) return StudyStop.zero;

  final reviewOwe = plan.reviewPlan - plan.reviewDone;
  final newOwe = plan.newPlan - plan.newDone;
  if (reviewOwe <= 0 && newOwe <= 0 && plan.poolLeft <= 0) {
    return StudyStop.nothingToLearn;
  }
  return plan.finished >= plan.quota ? StudyStop.quotaOut : StudyStop.moreGroup;
}

class StudyScreen extends StatefulWidget {

  final ValueNotifier<int>? focusTick;
  final ValueListenable<bool>? activeListenable;

  final WordCard? previewCard;

  const StudyScreen({
    super.key,
    this.focusTick,
    this.activeListenable,
    this.previewCard,
  });

  static bool needsRequeue(FsrsState next) =>
      next.state == FsrsState.learning || next.state == FsrsState.relearning;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {

  List<({String id, bool isNew})> _queue = [];
  final Map<String, WordCard> _cards = {};
  static const int _window = 30;

  WordCard? _cardAt(int i) =>
      (i >= 0 && i < _queue.length) ? _cards[_queue[i].id] : null;

  Future<void> _hydrate(List<({String id, bool isNew})> q, int from,
      Map<String, WordCard> into) async {
    final start = from < 0 ? 0 : from;
    final end = math.min(start + _window, q.length);
    final need = <String>[
      for (var i = start; i < end; i++)
        if (!into.containsKey(q[i].id)) q[i].id
    ];
    if (need.isEmpty) return;
    final got = await context.read<AppState>().db.wordsByIds(need);
    for (final c in got) {
      into[c.id] = c;
    }

    for (var i = math.min(end, q.length) - 1; i >= start; i--) {
      if (!into.containsKey(q[i].id)) q.removeAt(i);
    }
  }

  bool get _previewMode => widget.previewCard != null;

  int _groupNo = 1;
  int _index = 0;
  bool _flipped = false;
  bool _busy = false;

  late final AnimationController _flashCtrl;
  bool _flashing = false;
  int? _flashIndex;

  Future<void> _writeChain = Future<void>.value();

  DateTime _tapGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get tapGuarded => DateTime.now().isBefore(_tapGuardUntil);

  String? _sensesShownFor;

  String? _stripKbbiFor;
  bool _loading = true;
  FsrsState? _curSrs;

  List<({DateTime day, int dayNo, int rating})> _histDays = const [];
  int _histLogs = 0;
  List<int> _histToday = const [];

  TodayPlan _plan = todayPlanOf(
      quota: 0,
      newDone: 0,
      reviewDone: 0,
      newPending: 0,
      reviewPending: 0,
      reviewBacklog: 0,
      poolLeft: 0);

  bool _neverEnrolled = false;

  final List<_Undo> _undo = [];
  final _scroll = ScrollController();

  final _hdrCollapsed = ValueNotifier<bool>(false);

  final _backScrolled = ValueNotifier<bool>(false);

  void _onBackScroll() {

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onBackScroll();
      });
      return;
    }
    if (_scroll.positions.length != 1) return;
    final p = _scroll.position;
    final off = p.pixels;
    _backScrolled.value = off > 1;
    if (!_hdrCollapsed.value) {
      if (off > 40 && p.maxScrollExtent > 120) _hdrCollapsed.value = true;
    } else if (off < 8) {
      _hdrCollapsed.value = false;
    }
  }

  final _editZhCtl = TextEditingController();
  final _editQzCtl = TextEditingController();
  final _editExCtl = TextEditingController();
  final _editDvCtl = TextEditingController();
  final _editMnCtl = TextEditingController();

  bool? _typeCorrect;
  final _typeCtl = TextEditingController();
  final _typeFocus = FocusNode();

  static const int _relearnGap = 6;

  static const int _exLimit = 3;
  bool _showAllEx = false;

  static const int _dvLimit = 12;

  static const int _gkLimit = 4;
  bool _showAllGk = false;

  bool _showExHint = false;

  bool _showAllDv = true;

  void _resetCardUi() {
    _hdrCollapsed.value = false;
    _backScrolled.value = false;
    _showAllEx = false;
    _showAllDv = true;
    _showAllGk = false;

    _flashing = false;
    _flashIndex = null;
    _flashCtrl.value = 0;
  }

  static const kBackPrebuildDelay = Duration(milliseconds: 400);

  GlobalKey _backKey = GlobalKey(debugLabel: 'study-back');

  String? _backToken;

  bool _backPrebuilt = false;
  Timer? _prebuildTimer;

  void _renewBackKey() {
    _backKey = GlobalKey(debugLabel: 'study-back');
    _backPrebuilt = false;
    _prebuildTimer?.cancel();
    _prebuildTimer = Timer(kBackPrebuildDelay, () {
      if (mounted && !_flipped && !_backPrebuilt) {
        setState(() => _backPrebuilt = true);
      }
    });
  }

  AppState? _app;
  int _seenRevision = -1;
  int _overdueCount = 0;
  bool _postponeBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _flashCtrl =
        AnimationController(vsync: this, duration: kRateFlash);
    _app = context.read<AppState>();
    _scroll.addListener(_onBackScroll);
    if (_previewMode) {

      _queue = [(id: widget.previewCard!.id, isNew: true)];
      _cards[widget.previewCard!.id] = widget.previewCard!;
      _index = 0;
      _loading = false;
      return;
    }
    _seenRevision = _app!.queueRevision;
    _app!.addListener(_onAppChanged);
    widget.focusTick?.addListener(_onFocus);
    unawaited(AudioService.instance.warmUp());
    _load();

    _app!.db.metaGet('seen_ex_hint').then((v) {
      if (!mounted) return;
      if (v == null) {
        setState(() => _showExHint = true);
        _app!.db.metaSet('seen_ex_hint', '1');
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _app?.removeListener(_onAppChanged);
    widget.focusTick?.removeListener(_onFocus);
    _prebuildTimer?.cancel();
    _scroll.dispose();
    _hdrCollapsed.dispose();
    _backScrolled.dispose();

    _typeCtl.dispose();
    _typeFocus.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  void _onAppChanged() {
    if (_previewMode) return;
    final app = _app;
    if (app == null) return;
    if (app.queueRevision != _seenRevision) {
      _seenRevision = app.queueRevision;
      _load();
    }
  }

  void _onFocus() {
    if (_previewMode || _loading) {
      _refreshCounters();
      return;
    }
    final atDone = _queue.isEmpty || _index >= _queue.length;
    if (atDone && studyStopOf(_plan) == StudyStop.nothingToLearn) {
      _load(newSession: true);
    } else {
      _refreshCounters();
    }
  }

  Future<void> _refreshCounters() async {
    if (_previewMode) return;
    final app = _app;
    if (app == null || !mounted) return;
    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    if (!mounted) return;
    setState(() => _plan = plan);
  }

  Future<void> _load({bool newSession = false}) async {
    if (newSession) _groupNo = 1;
    final app = context.read<AppState>();
    final s = await app.db.buildSessionQueueIds(
        dailyQuota: app.dailyQuota, filter: app.bookFilter);

    final newIds = await app.db.todayNewIds();
    final queue = <({String id, bool isNew})>[
      for (final id in s.due) (id: id, isNew: newIds.contains(id)),
      for (final id in s.fresh) (id: id, isNew: true),
    ];

    if (!mounted) return;
    final newCards = <String, WordCard>{};
    await _hydrate(queue, 0, newCards);

    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    final overdue = await app.db.overdueReviewCount();
    final never = queue.isEmpty && !await app.db.hasEnrolledCards();
    if (!mounted) return;
    setState(() {
      _neverEnrolled = never;
      _overdueCount = overdue;
      _queue = queue;
      _cards
        ..clear()
        ..addAll(newCards);
      _undo.clear();
      _index = 0;
      _flipped = false;
      _loading = false;
      _plan = plan;
    });
    await _loadCurrent();
  }

  String? _audioOf(WordCard card) => card.audio;

  static double _elapsed(FsrsState? prev) =>
      Fsrs.elapsedDaysSince(prev?.lastReview);

  double get _elapsedDays => _elapsed(_curSrs);

  Future<bool> _autoContinue() async {
    if (_plan.taskLeft <= 0) return false;
    _groupNo++;
    await _load();
    if (_queue.isEmpty) {
      _groupNo--;
      return false;
    }
    return true;
  }

  Future<void> _loadCurrent({bool resetFlip = true}) async {
    if (_queue.isEmpty || _index >= _queue.length) return;

    await _hydrate(_queue, _index, _cards);
    if (!mounted) return;
    final card = _cardAt(_index);
    if (card == null) return;
    final db = context.read<AppState>().db;

    final histF = db.cardHistory(card.id);
    final srs = await db.getSrs(card.id);
    final hist = await histF;
    if (!mounted) return;
    setState(() {
      _curSrs = srs;
      _histDays = hist.days;
      _histLogs = hist.logs;
      _histToday = hist.todayExtra;
      if (resetFlip) _flipped = false;
      _resetCardUi();
    });
    unawaited(AudioService.instance.prefetchCard(
        audio: _audioOf(card), parts: card.audioParts, word: card.word));
    final nextCard = _cardAt(_index + 1);
    if (nextCard != null) {
      unawaited(AudioService.instance.prefetchCard(
          audio: _audioOf(nextCard),
          parts: nextCard.audioParts,
          word: nextCard.word));
    }
  }

  Widget _planBar() {
    final rAll = _plan.reviewShown;
    final nAll = _plan.newPlan;
    final rDone = _plan.reviewDone < 0
        ? 0
        : (_plan.reviewDone > rAll ? rAll : _plan.reviewDone);
    final nDone =
        _plan.newDone < 0 ? 0 : (_plan.newDone > nAll ? nAll : _plan.newDone);
    final rest = (rAll - rDone) + (nAll - nDone);
    final track = context.k.bandTrack;
    Widget seg(int flex, Color c) =>
        Expanded(flex: flex < 1 ? 1 : flex, child: Container(color: c));
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Row(children: [
          if (rDone > 0) seg(rDone, context.k.brand),
          if (nDone > 0) seg(nDone, context.k.brand2b),
          if (rest > 0) seg(rest, track),
          if (rAll + nAll <= 0) seg(1, track),
        ]),
      ),
    );
  }

  Future<void> _rateWithFlash(int rating, int index) async {
    if (_previewMode || _flashing || _busy || _index >= _queue.length) return;
    _setState(() {
      _flashing = true;
      _flashIndex = index;
    });
    var completed = false;
    try {
      await _flashCtrl.forward(from: 0);
      completed = true;
    } on TickerCanceled {
      completed = false;
    } finally {
      if (mounted) {
        _setState(() {
          _flashing = false;
          _flashIndex = null;
          _flashCtrl.value = 0;
        });
      }
    }
    if (!mounted || !completed) return;
    await _rate(rating);
  }

  Future<void> _rate(int rating) async {
    if (_previewMode) return;
    if (_busy || _index >= _queue.length) return;
    final idx = _index;
    final card = _cardAt(idx);
    if (idx + 1 >= _queue.length || card == null) return _rateSlow(rating);
    final wasNew = _queue[idx].isNew;
    final app = context.read<AppState>();
    unawaited(HapticFeedback.selectionClick());
    _tapGuardUntil = DateTime.now().add(const Duration(milliseconds: 350));
    setState(() {
      _index = idx + 1;
      _flipped = false;
      _flashing = false;
      _flashIndex = null;
      _flashCtrl.value = 0;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    _writeChain = _writeChain
        .then((_) => _persistRating(app, card, idx, rating, wasNew))
        .catchError((Object e, StackTrace s) {
      debugPrint('评分写库失败 ${card.id}: $e');
    });
    unawaited(_loadCurrent(resetFlip: false));
  }

  Future<FsrsState> _applyLoadBalance(AppState app, FsrsState next) async {
    if (!app.loadBalance || next.state != FsrsState.review) return next;
    final base = next.lastReview ?? DateTime.now();
    final rawDays = next.due.difference(base).inDays;
    if (rawDays < 4) return next;
    final delta = math.max(1, (rawDays * 0.05).round()).clamp(1, 7);
    final counts = await app.db.futureDueWindowCounts(
      minDayOffset: math.max(2, rawDays - delta),
      maxDayOffset: rawDays + delta,
    );
    final balanced = chooseBalancedDays(rawDays, counts);
    if (balanced == rawDays) return next;
    return FsrsState(
      stability: next.stability,
      difficulty: next.difficulty,
      due: next.due.add(Duration(days: balanced - rawDays)),
      reps: next.reps,
      lapses: next.lapses,
      state: next.state,
      lastReview: next.lastReview,
      step: next.step,
    );
  }

  Future<void> _persistRating(
      AppState app, WordCard card, int idx, int rating, bool wasNew) async {
    Fsrs.requestedRetention = app.retention;
    final prev = await app.db.getSrs(card.id);
    var next = Fsrs.apply(prev, rating, elapsedDays: _elapsed(prev));
    next = await _applyLoadBalance(app, next);
    final logF = app.db.logRating(card.id, rating);
    await app.db.saveSrs(card.id, next);
    final logId = await logF;
    final undo =
        _Undo(index: idx, cardId: card.id, prevSrs: prev, logId: logId);
    final willRequeue = StudyScreen.needsRequeue(next);
    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      if (willRequeue) {
        undo.insertedAt = math.min(_index + _relearnGap, _queue.length);
        _queue.insert(undo.insertedAt!, (id: card.id, isNew: wasNew));
      }
    });
    _undo.add(undo);
    app.bumpPlan();
  }

  Future<void> _rateSlow(int rating) async {
    if (_previewMode) return;
    if (_busy || _index >= _queue.length) return;

    _busy = true;
    // 等前一张卡的异步写库链落完，避免队尾或快速连点时读到未落库的旧状态。
    try {
      await _writeChain;
    } catch (_) {}
    if (!mounted || _index >= _queue.length) {
      _busy = false;
      return;
    }
    final sw = Stopwatch()..start();

    final app = context.read<AppState>();
    Fsrs.requestedRetention = app.retention;
    final idx = _index;
    final card = _cardAt(idx);
    if (card == null) {

      _busy = false;
      return;
    }

    final wasNew = _queue[idx].isNew;

    final prev = await app.db.getSrs(card.id);
    if (!mounted) return;
    if (_index != idx) {

      _busy = false;
      return;
    }

    var next = Fsrs.apply(prev, rating, elapsedDays: _elapsed(prev));
    next = await _applyLoadBalance(app, next);
    if (!mounted) return;

    final logF = app.db.logRating(card.id, rating);
    await app.db.saveSrs(card.id, next);
    final logId = await logF;
    final undo =
        _Undo(index: idx, cardId: card.id, prevSrs: prev, logId: logId);

    final willRequeue = StudyScreen.needsRequeue(next);

    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    perfLog('rate.db', sw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _plan = plan;
      _index++;

      _flipped = false;

      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (willRequeue) {

        undo.insertedAt = math.min(_index + _relearnGap, _queue.length);
        _queue.insert(undo.insertedAt!, (id: card.id, isNew: wasNew));
      }
    });
    _undo.add(undo);

    app.bumpPlan();
    if (_index < _queue.length) {
      await _loadCurrent();
      perfLog('rate.next', sw);
      return;
    }

    if (await _autoContinue()) return;

  }

  Future<void> _undoLast() async {
    if (_previewMode) return;
    if (_busy) return;
    _busy = true;
    await _writeChain;
    if (_undo.isEmpty || !mounted) {
      _busy = false;
      return;
    }
    final app = context.read<AppState>();
    final u = _undo.removeLast();
    await app.db.deleteLog(u.logId);
    if (u.prevSrs == null) {

      await app.db.deleteSrs(u.cardId);
    } else {
      await app.db.saveSrs(u.cardId, u.prevSrs!);
    }

    var removed = 0;
    final at = u.insertedAt;
    if (at != null && at < _queue.length && _queue[at].id == u.cardId) {
      removed = 1;
    }

    final plan = await app.db.todayPlan(dailyQuota: app.dailyQuota);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (removed == 1) _queue.removeAt(at!);
      _index = u.index;
      _plan = plan;
    });
    app.bumpPlan();
    await _loadCurrent();
  }

  void _autoPlayCard(WordCard card) {
    if (!context.read<AppState>().autoSpeak) return;

    unawaited(AudioService.instance.playCard(
        audio: _audioOf(card), parts: card.audioParts, word: card.word));
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || _previewMode) return false;
    if (!(widget.activeListenable?.value ?? true)) return false;
    if (_loading || _busy || _queue.isEmpty || _index >= _queue.length) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return false;
    }
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    final app = _app;
    final card = _cardAt(_index);
    if (app == null || card == null) return false;
    if (_spellingOf(app, card) && !_flipped) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      if (!_flipped) {
        _flip();
        return true;
      }
      return false;
    }
    if (_flipped) {
      if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        unawaited(_rate(Fsrs.ratingForget));
        return true;
      }
      if (key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.numpad2) {
        unawaited(_rate(Fsrs.ratingFuzzy));
        return true;
      }
      if (key == LogicalKeyboardKey.digit3 ||
          key == LogicalKeyboardKey.numpad3) {
        unawaited(_rate(Fsrs.ratingKnow));
        return true;
      }
      if (key == LogicalKeyboardKey.digit4 ||
          key == LogicalKeyboardKey.numpad4) {
        unawaited(_rate(Fsrs.ratingEasy));
        return true;
      }
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(AudioService.instance.playCard(
        audio: _audioOf(card),
        parts: card.audioParts,
        word: card.word,
      ));
      return true;
    }
    if (key == LogicalKeyboardKey.keyZ && _undo.isNotEmpty) {
      unawaited(_undoLast());
      return true;
    }
    return false;
  }

  void _flip() {
    if (_busy) return;
    final to = !_flipped;
    if (to) _typeFocus.unfocus();
    setState(() {
      _flipped = to;

      if (!to) _renewBackKey();
    });
    final cur = _cardAt(_index);
    if (to && cur != null) _autoPlayCard(cur);
  }

  Future<void> _goDetail() async {
    final card = _cardAt(_index);
    if (card == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WordDetailScreen(cardId: card.id)),
    );

    await _reloadCard();
  }

  static String _dvsToText(List<Derivation> dv) => dv
      .map((d) => (d.gloss == null || d.gloss!.isEmpty)
          ? d.form
          : '${d.form} | ${d.gloss}')
      .join('\n');

  static List<Derivation> _textToDvs(String text) {
    final out = <Derivation>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf('|');
      if (i == -1) {
        out.add(Derivation(form: t));
      } else {
        final f = t.substring(0, i).trim();
        final g = t.substring(i + 1).trim();
        if (f.isNotEmpty) {
          out.add(Derivation(form: f, gloss: g.isEmpty ? null : g));
        }
      }
    }
    return out;
  }

  static String _examplesToText(List<WordExample> ex) => ex
      .map((e) =>
          (e.zh == null || e.zh!.isEmpty) ? e.text : '${e.text} | ${e.zh}')
      .join('\n');

  static List<WordExample> _textToExamples(String text) {
    final out = <WordExample>[];
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.indexOf('|');
      if (i == -1) {
        out.add(WordExample(text: t));
      } else {
        final id = t.substring(0, i).trim();
        final zh = t.substring(i + 1).trim();
        if (id.isNotEmpty) {
          out.add(WordExample(text: id, zh: zh.isEmpty ? null : zh));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_queue.isEmpty || _index >= _queue.length) {

      return _buildDone();
    }
    final app = context.watch<AppState>();
    final cardOrNull = _cardAt(_index);
    if (cardOrNull == null) {

      _hydrate(_queue, _index, _cards).then((_) {
        if (mounted) setState(() {});
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final card = cardOrNull;
    final item = (card: card, isNew: _queue[_index].isNew);
    final spelling = _spellingOf(app, card);

    final token = '$_groupNo:$_index:${card.id}';
    if (token != _backToken) {
      _backToken = token;
      _renewBackKey();

      _typeCorrect = null;
      if (_typeCtl.text.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _typeCtl.clear();
        });
      }
    }

    return Scaffold(
      backgroundColor: context.k.bg,

      body: DecoratedBox(

        key: const Key(kOpenStudyLayout ? 'study.pageGradient' : 'study.pageBg'),
        decoration: kOpenStudyLayout
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    context.k.bandGradTop,
                    context.k.bandGradBottom,
                    context.k.bg,
                  ],
                  stops: const [0, 0.28, 0.52],
                ),
              )
            : BoxDecoration(color: context.k.bg),
        child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _studyHeader(app, card, item, spelling: spelling),
            if (!_previewMode &&
                _overdueCount >= 30 &&
                !_postponeBannerDismissed)
              _buildOverdueBanner(app),
            Expanded(
              child: GestureDetector(

                onHorizontalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 280) _undoLast();
                },

                onTap: (_flipped || _typeCorrect == false) ? null : _flip,

                child: ValueListenableBuilder<bool>(
                  valueListenable: _backScrolled,
                  builder: (context, on, stack) => ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        on && _flipped ? Colors.transparent : Colors.white,
                        Colors.white,
                      ],
                      stops: [0, r.height <= 0 ? 1 : (14 / r.height).clamp(0.0, 1.0)],
                    ).createShader(r),
                    child: stack,
                  ),

                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    AnimatedSwitcher(

                      duration: const Duration(milliseconds: 180),
                      child: _flipped
                          ? KeyedSubtree(
                              key: _backKey,
                              child: _buildBack(card, isNew: item.isNew))
                          : _buildFront(card, spelling: spelling),
                    ),

                    if (!_flipped && _backPrebuilt)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Offstage(
                          child: KeyedSubtree(
                              key: _backKey,
                              child: _buildBack(card, isNew: item.isNew)),
                        ),
                      ),
                  ],
                ),
                ),
              ),
            ),
            if (!_previewMode &&
                (kIsWeb || MediaQuery.sizeOf(context).width >= 720))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '快捷键：Space 翻面 · 1-4 评分 · R 重听 · Z 撤销',
                  style: TextStyle(fontSize: 11, color: context.k.t3),
                ),
              ),
            if (!_previewMode)

              _controls(app, card, isNew: item.isNew, spelling: spelling),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildOverdueBanner(AppState app) {
    final k = context.k;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: k.tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.border),
      ),
      child: Row(
        children: [
          Icon(Icons.event_repeat_rounded, size: 16, color: k.deep),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '积压 $_overdueCount 张逾期复习，可温和顺延',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: k.deep),
            ),
          ),
          TextButton(
            onPressed: () async {
              final moved = await showPostponeSheet(
                context,
                app,
                overdueCount: _overdueCount,
              );
              if (moved != null && moved > 0 && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已将 $moved 张逾期复习卡温和顺延')),
                );
              }
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('去顺延'),
          ),
          InkWell(
            onTap: () => setState(() => _postponeBannerDismissed = true),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: k.t2),
            ),
          ),
        ],
      ),
    );
  }

  static String? questionTextOf(WordCard card) =>
      card.quizZh ?? questionZhOf(card.zhClean);

  static String? quizHeaderOf(WordCard card) {
    final q = questionTextOf(card);
    if (q == null) return null;
    final p = card.posCodePrefix;
    if (p == null || p.isEmpty || q.startsWith('$p.')) return q;
    return '$p. $q';
  }

  void _setState(VoidCallback fn) => setState(fn);
}

bool examplesUnchanged(List<WordExample> old, List<WordExample> cur) {
  if (old.length != cur.length) return false;
  for (var i = 0; i < cur.length; i++) {
    if (old[i].text != cur[i].text || old[i].zh != cur[i].zh) return false;
  }
  return true;
}

List<WordExample> mergeExamples(List<WordExample> old, List<WordExample> cur) {
  if (!examplesUnchanged(old, cur)) return cur;
  return [
    for (var i = 0; i < cur.length; i++)
      WordExample(
        text: cur[i].text,
        zh: cur[i].zh,
        src: old[i].src,
        quiz: old[i].quiz,
      )
  ];
}

bool dvsUnchanged(List<Derivation> old, List<Derivation> cur) {
  if (old.length != cur.length) return false;
  for (var i = 0; i < cur.length; i++) {
    if (old[i].form != cur[i].form || old[i].gloss != cur[i].gloss) {
      return false;
    }
  }
  return true;
}

List<Derivation> mergeDvs(List<Derivation> old, List<Derivation> cur) {
  if (!dvsUnchanged(old, cur)) return cur;
  return [
    for (var i = 0; i < cur.length; i++)
      Derivation(
        form: cur[i].form,
        gloss: cur[i].gloss,
        pos: old[i].pos,
        def: old[i].def,
      )
  ];
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? hint;

  final bool expandable;
  final bool expanded;
  final VoidCallback? onToggle;

  final VoidCallback? onEdit;
  const _SectionLabel(this.text,
      {this.hint,
      this.expandable = false,
      this.expanded = false,
      this.onToggle,
      this.onEdit});

  @override
  Widget build(BuildContext context) {
    final trailing = _trailing(context);

    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 7),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.k.sec)),
          ),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: context.k.faint)),
            ),
          ] else
            const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget? _trailing(BuildContext context) {

    final editBtn = onEdit != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              child: _PenIcon(size: 18, color: context.k.nFaint2),
            ),
          )
        : null;
    if (expandable) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(expanded ? '收起' : '展开',
                      style: TextStyle(
                          fontSize: 11,
                          color: kSpeakGreen,
                          fontWeight: FontWeight.w500)),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: kSpeakGreen),
                ],
              ),
            ),
          ),
          if (editBtn != null) editBtn,
        ],
      );
    }
    return editBtn;
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.k.nFaint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  final double size;
  final EdgeInsetsGeometry padding;

  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.size = 21,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _RateButton extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final String? hint;
  final bool enabled;
  final VoidCallback onTap;

  final Color? disabledBg;
  final Color? disabledFg;

  const _RateButton({
    required this.label,
    required this.color,
    required this.icon,
    this.hint,
    this.enabled = true,
    required this.onTap,
    this.disabledBg,
    this.disabledFg,
  });

  @override
  State<_RateButton> createState() => _RateButtonState();
}

class _RateButtonState extends State<_RateButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final color = widget.color;
    final icon = widget.icon;
    final hint = widget.hint;
    final enabled = widget.enabled;
    final onTap = widget.onTap;
    final disabledBg = widget.disabledBg;
    final disabledFg = widget.disabledFg;
    final c = enabled
        ? color
        : (disabledBg == null ? color.withValues(alpha: 0.38) : color);

    final dark = Theme.of(context).brightness == Brightness.dark;
    final disabledLook = !enabled && disabledBg != null;
    final hsl = HSLColor.fromColor(color);
    final ink = (!enabled && disabledFg != null)
        ? disabledFg
        : hsl.withLightness(dark ? 0.82 : 0.30).toColor();
    return Expanded(
      child: GestureDetector(

        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,

        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: (_) {
          if (_down) setState(() => _down = false);
        },
        onTapCancel: () {
          if (_down) setState(() => _down = false);
        },
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 70),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(

              color: disabledLook
                  ? disabledBg

                  : color.withValues(
                      alpha:
                          _down ? (dark ? 0.50 : 0.42) : (dark ? 0.30 : 0.24)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: disabledLook
                      ? disabledBg
                      : color.withValues(alpha: enabled ? 1.0 : 0.3),
                  width: 1.6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: disabledLook ? ink : c, size: 18),
                    const SizedBox(width: 5),
                    Text(label,
                        style: TextStyle(
                            color: ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                if (hint != null)
                  Text(hint,
                      style: TextStyle(
                          color: ink.withValues(alpha: 0.72), fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _RateBarButton extends StatefulWidget {
  final String label;
  final Color color;
  final String? hint;
  final bool enabled;
  final bool dim;
  final bool primary;
  final VoidCallback onTap;

  const _RateBarButton({
    required this.label,
    required this.color,
    this.hint,
    this.enabled = true,
    this.dim = false,
    this.primary = false,
    required this.onTap,
  });

  @override
  State<_RateBarButton> createState() => _RateBarButtonState();
}

class _RateBarButtonState extends State<_RateBarButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.enabled;
    final color = widget.color;

    final bg = !enabled
        ? k.ring.withValues(alpha: 0.6)
        : (_down ? color.withValues(alpha: 0.16) : Colors.transparent);

    final ink = enabled
        ? HSLColor.fromColor(color).withLightness(dark ? 0.82 : 0.30).toColor()
        : k.faint;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onTap : null,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: (_) {
          if (_down) setState(() => _down = false);
        },
        onTapCancel: () {
          if (_down) setState(() => _down = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          height: 52,
          alignment: Alignment.center,
          color: bg,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 80),
            opacity: widget.dim ? 0.32 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label,
                    style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight:
                            widget.primary ? FontWeight.w800 : FontWeight.w600)),
                if (widget.hint != null)
                  Text(widget.hint!,
                      style: TextStyle(
                          color: enabled ? ink.withValues(alpha: 0.72) : k.faint,
                          fontSize: 10.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClozeText extends StatelessWidget {
  final ClozeQuestion question;
  final bool showAnswer;
  static const double fontSize = 16;
  const _ClozeText(
      {super.key, required this.question, required this.showAnswer});

  @override
  Widget build(BuildContext context) {
    final t = question.text;
    final base =
        TextStyle(fontSize: fontSize, height: 1.6, color: context.k.nInk2);
    if (showAnswer) {
      return Text.rich(TextSpan(style: base, children: [
        TextSpan(text: question.span.before(t)),
        TextSpan(
            text: question.answer,
            style: TextStyle(
                color: kSpeakGreen,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: kSpeakGreen,
                decorationThickness: 2)),
        TextSpan(text: question.span.after(t)),
      ]));
    }

    final w = (question.answer.length * fontSize * 0.52).clamp(26.0, 160.0);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: question.span.before(t)),
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          width: w,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: kRatingForget,
        ),
      ),
      TextSpan(text: question.span.after(t)),
    ]));
  }
}
