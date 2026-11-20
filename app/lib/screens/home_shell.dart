library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:provider/provider.dart';

import '../ai_tools.dart' show AiHomeTabs;
import '../app_state.dart';
import '../platform/io_shim.dart' show Platform;
import '../theme/k_colors.dart';
import '../widgets/first_notice.dart';
import '../widgets/web_audio_pill.dart';
import 'study_screen.dart';
import 'grammar/grammar_hub_screen.dart';
import 'select_screen.dart';
import 'stats_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _studyTick = ValueNotifier<int>(0);
  final _libraryTick = ValueNotifier<int>(0);

  final _statsTick = ValueNotifier<int>(0);
  final _profileTick = ValueNotifier<int>(0);
  late final List<Widget> _pages = [
    StudyScreen(focusTick: _studyTick),
    SelectScreen(focusTick: _libraryTick, onGoStudy: _goStudyTab),

    const GrammarHubScreen(),
    StatsScreen(focusTick: _statsTick),
    ProfileScreen(focusTick: _profileTick),
  ];

  void _goStudyTab() {
    if (_tab != 0) setState(() => _tab = 0);
    _studyTick.value++;
  }

  DateTime? _lastBackAt;

  void _onBack() {
    if (_tab != 0) {
      _selectTab(0);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    _showExitHint();
  }

  void _showExitHint() {
    final k = context.k;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 1600),
      behavior: SnackBarBehavior.floating,
      backgroundColor: k.surface,
      elevation: 6,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: k.border, width: 1),
      ),
      content: Row(
        children: [
          Icon(Icons.keyboard_return, size: 17, color: k.deep),
          const SizedBox(width: 8),
          Text('再按一次退出',
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: k.text)),
        ],
      ),
    ));
  }

  int _badge = 0;

  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();

    AiHomeTabs.select = _selectTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTaskBadge();
      _maybeShowNotice();
    });
    _landNewUserOnLibrary();

    _app.addListener(_onAppChanged);
  }

  Future<void> _landNewUserOnLibrary() async {
    final has = await _app.db.hasEnrolledCards();
    if (!has && mounted && _tab == 0) _selectTab(1);
  }

  Future<void> _maybeShowNotice() async {
    if (_app.noticeSeen || Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (!mounted) return;
    await showFirstNotice(context);
    await _app.markNoticeSeen();
  }

  void _onAppChanged() {
    if (!mounted) return;

    if (_app.queueRevision != _lastRev || _app.planRevision != _lastPlanRev) {
      _lastRev = _app.queueRevision;
      _lastPlanRev = _app.planRevision;
      _refreshTaskBadge();
    }
  }

  int _lastRev = -1;
  int _lastPlanRev = -1;

  Future<void> _refreshTaskBadge() async {
    final plan = await _app.db.todayPlan(dailyQuota: _app.dailyQuota);
    final n = plan.taskLeft;
    if (!mounted || n == _badge) return;
    setState(() => _badge = n);
  }

  @override
  void dispose() {
    if (AiHomeTabs.select == _selectTab) AiHomeTabs.select = null;
    _app.removeListener(_onAppChanged);
    _studyTick.dispose();
    _libraryTick.dispose();
    _statsTick.dispose();
    _profileTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: HomeTabs(
        select: _selectTab,
        child: Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: _tab, children: _pages),
              const Positioned.fill(child: WebAudioPackPill()),
            ],
          ),
          bottomNavigationBar: _FlatNavBar(
            index: _tab,
            taskBadge: _badge,
            items: const [
              (icon: Icons.school_outlined, active: Icons.school, label: '学习'),
              (
                icon: Icons.menu_book_outlined,
                active: Icons.menu_book,
                label: '词库'
              ),

              (
                icon: Icons.account_tree_outlined,
                active: Icons.account_tree,
                label: '语法'
              ),
              (
                icon: Icons.insights_outlined,
                active: Icons.insights,
                label: '统计'
              ),
              (icon: Icons.person_outline, active: Icons.person, label: '我的'),
            ],
            onTap: _selectTab,
          ),
        ),
      ),
    );
  }

  void _selectTab(int i) {
    if (i != _tab) {

      if (i == 0) {
        _studyTick.value++;
        _refreshTaskBadge();
      }
      if (i == 1) _libraryTick.value++;
      if (i == 3) _statsTick.value++;
      if (i == 4) _profileTick.value++;
    }
    setState(() => _tab = i);
  }
}

class HomeTabs extends InheritedWidget {
  const HomeTabs({super.key, required this.select, required super.child});

  final void Function(int) select;

  static HomeTabs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomeTabs>();

  @override
  bool updateShouldNotify(HomeTabs oldWidget) => select != oldWidget.select;
}

class _FlatNavBar extends StatelessWidget {
  final int index;
  final void Function(int) onTap;
  final List<({IconData icon, IconData active, String label})> items;

  final int taskBadge;

  const _FlatNavBar({
    required this.index,
    required this.items,
    required this.onTap,
    this.taskBadge = 0,
  });

  @override
  Widget build(BuildContext context) {

    final active = context.k.brand;
    final inactive = context.k.nFaint2;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: context.k.surface,

        border: Border(top: BorderSide(color: context.k.g200)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(i == index ? items[i].active : items[i].icon,
                              size: 23, color: i == index ? active : inactive),
                          if (i == 0 && taskBadge > 0)
                            Positioned(
                              top: -6,
                              left: 12,
                              child: _Badge(count: taskBadge),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(items[i].label,
                          style: TextStyle(
                              fontSize: 10.5,
                              height: 1.1,
                              fontWeight: i == index
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == index ? active : inactive)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(

      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.k.badge,
        borderRadius: BorderRadius.circular(9),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Text(count > 999 ? '999+' : '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 10.5,
              height: 1.25,
              color: context.k.onbrand,
              fontWeight: FontWeight.w600)),
    );
  }
}
