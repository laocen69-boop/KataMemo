library;

import 'package:flutter/material.dart';

import '../../grammar/grammar_models.dart';
import '../../theme/k_colors.dart';

class TreeBlockView extends StatefulWidget {
  const TreeBlockView({super.key, required this.block});

  final GTreeBlock block;

  @override
  State<TreeBlockView> createState() => _TreeBlockViewState();
}

class _TreeBlockViewState extends State<TreeBlockView> {

  final List<int> _path = [];

  GTreeOpt? get _picked =>
      _path.isEmpty ? null : widget.block.opts[_path.last];

  void _pick(int i) => setState(() => _path.add(i));

  void _backTo(int depth) =>
      setState(() => _path.removeRange(depth, _path.length));

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: context.k.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.k.nEdge, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 7),
                child: Icon(Icons.account_tree_outlined,
                    size: 16, color: context.k.deep),
              ),
              Expanded(
                child: Text(b.q,
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: context.k.text)),
              ),
            ],
          ),
          if (_path.isEmpty)

            for (var i = 0; i < b.opts.length; i++) _option(context, i)
          else ...[
            const SizedBox(height: 9),
            _crumbs(context),
            const SizedBox(height: 8),
            _result(context, _picked!.result),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _backTo(0),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('重选',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.k.deep)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _option(BuildContext context, int i) {
    final o = widget.block.opts[i];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _pick(i),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
          decoration: BoxDecoration(
            color: context.k.alt,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.label,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: context.k.text)),
              if (o.hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(o.hint,
                      style: TextStyle(
                          fontSize: 11.5, height: 1.4, color: context.k.t2)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _crumbs(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _crumb(context, '开始', 0),
          for (var i = 0; i < _path.length; i++)
            _crumb(context, widget.block.opts[_path[i]].label, i + 1),
        ],
      );

  Widget _crumb(BuildContext context, String text, int depth) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _backTo(depth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: context.k.alt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 11, color: context.k.t2)),
        ),
      );

  Widget _result(BuildContext context, GTreeOptResult r) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
        decoration: BoxDecoration(
          color: context.k.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.answer,
                style: TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: context.k.deep)),
            if (r.rule.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(r.rule,
                    style: TextStyle(
                        fontSize: 12.5, height: 1.5, color: context.k.t2)),
              ),
            if (r.examples.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in r.examples)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(e,
                            style: TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: context.k.text)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
}