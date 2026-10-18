import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final configuredOutput = Platform.environment['RIDEX_SMOKE_OUTPUT_DIR'];
  final output = configuredOutput == null
      ? await Directory.systemTemp.createTemp('ridex-rider-demo-smoke-')
      : Directory(configuredOutput).absolute;
  final checkout = Directory.current.absolute.uri.normalizePath().toString();
  if (output.absolute.uri.normalizePath().toString().toLowerCase().startsWith(
        checkout.toLowerCase(),
      )) {
    throw ArgumentError('RIDEX_SMOKE_OUTPUT_DIR must be outside the checkout.');
  }
  await output.create(recursive: true);
  stdout.writeln('Smoke artifacts: ${output.path}');

  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}${Platform.pathSeparator}$name.png')
          .writeAsBytes(bytes, flush: true);
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      await File('${output.path}${Platform.pathSeparator}result.json')
          .writeAsString(jsonEncode(data), flush: true);
    },
    writeResponseOnFailure: true,
  );
}
