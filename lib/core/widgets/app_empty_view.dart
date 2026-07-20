import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';

class AppEmptyView extends StatelessWidget {
  const AppEmptyView(
      {super.key,
      required this.title,
      required this.message,
      this.icon = Icons.inbox_outlined});

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.cloud,
            child: Icon(icon, size: 26, color: AppColors.slate),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
