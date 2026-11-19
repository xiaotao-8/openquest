import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import 'log_viewer_page.dart';
import 'package:Kelivo/shared/widgets/section_card.dart';

/// About page. By product decision this page keeps only the log
/// section: the context / request / Flutter log switches, each with a
/// shortcut into the log viewer. The app header, version, system info,
/// external links, QQ/Discord entries and both former easter eggs were
/// removed on purpose.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LogViewerPage(initialTab: initialTab),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Lucide.FolderOpen, size: 20, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 8),
                IosSwitch(value: value, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.65),
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    }

    Widget divider = Divider(
      height: 6,
      thickness: 0.6,
      indent: 12,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: _TactileIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.settingsPageAbout),
        actions: const [SizedBox(width: 12)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          SectionCard(
            children: [
              logRow(
                title: l10n.contextLogSettingTitle,
                subtitle: l10n.contextLogSettingSubtitle,
                value: settings.contextLogEnabled,
                onChanged: (v) => settings.setContextLogEnabled(v),
                initialTab: LogViewerPage.contextTab,
              ),
              divider,
              logRow(
                title: l10n.requestLogSettingTitle,
                subtitle: l10n.requestLogSettingSubtitle,
                value: settings.requestLogEnabled,
                onChanged: (v) => settings.setRequestLogEnabled(v),
                initialTab: LogViewerPage.requestTab,
              ),
              divider,
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
    );
  }
}

// AppBar tactile icon button copied from provider detail page (with slight press scale)
class _TactileIconButton extends StatefulWidget {
  const _TactileIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  State<_TactileIconButton> createState() => _TactileIconButtonState();
}

class _TactileIconButtonState extends State<_TactileIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final pressColor = base.withValues(alpha: 0.7);
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: _pressed ? pressColor : base,
    );

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          // Follow provider detail: no haptics on tap
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: icon,
          ),
        ),
      ),
    );
  }
}
