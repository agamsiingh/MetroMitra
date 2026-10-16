import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which end of the journey a station is being picked for.
enum JourneyEnd { from, to }

/// The user's current From/To choice, by canonical station id only. Display
/// names are always looked up from the dataset, never stored or compared.
@immutable
class JourneySelection {
  const JourneySelection({this.fromId, this.toId});

  final String? fromId;
  final String? toId;

  bool get isComplete => fromId != null && toId != null;
  bool get isSameStation => isComplete && fromId == toId;
  bool get canSearch => isComplete && !isSameStation;

  String? of(JourneyEnd end) => end == JourneyEnd.from ? fromId : toId;

  @override
  bool operator ==(Object other) =>
      other is JourneySelection && other.fromId == fromId && other.toId == toId;

  @override
  int get hashCode => Object.hash(fromId, toId);
}

class JourneyNotifier extends Notifier<JourneySelection> {
  @override
  JourneySelection build() => const JourneySelection();

  void set(JourneyEnd end, String stationId) {
    state = end == JourneyEnd.from
        ? JourneySelection(fromId: stationId, toId: state.toId)
        : JourneySelection(fromId: state.fromId, toId: stationId);
  }

  void clear(JourneyEnd end) {
    state = end == JourneyEnd.from
        ? JourneySelection(toId: state.toId)
        : JourneySelection(fromId: state.fromId);
  }

  void swap() {
    state = JourneySelection(fromId: state.toId, toId: state.fromId);
  }

  /// Used when a route screen is opened from a link with explicit ids.
  void setBoth(String fromId, String toId) {
    state = JourneySelection(fromId: fromId, toId: toId);
  }
}

final journeyProvider = NotifierProvider<JourneyNotifier, JourneySelection>(
  JourneyNotifier.new,
);
