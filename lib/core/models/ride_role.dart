enum RideRole { rider, driver, admin }

extension RideRoleX on RideRole {
  String get label => switch (this) {
        RideRole.rider => 'Rider',
        RideRole.driver => 'Driver',
        RideRole.admin => 'Admin',
      };

  static RideRole fromDatabase(String value) => switch (value) {
        'rider' => RideRole.rider,
        'driver' => RideRole.driver,
        'admin' => RideRole.admin,
        _ => throw FormatException('Unknown RideX role: $value'),
      };
}
