import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int rating = 4;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Rate your trip',
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircleAvatar(radius: 40, child: Icon(Icons.person)),
          const SizedBox(height: AppSpacing.lg),
          Text('How was Omar?',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (index) => IconButton(
                onPressed: () => setState(() => rating = index + 1),
                icon: Icon(
                  index < rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: Colors.amber,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
              label: 'Submit review', onPressed: () => context.go('/history')),
        ],
      ),
    );
  }
}
