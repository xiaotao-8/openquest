import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../features/dev/pages/markdown_playground_page.dart';
import '../../features/settings/pages/log_viewer_page.dart';
import '../../icons/lucide_adapter.dart' as lucide;
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_switch.dart';
import '../../theme/app_font_weights.dart';

/// Desktop About pane. Mirrors the mobile About page: by product decision
/// it keeps only the log section — the context / request / Flutter log
/// switches, each with a shortcut into the log viewer. The app header,
/// version and system info, external links (website / GitHub / license),
/// QQ/Discord entries, the sponsor entry and the easter egg that used to
/// live here were removed on purpose.
class DesktopAboutPane extends StatelessWidget {
  const DesktopAboutPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();

    Widget logRow({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      required int initialTab,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(lucide.Lucide.FolderOpen, size: 19, color: cs.primary),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LogViewerPage(initialTab: initialTab),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
            IosSwitch(value: value, onChanged: onChanged),
          ],
        ),
      );
    }

    return Container(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.settingsPageAbout,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: AppFontWeights.regular,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _DeskCard(
                title: l10n.settingsPageAbout,
                children: [
                  // Debug/profile-only dev entry, mirroring the mobile
                  // About page; never shown in release builds.
                  if (kDebugMode || kProfileMode) ...[
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MarkdownPlaygroundPage(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              lucide.Lucide.Code,
                              size: 19,
                              color: cs.onSurface.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              l10n.markdownPlaygroundTitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurface.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const _DeskRowDivider(),
                  ],
                  logRow(
                    title: l10n.contextLogSettingTitle,
                    subtitle: l10n.contextLogSettingSubtitle,
                    value: settings.contextLogEnabled,
                    onChanged: (v) => settings.setContextLogEnabled(v),
                    initialTab: LogViewerPage.contextTab,
                  ),
                  const _DeskRowDivider(),
                  logRow(
                    title: l10n.requestLogSettingTitle,
                    subtitle: l10n.requestLogSettingSubtitle,
                    value: settings.requestLogEnabled,
                    onChanged: (v) => settings.setRequestLogEnabled(v),
                    initialTab: LogViewerPage.requestTab,
                  ),
                  const _DeskRowDivider(),
                  logRow(
                    title: l10n.flutterLogSettingTitle,
                    subtitle: l10n.flutterLogSettingSubtitle,
                    value: settings.flutterLogEnabled,
                    onChanged: (v) => settings.setFlutterLogEnabled(v),
                    initialTab: LogViewerPage.appTab,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeskCard extends StatelessWidget {
  const _DeskCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          width: 0.5,
          color: isDark
              ? cs.onSurface.withValues(alpha: 0.06)
              : cs.outlineVariant.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: AppFontWeights.emphasis,
                  color: cs.onSurface,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DeskRowDivider extends StatelessWidget {
  const _DeskRowDivider();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Divider(
        height: 1,
        thickness: 0.5,
        indent: 8,
        endIndent: 8,
        color: cs.outlineVariant.withValues(alpha: 0.12),
      ),
    );
  }
}
