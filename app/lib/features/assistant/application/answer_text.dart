import 'dart:ui';

import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/shared/format/format.dart';

/// An answer as text: a headline and detail lines. Built **only** from the
/// answer's template and facts (docs/ai.md: the renderer only interpolates
/// facts), with names looked up by canonical id in the UI language.
class AnswerText {
  const AnswerText(this.headline, [this.lines = const []]);

  final String headline;
  final List<String> lines;
}

class AnswerRenderer {
  AnswerRenderer(this.l10n, this.services, this.locale);

  final AppLocalizations l10n;
  final MetroServices services;
  final Locale locale;

  bool get _hi => locale.languageCode == 'hi';

  String station(String id) {
    final s = services.snapshot.station(id);
    if (s == null) return id;
    return stationTitles(
      nameEn: s.nameEn,
      nameHi: s.nameHi,
      locale: locale,
    ).primary;
  }

  String line(String id) {
    final l = services.snapshot.line(id);
    if (l == null) return id;
    return lineTitles(
      nameEn: l.nameEn,
      nameHi: l.nameHi,
      locale: locale,
    ).primary;
  }

  /// Minutes since 00:00 of the service day -> "HH:MM"; past midnight is
  /// said so.
  String clock(int minutes) {
    final m = minutes % 1440;
    final t =
        '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
    return minutes >= 1440 ? l10n.ansNextDay(t) : t;
  }

  String gate(GateInfo g) {
    final name = _hi && g.nameHi != null ? g.nameHi : g.nameEn;
    return [
      if (name == null)
        l10n.stationGate('${g.number}')
      else
        l10n.stationGateNamed('${g.number}', name),
      if (g.hasLift ?? false) l10n.journeyGateLift,
      if (g.isStepFree ?? false) l10n.journeyGateStepFree,
      for (var i = 0; i < g.landmarksEn.length; i++)
        _hi && g.landmarksHi[i] != null ? g.landmarksHi[i]! : g.landmarksEn[i],
    ].join(' · ');
  }

  String facility(FacilityType t) => switch (t) {
    FacilityType.atm => l10n.facilityAtm,
    FacilityType.toilet => l10n.facilityToilet,
    FacilityType.drinkingWater => l10n.facilityDrinkingWater,
    FacilityType.helpDesk => l10n.facilityHelpDesk,
    FacilityType.cloakroom => l10n.facilityCloakroom,
    FacilityType.firstAid => l10n.facilityFirstAid,
    FacilityType.shop => l10n.facilityShop,
    FacilityType.other => l10n.facilityOther,
  };

  /// A label used inside an English sentence starts lower-case ("no record
  /// of toilet"); Hindi has no case.
  /// Acronyms ("ATM") are kept.
  String _inSentence(String label) =>
      _hi || label.length < 2 || label[1] != label[1].toLowerCase()
      ? label
      : label[0].toLowerCase() + label.substring(1);

  String _yn(bool v) => v ? l10n.factYes : l10n.factNo;

  String _money(String currency, int paise) =>
      l10n.fareAmount(currencySymbol(currency), formatPaise(paise));

  AnswerText render(AssistantAnswer a) {
    String id(String k) => a.fact<String>(k);
    List<String> ids(String k) => a.fact<List<Object>>(k).cast<String>();
    switch (a.template) {
      case AnswerTemplate.routeSummary:
        final minutes = a.fact<int>('minutes');
        return AnswerText(
          l10n.ansRouteSummary(
            station(id('fromId')),
            station(id('toId')),
            a.fact<bool>('approx')
                ? l10n.routeApproxMinutes(minutes)
                : l10n.ansMinutes(minutes),
            l10n.routeChanges(a.fact<int>('changes')),
            l10n.routeStops(a.fact<int>('stops')),
          ),
          [
            l10n.ansLines(ids('lineIds').map(line).join(', ')),
            if (ids('transferIds').isNotEmpty)
              l10n.ansChangeAt(ids('transferIds').map(station).join(', ')),
          ],
        );
      case AnswerTemplate.routeSameStation:
        return AnswerText(l10n.ansRouteSame(station(id('stationId'))));
      case AnswerTemplate.routeNone:
        return a.facts.containsKey('fromId')
            ? AnswerText(
                l10n.ansRouteNone(station(id('fromId')), station(id('toId'))),
              )
            : AnswerText(l10n.ansLineNoServices);
      case AnswerTemplate.nearestOpen:
        return AnswerText(l10n.ansNearest);
      case AnswerTemplate.gatesList:
        return AnswerText(l10n.ansGatesList(station(id('stationId'))), [
          for (final g in a.fact<List<Object>>('gates').cast<GateInfo>())
            gate(g),
        ]);
      case AnswerTemplate.gateForLandmark:
        return AnswerText(
          l10n.ansGateForLandmark(id('landmark'), station(id('stationId'))),
          [
            for (final g in a.fact<List<Object>>('gates').cast<GateInfo>())
              gate(g),
          ],
        );
      case AnswerTemplate.gateLandmarkUnknown:
        return AnswerText(
          l10n.ansGateLandmarkUnknown(
            id('landmark'),
            station(id('stationId')),
          ),
          [
            for (final g in a.fact<List<Object>>('gates').cast<GateInfo>())
              gate(g),
          ],
        );
      case AnswerTemplate.gatesMissing:
        return AnswerText(l10n.ansGatesMissing(station(id('stationId'))));
      case AnswerTemplate.platformFound:
        final towards = a.factOrNull<String>('towardsId');
        return AnswerText(
          towards == null
              ? l10n.ansPlatformFoundNoDirection(
                  station(id('stationId')),
                  line(id('lineId')),
                  station(id('destinationId')),
                  id('number'),
                )
              : l10n.ansPlatformFound(
                  station(id('stationId')),
                  line(id('lineId')),
                  station(towards),
                  id('number'),
                ),
          [if (!a.fact<bool>('verified')) l10n.ansUnverified],
        );
      case AnswerTemplate.platformMissing:
        return AnswerText(
          l10n.ansPlatformMissing(line(id('lineId')), station(id('stationId'))),
        );
      case AnswerTemplate.fareFound:
        final currency = a.fact<String>('currency');
        final card = a.factOrNull<int>('cardPaise');
        return AnswerText(
          l10n.ansFareFound(
            station(id('fromId')),
            station(id('toId')),
            _money(currency, a.fact<int>('paise')),
          ),
          [
            if (card != null) l10n.ansFareCard(_money(currency, card)),
            l10n.fareDayNote,
          ],
        );
      case AnswerTemplate.fareMissing:
        return AnswerText(
          l10n.ansFareMissing(station(id('fromId')), station(id('toId'))),
        );
      case AnswerTemplate.firstLastFound:
        final first = a.fact<bool>('first');
        final last = a.fact<bool>('last');
        return AnswerText(l10n.ansFirstLastFound(station(id('stationId'))), [
          for (final t in a.fact<List<Object>>('rows').cast<TimingFact>())
            first && last
                ? l10n.ansFirstLastRow(
                    station(t.terminalId),
                    clock(t.firstDep),
                    clock(t.lastDep),
                  )
                : first
                ? l10n.ansFirstRow(station(t.terminalId), clock(t.firstDep))
                : l10n.ansLastRow(station(t.terminalId), clock(t.lastDep)),
          if (a.fact<DayType>('dayType') == DayType.sundayHoliday)
            l10n.ansDaySunday
          else
            l10n.ansDayRegular,
        ]);
      case AnswerTemplate.firstLastMissing:
        return AnswerText(l10n.ansFirstLastMissing(station(id('stationId'))));
      case AnswerTemplate.interchangeNone:
        return AnswerText(
          l10n.ansInterchangeNone(station(id('fromId')), station(id('toId'))),
        );
      case AnswerTemplate.interchangeAt:
        return AnswerText(
          l10n.ansChangeAt(ids('transferIds').map(station).join(', ')),
          [l10n.ansLines(ids('lineIds').map(line).join(' → '))],
        );
      case AnswerTemplate.facilitiesList || AnswerTemplate.facilityFound:
        return AnswerText(l10n.ansFacilitiesList(station(id('stationId'))), [
          for (final f in a.fact<List<Object>>('items').cast<Facility>())
            () {
              final where = _hi && f.locationHi != null
                  ? f.locationHi
                  : f.locationEn;
              return where == null
                  ? facility(f.type)
                  : l10n.facilityAt(facility(f.type), where);
            }(),
        ]);
      case AnswerTemplate.facilityMissing:
        final f = a.factOrNull<FacilityType>('facility');
        return AnswerText(
          f == null
              ? l10n.ansFacilitiesMissing(station(id('stationId')))
              : l10n.ansFacilityMissing(
                  _inSentence(facility(f)),
                  station(id('stationId')),
                ),
        );
      case AnswerTemplate.accessibilityFound:
        final lifts = a.factOrNull<int>('lifts');
        final esc = a.factOrNull<int>('escalators');
        final tactile = a.factOrNull<bool>('tactile');
        final wheel = a.factOrNull<bool>('wheelchair');
        final liftGates = a.fact<List<Object>>('liftGates').cast<int>();
        return AnswerText(
          l10n.ansAccessibilityFound(station(id('stationId'))),
          [
            if (lifts != null) l10n.factLifts(lifts),
            if (esc != null) l10n.factEscalators(esc),
            if (tactile != null) l10n.factTactile(_yn(tactile)),
            if (wheel != null) l10n.factWheelchair(_yn(wheel)),
            if (liftGates.isNotEmpty) l10n.ansLiftGates(liftGates.join(', ')),
          ],
        );
      case AnswerTemplate.accessibilityMissing:
        return AnswerText(
          l10n.ansAccessibilityMissing(station(id('stationId'))),
        );
      case AnswerTemplate.parkingMissing:
        return AnswerText(l10n.ansParkingMissing(station(id('stationId'))));
      case AnswerTemplate.lineInfo:
        final stops = ids('stationIds');
        return AnswerText(l10n.ansLineInfo(line(id('lineId')), stops.length), [
          stops.map(station).join(' → '),
        ]);
      case AnswerTemplate.stationNotFound:
        return AnswerText(l10n.ansNotFound(id('text')));
      case AnswerTemplate.clarifyStation:
        return AnswerText(l10n.ansClarifyStation(id('text')));
      case AnswerTemplate.askFrom:
        return AnswerText(l10n.ansAskFrom);
      case AnswerTemplate.askTo:
        return AnswerText(l10n.ansAskTo);
      case AnswerTemplate.askStation:
        return AnswerText(l10n.ansAskStation);
      case AnswerTemplate.askDestination:
        return AnswerText(l10n.ansAskDestination);
      case AnswerTemplate.unknown:
        return AnswerText(l10n.ansUnknown);
    }
  }

  /// "Source: metro data (version) · (confidence) · checked (date)" from
  /// the facts' provenance (the weakest confidence is shown).
  String source(AssistantAnswer a) {
    if (a.sources.isEmpty) return l10n.askSource(a.datasetVersion);
    final weakest = a.sources.reduce(
      (x, y) => x.confidence.index >= y.confidence.index ? x : y,
    );
    final conf = switch (weakest.confidence) {
      Confidence.official => l10n.confOfficial,
      Confidence.verified => l10n.confVerified,
      Confidence.derived => l10n.confDerived,
      Confidence.community => l10n.confCommunity,
    };
    final dated = weakest.verifiedOn == null
        ? conf
        : '$conf · ${l10n.askSourceChecked(weakest.verifiedOn!)}';
    return l10n.askSourceConfidence(a.datasetVersion, dated);
  }
}
