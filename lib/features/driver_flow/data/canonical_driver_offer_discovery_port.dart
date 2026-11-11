import 'package:ridex/core/repositories/driver_eligibility_repository.dart';

/// Borrowed normal-user access, sharing B07's verified SDK/epoch binding.
/// SELECT only. Returned rows are untrusted advisory discovery evidence.
abstract interface class CanonicalDriverOfferDiscoveryPort
    implements DriverEligibilityTransport {
  static const rowLimit = 2;
  Object? get sessionIdentity;
  Future<List<Map<String, Object?>>> readOfferedRows(DateTime after);
}
