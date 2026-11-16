library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../activity_log.dart' show logGrammarWrong;
import '../../app_state.dart';
import '../../grammar/grammar_models.dart';
import '../../theme/k_colors.dart';

class DrillRunnerScreen extends StatefulWidget {
  const DrillRunnerScreen({super.key, required this.drills, this.title = '练习'});

  final List<GQuiz> drills;

  final String title;

  @override
  State<DrillRunnerScreen> createState() => _DrillRunnerScreenState();
}

class _DrillRunnerScreenState extends State<DrillRunnerScreen>
    with SingleTickerProviderStateMixin {
  int _i = 0;

  int? _picked;

  int _right = 0;
  bool _finished = false;

  late final AnimationController _shakeCtl;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 6.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtl);
  }

  @override
  void dispose() {
    _shakeCtl.dispose();
    super.dispose();
  }

  GQuiz get _drill => widget.drills[_i];

  bool get _supported => _drill.opts.isNotEmpty;

  Future<void> _answer(int j) async {
    if (_picked != null) return;
    final d = _drill;
    final ok = j == d.ans;
    setState(() {
      _picked = j;
      if (ok) _right++;
    });

    if (!ok && mounted && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_shakeCtl.forward(from: 0));
    }

    final db = context.read<AppState>().db;
    await db.recordGrammarDrill(d.page, ok);

    if (!ok) {
      unawaited(logGrammarWrong(db,
          quizId: d.id,
          page: d.page,
          question: d.q,
          options: d.opts,
          picked: j,
          answer: d.ans,
          why: d.why));
    }
  }

  void _next() {
    if (_i >= widget.drills.length - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _i++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.drills.isEmpty) {

      return Scaffold(
        backgroundColor: context.k.bg,
        appBar: AppBar(backgroundColor: context.k.bg, elevation: 0),
        body: Center(
            child: Text('这组还没有题目',
                style: TextStyle(fontSize: 13, color: context.k.nT3))),
      );
    }
    final n = widget.drills.length;
    return Scaffold(
      backgroundColor: context.k.bg,
      appBar: AppBar(
        backgroundColor: context.k.bg,
        elevation: 0,
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.k.text)),
        actions: [
          if (!_finished)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text('${_i + 1} / $n',
                    style: TextStyle(fontSize: 12, color: context.k.nT3)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: _finished ? _summary(context) : _question(context),
      ),
    );
  }

  List<Widget> _question(BuildContext context) {
    final d = _drill;
    return [
      _progressBar(context),
      const SizedBox(height: 14),
      if (!_supported) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: BoxDecoration(
            color: context.k.gWarnBg,
            borderRadius: BorderRadius.circular(10),
            border: Border(
                left: BorderSide(color: context.k.gWarn, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('此题型暂未支持',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.k.gWarn)),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('这道题的数据不完整，先跳过。',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: context.k.t2)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: _next,
            child: Text('跳过',
                style: TextStyle(fontSize: 13, color: context.k.deep)),
          ),
        ),
      ] else ...[
        Text(d.q,
            style: TextStyle(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: context.k.text)),
        const SizedBox(height: 14),
        for (var j = 0; j < d.opts.length; j++) _option(context, d, j),
        if (_picked != null) ...[
          const SizedBox(height: 14),
          _whyCard(context, d),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _next,
              style: FilledButton.styleFrom(
                  backgroundColor: context.k.brand,
                  foregroundColor: context.k.onbrand),
              child: Text(_i >= widget.drills.length - 1 ? '完成' : '下一题',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    ];
  }

  Widget _progressBar(BuildContext context) => Row(
        children: [
          for (var j = 0; j < widget.drills.length; j++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: j == widget.drills.length - 1 ? 0 : 3),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: j <= _i ? context.k.brand : context.k.ring,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _option(BuildContext context, GQuiz d, int j) {
    final answered = _picked != null;
    final isAnswer = j == d.ans;
    final isPicked = j == _picked;

    final Color edge = !answered
        ? context.k.nEdge
        : isAnswer
            ? context.k.brand
            : isPicked
                ? context.k.danger
                : context.k.nEdge;
    final Color bg = answered && isAnswer ? context.k.tint : context.k.surface;
    final Color fg = !answered
        ? context.k.text
        : isAnswer
            ? context.k.deep
            : isPicked
                ? context.k.danger
                : context.k.t2;
    final tile = AnimatedContainer(
      key: ValueKey('drill-opt-$j'),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: edge, width: answered && (isAnswer || isPicked) ? 1.2 : 0.5),
      ),
      child: Text(d.opts[j],
          style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              fontWeight: isPicked || (answered && isAnswer)
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: fg)),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _answer(j),

      child: isPicked && answered && !isAnswer
          ? AnimatedBuilder(
              animation: _shake,
              builder: (_, child) =>
                  Transform.translate(offset: Offset(_shake.value, 0), child: child),
              child: tile,
            )
          : tile,
    );
  }

  Widget _whyCard(BuildContext context, GQuiz d) {
    final ok = _picked == d.ans;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: context.k.alt,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(color: ok ? context.k.brand : context.k.danger, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ok ? '答对了' : '再看一下',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ok ? context.k.deep : context.k.danger)),
          if (d.why.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(d.why,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.55, color: context.k.t2)),
            ),
        ],
      ),
    );
  }

  List<Widget> _summary(BuildContext context) => [
        const SizedBox(height: 30),
        Center(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline, size: 34, color: context.k.brand),
              const SizedBox(height: 10),
              Text('本组答完',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.k.text)),
              const SizedBox(height: 4),
              Text('答对 $_right / ${widget.drills.length} 题',
                  style: TextStyle(fontSize: 13, color: context.k.t2)),
              const SizedBox(height: 4),
              Text('练习不计入学习进度，也不占今日卡量',
                  style: TextStyle(fontSize: 11.5, color: context.k.nT3)),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                width: 180,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: FilledButton.styleFrom(
                      backgroundColor: context.k.brand,
                      foregroundColor: context.k.onbrand),
                  child: const Text('完成',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ];
}