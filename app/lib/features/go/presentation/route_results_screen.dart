import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/features/go/presentation/route_legs.dart';
import 'package:metromitra/features/journey/application/journey_controller.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// S3 Route results for a canonical (from, to) station-id pair.
class RouteResultsScreen extends ConsumerStatefulWidget {
  const RouteResultsScreen({
    required this.fromId,
    required this.toId,
    super.key,
  });

  final String fromId;
  final String toId;

  @override
  ConsumerState<RouteResultsScreen> createState() => _RouteResultsScreenState();
}

class _RouteResultsScreenState extends ConsumerState<RouteResultsScreen> {
  int _selected = 0;

  void _swap() {
    ref.read(journeyProvider.notifier).setBoth(widget.toId, widget.fromId);
    context.pushReplacement(
      '/go/route?from=${Uri.encodeQueryComponent(widget.toId)}'
      '&to=${Uri.encodeQueryComponent(widget.fromId)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = ref.watch(metroServicesProvider);
    final lookup = ref.watch(
      routeLookupProvider(RouteQuery(widget.fromId, widget.toId)),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.routeTitle)),
      body: Column(
        children: [
          const DataBanner(),
          _Header(
            fromId: widget.fromId,
            toId: widget.toId,
            onSwap: _swap,
          ),
          Expanded(
            child: switch (lookup) {
              RouteFound(:final options) => _Found(
                fromId: widget.fromId,
                toId: widget.toId,
                options: options,
                selected: _selected.clamp(0, options.length - 1),
                services: services,
                onSelect: (i) => setState(() => _selected = i),
              ),
              RouteSameStation() => StateView(
                key: const Key('route-same'),
                kind: StateViewKind.empty,
                title: l10n.routeSameTitle,
                message: l10n.routeSameBody,
              ),
              RouteUnreachable(:final fromId, :final toId) => StateView(
                key: const Key('route-unreachable'),
                kind: StateViewKind.empty,
                title: l10n.routeNoRouteTitle,
                message: l10n.routeNoRouteBody(
                  _name(services, fromId, context),
                  _name(services, toId, context),
                ),
              ),
              RouteNotServed(:final stationId) => StateView(
                key: const Key('route-not-served'),
                kind: StateViewKind.empty,
                title: l10n.routeNotServedTitle,
                message: l10n.routeNotServedBody(
                  _name(services, stationId, context),
                ),
              ),
              RouteUnknownStation() => StateView(
                key: const Key('route-unknown'),
                kind: StateViewKind.error,
                title: l10n.routeUnknownTitle,
                message: l10n.routeUnknownBody,
              ),
            },
          ),
        ],
      ),
    );
  }
}

String _name(MetroServices services, String id, BuildContext context) {
  final s = services.snapshot.station(id);
  if (s == null) return id;
  return stationTitles(
    nameEn: s.nameEn,
    nameHi: s.nameHi,
    locale: Localizations.localeOf(context),
  ).primary;
}

/// Tapping a station name opens its detail (by canonical id). Unknown ids
/// are not links.
class _StationLink extends ConsumerWidget {
  const _StationLink({
    required this.stationId,
    required this.linkKey,
    required this.child,
  });

  final String stationId;
  final Key linkKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known =
        ref.watch(metroServicesProvider).snapshot.station(stationId) != null;
    return InkWell(
      key: linkKey,
      onTap: known
          ? () => context.push('/station/${Uri.encodeComponent(stationId)}')
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.fromId,
    required this.toId,
    required this.onSwap,
  });

  final String fromId;
  final String toId;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final services = ref.watch(metroServicesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.unit * 2,
        AppSpacing.unit * 2,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StationLink(
                  stationId: fromId,
                  linkKey: const Key('open-from'),
                  child: Text(
                    _known(services, fromId)
                        ? _name(services, fromId, context)
                        : l10n.routeUnknownTitle,
                    key: const Key('header-from'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.arrow_downward_rounded, size: 16),
                _StationLink(
                  stationId: toId,
                  linkKey: const Key('open-to'),
                  child: Text(
                    _known(services, toId)
                        ? _name(services, toId, context)
                        : l10n.routeUnknownTitle,
                    key: const Key('header-to'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('swap-route'),
            tooltip: l10n.homeSwap,
            onPressed: onSwap,
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
    );
  }

  bool _known(MetroServices s, String id) => s.snapshot.station(id) != null;
}

String profileLabel(AppLocalizations l10n, RoutingProfile p) => switch (p) {
  RoutingProfile.fastest => l10n.profileFastest,
  RoutingProfile.easiest => l10n.profileEasiest,
  RoutingProfile.lessWalking => l10n.profileLessWalking,
  RoutingProfile.fewestStops => l10n.profileFewestStops,
};

class _Found extends ConsumerWidget {
  const _Found({
    required this.fromId,
    required this.toId,
    required this.options,
    required this.selected,
    required this.services,
    required this.onSelect,
  });

  final String fromId;
  final String toId;
  final List<RouteOption> options;
  final int selected;
  final MetroServices services;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final option = options[selected];
    final it = option.itinerary;
    return ListView(
      key: const Key('route-found'),
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        if (options.length > 1)
          Wrap(
            spacing: AppSpacing.unit * 2,
            runSpacing: AppSpacing.unit,
            children: [
              for (var i = 0; i < options.length; i++)
                ChoiceChip(
                  key: Key('alt-$i'),
                  selected: i == selected,
                  onSelected: (_) => onSelect(i),
                  label: Text(
                    options[i].itinerary.profiles
                        .map((p) => profileLabel(l10n, p))
                        .join(' · '),
                  ),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.screenPadding),
        _Summary(itinerary: it, services: services),
        const SizedBox(height: AppSpacing.screenPadding),
        // the one primary action of the screen (docs/screens.md S3)
        FilledButton.icon(
          key: const Key('start-journey'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: () async {
            final ok = await ref
                .read(activeJourneyProvider.notifier)
                .start(fromId, toId, selected);
            if (!context.mounted) return;
            if (ok) {
              unawaited(context.push('/journey'));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.journeyCouldNotStart)),
              );
            }
          },
          icon: const Icon(Icons.navigation_rounded),
          label: Text(l10n.journeyStart),
        ),
        const SizedBox(height: AppSpacing.unit * 2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('show-route-on-map'),
            onPressed: () => context.push(
              '/go/route/map?from=${Uri.encodeQueryComponent(fromId)}'
              '&to=${Uri.encodeQueryComponent(toId)}&opt=$selected',
            ),
            icon: const Icon(Icons.map_outlined),
            label: Text(l10n.mapShowOnMap),
          ),
        ),
        if (it.timeIsEstimate) ...[
          const SizedBox(height: AppSpacing.screenPadding),
          const _ApproxNotice(),
        ],
        const SizedBox(height: AppSpacing.sectionGap),
        RouteTimeline(itinerary: it, services: services),
        const SizedBox(height: AppSpacing.sectionGap),
        FareSection(option: option),
        WarningsSection(itinerary: it, services: services),
        if (it.assumptions.isNotEmpty)
          AssumptionsSection(itinerary: it, services: services),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.itinerary, required this.services});

  final Itinerary itinerary;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = minutesOf(itinerary.totalTimeS);
    final facts = [
      l10n.routeChanges(itinerary.changes),
      l10n.routeStops(itinerary.stops),
      if (itinerary.walkM > 0) l10n.routeWalking(itinerary.walkM),
    ];
    final lines = <LineChipData>[];
    for (final r in itinerary.rides) {
      if (lines.any((l) => l.lineId == r.lineId)) continue;
      final line = services.snapshot.line(r.lineId);
      if (line == null) continue;
      lines.add(
        LineChipData(
          lineId: line.id,
          nameEn: line.nameEn,
          nameHi: line.nameHi,
          colorHex: line.colorHex,
          textColorHex: line.textColorHex,
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              itinerary.timeIsEstimate
                  ? l10n.routeApproxMinutes(minutes)
                  : '$minutes min',
              key: const Key('summary-duration'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.unit),
            Text(facts.join(' · '), key: const Key('summary-facts')),
            if (routeDistanceM(itinerary) > 0)
              Text(
                l10n.routeDistance(
                  (routeDistanceM(itinerary) / 1000).toStringAsFixed(1),
                ),
                key: const Key('summary-distance'),
              ),
            if (routeDistanceM(itinerary) > 0 &&
                distanceIsEstimate(itinerary, services.snapshot))
              Text(
                l10n.routeDistanceEstimate,
                key: const Key('summary-distance-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.unit * 2),
            Wrap(
              spacing: AppSpacing.unit * 2,
              runSpacing: AppSpacing.unit * 2,
              children: [for (final l in lines) LineChip(data: l)],
            ),
          ],
        ),
      ),
    );
  }
}

class _ApproxNotice extends StatelessWidget {
  const _ApproxNotice();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('approx-notice'),
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: AppSpacing.unit * 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.routeApproxTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(l10n.routeApproxBody),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Metres ridden on trains (walks not included), from the dataset edges.
int routeDistanceM(Itinerary it) =>
    it.rides.fold(0, (sum, r) => sum + r.distanceM);

/// True unless every ridden edge has an official or verified distance. Today
/// all distances are derived from station positions (shorter than the track),
/// so the screen says "estimate".
bool distanceIsEstimate(Itinerary it, MetroSnapshot snap) {
  for (final r in it.rides) {
    for (var i = 0; i + 1 < r.stationIds.length; i++) {
      final from = r.stationIds[i];
      final to = r.stationIds[i + 1];
      final e = snap
          .edgesFrom(from)
          .where((x) => x.serviceId == r.serviceId && x.toStation == to)
          .firstOrNull;
      if (e == null) return true;
      final c = e.provenance.confidence;
      if (c != Confidence.official && c != Confidence.verified) return true;
    }
  }
  return false;
}
