String? requiredField(String? value, {String label = 'Field'}) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required';
  }
  return null;
}

String? emailValidator(String? value) {
  final required = requiredField(value, label: 'Email');
  if (required != null) {
    return required;
  }
  if (!(value!.contains('@') && value.contains('.'))) {
    return 'Enter a valid email';
  }
  return null;
}

String? passwordValidator(String? value) {
  final required = requiredField(value, label: 'Password');
  if (required != null) {
    return required;
  }
  if (value!.length < 6) {
    return 'Use at least 6 characters';
  }
  return null;
}
