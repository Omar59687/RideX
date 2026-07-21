import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/app/theme/app_colors.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/app_text_field.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'demo@ridex.app');
  final _passwordController = TextEditingController(text: '123456');
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(selectedRoleProvider);
    final showDemo = !EnvConfig.hasBackendConfig;

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
                  Text('RideX',
                      style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in with email and password. Ride role and driver approval are loaded from Supabase.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Card(
                    color: AppColors.graphite,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                Colors.white.withValues(alpha: .12),
                            child: Icon(
                              role == RideRole.rider
                                  ? Icons.person_pin_circle_rounded
                                  : Icons.drive_eta_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  showDemo
                                      ? 'Sign in as ${role.label}'
                                      : 'Role selection is used for new accounts',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  showDemo
                                      ? 'Demo access is only available when Supabase is not configured.'
                                      : 'Existing accounts are routed automatically after sign-in.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hint: 'name@example.com',
                    validator: emailValidator,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: Icons.alternate_email_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    validator: passwordValidator,
                    obscureText: true,
                    prefixIcon: Icons.lock_outline_rounded,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      label: 'Forgot password?',
                      variant: AppButtonVariant.text,
                      isExpanded: false,
                      onPressed: () => context.push('/forgot-password'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Sign in',
                    trailing: Icons.arrow_forward_rounded,
                    onPressed: () async {
                      setState(() => _errorText = null);
                      if (!_formKey.currentState!.validate()) {
                        return;
                      }
                      final error = await ref
                          .read(sessionControllerProvider.notifier)
                          .signIn(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                            role: role,
                          );
                      if (!mounted || error != null) {
                        setState(() => _errorText = error);
                      }
                    },
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _errorText!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (showDemo) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Continue as Demo ${role.label}',
                      icon: role == RideRole.rider
                          ? Icons.local_taxi_rounded
                          : Icons.drive_eta_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: () async {
                        await ref
                            .read(sessionControllerProvider.notifier)
                            .continueAsDemo(role);
                        if (context.mounted) {
                          context.go(role == RideRole.rider
                              ? '/rider/home'
                              : '/driver/home');
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: AppButton(
                      label: 'Create account',
                      variant: AppButtonVariant.text,
                      isExpanded: false,
                      onPressed: () => context.push('/sign-up'),
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
