import 'package:ridex/core/errors/auth_exception.dart';
import 'package:ridex/core/models/app_user.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

class ProfileService {
  const ProfileService(this._client);

  final SupabaseClient _client;

  Future<AppUser> fetchAppUser(String userId) async {
    final userRow = await _client
        .from('users')
        .select('id, role, display_name, email, photo_url, is_blocked')
        .eq('id', userId)
        .maybeSingle();

    if (userRow == null) {
      throw const ProfileException('Your account profile is missing.');
    }

    final RideRole role;
    try {
      role = RideRoleX.fromDatabase(userRow['role'] as String);
    } on Object {
      throw const ProfileException('Your account profile is invalid.');
    }

    DriverApprovalStatus? approvalStatus;
    if (role == RideRole.driver) {
      final driverRow = await _client
          .from('driver_profiles')
          .select('approval_status')
          .eq('user_id', userId)
          .maybeSingle();

      if (driverRow == null) {
        throw const ProfileException('Your Driver profile is missing.');
      }
      try {
        approvalStatus = DriverApprovalStatusX.fromDatabase(
          driverRow['approval_status'] as String,
        );
      } on Object {
        throw const ProfileException('Your Driver profile is invalid.');
      }
    }

    return AppUser(
      id: userRow['id'] as String,
      name: userRow['display_name'] as String? ?? 'RideX User',
      email: userRow['email'] as String? ?? '',
      role: role,
      isBlocked: userRow['is_blocked'] as bool? ?? false,
      driverApprovalStatus: approvalStatus,
      avatarUrl: userRow['photo_url'] as String?,
    );
  }
}
