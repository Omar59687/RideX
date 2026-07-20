import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/ride_role.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final RideRole role;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, name, email, role, avatarUrl];
}
