import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/core/widgets/app_button.dart';

class AppErrorView extends StatelessWidget {
  const AppErrorView(
      {super.key, required this.title, required this.message, this.onRetry});

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFFFECEC),
            child: Icon(
              Icons.error_outline_rounded,
              size: 28,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            AppButton(label: 'Try again', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}
