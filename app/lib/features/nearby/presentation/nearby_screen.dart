import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/features/nearby/application/nearby_provider.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/location/location_source.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// S6 Nearby. Location is requested only when the user taps "Use my
/// location" here; the position lives in this screen's state and is dropped
/// when it closes. Distances are straight-line.
class NearbyScreen extends ConsumerWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(nearbyProvider);
    final controller = ref.read(nearbyProvider.notifier);

    Future<void> pickByName() async {
      final id = await context.push<String>('/go/pick/from');
      if (id != null && context.mounted) {
        await context.push('/station/${Uri.encodeComponent(id)}');
      }
    }

    Widget pickButton() => OutlinedButton(
      key: const Key('nearby-pick'),
      onPressed: pickByName,
      child: Text(l10n.nearbyPickStation),
    );

    final body = switch (state) {
      NearbyIdle() => StateView(
        key: const Key('nearby-idle'),
        kind: StateViewKind.empty,
        title: l10n.nearbyRationaleTitle,
        message: l10n.nearbyRationaleBody,
        action: FilledButton(
          key: const Key('nearby-use-location'),
          onPressed: controller.locate,
          child: Text(l10n.nearbyUseLocation),
        ),
      ),
      NearbyLocating() => Center(
        key: const Key('nearby-locating'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.screenPadding),
            Text(l10n.nearbyLocating),
          ],
        ),
      ),
      NearbyDenied(:final permanent) => StateView(
        key: const Key('nearby-denied'),
        kind: StateViewKind.denied,
        title: l10n.nearbyDeniedTitle,
        message: permanent
            ? l10n.nearbyDeniedPermanentBody
            : l10n.nearbyDeniedBody,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (permanent)
              FilledButton(
                key: const Key('nearby-open-settings'),
                onPressed: ref.read(locationSourceProvider).openSettings,
                child: Text(l10n.nearbyOpenSettings),
              )
            else
              FilledButton(
                key: const Key('nearby-retry'),
                onPressed: controller.locate,
                child: Text(l10n.nearbyRetry),
              ),
            const SizedBox(height: AppSpacing.unit * 2),
            pickButton(),
          ],
        ),
      ),
      NearbyUnavailable(:final servicesOff) => StateView(
        key: Key(
          servicesOff ? 'nearby-services-off' : 'nearby-unavailable',
        ),
        kind: StateViewKind.error,
        title: servicesOff
            ? l10n.nearbyServicesOffTitle
            : l10n.nearbyUnavailableTitle,
        message: servicesOff
            ? l10n.nearbyServicesOffBody
            : l10n.nearbyUnavailableBody,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (servicesOff)
              FilledButton(
                key: const Key('nearby-open-location-settings'),
                onPressed: ref
                    .read(locationSourceProvider)
                    .openLocationSettings,
                child: Text(l10n.nearbyOpenLocationSettings),
              ),
            FilledButton.tonal(
              key: const Key('nearby-retry'),
              onPressed: controller.locate,
              child: Text(l10n.nearbyRetry),
            ),
            const SizedBox(height: AppSpacing.unit * 2),
            pickButton(),
          ],
        ),
      ),
      NearbyInvalidLocation() => StateView(
        key: const Key('nearby-invalid'),
        kind: StateViewKind.error,
        title: l10n.nearbyInvalidTitle,
        message: l10n.nearbyInvalidBody,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('nearby-retry'),
              onPressed: controller.locate,
              child: Text(l10n.nearbyRetry),
            ),
            const SizedBox(height: AppSpacing.unit * 2),
            pickButton(),
          ],
        ),
      ),
      NearbyReady(:final rows, :final isApproximate) =>
        rows.isEmpty
            ? StateView(
                key: const Key('nearby-none'),
                kind: StateViewKind.empty,
                title: l10n.nearbyNoneTitle,
                message: l10n.nearbyNoneBody(
                  (defaultNearbyRadiusM / 1000).toStringAsFixed(0),
                ),
                action: pickButton(),
              )
            : _Results(rows: rows, isApproximate: isApproximate),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyTitle)),
      body: Column(
        children: [
          const DataBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.rows, required this.isApproximate});

  final List<NearbyRow> rows;
  final bool isApproximate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    return ListView(
      key: const Key('nearby-results'),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.nearbyStraightLineNote,
                key: const Key('nearby-straight-note'),
                style: theme.textTheme.bodySmall,
              ),
              if (isApproximate)
                Text(
                  l10n.nearbyApproximate,
                  key: const Key('nearby-approximate'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        for (final r in rows)
          InkWell(
            key: Key('nearby-row-${r.option.id}'),
            // the canonical id opens the detail; names are display only
            onTap: () =>
                context.push('/station/${Uri.encodeComponent(r.option.id)}'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                  vertical: AppSpacing.unit * 3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stationTitles(
                        nameEn: r.option.nameEn,
                        nameHi: r.option.nameHi,
                        locale: locale,
                      ).primary,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      l10n.nearbyDistance(_distance(l10n, r.distanceM)),
                      key: Key('nearby-distance-${r.option.id}'),
                    ),
                    const SizedBox(height: AppSpacing.unit * 2),
                    Wrap(
                      spacing: AppSpacing.unit * 2,
                      runSpacing: AppSpacing.unit * 2,
                      children: [
                        for (final l in r.option.lines) LineChip(data: l),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _distance(AppLocalizations l10n, int meters) => meters < 1000
    ? l10n.distanceMeters(meters)
    : l10n.distanceKm((meters / 1000).toStringAsFixed(1));
