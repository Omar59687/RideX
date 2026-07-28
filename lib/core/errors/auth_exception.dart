class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfileException extends AuthException {
  const ProfileException(super.message);
}
