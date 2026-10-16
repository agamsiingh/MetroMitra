import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/features/remote_config/application/remote_config.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';

/// A short notice from the admin panel (e.g. a service change) at the top of
/// Home. Plain text, no links, hidden when empty or switched off. It is not a
/// source of metro facts: fares, gates and timings come from the dataset.
class AnnouncementBanner extends ConsumerWidget {
  const AnnouncementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(remoteConfigProvider.select((c) => c.announcement));
    final lang = Localizations.localeOf(context).languageCode;
    final text = a.textFor(lang);
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final warning = a.severity == AnnouncementSeverity.warning;
    final bg = warning ? scheme.tertiaryContainer : scheme.secondaryContainer;
    final fg = warning
        ? scheme.onTertiaryContainer
        : scheme.onSecondaryContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('announcement'),
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.unit * 3,
        ),
        child: Row(
          children: [
            Icon(
              warning ? Icons.warning_amber_rounded : Icons.info_outline,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.unit * 3),
            Expanded(
              child: Text(
                text,
                key: const Key('announcement-text'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
