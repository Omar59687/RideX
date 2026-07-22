import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_text_field.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';

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
  String? _errorText;
  bool _submitting = false;

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

    return AuthShell(
      title: 'Create your account',
      subtitle: 'One profile for every RideX journey across Jordan.',
      footer: AppButton(
        label: 'Back to sign in',
        isExpanded: false,
        variant: AppButtonVariant.text,
        onPressed: _submitting ? null : () => context.pop(),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SelectedRole(role: role),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _nameController,
              label: 'Full name',
              hint: 'Enter your full name',
              validator: (value) => requiredField(value, label: 'Name'),
              prefixIcon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'name@example.com',
              validator: emailValidator,
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Minimum 6 characters',
              validator: passwordValidator,
              obscureText: true,
              prefixIcon: Icons.lock_outline_rounded,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submit(role),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  _errorText!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Create account',
              trailing: Icons.arrow_forward_rounded,
              isLoading: _submitting,
              onPressed: () => _submit(role),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(RideRole role) async {
    if (_submitting) return;
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final error = await ref.read(sessionControllerProvider.notifier).signUp(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          role: role,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorText = error;
    });
  }
}

class _SelectedRole extends StatelessWidget {
  const _SelectedRole({required this.role});

  final RideRole role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Icon(
            role == RideRole.rider
                ? Icons.person_pin_circle_rounded
                : Icons.drive_eta_rounded,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Creating a ${role.label.toLowerCase()} account',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
