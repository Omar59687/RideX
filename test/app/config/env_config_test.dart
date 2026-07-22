import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/config/env_config.dart';

void main() {
  const validUrl = 'https://backend.unit-test.invalid';
  const validPublishableKey = 'sb_publishable_unit_test_value_000000000000';

  group('EnvConfig.validateSupabaseEnvironment', () {
    test('uses Mock mode when both values are absent', () {
      expect(
        EnvConfig.validateSupabaseEnvironment(url: '', publishableKey: ''),
        isNull,
      );
    });

    test('rejects incomplete configuration', () {
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: '',
        ),
        throwsFailure(EnvConfigFailure.incompleteBackendConfig),
      );
    });

    test('rejects placeholder values', () {
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: 'https://your-project.supabase.co',
          publishableKey: validPublishableKey,
        ),
        throwsFailure(EnvConfigFailure.placeholderValue),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: 'sb_publishable_REPLACE_WITH_PUBLIC_CLIENT_KEY',
        ),
        throwsFailure(EnvConfigFailure.placeholderValue),
      );
    });

    test('rejects malformed and insecure URLs', () {
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: 'not-a-url',
          publishableKey: validPublishableKey,
        ),
        throwsFailure(EnvConfigFailure.invalidUrl),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: 'http://remote.unit-test.invalid',
          publishableKey: validPublishableKey,
        ),
        throwsFailure(EnvConfigFailure.insecureUrl),
      );
    });

    test('accepts a valid custom HTTPS domain', () {
      final environment = EnvConfig.validateSupabaseEnvironment(
        url: validUrl,
        publishableKey: validPublishableKey,
      );

      expect(environment, isNotNull);
      expect(environment!.url, validUrl);
      expect(environment.publishableKey, validPublishableKey);
    });

    test('rejects clearly invalid publishable keys', () {
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: 'too-short',
        ),
        throwsFailure(EnvConfigFailure.invalidPublishableKey),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: 'invalid key with whitespace 000000',
        ),
        throwsFailure(EnvConfigFailure.invalidPublishableKey),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: 'sb_unknown_unit_test_value_000000000000',
        ),
        throwsFailure(EnvConfigFailure.invalidPublishableKey),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: _syntheticJwt(role: 'authenticated'),
        ),
        throwsFailure(EnvConfigFailure.invalidPublishableKey),
      );
    });

    test('rejects recognized secret and service-role keys', () {
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: 'sb_secret_unit_test_value_000000000000',
        ),
        throwsFailure(EnvConfigFailure.forbiddenBackendKey),
      );
      expect(
        () => EnvConfig.validateSupabaseEnvironment(
          url: validUrl,
          publishableKey: _syntheticJwt(role: 'service_role'),
        ),
        throwsFailure(EnvConfigFailure.forbiddenBackendKey),
      );
    });

    test('accepts a structurally valid legacy anon key', () {
      final key = _syntheticJwt(role: 'anon');

      final environment = EnvConfig.validateSupabaseEnvironment(
        url: validUrl,
        publishableKey: key,
      );

      expect(environment, isNotNull);
      expect(environment!.publishableKey, key);
    });
  });
}

Matcher throwsFailure(EnvConfigFailure failure) {
  return throwsA(
    isA<EnvConfigException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );
}

String _syntheticJwt({required String role}) {
  final header = _withoutPadding(
    base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')),
  );
  final payload = _withoutPadding(
    base64Url.encode(utf8.encode(jsonEncode({'role': role}))),
  );
  return '$header.$payload.synthetic_unit_test_signature_000000';
}

String _withoutPadding(String value) => value.replaceAll('=', '');
