import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation_prompt_settings.dart';
import 'package:Kelivo/core/models/group_chat_meta.dart';
import 'package:Kelivo/core/services/api/request_image_context.dart';
import 'package:flutter_test/flutter_test.dart';

Assistant bot(
  String id,
  String name, {
  String systemPrompt = '',
  String speakingStyle = '',
  String personaRules = '',
}) => Assistant(
  id: id,
  name: name,
  systemPrompt: systemPrompt,
  speakingStyle: speakingStyle,
  personaRules: personaRules,
);

void main() {
  group('Soul composition', () {
    test('persona + style + rules join in order, skipping empties', () {
      final a = bot(
        'a',
        'A',
        systemPrompt: 'You are a chef.',
        speakingStyle: 'Short, cheerful sentences.',
        personaRules: 'Never reveal the recipe.',
      );
      expect(
        a.effectiveSoulPrompt,
        'You are a chef.\n\n'
        'Short, cheerful sentences.\n\n'
        'Never reveal the recipe.',
      );
    });

    test('only style set still produces a prompt', () {
      final a = bot('a', 'A', speakingStyle: 'Speaks in haiku.');
      expect(a.effectiveSoulPrompt, 'Speaks in haiku.');
    });

    test('all empty produces empty prompt', () {
      expect(bot('a', 'A').effectiveSoulPrompt, '');
    });

    test('effectiveSystemPrompt uses the composed Soul', () {
      const settings = ConversationPromptSettings();
      final a = bot(
        'a',
        'A',
        systemPrompt: 'Persona.',
        personaRules: 'Rule one.',
      );
      expect(settings.effectiveSystemPrompt(a), 'Persona.\n\nRule one.');
    });

    test('conversation override still wins when allowed', () {
      const settings = ConversationPromptSettings(systemPrompt: 'Override.');
      final a = bot(
        'a',
        'A',
        systemPrompt: 'Persona.',
      ).copyWith(allowConversationSystemPrompt: true);
      expect(settings.effectiveSystemPrompt(a), 'Override.');
    });

    test('Soul fields survive JSON round-trip (persistence)', () {
      final a = bot(
        'a',
        'A',
        systemPrompt: 'P',
        speakingStyle: 'S',
        personaRules: 'R',
      );
      final restored = Assistant.fromJson(a.toJson());
      expect(restored.speakingStyle, 'S');
      expect(restored.personaRules, 'R');
      expect(restored.effectiveSoulPrompt, 'P\n\nS\n\nR');
    });

    test('legacy JSON without Soul fields defaults to empty', () {
      final restored = Assistant.fromJson({'id': 'x', 'name': 'Legacy'});
      expect(restored.speakingStyle, '');
      expect(restored.personaRules, '');
    });
  });

  group('GroupChatMeta', () {
    test('extras round-trip', () {
      const meta = GroupChatMeta(isGroup: true, memberIds: ['b1', 'b2']);
      final extras = meta.applyTo({'other': 1});
      final restored = GroupChatMeta.fromExtras(extras);
      expect(restored.isGroup, isTrue);
      expect(restored.memberIds, ['b1', 'b2']);
      expect(extras['other'], 1);
    });

    test('non-group extras parse as not a group', () {
      final meta = GroupChatMeta.fromExtras(const {});
      expect(meta.isGroup, isFalse);
      expect(meta.memberIds, isEmpty);
    });

    test('side chat flag', () {
      expect(
        GroupChatMeta.isSideChat({GroupChatMeta.sideChatKey: true}),
        isTrue,
      );
      expect(GroupChatMeta.isSideChat(const {}), isFalse);
    });
  });

  group('parseMention', () {
    final members = [bot('1', 'Chef'), bot('2', 'Chef Pro'), bot('3', 'Poet')];

    test('matches a plain @name', () {
      expect(GroupChatMeta.parseMention('@Chef hi', members)?.id, '1');
    });

    test('longest name wins', () {
      expect(GroupChatMeta.parseMention('@Chef Pro hi', members)?.id, '2');
    });

    test('full-width ＠ also matches', () {
      expect(GroupChatMeta.parseMention('＠Poet hi', members)?.id, '3');
    });

    test('no mention returns null', () {
      expect(GroupChatMeta.parseMention('hello everyone', members), isNull);
    });

    test('mentioning a non-member returns null', () {
      expect(GroupChatMeta.parseMention('@Stranger hi', members), isNull);
    });
  });

  group('mapGroupHistoryForBot', () {
    ChatMessage msg(String id, String role, String text, {String? senderId}) =>
        ChatMessage(
          id: id,
          role: role,
          content: text,
          conversationId: 'g1',
          senderId: senderId,
        );

    Map<String, dynamic> api(String id, String role, String text) => {
      'role': role,
      'content': text,
      imageContextOwnerKey: id,
    };

    test('own replies stay assistant, other Bots become named user turns', () {
      final sources = [
        msg('m1', 'user', 'hello'),
        msg('m2', 'assistant', 'from chef', senderId: 'chef'),
        msg('m3', 'assistant', 'from poet', senderId: 'poet'),
        msg('m4', 'assistant', 'legacy reply'),
      ];
      final apiMessages = [
        api('m1', 'user', 'hello'),
        api('m2', 'assistant', 'from chef'),
        api('m3', 'assistant', 'from poet'),
        api('m4', 'assistant', 'legacy reply'),
      ];
      final out = mapGroupHistoryForBot(
        apiMessages: apiMessages,
        sourceMessages: sources,
        selfAssistantId: 'chef',
        nameOf: (id) => {'chef': 'Chef', 'poet': 'Poet'}[id],
      );
      expect(out[0]['role'], 'user');
      expect(out[0]['content'], 'hello');
      expect(out[1]['role'], 'assistant');
      expect(out[1]['content'], 'from chef');
      expect(out[2]['role'], 'user');
      expect(out[2]['content'], 'Poet: from poet');
      // No senderId = the conversation's implied assistant: unchanged.
      expect(out[3]['role'], 'assistant');
      expect(out[3]['content'], 'legacy reply');
    });

    test('system and tool messages pass through untouched', () {
      final out = mapGroupHistoryForBot(
        apiMessages: [
          {'role': 'system', 'content': 'soul'},
        ],
        sourceMessages: const [],
        selfAssistantId: 'chef',
        nameOf: (_) => null,
      );
      expect(out.single['role'], 'system');
      expect(out.single['content'], 'soul');
    });
  });

  group('ChatMessage senderId', () {
    test('copyWith preserves senderId', () {
      final m = ChatMessage(
        role: 'assistant',
        content: 'hi',
        conversationId: 'g1',
        senderId: 'bot-1',
      );
      final copy = m.copyWith(content: 'edited');
      expect(copy.senderId, 'bot-1');
    });

    test('JSON round-trip preserves senderId', () {
      final m = ChatMessage(
        role: 'assistant',
        content: 'hi',
        conversationId: 'g1',
        senderId: 'bot-1',
      );
      expect(ChatMessage.fromJson(m.toJson()).senderId, 'bot-1');
    });
  });
}
