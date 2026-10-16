/// Dataset schema v1 (docs/data-model.md). Single source of truth for the DDL
/// used by the pipeline (writer) and the device (reader).
library;

/// Schema version this build writes.
const int currentSchemaVersion = 1;

/// Oldest schema version this build can still read.
const int minSupportedSchemaVersion = 1;

/// Tables in dependency (insert) order.
const List<String> schemaTables = [
  'meta',
  'source',
  'fare_system',
  'operator',
  'line',
  'line_service',
  'station',
  'service_stop',
  'station_name',
  'station_line',
  'edge',
  'transfer',
  'walk_link',
  'platform',
  'gate',
  'gate_landmark',
  'facility',
  'accessibility',
  'fare_slab',
  'fare_discount',
  'fare_override',
  'timing',
  'origin',
];

const _prov = '''
  source_id TEXT NOT NULL REFERENCES source(id),
  confidence TEXT NOT NULL CHECK (confidence IN ('official','verified','derived','community')),
  verified_on TEXT''';

const _status = "CHECK (status IN ('open','closed','planned'))";
const _dayType = "CHECK (day_type IN ('regular','sunday_holiday'))";

/// DDL statements, executed in order inside one transaction.
final List<String> schemaStatements = [
  'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  '''
CREATE TABLE source(
  id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT, license TEXT NOT NULL,
  retrieved_at TEXT, notes TEXT, version TEXT, sha256 TEXT)''',
  // fare_system.operator_id is validated in Dart (operator <-> fare_system is circular).
  '''
CREATE TABLE fare_system(
  id TEXT PRIMARY KEY, operator_id TEXT NOT NULL, currency TEXT NOT NULL,
  effective_from TEXT NOT NULL, source_id TEXT NOT NULL REFERENCES source(id))''',
  '''
CREATE TABLE operator(
  id TEXT PRIMARY KEY, name_en TEXT NOT NULL, name_hi TEXT,
  fare_system_id TEXT REFERENCES fare_system(id))''',
  '''
CREATE TABLE line(
  id TEXT PRIMARY KEY, operator_id TEXT NOT NULL REFERENCES operator(id),
  name_en TEXT NOT NULL, name_hi TEXT, short_name TEXT,
  color_hex TEXT NOT NULL, text_color_hex TEXT NOT NULL, sort INTEGER NOT NULL,
  status TEXT NOT NULL $_status)''',
  '''
CREATE TABLE line_service(
  id TEXT PRIMARY KEY, line_id TEXT NOT NULL REFERENCES line(id),
  name TEXT NOT NULL, is_loop INTEGER NOT NULL DEFAULT 0 CHECK (is_loop IN (0,1)),
  through_service_of TEXT REFERENCES line_service(id))''',
  '''
CREATE TABLE station(
  id TEXT PRIMARY KEY, name_en TEXT NOT NULL, name_hi TEXT,
  lat REAL NOT NULL, lng REAL NOT NULL, popularity INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL $_status, opened_on TEXT, map_x REAL, map_y REAL,
$_prov)''',
  '''
CREATE TABLE service_stop(
  service_id TEXT NOT NULL REFERENCES line_service(id), seq INTEGER NOT NULL,
  station_id TEXT NOT NULL REFERENCES station(id),
  dist_from_start_m INTEGER NOT NULL, PRIMARY KEY(service_id, seq))''',
  '''
CREATE TABLE station_name(
  station_id TEXT NOT NULL REFERENCES station(id), text TEXT NOT NULL,
  lang TEXT NOT NULL CHECK (lang IN ('en','hi')),
  kind TEXT NOT NULL CHECK (kind IN ('official','alias','old','misspelling','landmark')),
  PRIMARY KEY(station_id, text, lang, kind))''',
  '''
CREATE TABLE station_line(
  station_id TEXT NOT NULL REFERENCES station(id),
  line_id TEXT NOT NULL REFERENCES line(id), station_code TEXT,
  PRIMARY KEY(station_id, line_id))''',
  '''
CREATE TABLE edge(
  id TEXT PRIMARY KEY, service_id TEXT NOT NULL REFERENCES line_service(id),
  from_station TEXT NOT NULL REFERENCES station(id),
  to_station TEXT NOT NULL REFERENCES station(id),
  travel_s INTEGER, distance_m INTEGER NOT NULL,
$_prov)''',
  '''
CREATE TABLE transfer(
  station_id TEXT NOT NULL REFERENCES station(id),
  from_line TEXT NOT NULL REFERENCES line(id), to_line TEXT NOT NULL REFERENCES line(id),
  walk_m INTEGER, walk_s INTEGER, step_free INTEGER,
  notes_en TEXT, notes_hi TEXT,
$_prov, PRIMARY KEY(station_id, from_line, to_line))''',
  '''
CREATE TABLE walk_link(
  id TEXT PRIMARY KEY, from_station TEXT NOT NULL REFERENCES station(id),
  to_station TEXT NOT NULL REFERENCES station(id),
  walk_m INTEGER NOT NULL, walk_s INTEGER NOT NULL,
  requires_exit INTEGER NOT NULL CHECK (requires_exit IN (0,1)), step_free INTEGER,
  notes_en TEXT, notes_hi TEXT,
$_prov)''',
  '''
CREATE TABLE platform(
  station_id TEXT NOT NULL REFERENCES station(id),
  line_id TEXT NOT NULL REFERENCES line(id), number TEXT NOT NULL,
  towards_station_id TEXT REFERENCES station(id),
  service_id TEXT REFERENCES line_service(id), notes_en TEXT, notes_hi TEXT,
$_prov, PRIMARY KEY(station_id, line_id, number))''',
  '''
CREATE TABLE gate(
  id TEXT PRIMARY KEY, station_id TEXT NOT NULL REFERENCES station(id),
  number INTEGER NOT NULL, name_en TEXT, name_hi TEXT, lat REAL, lng REAL,
  is_open INTEGER, has_lift INTEGER, has_ramp INTEGER, has_escalator INTEGER,
  is_step_free INTEGER,
$_prov)''',
  '''
CREATE TABLE gate_landmark(
  gate_id TEXT NOT NULL REFERENCES gate(id), text_en TEXT NOT NULL, text_hi TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('road','landmark','bus','rail','mall','other')))''',
  '''
CREATE TABLE facility(
  station_id TEXT NOT NULL REFERENCES station(id), type TEXT NOT NULL,
  gate_id TEXT REFERENCES gate(id), location_en TEXT, location_hi TEXT,
$_prov)''',
  '''
CREATE TABLE accessibility(
  station_id TEXT PRIMARY KEY REFERENCES station(id), lifts INTEGER,
  escalators INTEGER, tactile_path INTEGER, wheelchair_available INTEGER,
  notes_en TEXT, notes_hi TEXT,
$_prov)''',
  '''
CREATE TABLE fare_slab(
  fare_system_id TEXT NOT NULL REFERENCES fare_system(id),
  day_type TEXT NOT NULL $_dayType, min_km INTEGER NOT NULL, max_km INTEGER,
  amount_paise INTEGER NOT NULL, PRIMARY KEY(fare_system_id, day_type, min_km))''',
  '''
CREATE TABLE fare_discount(
  fare_system_id TEXT NOT NULL REFERENCES fare_system(id),
  media TEXT NOT NULL CHECK (media IN ('smart_card','token','any')),
  kind TEXT NOT NULL CHECK (kind IN ('base','off_peak')),
  percent INTEGER NOT NULL, windows_json TEXT,
  PRIMARY KEY(fare_system_id, media, kind))''',
  '''
CREATE TABLE fare_override(
  fare_system_id TEXT NOT NULL REFERENCES fare_system(id),
  from_station TEXT NOT NULL REFERENCES station(id),
  to_station TEXT NOT NULL REFERENCES station(id),
  day_type TEXT NOT NULL $_dayType, amount_paise INTEGER NOT NULL,
  source_id TEXT NOT NULL REFERENCES source(id), verified_on TEXT NOT NULL,
  PRIMARY KEY(fare_system_id, from_station, to_station, day_type))''',
  '''
CREATE TABLE timing(
  service_id TEXT NOT NULL REFERENCES line_service(id),
  station_id TEXT NOT NULL REFERENCES station(id),
  direction_terminal_id TEXT NOT NULL REFERENCES station(id),
  day_type TEXT NOT NULL $_dayType, first_dep INTEGER NOT NULL,
  last_dep INTEGER NOT NULL,
$_prov, PRIMARY KEY(service_id, station_id, direction_terminal_id, day_type))''',
  // Where each imported/derived/curated field came from (docs/data-model.md).
  '''
CREATE TABLE origin(
  entity TEXT NOT NULL CHECK (entity IN ('operator','line','line_service','station')),
  entity_id TEXT NOT NULL, field TEXT NOT NULL,
  source_id TEXT NOT NULL REFERENCES source(id), external_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('imported','normalized','derived','curated','curated_override')),
  detail TEXT, PRIMARY KEY(entity, entity_id, field, source_id))''',
  'CREATE INDEX idx_service_stop_station ON service_stop(station_id)',
  'CREATE INDEX idx_edge_from ON edge(from_station)',
  'CREATE INDEX idx_gate_station ON gate(station_id)',
  'CREATE INDEX idx_station_name_text ON station_name(text)',
];
