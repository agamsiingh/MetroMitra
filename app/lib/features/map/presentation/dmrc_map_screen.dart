import 'package:flutter/material.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:pdfrx/pdfrx.dart';

/// Full-screen viewer for the official DMRC network map PDF bundled in assets.
/// Supports pinch-to-zoom, pan, and page navigation.
class DmrcMapScreen extends StatelessWidget {
  const DmrcMapScreen({super.key});

  static const _assetPath = 'assets/brand/dmrc_map.pdf';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        // Show a subtitle so the user knows this is the official DMRC map
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Official DMRC Map',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      body: PdfViewer.asset(_assetPath),
    );
  }
}
