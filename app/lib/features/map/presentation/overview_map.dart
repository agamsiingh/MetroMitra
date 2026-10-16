import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/app/theme/tokens.dart';
import 'package:metromitra/features/go/application/station_options.dart';
import 'package:metromitra/features/map/application/map_overlay.dart';
import 'package:metromitra/features/map/presentation/network_map.dart';
import 'package:metromitra/shared/format/format.dart';
import 'package:metromitra/shared/widgets/line_chip.dart';

/// Width of the drawing in logical pixels; the viewer scales it to fit.
const overviewWidth = 3200.0;

/// The "you are here" dot (the same blue on every map, whatever the theme).
const _userBlue = Color(0xFF1A73E8);

/// Empty border around the drawing.
const _overviewPad = 260.0;

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
  OverviewLayout._(
    this.size,
    this.points,
    this.labels,
    this._minX,
    this._minY,
    this._scale,
    this._offsetX,
  );

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
    const pad = _overviewPad;
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    // Fit the width, but never let the drawing get absurdly tall (a network
    // that is nearly a straight line): then the height decides, and the
    // drawing is centred sideways.
    const maxHeight = overviewWidth * 3;
    final scale = math.min(
      (overviewWidth - 2 * pad) / spanX,
      (maxHeight - 2 * pad) / spanY,
    );
    final offsetX = (overviewWidth - 2 * pad - spanX * scale) / 2;
    final height = spanY * scale + 2 * pad;
    final points = {
      for (final s in stations)
        s.id: Offset(
          (s.x - minX) * scale + pad + offsetX,
          (s.y - minY) * scale + pad,
        ),
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
    return OverviewLayout._(
      Size(overviewWidth, height),
      points,
      labels,
      minX,
      minY,
      scale,
      offsetX,
    );
  }

  final Size size;
  final Map<String, Offset> points;
  final List<OverviewLabel> labels;
  final double _minX;
  final double _minY;
  final double _scale;
  final double _offsetX;

  /// Where a map-plane point (a station or a live position) lands on the drawing.
  Offset project(double x, double y) => Offset(
    (x - _minX) * _scale + _overviewPad + _offsetX,
    (y - _minY) * _scale + _overviewPad,
  );
}

class OverviewPainter extends CustomPainter {
  OverviewPainter({
    required this.geometry,
    required this.layout,
    required this.lineColors,
    required this.ink,
    required this.paper,
    this.overlay,
  });

  final MapGeometry geometry;
  final OverviewLayout layout;
  final Map<String, Color> lineColors;
  final Color ink;
  final Color paper;

  /// A route to show: its segments are thick and the rest of the map is
  /// faded (still named), so the route reads at a glance.
  final MapOverlay? overlay;

  @override
  void paint(Canvas canvas, Size size) {
    final o = overlay;
    final onRoute = o?.routeStationIds.toSet();
    for (final seg in geometry.segments) {
      final a = layout.points[seg.fromId];
      final b = layout.points[seg.toId];
      if (a == null || b == null) continue;
      final hit = o == null || o.highlightedSegments.contains(seg.key);
      final color = lineColors[seg.lineId] ?? const Color(0xFF607D8B);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = hit ? color : color.withValues(alpha: 0.22)
          ..strokeWidth = o == null
              ? 11
              : hit
              ? 19
              : 8
          ..strokeCap = StrokeCap.round,
      );
    }
    if (o != null) {
      for (final (from, to) in o.walks) {
        final a = layout.points[from];
        final b = layout.points[to];
        if (a != null && b != null) _dashed(canvas, a, b, ink);
      }
    }
    for (final s in geometry.stations) {
      final p = layout.points[s.id]!;
      final inter = s.lineIds.length > 1;
      final dim = onRoute != null && !onRoute.contains(s.id);
      final r = inter ? 15.0 : 8.0;
      final ringInk = dim ? ink.withValues(alpha: 0.35) : ink;
      canvas
        ..drawCircle(p, r, Paint()..color = paper)
        ..drawCircle(
          p,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = inter ? 5 : 3.5
            ..color = ringInk,
        );
      if (inter) canvas.drawCircle(p, 4.5, Paint()..color = ringInk);
    }
    if (o != null) {
      for (final id in o.transferStationIds) {
        final p = layout.points[id];
        if (p == null) continue;
        canvas.drawCircle(
          p,
          27,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = ink,
        );
      }
    }
    for (final l in layout.labels) {
      if (onRoute == null || onRoute.contains(l.stationId)) {
        l.painter.paint(canvas, l.offset);
      } else {
        canvas.saveLayer(
          (l.offset & Size(l.painter.width, l.painter.height)).inflate(4),
          Paint()..color = const Color(0x66000000),
        );
        l.painter.paint(canvas, l.offset);
        canvas.restore();
      }
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Color color) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var d = 0.0; d < total; d += 36) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 20, total), paint);
    }
  }

  @override
  bool shouldRepaint(OverviewPainter old) =>
      old.layout != layout ||
      old.geometry != geometry ||
      old.ink != ink ||
      old.paper != paper ||
      old.overlay != overlay;
}

/// The overall map: the whole network with every station named, pinch to
/// zoom, tap a station for its detail, plus the user's marks on top (route
/// ends, a searched station, the live position). One widget so the Map tab
/// has every operation the older geographic map had.
class OverviewMapView extends StatefulWidget {
  const OverviewMapView({
    required this.geometry,
    required this.snapshot,
    this.canvasKey = const Key('map-canvas'),
    this.fromId,
    this.toId,
    this.highlightId,
    this.focusId,
    this.user,
    this.overlay,
    this.extraControls = const [],
    this.onStationTap,
    super.key,
  });

  final MapGeometry geometry;
  final MetroSnapshot snapshot;
  final Key canvasKey;

  /// Chosen journey ends, ringed on the map.
  final String? fromId;
  final String? toId;

  /// Station found with the search: ringed, labelled and brought to the centre.
  final String? highlightId;

  /// Station to centre on when the map first opens (`?station=<id>`).
  final String? focusId;

  /// Live position; centred once when the first fix arrives.
  final MapUser? user;

  /// A route to show: framed on screen, highlighted, the rest faded.
  final MapOverlay? overlay;

  /// Round buttons stacked above the zoom buttons (live location).
  final List<Widget> extraControls;
  final void Function(String stationId)? onStationTap;

  @override
  State<OverviewMapView> createState() => _OverviewMapViewState();
}

class _OverviewMapViewState extends State<OverviewMapView> {
  static const _minScale = 0.05;
  static const _maxScale = 3.0;

  OverviewLayout? _layout;
  Locale? _layoutLocale;
  Brightness? _layoutBrightness;
  final _transform = TransformationController();
  Size _box = Size.zero;
  bool _fitted = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OverviewMapView old) {
    super.didUpdateWidget(old);
    final layout = _layout;
    if (layout == null || !_fitted) return;
    if (widget.highlightId != null && widget.highlightId != old.highlightId) {
      final p = layout.points[widget.highlightId];
      if (p != null) _centerOn(p);
    }
    final u = widget.user;
    if (u != null && old.user == null) {
      _centerOn(layout.project(u.x, u.y), minScale: 0.45);
    }
  }

  OverviewLayout _layoutFor(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    if (_layout != null &&
        _layoutLocale == locale &&
        _layoutBrightness == theme.brightness) {
      return _layout!;
    }
    final color = theme.colorScheme.onSurface;
    final layout = OverviewLayout.build(
      geometry: widget.geometry,
      snapshot: widget.snapshot,
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

  /// Zoom factor (x scale; z is not scaled, so getMaxScaleOnAxis would say 1
  /// whenever the map is zoomed out).
  double get _scale => _transform.value.entry(0, 0);

  /// What "fit" shows: the whole drawing, or just the route when one is set.
  Rect _fitTarget(OverviewLayout layout) {
    final ids = widget.overlay?.routeStationIds ?? const <String>[];
    Rect? r;
    for (final id in ids) {
      final p = layout.points[id];
      if (p == null) continue;
      r = r == null
          ? Rect.fromPoints(p, p)
          : r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r == null ? Offset.zero & layout.size : r.inflate(230);
  }

  void _fit(OverviewLayout layout) {
    final target = _fitTarget(layout);
    final routeOnly = target.size != layout.size;
    final s = math
        .min(_box.width / target.width, _box.height / target.height)
        .clamp(_minScale, routeOnly ? 1.0 : _maxScale);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        _box.width / 2 - target.center.dx * s,
        _box.height / 2 - target.center.dy * s,
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
  }

  /// Puts [p] (drawing coordinates) in the middle of the view.
  void _centerOn(Offset p, {double minScale = 0.5}) {
    final s = _scale.clamp(minScale, _maxScale);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        _box.width / 2 - p.dx * s,
        _box.height / 2 - p.dy * s,
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
  }

  void _zoomBy(double factor) {
    final cur = _scale;
    final target = (cur * factor).clamp(_minScale, _maxScale);
    final f = target / cur;
    final c = Offset(_box.width / 2, _box.height / 2);
    _transform.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(_transform.value);
  }

  /// Nearest station to a tap, within a finger's width on screen.
  String? _stationAt(Offset local, OverviewLayout layout) {
    final reach = math.max(26, 40 / _scale);
    String? best;
    var bestD = reach;
    layout.points.forEach((id, p) {
      final d = (p - local).distance;
      if (d < bestD) {
        bestD = d;
        best = id;
      }
    });
    return best;
  }

  TextPainter? _tag(String? id, Locale locale, TextStyle style) {
    final st = id == null ? null : widget.snapshot.station(id);
    if (st == null) return null;
    final titles = stationTitles(
      nameEn: st.nameEn,
      nameHi: st.nameHi,
      locale: locale,
    );
    return TextPainter(
      text: TextSpan(text: titles.primary, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout(maxWidth: 520);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final layout = _layoutFor(context);
    final lineColors = {
      for (final l in widget.snapshot.lines) l.id: colorFromHex(l.colorHex),
    };
    final locale = Localizations.localeOf(context);
    final tagStyle = TextStyle(
      color: scheme.onInverseSurface,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    );
    final tagged = {
      if (widget.highlightId != null) widget.highlightId!,
      if (widget.user?.nearestId != null) widget.user!.nearestId!,
      // a shown route: its two ends always carry their names
      if (widget.overlay != null && widget.fromId != null) widget.fromId!,
      if (widget.overlay != null && widget.toId != null) widget.toId!,
    };
    return LayoutBuilder(
      builder: (context, box) {
        _box = Size(box.maxWidth, box.maxHeight);
        if (!_fitted && box.maxWidth > 0 && box.maxHeight > 0) {
          _fit(layout);
          final focus = widget.focusId == null
              ? null
              : layout.points[widget.focusId];
          if (focus != null) _centerOn(focus, minScale: 0.6);
          _fitted = true;
        }
        return ColoredBox(
          color: scheme.surface,
          child: Stack(
            children: [
              InteractiveViewer(
                key: const Key('overview-viewer'),
                transformationController: _transform,
                constrained: false,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(400),
                child: Semantics(
                  label: l10n.mapSemantics(widget.geometry.stations.length),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final id = _stationAt(d.localPosition, layout);
                      if (id != null) widget.onStationTap?.call(id);
                    },
                    child: Stack(
                      key: widget.canvasKey,
                      children: [
                        CustomPaint(
                          size: layout.size,
                          painter: OverviewPainter(
                            geometry: widget.geometry,
                            layout: layout,
                            lineColors: lineColors,
                            ink: scheme.onSurface,
                            paper: scheme.surface,
                            overlay: widget.overlay,
                          ),
                        ),
                        CustomPaint(
                          key: const Key('overview-marks'),
                          size: layout.size,
                          painter: OverviewMarksPainter(
                            layout: layout,
                            transform: _transform,
                            fromId: widget.fromId,
                            toId: widget.toId,
                            highlightId: widget.highlightId,
                            user: widget.user,
                            fromColor: scheme.primary,
                            toColor: scheme.tertiary,
                            highlightColor: scheme.secondary,
                            userColor: _userBlue,
                            lostColor: scheme.outline,
                            halo: scheme.surface,
                            tagBackground: scheme.inverseSurface,
                            tags: {
                              for (final id in tagged)
                                id: ?_tag(id, locale, tagStyle),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 8,
                bottom: 8,
                child: Column(
                  children: [
                    for (final c in widget.extraControls) ...[
                      c,
                      const SizedBox(height: 8),
                    ],
                    MapRoundButton(
                      key: const Key('map-zoom-in'),
                      icon: Icons.add_rounded,
                      tooltip: l10n.mapZoomIn,
                      onPressed: () => _zoomBy(1.6),
                    ),
                    const SizedBox(height: 8),
                    MapRoundButton(
                      key: const Key('map-zoom-out'),
                      icon: Icons.remove_rounded,
                      tooltip: l10n.mapZoomOut,
                      onPressed: () => _zoomBy(1 / 1.6),
                    ),
                    const SizedBox(height: 8),
                    MapRoundButton(
                      key: const Key('map-reset'),
                      icon: Icons.center_focus_strong_outlined,
                      tooltip: l10n.mapReset,
                      onPressed: () => _fit(layout),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Marks drawn over the map at a steady on-screen size whatever the zoom:
/// journey ends, the searched station, the live position and name tags.
class OverviewMarksPainter extends CustomPainter {
  OverviewMarksPainter({
    required this.layout,
    required this.transform,
    required this.fromId,
    required this.toId,
    required this.highlightId,
    required this.user,
    required this.fromColor,
    required this.toColor,
    required this.highlightColor,
    required this.userColor,
    required this.lostColor,
    required this.halo,
    required this.tagBackground,
    required this.tags,
  }) : super(repaint: transform);

  final OverviewLayout layout;
  final TransformationController transform;
  final String? fromId;
  final String? toId;
  final String? highlightId;
  final MapUser? user;
  final Color fromColor;
  final Color toColor;
  final Color highlightColor;
  final Color userColor;
  final Color lostColor;
  final Color halo;
  final Color tagBackground;
  final Map<String, TextPainter> tags;

  @override
  void paint(Canvas canvas, Size size) {
    // one screen pixel in drawing units: marks keep their size when zoomed
    final px = 1 / transform.value.entry(0, 0);
    void ring(String? id, Color color, double radius) {
      final p = id == null ? null : layout.points[id];
      if (p == null) return;
      canvas
        ..drawCircle(p, (radius + 3) * px, Paint()..color = halo)
        ..drawCircle(
          p,
          radius * px,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * px
            ..color = color,
        );
    }

    ring(fromId, fromColor, 12);
    ring(toId, toColor, 12);
    ring(highlightId, highlightColor, 18);

    final u = user;
    Offset? userAt;
    if (u != null) {
      userAt = layout.project(u.x, u.y);
      final c = u.lost ? lostColor : userColor;
      canvas
        ..drawCircle(userAt, 22 * px, Paint()..color = c.withValues(alpha: .22))
        ..drawCircle(userAt, 10 * px, Paint()..color = halo)
        ..drawCircle(userAt, 7 * px, Paint()..color = c);
    }

    for (final entry in tags.entries) {
      final p = layout.points[entry.key];
      if (p == null) continue;
      final tp = entry.value;
      final w = tp.width * px * 0.62;
      final h = tp.height * px * 0.62;
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          p.dx - w / 2 - 6 * px,
          p.dy - 26 * px - h - 4 * px,
          w + 12 * px,
          h + 8 * px,
        ),
        Radius.circular(8 * px),
      );
      canvas
        ..drawRRect(box, Paint()..color = tagBackground)
        ..save()
        ..translate(p.dx - w / 2, p.dy - 26 * px - h)
        ..scale(px * 0.62);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(OverviewMarksPainter old) =>
      old.layout != layout ||
      old.fromId != fromId ||
      old.toId != toId ||
      old.highlightId != highlightId ||
      old.user != user ||
      old.tags.length != tags.length ||
      old.fromColor != fromColor ||
      old.halo != halo;
}

class OverviewLegend extends StatelessWidget {
  const OverviewLegend({required this.snapshot, super.key});

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
