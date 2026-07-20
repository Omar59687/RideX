import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/status_chip.dart';

class DriverApplicationStatusScreen extends StatelessWidget {
  const DriverApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Driver application',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                  child: Text('Approved for demo',
                      style: Theme.of(context).textTheme.headlineLarge)),
              const StatusChip(label: 'Approved'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Card(
            child: ListTile(
              title: Text('Toyota Camry · 652-UKW'),
              subtitle: Text('Economy · Black · Ready for mock rides'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
              label: 'Back to driver home',
              onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
