import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Where the active journey is kept so it survives the app being killed
/// (docs/data-model.md: `journey_state(json)` in the user database). It
/// holds canonical station ids, the route choice and the step position:
/// never a location.
abstract interface class JourneyStore {
  /// The saved journey, or null when there is none (or it cannot be read).
  Future<String?> load();

  /// Saves [json]; [savedAtMs] comes from the app clock.
  Future<void> save(String json, int savedAtMs);

  Future<void> clear();
}

/// `user.sqlite` in the app support directory, table `journey_state` with
/// one row. The rest of the user database (recents, favourites, settings)
/// arrives with its own milestone; this file is the same database.
class SqliteJourneyStore implements JourneyStore {
  SqliteJourneyStore(this._directory);

  /// Directory of the user database (injected for tests).
  final Future<Directory> Function() _directory;

  static const fileName = 'user.sqlite';

  Future<T> _use<T>(T Function(Database db) body) async {
    final dir = await _directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final db = sqlite3.open('${dir.path}${Platform.pathSeparator}$fileName');
    try {
      db.execute(
        'CREATE TABLE IF NOT EXISTS journey_state ( '
        'id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL, '
        'saved_at INTEGER NOT NULL)',
      );
      return body(db);
    } finally {
      db.close();
    }
  }

  @override
  Future<String?> load() async {
    try {
      return await _use((db) {
        final rows = db.select('SELECT json FROM journey_state WHERE id = 1');
        return rows.isEmpty ? null : rows.first['json'] as String?;
      });
    } on Object {
      // an unreadable user database never blocks the app
      return null;
    }
  }

  @override
  Future<void> save(String json, int savedAtMs) => _use((db) {
    db.execute(
      'INSERT OR REPLACE INTO journey_state (id, json, saved_at) '
      'VALUES (1, ?, ?)',
      [json, savedAtMs],
    );
  });

  @override
  Future<void> clear() => _use((db) {
    db.execute('DELETE FROM journey_state');
  });
}

final journeyStoreProvider = Provider<JourneyStore>(
  (ref) => SqliteJourneyStore(getApplicationSupportDirectory),
);
