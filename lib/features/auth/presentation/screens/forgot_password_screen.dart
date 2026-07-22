import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_text_field.dart';
import 'package:ridex/features/auth/presentation/widgets/auth_shell.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Reset your password',
      subtitle: 'Return to your account with a simple recovery step.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sent ? Icons.mark_email_read_rounded : Icons.mail_outline,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    sent
                        ? 'A demo reset link has been sent.'
                        : 'Mock recovery only. Enter your email and we will simulate a password reset message.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              controller: _controller,
              label: 'Email',
              hint: 'name@example.com',
              validator: emailValidator,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.alternate_email_rounded,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: sent ? 'Sent' : 'Send reset link',
              onPressed: sent
                  ? null
                  : () {
                      if (_formKey.currentState!.validate()) {
                        setState(() => sent = true);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
