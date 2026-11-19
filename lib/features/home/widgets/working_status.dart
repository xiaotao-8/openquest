import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message_part.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
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

Map<String, dynamic> _toolArgs(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
  }
  return const <String, dynamic>{};
}

/// One-line, length-capped rendering of a tool argument value.
String _shortArg(Object? value, [int max = 90]) {
  final text = (value ?? '').toString().replaceAll('\n', ' ').trim();
  if (text.length <= max) return text;
  return '${text.substring(0, max)}…';
}

/// What a running tool call is doing, with the real call detail the user
/// asked for: the search query, the fetched page's host, the exact
/// command, the file path, or the connected server + tool name — never
/// just a generic "using a tool" when the payload says more.
String _toolAction(String payloadJson, AppLocalizations l10n) {
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) {
      final name = (decoded['name'] ?? '').toString();
      final lower = name.toLowerCase();
      final args = _toolArgs(decoded['arguments']);
      final server = (decoded['server'] ?? '').toString().trim();
      if (lower.contains('search')) {
        final query = _shortArg(args['query'] ?? args['q']);
        return query.isEmpty
            ? l10n.botActionSearching
            : l10n.chatMessageWidgetWebSearch(query);
      }
      if (lower.contains('fetch') ||
          lower.contains('browser') ||
          lower.contains('web')) {
        final url = (args['url'] ?? '').toString().trim();
        if (url.isNotEmpty) {
          final host = Uri.tryParse(url)?.host ?? '';
          return l10n.chatMessageWidgetWebFetch(
            host.isEmpty ? _shortArg(url) : host,
          );
        }
        return l10n.botActionBrowsing;
      }
      if (lower.contains('bash') ||
          lower.contains('exec') ||
          lower.contains('terminal') ||
          lower.contains('command') ||
          lower.contains('shell')) {
        final command = _shortArg(args['command'] ?? args['cmd']);
        return command.isEmpty
            ? l10n.botActionRunningCommand
            : l10n.botActionRunningCommandDetail(command);
      }
      if (lower.contains('write') ||
          lower.contains('edit') ||
          lower.contains('patch')) {
        final path = _shortArg(
          args['path'] ?? args['file_path'] ?? args['filename'],
          70,
        );
        return path.isEmpty
            ? l10n.botActionWritingCode
            : l10n.botActionWritingFileDetail(path);
      }
      if (lower.contains('read')) {
        final path = _shortArg(
          args['path'] ?? args['file_path'] ?? args['filename'],
          70,
        );
        return path.isEmpty
            ? l10n.botActionReadingFile
            : l10n.botActionReadingFileDetail(path);
      }
      if (lower == 'app_settings') {
        final key = _shortArg(args['key'], 40);
        if (key.isNotEmpty) return l10n.chatMessageWidgetAppSettings(key);
      }
      if (server.isNotEmpty && name.isNotEmpty) {
        return l10n.botActionServerTool(name, server);
      }
      if (name.isNotEmpty) return l10n.chatMessageWidgetToolCall(name);
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
        onTap: () => _showWorkingList(context),
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

  void _showWorkingList(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _WorkingListPanel(),
    );
  }
}

/// The expanded working panel: large and readable, one row per working
/// Bot with its real current activity. It watches the shared ChatService,
/// so rows update live while the panel is open (and it reports when
/// everyone has finished instead of going stale).
class _WorkingListPanel extends StatelessWidget {
  const _WorkingListPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final chatService = context.watch<ChatService>();
    final assistants = context.watch<AssistantProvider>();
    final working = computeWorkingBots(chatService, assistants, l10n);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      // Pure-black theme: the default dialog fill is scheme.surface
      // (#000), invisible against the black chat. Use the card layer
      // (#191919, same as the settings cards) so the panel reads as a
      // panel instead of floating text over the messages.
      backgroundColor: context.appColors.surfaceCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    l10n.workingListTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (working.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        l10n.workingCountLabel(working.length),
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: Icon(Lucide.X, size: 20, color: cs.onSurface),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (working.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    l10n.workingListAllDone,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: working.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: cs.outlineVariant.withValues(alpha: 0.14),
                    ),
                    itemBuilder: (context, index) {
                      final bot = working[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bot.assistant != null)
                              AssistantAvatar(
                                assistant: bot.assistant!,
                                size: 40,
                              )
                            else
                              const SizedBox(width: 40, height: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bot.botName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    bot.action,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.35,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.88,
                                      ),
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    bot.conversation.title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
