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
import 'package:metromitra/features/map/application/live_tracking.dart';
import 'package:metromitra/features/map/application/map_overlay.dart';
import 'package:metromitra/features/map/application/map_provider.dart';
import 'package:metromitra/features/map/presentation/network_map.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/location/location_source.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// Opens a station's detail by canonical id.
void openStation(BuildContext context, String id) =>
    context.push('/station/${Uri.encodeComponent(id)}');

/// Reads the geometry, turning any failure into `null` ("map unavailable").
MapGeometry? _geometryOrNull(WidgetRef ref) {
  try {
    return ref.watch(mapGeometryProvider);
  } on Object {
    return null;
  }
}

/// S7 Map tab: the whole network, or one station when opened with
/// `?station=<id>`. Tapping a station opens its detail. The app bar search
/// frames a station; the location button shows the live position and the
/// nearest station (memory only, it stops when the map closes).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({this.focusStationId, super.key});

  /// Canonical id to frame; null = the whole network.
  final String? focusStationId;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Station picked with the map search (ringed, labelled, framed).
  String? _foundId;

  /// The latest explicit framing (search result or first live fix); wins
  /// over the initial frame while the screen is open.
  MapRect? _frame;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab is showing (the shell keeps this one alive, offstage):
    // the GPS must not keep running in the background.
    if (!TickerMode.valuesOf(context).enabled) {
      final tracking = ref.read(liveTrackingProvider.notifier);
      if (tracking.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tracking.stop());
      }
    }
  }

  Future<void> _search(MetroServices services) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MapSearchSheet(services: services),
    );
    if (id == null || !mounted) return;
    final f = ref.read(mapGeometryProvider).framingForStation(id);
    setState(() {
      _foundId = id;
      if (f != null) _frame = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final geometry = _geometryOrNull(ref);
    final services = ref.watch(metroServicesProvider);
    final journey = ref.watch(journeyProvider);
    final focusStationId = widget.focusStationId;
    final tracking = ref.watch(liveTrackingProvider);
    final flags = ref.watch(remoteConfigProvider.select((c) => c.flags));
    ref.listen(liveTrackingProvider, (prev, next) {
      // frame the user + the nearest station once, at the first fix
      if (prev is! TrackingOn && next is TrackingOn && next.frame != null) {
        setState(() => _frame = next.frame);
      }
    });

    Widget body;
    if (geometry == null) {
      body = StateView(
        key: const Key('map-unavailable'),
        kind: StateViewKind.error,
        title: l10n.mapUnavailableTitle,
        message: l10n.mapUnavailableBody,
      );
    } else if (geometry.isEmpty) {
      body = StateView(
        key: const Key('map-empty'),
        kind: StateViewKind.empty,
        title: l10n.mapEmptyTitle,
        message: geometry.skippedStationIds.isEmpty
            ? l10n.mapEmptyBody
            : l10n.mapEmptyNoCoordsBody,
      );
    } else if (focusStationId != null &&
        services.snapshot.station(focusStationId) == null) {
      body = _focusProblem(
        context,
        key: 'map-station-not-found',
        title: l10n.mapStationNotFoundTitle,
        message: l10n.mapStationNotFoundBody,
      );
    } else if (focusStationId != null &&
        geometry.station(focusStationId) == null) {
      body = _focusProblem(
        context,
        key: 'map-station-no-coordinates',
        title: l10n.mapStationNoCoordsTitle,
        message: l10n.mapStationNoCoordsBody,
      );
    } else {
      final frame =
          _frame ??
          (focusStationId == null
              ? geometry.networkFrame!
              : geometry.framingForStation(focusStationId)!);
      final on = tracking is TrackingOn ? tracking : null;
      final point = on?.point;
      final active = tracking is TrackingOn || tracking is TrackingStarting;
      body = Column(
        children: [
          if (geometry.skippedStationIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.unit * 2,
                AppSpacing.screenPadding,
                0,
              ),
              child: Text(
                l10n.mapSkippedNote(geometry.skippedStationIds.length),
                key: const Key('map-skipped-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (tracking is! TrackingOff) _TrackingPanel(state: tracking),
          Expanded(
            child: NetworkMap(
              geometry: geometry,
              snapshot: services.snapshot,
              frame: frame,
              fromId: journey.fromId,
              toId: journey.toId,
              highlightId: _foundId,
              user: point == null
                  ? null
                  : MapUser(
                      x: point.$1,
                      y: point.$2,
                      accuracyM: on!.fix.accuracyM,
                      lost: on.lost,
                      nearestId: on.nearest?.station.id,
                    ),
              extraControls: [
                if (flags.showLiveTracking)
                  MapRoundButton(
                    key: const Key('map-track'),
                    icon: active
                        ? Icons.location_disabled_rounded
                        : Icons.my_location_rounded,
                    tooltip: active ? l10n.mapTrackStop : l10n.mapTrackStart,
                    onPressed: () =>
                        ref.read(liveTrackingProvider.notifier).toggle(),
                  ),
              ],
              onStationTap: (id) => openStation(context, id),
            ),
          ),
          _Attribution(services: services),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        actions: [
          if (geometry != null && !geometry.isEmpty && flags.showOverviewMap)
            IconButton(
              key: const Key('map-overview'),
              tooltip: l10n.overviewOpen,
              icon: const Icon(Icons.map_outlined),
              onPressed: () => context.push('/map/overview'),
            ),
          if (flags.showDmrcMap)
            IconButton(
              key: const Key('map-dmrc'),
              tooltip: 'Official DMRC Map',
              icon: const Icon(Icons.picture_as_pdf_rounded),
              onPressed: () => context.push('/map/dmrc'),
            ),
          if (geometry != null && !geometry.isEmpty && flags.showMapSearch)
            IconButton(
              key: const Key('map-search'),
              tooltip: l10n.mapSearch,
              icon: const Icon(Icons.search_rounded),
              onPressed: () => _search(services),
            ),
        ],
      ),
      body: Column(
        children: [
          const DataBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _focusProblem(
    BuildContext context, {
    required String key,
    required String title,
    required String message,
  }) {
    final l10n = AppLocalizations.of(context);
    return StateView(
      key: Key(key),
      kind: StateViewKind.empty,
      title: title,
      message: message,
      action: FilledButton(
        key: const Key('map-show-whole'),
        onPressed: () => context.go('/map'),
        child: Text(l10n.mapShowWhole),
      ),
    );
  }
}

/// Live-tracking status above the map: locating, nearest station (a tap
/// opens it), lost signal, or why no position is available.
class _TrackingPanel extends ConsumerWidget {
  const _TrackingPanel({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final source = ref.read(locationSourceProvider);
    Widget line(String text, {Key? key, TextStyle? style}) =>
        Text(text, key: key, style: style ?? theme.textTheme.bodyMedium);

    final children = <Widget>[
      ...switch (state) {
        TrackingOff() => const <Widget>[],
        TrackingStarting() => [
          line(l10n.mapTrackLocating, key: const Key('map-track-locating')),
        ],
        TrackingOn(:final nearest, :final fix, :final lost) => [
          if (nearest == null)
            line(
              l10n.mapTrackNone(
                (trackingNearestRadiusM / 1000).toStringAsFixed(0),
              ),
              key: const Key('map-track-none'),
            )
          else
            InkWell(
              key: const Key('map-track-nearest'),
              onTap: () => openStation(context, nearest.station.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(
                    l10n.mapTrackNearest(
                      stationTitles(
                        nameEn: nearest.station.nameEn,
                        nameHi: nearest.station.nameHi,
                        locale: locale,
                      ).primary,
                    ),
                    key: const Key('map-track-nearest-name'),
                    style: theme.textTheme.titleSmall,
                  ),
                  line(
                    l10n.mapTrackDistance(_distance(l10n, nearest.distanceM)),
                    key: const Key('map-track-distance'),
                  ),
                ],
              ),
            ),
          if (lost)
            line(l10n.mapTrackLost, key: const Key('map-track-lost'))
          else if (fix.isApproximate)
            line(l10n.mapTrackApprox, key: const Key('map-track-approx')),
          line(l10n.mapTrackPrivacy, style: theme.textTheme.bodySmall),
        ],
        TrackingDenied(:final permanent) => [
          line(l10n.nearbyDeniedTitle, style: theme.textTheme.titleSmall),
          line(
            permanent
                ? l10n.nearbyDeniedPermanentBody
                : l10n.mapTrackDeniedBody,
            key: const Key('map-track-denied'),
          ),
          if (permanent)
            TextButton(
              key: const Key('map-track-settings'),
              onPressed: source.openSettings,
              child: Text(l10n.nearbyOpenSettings),
            ),
        ],
        TrackingUnavailable(:final servicesOff) => [
          line(
            servicesOff
                ? l10n.nearbyServicesOffTitle
                : l10n.nearbyUnavailableTitle,
            key: const Key('map-track-unavailable'),
            style: theme.textTheme.titleSmall,
          ),
          if (servicesOff)
            TextButton(
              key: const Key('map-track-location-settings'),
              onPressed: source.openLocationSettings,
              child: Text(l10n.nearbyOpenLocationSettings),
            ),
        ],
      },
    ];
    return Container(
      key: const Key('map-track-panel'),
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.unit * 2,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

String _distance(AppLocalizations l10n, int meters) => meters < 1000
    ? l10n.distanceMeters(meters)
    : l10n.distanceKm((meters / 1000).toStringAsFixed(1));

/// Search for a station to show on the map (the same index as the picker).
class _MapSearchSheet extends StatefulWidget {
  const _MapSearchSheet({required this.services});

  final MetroServices services;

  @override
  State<_MapSearchSheet> createState() => _MapSearchSheetState();
}

class _MapSearchSheetState extends State<_MapSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final results = _q.trim().isEmpty
        ? const <SearchResult>[]
        : widget.services.search.search(
            _q,
            options: const SearchOptions(
              limit: 8,
              scope: SearchScope.stations,
            ),
          );
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.screenPadding,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom +
            AppSpacing.screenPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('map-search-field'),
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
              hintText: l10n.mapSearchHint,
              counterText: '',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          if (_q.trim().isNotEmpty && results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Text(
                l10n.mapSearchNone,
                key: const Key('map-search-none'),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final r in results)
                  if (r.station case final s?)
                    ListTile(
                      key: Key('map-search-result-${s.id}'),
                      title: Text(
                        stationTitles(
                          nameEn: s.nameEn,
                          nameHi: s.nameHi,
                          locale: locale,
                        ).primary,
                      ),
                      subtitle: Text(
                        [
                          ?stationTitles(
                            nameEn: s.nameEn,
                            nameHi: s.nameHi,
                            locale: locale,
                          ).secondary,
                          s.lines.map((l) => l.lineNameEn).join(', '),
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).pop(s.id),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.services});

  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final text = services.snapshot.meta[MetaKeys.attribution];
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.unit * 2,
      ),
      child: Text(
        AppLocalizations.of(context).mapAttribution(text),
        key: const Key('map-attribution'),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The selected route (option [optionIndex]) on the map. Reuses the route
/// lookup of the results screen, so it never shows a route the list would not.
class RouteMapScreen extends ConsumerWidget {
  const RouteMapScreen({
    required this.fromId,
    required this.toId,
    this.optionIndex = 0,
    super.key,
  });

  final String fromId;
  final String toId;
  final int optionIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final geometry = _geometryOrNull(ref);
    final services = ref.watch(metroServicesProvider);
    final lookup = ref.watch(routeLookupProvider(RouteQuery(fromId, toId)));

    Widget body;
    if (geometry == null) {
      body = StateView(
        key: const Key('map-unavailable'),
        kind: StateViewKind.error,
        title: l10n.mapUnavailableTitle,
        message: l10n.mapUnavailableBody,
      );
    } else if (lookup is! RouteFound) {
      body = StateView(
        key: const Key('map-route-not-found'),
        kind: StateViewKind.empty,
        title: l10n.mapRouteNotFoundTitle,
        message: l10n.mapRouteNotFoundBody,
      );
    } else {
      final options = lookup.options;
      final it = options[optionIndex.clamp(0, options.length - 1)].itinerary;
      final overlay = overlayFor(geometry, it);
      final frame = geometry.framingFor(overlay.routeStationIds);
      if (frame == null) {
        body = StateView(
          key: const Key('map-route-no-geometry'),
          kind: StateViewKind.empty,
          title: l10n.mapRouteNoGeometryTitle,
          message: l10n.mapRouteNoGeometryBody,
        );
      } else {
        body = Column(
          children: [
            _RouteSummary(itinerary: it, overlay: overlay, services: services),
            Expanded(
              child: NetworkMap(
                mapKey: const Key('map-route-canvas'),
                geometry: geometry,
                snapshot: services.snapshot,
                frame: frame,
                overlay: overlay,
                onStationTap: (id) => openStation(context, id),
              ),
            ),
            _Legend(overlay: overlay),
          ],
        );
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mapRouteTitle)),
      body: Column(
        children: [
          const DataBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.itinerary,
    required this.overlay,
    required this.services,
  });

  final Itinerary itinerary;
  final MapOverlay overlay;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final minutes = minutesOf(itinerary.totalTimeS);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // same wording and rule as the results screen: estimates say so
            itinerary.timeIsEstimate
                ? l10n.routeApproxMinutes(minutes)
                : '$minutes min',
            key: const Key('map-route-duration'),
            style: theme.textTheme.titleMedium,
          ),
          if (itinerary.timeIsEstimate)
            Text(
              l10n.routeApproxBody,
              key: const Key('map-approx-notice'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.unit * 2),
          Wrap(
            spacing: AppSpacing.unit * 2,
            runSpacing: AppSpacing.unit * 2,
            children: [
              for (final id in overlay.lineIds)
                if (services.snapshot.line(id) != null)
                  LineChip(
                    data: LineChipData(
                      lineId: id,
                      nameEn: services.snapshot.line(id)!.nameEn,
                      nameHi: services.snapshot.line(id)!.nameHi,
                      colorHex: services.snapshot.line(id)!.colorHex,
                      textColorHex: services.snapshot.line(id)!.textColorHex,
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.overlay});

  final MapOverlay overlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.mapLegendInterchange, style: style),
          if (overlay.transferStationIds.isNotEmpty)
            Text(
              l10n.mapLegendTransfer,
              key: const Key('map-legend-transfer'),
              style: style,
            ),
          if (overlay.walks.isNotEmpty)
            Text(
              l10n.mapLegendWalk,
              key: const Key('map-legend-walk'),
              style: style,
            ),
        ],
      ),
    );
  }
}
