import 'package:ridex/core/models/app_user.dart';

abstract class AuthRepository {
  Stream<void> authStateChanges();
  Future<AppUser?> restoreSession();
  Future<AppUser> continueAsDemo();
  Future<AppUser> signIn({
    required String email,
    required String password,
  });
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  });
  Future<void> signOut();
}
