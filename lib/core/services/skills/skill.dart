import '../../models/skill_record.dart';

class Skill {
  const Skill({
    required this.record,
    required this.name,
    required this.description,
    required this.dir,
    required this.skillMdPath,
  });

  final SkillRecord record;
  final String name;
  final String description;
  final String dir;
  final String skillMdPath;

  /// Name to show in the UI. In a Chinese UI, a cached Chinese translation
  /// (made by the user's own model, see SkillTranslationService) wins over
  /// the original frontmatter text; other locales always see the original.
  String displayName({required bool chineseUi}) {
    final translated = record.translatedName;
    if (chineseUi && translated != null && translated.isNotEmpty) {
      return translated;
    }
    return name;
  }

  /// Description to show in the UI; same rule as [displayName].
  String displayDescription({required bool chineseUi}) {
    final translated = record.translatedDescription;
    if (chineseUi && translated != null && translated.isNotEmpty) {
      return translated;
    }
    return description;
  }
}
