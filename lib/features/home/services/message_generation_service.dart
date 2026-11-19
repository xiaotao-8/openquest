import '../../../core/services/tools/view_image_tool.dart';
import '../../../core/models/native_compaction.dart';
import '../../../core/models/compression_config.dart';
import '../../../core/models/carried_original.dart';
import '../../../core/services/api/native_compaction_context.dart';
import '../../../core/services/api/providers/zhipu_layout_parsing.dart';
import '../../../core/models/context_operation.dart';
import '../../../core/services/api/request_image_context.dart';
import '../../intelligent_ui/host/ui_context_submission.dart';
import '../../intelligent_ui/protocol/ui_stream_parser.dart';
import 'package:Kelivo/core/providers/external_mounts_provider.dart';
import 'dart:async';
import '../../../core/models/quote_ref.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/message_part.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/group_chat_meta.dart';
import '../../../core/models/model_spec.dart';
import '../../../core/models/reasoning_request.dart';
import '../../../core/models/skills_binding.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/response_speed.dart';
import '../../../core/services/api/providers/openai/responses_history.dart';
import '../../../core/services/api/reasoning/reasoning_dialects.dart';
import '../../../core/services/model_spec/model_spec_resolver.dart';
import '../../../core/providers/workspace_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/services/logging/context_logger.dart';
import '../../../core/services/logging/context_log_models.dart';
import '../../../core/services/memory/memory_block_builder.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/workspace/workspace_tools_service.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/assistant_regex.dart';
import '../../../core/models/assistant_regex.dart';
import '../controllers/stream_controller.dart' as stream_ctrl;
import '../controllers/generation_controller.dart';
import 'ask_user_interaction_service.dart';
import 'context_assembly.dart';
import 'context_usage_service.dart';
import 'message_builder_service.dart';
import 'tool_approval_service.dart';
import '../utils/model_display_helper.dart';

/// Callback types for UI updates from MessageGenerationService
typedef OnMessagesChanged = void Function();
typedef OnConversationLoadingChanged =
    void Function(String conversationId, bool loading);
typedef OnScrollToBottom = void Function();
typedef OnShowError = void Function(String message);
typedef OnShowWarning = void Function(String message);

const String conversationIdHeaderName = 'X-Conversation-Id';
const String _conversationIdHeaderNameLower = 'x-conversation-id';

Map<String, String>? buildConversationRequestHeaders({
  required String conversationId,
  Map<String, String>? customHeaders,
}) {
  final headers = <String, String>{
    if (customHeaders != null)
      for (final entry in customHeaders.entries)
        if (entry.key.toLowerCase() != _conversationIdHeaderNameLower)
          entry.key: entry.value,
  };
  final normalizedConversationId = conversationId.trim();
  if (normalizedConversationId.isNotEmpty) {
    headers[conversationIdHeaderName] = normalizedConversationId;
  }
  return headers.isEmpty ? null : headers;
}

/// Rewrites pre-rename native-UI markers (`kelivo-ui` fences and
/// `kelivo.native/1` catalog headers) to their OpenQuest names inside an
/// assembled request payload. Mutates [apiMessages] in place; only the
/// outgoing request is affected — stored history is never rewritten.
void rewriteLegacyUiMarkers(List<Map<String, dynamic>> apiMessages) {
  String rewrite(String text) {
    if (!text.contains('kelivo')) return text;
    return text
        .replaceAll('```kelivo-ui', '```openquest-ui')
        .replaceAll('kelivo.native/1', 'openquest.native/1');
  }

  Object? rewriteValue(Object? value) {
    if (value is String) return rewrite(value);
    if (value is List) {
      var changed = false;
      final out = <Object?>[];
      for (final part in value) {
        final next = rewriteValue(part);
        if (!identical(next, part)) changed = true;
        out.add(next);
      }
      return changed ? out : value;
    }
    if (value is Map) {
      var changed = false;
      final out = <String, dynamic>{};
      value.forEach((key, v) {
        final next = rewriteValue(v);
        if (!identical(next, v)) changed = true;
        out[key.toString()] = next;
      });
      return changed ? out : value;
    }
    return value;
  }

  for (final message in apiMessages) {
    final content = message['content'];
    final rewritten = rewriteValue(content);
    if (!identical(rewritten, content)) {
      message['content'] = rewritten;
    }
  }
}

/// Placeholder text an earlier build substituted for broken fences. One
/// such substitution was stored as an assistant reply, and the model kept
/// copying the sentence as if it were the card format.
const _legacyUiPlaceholder = '（此处有一张交互卡片，源码略）';

/// A complete, valid minimal voting card. Broken historical fences are
/// swapped for this paradigm so the shape the model imitates is a working
/// one. API-level diagnosis (2026-11-19, 9 controlled conditions) proved
/// the model copies the shape of its previous card replies and ignores
/// guidance wording in a polluted conversation: deleting broken fences
/// left prose-only "card replies" and the model answered prose-only;
/// sanitized history plus one valid card turn produced valid cards that
/// then self-sustained.
const validCardParadigm =
    '```openquest-ui\n'
    'ui 1 catalog "openquest.native/1"\n'
    '\$choice: string = "A"\n'
    'root = Column(children=[intro,form,ask])\n'
    'intro = Text(text="主推口味投票", variant="caption")\n'
    'form = Form(children=[voteGroup])\n'
    'voteGroup = RadioGroup(label="选一款主推口味", bind=\$choice, options=[{"value":"A","label":"桂花"},{"value":"B","label":"栗子"},{"value":"C","label":"南瓜"}], required=true)\n'
    'ask = Button(label="提交投票", form=form, action=Ask(text="我选了这款口味", context={"choice":\$choice}))\n'
    '```';

const _paradigmUserTurn = '做一个主推口味三选一投票卡，让我点选';
const _paradigmAssistantTurn =
    '结论：用这张卡选主推口味。\n\n$validCardParadigm\n\n**点选后告诉我结果**～';

/// Repairs card replies in the assembled request history. Stored/displayed
/// history is never touched; this only changes what the model sees.
///
/// - A valid `openquest-ui` fence passes through byte-identical.
/// - An invalid fence is replaced in place by [validCardParadigm], keeping
///   the surrounding prose, so the turn keeps the shape of a working card
///   reply instead of degenerating into a prose-only "card" the model
///   would imitate.
/// - The legacy placeholder sentence is likewise swapped for the paradigm.
/// - If any repair happened and no fence in the history was natively
///   valid, one paradigm exchange is inserted just before the final
///   user message, so the most recent card example in context is valid.
///   Once a real valid card lands in history this stops firing and the
///   conversation sustains itself.
void sanitizeInvalidUiFences(List<Map<String, dynamic>> apiMessages) {
  var repaired = false;
  var hasNativeValidFence = false;

  bool fenceIsValid(String body) {
    final snapshot = UiStreamParser().update(body, closed: true);
    return !snapshot.invalid && snapshot.program.diagnostics.isEmpty;
  }

  String sanitize(String text) {
    var result = text;
    if (result.contains('```openquest-ui')) {
      final out = StringBuffer();
      var cursor = 0;
      var changed = false;
      while (true) {
        final open = result.indexOf('```openquest-ui', cursor);
        if (open < 0) break;
        final bodyStart = result.indexOf('\n', open);
        if (bodyStart < 0) break;
        final close = result.indexOf('```', bodyStart + 1);
        if (close < 0) break;
        final body = result.substring(bodyStart + 1, close);
        out.write(result.substring(cursor, open));
        if (fenceIsValid(body)) {
          hasNativeValidFence = true;
          out.write(result.substring(open, close + 3));
        } else {
          out.write(validCardParadigm);
          changed = true;
          repaired = true;
        }
        cursor = close + 3;
      }
      if (changed) {
        out.write(result.substring(cursor));
        result = out.toString();
      }
    }
    if (result.contains(_legacyUiPlaceholder)) {
      result = result.replaceAll(_legacyUiPlaceholder, validCardParadigm);
      repaired = true;
    }
    return result;
  }

  Object? sanitizeValue(Object? value) {
    if (value is String) return sanitize(value);
    if (value is List) {
      var changed = false;
      final out = <Object?>[];
      for (final part in value) {
        final next = sanitizeValue(part);
        if (!identical(next, part)) changed = true;
        out.add(next);
      }
      return changed ? out : value;
    }
    if (value is Map) {
      var changed = false;
      final out = <String, dynamic>{};
      value.forEach((key, v) {
        final next = sanitizeValue(v);
        if (!identical(next, v)) changed = true;
        out[key.toString()] = next;
      });
      return changed ? out : value;
    }
    return value;
  }

  for (final message in apiMessages) {
    final content = message['content'];
    final sanitized = sanitizeValue(content);
    if (!identical(sanitized, content)) {
      message['content'] = sanitized;
    }
  }

  if (repaired && !hasNativeValidFence) {
    final insertAt =
        apiMessages.isNotEmpty && apiMessages.last['role'] == 'user'
        ? apiMessages.length - 1
        : apiMessages.length;
    apiMessages.insertAll(insertAt, [
      {'role': 'user', 'content': _paradigmUserTurn},
      {'role': 'assistant', 'content': _paradigmAssistantTurn},
    ]);
  }
}

/// Result of preparing a message generation
class UnprocessedRequestContext {
  UnprocessedRequestContext({
    required this.apiMessages,
    required this.toolDefs,
    required this.hasBuiltInSearch,
    required this.workspaceContext,
    required this.mcpRouteSnapshot,
    required this.workspaceAttachments,
    required this.cfg,
  });

  final List<Map<String, dynamic>> apiMessages;
  final List<Map<String, dynamic>> toolDefs;
  final bool hasBuiltInSearch;
  final WorkspaceToolContext? workspaceContext;
  final McpToolRouteSnapshot? mcpRouteSnapshot;
  final List<AttachmentInfo> workspaceAttachments;
  final ProviderConfig cfg;
}

class PreparedGeneration {
  final List<Map<String, dynamic>> apiMessages;
  final List<Map<String, dynamic>> toolDefs;
  final ToolCallHandler? onToolCall;
  final bool hasBuiltInSearch;
  final List<String> lastUserImagePaths;
  final Object? contextUsageConfiguration;
  final int? contextUsageRevision;
  final RequestImageContext? imageContext;

  PreparedGeneration({
    required this.apiMessages,
    required this.toolDefs,
    this.onToolCall,
    required this.hasBuiltInSearch,
    required this.lastUserImagePaths,
    this.contextUsageConfiguration,
    this.contextUsageRevision,
    this.imageContext,
  });
}

/// Service for handling message generation orchestration.
///
/// This service coordinates:
/// - Message creation (user + assistant placeholder)
/// - API message preparation with all injections
/// - Stream execution and management
/// - Reasoning state initialization
///
/// UI updates are communicated through callbacks to maintain separation.
class MessageGenerationService {
  MessageGenerationService({
    required this.chatService,
    required this.messageBuilderService,
    required this.generationController,
    required this.streamController,
    required this.contextProvider,
  });

  final ChatService chatService;
  final MessageBuilderService messageBuilderService;
  final GenerationController generationController;
  final stream_ctrl.StreamController streamController;
  final BuildContext contextProvider;

  // Callbacks for UI updates (set by home_page)
  OnMessagesChanged? onMessagesChanged;
  OnConversationLoadingChanged? onConversationLoadingChanged;
  OnScrollToBottom? onScrollToBottom;
  OnShowError? onShowError;
  OnShowWarning? onShowWarning;

  /// Called when file processing starts for the assistant message [messageId].
  void Function(String messageId)? onFileProcessingStarted;

  /// Called when file processing finishes. A null [messageId] clears whichever
  /// message currently owns the indicator (error/cancel cleanup paths).
  void Function(String? messageId)? onFileProcessingFinished;

  /// Check if reasoning is enabled for given budget
  bool isReasoningEnabled(ReasoningRequest r) {
    return r.level != ReasoningLevel.off;
  }

  /// Packs system prompt, injections, history, and tool definitions without
  /// OCR, document extraction, or inline-image encoding.
  /// Disable [applyMessageLimit] when compression already selected its range.
  Future<UnprocessedRequestContext> assembleUnprocessedRequestContext({
    bool? fixedContextStart,
    DateTime? promptTime,
    bool forceResponses = false,
    bool applyMessageLimit = true,
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    required SettingsProvider settings,
    required Assistant? assistant,
    required String? assistantId,
    required String providerKey,
    required String modelId,
    String? requiredAttachmentMessageId,
    bool syncWorkspaceAttachments = true,
    bool persistWorldBookActivation = true,
    void Function(int before, int after)? onWorldBookActivationPersisted,
  }) async {
    WorkspaceProvider? workspaceProvider;
    WorkspaceRuntimeProvider? runtimeProvider;
    ExternalMountsProvider? externalMounts;
    try {
      workspaceProvider = contextProvider.read<WorkspaceProvider>();
      runtimeProvider = contextProvider.read<WorkspaceRuntimeProvider>();
      externalMounts = contextProvider.read<ExternalMountsProvider?>();
    } catch (_) {}

    var cfg = settings.getProviderConfig(providerKey).forModelProtocol(modelId);
    final compression = currentConversation == null
        ? settings.compressionDefaults
        : await chatService.compressionConfig(
            currentConversation.id,
            settings.compressionDefaults,
          );
    if (forceResponses ||
        (compression.nativeEnabled &&
            compression.mode == AutoCompressionMode.auto) ||
        messages.any((m) => NativeCompactionPayload.forMessage(m) != null)) {
      cfg = nativeResponsesConfig(cfg);
    }
    final kind = ProviderConfig.classify(
      providerKey,
      explicitType: cfg.providerType,
    );
    final includeToolMessages = switch (kind) {
      ProviderKind.openai || ProviderKind.claude || ProviderKind.google => true,
    };
    final usesClaudeHistory =
        kind == ProviderKind.claude ||
        (kind == ProviderKind.google &&
            cfg.vertexAI == true &&
            modelId.toLowerCase().startsWith('claude-'));

    final apiMessages = messageBuilderService.buildApiMessages(
      messages: messages,
      versionSelections: versionSelections,
      currentConversation: currentConversation,
      includeToolMessages: includeToolMessages,
      // Claude replays its rounds from the native turn artifact instead.
      preserveToolTurns: !usesClaudeHistory,
      googleProviderId: kind == ProviderKind.google ? providerKey : null,
      claudeSource: usesClaudeHistory
          ? (providerId: providerKey, modelId: modelId)
          : null,
      responsesScope: kind == ProviderKind.openai && cfg.useResponseApi == true
          ? responsesReplayScope(cfg, modelId)
          : null,
    );

    // Group chat: present the room to the replying Bot — other Bots'
    // replies become named user turns, its own stay assistant turns.
    final groupMeta = currentConversation == null
        ? const GroupChatMeta()
        : GroupChatMeta.fromExtras(currentConversation.extras);
    if (groupMeta.isGroup && assistantId != null) {
      final assistants = contextProvider.read<AssistantProvider>();
      final mapped = mapGroupHistoryForBot(
        apiMessages: apiMessages,
        sourceMessages: messages,
        selfAssistantId: assistantId,
        nameOf: (id) => id == 'system' ? '系统提示' : assistants.getById(id)?.name,
      );
      apiMessages
        ..clear()
        ..addAll(mapped);
      // OpenQuest group guard: hand the replying Bot the room's real
      // member list. Bots may only @ members on this list — inventing a
      // member (seen in live testing: a Bot delegating to a nonexistent
      // 「画师」) stalls the room because nobody can ever answer.
      final memberNames = <String>[
        for (final id in groupMeta.memberIds)
          if (assistants.getById(id) != null) assistants.getById(id)!.name,
      ];
      if (memberNames.isNotEmpty) {
        final roster = <String, dynamic>{
          'role': 'system',
          'content':
              '本群成员名单（共 ${memberNames.length} 位）：${memberNames.join('、')}。'
              '你只能 @ 名单内的成员；名单外的人不存在，不要虚构新成员，'
              '也不要把任务派给名单外的人。'
              '群里聊天不用等被 @：看到消息就可以自然接话。'
              '如果你想让某位成员接着说，在回复里 @ 他/她，被 @ 的成员会接着回复；'
              '不用每条都 @，只在确实需要对方时用。',
        };
        // After the system prompt (which carries the Bot's Soul), so the
        // persona keeps top priority; the roster is a room fact, not an
        // instruction that may dilute it.
        final sysIndex = apiMessages.indexWhere((m) => m['role'] == 'system');
        apiMessages.insert(sysIndex < 0 ? 0 : sysIndex + 1, roster);
      }
    }

    if (assistant != null && assistant.regexRules.isNotEmpty) {
      for (int i = 0; i < apiMessages.length; i++) {
        final role = (apiMessages[i]['role'] ?? '').toString();
        if (role != 'assistant' ||
            isCarriedMessageId(
              apiMessages[i][imageContextOwnerKey]?.toString() ?? '',
            )) {
          continue;
        }
        final raw = (apiMessages[i]['content'] ?? '').toString();
        if (raw.isEmpty) continue;
        apiMessages[i]['content'] = applyAssistantRegexes(
          raw,
          assistant: assistant,
          scope: AssistantRegexScope.assistant,
          target: AssistantRegexTransformTarget.send,
        );
      }
    }

    // OpenQuest rename: history written before the rename still carries
    // legacy `kelivo-ui` fences / `kelivo.native/1` headers. Replayed
    // verbatim, the model imitates the old fence and its reply renders as
    // raw source instead of a native card. Rewrite the legacy markers in
    // the request payload only — stored/displayed history stays untouched.
    rewriteLegacyUiMarkers(apiMessages);

    // Broken native-UI blocks in history teach the model broken DSL: it
    // copies the defective shapes (multi-line array state, string
    // concatenation, mistyped values) into its next card and the reply
    // renders as red error blocks. Replace fences the app's own parser
    // rejects with a plain placeholder in the request payload only.
    sanitizeInvalidUiFences(apiMessages);

    final promptConversation = currentConversation == null
        ? null
        : chatService.getConversation(currentConversation.id) ??
              currentConversation;

    // Select real history before prompt injections can add synthetic user
    // turns. World-book scanning and placement then see the selected context.
    final hasFixedStart =
        fixedContextStart ??
        (currentConversation != null &&
            ContextHistory.fixedStart(
                  chatService.contextOperationsFor(currentConversation.id),
                ) !=
                null);
    if (applyMessageLimit && !hasFixedStart) {
      messageBuilderService.applyContextLimit(apiMessages, assistant);
    }

    messageBuilderService.injectSystemPrompt(
      apiMessages,
      assistant,
      modelId,
      conversation: promptConversation,
      promptTime: promptTime,
    );
    await messageBuilderService.injectMemoryAndRecentChats(
      apiMessages,
      assistant,
      settings: settings,
      currentConversationId: currentConversation?.id,
    );

    final hasBuiltInSearch = messageBuilderService.hasBuiltInSearch(
      settings,
      providerKey,
      modelId,
    );
    messageBuilderService.injectSearchPrompt(
      apiMessages,
      settings,
      assistant,
      hasBuiltInSearch,
    );
    await messageBuilderService.injectInstructionPrompts(
      apiMessages,
      assistantId,
      conversation: promptConversation,
      conversationScoped: assistant?.allowConversationPromptInjection ?? false,
    );
    var afterWorldBook = '';
    await messageBuilderService.injectWorldBookPrompts(
      apiMessages,
      assistantId,
      conversation: promptConversation,
      conversationScoped: assistant?.allowConversationPromptInjection ?? false,
      persistActivation: persistWorldBookActivation,
      deferAfterSystemPrompt: (content) => afterWorldBook = content,
      onActivationPersisted: onWorldBookActivationPersisted,
      sourceMessages: messageBuilderService.collapseVersions(
        messages,
        versionSelections,
      ),
    );

    WorkspaceToolContext? workspaceContext;
    var addedWorkspace = false;
    var workspaceAttachments = const <AttachmentInfo>[];
    try {
      if (workspaceProvider != null && runtimeProvider != null) {
        workspaceContext = await WorkspaceToolsService.resolve(
          externalMounts: externalMounts,
          conversationId: currentConversation?.id,
          workspaceProvider: workspaceProvider,
          runtimeProvider: runtimeProvider,
          chatService: chatService,
        );
      }
      workspaceContext ??= await _skillsOnlyContext(
        assistant: assistant,
        conversation: currentConversation,
      );
      if (syncWorkspaceAttachments &&
          workspaceContext != null &&
          !workspaceContext.skillsOnly) {
        workspaceAttachments = await syncAttachments(
          workspaceContext,
          messages,
          requiredMessageId: requiredAttachmentMessageId,
        );
      }
      if (workspaceContext != null) {
        addedWorkspace = await messageBuilderService.injectWorkspacePrompt(
          apiMessages,
          assistant,
          conversationId: currentConversation?.id,
          workspaceContext: workspaceContext,
        );
      }
    } catch (e) {
      if (workspaceContext != null && !workspaceContext.skillsOnly) {
        rethrow;
      }
      debugPrint('Workspace prompt/attachments failed: $e');
    }
    final addedSkills = await messageBuilderService.injectSkillsPrompt(
      apiMessages,
      assistant,
      conversationId: currentConversation?.id,
      workspaceContext: workspaceContext,
      toolsSupported: ModelSpecResolver.instance
          .spec(cfg, modelId)
          .supportsTool,
    );

    messageBuilderService.appendWorldBookAfterPrompt(
      apiMessages,
      afterWorldBook,
      afterNewSection: addedWorkspace || addedSkills,
    );

    final mcpRouteSnapshot = generationController.captureMcpToolRoutes(
      assistant,
      conversationId: currentConversation?.id,
    );
    final toolDefs = generationController.buildToolDefinitions(
      settings,
      assistant,
      providerKey,
      modelId,
      hasBuiltInSearch,
      mcpRouteSnapshot: mcpRouteSnapshot,
      workspaceContext: workspaceContext,
      conversationId: currentConversation?.id,
    );
    return UnprocessedRequestContext(
      apiMessages: apiMessages,
      toolDefs: toolDefs,
      hasBuiltInSearch: hasBuiltInSearch,
      workspaceContext: workspaceContext,
      mcpRouteSnapshot: mcpRouteSnapshot,
      workspaceAttachments: workspaceAttachments,
      cfg: cfg,
    );
  }

  /// References for a historical summary must not assemble a new chat request:
  /// that would refresh memory and world-book state from beyond its range.
  Future<String> compressionReferenceText({
    required String conversationId,
    required String modelId,
    required String? assistantId,
    required List<ChatMessage> messages,
    required DateTime promptTime,
    required bool includeInstructionInjections,
  }) async {
    final assistant = assistantId == null
        ? null
        : contextProvider.read<AssistantProvider>().getById(assistantId);
    final conversation = chatService.getConversation(conversationId);
    final apiMessages = messageBuilderService.buildApiMessages(
      messages: messages,
      versionSelections: chatService.getVersionSelections(conversationId),
      currentConversation: conversation?.copyWith(truncateIndex: -1),
      includeToolMessages: false,
    );
    messageBuilderService.injectSystemPrompt(
      apiMessages,
      assistant,
      modelId,
      conversation: conversation,
      promptTime: promptTime,
    );
    if (includeInstructionInjections) {
      await messageBuilderService.injectInstructionPrompts(
        apiMessages,
        assistantId,
        conversation: conversation,
        conversationScoped:
            assistant?.allowConversationPromptInjection ?? false,
      );
    }
    await messageBuilderService.injectWorldBookPrompts(
      apiMessages,
      assistantId,
      conversation: conversation,
      conversationScoped: assistant?.allowConversationPromptInjection ?? false,
      sourceMessages: messages,
      restrictToSourceMessages: true,
      persistActivation: false,
    );
    // Use the last frozen snapshot in this range, without refreshing it from
    // live memory or repeating superseded snapshots in a long conversation.
    final prompts = await chatService.chatRepositoryOrNull?.getMessagePrompts(
      messages.where((m) => m.role == 'user').map((m) => m.id),
    );
    for (final message in messages.reversed) {
      final frozen = prompts?[message.id];
      if (frozen == null || !frozen.carriesMemorySnapshot) continue;
      final split = MemoryBlockBuilder.splitInjectedPrefix(frozen.payload);
      if (split == null) continue;
      final reference = <String, dynamic>{
        'role': 'system',
        'content': split.prefix,
      };
      ContextSegmentTags.replaceWithSingle(
        reference,
        source: ContextSource.memorySnapshot,
        length: split.prefix.length,
        meta: {'messageId': message.id},
      );
      apiMessages.add(reference);
      break;
    }
    return ContextAssemblyPreview.fromApiMessages(
      apiMessages: apiMessages,
      tools: const [],
      mcpToolNames: const {},
      images: const [],
    ).referenceText;
  }

  Future<ContextAssemblyPreview> previewContextAssembly({
    bool? fixedContextStart,
    DateTime? promptTime,
    bool forceResponses = false,
    bool applyMessageLimit = true,
    required String conversationId,
    required String providerKey,
    required String modelId,
    required String? assistantId,
    List<ChatMessage>? messagesOverride,
  }) => _contextAssembly(
    fixedContextStart: fixedContextStart,
    promptTime: promptTime,
    forceResponses: forceResponses,
    applyMessageLimit: applyMessageLimit,
    conversationId: conversationId,
    providerKey: providerKey,
    modelId: modelId,
    assistantId: assistantId,
    messagesOverride: messagesOverride,
    persistWorldBookActivation: false,
  );

  Future<ContextAssemblyPreview> prepareCompressedContext({
    bool? fixedContextStart,
    required String conversationId,
    required String providerKey,
    required String modelId,
    required String? assistantId,
    List<ChatMessage>? messagesOverride,
  }) => _contextAssembly(
    fixedContextStart: fixedContextStart,
    conversationId: conversationId,
    providerKey: providerKey,
    modelId: modelId,
    assistantId: assistantId,
    messagesOverride: messagesOverride,
    persistWorldBookActivation: true,
  );

  Future<ContextAssemblyPreview> _contextAssembly({
    bool? fixedContextStart,
    DateTime? promptTime,
    bool forceResponses = false,
    bool applyMessageLimit = true,
    required String conversationId,
    required String providerKey,
    required String modelId,
    required String? assistantId,
    List<ChatMessage>? messagesOverride,
    required bool persistWorldBookActivation,
  }) async {
    final settings = contextProvider.read<SettingsProvider>();
    Assistant? assistant;
    try {
      final assistants = contextProvider.read<AssistantProvider>();
      assistant = assistantId == null ? null : assistants.getById(assistantId);
    } catch (_) {}
    final conversation = chatService.getConversation(conversationId);
    final messages =
        messagesOverride ??
        await chatService.loadSelectedContextMessages(
          conversationId,
          limit: applyMessageLimit && assistant?.limitContextMessages == true
              ? assistant!.contextMessageSize
              : 0x7fffffff,
        );
    final packed = await assembleUnprocessedRequestContext(
      fixedContextStart: fixedContextStart,
      promptTime: promptTime,
      forceResponses: forceResponses,
      applyMessageLimit: applyMessageLimit,
      messages: messages,
      versionSelections: chatService.getVersionSelections(conversationId),
      currentConversation: conversation?.copyWith(truncateIndex: -1),
      settings: settings,
      assistant: assistant,
      assistantId: assistantId,
      providerKey: providerKey,
      modelId: modelId,
      syncWorkspaceAttachments: false,
      persistWorldBookActivation: persistWorldBookActivation,
    );
    // Reuse the send path to include the live memory snapshot and frozen user
    // prompts. Previewing must never freeze a draft, run OCR, or write extras.
    await messageBuilderService.processUserMessagesForApi(
      packed.apiMessages,
      settings,
      assistant,
      conversation: conversation,
      sourceMessages: messages,
      previewOnly: true,
      nativePdfInput: ModelSpecResolver.instance
          .spec(packed.cfg, modelId)
          .supportsPdfInput,
    );
    final imageContext =
        ChatApiService.supportsOpenAIImagesApiRouting(packed.cfg, modelId) ||
            shouldUseZhipuLayoutParsing(packed.cfg, modelId)
        ? null
        : await _imageContext(
            conversationId,
            messages,
            packed,
            settings,
            modelId,
          );
    if (imageContext != null) {
      await imageContext.prepareMessages(
        packed.apiMessages,
        const [],
        parseMarkdownImages: settings.sendMarkdownImageLinksAsImages,
        allowRemoteImages: imageContext.allowsRemoteUserImages,
      );
    }
    final imagePreview = await imageContext?.preview();
    return ContextAssemblyPreview.fromApiMessages(
      imageContext: imageContext,
      apiMessages: packed.apiMessages,
      mcpToolNames: {
        for (final tool in packed.toolDefs)
          if (tool['function'] case {'name': final String name})
            if (packed.mcpRouteSnapshot?.containsExposedName(name) ?? false)
              name,
      },
      tools: packed.toolDefs,
      images: imagePreview == null
          ? imageRefsFromApiMessages(
              packed.apiMessages,
              sourceMessages: messages,
            )
          : [
              for (final image in imagePreview)
                if (image.included) const ContextImageRef(),
            ],
    );
  }

  Future<RequestImageContext> _imageContext(
    String conversationId,
    List<ChatMessage> messages,
    UnprocessedRequestContext packed,
    SettingsProvider settings,
    String modelId, {
    bool omitImages = false,
  }) async {
    final cfg = packed.cfg;
    final kind = ProviderConfig.classify(
      cfg.id,
      explicitType: cfg.providerType,
    );
    final original = await chatService.imageContextHistory(
      conversationId,
      throughMessageId: messages
          .where(
            (m) => !ContextOperation.isSummary(m) && !isCarriedMessageId(m.id),
          )
          .lastOrNull
          ?.id,
    );
    final history =
        chatService.chatRepositoryOrNull == null &&
            !chatService.isTemporaryConversation(conversationId)
        ? messages
        : original;
    final spec = ModelSpecResolver.instance.spec(cfg, modelId);
    final remoteImages =
        (kind == ProviderKind.openai && spec.remoteImageUrls) ||
        (kind == ProviderKind.google &&
            cfg.vertexAI == true &&
            modelId.toLowerCase().startsWith('claude-'));
    return RequestImageContext(
      settings: await chatService.imageContextSettings(conversationId),
      images: await RequestImageContext.collectHistory(
        history,
        parseMarkdownImages: settings.sendMarkdownImageLinksAsImages,
        allowRemoteImages: remoteImages,
      ),
      userTurns: RequestImageContext.userTurnsFor(history),
      inlineRemoteUsers: kind == ProviderKind.google,
      allowsRemoteUserImages: remoteImages,
      omitUserImages: settings.ocrActive,
      omitImages: omitImages,
      latestUserId: history
          .where((m) => m.role == 'user' && !ContextOperation.isSummary(m))
          .lastOrNull
          ?.id,
      budget: cfg.requestBudgetForModel(modelId),
      historyBudget: cfg.defaultRequestBudget,
      canImageInput: spec.supportsImageInput,
      canRecall: packed.toolDefs.any(ViewImageTool.supportsHistory),
      viewImageUris: packed.toolDefs.any(ViewImageTool.supportsFiles)
          ? {for (final file in packed.workspaceAttachments) file.sourceUri}
          : {},
    );
  }

  /// Prepare API messages with all injections applied.
  /// [requiredAttachmentMessageId] identifies a new submission; retries and
  /// historical context can legitimately reference attachments since removed.
  Future<PreparedGeneration> prepareApiMessagesWithInjections({
    required List<ChatMessage> messages,
    required Map<String, int> versionSelections,
    required Conversation? currentConversation,
    required SettingsProvider settings,
    required Assistant? assistant,
    required String? assistantId,
    required String providerKey,
    required String modelId,
    bool omitImages = false,
    ToolApprovalService? approvalService,
    AskUserInteractionService? askUserService,
    String? processingMessageId,
    String? requiredAttachmentMessageId,
  }) async {
    var requestRevision = currentConversation == null
        ? null
        : chatService.contextRevision(currentConversation.id);
    final instructions = contextProvider.read<InstructionInjectionProvider?>();
    final worldBooks = contextProvider.read<WorldBookProvider?>();
    await instructions?.initialize();
    await worldBooks?.initialize();
    final configuration = contextUsageConfiguration(
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      assistantId: assistantId,
      instructions: instructions,
      worldBooks: worldBooks,
      conversation: currentConversation == null
          ? null
          : chatService.getConversation(currentConversation.id) ??
                currentConversation,
    );
    final requestConfiguration = (
      settings: configuration.settings,
      memorySnapshotHash: await readContextMemorySnapshotHash(
        repository: chatService.chatRepositoryOrNull,
        settings: settings,
        assistant: assistant,
      ),
    );
    final packed = await assembleUnprocessedRequestContext(
      messages: messages,
      versionSelections: versionSelections,
      currentConversation: currentConversation,
      settings: settings,
      assistant: assistant,
      assistantId: assistantId,
      providerKey: providerKey,
      modelId: modelId,
      requiredAttachmentMessageId: requiredAttachmentMessageId,
      onWorldBookActivationPersisted: (before, after) {
        // Accept only this preparation's own write. A history edit before or
        // during persistence invalidates provenance and must not be rebased.
        requestRevision = requestRevision == before && after == before + 1
            ? after
            : null;
      },
    );
    final cfg = packed.cfg;
    final apiMessages = packed.apiMessages;
    final toolDefs = packed.toolDefs;
    final hasBuiltInSearch = packed.hasBuiltInSearch;
    final workspaceContext = packed.workspaceContext;
    final mcpRouteSnapshot = packed.mcpRouteSnapshot;
    final workspaceAttachments = packed.workspaceAttachments;
    final nativePdfInput = ModelSpecResolver.instance
        .spec(cfg, modelId)
        .supportsPdfInput;
    final sandboxDataFiles = BuiltInToolsHelper.sendsDataFilesToSandbox(
      cfg: cfg,
      modelId: modelId,
      clientTools: toolDefs,
    );
    final resolvedWorkspace = workspaceContext;
    final hasWorkspaceFileTools =
        resolvedWorkspace != null &&
        !resolvedWorkspace.skillsOnly &&
        toolDefs.any((tool) {
          final name = (tool['function'] as Map?)?['name'];
          return (name == 'read_file' || name == 'shell') &&
              resolvedWorkspace.workspace.isToolEnabled(name as String);
        });
    final localAttachments = <String, AttachmentInfo>{
      for (final file in workspaceAttachments) file.sourceUri: file,
    };
    final indicatorMessageId =
        processingMessageId != null &&
            messageBuilderService.hasPendingAttachmentWork(
              apiMessages,
              settings,
              conversation: currentConversation,
              sourceMessages: messages,
              sandboxDataFiles: sandboxDataFiles,
              nativePdfInput: nativePdfInput,
              workspaceAttachments: localAttachments,
              useWorkspaceForDocuments: hasWorkspaceFileTools,
            )
        ? processingMessageId
        : null;
    List<String> lastUserImagePaths;
    if (indicatorMessageId != null) {
      onFileProcessingStarted?.call(indicatorMessageId);
    }
    try {
      lastUserImagePaths = await messageBuilderService
          .processUserMessagesForApi(
            apiMessages,
            settings,
            assistant,
            conversation: currentConversation,
            sourceMessages: messages,
            sandboxDataFiles: sandboxDataFiles,
            nativePdfInput: nativePdfInput,
            workspaceAttachments: localAttachments,
            useWorkspaceForDocuments: hasWorkspaceFileTools,
          );
    } on AttachmentReadError catch (e) {
      if (resolvedWorkspace != null &&
          !resolvedWorkspace.skillsOnly &&
          !hasWorkspaceFileTools &&
          e.problem != AttachmentProblem.missing) {
        throw AttachmentReadError(AttachmentProblem.workspace, e.name);
      }
      rethrow;
    } finally {
      if (indicatorMessageId != null) {
        onFileProcessingFinished?.call(indicatorMessageId);
      }
    }

    RequestImageContext? imageContext;
    if (currentConversation != null &&
        (omitImages ||
            (!ChatApiService.supportsOpenAIImagesApiRouting(cfg, modelId) &&
                !shouldUseZhipuLayoutParsing(cfg, modelId)))) {
      imageContext = await _imageContext(
        currentConversation.id,
        messages,
        packed,
        settings,
        modelId,
        omitImages: omitImages,
      );
      lastUserImagePaths = await imageContext.prepareMessages(
        apiMessages,
        lastUserImagePaths,
        parseMarkdownImages: settings.sendMarkdownImageLinksAsImages,
        allowRemoteImages: imageContext.allowsRemoteUserImages,
      );
    } else {
      await messageBuilderService.inlineLocalImages(apiMessages);
    }

    if (ContextLogger.enabled) {
      final providerName = cfg.name.trim();
      ContextLogger.logPrepared(
        apiMessages: apiMessages,
        conversationId: currentConversation?.id ?? '',
        assistantName: assistant?.name ?? '',
        provider: providerName.isNotEmpty ? providerName : providerKey,
        model: modelId,
      );
    }
    messageBuilderService.stripInternalRevisionIds(apiMessages);

    final onToolCall = toolDefs.isNotEmpty
        ? generationController.buildToolCallHandler(
            settings,
            assistant,
            approvalService: approvalService,
            askUserService: askUserService,
            conversationId: currentConversation?.id,
            mcpRouteSnapshot: mcpRouteSnapshot,
            workspaceContext: workspaceContext,
          )
        : null;

    return PreparedGeneration(
      apiMessages: apiMessages,
      toolDefs: toolDefs,
      onToolCall: onToolCall,
      hasBuiltInSearch: hasBuiltInSearch,
      lastUserImagePaths: lastUserImagePaths,
      contextUsageConfiguration: omitImages ? null : requestConfiguration,
      contextUsageRevision: requestRevision,
      imageContext: imageContext,
    );
  }

  UiContextSubmission? _uiContext(ChatInputData input) {
    final attachment = input.uiContext;
    return attachment == null
        ? null
        : UiContextSubmission(
            attachment,
            omittedText: AppLocalizations.of(contextProvider)!.genuiChipOmitted,
          );
  }

  /// Estimate the same frozen payload that sending would persist. The final
  /// write still revalidates its source atomically; previews never save a draft
  /// or substitute newer values from an interactive surface.
  Future<List<MessagePart>> buildUserMessagePreviewParts(
    ChatInputData input, {
    required Assistant? assistant,
  }) async {
    final quoteMarker = input.quotes.isEmpty
        ? null
        : AppLocalizations.of(contextProvider)!.selectionQuoteMarker;
    final uiContext = _uiContext(input);
    final body = await buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    if (input.quotes.isNotEmpty && body.first is TextPart) {
      body[0] = TextPart(
        formatQuotedMessage(
          (body.first as TextPart).text,
          input.quotes,
          quoteMarker: quoteMarker!,
        ),
      );
    }
    if (uiContext == null) return body;
    final source = uiContext.attachment.source;
    final current =
        source != null && await chatService.isUiContextCurrent(source);
    return uiContext.resolve(body, sourceIsCurrent: current);
  }

  /// Create user message from input data.
  Future<ChatMessage> createUserMessage({
    required String conversationId,
    required ChatInputData input,
    required Assistant? assistant,
  }) async {
    final uiContext = _uiContext(input);
    final parts = await MessageGenerationService.buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'user',
      // A composer submission's message carries the submission id, the
      // same invariant the generation path keeps, so the draft store can
      // consume the draft instead of restoring the sent text.
      id: input.draftSubmission?.id,
      parts: parts,
      quotes: input.quotes,
      uiContext: uiContext,
    );
  }

  Future<
    ({ChatMessage userMessage, ChatMessage assistantMessage, String? runId})
  >
  beginSendGeneration({
    required String conversationId,
    required ChatInputData input,
    required Assistant? assistant,
    required String modelId,
    required String providerKey,
    String? senderId,
  }) async {
    final uiContext = _uiContext(input);
    final userParts = await buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    if (chatService.isTemporaryConversation(conversationId)) {
      final userMessage = await chatService.addMessage(
        conversationId: conversationId,
        role: 'user',
        parts: userParts,
        quotes: input.quotes,
        uiContext: uiContext,
      );
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
        senderId: senderId,
      );
      return (
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        runId: null,
      );
    }
    final result = await chatService.beginSendGeneration(
      conversationId: conversationId,
      userParts: userParts,
      quotes: input.quotes,
      modelId: modelId,
      providerId: providerKey,
      draftSubmission: input.draftSubmission,
      uiContext: uiContext,
      senderId: senderId,
    );
    return (
      userMessage: result.userMessage!,
      assistantMessage: result.assistantMessage,
      runId: result.run.id,
    );
  }

  Future<({ChatMessage assistantMessage, String? runId})> beginRegeneration({
    required String conversationId,
    required String modelId,
    required String providerKey,
    required String groupId,
    required int version,
    required bool truncateFuture,
    String? expectedContextState,
  }) async {
    if (chatService.isTemporaryConversation(conversationId)) {
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
        groupId: groupId,
        version: version,
      );
      return (assistantMessage: assistantMessage, runId: null);
    }
    final result = await chatService.beginRegeneration(
      expectedContextState: expectedContextState,
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerKey,
      groupId: groupId,
      version: version,
      truncateFuture: truncateFuture,
    );
    return (assistantMessage: result.assistantMessage, runId: result.run.id);
  }

  Future<({ChatMessage assistantMessage, String? runId})>
  beginAssistantGeneration({
    required String conversationId,
    required String modelId,
    required String providerKey,
    required String anchorGroupId,
    required bool truncateFuture,
    String? expectedContextState,
  }) async {
    if (chatService.isTemporaryConversation(conversationId)) {
      final assistantMessage = await createAssistantPlaceholder(
        conversationId: conversationId,
        modelId: modelId,
        providerKey: providerKey,
        temporaryAfterGroupId: anchorGroupId,
      );
      return (assistantMessage: assistantMessage, runId: null);
    }
    final result = await chatService.beginAssistantGeneration(
      expectedContextState: expectedContextState,
      conversationId: conversationId,
      modelId: modelId,
      providerId: providerKey,
      anchorGroupId: anchorGroupId,
      truncateFuture: truncateFuture,
    );
    return (assistantMessage: result.assistantMessage, runId: result.run.id);
  }

  /// Build structured parts for a persisted user message.
  ///
  /// Text is always present (possibly empty). Attachments follow in the
  /// user's selection order. No legacy attachment markers are produced.
  static Future<List<MessagePart>> buildPersistedUserMessageParts(
    ChatInputData input, {
    required Assistant? assistant,
  }) async {
    String transform(String text) => applyAssistantRegexes(
      text,
      assistant: assistant,
      scope: AssistantRegexScope.user,
      target: AssistantRegexTransformTarget.persist,
    );
    final processedUserText = input.quotes.isEmpty
        ? transform(input.text.trim())
        : input.text
              .trim()
              .split(quotePlaceholder)
              .map(transform)
              .join(quotePlaceholder);

    final parts = <MessagePart>[TextPart(processedUserText)];
    for (final path in input.imagePaths) {
      parts.add(
        ImagePart(
          uri: SandboxPathResolver.canonicalize(path),
          mime: await inferAttachmentMime(uri: path),
        ),
      );
    }
    for (final document in input.documents) {
      parts.add(
        FilePart(
          uri: SandboxPathResolver.canonicalize(document.path),
          name: document.fileName,
          mime: await inferAttachmentMime(
            uri: document.path,
            explicitMime: document.mime,
            fileName: document.fileName,
          ),
        ),
      );
    }
    return parts;
  }

  /// Derived text body for callers that still need a plain string.
  static Future<String> buildPersistedUserMessageContent(
    ChatInputData input, {
    required Assistant? assistant,
  }) async {
    final parts = await buildPersistedUserMessageParts(
      input,
      assistant: assistant,
    );
    return parts.whereType<TextPart>().map((part) => part.text).join();
  }

  /// Create assistant message placeholder.
  Future<ChatMessage> createAssistantPlaceholder({
    required String conversationId,
    required String modelId,
    required String providerKey,
    String? groupId,
    int version = 0,
    String? temporaryAfterGroupId,
    String? senderId,
  }) async {
    return chatService.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      modelId: modelId,
      providerId: providerKey,
      isStreaming: true,
      groupId: groupId,
      version: version,
      selectVersion: groupId != null,
      temporaryAfterGroupId: temporaryAfterGroupId,
      senderId: senderId,
    );
  }

  /// Initialize reasoning state for a message if reasoning is enabled.
  Future<void> initializeReasoningState({
    required String messageId,
    required bool enableReasoning,
  }) async {
    if (enableReasoning) {
      final rd = stream_ctrl.ReasoningData();
      streamController.reasoning[messageId] = rd;
      await chatService.updateMessage(
        messageId,
        reasoningStartAt: DateTime.now(),
      );
    }
  }

  /// Build GenerationContext for streaming.
  stream_ctrl.GenerationContext buildGenerationContext({
    required ChatMessage assistantMessage,
    required PreparedGeneration prepared,
    required List<String> userImagePaths,
    required bool allowImagesApiRouting,
    required String providerKey,
    required String modelId,
    required Assistant? assistant,
    required SettingsProvider settings,
    required bool supportsReasoning,
    required bool enableReasoning,
    required bool generateTitleOnFinish,
    String? generationRunId,
    bool isContinuation = false,
    bool scheduled = false,
    bool scheduledNotify = true,
    bool scheduledPreview = true,
  }) {
    final bool ocrActive = settings.ocrActive;

    return stream_ctrl.GenerationContext(
      assistantMessage: assistantMessage,
      imageContext: prepared.imageContext
        ?..targetMessageId = assistantMessage.id,
      apiMessages: prepared.apiMessages,
      contextUsageConfiguration: prepared.contextUsageConfiguration,
      contextUsageRevision: prepared.contextUsageRevision,
      userImagePaths:
          prepared.imageContext?.preparePaths(
            userImagePaths,
            allowRemoteImages: prepared.imageContext!.allowsRemoteUserImages,
          ) ??
          userImagePaths,
      allowImagesApiRouting: allowImagesApiRouting,
      providerKey: providerKey,
      modelId: modelId,
      assistant: assistant,
      settings: settings,
      config: settings.getProviderConfig(providerKey),
      toolDefs: prepared.toolDefs,
      onToolCall: prepared.onToolCall,
      extraHeaders: buildConversationRequestHeaders(
        conversationId: assistantMessage.conversationId,
        customHeaders: generationController.buildCustomHeaders(assistant),
      ),
      extraBody: generationController.buildCustomBody(assistant),
      serviceTier: ConversationResponseSpeed.requestTier(
        chatService.getConversation(assistantMessage.conversationId),
        settings.getProviderConfig(providerKey),
        modelId,
      ),
      supportsReasoning: supportsReasoning,
      enableReasoning: enableReasoning,
      streamOutput: assistant?.streamOutput ?? true,
      ocrActive: ocrActive,
      generateTitleOnFinish: generateTitleOnFinish,
      generationRunId: generationRunId,
      isContinuation: isContinuation,
      scheduled: scheduled,
      scheduledNotify: scheduledNotify,
      scheduledPreview: scheduledPreview,
    );
  }

  /// Get the model this conversation sends with: the conversation's own
  /// override, else the assistant's model, else the global default.
  ({String? providerKey, String? modelId}) getModelConfig(
    SettingsProvider settings,
    Assistant? assistant, {
    Conversation? conversation,
  }) => resolveChatModel(
    settings,
    conversation: conversation,
    assistant: assistant,
  );

  /// Calculate version info for regeneration.
  ({String? targetGroupId, int nextVersion, int lastKeep})
  calculateRegenerationVersioning({
    required ChatMessage message,
    required List<ChatMessage> messages,
    required bool assistantAsNewReply,
  }) {
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) {
      return (targetGroupId: null, nextVersion: 0, lastKeep: -1);
    }

    String? targetGroupId;
    int nextVersion = 0;
    int lastKeep;

    if (message.role == 'assistant') {
      lastKeep = idx;
      if (assistantAsNewReply) {
        targetGroupId = null;
        nextVersion = 0;
      } else {
        targetGroupId = message.groupId ?? message.id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      }
    } else {
      // User message
      final userGroupId = message.groupId ?? message.id;
      int userFirst = -1;
      for (int i = 0; i < messages.length; i++) {
        final gid0 = (messages[i].groupId ?? messages[i].id);
        if (gid0 == userGroupId) {
          userFirst = i;
          break;
        }
      }
      if (userFirst < 0) userFirst = idx;

      int aid = -1;
      for (int i = userFirst + 1; i < messages.length; i++) {
        final candidateGroupId = messages[i].groupId ?? messages[i].id;
        if (candidateGroupId == userGroupId) continue;
        if (messages[i].role == 'assistant') {
          aid = i;
        }
        break;
      }

      if (aid >= 0) {
        lastKeep = aid;
        targetGroupId = messages[aid].groupId ?? messages[aid].id;
        int maxVer = -1;
        for (final m in messages) {
          final gid = (m.groupId ?? m.id);
          if (gid == targetGroupId) {
            if (m.version > maxVer) maxVer = m.version;
          }
        }
        nextVersion = maxVer + 1;
      } else {
        lastKeep = userFirst;
        targetGroupId = null;
        nextVersion = 0;
      }
    }

    return (
      targetGroupId: targetGroupId,
      nextVersion: nextVersion,
      lastKeep: lastKeep,
    );
  }

  /// Remove trailing messages after regeneration cut point.
  @visibleForTesting
  static List<String> collectTrailingMessageIdsForRemoval({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) {
    if (lastKeep >= messages.length - 1) {
      return const [];
    }

    final keepGroups = <String>{};
    for (int i = 0; i <= lastKeep && i < messages.length; i++) {
      keepGroups.add(messages[i].groupId ?? messages[i].id);
    }
    if (targetGroupId != null) keepGroups.add(targetGroupId);

    final removeIds = <String>[];
    for (final message in messages.sublist(lastKeep + 1)) {
      final groupId = message.groupId ?? message.id;
      if (!keepGroups.contains(groupId)) {
        removeIds.add(message.id);
      }
    }
    return removeIds;
  }

  /// Remove trailing messages after regeneration cut point.
  Future<List<String>> removeTrailingMessages({
    required List<ChatMessage> messages,
    required int lastKeep,
    required String? targetGroupId,
  }) async {
    final removeIds = collectTrailingMessageIdsForRemoval(
      messages: messages,
      lastKeep: lastKeep,
      targetGroupId: targetGroupId,
    );

    var deletedIds = removeIds;
    if (removeIds.isNotEmpty && messages.isNotEmpty) {
      final removeIdSet = removeIds.toSet();
      final conversationId = messages.first.conversationId;
      final selectionChanges = <String, int?>{};
      for (final message in messages) {
        if (removeIdSet.contains(message.id)) {
          selectionChanges[message.groupId ?? message.id] = null;
        }
      }
      deletedIds = (await chatService.deleteMessages(
        conversationId: conversationId,
        messageIds: removeIdSet,
        versionSelectionChanges: selectionChanges,
      )).toList(growable: false);
    }
    for (final id in deletedIds) {
      streamController.reasoning.remove(id);
      streamController.toolParts.remove(id);
      streamController.reasoningSegments.remove(id);
    }

    return deletedIds;
  }

  String _effectiveAttachmentMime(DocumentAttachment attachment) {
    return resolveDocumentAttachmentMime(attachment);
  }

  /// Image / audio / video the [spec] can read. Documents are never included.
  @visibleForTesting
  static List<String> filterMediaPathsForProvider(
    List<String> paths, {
    required ModelSpec spec,
  }) {
    return [
      for (final path in paths)
        if (_specAcceptsGatedMediaPath(path, spec)) path,
    ];
  }

  static bool _specAcceptsGatedMediaPath(String path, ModelSpec spec) {
    final mime = inferMediaMimeFromSource(path, fallbackMime: 'image/png');
    if (isAudioMime(mime)) return spec.supportsAudioInput;
    if (isVideoMime(mime)) return spec.supportsVideoInput;
    if (isImageMime(mime)) return spec.supportsImageInput;
    return false;
  }

  /// Build user image paths considering OCR mode.
  List<String> buildUserImagePaths({
    required ChatInputData? input,
    required List<String> lastUserImagePaths,
    required SettingsProvider settings,
    required String providerKey,
    required String modelId,
  }) {
    final bool ocrActive = settings.ocrActive;
    final spec = ModelSpecResolver.instance.spec(
      settings.getProviderConfig(providerKey),
      modelId,
    );

    if (input != null) {
      final currentMediaPaths = <String>[];
      for (final d in input.documents) {
        final effectiveMime = _effectiveAttachmentMime(d);
        if (isVideoMime(effectiveMime) || isAudioMime(effectiveMime)) {
          currentMediaPaths.add(d.path);
        }
      }
      return filterMediaPathsForProvider(<String>[
        if (!ocrActive) ...input.imagePaths,
        ...currentMediaPaths,
      ], spec: spec);
    }

    return filterMediaPathsForProvider(
      lastUserImagePaths
          .where((path) {
            if (!ocrActive) return true;
            return !isImageMime(
              inferMediaMimeFromSource(path, fallbackMime: 'image/png'),
            );
          })
          .toList(growable: false),
      spec: spec,
    );
  }

  Future<WorkspaceToolContext?> _skillsOnlyContext({
    required Assistant? assistant,
    required Conversation? conversation,
  }) async {
    try {
      final skillsService = contextProvider.read<SkillsService>();
      await skillsService.loaded;
      final override = conversation == null
          ? null
          : SkillsBinding.fromExtras(conversation.extras).skillIds;
      final skills = skillsService.resolveForAssistant(
        assistant,
        conversationOverride: override,
      );
      if (skills.isEmpty) return null;
      return WorkspaceToolContext.skillsOnly(
        skillsHostDir: skillsService.skillsDirectory.path,
        conversationId: conversation?.id,
        assistantId: conversation?.assistantId,
      );
    } catch (_) {
      return null;
    }
  }
}
