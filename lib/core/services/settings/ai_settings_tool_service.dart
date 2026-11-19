import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;

import '../../models/assistant.dart';
import '../../providers/assistant_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_provider.dart';
import '../search/web_fetch_service.dart';

/// How risky one [AiSettingsToolService] key is.
///
/// Direct keys apply immediately; approval keys must go through the user's
/// approval card first (handled by the caller via `ToolCallPermission`);
/// forbidden keys are refused outright — no approval card can grant them.
enum AiSettingRisk { direct, approval, forbidden }

/// The unified, model-agnostic `app_settings` tool.
///
/// One tool, one protocol for every model: `{action, key, value}` with a
/// fixed whitelist of keys. Each key maps to an existing provider setter, so
/// the model never sees app internals and any model that can call tools can
/// drive the same settings. The tool is only offered while the user has the
/// master switch (Settings → 行为与启动 → AI 操控设置） on.
abstract final class AiSettingsToolService {
  static const String toolName = 'app_settings';

  static const String keyThemeMode = 'theme_mode';
  static const String keyUserDisplayName = 'user_display_name';
  static const String keyAssistantName = 'assistant_name';
  static const String keyWebFetchMode = 'web_fetch_mode';
  static const String keyAssistantSearchEnabled = 'assistant_search_enabled';
  static const String keyFullAccessMode = 'full_access_mode';

  static const List<String> allKeys = [
    keyThemeMode,
    keyUserDisplayName,
    keyAssistantName,
    keyWebFetchMode,
    keyAssistantSearchEnabled,
    keyFullAccessMode,
  ];

  static AiSettingRisk? riskFor(String key) {
    switch (key) {
      case keyThemeMode:
      case keyUserDisplayName:
      case keyAssistantName:
        return AiSettingRisk.direct;
      case keyWebFetchMode:
      case keyAssistantSearchEnabled:
        return AiSettingRisk.approval;
      case keyFullAccessMode:
        return AiSettingRisk.forbidden;
      default:
        return null;
    }
  }

  static const String toolDescription = '''
Read or change OpenQuest app settings on the user's behalf. One protocol for every setting; use action "get" to read a value and "set" to change it.

Keys and allowed values for "set":
- theme_mode: "system" | "light" | "dark" — the app's color mode.
- user_display_name: the user's own display name (short text).
- assistant_name: rename the assistant in this conversation (short text).
- web_fetch_mode: "off" | "local" | "follow" — whether the assistant may read web pages. SENSITIVE: changing it asks the user to approve first.
- assistant_search_enabled: "true" | "false" — web search for the assistant in this conversation. SENSITIVE: changing it asks the user to approve first.
- full_access_mode: REFUSED. Full-access (no-approval) mode can only be turned on by the user personally in Settings; never attempt it and tell the user so if they ask you to enable it.

Only change a setting when the user actually asked for that change. After a successful "set", briefly confirm the new value to the user.''';

  static Map<String, dynamic> getToolDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': toolDescription,
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['get', 'set'],
              'description': 'Read ("get") or change ("set") the setting.',
            },
            'key': {
              'type': 'string',
              'enum': allKeys,
              'description': 'Which setting to read or change.',
            },
            'value': {
              'type': 'string',
              'description':
                  'The new value as a string (required for "set"; see the tool description for each key\'s allowed values).',
            },
          },
          'required': ['action', 'key'],
        },
      },
    };
  }

  static String _error(String message) => jsonEncode({'error': message});

  static String _ok(String key, String value) =>
      jsonEncode({'ok': true, 'key': key, 'value': value});

  /// Executes one call. Approval for [AiSettingRisk.approval] keys is the
  /// caller's job (it must authorize before calling this); forbidden keys
  /// are refused here so no caller can bypass the refusal.
  static Future<String> execute({
    required Map<String, dynamic> args,
    required SettingsProvider settings,
    required AssistantProvider assistantProvider,
    required UserProvider userProvider,
    required Assistant? assistant,
  }) async {
    final action = (args['action'] ?? '').toString().trim().toLowerCase();
    final key = (args['key'] ?? '').toString().trim();
    final value = (args['value'] ?? '').toString().trim();

    final risk = riskFor(key);
    if (risk == null) {
      return _error(
        'Unknown setting key "$key". Allowed keys: ${allKeys.join(', ')}.',
      );
    }
    if (risk == AiSettingRisk.forbidden) {
      return _error(
        'Refused: full-access mode can only be enabled by the user '
        'personally in Settings. It cannot be changed by the assistant, '
        'even with approval.',
      );
    }
    if (action != 'get' && action != 'set') {
      return _error('action must be "get" or "set".');
    }

    switch (key) {
      case keyThemeMode:
        if (action == 'get') return _ok(key, settings.themeMode.name);
        final mode = switch (value) {
          'system' => ThemeMode.system,
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => null,
        };
        if (mode == null) {
          return _error('theme_mode must be "system", "light" or "dark".');
        }
        await settings.setThemeMode(mode);
        return _ok(key, mode.name);

      case keyUserDisplayName:
        if (action == 'get') return _ok(key, userProvider.name);
        if (value.isEmpty || value.length > 40) {
          return _error('user_display_name must be 1-40 characters.');
        }
        await userProvider.setName(value);
        return _ok(key, value);

      case keyAssistantName:
        if (assistant == null) {
          return _error('No assistant is active in this conversation.');
        }
        if (action == 'get') return _ok(key, assistant.name);
        if (value.isEmpty || value.length > 40) {
          return _error('assistant_name must be 1-40 characters.');
        }
        await assistantProvider.updateAssistant(
          assistant.copyWith(name: value),
        );
        return _ok(key, value);

      case keyWebFetchMode:
        if (action == 'get') return _ok(key, settings.webFetchMode);
        if (value != WebFetchMode.off &&
            value != WebFetchMode.local &&
            value != WebFetchMode.follow) {
          return _error('web_fetch_mode must be "off", "local" or "follow".');
        }
        await settings.setWebFetchMode(value);
        return _ok(key, settings.webFetchMode);

      case keyAssistantSearchEnabled:
        if (assistant == null) {
          return _error('No assistant is active in this conversation.');
        }
        if (action == 'get') {
          return _ok(key, assistant.searchEnabled.toString());
        }
        if (value != 'true' && value != 'false') {
          return _error('assistant_search_enabled must be "true" or "false".');
        }
        final enabled = value == 'true';
        await assistantProvider.updateAssistant(
          assistant.copyWith(searchEnabled: enabled),
        );
        return _ok(key, enabled.toString());

      default:
        return _error('Unhandled setting key "$key".');
    }
  }
}
