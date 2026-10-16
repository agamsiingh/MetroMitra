import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/bootstrap/bootstrap_providers.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/features/map/application/map_provider.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/data_banner.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

/// Width of the drawing in logical pixels; the viewer scales it to fit.
const overviewWidth = 3200.0;

/// One placed label: where it goes and what it says.
class OverviewLabel {
  const OverviewLabel(this.stationId, this.offset, this.painter);

  final String stationId;
  final Offset offset;
  final TextPainter painter;
}

/// The whole network as one poster-style map with every station named in
/// both scripts, laid out from the loaded dataset (nothing is stored as an
/// image). Same layout rules as `tools/export_map.py`: interchanges are
/// labelled first, each label tries eight positions around its station and
/// is skipped if it would overlap another.
class OverviewLayout {
  OverviewLayout._(this.size, this.points, this.labels);

  factory OverviewLayout.build({
    required MapGeometry geometry,
    required MetroSnapshot snapshot,
    required Locale locale,
    required TextStyle primary,
    required TextStyle secondary,
    required TextDirection direction,
  }) {
    final stations = geometry.stations;
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final s in stations) {
      minX = math.min(minX, s.x);
      maxX = math.max(maxX, s.x);
      minY = math.min(minY, s.y);
      maxY = math.max(maxY, s.y);
    }
    const pad = 260.0;
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    final scale = (overviewWidth - 2 * pad) / spanX;
    final height = spanY * scale + 2 * pad;
    final points = {
      for (final s in stations)
        s.id: Offset((s.x - minX) * scale + pad, (s.y - minY) * scale + pad),
    };

    final placed = <Rect>[];
    final labels = <OverviewLabel>[];
    final order = [...stations]
      ..sort((a, b) {
        final c = b.lineIds.length.compareTo(a.lineIds.length);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final bounds = Rect.fromLTWH(8, 8, overviewWidth - 16, height - 16);
    for (final s in order) {
      final st = snapshot.station(s.id);
      if (st == null) continue;
      final titles = stationTitles(
        nameEn: st.nameEn,
        nameHi: st.nameHi,
        locale: locale,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: titles.primary,
          style: primary,
          children: [
            if (titles.secondary != null)
              TextSpan(text: '\n${titles.secondary}', style: secondary),
          ],
        ),
        textDirection: direction,
        maxLines: 2,
      )..layout(maxWidth: 360);
      final p = points[s.id]!;
      final w = tp.width;
      final h = tp.height;
      final tries = [
        Offset(p.dx + 20, p.dy - h / 2),
        Offset(p.dx - 20 - w, p.dy - h / 2),
        Offset(p.dx - w / 2, p.dy - 22 - h),
        Offset(p.dx - w / 2, p.dy + 22),
        Offset(p.dx + 18, p.dy - h - 10),
        Offset(p.dx - 18 - w, p.dy - h - 10),
        Offset(p.dx + 18, p.dy + 10),
        Offset(p.dx - 18 - w, p.dy + 10),
      ];
      for (final o in tries) {
        final r = (o & Size(w, h)).inflate(2);
        if (!bounds.contains(r.topLeft) || !bounds.contains(r.bottomRight)) {
          continue;
        }
        if (placed.any((q) => q.overlaps(r))) continue;
        placed.add(r);
        labels.add(OverviewLabel(s.id, o, tp));
        break;
      }
    }
    return OverviewLayout._(Size(overviewWidth, height), points, labels);
  }

  final Size size;
  final Map<String, Offset> points;
  final List<OverviewLabel> labels;
}

class OverviewPainter extends CustomPainter {
  OverviewPainter({
    required this.geometry,
    required this.layout,
    required this.lineColors,
    required this.ink,
    required this.paper,
  });

  final MapGeometry geometry;
  final OverviewLayout layout;
  final Map<String, Color> lineColors;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    for (final seg in geometry.segments) {
      final a = layout.points[seg.fromId];
      final b = layout.points[seg.toId];
      if (a == null || b == null) continue;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = lineColors[seg.lineId] ?? const Color(0xFF607D8B)
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final s in geometry.stations) {
      final p = layout.points[s.id]!;
      final inter = s.lineIds.length > 1;
      final r = inter ? 15.0 : 8.0;
      canvas
        ..drawCircle(p, r, Paint()..color = paper)
        ..drawCircle(
          p,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = inter ? 5 : 3.5
            ..color = ink,
        );
      if (inter) canvas.drawCircle(p, 4.5, Paint()..color = ink);
    }
    for (final l in layout.labels) {
      l.painter.paint(canvas, l.offset);
    }
  }

  @override
  bool shouldRepaint(OverviewPainter old) =>
      old.layout != layout ||
      old.geometry != geometry ||
      old.ink != ink ||
      old.paper != paper;
}

/// "Overview map": the whole network with every station named, pinch to
/// zoom. Opened from the Map tab.
class OverviewMapScreen extends ConsumerStatefulWidget {
  const OverviewMapScreen({super.key});

  @override
  ConsumerState<OverviewMapScreen> createState() => _OverviewMapScreenState();
}

class _OverviewMapScreenState extends ConsumerState<OverviewMapScreen> {
  OverviewLayout? _layout;
  Locale? _layoutLocale;
  Brightness? _layoutBrightness;
  final _transform = TransformationController();
  bool _fitted = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  OverviewLayout _layoutFor(
    BuildContext context,
    MapGeometry geometry,
    MetroSnapshot snapshot,
  ) {
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    if (_layout != null &&
        _layoutLocale == locale &&
        _layoutBrightness == theme.brightness) {
      return _layout!;
    }
    final color = theme.colorScheme.onSurface;
    final layout = OverviewLayout.build(
      geometry: geometry,
      snapshot: snapshot,
      locale: locale,
      primary: TextStyle(
        color: color,
        fontSize: 21,
        fontWeight: FontWeight.w600,
      ),
      secondary: TextStyle(
        color: color.withValues(alpha: 0.72),
        fontSize: 16,
      ),
      direction: Directionality.of(context),
    );
    _layout = layout;
    _layoutLocale = locale;
    _layoutBrightness = theme.brightness;
    return layout;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final services = ref.watch(metroServicesProvider);
    MapGeometry? geometry;
    try {
      geometry = ref.watch(mapGeometryProvider);
    } on Object {
      geometry = null;
    }
    Widget body;
    if (geometry == null || geometry.isEmpty) {
      body = StateView(
        key: const Key('overview-unavailable'),
        kind: StateViewKind.empty,
        title: l10n.mapEmptyTitle,
        message: l10n.mapEmptyBody,
      );
    } else {
      final geo = geometry;
      final layout = _layoutFor(context, geo, services.snapshot);
      final lineColors = {
        for (final l in services.snapshot.lines) l.id: colorFromHex(l.colorHex),
      };
      body = Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (!_fitted && box.maxWidth > 0 && box.maxHeight > 0) {
                  // first show: the whole network fits the screen
                  final s = math.min(
                    box.maxWidth / layout.size.width,
                    box.maxHeight / layout.size.height,
                  );
                  _transform.value = Matrix4.identity()
                    ..translateByDouble(
                      (box.maxWidth - layout.size.width * s) / 2,
                      (box.maxHeight - layout.size.height * s) / 2,
                      0,
                      1,
                    )
                    ..scaleByDouble(s, s, 1, 1);
                  _fitted = true;
                }
                return ColoredBox(
                  color: theme.colorScheme.surface,
                  child: InteractiveViewer(
                    key: const Key('overview-viewer'),
                    transformationController: _transform,
                    constrained: false,
                    minScale: 0.05,
                    boundaryMargin: const EdgeInsets.all(400),
                    child: Semantics(
                      label: l10n.mapSemantics(geo.stations.length),
                      child: CustomPaint(
                        key: const Key('overview-canvas'),
                        size: layout.size,
                        painter: OverviewPainter(
                          geometry: geo,
                          layout: layout,
                          lineColors: lineColors,
                          ink: theme.colorScheme.onSurface,
                          paper: theme.colorScheme.surface,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _OverviewLegend(snapshot: services.snapshot),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.overviewTitle),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Column(
        children: [
          const DataBanner(),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _OverviewLegend extends StatelessWidget {
  const _OverviewLegend({required this.snapshot});

  final MetroSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    final attribution = snapshot.meta[MetaKeys.attribution];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              key: const Key('overview-legend'),
              spacing: AppSpacing.unit * 2,
              runSpacing: AppSpacing.unit * 2,
              children: [
                for (final l in snapshot.lines)
                  LineChip(
                    data: LineChipData(
                      lineId: l.id,
                      nameEn: l.nameEn,
                      nameHi: l.nameHi,
                      colorHex: l.colorHex,
                      textColorHex: l.textColorHex,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.unit * 2),
            Text(l10n.mapLegendInterchange, style: style),
            Text(
              l10n.overviewNotToScale,
              key: const Key('overview-not-to-scale'),
              style: style,
            ),
            if (attribution != null && attribution.isNotEmpty)
              Text(
                l10n.mapAttribution(attribution),
                key: const Key('overview-attribution'),
                style: style,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
