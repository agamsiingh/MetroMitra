import 'package:metro_core/src/model/enums.dart';

/// Where a fact came from and how far to trust it. Every fact row has one.
class Provenance {
  const Provenance({
    required this.sourceId,
    required this.confidence,
    this.verifiedOn,
  });

  final String sourceId;
  final Confidence confidence;

  /// ISO date `YYYY-MM-DD`; mandatory for official/verified facts.
  final String? verifiedOn;

  @override
  String toString() => 'Provenance($sourceId, ${confidence.wire}, $verifiedOn)';
}

/// A data source and its licence (rendered in Settings -> Data & licences).
class Source {
  const Source({
    required this.id,
    required this.name,
    required this.license,
    this.url,
    this.retrievedAt,
    this.notes,
    this.version,
    this.sha256,
  });

  final String id;
  final String name;
  final String? url;
  final String license;
  final String? retrievedAt;
  final String? notes;

  /// Upstream data version (e.g. OSM base timestamp) or curated-file hash.
  final String? version;

  /// sha256 of the raw input this source contributed.
  final String? sha256;
}

/// Field-level origin: which source supplied [field] of an entity, under which
/// external identifier, and whether it was imported, normalised, derived or
/// curated. One row per (entity, field, source).
class Origin {
  const Origin({
    required this.entity,
    required this.entityId,
    required this.field,
    required this.sourceId,
    required this.status,
    this.externalId,
    this.detail,
  });

  /// `operator`, `line`, `line_service` or `station`.
  final String entity;
  final String entityId;

  /// `record` for the entity itself, otherwise a field name (`name_hi`).
  final String field;
  final String sourceId;

  /// Identifier in the source (OSM `node/123`, Wikidata `Q42`).
  final String? externalId;
  final OriginStatus status;
  final String? detail;

  String get key => '$entity|$entityId|$field|$sourceId';
}
