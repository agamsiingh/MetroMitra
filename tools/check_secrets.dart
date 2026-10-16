// Fails if a vendor secret or private key could be shipped in the app, a
// package or config (docs/security.md). Adapted from Briskit check_secrets.dart.
// Scans app/, packages/, tools/, data/ and docs/-adjacent config; skips tests,
// build output and this file's own patterns.
import 'dart:io';

const _roots = [
  'app',
  'packages',
  'server',
  'tools',
  'data',
  'admin',
  'supabase',
];
const _extensions = {
  '.dart',
  '.json',
  '.yaml',
  '.yml',
  '.xml',
  '.gradle',
  '.kts',
  '.properties',
  '.env',
  '.arb',
  '.sql',
  '.md',
  '.ts',
  '.tsx',
  '.mjs',
};

final _rules = <String, RegExp>{
  'Anthropic API key (sk-ant-)': RegExp(r'sk-ant-[A-Za-z0-9_-]{10,}'),
  'OpenAI-style API key (sk-)': RegExp(r'\bsk-[A-Za-z0-9]{20,}'),
  'Google API key (AIza)': RegExp(r'AIza[0-9A-Za-z_-]{35}'),
  'Private key PEM header': RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  'Supabase secret key (sb_secret_)': RegExp(r'sb_secret_[A-Za-z0-9_-]{10,}'),
  'JWT (e.g. a Supabase service-role key)': RegExp(
    r'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}',
  ),
  'AWS access key id': RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
};

/// Returns the process exit code.
int main() {
  var violations = 0;
  for (final root in _roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.contains('/.dart_tool/') ||
          path.contains('/node_modules/') ||
          path.contains('/.next/') ||
          path.contains('/build/') ||
          path.contains('/test/') ||
          path.endsWith('tools/check_secrets.dart') ||
          path.contains('/data/cache/') ||
          !_extensions.any(path.endsWith)) {
        continue;
      }
      final List<String> lines;
      try {
        lines = file.readAsLinesSync();
      } on FileSystemException {
        continue;
      }
      for (var i = 0; i < lines.length; i++) {
        for (final MapEntry(key: why, value: pattern) in _rules.entries) {
          if (pattern.hasMatch(lines[i])) {
            stderr.writeln('$path:${i + 1}: $why');
            violations++;
          }
        }
      }
    }
  }
  if (violations > 0) return 1;
  stdout.writeln('No secrets found');
  return 0;
}
