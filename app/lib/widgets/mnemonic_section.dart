library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../platform/io_shim.dart';
import '../theme/k_colors.dart';
import '../app_state.dart';
import '../images.dart';
import '../models.dart';

class _MnemonicImage extends StatefulWidget {
  final String rel;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final int? cacheWidth;
  final Color? backgroundColor;
  final String missingText;
  final void Function(File file)? onTap;

  const _MnemonicImage({
    super.key,
    required this.rel,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 8,
    this.cacheWidth,
    this.backgroundColor,
    this.missingText = '图片已丢失',
    this.onTap,
  });

  @override
  State<_MnemonicImage> createState() => _MnemonicImageState();
}

class _MnemonicImageState extends State<_MnemonicImage> {
  File? _file;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _file = ImageStore.cached(widget.rel);
    _loading = _file == null;
    if (_file == null) _resolve();
  }

  @override
  void didUpdateWidget(covariant _MnemonicImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rel != widget.rel) {
      _file = ImageStore.cached(widget.rel);
      _loading = _file == null;
      if (_file == null) _resolve();
    }
  }

  Future<void> _resolve() async {
    final rel = widget.rel;
    final f = await ImageStore.resolve(rel);
    if (!mounted || widget.rel != rel) return;
    setState(() {
      _file = f;
      _loading = false;
    });
  }

  Widget _placeholder(BuildContext context) => Container(
        width: widget.width,
        height: widget.height,
        color:
            widget.backgroundColor ?? context.k.nFaint2.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Text(
          _loading ? '…' : widget.missingText,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.k.nT2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = _file;
    Widget child;
    if (f == null) {
      child = _placeholder(context);
    } else {
      child = Container(
        width: widget.width,
        height: widget.height,
        color: widget.backgroundColor,
        child: buildFileImage(
          f,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,

          cacheWidth: widget.cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(context),
        ),
      );
    }
    child = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: child,
    );
    if (widget.onTap != null && f != null) {
      final file = f;
      child = GestureDetector(
        onTap: () => widget.onTap!(file),
        child: child,
      );
    }
    return child;
  }
}

class MnemonicImagesRow extends StatelessWidget {
  final List<String> relPaths;

  final double height;

  const MnemonicImagesRow({
    super.key,
    required this.relPaths,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rel in relPaths) ...[
          _MnemonicImage(
            key: ValueKey(rel),
            rel: rel,
            width: double.infinity,
            height: height,
            fit: BoxFit.contain,
            radius: 10,
            cacheWidth: cacheWidth,
            backgroundColor: Colors.black.withValues(alpha: 0.03),
            missingText: '图片已丢失',
            onTap: (f) => showImageViewer(context, f, rel),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

void showImageViewer(BuildContext context, File file, String caption) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,

              child: Center(
                child: buildFileImage(file, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              tooltip: '关闭',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('双指缩放 / 点空白处关闭',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6))),
            ),
          ),
        ),
      ],
    ),
  );
}

class MnemonicImageEditor extends StatefulWidget {
  final WordCard card;
  final VoidCallback onChanged;

  final bool showHint;

  const MnemonicImageEditor({
    super.key,
    required this.card,
    required this.onChanged,
    this.showHint = true,
  });

  @override
  State<MnemonicImageEditor> createState() => _MnemonicImageEditorState();
}

class _MnemonicImageEditorState extends State<MnemonicImageEditor> {
  bool _busy = false;

  late List<String> _imgs;

  @override
  void initState() {
    super.initState();
    _imgs = List.of(widget.card.mnemonicImages);
  }

  @override
  void didUpdateWidget(covariant MnemonicImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.card.id != oldWidget.card.id ||
        !listEquals(
            widget.card.mnemonicImages, oldWidget.card.mnemonicImages)) {
      _imgs = List.of(widget.card.mnemonicImages);
    }
  }

  Future<void> _add(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ImageStore.pick(source: source);
    if (!mounted) return;
    if (r.error != null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(r.error!)));
      return;
    }
    if (r.rel == null) {
      setState(() => _busy = false);
      return;
    }
    final app = context.read<AppState>();
    final next = [..._imgs, r.rel!];
    await app.db.saveEdit(widget.card.id, 'mnemonic_images', next.join(','));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _imgs = next;
    });
    widget.onChanged();
  }

  Future<void> _remove(String rel) async {
    if (_busy) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final next = _imgs.where((x) => x != rel).toList();
    await app.db.saveEdit(widget.card.id, 'mnemonic_images',
        next.isEmpty ? null : next.join(','));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _imgs = next;
    });
    widget.onChanged();

    unawaited(Future<void>.delayed(
        const Duration(milliseconds: 1200), () => ImageStore.delete(rel)));
  }

  @override
  Widget build(BuildContext context) {
    final imgs = _imgs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imgs.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final rel in imgs) _thumb(rel)],
          ),
        if (imgs.isNotEmpty) const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('从相册加图', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: const Text('拍照', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (widget.showHint) ...[
          const SizedBox(height: 4),
          Text('图片存在本机（不进词库文件），换词库重导不会丢',
              style: TextStyle(fontSize: 11, color: context.k.nFaint2)),
        ],
      ],
    );
  }

  Widget _thumb(String rel) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return KeyedSubtree(
      key: ValueKey(rel),
      child: Stack(
        children: [

          _MnemonicImage(
            rel: rel,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            radius: 8,
            cacheWidth: (92 * dpr).round(),
            backgroundColor: context.k.nFaint2.withValues(alpha: 0.12),
            missingText: '图片已丢失',
            onTap: (f) => showImageViewer(context, f, rel),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: _busy ? null : () => _remove(rel),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MnemonicSection extends StatefulWidget {
  final WordCard card;
  final VoidCallback onChanged;

  const MnemonicSection({
    super.key,
    required this.card,
    required this.onChanged,
  });

  @override
  State<MnemonicSection> createState() => _MnemonicSectionState();
}

class _MnemonicSectionState extends State<MnemonicSection> {
  @override
  Widget build(BuildContext context) {

    final mn = widget.card.mnemonicShown;
    final isDefault = widget.card.showsDefaultMnemonic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mn != null && mn.isNotEmpty) ...[

          if (isDefault || widget.card.mnemonicDefault != null)
            Row(
              children: [
                Text(
                    isDefault
                        ? '助记 · ${widget.card.mnemonicDefaultKind}（可改）'
                        : '我的助记',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: isDefault ? context.k.nT2 : context.k.g700)),
                const Spacer(),
                if (isDefault == false && widget.card.mnemonicDefault != null)
                  GestureDetector(
                    onTap: () async {

                      await context
                          .read<AppState>()
                          .db
                          .saveMnemonic(widget.card.id, '');
                      widget.onChanged();
                    },
                    child: Text('恢复默认',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(mn, style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
        ],
        MnemonicImageEditor(
          card: widget.card,
          onChanged: widget.onChanged,
        ),
      ],
    );
  }
}
