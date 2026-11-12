import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/src/acceptance/read_only_preflight.dart';
import 'package:ridex/src/acceptance/two_emulator_acceptance.dart';

void main() {
  Future<LocalPreflight> collect(
      {String? package = 'com.ridex.app',
      String? devices,
      String boot = '1',
      String? apkPath,
      bool throws = false,
      List<List<String>>? calls}) {
    return ReadOnlyPreflightProbe(
        sourceApplicationId: package,
        sdkLayoutAvailable: true,
        run: (exe, args) async {
          calls?.add([exe, ...args]);
          if (throws) {
            throw StateError('private credential canary');
          }
          if (args.first == 'rev-parse') {
            return ProbeResult(0, 'a' * 40);
          }
          if (args.first == 'status') {
            return const ProbeResult(0, '');
          }
          if (args.first == '--version') {
            return const ProbeResult(0, '{"frameworkVersion":"3.41.2"}');
          }
          if (args.first == 'version') {
            return const ProbeResult(0, 'Android Debug Bridge version 1.0.41');
          }
          if (args.first == 'devices') {
            return ProbeResult(
                0,
                devices ??
                    'List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n');
          }
          if (args.contains('getprop')) {
            return ProbeResult(0, boot);
          }
          if (args.contains('pm')) {
            return ProbeResult(
                0,
                apkPath ??
                    'package:/data/app/~~abc/com.ridex.app-123/base.apk\n');
          }
          if (args.contains('dumpsys')) {
            return const ProbeResult(0, 'versionCode=12 minSdk=23');
          }
          if (args.contains('sha256sum')) {
            return ProbeResult(0, '${'b' * 64}  /data/app/base.apk');
          }
          throw StateError('Unexpected command');
        }).collect();
  }

  test('fixed probes collect two booted installed APK versions and hashes',
      () async {
    final calls = <List<String>>[];
    final r = await collect(calls: calls);
    expect(r.rider.connected, isTrue);
    expect(r.driver.booted, isTrue);
    expect(r.driver.applicationId, 'com.ridex.app');
    expect(r.driver.apkSha256, 'b' * 64);
    expect(r.driver.versionCode, '12');
    expect(r.cleanRepository, isTrue);
    expect(
        calls.any((c) => c.any([
              'install',
              'am',
              'input',
              'push',
              'pull',
              'logcat',
              'start-server',
              'login',
              'invoke'
            ].contains)),
        isFalse);
    expect(calls.where((c) => c.contains('pm')).length, 2);
  });
  test('offline or unauthorized emulator never triggers shell probes',
      () async {
    final calls = <List<String>>[];
    final r = await collect(
        devices: 'emulator-5554\toffline\nemulator-5556\tunauthorized\n',
        calls: calls);
    expect(r.rider.connected, isFalse);
    expect(r.driver.connected, isFalse);
    expect(calls.any((c) => c.contains('shell')), isFalse);
  });
  test('incomplete boot does not inspect application', () async {
    final calls = <List<String>>[];
    final r = await collect(boot: '0', calls: calls);
    expect(r.rider.connected, isTrue);
    expect(r.rider.booted, isFalse);
    expect(calls.any((c) => c.contains('pm')), isFalse);
  });
  test('unknown package is never guessed', () async {
    final calls = <List<String>>[];
    final r = await collect(package: null, calls: calls);
    expect(r.rider.applicationId, isNull);
    expect(calls.any((c) => c.contains('pm')), isFalse);
  });
  test('malicious package cannot enter Android shell arguments', () async {
    final calls = <List<String>>[];
    await collect(package: 'com.ridex.app;echo secret', calls: calls);
    expect(calls.any((c) => c.join(' ').contains('secret')), isFalse);
  });
  test('package path injection never reaches hash command', () async {
    final calls = <List<String>>[];
    final r = await collect(
        apkPath: 'package:/data/app/base.apk;echo secret', calls: calls);
    expect(r.rider.apkSha256, isNull);
    expect(calls.any((c) => c.contains('sha256sum')), isFalse);
  });
  test('split APK hash stays unknown', () async {
    final r = await collect(
        apkPath: 'package:/data/app/a/base.apk\npackage:/data/app/a/split.apk');
    expect(r.rider.apkSha256, isNull);
  });
  test('tool interruption produces blocked observations without raw errors',
      () async {
    final r = await collect(throws: true);
    expect(r.repositorySha, isNull);
    expect(r.adbAvailable, isFalse);
  });
  test('source application ID accepts only a single unambiguous literal', () {
    expect(literalApplicationId('applicationId = "com.ridex.app"\n'),
        'com.ridex.app');
    expect(literalApplicationId("applicationId = 'com.ridex.app'\n"),
        'com.ridex.app');
    expect(
        literalApplicationId(
            '// applicationId = "bad.example.app"\napplicationId = "com.ridex.app"\n'),
        'com.ridex.app');
    for (final text in [
      'applicationId = variable\n',
      'applicationId = "com.ridex.app"\napplicationIdSuffix=".debug"',
      'productFlavors {}\napplicationId="com.ridex.app"\n',
      'applicationId="com.ridex.app"\napplicationId="com.other.app"\n',
      'applicationId="com.ridex.app" + variable\n'
    ]) {
      expect(literalApplicationId(text), isNull);
    }
  });
  test('actual bounded evidence files are required, arbitrary names ignored',
      () {
    final root = Directory.systemTemp.createTempSync('b09a-test-');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/evidence-001.json').writeAsStringSync('{}');
    File('${root.path}/evidence-002.json').writeAsStringSync('');
    File('${root.path}/private-token.json').writeAsStringSync('{}');
    File('${root.path}/evidence-003.json').writeAsStringSync('x' * 65537);
    expect(existingEvidenceReferences(root), {'evidence-001'});
    expect(
        existingEvidenceReferences(Directory('${root.path}/missing')), isEmpty);
  });
  test('SDK locator uses direct SDK ADB and requires platform/build tools', () {
    final root = Directory.systemTemp.createTempSync('b09a-sdk-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/platform-tools').createSync();
    File('${root.path}/platform-tools/${Platform.isWindows ? 'adb.exe' : 'adb'}')
        .writeAsStringSync('fixture');
    expect(AndroidTools.locate(sdkRoot: root.path).layoutAvailable, isFalse);
    Directory('${root.path}/platforms').createSync();
    Directory('${root.path}/build-tools').createSync();
    final located = AndroidTools.locate(sdkRoot: root.path);
    expect(located.layoutAvailable, isTrue);
    expect(located.adb, contains('platform-tools'));
  });
}
