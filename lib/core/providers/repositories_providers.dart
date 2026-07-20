import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/mocks/mock_repositories.dart';
import 'package:ridex/core/repositories/auth_repository.dart';
import 'package:ridex/core/repositories/booking_repository.dart';
import 'package:ridex/core/repositories/profile_repository.dart';
import 'package:ridex/core/repositories/trips_repository.dart';

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => MockAuthRepository());
final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => MockBookingRepository());
final tripsRepositoryProvider =
    Provider<TripsRepository>((ref) => MockTripsRepository());
final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => MockProfileRepository());
