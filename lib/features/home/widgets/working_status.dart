import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message_part.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_semantic_colors.dart';
import 'assistant_avatar.dart';

/// One Bot that is generating right now, with what it is doing.
class WorkingBot {
  final Conversation conversation;
  final Assistant? assistant;
  final String action;

  const WorkingBot({
    required this.conversation,
    required this.assistant,
    required this.action,
  });

  String get botName => assistant?.name ?? '智能体';
}

/// What a streaming Bot is doing right now, derived live from the latest
/// parts of its streaming message: a running tool call wins, then
/// reasoning, then plain reply text.
String describeBotAction(ChatMessage message, AppLocalizations l10n) {
  for (final part in message.parts.reversed) {
    if (part is ToolCallPart) return _toolAction(part.payloadJson, l10n);
    if (part is ReasoningPart && part.text.trim().isNotEmpty) {
      return l10n.botActionThinking;
    }
    if (part is TextPart && part.text.trim().isNotEmpty) {
      return l10n.botActionReplying;
    }
  }
  return l10n.botActionThinking;
}

String _toolAction(String payloadJson, AppLocalizations l10n) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) {
      final name = (decoded['name'] ?? '').toString().toLowerCase();
      if (name.contains('search')) return l10n.botActionSearching;
      if (name.contains('fetch') ||
          name.contains('browser') ||
          name.contains('web')) {
        return l10n.botActionBrowsing;
      }
      if (name.contains('bash') ||
          name.contains('exec') ||
          name.contains('terminal') ||
          name.contains('command') ||
          name.contains('shell')) {
        return l10n.botActionRunningCommand;
      }
      if (name.contains('write') ||
          name.contains('edit') ||
          name.contains('patch')) {
        return l10n.botActionWritingCode;
      }
      if (name.contains('read')) return l10n.botActionReadingFile;
    }
  } catch (_) {}
  return l10n.botActionUsingTool;
}

/// All Bots currently generating anywhere in the app. Derived from the
/// shared ChatService message cache, so the chat header indicator and
/// the sidebar progress rows always agree — one source, not two.
List<WorkingBot> computeWorkingBots(
  ChatService chatService,
  AssistantProvider assistants,
  AppLocalizations l10n,
) {
  final result = <WorkingBot>[];
  for (final conversation in chatService.getAllConversations()) {
    final messages = chatService.getMessages(conversation.id);
    for (final message in messages.reversed) {
      if (message.role == 'assistant' && message.isStreaming) {
        final botId = message.senderId ?? conversation.assistantId;
        result.add(
          WorkingBot(
            conversation: conversation,
            assistant: botId == null ? null : assistants.getById(botId),
            action: describeBotAction(message, l10n),
          ),
        );
        break;
      }
    }
  }
  return result;
}

/// The working Bot in one conversation, or null when it is idle.
WorkingBot? workingBotFor(
  ChatService chatService,
  AssistantProvider assistants,
  AppLocalizations l10n,
  String conversationId,
) {
  for (final bot in computeWorkingBots(chatService, assistants, l10n)) {
    if (bot.conversation.id == conversationId) return bot;
  }
  return null;
}

/// Small live chip for the chat header: how many Bots are working right
/// now (with their tiny avatars). Tap to expand the per-Bot list —
/// who is doing what, in small text.
class WorkingIndicator extends StatelessWidget {
  const WorkingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chatService = context.watch<ChatService>();
    final assistants = context.watch<AssistantProvider>();
    final working = computeWorkingBots(chatService, assistants, l10n);
    if (working.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showWorkingList(context, working),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 6),
              for (final bot in working.take(3))
                if (bot.assistant != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: AssistantAvatar(assistant: bot.assistant!, size: 16),
                  ),
              Text(
                l10n.workingCountLabel(working.length),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWorkingList(BuildContext context, List<WorkingBot> working) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        // Pure-black theme: the default dialog fill is scheme.surface
        // (#000), invisible against the black chat. Use the card layer
        // (#191919, same as the settings cards) so the panel reads as a
        // panel instead of floating text over the messages.
        backgroundColor: context.appColors.surfaceCard,
        title: Text(
          l10n.workingListTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final bot in working)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      if (bot.assistant != null)
                        AssistantAvatar(assistant: bot.assistant!, size: 28)
                      else
                        const SizedBox(width: 28, height: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bot.botName,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${bot.action} · ${bot.conversation.title}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.homePageCancel),
          ),
        ],
      ),
    );
  }
}
