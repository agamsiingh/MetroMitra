/// Pure-Dart MetroMitra domain: models, dataset reader/writer, validation,
/// and (from later milestones) routing, fare, search, assistant.
/// No Flutter, no network, no platform plugins.
library;

export 'src/ai/ai_gateway.dart';
export 'src/assistant/assistant.dart';
export 'src/assistant/assistant_models.dart';
export 'src/assistant/lexicon.dart';
export 'src/authoring/yaml_dataset.dart';
export 'src/core_info.dart';
export 'src/dataset/dataset_reader.dart';
export 'src/dataset/dataset_repository.dart';
export 'src/dataset/dataset_writer.dart';
export 'src/dataset/schema.dart';
export 'src/fare/fare_engine.dart';
export 'src/fare/fare_quote.dart';
export 'src/geo/nearby.dart';
export 'src/journey/journey.dart';
export 'src/map/map_geometry.dart';
export 'src/model/enums.dart';
export 'src/model/fare.dart';
export 'src/model/network.dart';
export 'src/model/provenance.dart';
export 'src/model/snapshot.dart';
export 'src/model/station_facts.dart';
export 'src/routing/itinerary.dart';
export 'src/routing/last_train.dart';
export 'src/routing/route_planner.dart';
export 'src/routing/travel_time.dart';
export 'src/search/normalizer.dart';
export 'src/search/search_index.dart';
export 'src/search/search_models.dart';
export 'src/update/update_manifest.dart';
export 'src/validation/validation.dart';
