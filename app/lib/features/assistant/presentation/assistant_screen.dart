import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/assistant/application/answer_text.dart';
import 'package:metromitra/features/assistant/application/assistant_controller.dart';
import 'package:metromitra/features/remote_config/application/remote_config_providers.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';

/// S8 Ask (offline part): type or tap a suggestion; each answer is built from
/// the dataset only and shows its source. No ads, no network.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _field = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = text ?? _field.text;
    if (q.trim().isEmpty) return;
    ref
        .read(assistantProvider.notifier)
        .ask(q, locale: Localizations.localeOf(context).languageCode);
    _field.clear();
    _toEnd();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Puts a question start into the field (Hindi puts the words after the
  /// place, so the cursor goes to the start there).
  void _insert(String text) {
    _field
      ..text = text
      ..selection = TextSelection.collapsed(
        offset: text.startsWith(' ') ? 0 : text.length,
      );
  }

  /// A chip was tapped: answer, then show the new answer (seen on a device:
  /// without scrolling it stayed half under the input field).
  void _choose(AssistantExchange e, String id) {
    ref.read(assistantProvider.notifier).choose(e, id);
    _toEnd();
  }

  Future<void> _pick(AssistantExchange e) async {
    final id = await context.push<String>('/go/pick/to');
    if (id != null && mounted) {
      ref.read(assistantProvider.notifier).choose(e, id);
      _toEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exchanges = ref.watch(assistantProvider);
    final services = ref.watch(metroServicesProvider);
    final renderer = AnswerRenderer(
      l10n,
      services,
      Localizations.localeOf(context),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.askTitle)),
      body: Column(
        children: [
          const DataBanner(),
          Expanded(
            child: ListView(
              key: const Key('ask-list'),
              controller: _scroll,
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                if (exchanges.isEmpty) ...[
                  Text(
                    remoteText(ref, context, 'askIntro', l10n.askIntro),
                    key: const Key('ask-intro'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.screenPadding),
                  Wrap(
                    spacing: AppSpacing.unit * 2,
                    runSpacing: AppSpacing.unit * 2,
                    children: [
                      ActionChip(
                        key: const Key('suggest-route'),
                        label: Text(l10n.askSuggestRoute),
                        onPressed: () => _insert(l10n.askInsertRoute),
                      ),
                      ActionChip(
                        key: const Key('suggest-fare'),
                        label: Text(l10n.askSuggestFare),
                        onPressed: () => _insert(l10n.askInsertFare),
                      ),
                      ActionChip(
                        key: const Key('suggest-last'),
                        label: Text(l10n.askSuggestLast),
                        onPressed: () => _insert(l10n.askInsertLast),
                      ),
                      ActionChip(
                        key: const Key('suggest-nearest'),
                        label: Text(l10n.askSuggestNearest),
                        onPressed: () => _send(l10n.askSuggestNearest),
                      ),
                    ],
                  ),
                ],
                for (var i = 0; i < exchanges.length; i++) ...[
                  _UserTurn(exchange: exchanges[i], renderer: renderer),
                  if (exchanges[i].ai != null)
                    _AiCard(index: i, outcome: exchanges[i].ai!),
                  _AnswerCard(
                    index: i,
                    exchange: exchanges[i],
                    renderer: renderer,
                    isLatest: i == exchanges.length - 1,
                    onPick: _pick,
                    onChoose: _choose,
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.unit * 2,
                AppSpacing.unit * 2,
                AppSpacing.unit * 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('ask-field'),
                      controller: _field,
                      maxLength: AssistantController.maxLength,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.askHint,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.buttonRadius,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    key: const Key('ask-send'),
                    tooltip: l10n.askSend,
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 56,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTurn extends StatelessWidget {
  const _UserTurn({required this.exchange, required this.renderer});

  final AssistantExchange exchange;
  final AnswerRenderer renderer;

  @override
  Widget build(BuildContext context) {
    final text =
        exchange.question ??
        renderer.l10n.askChosen(renderer.station(exchange.chosenStationId!));
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.only(
          top: AppSpacing.screenPadding,
          bottom: AppSpacing.unit * 2,
          left: AppSpacing.sectionGap * 2,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: AppSpacing.unit * 3,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: Text(text),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.index,
    required this.exchange,
    required this.renderer,
    required this.isLatest,
    required this.onPick,
    required this.onChoose,
  });

  final int index;
  final AssistantExchange exchange;
  final AnswerRenderer renderer;
  final bool isLatest;
  final Future<void> Function(AssistantExchange) onPick;
  final void Function(AssistantExchange, String) onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = exchange.answer;
    final text = renderer.render(a);
    final showSource =
        a.kind == AnswerKind.answer || a.kind == AnswerKind.missing;
    return Card(
      key: Key('answer-$index'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.headline,
                key: Key('answer-$index-headline'),
                style: theme.textTheme.titleMedium,
              ),
              for (final l in text.lines)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.unit),
                  child: Text(l),
                ),
              // choices only on the latest answer: older ones are history
              if (isLatest && a.choices.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.unit * 2),
                Wrap(
                  spacing: AppSpacing.unit * 2,
                  runSpacing: AppSpacing.unit * 2,
                  children: [
                    for (final id in a.choices)
                      ActionChip(
                        key: Key('choice-$id'),
                        label: Text(renderer.station(id)),
                        onPressed: () => onChoose(exchange, id),
                      ),
                  ],
                ),
              ],
              if (a.actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.unit * 2),
                Wrap(
                  spacing: AppSpacing.unit * 2,
                  children: [
                    for (final act in a.actions)
                      if (act is! PickStationAction || isLatest)
                        _actionButton(context, act),
                  ],
                ),
              ],
              if (showSource) ...[
                const SizedBox(height: AppSpacing.unit * 2),
                Text(
                  renderer.source(a),
                  key: Key('answer-$index-source'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(BuildContext context, AssistantAction act) {
    final l10n = renderer.l10n;
    return switch (act) {
      OpenRouteAction(:final fromId, :final toId) => TextButton(
        key: Key('act-route-$index'),
        onPressed: () => context.push(
          '/go/route?from=${Uri.encodeQueryComponent(fromId)}'
          '&to=${Uri.encodeQueryComponent(toId)}',
        ),
        child: Text(l10n.actOpenRoute),
      ),
      OpenStationAction(:final stationId) => TextButton(
        key: Key('act-station-$index'),
        onPressed: () =>
            context.push('/station/${Uri.encodeComponent(stationId)}'),
        child: Text(l10n.actOpenStation),
      ),
      OpenNearbyAction() => TextButton(
        key: Key('act-nearby-$index'),
        onPressed: () => context.push('/go/nearby'),
        child: Text(l10n.nearbyButton),
      ),
      PickStationAction() => FilledButton.tonal(
        key: Key('act-pick-$index'),
        onPressed: () => onPick(exchange),
        child: Text(l10n.actChooseStation),
      ),
    };
  }
}

/// The optional online AI answer, always labelled as generated text.
class _AiCard extends StatelessWidget {
  const _AiCard({required this.index, required this.outcome});

  final int index;
  final AiOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = switch (outcome.status) {
      AiStatus.pending => l10n.askAiPending,
      AiStatus.answered => outcome.text ?? '',
      AiStatus.offline => l10n.askAiOffline,
      AiStatus.busy => l10n.askAiBusy,
      AiStatus.refused => l10n.askAiRefused,
    };
    final answered = outcome.status == AiStatus.answered;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.unit * 2),
      child: Card(
        key: Key('ai-$index'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (answered)
                  Text(
                    l10n.askAiLabel,
                    key: Key('ai-$index-label'),
                    style: theme.textTheme.labelMedium,
                  ),
                if (outcome.status == AiStatus.pending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.unit * 2),
                    child: LinearProgressIndicator(),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.unit),
                  child: Text(text, key: Key('ai-$index-text')),
                ),
                if (answered) ...[
                  const SizedBox(height: AppSpacing.unit * 2),
                  Text(l10n.askAiSent, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
