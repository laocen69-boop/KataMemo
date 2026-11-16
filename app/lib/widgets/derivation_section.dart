library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../db.dart';
import '../models.dart';

class DerivationList extends StatefulWidget {
  final List<Derivation> derivations;

  final int? limit;

  final void Function(Derivation d)? onTapDerivation;

  const DerivationList({
    super.key,
    required this.derivations,
    this.limit,
    this.onTapDerivation,
  });

  @override
  State<DerivationList> createState() => _DerivationListState();
}

class _DerivationListState extends State<DerivationList> {

  Map<String, String> _fallback = const {};

  @override
  void initState() {
    super.initState();
    _loadFallback();
  }

  @override
  void didUpdateWidget(covariant DerivationList oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.derivations, widget.derivations)) {
      _fallback = const {};
      _loadFallback();
    }
  }

  Future<void> _loadFallback() async {
    final missing = [
      for (final d in widget.derivations)
        if ((d.gloss ?? '').trim().isEmpty && d.form.trim().isNotEmpty)
          AppDb.fold(d.form),
    ];
    if (missing.isEmpty) return;
    final map = await context.read<AppState>().db.derivationZhMap(missing);
    if (!mounted || map.isEmpty) return;
    setState(() => _fallback = map);
  }

  (String, bool) _zhOf(Derivation d) {
    final g = (d.gloss ?? '').trim();
    if (g.isNotEmpty) return (g, true);
    final fb = _fallback[AppDb.fold(d.form)];
    if (fb != null && fb.isNotEmpty) return (fb, true);
    return ((d.def ?? '').trim(), false);
  }

  Widget _formCell(Derivation d) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTapDerivation == null
          ? null
          : () => widget.onTapDerivation!(d),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 10, 4),

        child: Text(d.form,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _zhCell(Derivation d, Color grey) {
    final (zh, isZh) = _zhOf(d);
    return Text.rich(
      TextSpan(children: [
        if (d.pos != null && d.pos!.trim().isNotEmpty)
          TextSpan(
              text: '（${d.pos}）',
              style: TextStyle(fontSize: 11.5, color: grey)),
        TextSpan(
            text: zh.isEmpty ? '—' : zh,
            style: TextStyle(
                fontSize: 13.5, height: 1.45, color: isZh ? null : grey)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.limit == null
        ? widget.derivations
        : widget.derivations.take(widget.limit!);
    final grey = context.k.nT2;

    return LayoutBuilder(builder: (context, cx) {
      final avail = cx.maxWidth;
      final cap = avail.isFinite ? math.min(176.0, avail * 0.5) : 176.0;
      return Table(
        columnWidths: {
          0:
              MinColumnWidth(const IntrinsicColumnWidth(), FixedColumnWidth(cap)),
          1: const FlexColumnWidth(),
        },
        children: [
          for (final d in items)
            TableRow(children: [
              TableCell(child: _formCell(d)),
              TableCell(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _zhCell(d, grey),
                ),
              ),
            ]),
        ],
      );
    });
  }
}
