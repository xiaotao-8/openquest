import 'dart:async';

/// A bounded-choice question a Bot embeds in its reply so the app can
/// render a Minis-style `user_ask` card instead of leaving an open-ended
/// question in plain text. Model-agnostic: any model just emits a fenced
/// block in its reply:
///
/// ```ask
/// 问题文本（需要多选时在问题里注明可多选）
/// - 短标签 | 一行说明
/// - 短标签 | 一行说明
/// ```
///
/// The first non-empty line is the question; each following line must be
/// a list item (`- `, `• `, `* ` or `1. ` style) holding a short label
/// and an optional one-line description after `|`. 2-4 options make a
/// choice card; a block with only the question renders as an open
/// question card. Anything malformed is left as plain text.
class AskOption {
  final String label;
  final String? description;
  const AskOption({required this.label, this.description});
}

class AskOptions {
  final String question;
  final List<AskOption> options;
  final bool multiSelect;
  const AskOptions({
    required this.question,
    required this.options,
    this.multiSelect = false,
  });
}

/// Result of pulling an `ask` block out of a message body.
class AskOptionsParse {
  final String textWithoutBlock;
  final AskOptions ask;
  const AskOptionsParse({required this.textWithoutBlock, required this.ask});
}

final RegExp _askBlockPattern = RegExp(r'```ask[ \t]*\r?\n([\s\S]*?)\r?\n?```');
final RegExp _optionLinePattern = RegExp(r'^(?:[-•*]|\d{1,2}[.、)])\s+(.+)$');

/// Parse [text] for a completed `ask` block. Returns null when there is
/// no block or the block is malformed (a single option line, non-list
/// lines), in which case the text renders unchanged.
AskOptionsParse? parseAskOptions(String text) {
  final match = _askBlockPattern.firstMatch(text);
  if (match == null) return null;
  final body = match.group(1) ?? '';
  final lines = body
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  final options = <AskOption>[];
  for (final line in lines.skip(1)) {
    final m = _optionLinePattern.firstMatch(line);
    if (m == null) return null;
    final content = m.group(1)!.trim();
    if (content.isEmpty) return null;
    final split = content.split(RegExp(r'[|｜]'));
    final label = split.first.trim();
    if (label.isEmpty) return null;
    final description = split.length > 1
        ? split.sublist(1).join('|').trim()
        : null;
    options.add(
      AskOption(
        label: label,
        description: (description == null || description.isEmpty)
            ? null
            : description,
      ),
    );
  }
  if (options.length == 1 || options.length > 4) return null;
  final question = lines.first;
  final without = (text.substring(0, match.start) + text.substring(match.end))
      .trim();
  return AskOptionsParse(
    textWithoutBlock: without,
    ask: AskOptions(
      question: question,
      options: options,
      multiSelect: question.contains('可多选'),
    ),
  );
}

/// Tap events from rendered ask cards. The home page subscribes and
/// forwards the chosen answer through its normal send path, so the Bot
/// receives it as the user's next message and continues.
class AskOptionsBus {
  AskOptionsBus._();
  static final AskOptionsBus instance = AskOptionsBus._();

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get selections => _controller.stream;

  void select(String answer) {
    if (answer.trim().isEmpty) return;
    _controller.add(answer);
  }
}
