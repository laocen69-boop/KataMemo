library;

import 'package:flutter/material.dart';

import '../../grammar/grammar_models.dart';
import '../../theme/k_colors.dart';

class GTable extends StatelessWidget {
  const GTable({super.key, required this.block});

  final GTableBlock block;

  @override
  Widget build(BuildContext context) {
    if (block.cols.isEmpty) return const SizedBox.shrink();
    final n = block.cols.length;

    final rows = <List<String>>[
      block.cols,
      for (final r in block.rows)
        [for (var i = 0; i < n; i++) i < r.length ? r[i] : ''],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (block.wide)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swipe_left, size: 13, color: context.k.nT3),
                const SizedBox(width: 4),
                Text('可横滑',
                    style: TextStyle(fontSize: 10.5, color: context.k.nT3)),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: context.k.nEdge, width: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(

              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                0: const FixedColumnWidth(96),
                for (var i = 1; i < n; i++) i: const FixedColumnWidth(132),
              },
              border: TableBorder(
                horizontalInside:
                    BorderSide(color: context.k.nEdge, width: 0.5),
              ),
              children: [
                for (var ri = 0; ri < rows.length; ri++)
                  TableRow(
                    children: [
                      for (var ci = 0; ci < n; ci++)
                        _cell(context, rows[ri][ci],
                            header: ri == 0, firstCol: ci == 0),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, String text,
      {required bool header, required bool firstCol}) {

    final lines = text.split(kGTableCellSep);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: header ? context.k.alt : null,

        border: firstCol
            ? Border(right: BorderSide(color: context.k.nEdge, width: 0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: EdgeInsets.only(bottom: l == lines.last ? 0 : 3),
              child: Text(l,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                      color: header ? context.k.text : context.k.t2)),
            ),
        ],
      ),
    );
  }
}
