part of 'select_screen.dart';

mixin _PagedScroll<T extends StatefulWidget> on State<T> {
  ScrollController get _pageScroll;
  bool get _pageHasMore;
  bool get _pageLoadingMore;
  Future<void> _pageLoadMore();

  double get _pageThreshold;

  bool get _scrollLoadBlocked => false;

  bool get _autoFillBlocked => false;

  bool _autoFill = true;

  bool _anchorJump = false;

  void _maybeLoadMore() {
    if (_anchorJump) return;
    _autoFill = true;
    if (_pageLoadingMore || !_pageHasMore || _scrollLoadBlocked) return;
    if (!_pageScroll.hasClients) return;
    final p = _pageScroll.position;
    if (p.pixels >= p.maxScrollExtent - _pageThreshold) _pageLoadMore();
  }

  void _scheduleFill() {
    if (_pageLoadingMore || !_pageHasMore) return;
    if (!_autoFill || _autoFillBlocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScroll.hasClients) return;
      if (!_autoFill || _autoFillBlocked) return;
      if (_pageScroll.position.maxScrollExtent <= 0) _pageLoadMore();
    });
  }
}
