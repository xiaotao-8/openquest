import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../controllers/muse_nav_bus.dart';
import 'goals_page.dart';

/// Skeleton page for a Muse sidebar section （动态 / 点子 / 目标 / 资源库）:
/// a real, openable page with its basic structure and an honest empty
/// state. No fake data is shown; content arrives with later phases.
class MuseSectionPage extends StatelessWidget {
  const MuseSectionPage({super.key, required this.tab});

  final MuseNavTab tab;

  @override
  Widget build(BuildContext context) {
    if (tab == MuseNavTab.goals) return const GoalsPage();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final (title, icon, emptyText) = switch (tab) {
      MuseNavTab.feed => (
        l10n.museNavFeed,
        Lucide.Activity,
        l10n.museFeedEmpty,
      ),
      MuseNavTab.ideas => (
        l10n.museNavIdeas,
        Lucide.Lightbulb,
        l10n.museIdeasEmpty,
      ),
      MuseNavTab.goals => (
        l10n.museNavGoals,
        Lucide.Target,
        l10n.museGoalsEmpty,
      ),
      MuseNavTab.library => (
        l10n.museNavLibrary,
        Lucide.Library,
        l10n.museLibraryEmpty,
      ),
      MuseNavTab.chat => (l10n.museNavMainChat, Lucide.MessageCircle, ''),
    };
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 44,
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      emptyText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
