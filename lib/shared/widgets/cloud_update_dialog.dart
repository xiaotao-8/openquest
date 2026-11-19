import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/update_provider.dart';
import '../../l10n/app_localizations.dart';
import 'snackbar.dart';

/// The cloud-update prompt: shown as soon as a check finds a newer version
/// on the user's update feed (app launch / return to foreground). The app
/// cannot install packages itself on iOS, so the download button hands the
/// package to the system (browser / signing tool) and the copy says so.
class CloudUpdateDialog {
  static Future<void> show(BuildContext context, UpdateInfo info) async {
    final l10n = AppLocalizations.of(context)!;
    final url = info.bestDownloadUrl();
    final notes = (info.notes ?? '').trim();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            info.build != null
                ? l10n.sideDrawerUpdateTitleWithBuild(info.version, info.build!)
                : l10n.sideDrawerUpdateTitle(info.version),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notes.isNotEmpty) Text(notes),
              if (Platform.isIOS) ...[
                if (notes.isNotEmpty) const SizedBox(height: 12),
                Text(l10n.cloudUpdateIosHint),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cloudUpdateLaterButton),
            ),
            if (url != null && url.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final uri = Uri.parse(url);
                  try {
                    // ignore: deprecated_member_use
                    await launchUrl(uri);
                  } catch (_) {
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    showAppSnackBar(
                      context,
                      message: l10n.sideDrawerLinkCopied,
                      type: NotificationType.success,
                    );
                  }
                },
                child: Text(l10n.cloudUpdateDownloadButton),
              ),
          ],
        );
      },
    );
  }
}
