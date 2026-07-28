import 'package:flutter/material.dart';
import 'package:ridex/core/widgets/app_dialog.dart';

Future<void> showComingSoonDialog(
  BuildContext context, {
  required String feature,
}) async {
  await showAppDialog(
    context: context,
    title: 'Coming soon',
    message: '$feature is not available in this demo yet.',
    icon: Icons.auto_awesome_outlined,
    confirmLabel: 'Got it',
  );
}
