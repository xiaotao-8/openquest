import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/providers/goals_store.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/muse_nav_bus.dart';

/// The Goals tab: the user's own goals with live progress. Starts empty;
/// goals exist only because the user created them. The sidebar goal
/// section reads the same GoalsStore.
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final store = context.watch<GoalsStore>();
    final goals = store.goals;
    final chatService = context.watch<ChatService>();
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.museNavGoals,
                    style: TextStyle(
                      fontSize: 17,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Lucide.Plus, size: 20),
                  tooltip: l10n.goalAddTitle,
                  onPressed: () => _showGoalDialog(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: goals.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Text(
                        l10n.museGoalsEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      for (final goal in goals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _GoalCard(
                            goal: goal,
                            linkedConversation: goal.conversationId == null
                                ? null
                                : chatService.getConversation(
                                    goal.conversationId!,
                                  ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showGoalDialog(
    BuildContext context, {
    GoalItem? existing,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final store = context.read<GoalsStore>();
    final conversations = context
        .read<ChatService>()
        .getAllConversations()
        .where((c) => c.title.trim().isNotEmpty)
        .toList();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final targetCtrl = TextEditingController(
      text: existing == null ? '' : _num(existing.target),
    );
    final currentCtrl = TextEditingController(
      text: existing == null ? '' : _num(existing.current),
    );
    // A link to a since-deleted conversation is treated as no link.
    var selectedLink = existing?.conversationId;
    if (selectedLink != null &&
        !conversations.any((c) => c.id == selectedLink)) {
      selectedLink = null;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null ? l10n.goalAddTitle : l10n.goalEditTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 320,
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: existing == null,
                  decoration: InputDecoration(labelText: l10n.goalTitleLabel),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: currentCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.goalCurrentLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.goalTargetLabel,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: selectedLink,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.goalLinkConversationLabel,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l10n.goalLinkNone),
                    ),
                    for (final c in conversations)
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => selectedLink = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.homePageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.goalSave),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;
    final target = double.tryParse(targetCtrl.text.trim()) ?? 1;
    final current = double.tryParse(currentCtrl.text.trim()) ?? 0;
    if (existing == null) {
      await store.addGoal(
        title: title,
        target: target <= 0 ? 1 : target,
        conversationId: selectedLink,
      );
      if (current > 0) {
        final created = store.goals.lastWhere((g) => g.title == title);
        await store.updateGoal(created.id, current: current);
      }
    } else {
      await store.updateGoal(
        existing.id,
        title: title,
        target: target <= 0 ? 1 : target,
        current: current,
        conversationId: selectedLink,
        clearConversation: selectedLink == null,
      );
    }
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.linkedConversation});

  final GoalItem goal;

  /// The conversation this goal is linked to, resolved by the page;
  /// null when the goal has no link (or the conversation is gone).
  final Conversation? linkedConversation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = context.read<GoalsStore>();
    final pct = (goal.progress * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Lucide.Pencil, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    GoalsPage._showGoalDialog(context, existing: goal),
              ),
              IconButton(
                icon: Icon(Lucide.Trash2, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () => store.removeGoal(goal.id),
              ),
            ],
          ),
          if (linkedConversation != null) ...[
            const SizedBox(height: 2),
            InkWell(
              onTap: () => MuseNavBus.instance.requestOpenConversation(
                linkedConversation!.id,
              ),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.MessagesSquare,
                      size: 13,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        linkedConversation!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Lucide.ChevronRight,
                      size: 13,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: goal.progress,
              minHeight: 6,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${GoalsPage._num(goal.current)} / ${GoalsPage._num(goal.target)} · $pct%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Lucide.Minus, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: goal.current <= 0
                    ? null
                    : () =>
                          store.updateGoal(goal.id, current: goal.current - 1),
              ),
              IconButton(
                icon: Icon(Lucide.Plus, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    store.updateGoal(goal.id, current: goal.current + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
