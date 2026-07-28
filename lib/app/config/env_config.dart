import 'dart:convert';

enum EnvConfigFailure {
  incompleteBackendConfig,
  placeholderValue,
  invalidUrl,
  insecureUrl,
  invalidPublishableKey,
  forbiddenBackendKey,
}

class EnvConfigException implements Exception {
  const EnvConfigException(this.failure);

  final EnvConfigFailure failure;

  @override
  String toString() => 'Invalid application environment configuration.';
}

class SupabaseEnvironment {
  const SupabaseEnvironment({required this.url, required this.publishableKey});

  final String url;
  final String publishableKey;
}

class EnvConfig {
  const EnvConfig._();

  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');
  static const googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  static bool get hasBackendConfig =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  static bool get hasMapsConfig => googleMapsApiKey.isNotEmpty;

  static SupabaseEnvironment? get supabaseEnvironment =>
      validateSupabaseEnvironment(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );

  static SupabaseEnvironment? validateSupabaseEnvironment({
    required String url,
    required String publishableKey,
  }) {
    final normalizedUrl = url.trim();
    final normalizedKey = publishableKey.trim();
    final hasUrl = normalizedUrl.isNotEmpty;
    final hasKey = normalizedKey.isNotEmpty;

    if (!hasUrl && !hasKey) return null;
    if (!hasUrl || !hasKey) {
      throw const EnvConfigException(
        EnvConfigFailure.incompleteBackendConfig,
      );
    }
    if (_isPlaceholder(normalizedUrl) || _isPlaceholder(normalizedKey)) {
      throw const EnvConfigException(EnvConfigFailure.placeholderValue);
    }

    final uri = Uri.tryParse(normalizedUrl);
    if (url != normalizedUrl ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const EnvConfigException(EnvConfigFailure.invalidUrl);
    }
    if (uri.scheme.toLowerCase() != 'https') {
      throw const EnvConfigException(EnvConfigFailure.insecureUrl);
    }

    _validatePublishableKey(publishableKey, normalizedKey);
    return SupabaseEnvironment(
      url: normalizedUrl,
      publishableKey: normalizedKey,
    );
  }

  static bool _isPlaceholder(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('<') ||
        normalized.contains('>') ||
        normalized.contains('your-project') ||
        normalized.contains('your_project') ||
        normalized.contains('your-key') ||
        normalized.contains('your_key') ||
        normalized.contains('placeholder') ||
        normalized.contains('change-me') ||
        normalized.contains('changeme') ||
        normalized.contains('replace-with') ||
        normalized.contains('replace_with') ||
        normalized.contains('example.supabase.co');
  }

  static void _validatePublishableKey(String value, String normalized) {
    final lower = normalized.toLowerCase();
    if (lower.startsWith('sb_secret_') || lower.contains('service_role')) {
      throw const EnvConfigException(EnvConfigFailure.forbiddenBackendKey);
    }
    if (lower.startsWith('sb_') && !lower.startsWith('sb_publishable_')) {
      throw const EnvConfigException(
        EnvConfigFailure.invalidPublishableKey,
      );
    }
    if (value != normalized ||
        normalized.length < 20 ||
        RegExp(r'\s').hasMatch(normalized) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(normalized)) {
      throw const EnvConfigException(
        EnvConfigFailure.invalidPublishableKey,
      );
    }
    if (normalized.startsWith('eyJ')) {
      _validateLegacyJwt(normalized);
    }
  }

  static void _validateLegacyJwt(String value) {
    final segments = value.split('.');
    if (segments.length != 3) {
      throw const EnvConfigException(
        EnvConfigFailure.invalidPublishableKey,
      );
    }

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      if (payload is! Map<String, dynamic>) {
        throw const EnvConfigException(
          EnvConfigFailure.invalidPublishableKey,
        );
      }
      final role = payload['role'];
      if (role == 'service_role') {
        throw const EnvConfigException(EnvConfigFailure.forbiddenBackendKey);
      }
      if (role != 'anon') {
        throw const EnvConfigException(
          EnvConfigFailure.invalidPublishableKey,
        );
      }
    } on EnvConfigException {
      rethrow;
    } on Object {
      throw const EnvConfigException(
        EnvConfigFailure.invalidPublishableKey,
      );
    }
  }
}
