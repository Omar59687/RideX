import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ridex/core/services/trips/driver_completion_command_store.dart';
import 'package:ridex/core/services/trips/file_driver_completion_command_store.dart';

/// Application support, never temp/cache or SharedPreferences. The journal
/// itself partitions by namespace/Driver and owns safe creation/acknowledgement.
Future<DriverCompletionCommandStore> openApplicationCompletionStore() async {
  final support = await getApplicationSupportDirectory();
  return FileDriverCompletionCommandStore(
      directory:
          Directory.fromUri(support.uri.resolve('driver_cash_completion/')));
}
