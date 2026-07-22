import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ridex/core/widgets/app_text_field.dart';

class JordanPhone {
  const JordanPhone._();

  static String digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static String normalize(String value) {
    var valueDigits = digits(value);
    if (valueDigits.startsWith('00962')) {
      valueDigits = valueDigits.substring(2);
    }
    if (valueDigits.startsWith('0')) {
      valueDigits = '962${valueDigits.substring(1)}';
    }
    if (valueDigits.startsWith('7')) {
      valueDigits = '962$valueDigits';
    }
    return valueDigits.startsWith('962') ? '+$valueDigits' : value;
  }

  static bool isValid(String value) =>
      RegExp(r'^\+9627[789]\d{7}$').hasMatch(normalize(value));

  static String format(String value) {
    var local = digits(normalize(value));
    if (local.startsWith('962')) {
      local = local.substring(3);
    }
    if (local.length > 9) {
      local = local.substring(0, 9);
    }
    final buffer = StringBuffer('+962');
    if (local.isNotEmpty) {
      final end = local.length < 2 ? local.length : 2;
      buffer.write(' ${local.substring(0, end)}');
    }
    if (local.length > 2) {
      final end = local.length < 5 ? local.length : 5;
      buffer.write(' ${local.substring(2, end)}');
    }
    if (local.length > 5) {
      buffer.write(' ${local.substring(5)}');
    }
    return buffer.toString();
  }

  static String? validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!isValid(value)) {
      return 'Enter a valid Jordan mobile number';
    }
    return null;
  }
}

class JordanPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = JordanPhone.format(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class JordanPhoneField extends StatelessWidget {
  const JordanPhoneField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: 'Mobile number',
      hint: '+962 7X XXX XXXX',
      helperText: 'Jordan mobile numbers only',
      prefixIcon: Icons.phone_android_rounded,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      inputFormatters: [JordanPhoneInputFormatter()],
      validator: JordanPhone.validate,
      enabled: enabled,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: const [AutofillHints.telephoneNumber],
    );
  }
}
