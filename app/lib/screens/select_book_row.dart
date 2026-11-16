part of 'select_screen.dart';

class _BookAvatar extends StatelessWidget {
  final String name;
  final bool hasChildren;
  final bool current;

  final bool newStyle;
  const _BookAvatar(
      {required this.name,
      this.hasChildren = false,
      this.current = false,
      this.newStyle = false});

  static const Color _folderColor = Color(0xFF8E8EE0);

  @override
  Widget build(BuildContext context) {
    if (hasChildren) {
      if (newStyle) {
        return Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.k.tint,
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.folder_outlined, size: 20, color: context.k.deep),
        );
      }
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _folderColor.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border:
              Border.all(color: _folderColor.withValues(alpha: 0.35), width: 1),
        ),
        child: const Icon(Icons.folder_outlined, size: 18, color: _folderColor),
      );
    }

    final ch = name.characters.isEmpty ? '?' : name.characters.first;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.k.nPale,
        shape: BoxShape.circle,
        border: current
            ? Border.all(color: kSpeakGreen, width: 1.6)
            : Border.all(color: context.k.g300, width: 1),
      ),
      child: Text(ch,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.k.g700)),
    );
  }
}

class BookRow extends StatelessWidget {
  final BookNode book;
  final bool isCurrent;
  final bool hasChildren;

  final BookProgress? progress;
  final VoidCallback onTap;

  final bool finished;

  final bool newStyle;

  const BookRow({
    super.key,
    required this.book,
    required this.onTap,
    this.isCurrent = false,
    this.hasChildren = false,
    this.progress,
    this.finished = false,
    this.newStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    if (newStyle) return _buildNew(context);
    final p = progress;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,

      color: isCurrent
          ? kSpeakGreen.withValues(alpha: 0.06)
          : (finished ? context.k.catTint2 : context.k.surface),

      shape: Border(bottom: BorderSide(color: context.k.g200, width: 0.8)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 9, 8, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BookAvatar(
                      name: book.name,
                      hasChildren: hasChildren,
                      current: isCurrent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(book.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15.5)),
                        ),

                        if (book.count > 0) ...[
                          const SizedBox(width: 5),
                          Text('（${book.count} 词）',
                              style: TextStyle(
                                  fontSize: 12.5, color: context.k.nFaint2)),
                        ],

                        if (finished) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: context.k.catTint,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('已学完',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: context.k.catMid,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (isCurrent && p != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 46, right: 6),
                  child: MemorySegmentBar(
                    counts: progressBarCounts(p.bands, p.all - p.total),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNew(BuildContext context) {
    final p = progress;
    final fg = isCurrent ? context.k.deep : context.k.t2;
    final ch = book.name.characters.isEmpty
        ? '?'
        : book.name.characters.first;
    final ratio =
        (p == null || p.all <= 0) ? 0.0 : (p.total / p.all).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    Widget leading;
    if (hasChildren) {
      leading = _BookAvatar(
          name: book.name, hasChildren: true, newStyle: true);
    } else if (finished) {
      leading = Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: context.k.brand, shape: BoxShape.circle),
        child: Icon(Icons.check, size: 18, color: context.k.onbrand),
      );
    } else {
      leading = SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BookRingPainter(
                    ratio,
                    isCurrent ? context.k.curTrack : context.k.ring,
                    context.k.brand),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: context.k.surface, shape: BoxShape.circle),
              child: Text(ch,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      );
    }

    Widget nameArea(double maxWidth) {
      final name = Text(book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15.5,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              color: isCurrent ? context.k.deep : context.k.text));
      if (finished) {
        return Row(children: [
          Flexible(child: name),
          const SizedBox(width: 6),
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.k.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('已学完',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: context.k.deep)),
          ),
        ]);
      }
      if (isCurrent) {
        return Row(children: [
          Flexible(child: name),
          const SizedBox(width: 8),
          Text('$pct%',
              style: TextStyle(fontSize: 10.5, color: context.k.t3)),
        ]);
      }
      return Align(alignment: Alignment.centerLeft, child: name);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        key: Key('book.row-${book.id}'),
        children: [

          if (isCurrent)
            Positioned.fill(
              child: ColoredBox(color: context.k.cur),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              SizedBox(
                height: 58,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 12),

                      Expanded(
                        child: LayoutBuilder(
                          builder: (_, c) => nameArea(c.maxWidth),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: book.count > 0
                            ? Text('${book.count}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isCurrent
                                        ? context.k.deep
                                        : context.k.t3,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ]))
                            : null,
                      ),
                      const SizedBox(width: 2),

                      if (hasChildren)
                        Icon(Icons.chevron_right, size: 18, color: context.k.t3)
                      else
                        const SizedBox(width: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (isCurrent)
            Positioned(
              left: 62,
              right: 16,
              bottom: 2,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        key: Key('book.track-${book.id}'),
                        color: context.k.curTrack,
                      ),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio,
                      heightFactor: 1,
                      child: ColoredBox(
                        key: Key('book.fill-${book.id}'),
                        color: context.k.brand,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BookCard extends StatelessWidget {
  final BookNode book;
  final BookProgress? progress;
  final bool isCurrent;
  final VoidCallback onTap;

  final bool highlight;

  final bool hasChildren;

  final int dailyQuota;

  final bool finished;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    this.progress,
    this.isCurrent = false,
    this.dailyQuota = 20,
    this.highlight = false,
    this.hasChildren = false,
    this.finished = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLeaf = book.clickable;
    final p = progress;

    return Card(
      margin: EdgeInsets.zero,

      color: finished ? context.k.catTint2 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isCurrent
            ? BorderSide(color: kSpeakGreen, width: 1.6)
            : highlight
                ? BorderSide(color: context.k.q4, width: 1.4)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  _BookAvatar(
                      name: book.name,
                      hasChildren: hasChildren,
                      current: isCurrent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(book.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15.5),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kSpeakGreen,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('学习目标',
                          style:
                              TextStyle(fontSize: 10.5, color: Colors.white)),
                    ),
                  Icon(Icons.chevron_right, size: 20, color: context.k.nFaint2),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  _subtitle(p, book, dailyQuota),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.k.nT2),
                ),
              ),
              if (isLeaf) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32, right: 6),

                  child: MemorySegmentBar(
                    counts: progressBarCounts(p?.bands ?? kEmptyBands,
                        (p?.all ?? 0) - (p?.total ?? 0)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(BookProgress? p, BookNode book, int quota) {
    if (p == null) {
      if (book.count > 0) return '${book.count} 词';
      return book.desc.isNotEmpty ? book.desc : '展开查看子类';
    }
    final parts = <String>['${p.all} 词'];
    if (p.total != p.all) parts.add('在记忆 ${p.total}');
    parts.add('已学 ${p.started}');
    if (p.due > 0) parts.add('待复习 ${p.due}');
    final days = estimateDays(p, quota);
    if (days != null) parts.add(days == 1 ? '按当前卡量约 1 天' : '按当前卡量约 $days 天');
    return parts.join(' · ');
  }

  static int? estimateDays(BookProgress p, int quota) {
    if (quota <= 0) return null;
    final remain = p.total - p.started;
    if (remain <= 0) return null;
    return (remain / quota).ceil();
  }
}
