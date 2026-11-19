enum SkillSource { paste, file, github, bundled }

class SkillRecord {
  final String id;
  final bool enabled;
  final int useCount;
  final SkillSource source;
  final DateTime installedAt;
  final DateTime updatedAt;

  /// Chinese translations of the skill's frontmatter name/description,
  /// produced on demand by the user's own model for display in a Chinese
  /// UI (see SkillTranslationService). [translationSourceHash] is the hash
  /// of the source name+description the translations were made from; when
  /// the source text changes the hash no longer matches and the skill is
  /// translated again.
  final String? translatedName;
  final String? translatedDescription;
  final String? translationSourceHash;

  const SkillRecord({
    required this.id,
    this.enabled = true,
    this.useCount = 0,
    required this.source,
    required this.installedAt,
    required this.updatedAt,
    this.translatedName,
    this.translatedDescription,
    this.translationSourceHash,
  });

  SkillRecord copyWith({
    String? id,
    bool? enabled,
    int? useCount,
    SkillSource? source,
    DateTime? installedAt,
    DateTime? updatedAt,
    String? translatedName,
    String? translatedDescription,
    String? translationSourceHash,
  }) {
    return SkillRecord(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      useCount: useCount ?? this.useCount,
      source: source ?? this.source,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      translatedName: translatedName ?? this.translatedName,
      translatedDescription:
          translatedDescription ?? this.translatedDescription,
      translationSourceHash:
          translationSourceHash ?? this.translationSourceHash,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'useCount': useCount,
    'source': source.name,
    'installedAt': installedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (translatedName != null) 'translatedName': translatedName,
    if (translatedDescription != null)
      'translatedDescription': translatedDescription,
    if (translationSourceHash != null)
      'translationSourceHash': translationSourceHash,
  };

  factory SkillRecord.fromJson(Map<String, dynamic> json) {
    return SkillRecord(
      id: json['id'] as String,
      enabled: json['enabled'] as bool? ?? true,
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      source: skillSourceFromString(json['source'] as String?),
      installedAt: DateTime.parse(json['installedAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      translatedName: json['translatedName'] as String?,
      translatedDescription: json['translatedDescription'] as String?,
      translationSourceHash: json['translationSourceHash'] as String?,
    );
  }

  static SkillSource skillSourceFromString(String? value) {
    switch (value) {
      case 'file':
        return SkillSource.file;
      case 'github':
        return SkillSource.github;
      case 'bundled':
        return SkillSource.bundled;
      case 'paste':
      default:
        return SkillSource.paste;
    }
  }
}
