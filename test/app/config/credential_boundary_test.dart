import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracked application configuration uses injection and no credentials',
      () {
    final trackedFiles = _trackedFiles();

    expect(
      trackedFiles.where((path) => path.startsWith('supabase/.temp/')),
      isEmpty,
      reason: 'generated Supabase metadata must not be tracked',
    );
    expect(trackedFiles, isNot(contains('android/local.properties')));
    expect(trackedFiles, isNot(contains('ios/Flutter/config.local.xcconfig')));
    expect(trackedFiles, isNot(contains('supabase/functions/.env')));

    final androidGradle = _read('android/app/build.gradle');
    final androidManifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(androidGradle, contains('getProperty("MAPS_API_KEY", "")'));
    expect(androidGradle, contains('manifestPlaceholders["MAPS_API_KEY"]'));
    expect(androidManifest, contains(r'android:value="${MAPS_API_KEY}"'));
    expect(androidManifest, isNot(matches(_literalMapsKeyPattern)));

    final iosInfo = _read('ios/Runner/Info.plist');
    expect(iosInfo, contains(r'$(GOOGLE_MAPS_API_KEY)'));
    expect(iosInfo, isNot(matches(_literalMapsKeyPattern)));

    final envConfig = _read('lib/app/config/env_config.dart');
    expect(envConfig, contains("String.fromEnvironment('SUPABASE_URL'"));
    expect(
      envConfig,
      contains("String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'"),
    );
    expect(envConfig, contains("bool.fromEnvironment('GOOGLE_MAPS_ENABLED'"));

    for (final relativePath in trackedFiles) {
      final normalized = relativePath.toLowerCase();
      if (!_configurationFile(normalized)) continue;

      final source = File(_path(relativePath)).readAsStringSync();
      expect(source, isNot(matches(_secretValuePattern)), reason: relativePath);
      expect(source, isNot(matches(_databaseCredentialPattern)),
          reason: relativePath);
      if (relativePath.startsWith('lib/') ||
          relativePath.startsWith('android/') ||
          relativePath.startsWith('ios/')) {
        expect(source, isNot(contains('GOOGLE_MAPS_WEB_SERVICES_API_KEY')),
            reason: relativePath);
        expect(source, isNot(contains('GOOGLE_ROUTES_API_KEY')),
            reason: relativePath);
      }
    }
  });
}

final _secretValuePattern = RegExp(
  r'''(?:service[_-]?role|sb_secret_|access[_-]?token|refresh[_-]?token)\s*[:=]\s*['"]?[A-Za-z0-9._-]{12,}''',
  caseSensitive: false,
);

final _databaseCredentialPattern = RegExp(
  r'''(?:postgres(?:ql)?|pooler)[^\r\n]{0,80}(?:password|://[^\s]+:[^\s@]+@)''',
  caseSensitive: false,
);

final _literalMapsKeyPattern = RegExp(
  r'''(?:AIza[0-9A-Za-z_-]{20,}|GOOGLE_MAPS_API_KEY\s*[=:]\s*[^$\{\s][^\r\n]*)''',
);

bool _configurationFile(String path) {
  return path.endsWith('.dart') ||
      path.endsWith('.gradle') ||
      path.endsWith('.plist') ||
      path.endsWith('.xml') ||
      path.endsWith('.json') ||
      path.endsWith('.properties') ||
      path.endsWith('.xcconfig') ||
      path.endsWith('.yaml') ||
      path.endsWith('.yml') ||
      path.endsWith('.toml') ||
      path == 'readme.md';
}

Set<String> _trackedFiles() {
  final result = Process.runSync(
    'git',
    ['ls-files'],
    workingDirectory: Directory.current.path,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect tracked files.');
  }
  return (result.stdout as String)
      .split(RegExp(r'\r?\n'))
      .where((path) => path.isNotEmpty)
      .toSet();
}

String _path(String relativePath) =>
    Directory.current.uri.resolve(relativePath).toFilePath();

String _read(String relativePath) =>
    File(_path(relativePath)).readAsStringSync();
