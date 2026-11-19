import '../services/api/request_image_context.dart';
import 'assistant.dart';
import 'chat_message.dart';

/// Group-chat metadata owned by a conversation, persisted in its Drift
/// extras. A group is created by the user, starts with the members the user
/// picked, and is never pre-populated by the app.
class GroupChatMeta {
  static const isGroupKey = 'group.isGroup';
  static const memberIdsKey = 'group.memberIds';
  static const sideChatKey = 'sideChat';
  static const modelModeKey = 'group.modelMode';
  static const unifiedModelKey = 'group.unifiedModel';
  static const memberModelsKey = 'group.memberModels';
  static const avatarKey = 'group.avatar';

  /// Model assignment modes for a group, chosen by the user in the
  /// group settings: each Bot individually, or one model for all.
  static const modelModeIndividual = 'individual';
  static const modelModeUnified = 'unified';

  final bool isGroup;
  final List<String> memberIds;

  /// 'individual' (default) or 'unified'.
  final String modelMode;

  /// 'providerKey|modelId' applied to every member without an
  /// individual assignment, in unified mode.
  final String? unifiedModel;

  /// Per-member 'providerKey|modelId' overrides. An individual
  /// assignment always wins over the unified model, and switching the
  /// mode never discards these.
  final Map<String, String> memberModels;

  /// Group avatar image path chosen by the user; null/empty shows the
  /// name's initial-letter avatar instead.
  final String? avatar;

  const GroupChatMeta({
    this.isGroup = false,
    this.memberIds = const [],
    this.modelMode = modelModeIndividual,
    this.unifiedModel,
    this.memberModels = const {},
    this.avatar,
  });

  factory GroupChatMeta.fromExtras(Map<String, dynamic> extras) {
    final raw = extras[memberIdsKey];
    final rawModels = extras[memberModelsKey];
    return GroupChatMeta(
      isGroup: extras[isGroupKey] == true,
      memberIds: raw is List
          ? raw.whereType<String>().toSet().toList()
          : const [],
      modelMode: extras[modelModeKey] == modelModeUnified
          ? modelModeUnified
          : modelModeIndividual,
      unifiedModel: extras[unifiedModelKey]?.toString(),
      memberModels: rawModels is Map
          ? rawModels.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      avatar: extras[avatarKey]?.toString(),
    );
  }

  Map<String, dynamic> applyTo(Map<String, dynamic> extras) {
    final next = Map<String, dynamic>.from(extras);
    if (isGroup) {
      next[isGroupKey] = true;
      next[memberIdsKey] = List<String>.from(memberIds);
      next[modelModeKey] = modelMode;
      if (unifiedModel != null) {
        next[unifiedModelKey] = unifiedModel;
      } else {
        next.remove(unifiedModelKey);
      }
      if (memberModels.isNotEmpty) {
        next[memberModelsKey] = Map<String, String>.from(memberModels);
      } else {
        next.remove(memberModelsKey);
      }
      if (avatar != null && avatar!.isNotEmpty) {
        next[avatarKey] = avatar;
      } else {
        next.remove(avatarKey);
      }
    } else {
      next.remove(isGroupKey);
      next.remove(memberIdsKey);
      next.remove(modelModeKey);
      next.remove(unifiedModelKey);
      next.remove(memberModelsKey);
      next.remove(avatarKey);
    }
    return next;
  }

  static ({String providerKey, String modelId})? parseModelRef(String? ref) {
    if (ref == null) return null;
    final sep = ref.indexOf('|');
    if (sep <= 0 || sep >= ref.length - 1) return null;
    return (
      providerKey: ref.substring(0, sep),
      modelId: ref.substring(sep + 1),
    );
  }

  static String encodeModelRef(String providerKey, String modelId) =>
      '$providerKey|$modelId';

  /// The model a member must use in this group: its individual
  /// assignment first, then the unified model in unified mode, else
  /// null (the Bot's own configured model).
  ({String providerKey, String modelId})? modelOverrideFor(String memberId) {
    final individual = parseModelRef(memberModels[memberId]);
    if (individual != null) return individual;
    if (modelMode == modelModeUnified) return parseModelRef(unifiedModel);
    return null;
  }

  static bool isSideChat(Map<String, dynamic> extras) =>
      extras[sideChatKey] == true;

  /// Find the group member mentioned in [text] as `@<name>`. Longest names
  /// win so `@Bot` never shadows `@Bot Pro`. Returns null when no member is
  /// mentioned. A mention calls on that member specifically, but it is not
  /// a precondition for a reply: group members take part on their own.
  static Assistant? parseMention(String text, List<Assistant> members) {
    if (!text.contains('@') && !text.contains('＠')) return null;
    final sorted = [...members]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final member in sorted) {
      final name = member.name.trim();
      if (name.isEmpty) continue;
      if (text.contains('@$name') || text.contains('＠$name')) return member;
    }
    return null;
  }

  /// The member whose name appears in [text] even without an @ — calling
  /// someone by name counts as addressing them. Longest names win, as in
  /// [parseMention]. Returns null when no member is named.
  static Assistant? memberNamedInText(String text, List<Assistant> members) {
    final sorted = [...members]
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final member in sorted) {
      final name = member.name.trim();
      if (name.isEmpty) continue;
      if (text.contains(name)) return member;
    }
    return null;
  }

  /// The first `@<name>`-looking token in [text] that matches no member,
  /// or null when every @token names a real member (or there is none).
  /// Tokens containing a dot (e-mail addresses, file names) and the
  /// conventional @所有人 / @all are not treated as member mentions.
  static String? unknownMention(String text, List<Assistant> members) {
    if (!text.contains('@') && !text.contains('＠')) return null;
    final pattern = RegExp(r'[@＠]([^\s@＠,，、。：:；;！!？?·/\\]+)');
    for (final m in pattern.allMatches(text)) {
      final token = m.group(1)!.trim();
      if (token.isEmpty || token.contains('.')) continue;
      if (token == '所有人' || token.toLowerCase() == 'all') continue;
      final known = members.any((a) => a.name.trim() == token);
      if (!known) return token;
    }
    return null;
  }
}

/// Rewrite built API messages for a group conversation so the replying Bot
/// sees the room correctly: its own earlier replies stay `assistant`, other
/// Bots' replies become `user` turns prefixed with the speaker's name, and
/// human messages stay `user`. Pure and side-effect free; returns a new list.
List<Map<String, dynamic>> mapGroupHistoryForBot({
  required List<Map<String, dynamic>> apiMessages,
  required List<ChatMessage> sourceMessages,
  required String selfAssistantId,
  required String? Function(String assistantId) nameOf,
}) {
  final byId = <String, ChatMessage>{for (final m in sourceMessages) m.id: m};
  return [
    for (final message in apiMessages)
      _mapGroupMessage(message, byId, selfAssistantId, nameOf),
  ];
}

Map<String, dynamic> _mapGroupMessage(
  Map<String, dynamic> message,
  Map<String, ChatMessage> byId,
  String selfAssistantId,
  String? Function(String assistantId) nameOf,
) {
  if (message['role'] != 'assistant') return message;
  final ownerId = message[imageContextOwnerKey]?.toString();
  final source = ownerId == null ? null : byId[ownerId];
  final senderId = source?.senderId;
  if (senderId == null || senderId == selfAssistantId) return message;
  final content = message['content'];
  if (content is! String) return message;
  final name = nameOf(senderId) ?? 'Assistant';
  return <String, dynamic>{
    ...message,
    'role': 'user',
    'content': '$name: $content',
  };
}
