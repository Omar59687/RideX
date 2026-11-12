import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProcessResult> cli(List<String> args) => Process.run(
      Platform.isWindows ? 'dart.bat' : 'dart',
      ['run', 'bin/b09a_preflight.dart', ...args],
      runInShell: Platform.isWindows);
  test('CLI help performs no device or hosted operations', () async {
    final result = await cli(['--help']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('NOT RUN'));
    expect(result.stdout, contains('--evidence-root'));
  });
  test('CLI rejects unknown options without echoing supplied credential',
      () async {
    final result = await cli(['--token', 'private-canary-credential']);
    expect(result.exitCode, 64);
    expect(
        '${result.stdout}${result.stderr}', isNot(contains('private-canary')));
  });
  test('CLI rejects output inside checkout before probing', () async {
    final result =
        await cli(['--out', '${Directory.current.path}/b09a-forbidden-output']);
    expect(result.exitCode, 64);
    expect(Directory('b09a-forbidden-output').existsSync(), isFalse);
  });
  test('CLI refuses to overwrite an evidence report', () async {
    final root = Directory.systemTemp.createTempSync('b09a-cli-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/report.json').writeAsStringSync('retained');
    final result = await cli(['--out', root.path]);
    expect(result.exitCode, 64);
    expect(File('${root.path}/report.json').readAsStringSync(), 'retained');
  });
}
