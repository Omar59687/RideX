import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/services/supabase/auth_service.dart';
import 'package:ridex/core/services/supabase/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository({
    required AuthService authService,
    required ProfileService profileService,
  })  : _authService = authService,
        _profileService = profileService;

  final AuthService _authService;
  final ProfileService _profileService;

  @override
  Stream<void> authStateChanges() => _authService.authStateChanges();

  @override
  Future<AppUser?> restoreSession() async {
    final session = _authService.currentSession;
    final user = session?.user;
    if (user == null) {
      return null;
    }
    return _profileService.fetchAppUser(user.id);
  }

  @override
  Future<AppUser> continueAsDemo() async {
    throw const AuthException(
        'Demo authentication is unavailable when Supabase is configured.');
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response =
          await _authService.signIn(email: email, password: password);
      final user = response.user;
      if (user == null) {
        throw const AuthException(
            'Unable to sign in right now. Please try again.');
      }
      return _profileService.fetchAppUser(user.id);
    } on AuthException {
      rethrow;
    } on AuthApiException catch (error) {
      throw AuthException(_mapAuthError(error));
    } catch (_) {
      throw const AuthException('Something went wrong while signing in.');
    }
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        metadata: {
          'display_name': name.trim(),
        },
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException(
            'Account creation did not complete. Please try again.');
      }
      if (response.session == null) {
        throw const AuthException(
            'Account created. Please confirm your email before signing in.');
      }
      return _profileService.fetchAppUser(user.id);
    } on AuthException {
      rethrow;
    } on AuthApiException catch (error) {
      throw AuthException(_mapAuthError(error));
    } catch (_) {
      throw const AuthException(
          'Something went wrong while creating your account.');
    }
  }

  @override
  Future<void> signOut() => _authService.signOut();

  String _mapAuthError(AuthApiException error) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (message.contains('user already registered')) {
      return 'This email is already registered.';
    }
    return error.message;
  }
}
