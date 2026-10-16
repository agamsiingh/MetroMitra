import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/router.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/features/journey/application/journey_controller.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/announcement_banner.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';

/// S1 Home: choose From and To, then find a route. Recents are not shown:
/// the user database arrives in a later milestone.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selection = ref.watch(journeyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DataBanner(),
          const AnnouncementBanner(),
          const _JourneyBanner(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  remoteText(ref, context, 'homeHeading', l10n.homeHeading),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                const _StationField(end: JourneyEnd.from),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const Key('swap'),
                    tooltip: l10n.homeSwap,
                    onPressed:
                        selection.fromId == null && selection.toId == null
                        ? null
                        : () => ref.read(journeyProvider.notifier).swap(),
                    icon: const Icon(Icons.swap_vert_rounded),
                  ),
                ),
                const _StationField(end: JourneyEnd.to),
                const SizedBox(height: AppSpacing.screenPadding),
                if (selection.isSameStation)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSpacing.screenPadding,
                    ),
                    child: Text(
                      l10n.homeSameStation,
                      key: const Key('same-station-message'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const Key('nearby'),
                  onPressed: () => context.push(Routes.nearby),
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(l10n.nearbyButton),
                ),
                const SizedBox(height: AppSpacing.unit * 2),
                FilledButton(
                  key: const Key('find-route'),
                  onPressed: selection.canSearch
                      ? () => context.push(
                          '/go/route?from=${Uri.encodeQueryComponent(selection.fromId!)}'
                          '&to=${Uri.encodeQueryComponent(selection.toId!)}',
                        )
                      : null,
                  child: Text(l10n.homeFindRoute),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationField extends ConsumerWidget {
  const _StationField({required this.end});

  final JourneyEnd end;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final services = ref.watch(metroServicesProvider);
    final id = ref.watch(journeyProvider).of(end);
    final option = id == null ? null : stationOptionFor(services, id);
    final label = end == JourneyEnd.from
        ? l10n.homeFromLabel
        : l10n.homeToLabel;
    final hint = end == JourneyEnd.from ? l10n.homePickFrom : l10n.homePickTo;
    final key = Key('field-${end.name}');
    final titles = option == null
        ? null
        : stationTitles(
            nameEn: option.nameEn,
            nameHi: option.nameHi,
            locale: locale,
          );

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: () async {
          final picked = await context.push<String>('/go/pick/${end.name}');
          if (picked != null) {
            ref.read(journeyProvider.notifier).set(end, picked);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AppSpacing.unit),
                if (id != null && option == null)
                  Text(
                    l10n.homeStationMissing,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else if (titles == null)
                  Text(
                    hint,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titles.primary,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: Key('field-info-${end.name}'),
                        tooltip: l10n.stationInfoTooltip,
                        icon: const Icon(Icons.info_outline_rounded),
                        onPressed: () => context.push(
                          '/station/${Uri.encodeComponent(id!)}',
                        ),
                      ),
                    ],
                  ),
                  if (titles.secondary != null)
                    Text(
                      titles.secondary!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.unit * 2),
                  Wrap(
                    spacing: AppSpacing.unit * 2,
                    runSpacing: AppSpacing.unit * 2,
                    children: [
                      for (final l in option!.lines) LineChip(data: l),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A journey that is running (or was saved before the app was closed) can be
/// continued from Home. Reading [journeyRestoreProvider] resumes a saved
/// journey once per app start.
class _JourneyBanner extends ConsumerWidget {
  const _JourneyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(journeyRestoreProvider);
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(activeJourneyProvider);
    final controller = ref.read(activeJourneyProvider.notifier);
    final Widget content;
    switch (session) {
      case NoJourney():
        return const SizedBox.shrink();
      case JourneyRunning(:final journey):
        final services = ref.watch(metroServicesProvider);
        String name(String id) {
          final o = stationOptionFor(services, id);
          return o == null
              ? id
              : stationTitles(
                  nameEn: o.nameEn,
                  nameHi: o.nameHi,
                  locale: Localizations.localeOf(context),
                ).primary;
        }

        content = Column(
          key: const Key('journey-banner'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.journeyInProgress(
                name(journey.plan.fromId),
                name(journey.plan.toId),
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.unit * 2),
            Wrap(
              spacing: AppSpacing.unit * 2,
              children: [
                FilledButton.tonal(
                  key: const Key('resume-journey'),
                  onPressed: () => context.push('/journey'),
                  child: Text(l10n.journeyContinue),
                ),
                TextButton(
                  key: const Key('resume-end'),
                  onPressed: controller.end,
                  child: Text(l10n.journeyEndShort),
                ),
              ],
            ),
          ],
        );
      case JourneyNotRestored(:final problem):
        content = Column(
          key: const Key('journey-not-restored'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              problem == RestoreProblem.expired
                  ? l10n.journeyRestoreExpired
                  : l10n.journeyRestoreDataChanged,
            ),
            TextButton(
              key: const Key('journey-dismiss'),
              onPressed: controller.dismissNotice,
              child: Text(l10n.journeyDismiss),
            ),
          ],
        );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
        AppSpacing.screenPadding,
        0,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: content,
        ),
      ),
    );
  }
}
