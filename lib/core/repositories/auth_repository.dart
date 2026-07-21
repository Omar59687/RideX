import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/ride_role.dart';

abstract class AuthRepository {
  Stream<void> authStateChanges();
  Future<AppUser?> restoreSession();
  Future<AppUser> continueAsDemo(RideRole role);
  Future<AppUser> signIn({
    required String email,
    required String password,
    RideRole? role,
  });
  Future<AppUser> signUp(
      {required String name,
      required String email,
      required String password,
      required RideRole role});
  Future<void> signOut();
}
