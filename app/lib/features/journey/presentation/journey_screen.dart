import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/bootstrap/metro_services.dart';
import 'package:metromitra/features/go/application/route_lookup.dart';
import 'package:metromitra/features/journey/application/journey_controller.dart';
import 'package:metromitra/shared/data/keep_awake.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// How often the screen re-reads the clock to move the stop estimate.
const journeyTick = Duration(seconds: 10);

/// S4 Journey mode: one big current step, one primary action, the next step
/// as a preview. Platforms, gates and exits appear only when the dataset has
/// them; otherwise the screen says they are unavailable. No ads.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  Timer? _ticker;
  bool? _awake;
  bool _locating = false;
  int? _alertedStep;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(journeyTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_awake ?? false) unawaited(_keepAwake.set(on: false));
    super.dispose();
  }

  late final KeepAwake _keepAwake = ref.read(keepAwakeProvider);

  void _syncKeepAwake(bool want) {
    if (_awake == want) return;
    _awake = want;
    unawaited(_keepAwake.set(on: want));
  }

  Future<void> _confirmEnd() async {
    final l10n = AppLocalizations.of(context);
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('end-journey-dialog'),
        title: Text(l10n.journeyEndTitle),
        content: Text(l10n.journeyEndBody),
        actions: [
          TextButton(
            key: const Key('end-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.journeyEndCancel),
          ),
          FilledButton(
            key: const Key('end-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.journeyEndConfirm),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;
    await ref.read(activeJourneyProvider.notifier).end();
    if (mounted) context.go('/go');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(activeJourneyProvider);
    if (session is! JourneyRunning) {
      _syncKeepAwake(false);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.journeyTitle)),
        body: StateView(
          key: const Key('journey-none'),
          kind: StateViewKind.empty,
          title: l10n.journeyNoneTitle,
          message: l10n.journeyNoneBody,
          action: FilledButton(
            onPressed: () => context.go('/go'),
            child: Text(l10n.navGo),
          ),
        ),
      );
    }
    final journey = session.journey;
    _syncKeepAwake(journey.keepAwake);
    final services = ref.watch(metroServicesProvider);
    final now = ref.watch(clockProvider)().millisecondsSinceEpoch;
    final progress = journey.engine.progress(journey.state, now);
    if (progress.getOffNext && _alertedStep != progress.stepIndex) {
      // in-app "get off next" alert with a vibration (foreground only)
      _alertedStep = progress.stepIndex;
      unawaited(HapticFeedback.vibrate());
    }
    final steps = journey.plan.steps;
    final next = progress.isLastStep ? null : steps[progress.stepIndex + 1];
    final text = _StepText(l10n, services, Localizations.localeOf(context));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmEnd());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.journeyTitle),
          actions: [
            IconButton(
              key: const Key('journey-close'),
              tooltip: l10n.journeyEndConfirm,
              icon: const Icon(Icons.close_rounded),
              onPressed: _confirmEnd,
            ),
          ],
        ),
        body: ListView(
          key: const Key('journey'),
          padding: EdgeInsets.zero,
          children: [
            const DataBanner(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.journeyStepOf(progress.stepIndex + 1, steps.length),
                    key: const Key('journey-step-count'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.unit * 2),
                  _CurrentStep(progress: progress, text: text),
                  const SizedBox(height: AppSpacing.screenPadding),
                  FilledButton(
                    key: const Key('journey-primary'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () async {
                      final wasLast = progress.isLastStep;
                      await ref.read(activeJourneyProvider.notifier).advance();
                      if (wasLast && context.mounted) context.go('/go');
                    },
                    child: Text(text.action(progress.step.kind)),
                  ),
                  const SizedBox(height: AppSpacing.unit * 2),
                  Wrap(
                    spacing: AppSpacing.unit * 2,
                    runSpacing: AppSpacing.unit * 2,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('journey-correct'),
                        onPressed: () => _pickStation(journey, text),
                        icon: const Icon(Icons.place_outlined),
                        label: Text(l10n.journeyCorrect),
                      ),
                      OutlinedButton.icon(
                        key: const Key('journey-locate'),
                        // a fix can take up to 10 s: say so, and no double tap
                        onPressed: _locating ? null : _snap,
                        icon: _locating
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(
                          _locating
                              ? l10n.nearbyLocating
                              : l10n.journeyUseLocation,
                        ),
                      ),
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: AppSpacing.sectionGap),
                    Text(
                      l10n.journeyNext(text.title(next)),
                      key: const Key('next-step'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                  if (journey.itinerary.timeIsEstimate) ...[
                    const SizedBox(height: AppSpacing.screenPadding),
                    Text(
                      l10n.journeyEstimateNote,
                      key: const Key('journey-estimate-note'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.screenPadding),
                  SwitchListTile(
                    key: const Key('keep-awake'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.journeyKeepAwake),
                    value: journey.keepAwake,
                    onChanged: (v) => ref
                        .read(activeJourneyProvider.notifier)
                        .setKeepAwake(on: v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStation(ActiveJourney journey, _StepText text) async {
    final l10n = AppLocalizations.of(context);
    final ids = journey.engine.correctableStations();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const Key('correct-sheet'),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Text(
                l10n.journeyCorrectTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final id in ids)
              ListTile(
                key: Key('correct-$id'),
                minTileHeight: 56,
                title: Text(text.station(id)),
                onTap: () => Navigator.of(context).pop(id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(activeJourneyProvider.notifier).correctTo(picked);
  }

  Future<void> _snap() async {
    final l10n = AppLocalizations.of(context);
    final services = ref.read(metroServicesProvider);
    setState(() => _locating = true);
    final (result, id) = await ref
        .read(activeJourneyProvider.notifier)
        .snapToLocation();
    if (!mounted) return;
    setState(() => _locating = false);
    final text = _StepText(l10n, services, Localizations.localeOf(context));
    final message = switch (result) {
      SnapResult.moved => l10n.journeyLocated(text.station(id!)),
      SnapResult.notNear => l10n.journeyNotNear,
      SnapResult.denied => l10n.journeyLocationDenied,
      SnapResult.unavailable ||
      SnapResult.invalid => l10n.journeyLocationUnavailable,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(key: const Key('journey-snack'), content: Text(message)),
      );
  }
}

/// Texts of steps, built from the dataset in the UI language.
class _StepText {
  _StepText(this.l10n, this.services, this.locale);

  final AppLocalizations l10n;
  final MetroServices services;
  final Locale locale;

  String station(String id) {
    final s = services.snapshot.station(id);
    if (s == null) return id;
    return stationTitles(
      nameEn: s.nameEn,
      nameHi: s.nameHi,
      locale: locale,
    ).primary;
  }

  String line(String? id) {
    final l = id == null ? null : services.snapshot.line(id);
    if (l == null) return id ?? '';
    return lineTitles(
      nameEn: l.nameEn,
      nameHi: l.nameHi,
      locale: locale,
    ).primary;
  }

  String title(JourneyStep s) => switch (s.kind) {
    JourneyStepKind.enter => l10n.journeyEnter(station(s.stationId)),
    JourneyStepKind.board =>
      s.towardsStationId == null
          ? l10n.journeyBoard(line(s.lineId))
          : l10n.journeyBoardTowards(
              line(s.lineId),
              station(s.towardsStationId!),
            ),
    JourneyStepKind.ride => l10n.journeyRide(station(s.toStationId!)),
    JourneyStepKind.change => l10n.changeTitle(station(s.stationId)),
    JourneyStepKind.stayOnBoard => l10n.changeThrough(line(s.toLineId)),
    JourneyStepKind.walk => l10n.walkTitle(station(s.toStationId!)),
    JourneyStepKind.exit => l10n.journeyExit(station(s.stationId)),
  };

  String action(JourneyStepKind k) => switch (k) {
    JourneyStepKind.enter => l10n.journeyActionEnter,
    JourneyStepKind.board => l10n.journeyActionBoard,
    JourneyStepKind.ride => l10n.journeyActionRide,
    JourneyStepKind.change => l10n.journeyActionChange,
    JourneyStepKind.stayOnBoard => l10n.journeyActionStay,
    JourneyStepKind.walk => l10n.journeyActionWalk,
    JourneyStepKind.exit => l10n.journeyActionDone,
  };

  String gate(GateInfo g) {
    final hi = locale.languageCode == 'hi';
    final name = hi && g.nameHi != null ? g.nameHi : g.nameEn;
    return [
      if (name == null)
        l10n.stationGate('${g.number}')
      else
        l10n.stationGateNamed('${g.number}', name),
      if (g.hasLift ?? false) l10n.journeyGateLift,
      if (g.isStepFree ?? false) l10n.journeyGateStepFree,
      for (var i = 0; i < g.landmarksEn.length; i++)
        hi && g.landmarksHi[i] != null ? g.landmarksHi[i]! : g.landmarksEn[i],
    ].join(' · ');
  }
}

class _CurrentStep extends StatelessWidget {
  const _CurrentStep({required this.progress, required this.text});

  final JourneyProgress progress;
  final _StepText text;

  @override
  Widget build(BuildContext context) {
    final l10n = text.l10n;
    final theme = Theme.of(context);
    final s = progress.step;
    final details = <Widget>[];
    void line(String t, {Key? key, TextStyle? style}) => details.add(
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.unit * 2),
        child: Text(t, key: key, style: style ?? theme.textTheme.bodyLarge),
      ),
    );

    switch (s.kind) {
      case JourneyStepKind.enter:
      case JourneyStepKind.exit:
        if (s.gates.isEmpty) {
          line(
            s.kind == JourneyStepKind.enter
                ? l10n.journeyEntryUnknown
                : l10n.journeyExitUnknown,
            key: const Key('gates-unknown'),
          );
        } else {
          line(l10n.journeyGates, style: theme.textTheme.titleSmall);
          for (final g in s.gates) {
            line(text.gate(g), key: Key('gate-${g.id}'));
          }
        }
        if (s.kind == JourneyStepKind.exit) {
          // no destination landmark is known, so no "best" exit is claimed
          line(
            l10n.journeyNoBestExit,
            key: const Key('no-best-exit'),
            style: theme.textTheme.bodySmall,
          );
        }
      case JourneyStepKind.board:
        line(l10n.journeyBoardAt(text.station(s.stationId)));
        final p = s.platform;
        line(
          p == null
              ? l10n.journeyPlatformUnknown
              : (p.provenance.confidence == Confidence.official ||
                    p.provenance.confidence == Confidence.verified)
              ? l10n.journeyPlatform(p.number)
              : l10n.journeyPlatformUnverified(p.number),
          key: const Key('platform'),
          // a known platform is the thing to look for; "unknown" must not shout
          style: p == null
              ? theme.textTheme.bodyLarge
              : theme.textTheme.headlineSmall,
        );
        if (s.towardsStationId == null) line(l10n.journeyNoDirection);
      case JourneyStepKind.ride:
        final pos = progress.positionIndex ?? 0;
        // at the stop the red "get off here" line says it all (seen on a
        // device: "You should be there" twice read as noise)
        if (!progress.shouldBeThere) {
          line(
            l10n.journeyStopsLeft(progress.stopsRemaining ?? s.stopCount),
            key: const Key('stops-left'),
            style: theme.textTheme.headlineSmall,
          );
        }
        if (progress.shouldBeThere) {
          line(
            l10n.journeyShouldBeThere(text.station(s.toStationId!)),
            key: const Key('should-be-there'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        } else {
          if (progress.getOffNext) {
            line(
              l10n.journeyGetOffNext,
              key: const Key('get-off-next'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            );
          }
          line(
            l10n.journeyNear(text.station(s.stationIds[pos])),
            key: const Key('near'),
          );
        }
      case JourneyStepKind.change:
        if (s.lineId != s.toLineId) {
          line(l10n.changeLines(text.line(s.lineId), text.line(s.toLineId)));
        }
        if (s.transferKind == TransferKind.repeatedStop) {
          line(l10n.changeRepeatedStop);
        } else if (s.transferKind == TransferKind.sameLineChange) {
          line(l10n.changeSameLine);
        }
        line(
          s.walkEstimated
              ? l10n.changeWalkEstimated(minutesOf(s.walkS ?? 0))
              : l10n.changeWalkKnown(minutesOf(s.walkS ?? 0), s.walkM ?? 0),
          key: const Key('change-walk'),
        );
        if (s.stepFree ?? false) line(l10n.changeStepFree);
      case JourneyStepKind.stayOnBoard:
        break;
      case JourneyStepKind.walk:
        line(l10n.walkDetail(s.walkM ?? 0, minutesOf(s.walkS ?? 0)));
        if (s.requiresExit) line(l10n.walkLeavesArea);
    }

    return Card(
      key: const Key('current-step'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.title(s),
                key: const Key('step-title'),
                style: theme.textTheme.headlineMedium,
              ),
              ...details,
            ],
          ),
        ),
      ),
    );
  }
}
