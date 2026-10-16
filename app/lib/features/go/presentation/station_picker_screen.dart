import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/journey_provider.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// S2 Station picker. Returns the chosen station's canonical id through the
/// route (`context.pop(id)`); display names are never used to identify it.
class StationPickerScreen extends ConsumerStatefulWidget {
  const StationPickerScreen({required this.end, super.key});

  final JourneyEnd end;

  @override
  ConsumerState<StationPickerScreen> createState() =>
      _StationPickerScreenState();
}

class _StationPickerScreenState extends ConsumerState<StationPickerScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = ref.watch(metroServicesProvider);
    final results = searchStationOptions(services, _controller.text);
    final title = widget.end == JourneyEnd.from
        ? l10n.homePickFrom
        : l10n.homePickTo;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          const DataBanner(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: TextField(
              key: const Key('picker-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.pickerHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('picker-clear'),
                        tooltip: l10n.pickerClear,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_controller.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                ),
              ),
            ),
          ),
          Expanded(child: _Body(results: results)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.results});

  final PickerResults results;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (results.isBlank) {
      return StateView(
        key: const Key('picker-blank'),
        kind: StateViewKind.empty,
        title: l10n.pickerBlankTitle,
        message: l10n.pickerBlankBody,
      );
    }
    if (results.isEmpty) {
      return StateView(
        key: const Key('picker-no-results'),
        kind: StateViewKind.empty,
        title: l10n.pickerNoResultsTitle(results.query.trim()),
        message: l10n.pickerNoResultsBody,
      );
    }
    return ListView(
      key: const Key('picker-results'),
      children: [
        for (final o in results.direct) _OptionTile(option: o),
        if (results.similar.isNotEmpty)
          Padding(
            key: const Key('picker-similar-header'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.screenPadding,
              AppSpacing.screenPadding,
              AppSpacing.unit,
            ),
            child: Text(
              results.direct.isEmpty
                  ? l10n.pickerDidYouMean
                  : l10n.pickerSimilar,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        for (final o in results.similar) _OptionTile(option: o),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option});

  final StationOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = stationTitles(
      nameEn: option.nameEn,
      nameHi: option.nameHi,
      locale: Localizations.localeOf(context),
    );
    return InkWell(
      key: Key('station-option-${option.id}'),
      // The canonical id is what the picker returns, not the text shown.
      onTap: () => context.pop(option.id),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      titles.primary,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (option.isInterchange)
                    Chip(
                      key: Key('interchange-${option.id}'),
                      label: Text(l10n.pickerInterchange),
                      visualDensity: VisualDensity.compact,
                    ),
                  IconButton(
                    key: Key('station-info-${option.id}'),
                    tooltip: l10n.stationInfoTooltip,
                    icon: const Icon(Icons.info_outline_rounded),
                    onPressed: () => context.push(
                      '/station/${Uri.encodeComponent(option.id)}',
                    ),
                  ),
                ],
              ),
              if (titles.secondary != null)
                Text(
                  titles.secondary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              if (option.matchedText != null)
                Text(
                  l10n.pickerMatched(option.matchedText!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.unit * 2),
              Wrap(
                spacing: AppSpacing.unit * 2,
                runSpacing: AppSpacing.unit * 2,
                children: [for (final l in option.lines) LineChip(data: l)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
