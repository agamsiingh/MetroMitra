import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/features/map/application/map_camera.dart';
import 'package:metromitra/features/map/application/map_overlay.dart';
import 'package:metromitra/shared/format/format.dart';

/// Tap radius in logical pixels (docs/map.md: nearest station within 24 dp).
const mapTapRadius = 24.0;

/// Pure-Flutter vector map of the network: lines in the colours the dataset
/// gives them, stations by canonical id, optional route overlay. No tiles, no
/// network, no plugin: it works on an aeroplane.
///
/// Pan/zoom is done here (not by a transform) so strokes, markers and labels
/// keep their size at every zoom.
class NetworkMap extends StatefulWidget {
  const NetworkMap({
    required this.geometry,
    required this.snapshot,
    required this.frame,
    required this.onStationTap,
    this.overlay,
    this.fromId,
    this.toId,
    this.mapKey = const Key('map-canvas'),
    this.user,
    this.extraControls = const [],
    this.highlightId,
    super.key,
  });

  final MapGeometry geometry;
  final MetroSnapshot snapshot;

  /// Initial framing (whole network, a station or a route).
  final MapRect frame;

  /// Called with the canonical id of the tapped station.
  final ValueChanged<String> onStationTap;
  final MapOverlay? overlay;

  /// The journey's selected origin / destination, when set.
  final String? fromId;
  final String? toId;
  final Key mapKey;

  /// The user's live position (map live tracking), or null.
  final MapUser? user;

  /// Extra round buttons above the zoom controls (e.g. live tracking).
  final List<Widget> extraControls;

  /// A station found with the map search: ringed and labelled.
  final String? highlightId;

  @override
  State<NetworkMap> createState() => _NetworkMapState();
}

class _NetworkMapState extends State<NetworkMap> {
  final _camera = MapCamera();
  final _labels = <String, TextPainter>{};
  String? _labelLocale;

  // gesture state
  double _startZoom = 1;
  Offset _lastFocal = Offset.zero;
  MapViewport? _viewport;

  @override
  void dispose() {
    _camera.dispose();
    for (final p in _labels.values) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(NetworkMap old) {
    super.didUpdateWidget(old);
    if (old.frame.toString() != widget.frame.toString() ||
        old.geometry != widget.geometry) {
      _camera.reset();
    }
  }

  void _zoomBy(double factor) {
    final v = _viewport;
    if (v == null) return;
    _camera.zoomAbout(v, _camera.zoom * factor, v.width / 2, v.height / 2);
  }

  void _tap(Offset local) {
    final v = _viewport;
    if (v == null) return;
    final (bx, by) = _camera.unapply(v, local.dx, local.dy);
    final (px, py) = v.fromBase(bx, by);
    final radius = mapTapRadius / (v.baseScale * _camera.zoom);
    final hit = widget.geometry.nearestStation(px, py, radius);
    if (hit != null) widget.onStationTap(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    if (_labelLocale != locale.languageCode) {
      for (final p in _labels.values) {
        p.dispose();
      }
      _labels.clear();
      _labelLocale = locale.languageCode;
    }
    final scheme = Theme.of(context).colorScheme;
    final textStyle =
        (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        );
    final lineColors = {
      for (final l in widget.snapshot.lines) l.id: colorFromHex(l.colorHex),
    };

    // Bilingual labels: the name in the app language, the other script
    // below it in a smaller size (both from the dataset; no transliteration).
    final secondaryStyle = textStyle.copyWith(
      fontWeight: FontWeight.w400,
      fontSize: (textStyle.fontSize ?? 11) * 0.9,
    );
    TextPainter label(String id) => _labels.putIfAbsent(id, () {
      final st = widget.snapshot.station(id);
      final titles = st == null
          ? (primary: id, secondary: null)
          : stationTitles(
              nameEn: st.nameEn,
              nameHi: st.nameHi,
              locale: locale,
            );
      return TextPainter(
        text: mapStationLabel(titles, textStyle, secondaryStyle),
        textDirection: Directionality.of(context),
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: 150);
    });

    return Semantics(
      container: true,
      label: l10n.mapSemantics(widget.geometry.stations.length),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final viewport = MapViewport(
            frame: widget.frame,
            width: size.width,
            height: size.height,
          );
          _viewport = viewport;
          return Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) {
                      _camera.zoomAbout(
                        viewport,
                        _camera.zoom * (e.scrollDelta.dy < 0 ? 1.2 : 1 / 1.2),
                        e.localPosition.dx,
                        e.localPosition.dy,
                      );
                    }
                  },
                  child: GestureDetector(
                    key: widget.mapKey,
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tap(d.localPosition),
                    onScaleStart: (d) {
                      _startZoom = _camera.zoom;
                      _lastFocal = d.localFocalPoint;
                    },
                    onScaleUpdate: (d) {
                      final delta = d.localFocalPoint - _lastFocal;
                      _lastFocal = d.localFocalPoint;
                      _camera.zoomAbout(
                        viewport,
                        _startZoom * d.scale,
                        d.localFocalPoint.dx,
                        d.localFocalPoint.dy,
                        dx: delta.dx,
                        dy: delta.dy,
                      );
                    },
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: size,
                          painter: _MapPainter(
                            geometry: widget.geometry,
                            viewport: viewport,
                            camera: _camera,
                            lineColors: lineColors,
                            overlay: widget.overlay,
                            fromId: widget.fromId,
                            toId: widget.toId,
                            scheme: scheme,
                            label: label,
                            user: widget.user,
                            highlightId: widget.highlightId,
                          ),
                        ),
                      ),
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
                      onPressed: _camera.reset,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      // 48 dp touch target (accessibility)
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeWidth = width
  ..color = color;

Paint _fill(Color color) => Paint()
  ..style = PaintingStyle.fill
  ..color = color;

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.geometry,
    required this.viewport,
    required this.camera,
    required this.lineColors,
    required this.overlay,
    required this.fromId,
    required this.toId,
    required this.scheme,
    required this.label,
    this.user,
    this.highlightId,
  }) : super(repaint: camera);

  final MapGeometry geometry;
  final MapViewport viewport;
  final MapCamera camera;
  final Map<String, Color> lineColors;
  final MapOverlay? overlay;
  final String? fromId;
  final String? toId;
  final ColorScheme scheme;
  final TextPainter Function(String id) label;
  final MapUser? user;
  final String? highlightId;

  static const _fallbackLine = Color(0xFF607D8B);

  /// Plain stations are drawn as dots below this marker scale.
  static const _dotBelow = 0.7;

  /// Comfortable on-screen distance between neighbouring stations (dp).
  static const _comfortableSpacing = 26.0;

  /// 1 when stations are far apart on screen, down to 0.4 when the network
  /// is dense. Based on the median stop-to-stop distance, so a small network
  /// (or a zoomed-in view) keeps full-size markers.
  double _markerScale(Map<String, Offset> pos) {
    final lengths = <double>[
      for (final seg in geometry.segments)
        (pos[seg.fromId]! - pos[seg.toId]!).distance,
    ]..sort();
    if (lengths.isEmpty) return 1;
    final median = lengths[lengths.length ~/ 2];
    return (median / _comfortableSpacing).clamp(0.4, 1.0);
  }

  Offset _pos(MapStation s) {
    final (bx, by) = viewport.toBase(s.x, s.y);
    final (sx, sy) = camera.apply(viewport, bx, by);
    return Offset(sx, sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final visible = screen.inflate(40);
    final route = overlay;
    final dim = route != null;

    // positions once per frame, only for stations that matter
    final pos = <String, Offset>{
      for (final s in geometry.stations) s.id: _pos(s),
    };

    // 1. line segments (dimmed behind a route)
    for (final seg in geometry.segments) {
      final a = pos[seg.fromId]!;
      final b = pos[seg.toId]!;
      if (!_touches(visible, a, b)) continue;
      if (route != null && route.highlightedSegments.contains(seg.key)) {
        continue;
      }
      final c = lineColors[seg.lineId] ?? _fallbackLine;
      canvas.drawLine(
        a,
        b,
        _stroke(dim ? c.withValues(alpha: 0.25) : c, dim ? 3 : 4),
      );
    }

    // 2. route: ridden segments in line colour, thicker, over a halo
    if (route != null) {
      for (final seg in geometry.segments) {
        if (!route.highlightedSegments.contains(seg.key)) continue;
        final a = pos[seg.fromId]!;
        final b = pos[seg.toId]!;
        if (!_touches(visible, a, b)) continue;
        canvas
          ..drawLine(a, b, _stroke(scheme.surface, 11))
          ..drawLine(
            a,
            b,
            _stroke(lineColors[seg.lineId] ?? _fallbackLine, 7),
          );
      }
      // walks the route actually contains: a dashed link, nothing more
      final dash = _stroke(scheme.onSurface, 3);
      for (final (from, to) in route.walks) {
        _dashed(canvas, pos[from]!, pos[to]!, dash);
      }
    }

    // 3. stations. Where the network is dense on screen (whole-network
    // zoom) the markers shrink and plain stations become small dots, so the
    // line colours stay readable; zoomed in they are full size.
    final k = _markerScale(pos);
    final ink = scheme.onSurface;
    final fill = scheme.surface;
    final routeSet = route == null
        ? const <String>{}
        : route.routeStationIds.toSet();
    final transferSet = route == null
        ? const <String>{}
        : route.transferStationIds.toSet();
    for (final s in geometry.stations) {
      final p = pos[s.id]!;
      if (!visible.contains(p)) continue;
      final onRoute = routeSet.contains(s.id);
      final faded = dim && !onRoute;
      final base = (s.isInterchange ? 6.5 : 4.0) * k;
      final r = onRoute ? base + 1.5 : base;
      final a = faded ? 0.35 : 1.0;
      if (k < _dotBelow && !s.isInterchange && !onRoute) {
        canvas.drawCircle(p, r * 0.5 + 0.6, _fill(ink.withValues(alpha: a)));
        continue;
      }
      canvas
        ..drawCircle(p, r, _fill(fill.withValues(alpha: a)))
        ..drawCircle(
          p,
          r,
          _stroke(
            ink.withValues(alpha: a),
            (s.isInterchange ? 3 : 2) * (k < 1 ? 0.6 : 1),
          ),
        );
      if (s.isInterchange) {
        // inner dot: interchange stations read differently without colour
        canvas.drawCircle(p, 2 * k, _fill(ink.withValues(alpha: a)));
      }
      if (transferSet.contains(s.id)) {
        canvas.drawCircle(
          p,
          r + 5,
          _stroke(scheme.secondary, 3),
        );
      }
    }

    // 4. journey ends (selected origin / destination, or the route's ends)
    void pin(String? id, Color color) {
      final s = id == null ? null : geometry.station(id);
      if (s == null) return;
      final p = pos[s.id]!;
      canvas
        ..drawCircle(p, 12, _stroke(color, 4))
        ..drawCircle(p, 5, _fill(color));
    }

    pin(route?.fromId ?? fromId, scheme.primary);
    pin(route?.toId ?? toId, scheme.tertiary);
    final found = highlightId == null ? null : geometry.station(highlightId!);
    if (found != null) {
      canvas.drawCircle(pos[found.id]!, 16, _stroke(scheme.secondary, 4));
    }

    // 4b. the user's live position: accuracy halo + dot (grey when lost)
    final u = user;
    if (u != null) {
      final (bx, by) = viewport.toBase(u.x, u.y);
      final (sx, sy) = camera.apply(viewport, bx, by);
      final p = Offset(sx, sy);
      final dot = u.lost ? scheme.outline : const Color(0xFF1A73E8);
      final acc = u.accuracyM;
      if (acc != null && acc > 0) {
        // plane units are degrees of latitude (~111 km)
        final r = acc / 111320 * viewport.baseScale * camera.zoom;
        if (r > 10) {
          canvas
            ..drawCircle(p, r, _fill(dot.withValues(alpha: 0.12)))
            ..drawCircle(p, r, _stroke(dot.withValues(alpha: 0.4), 1));
        }
      }
      canvas
        ..drawCircle(p, 9, _fill(scheme.surface))
        ..drawCircle(p, 7, _fill(dot));
    }

    // 5. labels, greedily without overlap, in priority order
    final placed = <Rect>[];
    void text(MapStation s, {bool force = false}) {
      final p = pos[s.id]!;
      if (!visible.contains(p)) return;
      final tp = label(s.id);
      final rect = Rect.fromLTWH(
        p.dx + 9,
        p.dy - tp.height / 2,
        tp.width,
        tp.height,
      );
      if (!force && placed.any((r) => r.overlaps(rect.inflate(2)))) return;
      placed.add(rect);
      tp.paint(canvas, rect.topLeft);
    }

    final z = camera.zoom;
    final ends = {?route?.fromId, ?route?.toId, ?fromId, ?toId};
    for (final id in {...ends, ?highlightId, ?user?.nearestId}) {
      final s = geometry.station(id);
      if (s != null) text(s, force: true);
    }
    for (final id in transferSet) {
      final s = geometry.station(id);
      if (s != null) text(s);
    }
    if (route != null && z >= 1.5) {
      for (final id in route.routeStationIds) {
        final s = geometry.station(id);
        if (s != null) text(s);
      }
    }
    if (z >= 2.5) {
      for (final s in geometry.stations) {
        if (s.isInterchange && (!dim || routeSet.contains(s.id))) text(s);
      }
    }
    // every station once there is room; overlapping labels are skipped
    if (z >= 3.5 && !dim) {
      geometry.stations.forEach(text);
    }
  }

  bool _touches(Rect visible, Offset a, Offset b) =>
      visible.overlaps(Rect.fromPoints(a, b).inflate(1));

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    const on = 8.0;
    const off = 6.0;
    var t = 0.0;
    while (t < len) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + on, len), paint);
      t += on + off;
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.geometry != geometry ||
      old.viewport.frame.toString() != viewport.frame.toString() ||
      old.viewport.width != viewport.width ||
      old.viewport.height != viewport.height ||
      old.overlay != overlay ||
      old.fromId != fromId ||
      old.toId != toId ||
      old.scheme != scheme ||
      old.lineColors != lineColors ||
      old.user != user ||
      old.highlightId != highlightId;
}

/// The user's position in the map plane, for drawing.
@immutable
class MapUser {
  const MapUser({
    required this.x,
    required this.y,
    this.accuracyM,
    this.lost = false,
    this.nearestId,
  });

  final double x;
  final double y;
  final double? accuracyM;
  final bool lost;

  /// Nearest station, labelled on the map.
  final String? nearestId;

  @override
  bool operator ==(Object other) =>
      other is MapUser &&
      other.x == x &&
      other.y == y &&
      other.accuracyM == accuracyM &&
      other.lost == lost &&
      other.nearestId == nearestId;

  @override
  int get hashCode => Object.hash(x, y, accuracyM, lost, nearestId);
}

/// A station label: the name in the app language, then the other script on
/// a second, smaller line when the dataset has it (never transliterated).
TextSpan mapStationLabel(
  ({String primary, String? secondary}) titles,
  TextStyle style,
  TextStyle secondaryStyle,
) => TextSpan(
  text: titles.primary,
  style: style,
  children: [
    if (titles.secondary != null)
      TextSpan(text: '\n${titles.secondary}', style: secondaryStyle),
  ],
);
