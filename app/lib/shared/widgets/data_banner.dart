import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';

/// Shown on every data screen when the loaded dataset is a draft or test
/// data, so unverified information is never presented as fact.
class DataBanner extends ConsumerWidget {
  const DataBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(metroServicesProvider);
    final l10n = AppLocalizations.of(context);
    final text = services.isTestData
        ? l10n.bannerTestData
        : services.isDraft
        ? l10n.bannerDraft
        : null;
    if (text == null) return const SizedBox.shrink();
    final status = Theme.of(context).extension<StatusColors>();
    final color = status?.warning ?? Theme.of(context).colorScheme.error;
    return Semantics(
      container: true,
      child: Container(
        key: const Key('data-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.unit * 2,
        ),
        color: color.withValues(alpha: 0.14),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 20),
            const SizedBox(width: AppSpacing.unit * 2),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
