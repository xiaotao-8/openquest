import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/conversation.dart';
import '../../../core/models/group_chat_meta.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/goals_store.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/muse_nav_bus.dart';
import 'assistant_avatar.dart';
import 'create_group_dialog.dart';
import 'working_status.dart';

/// Muse-style sidebar sections above the conversation list:
/// 选项卡 (Main Chat / Feed / Ideas / Goals / Library), 空间 (user-created
/// group chats — starts empty), 旁聊 (user-created side chats — starts
/// empty). Nothing here is pre-created; every entry exists only because
/// the user made it.
class MuseNavSections extends StatelessWidget {
  const MuseNavSections({
    super.key,
    required this.onSelectConversation,
    this.onNavigate,
  });

  final void Function(String id) onSelectConversation;

  /// Called after any navigation tap (tab switch or conversation open).
  /// Mobile passes this to close its drawer; the persistent desktop
  /// sidebar leaves it null.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.watch<ChatService>();
    final all = chatService.getAllConversations();
    final groups = [
      for (final c in all)
        if (GroupChatMeta.fromExtras(c.extras).isGroup) c,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final sideChats = [
      for (final c in all)
        if (!GroupChatMeta.fromExtras(c.extras).isGroup &&
            GroupChatMeta.isSideChat(c.extras))
          c,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final currentId = chatService.currentConversationId;
    final assistants = context.watch<AssistantProvider>();
    final workingByConversation = <String, WorkingBot>{
      for (final bot in computeWorkingBots(chatService, assistants, l10n))
        bot.conversation.id: bot,
    };
    final goals = context.watch<GoalsStore>().goals;

    return ValueListenableBuilder<MuseNavTab>(
      valueListenable: MuseNavBus.instance.tab,
      builder: (context, tab, _) {
        return Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _SectionHeader(title: l10n.museNavTabsSection),
                _NavRow(
                  icon: Lucide.MessageCircle,
                  label: l10n.museNavMainChat,
                  selected: tab == MuseNavTab.chat,
                  onTap: () => _selectTab(MuseNavTab.chat),
                ),
                _NavRow(
                  icon: Lucide.Activity,
                  label: l10n.museNavFeed,
                  selected: tab == MuseNavTab.feed,
                  onTap: () => _selectTab(MuseNavTab.feed),
                ),
                _NavRow(
                  icon: Lucide.Lightbulb,
                  label: l10n.museNavIdeas,
                  selected: tab == MuseNavTab.ideas,
                  onTap: () => _selectTab(MuseNavTab.ideas),
                ),
                _NavRow(
                  icon: Lucide.Target,
                  label: l10n.museNavGoals,
                  selected: tab == MuseNavTab.goals,
                  onTap: () => _selectTab(MuseNavTab.goals),
                ),
                _NavRow(
                  icon: Lucide.Library,
                  label: l10n.museNavLibrary,
                  selected: tab == MuseNavTab.library,
                  onTap: () => _selectTab(MuseNavTab.library),
                ),
                if (goals.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SectionHeader(title: l10n.museNavGoals),
                  for (final goal in goals)
                    _GoalRow(
                      goal: goal,
                      subtitle: goal.conversationId == null
                          ? null
                          : chatService
                                .getConversation(goal.conversationId!)
                                ?.title,
                      onTap: () {
                        // A linked goal jumps straight into its group
                        // chat / conversation; an unlinked one opens
                        // the Goals tab.
                        final linked = goal.conversationId == null
                            ? null
                            : chatService.getConversation(goal.conversationId!);
                        if (linked != null) {
                          _openConversation(linked.id);
                        } else {
                          _selectTab(MuseNavTab.goals);
                        }
                      },
                    ),
                ],
                const SizedBox(height: 10),
                _SectionHeader(
                  title: l10n.museNavSpacesSection,
                  onAdd: () => _createGroup(context),
                ),
                if (groups.isEmpty)
                  _EmptyText(text: l10n.museNavNoSpaces)
                else
                  for (final c in groups)
                    _ConversationRow(
                      conversation: c,
                      leading: GroupAvatar(
                        name: c.title,
                        avatarPath: GroupChatMeta.fromExtras(c.extras).avatar,
                        size: 24,
                      ),
                      icon: Lucide.Users,
                      selected: tab == MuseNavTab.chat && c.id == currentId,
                      onTap: () => _openConversation(c.id),
                      subtitle: workingByConversation[c.id] == null
                          ? null
                          : '${workingByConversation[c.id]!.botName} · ${workingByConversation[c.id]!.action}',
                    ),
                _NavRow(
                  icon: Lucide.Plus,
                  label: l10n.museNavNewSpace,
                  selected: false,
                  onTap: () => _createGroup(context),
                ),
                const SizedBox(height: 10),
                _SectionHeader(
                  title: l10n.museNavSideChatsSection,
                  onAdd: () => _createSideChat(context),
                ),
                if (sideChats.isEmpty)
                  _EmptyText(text: l10n.museNavNoSideChats)
                else
                  for (final c in sideChats)
                    _ConversationRow(
                      conversation: c,
                      icon: Lucide.MessagesSquare,
                      selected: tab == MuseNavTab.chat && c.id == currentId,
                      onTap: () => _openConversation(c.id),
                      subtitle: workingByConversation[c.id] == null
                          ? null
                          : '${workingByConversation[c.id]!.botName} · ${workingByConversation[c.id]!.action}',
                    ),
                _NavRow(
                  icon: Lucide.Plus,
                  label: l10n.museNavNewSideChat,
                  selected: false,
                  onTap: () => _createSideChat(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectTab(MuseNavTab tab) {
    MuseNavBus.instance.select(tab);
    onNavigate?.call();
  }

  void _openConversation(String id) {
    MuseNavBus.instance.showChat();
    onSelectConversation(id);
    onNavigate?.call();
  }

  Future<void> _createGroup(BuildContext context) async {
    final id = await CreateGroupDialog.show(context);
    if (id != null) _openConversation(id);
  }

  Future<void> _createSideChat(BuildContext context) async {
    final chatService = context.read<ChatService>();
    final conversation = await chatService.createConversation(
      assistantId: null,
      activate: false,
    );
    await chatService.updateConversationExtras(conversation.id, (extras) {
      final next = Map<String, dynamic>.from(extras);
      next[GroupChatMeta.sideChatKey] = true;
      return next;
    });
    _openConversation(conversation.id);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAdd});

  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 2, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Lucide.Plus,
                  size: 16,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Small live status line (e.g. which Bot is working in this room).
  final String? subtitle;

  /// Optional leading widget (e.g. a group's avatar) shown instead of
  /// the icon.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? cs.surfaceContainerHighest.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                if (leading != null)
                  leading!
                else
                  Icon(
                    icon,
                    size: 17,
                    color: cs.onSurface.withValues(
                      alpha: selected ? 0.95 : 0.75,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: cs.onSurface.withValues(
                            alpha: selected ? 0.95 : 0.85,
                          ),
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
  });

  final Conversation conversation;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return _NavRow(
      icon: icon,
      label: conversation.title,
      selected: selected,
      onTap: onTap,
      subtitle: subtitle,
      leading: leading,
    );
  }
}

/// One goal in the sidebar: title, percent and a thin progress bar —
/// the same GoalsStore data the Goals tab shows. When the goal is
/// linked to a conversation, its title appears in small text under
/// the goal title.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.onTap, this.subtitle});

  final GoalItem goal;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (goal.progress * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Lucide.Target,
                      size: 15,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        goal.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 25, top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 25),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: goal.progress,
                      minHeight: 3.5,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: cs.onSurface.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
