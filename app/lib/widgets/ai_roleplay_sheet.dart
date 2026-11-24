/// 情景角色扮演选择弹层（BIPA A1–B2 筛选 + 错词/推荐词切换 + 无黑框卡片设计）。
library;

import 'package:flutter/material.dart';

import '../ai_roleplay.dart';
import '../app_state.dart';
import '../theme/k_colors.dart';

class AiRoleplaySelection {
  final AiRoleplayScenario scenario;
  final List<String> targetWords;

  const AiRoleplaySelection({
    required this.scenario,
    required this.targetWords,
  });
}

Future<AiRoleplaySelection?> showAiRoleplaySheet(
  BuildContext context,
  AppState app, {
  String? currentScenarioId,
}) {
  return showModalBottomSheet<AiRoleplaySelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.k.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AiRoleplaySheet(
      app: app,
      currentScenarioId: currentScenarioId,
    ),
  );
}

class _AiRoleplaySheet extends StatefulWidget {
  final AppState app;
  final String? currentScenarioId;

  const _AiRoleplaySheet({
    required this.app,
    this.currentScenarioId,
  });

  @override
  State<_AiRoleplaySheet> createState() => _AiRoleplaySheetState();
}

class _AiRoleplaySheetState extends State<_AiRoleplaySheet> {
  String _levelFilter = 'ALL';
  bool _useUserWords = true;
  List<(String word, String zh)> _userTargets = const [];

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final list = await loadUserRoleplayTargets(widget.app);
    if (!mounted) return;
    setState(() {
      _userTargets = list;
      if (list.isEmpty) _useUserWords = false;
    });
  }

  List<String> _targetsFor(AiRoleplayScenario s) {
    if (!_useUserWords || _userTargets.isEmpty) return s.defaultTargets;
    final out = <String>[for (final (w, _) in _userTargets) w];
    for (final d in s.defaultTargets) {
      if (out.length >= 4) break;
      if (!out.any((w) => w.toLowerCase() == d.toLowerCase())) {
        out.add(d);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final filtered = [
      for (final s in kAiRoleplayScenarios)
        if (_levelFilter == 'ALL' || s.level == _levelFilter) s,
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scrollCtl) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '印尼语情景对话',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: k.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '选一个真实场景，在对话中自然用出任务词即可打钩',
                          style: TextStyle(fontSize: 12.5, color: k.t3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTargetSourceToggle(k),
              const SizedBox(height: 10),
              _buildLevelPills(k),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  controller: scrollCtl,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _buildScenarioCard(k, filtered[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTargetSourceToggle(KColors k) {
    final hasUser = _userTargets.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: k.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: k.border),
      ),
      child: Row(
        children: [
          Icon(Icons.track_changes_rounded, size: 17, color: k.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasUser && _useUserWords
                  ? '穿插我的错词/今日词：${_userTargets.map((e) => e.$1).join('、')}'
                  : '使用各场景精选高频任务词（4 个/场景）',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: k.t2, height: 1.35),
            ),
          ),
          if (hasUser) ...[
            const SizedBox(width: 8),
            GestureDetector(
              key: const Key('roleplay.toggleSource'),
              onTap: () => setState(() => _useUserWords = !_useUserWords),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _useUserWords ? k.tint : k.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _useUserWords ? k.brand.withValues(alpha: 0.4) : k.border),
                ),
                child: Text(
                  _useUserWords ? '用我的词' : '用场景词',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _useUserWords ? k.deep : k.t2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelPills(KColors k) {
    const levels = [
      ('ALL', '全部 (12)'),
      ('A1', 'A1 入门'),
      ('A2', 'A2 初级'),
      ('B1', 'B1 中级'),
      ('B2', 'B2 进阶'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (code, label) in levels)
          GestureDetector(
            key: ValueKey('roleplay.level.$code'),
            onTap: () => setState(() => _levelFilter = code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _levelFilter == code ? k.tint : k.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _levelFilter == code
                      ? k.brand.withValues(alpha: 0.45)
                      : k.border,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      _levelFilter == code ? FontWeight.w600 : FontWeight.w400,
                  color: _levelFilter == code ? k.deep : k.t2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildScenarioCard(KColors k, AiRoleplayScenario s) {
    final active = widget.currentScenarioId == s.id;
    final targets = _targetsFor(s);
    return GestureDetector(
      key: ValueKey('roleplay.card.${s.id}'),
      onTap: () => Navigator.pop(
        context,
        AiRoleplaySelection(scenario: s, targetWords: targets),
      ),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? k.brand.withValues(alpha: 0.55) : k.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: k.tint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'BIPA ${s.level}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: k.deep,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: k.text,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: k.t3),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '任务：${s.userGoal}',
              style: TextStyle(fontSize: 12.5, color: k.t2, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              '语域：${s.register}',
              style: TextStyle(fontSize: 11.5, color: k.t3),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (final w in targets)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: k.bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: k.border),
                    ),
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: k.text,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
