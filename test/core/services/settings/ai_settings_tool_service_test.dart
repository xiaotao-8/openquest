import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/core/services/settings/ai_settings_tool_service.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late AssistantProvider assistantProvider;
  late UserProvider userProvider;

  setUp(() {
    settings = SettingsProvider(createBusinessTestPreferences());
    assistantProvider = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    userProvider = UserProvider(preferences: createBusinessTestPreferences());
  });

  Future<Map<String, dynamic>> run(
    Map<String, dynamic> args, {
    Assistant? assistant,
  }) async {
    final raw = await AiSettingsToolService.execute(
      args: args,
      settings: settings,
      assistantProvider: assistantProvider,
      userProvider: userProvider,
      assistant: assistant,
    );
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test('master switch defaults to off', () {
    expect(settings.aiSettingsControlEnabled, isFalse);
  });

  test('risk levels: direct, approval, forbidden, unknown', () {
    expect(
      AiSettingsToolService.riskFor(AiSettingsToolService.keyThemeMode),
      AiSettingRisk.direct,
    );
    expect(
      AiSettingsToolService.riskFor(AiSettingsToolService.keyWebFetchMode),
      AiSettingRisk.approval,
    );
    expect(
      AiSettingsToolService.riskFor(
        AiSettingsToolService.keyAssistantSearchEnabled,
      ),
      AiSettingRisk.approval,
    );
    expect(
      AiSettingsToolService.riskFor(AiSettingsToolService.keyFullAccessMode),
      AiSettingRisk.forbidden,
    );
    expect(AiSettingsToolService.riskFor('nope'), isNull);
  });

  test('definition lists every key in the enum', () {
    final def = AiSettingsToolService.getToolDefinition();
    final fn = def['function'] as Map<String, dynamic>;
    expect(fn['name'], AiSettingsToolService.toolName);
    final params = fn['parameters'] as Map<String, dynamic>;
    final props = params['properties'] as Map<String, dynamic>;
    final keys = (props['key'] as Map<String, dynamic>)['enum'] as List;
    expect(keys, containsAll(AiSettingsToolService.allKeys));
  });

  test('full access mode is refused for get and set', () async {
    for (final action in ['get', 'set']) {
      final result = await run({
        'action': action,
        'key': 'full_access_mode',
        'value': 'true',
      });
      expect(result['error'], contains('Refused'));
    }
  });

  test('unknown key and bad action return errors', () async {
    expect((await run({'action': 'get', 'key': 'nope'}))['error'], isNotNull);
    expect(
      (await run({'action': 'poke', 'key': 'theme_mode'}))['error'],
      isNotNull,
    );
  });

  test('theme_mode set/get round-trips through SettingsProvider', () async {
    final set = await run({
      'action': 'set',
      'key': 'theme_mode',
      'value': 'dark',
    });
    expect(set['ok'], isTrue);
    expect(settings.themeMode, ThemeMode.dark);
    final get = await run({'action': 'get', 'key': 'theme_mode'});
    expect(get['value'], 'dark');
    expect(
      (await run({
        'action': 'set',
        'key': 'theme_mode',
        'value': 'purple',
      }))['error'],
      isNotNull,
    );
  });

  test('web_fetch_mode set applies and validates', () async {
    final set = await run({
      'action': 'set',
      'key': 'web_fetch_mode',
      'value': 'local',
    });
    expect(set['ok'], isTrue);
    expect(settings.webFetchMode, 'local');
  });

  test(
    'assistant rename and search toggle go through AssistantProvider',
    () async {
      await assistantProvider.loaded;
      final id = await assistantProvider.addAssistant(name: 'Old Name');
      final assistant = assistantProvider.assistants.firstWhere(
        (a) => a.id == id,
      );

      final renamed = await run({
        'action': 'set',
        'key': 'assistant_name',
        'value': 'New Name',
      }, assistant: assistant);
      expect(renamed['ok'], isTrue);
      expect(
        assistantProvider.assistants.firstWhere((a) => a.id == id).name,
        'New Name',
      );

      final toggled = await run({
        'action': 'set',
        'key': 'assistant_search_enabled',
        'value': 'true',
      }, assistant: assistant);
      expect(toggled['ok'], isTrue);
      expect(
        assistantProvider.assistants
            .firstWhere((a) => a.id == id)
            .searchEnabled,
        isTrue,
      );
    },
  );

  test('user display name set/get', () async {
    final set = await run({
      'action': 'set',
      'key': 'user_display_name',
      'value': 'Xiaotao',
    });
    expect(set['ok'], isTrue);
    expect(userProvider.name, 'Xiaotao');
  });
}
