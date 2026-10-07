import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/services/places/places_session_token.dart';

void main() {
  test('Places session tokens are URL-safe, bounded, and unique', () {
    final tokens = List<String>.generate(100, (_) => newPlacesSessionToken());

    for (final token in tokens) {
      expect(placesSessionTokenRegExp.hasMatch(token), isTrue);
    }
    expect(tokens.toSet(), hasLength(tokens.length));
  });

  test('Places session-token length is constrained to backend limits', () {
    expect(newPlacesSessionToken(length: 16), hasLength(16));
    expect(newPlacesSessionToken(length: 128), hasLength(128));
    expect(() => newPlacesSessionToken(length: 15), throwsRangeError);
    expect(() => newPlacesSessionToken(length: 129), throwsRangeError);
  });
}
