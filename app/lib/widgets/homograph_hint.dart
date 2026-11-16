library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/k_colors.dart';
import 'speak_button.dart' show kSpeakGreen;
import 'word_sheet.dart';

const String kAbbrSuffix = '-abbr';

String homographPartnerId(String cardId) => cardId.endsWith(kAbbrSuffix)
    ? cardId.substring(0, cardId.length - kAbbrSuffix.length)
    : '$cardId$kAbbrSuffix';

class HomographHint extends StatefulWidget {
  const HomographHint({
    super.key,
    required this.card,
    this.onOpenDetail,
    this.bare = false,
  });

  final WordCard card;
  final OpenWordDetail? onOpenDetail;

  final bool bare;

  @override
  State<HomographHint> createState() => _HomographHintState();
}

class _HomographHintState extends State<HomographHint> {
  WordCard? _other;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomographHint old) {
    super.didUpdateWidget(old);
    if (old.card.id != widget.card.id) _load();
  }

  Future<void> _load() async {
    final id = widget.card.id;
    _loadedFor = id;
    final other = await context.read<AppState>().db.getWord(homographPartnerId(id));
    if (!mounted || _loadedFor != id) return;
    setState(() => _other = other);
  }

  static String _short(String? zh) {
    final z = (zh ?? '').trim();
    if (z.isEmpty) return '';
    final first = z.split(RegExp(r'[；;]')).first.trim();
    return first.length > 22 ? '${first.substring(0, 22)}…' : first;
  }

  @override
  Widget build(BuildContext context) {
    final other = _other;

    if (other == null || other.id != homographPartnerId(widget.card.id)) {
      return const SizedBox.shrink();
    }
    final isAbbr = widget.card.id.endsWith(kAbbrSuffix);
    final label = isAbbr ? '同形词' : '缩写同形';
    final gloss = _short(other.zh);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showWordSheet(context, other.id, onOpenDetail: widget.onOpenDetail),
      child: Container(
        width: double.infinity,
        padding: widget.bare
            ? const EdgeInsets.symmetric(vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: widget.bare
            ? null
            : BoxDecoration(
                color: kSpeakGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
        child: Row(
          children: [
            Text('$label：',
                style: TextStyle(fontSize: 12.5, color: context.k.g700)),
            Flexible(
              child: Text(
                gloss.isEmpty ? other.word : '${other.word} = $gloss',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: kSpeakGreen),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 16, color: kSpeakGreen),
          ],
        ),
      ),
      ),
    );
  }
}
