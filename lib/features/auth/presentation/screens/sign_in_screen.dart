import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_text_field.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_method_tabs.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';
import 'package:ridex/features/auth/presentation/widgets/jordan_phone_field.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    this.backendConfigured,
  });

  final bool? backendConfigured;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'demo@ridex.app');
  final _passwordController = TextEditingController(text: '123456');
  final _phoneController = TextEditingController(text: '+962 ');
  AuthMethod _method = AuthMethod.email;
  String? _errorText;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(selectedRoleProvider);
    final mockMode = !(widget.backendConfigured ?? EnvConfig.hasBackendConfig);

    return AuthShell(
      showBack: false,
      title: 'Welcome back',
      subtitle: 'Sign in to keep your next RideX journey moving.',
      footer: AppButton(
        label: 'Create account',
        variant: AppButtonVariant.text,
        isExpanded: false,
        onPressed: _submitting ? null : () => context.push('/sign-up'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthMethodTabs(
            selected: _method,
            phoneEnabled: mockMode,
            onSelected: (method) => setState(() {
              _method = method;
              _errorText = null;
            }),
          ),
          if (!mockMode) ...[
            const SizedBox(height: AppSpacing.sm),
            _InfoBanner(
              icon: Icons.info_outline_rounded,
              text:
                  'Phone sign-in is not available with the production backend yet. Use your email and password.',
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: _method == AuthMethod.email
                ? _buildEmailForm(context, role, mockMode)
                : _buildPhoneForm(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailForm(
    BuildContext context,
    RideRole role,
    bool mockMode,
  ) {
    return Form(
      key: _emailFormKey,
      child: Column(
        key: const ValueKey('email-form'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoleSummary(role: role, mockMode: mockMode),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'name@example.com',
            validator: emailValidator,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.alternate_email_rounded,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            hint: 'Enter your password',
            validator: passwordValidator,
            obscureText: true,
            prefixIcon: Icons.lock_outline_rounded,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _submitEmail(),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              label: 'Forgot password?',
              variant: AppButtonVariant.text,
              isExpanded: false,
              onPressed:
                  _submitting ? null : () => context.push('/forgot-password'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Sign in',
            trailing: Icons.arrow_forward_rounded,
            isLoading: _submitting,
            onPressed: _submitEmail,
          ),
          _buildError(context),
          if (mockMode) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Continue as Demo Rider',
              icon: Icons.local_taxi_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: _submitting ? null : _continueAsDemo,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneForm(BuildContext context) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        key: const ValueKey('phone-form'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use the mock phone journey',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'We will take you to a deterministic OTP check. No message is sent.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          JordanPhoneField(
            controller: _phoneController,
            onFieldSubmitted: (_) => _continueWithPhone(),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Continue with phone',
            trailing: Icons.arrow_forward_rounded,
            onPressed: _continueWithPhone,
          ),
          _buildError(context),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    if (_errorText == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        liveRegion: true,
        child: Text(
          _errorText!,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  Future<void> _submitEmail() async {
    if (_submitting) return;
    setState(() => _errorText = null);
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final error = await ref.read(sessionControllerProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _errorText = error;
    });
  }

  void _continueWithPhone() {
    if (!_phoneFormKey.currentState!.validate()) return;
    final phone = JordanPhone.normalize(_phoneController.text);
    context.push(
        Uri(path: '/verify-otp', queryParameters: {'phone': phone}).toString());
  }

  Future<void> _continueAsDemo() async {
    setState(() => _submitting = true);
    await ref.read(sessionControllerProvider.notifier).continueAsDemo();
    if (!mounted) return;
    context.go('/rider/home');
  }
}

class _RoleSummary extends StatelessWidget {
  const _RoleSummary({required this.role, required this.mockMode});

  final RideRole role;
  final bool mockMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Row(
        children: [
          Icon(
            role == RideRole.rider
                ? Icons.person_pin_circle_rounded
                : Icons.drive_eta_rounded,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              mockMode
                  ? 'Sign in as ${role.label}'
                  : 'Existing accounts use their saved role',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.secondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
