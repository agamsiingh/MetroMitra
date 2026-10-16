/// Closed vocabularies of the dataset. Each has a stable `wire` string that is
/// what is stored in SQLite / YAML (docs/data-model.md).
library;

mixin Wire {
  String get wire;
}

T parseWire<T extends Wire>(List<T> values, String raw, String what) {
  for (final v in values) {
    if (v.wire == raw) return v;
  }
  throw FormatException(
    'Unknown $what "$raw"; expected one of '
    '${values.map((v) => v.wire).join(', ')}',
  );
}

/// How much to trust a fact (docs/data-model.md).
enum Confidence with Wire {
  official('official'),
  verified('verified'),
  derived('derived'),
  community('community');

  const Confidence(this.wire);
  @override
  final String wire;

  /// Official/verified facts must say *when* they were checked.
  bool get requiresVerifiedOn =>
      this == Confidence.official || this == Confidence.verified;

  static Confidence parse(String raw) => parseWire(values, raw, 'confidence');
}

enum NameKind with Wire {
  official('official'),
  alias('alias'),
  old('old'),
  misspelling('misspelling'),
  landmark('landmark');

  const NameKind(this.wire);
  @override
  final String wire;

  static NameKind parse(String raw) => parseWire(values, raw, 'name kind');
}

enum DayType with Wire {
  regular('regular'),
  sundayHoliday('sunday_holiday');

  const DayType(this.wire);
  @override
  final String wire;

  static DayType parse(String raw) => parseWire(values, raw, 'day type');
}

/// Lifecycle of a station or line. Only `open` takes part in routing.
enum OperatingStatus with Wire {
  open('open'),
  closed('closed'),
  planned('planned');

  const OperatingStatus(this.wire);
  @override
  final String wire;

  static OperatingStatus parse(String raw) => parseWire(values, raw, 'status');
}

enum FacilityType with Wire {
  atm('atm'),
  toilet('toilet'),
  drinkingWater('drinking_water'),
  helpDesk('help_desk'),
  cloakroom('cloakroom'),
  firstAid('first_aid'),
  shop('shop'),
  other('other');

  const FacilityType(this.wire);
  @override
  final String wire;

  static FacilityType parse(String raw) =>
      parseWire(values, raw, 'facility type');
}

enum GateLandmarkKind with Wire {
  road('road'),
  landmark('landmark'),
  bus('bus'),
  rail('rail'),
  mall('mall'),
  other('other');

  const GateLandmarkKind(this.wire);
  @override
  final String wire;

  static GateLandmarkKind parse(String raw) =>
      parseWire(values, raw, 'gate landmark kind');
}

/// Fare payment medium a discount applies to.
enum FareMedia with Wire {
  smartCard('smart_card'),
  token('token'),
  any('any');

  const FareMedia(this.wire);
  @override
  final String wire;

  static FareMedia parse(String raw) => parseWire(values, raw, 'fare media');
}

enum FareDiscountKind with Wire {
  base('base'),
  offPeak('off_peak');

  const FareDiscountKind(this.wire);
  @override
  final String wire;

  static FareDiscountKind parse(String raw) =>
      parseWire(values, raw, 'fare discount kind');
}

/// How an individual field reached the dataset (the `origin` table).
enum OriginStatus with Wire {
  /// Copied from a source as-is.
  imported('imported'),

  /// Source value after deterministic normalisation (trim, suffix strip...).
  normalized('normalized'),

  /// Computed by the pipeline from imported data (e.g. distances).
  derived('derived'),

  /// Supplied by a MetroMitra curated overlay.
  curated('curated'),

  /// Curated value that replaced a different source value (reported).
  curatedOverride('curated_override');

  const OriginStatus(this.wire);
  @override
  final String wire;

  static OriginStatus parse(String raw) =>
      parseWire(values, raw, 'origin status');
}
