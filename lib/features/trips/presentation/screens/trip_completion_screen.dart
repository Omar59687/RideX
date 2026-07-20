import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/utils/money_utils.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

class TripCompletionScreen extends StatelessWidget {
  const TripCompletionScreen({super.key, required this.isDriverView});

  final bool isDriverView;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Trip completed',
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(
              radius: 42, child: Icon(Icons.check_rounded, size: 40)),
          const SizedBox(height: AppSpacing.lg),
          Text(
              isDriverView
                  ? 'Ride finished successfully'
                  : 'Thanks for riding with RideX',
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(formatMoney(1.99),
              style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: isDriverView ? 'Open trip history' : 'Rate driver',
            onPressed: () =>
                context.go(isDriverView ? '/history' : '/rider/rating'),
          ),
        ],
      ),
    );
  }
}
