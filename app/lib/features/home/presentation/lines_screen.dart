import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/shared/format/format.dart';

/// Every line in the dataset with its own colour and the number of stations
/// it serves. Nothing here is typed in: names, colours and counts are data.
class LinesScreen extends ConsumerWidget {
  const LinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(metroServicesProvider).snapshot;
    final lines = [...snapshot.lines]..sort((a, b) => a.sort.compareTo(b.sort));
    final isHindi = Localizations.localeOf(context).languageCode == 'hi';
    int stationCount(String lineId) => {
      for (final sl in snapshot.stationLines)
        if (sl.lineId == lineId) sl.stationId,
    }.length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.linesTitle)),
      body: lines.isEmpty
          ? Center(child: Text(l10n.linesEmpty))
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final line = lines[i];
                final color = colorFromHex(line.colorHex);
                final name = isHindi && line.nameHi != null
                    ? line.nameHi!
                    : line.nameEn;
                return Card(
                  key: Key('line-${line.id}'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Container(width: 8, color: color),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                l10n.linesSubtitle(stationCount(line.id)),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
