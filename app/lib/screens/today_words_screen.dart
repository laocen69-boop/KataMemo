library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/word_search.dart';
import '../widgets/word_tile.dart';
import 'word_detail_screen.dart';

class TodayWordsScreen extends StatefulWidget {
  const TodayWordsScreen({
    super.key,
    required this.title,
    required this.rows,
    this.expected,
  });

  final String title;

  final List<WordCard> rows;

  final int? expected;

  @override
  State<TodayWordsScreen> createState() => _TodayWordsScreenState();
}

class _TodayWordsScreenState extends State<TodayWordsScreen> {
  SrsLevelMap _levels = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {

    final app = context.read<AppState>();
    final lv = await loadLevels(app.db, widget.rows);
    if (!mounted) return;
    setState(() {
      _levels = lv;
      _loading = false;
    });
  }

  String get _emptyText => switch (widget.title) {
        '待复习' => '今天没有到期的复习卡',
        '待新学' => '今天没有待学的新词了',
        _ => '今天要答的都答完了',
      };

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final expected = widget.expected;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            const SizedBox(width: 8),
            Text('${rows.length} 词',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: context.k.nFaint2)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_emptyText,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: context.k.nT2)),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length + (expected == rows.length ? 0 : 1),
                  itemBuilder: (ctx, i) {
                    if (i >= rows.length) {

                      final diff = rows.length - (expected ?? rows.length);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                        child: Text(
                          diff > 0
                              ? '今日计划只排了 $expected 张（今日卡量内）；'
                                  '其余 $diff 张是历史积压，会在每天的卡量里陆续排上'
                              : '今日计划 $expected 张，词表里只有 ${rows.length} 张'
                                  '（生词池已见底，或部分已提前学过）',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: context.k.nFaint2),
                        ),
                      );
                    }
                    final w = rows[i];
                    return WordTile(
                      card: w,

                      enrolled: true,
                      strength: strengthOf(_levels, w.id),
                      chevron: true,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => WordDetailScreen(cardId: w.id))),

                      onLongPress: () {},
                    );
                  },
                ),
    );
  }
}
