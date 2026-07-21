import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverApplicationStatusScreen extends ConsumerWidget {
  const DriverApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final approvalStatus = session.user?.driverApprovalStatus;

    final (title, subtitle, chipLabel) = switch (approvalStatus) {
      DriverApprovalStatus.approved => (
          'Approved for driver access',
          'Your RideX driver account can access the full driver flow.',
          'Approved'
        ),
      DriverApprovalStatus.rejected => (
          'Application rejected',
          'Your driver account needs review before you can go online.',
          'Rejected'
        ),
      _ => (
          'Application pending review',
          'Your account is waiting for manual approval before driver access is unlocked.',
          'Pending'
        ),
    };

    return AppScaffold(
      title: 'Driver application',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              StatusChip(label: chipLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              title: const Text('Driver account status'),
              subtitle: Text(subtitle),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (approvalStatus == DriverApprovalStatus.approved)
            AppButton(
              label: 'Back to driver home',
              onPressed: () => Navigator.of(context).pop(),
            ),
          if (approvalStatus != DriverApprovalStatus.approved)
            AppButton(
              label: 'Sign out',
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).signOut(),
            ),
        ],
      ),
    );
  }
}
