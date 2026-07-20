import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/app.dart';

Widget buildTestApp() {
  return const ProviderScope(child: RideXApp());
}
