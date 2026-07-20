import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/utils/validators.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/app_text_field.dart';

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
    return AppScaffold(
      title: 'Reset password',
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.md),
            Text('Mock recovery only',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(sent
                ? 'A demo reset link has been sent.'
                : 'Enter your email and we will simulate a password reset message.'),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
                controller: _controller,
                label: 'Email',
                validator: emailValidator),
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
