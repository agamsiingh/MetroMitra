import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:metro_core/metro_core.dart' hide Platform;

/// Where a plane point lands on screen for a given frame, widget size and
/// camera. The "base" view fits [frame] into the widget with [padding]; the
/// camera then zooms and pans on top of it.
///
/// All arithmetic is plain doubles on quantised input, so the same frame and
/// size always give the same pixels.
@immutable
class MapViewport {
  MapViewport({
    required this.frame,
    required this.width,
    required this.height,
    this.padding = 32,
  }) : baseScale = _fit(frame, width, height, padding);

  final MapRect frame;
  final double width;
  final double height;
  final double padding;

  /// Pixels per plane unit at camera zoom 1.
  final double baseScale;

  static double _fit(MapRect f, double w, double h, double pad) {
    final aw = math.max(w - 2 * pad, 1);
    final ah = math.max(h - 2 * pad, 1);
    // a frame always has a non-zero span (see MapGeometry.minSpan)
    return math.min(aw / f.width, ah / f.height);
  }

  /// Base-view screen position of a plane point.
  (double, double) toBase(double x, double y) => (
    (x - frame.centerX) * baseScale + width / 2,
    (y - frame.centerY) * baseScale + height / 2,
  );

  /// Plane point under a base-view screen position.
  (double, double) fromBase(double sx, double sy) => (
    (sx - width / 2) / baseScale + frame.centerX,
    (sy - height / 2) / baseScale + frame.centerY,
  );
}

/// Zoom and pan on top of a [MapViewport]: `screen = (base - c) * zoom + c +
/// offset`, with `c` the widget centre.
class MapCamera extends ChangeNotifier {
  static const minZoom = 1.0;
  static const maxZoom = 40.0;

  double zoom = 1;
  double offsetX = 0;
  double offsetY = 0;

  /// Screen position of a base-view position.
  (double, double) apply(MapViewport v, double bx, double by) => (
    (bx - v.width / 2) * zoom + v.width / 2 + offsetX,
    (by - v.height / 2) * zoom + v.height / 2 + offsetY,
  );

  /// Base-view position under a screen position.
  (double, double) unapply(MapViewport v, double sx, double sy) => (
    (sx - v.width / 2 - offsetX) / zoom + v.width / 2,
    (sy - v.height / 2 - offsetY) / zoom + v.height / 2,
  );

  /// Zoom to [newZoom] keeping the base point under screen point [fx], [fy]
  /// where it is, and pan by ([dx], [dy]).
  void zoomAbout(
    MapViewport v,
    double newZoom,
    double fx,
    double fy, {
    double dx = 0,
    double dy = 0,
  }) {
    final z = newZoom.clamp(minZoom, maxZoom);
    final (bx, by) = unapply(v, fx, fy);
    zoom = z;
    offsetX = fx + dx - ((bx - v.width / 2) * z + v.width / 2);
    offsetY = fy + dy - ((by - v.height / 2) * z + v.height / 2);
    notifyListeners();
  }

  void reset() {
    zoom = 1;
    offsetX = 0;
    offsetY = 0;
    notifyListeners();
  }
}
