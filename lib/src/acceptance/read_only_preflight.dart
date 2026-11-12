import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'two_emulator_acceptance.dart';

class ProbeResult {
  const ProbeResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

typedef ReadOnlyCommand = Future<ProbeResult> Function(
    String executable, List<String> arguments);

/// Fixed read-only commands only. No shell strings, install, launch, login,
/// permission change, database request, application action or credential access.
class ReadOnlyPreflightProbe {
  const ReadOnlyPreflightProbe({
    required this.run,
    required this.sdkLayoutAvailable,
    this.sourceApplicationId,
    this.sourceComponents = const {},
    this.adb = 'adb',
    this.flutter = 'flutter',
    this.git = 'git',
  });
  final ReadOnlyCommand run;
  final bool sdkLayoutAvailable;
  final String? sourceApplicationId;
  final Map<String, bool> sourceComponents;
  final String adb, flutter, git;

  Future<ProbeResult> _safe(String tool, List<String> args) async {
    try {
      return await run(tool, args);
    } on Object {
      return const ProbeResult(-1, '');
    }
  }

  Future<LocalPreflight> collect() async {
    final revision = await _safe(git, ['rev-parse', 'HEAD']);
    final status = await _safe(git, ['status', '--porcelain']);
    final version = await _safe(flutter, ['--version', '--machine']);
    String? flutterVersion;
    try {
      final data = jsonDecode(version.output);
      if (version.exitCode == 0 &&
          data is Map &&
          data['frameworkVersion'] is String &&
          RegExp(
            r'^\d+\.\d+\.\d+$',
          ).hasMatch(data['frameworkVersion'] as String)) {
        flutterVersion = data['frameworkVersion'] as String;
      }
    } on Object {
      /* Missing/malformed tool output is blocked, never echoed. */
    }
    final adbVersion = await _safe(adb, ['version']);
    final adbAvailable = adbVersion.exitCode == 0 &&
        adbVersion.output.contains('Android Debug Bridge version');
    final devices = adbAvailable
        ? await _safe(adb, ['devices'])
        : const ProbeResult(-1, '');
    final connected = <String>{};
    if (devices.exitCode == 0) {
      for (final line in devices.output.split('\n')) {
        final match = RegExp(
          r'^(emulator-(?:5554|5556))\s+device\s*$',
        ).firstMatch(line.trim());
        if (match != null) {
          connected.add(match.group(1)!);
        }
      }
    }
    Future<DeviceObservation> device(String id) async {
      if (!connected.contains(id)) return const DeviceObservation();
      final boot = await _safe(adb, [
        '-s',
        id,
        'shell',
        'getprop',
        'sys.boot_completed',
      ]);
      if (boot.exitCode != 0 || boot.output.trim() != '1') {
        return const DeviceObservation(connected: true);
      }
      final appId = sourceApplicationId;
      if (appId == null ||
          !RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,5}$')
              .hasMatch(appId)) {
        return const DeviceObservation(connected: true, booted: true);
      }
      final package = await _safe(adb, [
        '-s',
        id,
        'shell',
        'pm',
        'path',
        appId,
      ]);
      final paths = package.output
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final installed = package.exitCode == 0 &&
          paths.isNotEmpty &&
          paths.every((s) => s.startsWith('package:'));
      String? apkHash;
      String? versionCode;
      if (installed) {
        final details =
            await _safe(adb, ['-s', id, 'shell', 'dumpsys', 'package', appId]);
        final versions = RegExp(r'\bversionCode=([1-9][0-9]{0,9})\b')
            .allMatches(details.output)
            .map((m) => m.group(1)!)
            .toSet();
        if (details.exitCode == 0 && versions.length == 1) {
          versionCode = versions.single;
        }
      }
      if (installed && paths.length == 1) {
        final path = paths.single.substring('package:'.length);
        // ADB shell receives arguments as shell text on Android. Whitelist the
        // package-manager path before passing it to the read-only hash command.
        if (RegExp(
          r'^/data/app/[A-Za-z0-9._~+=/\-]+/base\.apk$',
        ).hasMatch(path)) {
          final hash = await _safe(adb, ['-s', id, 'shell', 'sha256sum', path]);
          final match = RegExp(r'^([a-f0-9]{64})[ \t]').firstMatch(hash.output);
          if (hash.exitCode == 0 && match != null) {
            apkHash = match.group(1);
          }
        }
      }
      return DeviceObservation(
        connected: true,
        booted: true,
        applicationId: installed ? appId : null,
        apkSha256: apkHash,
        versionCode: versionCode,
      );
    }

    return LocalPreflight(
      repositorySha: revision.exitCode == 0 ? revision.output.trim() : null,
      flutterVersion: flutterVersion,
      cleanRepository: status.exitCode == 0 && status.output.trim().isEmpty,
      adbAvailable: adbAvailable,
      sdkAvailable: sdkLayoutAvailable && adbAvailable,
      sourceApplicationId: sourceApplicationId,
      sourceComponents: sourceComponents,
      rider: await device(riderEmulator),
      driver: await device(driverEmulator),
    );
  }
}

/// Each process has a bounded lifetime/output. Stderr is drained, never retained
/// or printed: tool errors can contain paths, device data or credentials.
Future<ProbeResult> runReadOnlyCommand(
  String executable,
  List<String> arguments,
) async {
  Process? process;
  try {
    process = await Process.start(
      executable,
      arguments,
      runInShell:
          Platform.isWindows && executable.toLowerCase().endsWith('.bat'),
    );
    final running = process;
    final output = running.stdout.fold<List<int>>([], (bytes, chunk) {
      if (bytes.length + chunk.length > 65536) {
        throw const FormatException('Probe output limit.');
      }
      bytes.addAll(chunk);
      return bytes;
    });
    final result = await Future.wait<Object>([
      running.exitCode,
      output,
      running.stderr.drain<void>().then<Object>((_) => true),
    ]).timeout(const Duration(seconds: 15));
    return ProbeResult(
      result[0] as int,
      utf8.decode(result[1] as List<int>, allowMalformed: true),
    );
  } on Object {
    process?.kill();
    return const ProbeResult(-1, '');
  }
}

/// Deliberately narrow: computed/flavored IDs need reviewed build metadata.
/// Never execute Gradle or read local.properties / Dart defines to guess an ID.
String? literalApplicationId(String gradle) {
  final text = gradle.replaceAll(RegExp(r'/\*[\s\S]*?\*/|//[^\r\n]*'), '');
  if (RegExp(r'\b(applicationIdSuffix|productFlavors)\b').hasMatch(text)) {
    return null;
  }
  final declarations = RegExp(r'\bapplicationId\b').allMatches(text).length;
  final matches = RegExp(
          'applicationId\\s*=\\s*["\x27]([a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*){2,5})["\x27]\\s*(?:\\r?\\n|;|\\})')
      .allMatches(text)
      .toList();
  return declarations == 1 && matches.length == 1
      ? matches.single.group(1)
      : null;
}

/// Only opaque names of actual, nonempty, bounded artifacts are retained.
/// Symlinks outside the explicitly selected artifact directory are excluded.
Set<String> existingEvidenceReferences(Directory directory) {
  final result = <String>{};
  String compare(String path) {
    final normalized = path.replaceAll('\\', '/');
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  try {
    final root = directory.resolveSymbolicLinksSync();
    final prefix = '${compare(root)}/';
    for (final entity in directory.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (!RegExp(r'^evidence-[0-9]{3,6}\.json$').hasMatch(name)) {
        continue;
      }
      final file = File(entity.path);
      final target = compare(file.resolveSymbolicLinksSync());
      if (target.startsWith(prefix) &&
          file.lengthSync() > 0 &&
          file.lengthSync() <= 65536) {
        result.add(name.substring(0, name.length - 5));
      }
    }
  } on Object {/* An inaccessible artifact cannot satisfy a reference. */}
  return result;
}

class AndroidTools {
  const AndroidTools(this.adb, this.layoutAvailable);
  final String adb;
  final bool layoutAvailable;
  factory AndroidTools.locate({
    String? sdkRoot,
    String? adbOverride,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final root = sdkRoot ??
        env['ANDROID_SDK_ROOT'] ??
        env['ANDROID_HOME'] ??
        (env['LOCALAPPDATA'] == null
            ? null
            : '${env['LOCALAPPDATA']}/Android/sdk');
    final executable = Platform.isWindows ? 'adb.exe' : 'adb';
    final sdkAdb = root == null ? null : '$root/platform-tools/$executable';
    final present = sdkAdb != null &&
        File(sdkAdb).existsSync() &&
        Directory('$root/platforms').existsSync() &&
        Directory('$root/build-tools').existsSync();
    return AndroidTools(adbOverride ?? sdkAdb ?? executable, present);
  }
}
