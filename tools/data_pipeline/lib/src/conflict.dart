import 'package:data_pipeline/src/overlay.dart';

enum ConflictSeverity { error, warning }

/// Two sources (or a source and its own rules) disagree, or the data is
/// ambiguous. Conflicts are never resolved silently: each one is reported with
/// all candidate values, and only a curated `resolution` can clear it.
class Conflict {
  Conflict({
    required this.kind,
    required this.subject,
    required this.severity,
    required this.message,
    this.field,
    this.candidates = const {},
    this.resolution,
  });

  final String kind;

  /// What the conflict is about (`station:rajiv-chowk`, `osm-relation/123`).
  final String subject;
  final ConflictSeverity severity;
  final String message;
  final String? field;

  /// Candidate values by origin (`osm`, `wikidata`, cluster id...).
  final Map<String, String?> candidates;

  /// Set when a curated resolution applied.
  Resolution? resolution;

  /// Stable id used by overlay `resolutions` (`kind|subject|field`).
  String get id => [kind, subject, if (field != null) field].join('|');

  bool get resolved => resolution != null;

  /// Unresolved errors stop the build.
  bool get blocking => severity == ConflictSeverity.error && !resolved;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'subject': subject,
    'severity': severity.name,
    'message': message,
    'field': ?field,
    if (candidates.isNotEmpty) 'candidates': candidates,
    'status': resolved ? 'resolved-by-curation' : 'unresolved',
    if (resolution != null)
      'resolution': {
        'choice': resolution!.accept ? 'accept' : 'use:${resolution!.use}',
        'reason': resolution!.curation.reason,
        'source': resolution!.curation.source,
        'verified_on': resolution!.curation.verifiedOn,
      },
  };
}

/// A curated value replacing a source value; always listed in the report.
class OverrideRecord {
  const OverrideRecord({
    required this.target,
    required this.field,
    required this.from,
    required this.to,
    required this.curation,
  });

  final String target;
  final String field;
  final String? from;
  final String? to;
  final Curation curation;

  Map<String, Object?> toJson() => {
    'target': target,
    'field': field,
    'from': from,
    'to': to,
    'reason': curation.reason,
    'source': curation.source,
    'verified_on': curation.verifiedOn,
  };
}

/// Collects conflicts and applies curated resolutions to them.
class ConflictLog {
  ConflictLog(Iterable<Resolution> resolutions)
    : _resolutions = {for (final r in resolutions) r.conflict: r};

  final Map<String, Resolution> _resolutions;
  final Set<String> _used = {};
  final List<Conflict> all = [];

  /// Records [conflict]; returns it so the caller can read `resolution`.
  Conflict report(Conflict conflict) {
    final r = _resolutions[conflict.id];
    if (r != null) {
      conflict.resolution = r;
      _used.add(conflict.id);
    }
    all.add(conflict);
    return conflict;
  }

  /// Resolutions that matched nothing are themselves reported (stale).
  void reportUnmatchedResolutions() {
    for (final id in _resolutions.keys.toList()..sort()) {
      if (!_used.contains(id)) {
        all.add(
          Conflict(
            kind: 'resolution-unmatched',
            subject: id,
            severity: ConflictSeverity.warning,
            message:
                'Curated resolution matches no current conflict (stale or typo).',
          ),
        );
      }
    }
  }

  List<Conflict> get blocking => all.where((c) => c.blocking).toList();
}
