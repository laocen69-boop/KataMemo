library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'grammar_models.dart';

const String kGrammarAssetPath = 'assets/data/grammar.json';
const String kWritingAssetPath = 'assets/data/writing.json';

class GSearchHit {
  const GSearchHit(this.page, this.why, this.score);
  final GPage page;
  final String why;
  final int score;
}

class GrammarRepo extends ChangeNotifier {
  GrammarRepo({this.assetPath = kGrammarAssetPath, this.autoLoad = true});

  final String assetPath;

  final bool autoLoad;

  GDoc? _doc;
  Object? error;
  bool _loading = false;

  bool get ready => _doc != null;
  bool get loading => _loading;
  GDoc get doc => _doc ?? const GDoc();

  final Map<String, GPage> pageById = {};
  final Map<String, GSection> sectionById = {};
  final Map<String, List<GQuiz>> quizByPage = {};
  final Map<String, List<GPage>> _pagesByWord = {};

  Future<void> ensureLoaded() async {
    if (ready || _loading || !autoLoad) return;
    _loading = true;
    error = null;
    notifyListeners();
    try {
      final raw = await rootBundle.loadString(assetPath, cache: false);
      _index(GDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (e) {
      error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    error = null;
    await ensureLoaded();
  }

  void loadFromJson(String raw) {
    _index(GDoc.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    error = null;
    notifyListeners();
  }

  void _index(GDoc d) {
    _doc = d;
    _bodyCache.clear();
    pageById
      ..clear()
      ..addEntries(d.pages.map((p) => MapEntry(p.id, p)));
    sectionById
      ..clear()
      ..addEntries(d.sections.map((s) => MapEntry(s.id, s)));
    quizByPage.clear();
    for (final q in d.quiz) {
      quizByPage.putIfAbsent(q.page, () => []).add(q);
    }
    _pagesByWord.clear();
    for (final p in d.pages) {
      for (final w in p.words) {
        _pagesByWord.putIfAbsent(w, () => []).add(p);
      }
    }
  }

  List<GPage> pagesForWord(String wordId) => _pagesByWord[wordId] ?? const [];

  List<GPage> pagesOf(Iterable<String> ids) =>
      [for (final id in ids) if (pageById[id] != null) pageById[id]!];

  List<GSearchHit> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || !ready) return const [];
    final out = <GSearchHit>[];
    for (final p in doc.pages) {
      final title = p.title.toLowerCase();
      int score = 0;
      String why = '';
      if (title == q) {
        score = 100;
      } else if (title.startsWith(q)) {
        score = 80;
      } else if (title.contains(q) || p.titleId.toLowerCase().contains(q)) {
        score = 70;
      } else if (p.aliases.any((a) => a.toLowerCase() == q)) {
        score = 65;
        why = '别名';
      } else if (p.aliases.any((a) => a.toLowerCase().contains(q))) {
        score = 55;
        why = '别名';
      } else if (p.summary.toLowerCase().contains(q)) {
        score = 45;
        why = '摘要';
      } else {
        final h = p.headings.firstWhere((x) => x.toLowerCase().contains(q),
            orElse: () => '');
        if (h.isNotEmpty) {
          score = 35;
          why = '小节「$h」';
        } else if (_bodyText(p).contains(q)) {
          score = 20;
          why = '正文';
        }
      }
      if (score > 0) out.add(GSearchHit(p, why, score));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  final Map<String, String> _bodyCache = {};

  String _bodyText(GPage p) => _bodyCache.putIfAbsent(p.id, () {
        final sb = StringBuffer();
        for (final x in p.blocks) {
          switch (x) {
            case GLeadBlock(:final text) || GTextBlock(:final text):
              sb.writeln(text);
            case GStepsBlock(:final items) || GPitBlock(:final items):
              items.forEach(sb.writeln);
            case GTableBlock(:final cols, :final rows):
              sb.writeln(cols.join(' '));
              for (final r in rows) {
                sb.writeln(r.join(' '));
              }
            case GExBlock(:final items):
              for (final e in items) {
                sb.writeln('${e.plain} ${e.z}');
              }
            case GVsBlock(:final a, :final b):
              for (final s in [a, b]) {
                sb.writeln('${s.title} ${s.text}');
                for (final e in s.ex) {
                  sb.writeln('${e.plain} ${e.z}');
                }
              }
            case GWordsBlock(:final list):
              sb.writeln(list.join(' '));
            default:
          }
        }
        return sb.toString().toLowerCase();
      });
}
