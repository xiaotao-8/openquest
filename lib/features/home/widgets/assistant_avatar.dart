import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/models/assistant.dart';
import '../../../shared/widgets/emoji_text.dart';
import '../../../shared/widgets/avatar_image.dart';
import '../../../theme/app_font_weights.dart';

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    super.key,
    required this.assistant,
    this.fallbackName,
    this.size = 28,
  });

  final Assistant? assistant;
  final String? fallbackName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarValue = assistant?.avatar?.trim() ?? '';
    final name = (assistant?.name ?? fallbackName ?? '').trim();

    Widget avatar;
    if (avatarValue.isNotEmpty) {
      if (avatarValue.startsWith('http') ||
          (!kIsWeb &&
              (avatarValue.startsWith('/') || avatarValue.contains(':')))) {
        avatar = AvatarImage(
          source: avatarValue,
          isNetwork: avatarValue.startsWith('http'),
          size: size,
          fallback: _AssistantInitialAvatar(cs: cs, name: name, size: size),
        );
      } else {
        avatar = _AssistantEmojiAvatar(cs: cs, emoji: avatarValue, size: size);
      }
    } else {
      avatar = _AssistantInitialAvatar(cs: cs, name: name, size: size);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.onSurface.withValues(alpha: isDark ? 0.24 : 0.12),
          width: 0.5,
        ),
      ),
      child: avatar,
    );
  }
}

/// The default avatar for Bots and groups: the name's first character on
/// a dark gradient disc. The colour is derived from the name itself (same
/// name → same colour, always), picked from a set of deep tones that sit
/// well on the pure-black theme. Drawn entirely in code — no emoji, no
/// image assets. Users can still replace it with their own picture.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  static const List<Color> _palette = [
    Color(0xFF2E4A6B), // deep blue
    Color(0xFF1F5C4D), // deep teal
    Color(0xFF5B3A8E), // deep purple
    Color(0xFF7A3B2E), // dark terracotta
    Color(0xFF3E5C2E), // deep olive
    Color(0xFF6B2E4A), // deep plum
    Color(0xFF2E5C6B), // deep slate
    Color(0xFF6B5A2E), // deep bronze
  ];

  static Color colorForName(String name) {
    var hash = 0x811c9dc5;
    for (final unit in name.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final letter = name.isNotEmpty ? name.characters.first : '?';
    final base = colorForName(name);
    final darker = Color.fromARGB(
      255,
      (base.r * 255 * 0.55).round(),
      (base.g * 255 * 0.55).round(),
      (base.b * 255 * 0.55).round(),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, darker],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: size * 0.42,
          fontWeight: AppFontWeights.emphasis,
        ),
      ),
    );
  }
}

class _AssistantInitialAvatar extends StatelessWidget {
  const _AssistantInitialAvatar({
    required this.cs,
    required this.name,
    required this.size,
  });

  final ColorScheme cs;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InitialAvatar(name: name, size: size);
  }
}

class _AssistantEmojiAvatar extends StatelessWidget {
  const _AssistantEmojiAvatar({
    required this.cs,
    required this.emoji,
    required this.size,
  });

  final ColorScheme cs;
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: EmojiText(
        emoji.characters.take(1).toString(),
        fontSize: size * 0.5,
        optimizeEmojiAlign: true,
      ),
    );
  }
}

/// A group conversation's avatar: the user's chosen image when one is
/// set, otherwise the group's initial-letter avatar (same rule as Bots).
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.name,
    required this.avatarPath,
    this.size = 28,
  });

  final String name;
  final String? avatarPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = (avatarPath ?? '').trim();
    if (path.isNotEmpty) {
      return AvatarImage(
        source: path,
        isNetwork: path.startsWith('http'),
        size: size,
        fallback: InitialAvatar(name: name, size: size),
      );
    }
    return InitialAvatar(name: name, size: size);
  }
}
