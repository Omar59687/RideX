import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/config/env_config.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_text_field.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';
import 'package:ridex/features/auth/presentation/widgets/jordan_phone_field.dart';

class VerifyOtpExtra {
  const VerifyOtpExtra(this.phone);

  final String phone;
}

class VerifyOtpScreen extends ConsumerStatefulWidget {
  const VerifyOtpScreen({
    super.key,
    required this.phone,
    this.backendConfigured,
  });

  static const demoCode = '482701';

  final String? phone;
  final bool? backendConfigured;

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  String? _errorText;
  bool _verifying = false;

  String? get _validPhone {
    final phone = widget.phone;
    return phone != null && JordanPhone.isValid(phone)
        ? JordanPhone.normalize(phone)
        : null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mockMode = !(widget.backendConfigured ?? EnvConfig.hasBackendConfig);
    final phone = _validPhone;
    final available = mockMode && phone != null;

    return AuthShell(
      title: 'Verify your number',
      subtitle: phone == null
          ? 'Return to sign in and enter a valid Jordan mobile number.'
          : 'Enter the six-digit code for ${JordanPhone.format(phone)}.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mockMode && phone != null) ...[
              Text(
                'Demo verification code',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                VerifyOtpScreen.demoCode,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 6,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (!mockMode)
              _UnavailableMessage(
                message:
                    'Phone verification is not connected to the production backend. Sign in with email instead.',
              )
            else if (phone == null)
              const _UnavailableMessage(
                message: 'The phone number is missing or invalid.',
              ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              controller: _codeController,
              label: 'Verification code',
              hint: '6-digit code',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.password_rounded,
              enabled: available,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (value) {
                if (value == null || value.length != 6) {
                  return 'Enter the six-digit code';
                }
                return null;
              },
              onFieldSubmitted: (_) => _verify(),
              autofillHints: const [AutofillHints.oneTimeCode],
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
              label: 'Verify and continue',
              isLoading: _verifying,
              onPressed: available ? _verify : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Use email instead',
              variant: AppButtonVariant.text,
              onPressed: _verifying ? null : () => context.go('/sign-in'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verify() async {
    if (_verifying ||
        (widget.backendConfigured ?? EnvConfig.hasBackendConfig) ||
        _validPhone == null) {
      return;
    }
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) return;
    if (_codeController.text != VerifyOtpScreen.demoCode) {
      setState(() => _errorText = 'That demo code is not correct.');
      return;
    }
    setState(() => _verifying = true);
    await ref
        .read(sessionControllerProvider.notifier)
        .continueAsDemo(RideRole.rider);
    if (mounted) context.go('/rider/home');
  }
}

class _UnavailableMessage extends StatelessWidget {
  const _UnavailableMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
