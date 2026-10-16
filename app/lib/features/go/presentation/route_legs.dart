import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/shared/format/format.dart';

String _station(MetroServices s, String id, BuildContext context) {
  final st = s.snapshot.station(id);
  if (st == null) return id;
  return stationTitles(
    nameEn: st.nameEn,
    nameHi: st.nameHi,
    locale: Localizations.localeOf(context),
  ).primary;
}

String _line(MetroServices s, String id, BuildContext context) {
  final l = s.snapshot.line(id);
  if (l == null) return id;
  return lineTitles(
    nameEn: l.nameEn,
    nameHi: l.nameHi,
    locale: Localizations.localeOf(context),
  ).primary;
}

/// Legs of an itinerary in order: rides, changes and out-of-system walks.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    required this.itinerary,
    required this.services,
    super.key,
  });

  final Itinerary itinerary;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itinerary.legs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.unit * 3),
            child: switch (itinerary.legs[i]) {
              final RideLeg r => _RideCard(
                index: i,
                leg: r,
                services: services,
              ),
              final TransferLeg t => _TransferCard(
                index: i,
                leg: t,
                services: services,
              ),
              final WalkLeg w => _WalkCard(
                index: i,
                leg: w,
                services: services,
              ),
            },
          ),
      ],
    );
  }
}

class _RideCard extends StatefulWidget {
  const _RideCard({
    required this.index,
    required this.leg,
    required this.services,
  });

  final int index;
  final RideLeg leg;
  final MetroServices services;

  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = widget.services;
    final leg = widget.leg;
    final line = services.snapshot.line(leg.lineId);
    final lineName = _line(services, leg.lineId, context);
    final title = leg.directionTerminalId == null
        ? lineName
        : l10n.rideTowards(
            lineName,
            _station(services, leg.directionTerminalId!, context),
          );
    final theme = Theme.of(context);
    return Card(
      key: Key('ride-${widget.index}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (line != null)
              Container(width: 8, color: colorFromHex(line.colorHex)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.unit),
                    Text(
                      l10n.rideFromTo(
                        _station(services, leg.fromStationId, context),
                        _station(services, leg.toStationId, context),
                      ),
                    ),
                    Text(
                      '${l10n.routeStops(leg.stopCount)} · '
                      '${l10n.rideMinutes(minutesOf(leg.rideS))}',
                    ),
                    if (leg.waitS > 0)
                      Text(
                        l10n.rideWait(minutesOf(leg.waitS)),
                        style: theme.textTheme.bodySmall,
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: Key('ride-toggle-${widget.index}'),
                        onPressed: () => setState(() => _open = !_open),
                        child: Text(
                          _open ? l10n.rideHideStops : l10n.rideShowStops,
                        ),
                      ),
                    ),
                    if (_open)
                      for (final id in leg.stationIds)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.unit,
                          ),
                          child: InkWell(
                            key: Key('stop-${widget.index}-$id'),
                            onTap: () => context.push(
                              '/station/${Uri.encodeComponent(id)}',
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(_station(services, id, context)),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + title + any number of detail lines. (A ListTile has a fixed height
/// and overflows with three lines of text.)
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.unit * 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (lines.isNotEmpty) const SizedBox(height: AppSpacing.unit),
                  ...lines,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.index,
    required this.leg,
    required this.services,
  });

  final int index;
  final TransferLeg leg;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final from = _line(services, leg.fromLineId, context);
    final to = _line(services, leg.toLineId, context);
    if (leg.kind == TransferKind.throughRunning) {
      return _InfoCard(
        cardKey: Key('change-$index'),
        icon: Icons.train_rounded,
        title: l10n.changeThrough(to),
        lines: const [],
      );
    }
    final detail = switch (leg.kind) {
      TransferKind.repeatedStop => l10n.changeRepeatedStop,
      TransferKind.sameLineChange => l10n.changeSameLine,
      _ => null,
    };
    return _InfoCard(
      cardKey: Key('change-$index'),
      icon: Icons.transfer_within_a_station_rounded,
      title: l10n.changeTitle(_station(services, leg.stationId, context)),
      lines: [
        if (leg.fromLineId != leg.toLineId) Text(l10n.changeLines(from, to)),
        if (detail != null) Text(detail),
        Text(
          leg.walkEstimated
              ? l10n.changeWalkEstimated(minutesOf(leg.walkS + leg.waitS))
              : l10n.changeWalkKnown(minutesOf(leg.walkS), leg.walkM),
          key: Key('change-walk-$index'),
        ),
        // step-free is NULL (unknown) in most data: only a known "true" shows
        if (leg.stepFree ?? false)
          Text(
            l10n.changeStepFree,
            style: Theme.of(context).textTheme.labelMedium,
          ),
      ],
    );
  }
}

class _WalkCard extends StatelessWidget {
  const _WalkCard({
    required this.index,
    required this.leg,
    required this.services,
  });

  final int index;
  final WalkLeg leg;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _InfoCard(
      cardKey: Key('walk-$index'),
      icon: Icons.directions_walk_rounded,
      title: l10n.walkTitle(_station(services, leg.toStationId, context)),
      lines: [
        Text(l10n.walkDetail(leg.walkM, minutesOf(leg.walkS))),
        if (leg.requiresExit) Text(l10n.walkLeavesArea),
      ],
    );
  }
}

/// Fare, only when the dataset can price the whole trip. Otherwise says why
/// not; a number is never shown without dataset fare data.
class FareSection extends StatelessWidget {
  const FareSection({required this.option, super.key});

  final RouteOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fare = option.itinerary.fare;
    final theme = Theme.of(context);
    Widget body;
    if (fare == null || fare.status == FareStatus.unavailable) {
      body = Column(
        key: const Key('fare-unavailable'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fareUnavailableTitle, style: theme.textTheme.titleSmall),
          Text(l10n.fareUnavailableBody),
        ],
      );
    } else if (fare.status == FareStatus.partial) {
      body = Text(l10n.farePartial, key: const Key('fare-partial'));
    } else {
      final symbol = currencySymbol(fare.currency);
      String amount(FareQuote q) =>
          l10n.fareAmount(symbol, formatPaise(q.totalPaise!));
      final card = option.cardFare;
      body = Column(
        key: const Key('fare-available'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card != null && card.isAvailable
                ? '${l10n.fareToken}: ${amount(fare)}'
                : amount(fare),
            key: const Key('fare-total'),
            style: theme.textTheme.titleLarge,
          ),
          if (card != null && card.isAvailable)
            Text(
              '${l10n.fareCard}: ${amount(card)}',
              key: const Key('fare-card'),
            ),
          if (fare.separateTicket)
            Text(l10n.fareSeparate(fare.segments.length)),
          Text(
            fare.confidence == Confidence.verified ||
                    fare.confidence == Confidence.official
                ? l10n.fareVerified
                : l10n.fareDerived,
          ),
          Text(l10n.fareDayNote, style: theme.textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.fareTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.unit * 2),
        body,
        const SizedBox(height: AppSpacing.sectionGap),
      ],
    );
  }
}

/// Warnings from the router, shown rather than hidden.
class WarningsSection extends StatelessWidget {
  const WarningsSection({
    required this.itinerary,
    required this.services,
    super.key,
  });

  final Itinerary itinerary;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seen = <String>{};
    final lines = <String>[];
    for (final w in itinerary.warnings) {
      final station = w.stationId == null
          ? ''
          : _station(services, w.stationId!, context);
      final text = switch (w.code) {
        RouteWarningCode.unverifiedTransfer => l10n.warnUnverifiedTransfer(
          station,
        ),
        RouteWarningCode.repeatedStopChange => l10n.warnRepeatedStop(station),
        RouteWarningCode.separateTicket => l10n.warnSeparateTicket,
        // Not produced by the planner; the last-train check is a later step.
        RouteWarningCode.lastTrainUnknown ||
        RouteWarningCode.lastTrainRisk => null,
      };
      if (text != null && seen.add(text)) lines.add(text);
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('warnings'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.warnTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.unit * 2),
        for (final t in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.unit * 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 20),
                const SizedBox(width: AppSpacing.unit * 2),
                Expanded(child: Text(t)),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sectionGap),
      ],
    );
  }
}

/// Which assumptions the displayed times rely on, in plain words.
class AssumptionsSection extends StatelessWidget {
  const AssumptionsSection({
    required this.itinerary,
    required this.services,
    super.key,
  });

  final Itinerary itinerary;
  final MetroServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final waitMin = minutesOf(services.planner.model.boardWaitS);
    final text = <String>[
      for (final a in itinerary.assumptions)
        switch (a) {
          Assumption.rideTimeEstimated => l10n.assumeRide,
          Assumption.boardingWait => l10n.assumeWait(waitMin),
          Assumption.transferWalkTimeEstimated => l10n.assumeTransferTime,
          Assumption.transferWalkDistanceEstimated =>
            l10n.assumeTransferDistance,
          _ => a,
        },
    ];
    return ExpansionTile(
      key: const Key('assumptions'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(l10n.assumptionsTitle),
      children: [
        for (final t in text)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.circle, size: 8),
            title: Text(t),
          ),
      ],
    );
  }
}
