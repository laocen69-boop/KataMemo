library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, PlatformException;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../theme/k_colors.dart';
import '../app_state.dart';
import '../audio.dart';
import '../audio_picker.dart';
import '../db.dart';
import '../export_dir.dart';
import '../models.dart';
import '../widgets/speak_button.dart' show kSpeakGreen;
import '../widgets/swipe_reveal_row.dart';
import '../widgets/word_list_actions.dart';
import '../widgets/word_search.dart';
import '../widgets/word_tile.dart';
import 'select_screen.dart';
import 'study_screen.dart';
import 'word_detail_screen.dart';

part 'my_words_lists_tab.dart';
part 'my_words_tab.dart';
part 'user_word_form.dart';

const List<(String?, String)> kUserWordClasses = [
  (null, '不标词性'),
  ('n', '名词'),
  ('v', '动词'),
  ('a', '形容词'),
  ('adv', '副词'),
  ('num', '数词'),
  ('pron', '代词'),
  ('prep', '介词'),
  ('conj', '连词'),
  ('part', '语气词'),
  ('interj', '感叹词'),
];

class UserWordDraft {
  final String id;
  final String word;
  final String zh;
  final String? wordClass;
  final List<({String i, String? z})> examples;
  final String? mnemonic;
  final String? audio;

  const UserWordDraft({
    this.id = '',
    this.word = '',
    this.zh = '',
    this.wordClass,
    this.examples = const [],
    this.mnemonic,
    this.audio,
  });

  bool get isEdit => id.isNotEmpty;
}

class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  int? _nWords;
  int? _nLists;

  @override
  void initState() {
    super.initState();
    _recount();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _recount() async {
    final app = context.read<AppState>();
    final w = await app.db.countUserWords();
    final ls = await app.db.listWordLists();
    if (!mounted) return;
    setState(() {
      _nWords = w;
      _nLists = ls.length;
    });
  }

  Widget _tabLabel(String text, int? n) => Tab(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text),
            if (n != null) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5.5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: context.k.catTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.k.catDeep)),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: const Text('自建卡片'),
        bottom: TabBar(
          controller: _tab,

          labelColor: context.k.deep,
          unselectedLabelColor: context.k.nT2,
          indicatorColor: kSpeakGreen,
          labelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: [
            _tabLabel('自建词', _nWords),
            _tabLabel('词单', _nLists),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          MyWordsTab(onChanged: _recount),
          WordListsTab(onChanged: _recount),
        ],
      ),
    );
  }
}

class MyWordsTab extends StatefulWidget {

  final VoidCallback? onChanged;

  const MyWordsTab({super.key, this.onChanged});

  @override
  State<MyWordsTab> createState() => _MyWordsTabState();
}
