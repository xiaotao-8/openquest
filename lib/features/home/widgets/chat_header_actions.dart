import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/group_chat_meta.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../settings/pages/settings_page.dart';
import 'create_group_dialog.dart';

/// The chat header's settings entry — top-right corner, gear icon,
/// opens the settings page. Present in both desktop and mobile layouts.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IosIconButton(
      size: 20,
      padding: const EdgeInsets.all(8),
      minSize: 40,
      icon: Lucide.Settings,
      semanticLabel: AppLocalizations.of(context)!.settingsButtonTooltip,
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      },
    );
  }
}

/// Opens the current group conversation's settings (members + model
/// assignment). Renders nothing when the open conversation is not a
/// group.
class GroupSettingsButton extends StatelessWidget {
  const GroupSettingsButton({super.key, required this.conversationId});

  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    if (conversationId == null) return const SizedBox.shrink();
    final chatService = context.watch<ChatService>();
    final conversation = chatService.getConversation(conversationId!);
    if (conversation == null ||
        !GroupChatMeta.fromExtras(conversation.extras).isGroup) {
      return const SizedBox.shrink();
    }
    return IosIconButton(
      size: 20,
      padding: const EdgeInsets.all(8),
      minSize: 40,
      icon: Lucide.Users,
      semanticLabel: AppLocalizations.of(context)!.groupSettingsTitle,
      onTap: () => CreateGroupDialog.showEdit(context, conversation),
    );
  }
}
