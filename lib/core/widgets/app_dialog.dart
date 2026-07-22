import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.onConfirm,
    this.onCancel,
    this.destructive = false,
  });

  final String title;
  final String message;
  final IconData? icon;
  final Widget? content;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: icon == null
          ? null
          : Icon(
              icon,
              color: destructive
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (content != null) ...[
              const SizedBox(height: AppSpacing.md),
              content!,
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      actions: [
        if (onCancel != null)
          AppButton(
            label: cancelLabel,
            onPressed: onCancel,
            variant: AppButtonVariant.text,
            isExpanded: false,
          ),
        if (onConfirm != null)
          AppButton(
            label: confirmLabel,
            onPressed: onConfirm,
            destructive: destructive,
            isExpanded: false,
          ),
      ],
    );
  }
}

Future<bool?> showAppDialog({
  required BuildContext context,
  required String title,
  required String message,
  IconData? icon,
  Widget? content,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => AppDialog(
      title: title,
      message: message,
      icon: icon,
      content: content,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onConfirm: () => Navigator.of(dialogContext).pop(true),
    ),
  );
}
