import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.textInputAction,
    this.suffixIcon,
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.readOnly = false,
    this.focusNode,
    this.onChanged,
    this.onFieldSubmitted,
    this.autofillHints,
    this.maxLines = 1,
    this.minLines,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final bool readOnly;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final int? maxLines;
  final int? minLines;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          textField: true,
          label: semanticLabel ?? label,
          enabled: enabled,
          child: TextFormField(
            controller: controller,
            validator: validator,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            enabled: enabled,
            readOnly: readOnly,
            focusNode: focusNode,
            onChanged: onChanged,
            onFieldSubmitted: onFieldSubmitted,
            autofillHints: autofillHints,
            maxLines: obscureText ? 1 : maxLines,
            minLines: minLines,
            decoration: InputDecoration(
              hintText: hint,
              helperText: helperText,
              errorText: errorText,
              prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
              suffixIcon: suffixIcon,
              constraints: const BoxConstraints(minHeight: 52),
            ),
          ),
        ),
      ],
    );
  }
}
