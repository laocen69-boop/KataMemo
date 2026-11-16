library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/memory_ring.dart';
import '../widgets/speak_button.dart';
import 'word_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<WordCard> _words = [];
  Map<String, ({int state, double stability, int reps, int lapses})> _levels =
      {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final ws = await app.db.favorites();
    final lv = await app.db.srsLevels([for (final w in ws) w.id]);
    if (!mounted) return;
    setState(() {
      _words = ws;
      _levels = lv;
      _loading = false;
    });
  }

  MemoryStrength _strength(String id) {
    final s = _levels[id];
    if (s == null) return MemoryStrength.unknown;
    return MemoryStrength.of(stability: s.stability, reps: s.reps);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('收藏（${_words.length}）')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _words.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      '还没有收藏的单词。\n在单词详情页点右上角的星标即可收藏。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: context.k.nT2),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _words.length,
                  itemBuilder: (ctx, i) {
                    final w = _words[i];
                    final lv = _strength(w.id);
                    return ListTile(
                      leading: MemoryRing(
                        strength: lv,
                        size: 38,
                        child: Text(
                          w.word.isEmpty ? '?' : w.word[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: 14,
                              color: kSpeakGreen,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(w.word,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(lv.shortLabel,
                                maxLines: 1,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: memoryBandColor(context, lv.band))),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          if (w.zhClean != null) w.zhClean!,

                          if (w.wordClassLabelsCombined.isNotEmpty)
                            w.wordClassLabelsCombined,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SpeakButton(card: w, iconSize: 22),

                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => WordDetailScreen(cardId: w.id)),
                      ).then((_) => _load()),
                    );
                  },
                ),
    );
  }
}
