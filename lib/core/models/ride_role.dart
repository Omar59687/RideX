enum RideRole { rider, driver }

extension RideRoleX on RideRole {
  String get label => switch (this) {
        RideRole.rider => 'Rider',
        RideRole.driver => 'Driver',
      };
}
