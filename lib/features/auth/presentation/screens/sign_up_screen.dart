import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/app_text_field.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(selectedRoleProvider);
    return AppScaffold(
      title: null,
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Text('Create account',
                      style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                      'Build a polished demo session for the ${role.label.toLowerCase()} flow before backend integration.'),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                        color: AppColors.cloud,
                        borderRadius: BorderRadius.circular(24)),
                    child: Row(
                      children: [
                        CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.card,
                            child: Icon(role == RideRole.rider
                                ? Icons.person_pin_circle_rounded
                                : Icons.drive_eta_rounded)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                            child: Text('Mock account for ${role.label}',
                                style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _nameController,
                    label: 'Full name',
                    hint: 'Enter your full name',
                    validator: (value) => requiredField(value, label: 'Name'),
                    prefixIcon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'name@example.com',
                    validator: emailValidator,
                    prefixIcon: Icons.alternate_email_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Minimum 6 characters',
                    validator: passwordValidator,
                    obscureText: true,
                    prefixIcon: Icons.lock_outline_rounded,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Create demo account',
                    trailing: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) {
                        return;
                      }
                      await ref.read(sessionControllerProvider.notifier).signUp(
                            name: _nameController.text,
                            email: _emailController.text,
                            password: _passwordController.text,
                            role: role,
                          );
                      if (context.mounted) {
                        context.go(role == RideRole.rider
                            ? '/rider/home'
                            : '/driver/home');
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: AppButton(
                      label: 'Back to sign in',
                      isExpanded: false,
                      variant: AppButtonVariant.text,
                      onPressed: () => context.pop(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
