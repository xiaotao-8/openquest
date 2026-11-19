import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/message_generation_service.dart';
import 'package:Kelivo/features/intelligent_ui/protocol/ui_stream_parser.dart';

const brokenFence = '''
前文
```openquest-ui
ui 1 catalog "openquest.native/1"
root = Column(children=[form,result])
\$vote: string? = null
\$options = [
  {"value":"a","label":"甲"},
  {"value":"b","label":"乙"}
]
form = Form(children=[radio], title="选哪个？")
radio = RadioGroup(bind=\$vote, label="你的选择", options=\$options, required=true)
let name = \$vote == "a" ? "甲" : "乙"
result = Metric(label="你选了", value="选了" + name, unit="项")
```
后文''';

const validFence = '''
```openquest-ui
ui 1 catalog "openquest.native/1"
\$choice: string = "A"
root = Column(children=[intro,form,ask])
intro = Text(text="夏日新口味投票", variant="caption")
form = Form(children=[voteGroup])
voteGroup = RadioGroup(label="选一款你最想尝鲜的口味", bind=\$choice, options=[{"value":"A","label":"青岚浮雪"},{"value":"B","label":"暮色柑橘"}], required=true)
ask = Button(label="提交投票", form=form, action=Ask(text="我选了这款口味", context={"choice":\$choice}))
```''';

void main() {
  group('sanitizeInvalidUiFences', () {
    test('the paradigm card itself parses clean', () {
      final body = validCardParadigm
          .split('\n')
          .skip(1)
          .toList()
          .reversed
          .skip(1)
          .toList()
          .reversed
          .join('\n');
      final snapshot = UiStreamParser().update(body, closed: true);
      expect(snapshot.invalid, isFalse);
      expect(snapshot.program.diagnostics, isEmpty);
    });

    test('replaces a broken historical fence with the paradigm in place', () {
      // Shape copied from a real defective reply: multi-line untyped array
      // state, options bound from state, string concatenation, and a string
      // Metric value. The parser rejects it. Diagnosis (2026-11-19) showed
      // deleting it leaves a prose-only "card reply" the model imitates, so
      // the fence is swapped for a valid paradigm, prose kept.
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': brokenFence},
      ];
      sanitizeInvalidUiFences(messages);
      final content = messages.first['content'] as String;
      expect(content, contains(validCardParadigm));
      expect(content, isNot(contains('\$options')));
      expect(content, contains('前文'));
      expect(content, contains('后文'));
    });

    test('keeps a valid fence byte-identical and adds nothing', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': validFence},
        {'role': 'user', 'content': '继续'},
      ];
      sanitizeInvalidUiFences(messages);
      expect(messages.length, 2);
      expect(messages.first['content'], validFence);
    });

    test('sanitizes text nested in content parts', () {
      final messages = <Map<String, dynamic>>[
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'text',
              'text':
                  '```openquest-ui\nui 1 catalog "openquest.native/1"\nroot = Column(children=[missing])\n```',
            },
          ],
        },
      ];
      sanitizeInvalidUiFences(messages);
      final parts = messages.first['content'] as List;
      final text = (parts.single as Map)['text'] as String;
      expect(text, validCardParadigm);
    });

    test('swaps the legacy placeholder sentence for the paradigm', () {
      // A reply generated while the sanitizer still substituted a readable
      // placeholder was stored verbatim; the model copied the sentence as
      // the "card format". The sentence becomes a real paradigm card.
      const stored = '结论：做夏日新饮品三选一投票卡喵。\n\n（此处有一张交互卡片，源码略）\n\n**点选立即显示结果喵**～';
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': stored},
      ];
      sanitizeInvalidUiFences(messages);
      final content = messages.first['content'] as String;
      expect(content, isNot(contains('此处有一张交互卡片')));
      expect(content, contains(validCardParadigm));
      expect(content, contains('结论：做夏日新饮品三选一投票卡喵。'));
    });

    test('inserts a paradigm exchange before the final user message '
        'when repairs happened and no fence was natively valid', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': brokenFence},
        {'role': 'user', 'content': '再做一个投票卡'},
      ];
      sanitizeInvalidUiFences(messages);
      expect(messages.length, 4);
      expect(messages[1]['role'], 'user');
      expect(messages[2]['role'], 'assistant');
      expect(messages[2]['content'], contains(validCardParadigm));
      expect(messages[3]['content'], '再做一个投票卡');
    });

    test('no insertion when a natively valid fence exists in history', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': brokenFence},
        {'role': 'assistant', 'content': validFence},
        {'role': 'user', 'content': '继续'},
      ];
      sanitizeInvalidUiFences(messages);
      expect(messages.length, 3);
      expect(messages[1]['content'], validFence);
    });

    test('leaves plain text and unclosed fences untouched', () {
      const plain = '没有卡片的一条消息';
      const unclosed = '```openquest-ui\nui 1 catalog "openquest.native/1"\n';
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': plain},
        {'role': 'assistant', 'content': unclosed},
      ];
      sanitizeInvalidUiFences(messages);
      expect(messages.length, 2);
      expect(messages[0]['content'], plain);
      expect(messages[1]['content'], unclosed);
    });
  });
}
