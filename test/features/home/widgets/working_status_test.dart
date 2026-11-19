import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/features/home/widgets/working_status.dart';
import 'package:Kelivo/l10n/app_localizations_zh.dart';

ChatMessage _message(List<MessagePart> parts) => ChatMessage(
  role: 'assistant',
  conversationId: 'c1',
  parts: parts,
  isStreaming: true,
);

void main() {
  final l10n = AppLocalizationsZh();

  group('describeBotAction tool detail', () {
    test('search shows the real query', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"search_web","arguments":{"query":"杨枝甘露 配方比例"}}',
          ),
        ]),
        l10n,
      );
      expect(action, contains('杨枝甘露 配方比例'));
      expect(action, startsWith('联网检索'));
    });

    test('fetch shows the host', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"fetch_url","arguments":{"url":"https://example.com/menu?id=1"}}',
          ),
        ]),
        l10n,
      );
      expect(action, contains('example.com'));
    });

    test('command shows the exact command from string arguments', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"bash","arguments":"{\\"command\\":\\"ls -la /opt\\"}"}',
          ),
        ]),
        l10n,
      );
      expect(action, '运行命令：ls -la /opt');
    });

    test('read shows the file path', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"read_file","arguments":{"path":"/work/menu.md"}}',
          ),
        ]),
        l10n,
      );
      expect(action, '读取文件：/work/menu.md');
    });

    test('server tool names the tool and the server', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"deploy","arguments":{},"server":"ecs-hk"}',
          ),
        ]),
        l10n,
      );
      expect(action, '服务器工具：deploy（ecs-hk）');
    });

    test('app_settings names the setting key', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart(
            '{"id":"a","name":"app_settings","arguments":{"key":"theme_mode"}}',
          ),
        ]),
        l10n,
      );
      expect(action, contains('theme_mode'));
    });

    test('unknown tool falls back to its name, never a bare generic', () {
      final action = describeBotAction(
        _message(const [
          ToolCallPart('{"id":"a","name":"make_chart","arguments":{}}'),
        ]),
        l10n,
      );
      expect(action, contains('make_chart'));
    });
  });

  group('describeBotAction non-tool states', () {
    test('reasoning only reads as thinking', () {
      expect(
        describeBotAction(_message(const [ReasoningPart('想一想')]), l10n),
        '正在思考',
      );
    });

    test('streaming text reads as replying', () {
      expect(describeBotAction(_message(const [TextPart('好的')]), l10n), '正在回复');
    });

    test('a running tool call wins over earlier reasoning', () {
      final action = describeBotAction(
        _message(const [
          ReasoningPart('先查一下'),
          ToolCallPart(
            '{"id":"a","name":"search_web","arguments":{"query":"q1"}}',
          ),
        ]),
        l10n,
      );
      expect(action, contains('q1'));
    });
  });
}
