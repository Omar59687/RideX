import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isBlocked = false,
    this.driverApprovalStatus,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final RideRole role;
  final bool isBlocked;
  final DriverApprovalStatus? driverApprovalStatus;
  final String? avatarUrl;

  bool get isDriverApproved =>
      role == RideRole.driver &&
      driverApprovalStatus == DriverApprovalStatus.approved;

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        role,
        isBlocked,
        driverApprovalStatus,
        avatarUrl,
      ];
}
