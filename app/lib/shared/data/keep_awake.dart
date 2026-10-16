import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on during a journey (FR-JOURNEY 3). A seam so tests can
/// check it without the platform plugin.
abstract interface class KeepAwake {
  Future<void> set({required bool on});
}

class WakelockKeepAwake implements KeepAwake {
  @override
  Future<void> set({required bool on}) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object {
      // not supported on this device: the journey works without it
    }
  }
}

final keepAwakeProvider = Provider<KeepAwake>((ref) => WakelockKeepAwake());
