import 'package:ridex/core/models/app_user.dart';

abstract class ProfileRepository {
  Future<AppUser> getProfile(String userId);
}
