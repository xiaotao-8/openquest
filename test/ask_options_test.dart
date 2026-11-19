import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/utils/ask_options.dart';
import 'package:Kelivo/features/chat/widgets/ask_options_card.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  group('parseAskOptions', () {
    test('parses a well-formed ask block and strips it from the text', () {
      const text = '我先确认一下。\n\n```ask\n周末去哪玩？\n- 爬山\n- 看展\n- 宅家\n```';
      final parsed = parseAskOptions(text);
      expect(parsed, isNotNull);
      expect(parsed!.ask.question, '周末去哪玩？');
      expect(parsed.ask.options.map((o) => o.label).toList(), [
        '爬山',
        '看展',
        '宅家',
      ]);
      expect(parsed.ask.multiSelect, isFalse);
      expect(parsed.textWithoutBlock, '我先确认一下。');
    });

    test('accepts numbered options', () {
      const text = '```ask\n选哪个方案？\n1. 方案甲\n2. 方案乙\n```';
      final parsed = parseAskOptions(text);
      expect(parsed, isNotNull);
      expect(parsed!.ask.options.map((o) => o.label).toList(), ['方案甲', '方案乙']);
    });

    test('returns null when there is no ask block', () {
      expect(parseAskOptions('普通回复，没有选项。'), isNull);
    });

    test('returns null for a single option', () {
      const text = '```ask\n问题？\n- 只有一个\n```';
      expect(parseAskOptions(text), isNull);
    });

    test('returns null for more than four options', () {
      const text = '```ask\n问题？\n- 一\n- 二\n- 三\n- 四\n- 五\n```';
      expect(parseAskOptions(text), isNull);
    });

    test('returns null when a body line is not a list item', () {
      const text = '```ask\n问题？\n- 选项一\n随便一行\n```';
      expect(parseAskOptions(text), isNull);
    });

    test('returns null for an unclosed block (still streaming)', () {
      const text = '```ask\n问题？\n- 选项一\n- 选项二\n';
      expect(parseAskOptions(text), isNull);
    });
  });

  group('AskOptionsCard', () {
    const ask = AskOptions(
      question: '周末去哪玩？',
      options: [
        AskOption(label: '爬山', description: '锻炼身体'),
        AskOption(label: '看展'),
        AskOption(label: '宅家'),
      ],
    );

    testWidgets('renders question and options; tap publishes the option', (
      tester,
    ) async {
      final received = <String>[];
      final sub = AskOptionsBus.instance.selections.listen(received.add);
      addTearDown(sub.cancel);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AskOptionsCard(ask: ask),
            ),
          ),
        ),
      );

      expect(find.text('周末去哪玩？'), findsOneWidget);
      expect(find.text('爬山'), findsOneWidget);
      expect(find.text('看展'), findsOneWidget);
      expect(find.text('宅家'), findsOneWidget);

      await tester.tap(find.text('看展'));
      await tester.pump();
      expect(received, ['看展']);
    });

    testWidgets('golden: ask options card (dark)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            backgroundColor: Colors.black,
            body: Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 420, child: AskOptionsCard(ask: ask)),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(AskOptionsCard),
        matchesGoldenFile('ask_options_card.png'),
      );
    });
  });
}
