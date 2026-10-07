import 'dart:math';

/// Shared Places session-token generation.
///
/// Matches the Places edge validation of 16-128 URL-safe characters
/// (`^[A-Za-z0-9_-]{16,128}$`) so the same token can be reused from
/// autocomplete through prediction resolution within one search session.
final RegExp placesSessionTokenRegExp = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

const _placesSessionTokenAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

/// Creates a cryptographically secure URL-safe Places session token.
///
/// Defaults to 32 characters, comfortably inside the accepted 16-128 range.
String newPlacesSessionToken({int length = 32}) {
  RangeError.checkValueInInterval(length, 16, 128, 'length');
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(
      _placesSessionTokenAlphabet[
          random.nextInt(_placesSessionTokenAlphabet.length)],
    );
  }
  return buffer.toString();
}
