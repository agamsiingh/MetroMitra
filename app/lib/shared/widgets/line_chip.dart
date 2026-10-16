import 'package:flutter/material.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/shared/format/format.dart';

/// A line as a coloured pill. Colours come from the dataset, never the theme;
/// the text is always present (colour is never the only signal).
class LineChip extends StatelessWidget {
  const LineChip({required this.data, super.key});

  final LineChipData data;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final title = lineTitles(
      nameEn: data.nameEn,
      nameHi: data.nameHi,
      locale: locale,
    ).primary;
    final bg = colorFromHex(data.colorHex);
    final fg = colorFromHex(data.textColorHex, fallback: Colors.white);
    final label = data.code == null ? title : '$title · ${data.code}';
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
