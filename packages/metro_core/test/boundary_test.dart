import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

void main() {
  test('metro_core exposes its public library', () {
    expect(supportedDatasetSchemaVersion, currentSchemaVersion);
    expect(minSupportedSchemaVersion, lessThanOrEqualTo(currentSchemaVersion));
  });
}
