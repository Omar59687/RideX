import 'dart:convert';
import 'dart:io';

import 'package:ridex/src/acceptance/read_only_preflight.dart';
import 'package:ridex/src/acceptance/two_emulator_acceptance.dart';

const help = '''RideX B09A read-only preflight
Run from the repository root:
  dart run bin/b09a_preflight.dart [--evidence file.json] [--out external-directory]
    [--sdk-root Android-SDK-directory] [--adb adb-executable] [--flutter flutter-executable]
    [--evidence-root approved-external-artifact-directory]
No application actions or hosted requests are executed. Reports validate local
observations and supplied operator attestations; E2E execution is always NOT RUN.
Evidence uses the documented strict sanitized schema. Missing evidence is BLOCKED.
Output defaults to a new system-temp directory and must stay outside this checkout.
Exit codes: 2 incomplete readiness (expected; C is never executed), 64 usage/output error.
--help exits 0. Supplied attestations cannot certify approval, actors or backend wiring.
''';

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--help') {
    stdout.write(help);
    return;
  }
  const allowed = {
    '--evidence',
    '--out',
    '--sdk-root',
    '--adb',
    '--flutter',
    '--evidence-root'
  };
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (!allowed.contains(args[i]) ||
        i + 1 >= args.length ||
        args[i + 1].startsWith('--') ||
        options.containsKey(args[i])) {
      stderr.writeln('Invalid arguments. Use --help.');
      exitCode = 64;
      return;
    }
    options[args[i]] = args[i + 1];
  }
  try {
    final repository = Directory.current.resolveSymbolicLinksSync();
    if (!File('$repository/pubspec.yaml').existsSync() ||
        !File('$repository/AGENTS.md').existsSync()) {
      throw const FormatException('Run from repository root.');
    }
    final Directory output;
    {
      final requested = Directory(options['--out'] ??
              '${Directory.systemTemp.path}/ridex-b09a-evidence-${DateTime.now().microsecondsSinceEpoch}-$pid')
          .absolute;
      // Resolve existing parent before creating anything: reject checkout paths
      // and symlink escapes into it. Output must have an existing parent.
      final parent = requested.parent.resolveSymbolicLinksSync();
      final resolved = Directory(
        '$parent/${requested.uri.pathSegments.where((s) => s.isNotEmpty).last}',
      );
      final target = resolved.existsSync()
          ? resolved.resolveSymbolicLinksSync()
          : resolved.path;
      final normalized = target.replaceAll('\\', '/').toLowerCase();
      final root = repository.replaceAll('\\', '/').toLowerCase();
      if (normalized == root || normalized.startsWith('$root/')) {
        throw const FormatException('Output must be external.');
      }
      var ancestor = Directory(target);
      while (true) {
        if (File('${ancestor.path}/.git').existsSync() ||
            Directory('${ancestor.path}/.git').existsSync()) {
          throw const FormatException(
              'Output cannot be inside any repository.');
        }
        if (ancestor.parent.path == ancestor.path) break;
        ancestor = ancestor.parent;
      }
      output = await Directory(target).create();
      if (File('${output.path}/report.json').existsSync() ||
          File('${output.path}/report.md').existsSync()) {
        throw const FormatException('Do not overwrite evidence.');
      }
    }
    Object? evidence;
    if (options['--evidence'] != null) {
      try {
        final file = File(options['--evidence']!);
        if (await file.length() > 65536) {
          throw const FormatException('Evidence limit.');
        }
        evidence = jsonDecode(await file.readAsString());
      } on Object {
        // A deliberately invalid node yields a sanitized failed schema check.
        evidence = const ['invalid evidence'];
      }
    }
    final tools = AndroidTools.locate(
      sdkRoot: options['--sdk-root'],
      adbOverride: options['--adb'],
    );
    final local = await ReadOnlyPreflightProbe(
      run: runReadOnlyCommand,
      adb: tools.adb,
      sdkLayoutAvailable: tools.layoutAvailable,
      sourceApplicationId: literalApplicationId(
          await File('$repository/android/app/build.gradle').readAsString()),
      sourceComponents: {
        for (final entry in sourcePaths.entries)
          entry.key: File('$repository/${entry.value}').existsSync()
      },
      flutter: options['--flutter'] ??
          (Platform.isWindows ? 'flutter.bat' : 'flutter'),
    ).collect();
    final references = options['--evidence-root'] == null
        ? <String>{}
        : existingEvidenceReferences(Directory(options['--evidence-root']!));
    final report = await evaluateWithApprovedReadOnlyAccess(
        local, evidence, DateTime.now().toUtc(),
        availableReferences: references);
    await File(
      '${output.path}/report.json',
    ).writeAsString(reportJson(report), flush: true);
    await File(
      '${output.path}/report.md',
    ).writeAsString(report.toMarkdown(), flush: true);
    stdout.write(report.toMarkdown());
    stdout.writeln('Report files saved in a new external evidence directory.');
    exitCode = report.allChecksPass ? 0 : 2;
  } on Object {
    stderr.writeln(
      'Preflight could not create a safe report. Run from the repository root with a new external output directory.',
    );
    exitCode = 64;
  }
}
