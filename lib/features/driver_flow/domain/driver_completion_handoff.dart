import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';

/// Authenticated transport scope, never supplied by a screen or command.
/// sdkSession is an opaque identity only: never serialize/display SDK credentials.
final class DriverHandoffScope {
  const DriverHandoffScope(
      {required this.owner,
      required this.sdkSession,
      required this.isApprovedDriver});
  final DriverAuthorityOwner owner;
  final Object? sdkSession;
  final bool isApprovedDriver;
  bool get usable => owner.isUsable && sdkSession != null && isApprovedDriver;
  bool sameAuthority(DriverHandoffScope other) =>
      usable &&
      other.usable &&
      owner.sameOwner(other.owner) &&
      identical(sdkSession, other.sdkSession);
}

/// Read/presentation outcomes, NOT additional database payment statuses.
enum DriverHandoffReadState {
  notChecked,
  loading,
  verified,
  missing,
  unknown,
  error,
  unauthorized
}

/// The reader attaches the actual authenticated read scope and requested Trip.
/// Missing/UNKNOWN/error never carry a success payload or fabricated identity.
final class DriverHandoffRead<T> {
  DriverHandoffRead(
      {required this.scope,
      required this.tripId,
      required this.state,
      this.evidence}) {
    _id(tripId);
    if ((state == DriverHandoffReadState.verified) != (evidence != null) ||
        state == DriverHandoffReadState.loading ||
        state == DriverHandoffReadState.notChecked) {
      throw ArgumentError(
          'A terminal read outcome with matching evidence is required.');
    }
  }
  final DriverHandoffScope scope;
  final String tripId;
  final DriverHandoffReadState state;
  final T? evidence;
}

/// Fields must come from an authenticated canonical Trip reread, not an RPC ack,
/// MockTrip, completion callback or journal. Card is read-only/fake-backed in C05.
final class DriverHandoffTrip {
  DriverHandoffTrip(
      {required this.tripId,
      required this.driverId,
      required this.status,
      required this.version,
      required this.method}) {
    _id(tripId);
    _id(driverId);
    _version(version);
  }
  final String tripId, driverId;
  final DriverTripLifecycleStatus status;
  final int version;
  final PaymentMethod method;
}

sealed class DriverHandoffPayment {
  DriverHandoffPayment(
      {required this.paymentId,
      required this.tripId,
      required this.version,
      required this.method}) {
    _id(paymentId);
    _id(tripId);
    _version(version);
  }
  final String paymentId, tripId;
  final int version;
  final PaymentMethod method;
}

final class DriverHandoffCashPayment extends DriverHandoffPayment {
  DriverHandoffCashPayment(
      {required super.paymentId,
      required super.tripId,
      required super.version,
      required this.status})
      : super(method: PaymentMethod.cash);
  final CashPaymentStatus status;
}

final class DriverHandoffCardPayment extends DriverHandoffPayment {
  DriverHandoffCardPayment(
      {required super.paymentId,
      required super.tripId,
      required super.version,
      required this.status})
      : super(method: PaymentMethod.card);
  final CardPaymentStatus status;
}

/// Immutable backend-issued receipt identity and number from an authorized
/// Driver-safe receipt read. Receipt presence never infers Payment status.
final class DriverHandoffReceipt {
  DriverHandoffReceipt(
      {required this.receiptId,
      required this.tripId,
      required this.method,
      required this.number}) {
    _id(receiptId);
    _id(tripId);
    if (number.trim().isEmpty || number.trim() != number) {
      throw ArgumentError('Canonical receipt number required.');
    }
  }
  final String receiptId, tripId, number;
  final PaymentMethod method;
}

/// Trusted adapter/fake seam only. Same normal-user client, RLS, current role,
/// approval, assigned Driver and pinned SDK authority around every awaited read.
/// No production finance adapter exists: migrations 020/027 deny Driver payment
/// access. Do NOT wire Rider/Admin readers or invent an RPC to implement this.
abstract interface class DriverCompletionHandoffReader {
  DriverHandoffScope get currentScope;
  Future<DriverHandoffRead<DriverHandoffTrip>> readTrip(String tripId);
  Future<DriverHandoffRead<DriverHandoffPayment>> readPayment(String tripId);
  Future<DriverHandoffRead<DriverHandoffReceipt>> readReceipt(String tripId);
}

void _id(String value) {
  if (!isCanonicalTripId(value)) {
    throw ArgumentError('Canonical UUID required.');
  }
}

void _version(int value) {
  if (value < 1 || value > 2147483647) {
    throw ArgumentError('Canonical version required.');
  }
}
