import 'dart:convert';

import 'skill.dart';
import 'skills_service.dart';

/// Translates one prompt with the user's own configured model and returns
/// the model's raw text output.
typedef SkillTextTranslator = Future<String> Function(String prompt);

/// Automatic Chinese display translation for skill (plugin) content.
///
/// Product rule: English skill names/descriptions shown in the browsing
/// and settings UI must be translated into Chinese automatically — no tap
/// needed — using the user's own configured model (no external
/// translation service). Translations are cached on the skill record,
/// keyed by a hash of the source text, so each version of a skill is
/// translated at most once. Failures are silent: the original text stays
/// on screen and translation is retried on a later app launch.
class SkillTranslationService {
  SkillTranslationService._();

  static final SkillTranslationService instance = SkillTranslationService._();

  /// id+sourceHash pairs already attempted in this process, so a failing
  /// or unconfigured model is not retried on every rebuild.
  static final Set<String> _attempted = <String>{};

  /// True when [text] contains Latin letters and no CJK characters, i.e.
  /// it reads as foreign (English) text to a Chinese user.
  static bool needsTranslation(String text) {
    var hasLatin = false;
    for (final rune in text.runes) {
      if ((rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0xF900 && rune <= 0xFAFF)) {
        return false;
      }
      if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
        hasLatin = true;
      }
    }
    return hasLatin;
  }

  /// Stable FNV-1a hash of the skill's source name + description.
  static String sourceHash(Skill skill) {
    var hash = 0x811c9dc5;
    for (final rune in '${skill.name}\n${skill.description}'.runes) {
      hash ^= rune;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// True when the skill has foreign text and no up-to-date cached
  /// translation for its current source text.
  static bool isStale(Skill skill) {
    if (!needsTranslation(skill.name) && !needsTranslation(skill.description)) {
      return false;
    }
    return skill.record.translationSourceHash != sourceHash(skill);
  }

  static String buildPrompt(Skill skill) {
    return '你是翻译助手。把下面这个软件技能的名称和说明翻译成简体中文。'
        '只输出一个 JSON 对象，不要输出任何其他文字，格式：'
        '{"name":"译文","description":"译文"}\n'
        '名称：${skill.name}\n'
        '说明：${skill.description}';
  }

  /// Parses the model's reply into translated fields. Accepts a bare JSON
  /// object or one wrapped in prose/code fences. Returns null when no
  /// usable translation is present.
  static ({String? name, String? description})? parseResult(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    String? clean(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final name = clean(decoded['name']);
    final description = clean(decoded['description']);
    if (name == null && description == null) return null;
    return (name: name, description: description);
  }

  /// Translates every stale skill in [service], one model call per skill,
  /// storing results back through [SkillsService.setTranslation].
  Future<void> translateMissing(
    SkillsService service,
    SkillTextTranslator translate,
  ) async {
    for (final skill in List<Skill>.of(service.skills)) {
      if (!isStale(skill)) continue;
      final hash = sourceHash(skill);
      if (!_attempted.add('${skill.record.id}:$hash')) continue;
      try {
        final raw = await translate(buildPrompt(skill));
        final parsed = parseResult(raw);
        if (parsed == null) continue;
        await service.setTranslation(
          skill.record.id,
          translatedName: parsed.name,
          translatedDescription: parsed.description,
          sourceHash: hash,
        );
      } catch (_) {
        // Best effort only: original text stays; a later launch retries.
      }
    }
  }
}
