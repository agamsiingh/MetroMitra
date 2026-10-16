import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/station/application/station_detail.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// S5 Station detail. Resolves only a canonical station id; shows what the
/// dataset says and says so when it says nothing (no guessed facilities,
/// gates, platforms, accessibility or Hindi names).
class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({required this.stationId, super.key});

  final String stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final services = ref.watch(metroServicesProvider);
    final detail = stationDetailFor(services, stationId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.stationTitle)),
      body: detail == null
          ? Column(
              children: [
                const DataBanner(),
                Expanded(
                  child: StateView(
                    key: const Key('station-not-found'),
                    kind: StateViewKind.empty,
                    title: l10n.stationNotFoundTitle,
                    message: l10n.stationNotFoundBody,
                  ),
                ),
              ],
            )
          : _Body(detail: detail),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final StationDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final titles = stationTitles(
      nameEn: detail.nameEn,
      nameHi: detail.nameHi,
      locale: Localizations.localeOf(context),
    );
    final status = switch (detail.status) {
      OperatingStatus.open => l10n.stationStatusOpen,
      OperatingStatus.closed => l10n.stationStatusClosed,
      OperatingStatus.planned => l10n.stationStatusPlanned,
    };

    void routeFrom(JourneyEnd end) {
      ref.read(journeyProvider.notifier).set(end, detail.id);
      context.go('/go');
    }

    return ListView(
      key: const Key('station-detail'),
      padding: EdgeInsets.zero,
      children: [
        const DataBanner(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titles.primary,
                key: const Key('station-name'),
                style: theme.textTheme.headlineSmall,
              ),
              if (titles.secondary != null)
                Text(
                  titles.secondary!,
                  key: const Key('station-name-other'),
                  style: theme.textTheme.titleMedium,
                ),
              const SizedBox(height: AppSpacing.unit * 2),
              Text(
                '${l10n.stationStatusLabel}: $status',
                key: const Key('station-status'),
                style: theme.textTheme.bodyLarge,
              ),
              Text(
                detail.isInterchange
                    ? l10n.stationInterchange
                    : l10n.stationSingleLine,
                key: Key(
                  detail.isInterchange ? 'station-interchange' : 'station-one',
                ),
              ),
              const SizedBox(height: AppSpacing.screenPadding),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('route-from-here'),
                      onPressed: () => routeFrom(JourneyEnd.from),
                      child: Text(l10n.stationRouteFrom),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.unit * 3),
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('route-to-here'),
                      onPressed: () => routeFrom(JourneyEnd.to),
                      child: Text(l10n.stationRouteTo),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('show-on-map'),
                  onPressed: () => context.go(
                    '/map?station=${Uri.encodeQueryComponent(detail.id)}',
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(l10n.mapShowOnMap),
                ),
              ),
              _Section(
                title: l10n.stationLinesTitle,
                child: Wrap(
                  key: const Key('station-lines'),
                  spacing: AppSpacing.unit * 2,
                  runSpacing: AppSpacing.unit * 2,
                  children: [for (final l in detail.lines) LineChip(data: l)],
                ),
              ),
              if (detail.services.isNotEmpty)
                _Section(
                  title: l10n.stationServicesTitle,
                  child: Column(
                    key: const Key('station-services'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in detail.services) Text(s.name),
                    ],
                  ),
                ),
              if (detail.aliases.isNotEmpty)
                _Section(
                  title: l10n.stationAliasesTitle,
                  child: Column(
                    key: const Key('station-aliases'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in detail.aliases)
                        Text(switch (a.kind) {
                          NameKind.old => l10n.stationAliasOld(a.text),
                          NameKind.misspelling => l10n.stationAliasMisspelling(
                            a.text,
                          ),
                          NameKind.landmark => l10n.stationAliasLandmark(
                            a.text,
                          ),
                          _ => l10n.stationAliasPlain(a.text),
                        }),
                    ],
                  ),
                ),
              _Section(
                title: l10n.stationLocationTitle,
                child: Text(
                  detail.hasCoordinates
                      ? l10n.stationCoordinates(
                          detail.lat!.toStringAsFixed(5),
                          detail.lng!.toStringAsFixed(5),
                        )
                      : l10n.stationNoCoordinates,
                  key: const Key('station-coordinates'),
                ),
              ),
              _MoreFacts(detail: detail),
              const SizedBox(height: AppSpacing.screenPadding),
              _Source(provenance: detail.provenance),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.unit * 2),
          child,
        ],
      ),
    );
  }
}

/// Platforms, gates, facilities, accessibility: each shows the dataset's
/// records or "Not in the data yet". Unknown (null) values are left out
/// rather than shown as "no".
class _MoreFacts extends StatelessWidget {
  const _MoreFacts({required this.detail});

  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    // null (unknown) yields no row: it is never shown as "No".
    String? fact(String Function(String) label, {required bool? of}) =>
        of == null ? null : label(of ? l10n.factYes : l10n.factNo);
    final a = detail.accessibility;
    final accessibility = <String>[
      if (a?.lifts != null) l10n.factLifts(a!.lifts!),
      if (a?.escalators != null) l10n.factEscalators(a!.escalators!),
      ?fact(l10n.factTactile, of: a?.tactilePath),
      ?fact(l10n.factWheelchair, of: a?.wheelchairAvailable),
    ];

    Widget block(String key, String title, List<String> rows) => _Section(
      title: title,
      child: Column(
        key: Key(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.isEmpty
            ? [Text(l10n.stationNotInData)]
            : [for (final r in rows) Text(r)],
      ),
    );

    String lineName(String lineId) {
      final line = detail.lines.where((l) => l.lineId == lineId);
      return line.isEmpty
          ? lineId
          : lineTitles(
              nameEn: line.first.nameEn,
              nameHi: line.first.nameHi,
              locale: locale,
            ).primary;
    }

    String facilityName(FacilityType t) => switch (t) {
      FacilityType.atm => l10n.facilityAtm,
      FacilityType.toilet => l10n.facilityToilet,
      FacilityType.drinkingWater => l10n.facilityDrinkingWater,
      FacilityType.helpDesk => l10n.facilityHelpDesk,
      FacilityType.cloakroom => l10n.facilityCloakroom,
      FacilityType.firstAid => l10n.facilityFirstAid,
      FacilityType.shop => l10n.facilityShop,
      FacilityType.other => l10n.facilityOther,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        block('station-platforms', l10n.stationPlatformsTitle, [
          for (final p in detail.platforms)
            l10n.stationPlatform(p.number, lineName(p.lineId)),
        ]),
        block('station-gates', l10n.stationGatesTitle, [
          for (final g in detail.gates)
            [
              if (g.nameEn == null)
                l10n.stationGate('${g.number}')
              else
                l10n.stationGateNamed(
                  '${g.number}',
                  locale.languageCode == 'hi' && g.nameHi != null
                      ? g.nameHi!
                      : g.nameEn!,
                ),
              ?fact(l10n.factLift, of: g.hasLift),
              ?fact(l10n.factRamp, of: g.hasRamp),
              ?fact(l10n.factEscalator, of: g.hasEscalator),
              ?fact(l10n.factStepFree, of: g.isStepFree),
              ?fact(l10n.factGateOpen, of: g.isOpen),
              ...g.landmarks,
            ].join(' · '),
        ]),
        block('station-facilities', l10n.stationFacilitiesTitle, [
          for (final f in detail.facilities)
            () {
              final where = locale.languageCode == 'hi' && f.locationHi != null
                  ? f.locationHi
                  : f.locationEn;
              final name = facilityName(f.type);
              return where == null ? name : l10n.facilityAt(name, where);
            }(),
        ]),
        block(
          'station-accessibility',
          l10n.stationAccessibilityTitle,
          accessibility,
        ),
      ],
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({required this.provenance});

  final Provenance provenance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final confidence = switch (provenance.confidence) {
      Confidence.official => l10n.confOfficial,
      Confidence.verified => l10n.confVerified,
      Confidence.derived => l10n.confDerived,
      Confidence.community => l10n.confCommunity,
    };
    final date = provenance.verifiedOn;
    return Text(
      date == null
          ? l10n.stationSource(provenance.sourceId, confidence)
          : l10n.stationSourceVerified(provenance.sourceId, confidence, date),
      key: const Key('station-source'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
