import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/utils/ask_options.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

/// Minis-style `user_ask` card rendered under an assistant reply that
/// carried an `ask` block: a full card with a small header chip, a
/// one-sentence question, and 2-4 option ROWS (short label + one line of
/// small description). Tapping a row answers immediately; in
/// multi-select mode rows toggle and a submit button sends the picked
/// labels together. A block with no options renders as an open question
/// card (header + question only).
class AskOptionsCard extends StatefulWidget {
  const AskOptionsCard({super.key, required this.ask});

  final AskOptions ask;

  @override
  State<AskOptionsCard> createState() => _AskOptionsCardState();
}

class _AskOptionsCardState extends State<AskOptionsCard> {
  final Set<int> _selected = <int>{};
  bool _answered = false;

  void _tapRow(int index) {
    if (_answered) return;
    final ask = widget.ask;
    if (!ask.multiSelect) {
      setState(() => _answered = true);
      AskOptionsBus.instance.select(ask.options[index].label);
      return;
    }
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _submitMulti() {
    if (_answered || _selected.isEmpty) return;
    final picked = _selected.toList()..sort();
    setState(() => _answered = true);
    AskOptionsBus.instance.select(
      picked.map((i) => widget.ask.options[i].label).join('、'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final ask = widget.ask;
    final cardColor = isDark
        ? cs.onSurface.withValues(alpha: 0.05)
        : cs.surfaceContainerHighest.withValues(alpha: 0.55);
    final rowColor = isDark
        ? cs.onSurface.withValues(alpha: 0.06)
        : cs.onSurface.withValues(alpha: 0.04);
    final borderColor = cs.onSurface.withValues(alpha: isDark ? 0.10 : 0.12);
    final textColor = cs.onSurface.withValues(alpha: 0.92);
    final subColor = cs.onSurface.withValues(alpha: 0.55);

    return Opacity(
      opacity: _answered ? 0.55 : 1,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header chip.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.messageCircleQuestion,
                    size: 12,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.askCardHeader,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      fontWeight: AppFontWeights.semibold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ask.question,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                height: 1.4,
                fontWeight: AppFontWeights.semibold,
              ),
            ),
            if (ask.options.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < ask.options.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _buildRow(
                  context,
                  index: i,
                  rowColor: rowColor,
                  borderColor: borderColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
              ],
            ],
            if (ask.multiSelect && ask.options.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_selected.isEmpty || _answered)
                      ? null
                      : _submitMulti,
                  child: Text(l10n.askCardSubmit),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required int index,
    required Color rowColor,
    required Color borderColor,
    required Color textColor,
    required Color subColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final ask = widget.ask;
    final option = ask.options[index];
    final checked = _selected.contains(index);
    return Semantics(
      button: true,
      label: option.label,
      child: IosCardPress(
        onTap: () => _tapRow(index),
        haptics: false,
        baseColor: checked && ask.multiSelect
            ? cs.primary.withValues(alpha: 0.16)
            : rowColor,
        borderRadius: BorderRadius.circular(12),
        pressedScale: 0.99,
        pressedBlendStrength: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: AppFontWeights.medium,
                    ),
                  ),
                  if (option.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (ask.multiSelect) ...[
              const SizedBox(width: 10),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: checked ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: checked ? cs.primary : borderColor,
                    width: 1.4,
                  ),
                ),
                child: checked
                    ? Icon(LucideIcons.check, size: 13, color: cs.onPrimary)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
