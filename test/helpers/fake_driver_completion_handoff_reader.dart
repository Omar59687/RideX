import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_authority.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/features/driver_flow/domain/driver_completion_handoff.dart';
import 'fake_canonical_driver_port.dart' as f;

const handoffPaymentId = 'b8000000-0000-0000-0000-000000000001';
const handoffReceiptId = 'b8000000-0000-0000-0000-000000000002';
DriverHandoffScope handoffScope(
        {String? driver = f.driverId,
        int epoch = 1,
        bool approved = true,
        bool valid = true,
        Object? session}) =>
    DriverHandoffScope(
        owner: DriverAuthorityOwner(
            driverId: driver,
            backend: f.backend,
            epoch: epoch,
            hasValidSession: valid),
        sdkSession: session ?? Object(),
        isApprovedDriver: approved);

/// Test-only backend-shaped, read-only seam. No endpoint/financial mutation API.
class FakeDriverCompletionHandoffReader
    implements DriverCompletionHandoffReader {
  @override
  DriverHandoffScope currentScope = handoffScope();
  DriverHandoffScope? replyScope;
  PaymentMethod method = PaymentMethod.cash;
  DriverTripLifecycleStatus status = DriverTripLifecycleStatus.completed;
  int tripVersion = 5, paymentVersion = 7;
  CashPaymentStatus cashStatus = CashPaymentStatus.cashSelected;
  CardPaymentStatus cardStatus = CardPaymentStatus.cardPaymentAuthorized;
  DriverHandoffReadState tripState = DriverHandoffReadState.verified;
  DriverHandoffReadState paymentState = DriverHandoffReadState.verified;
  DriverHandoffReadState receiptState = DriverHandoffReadState.missing;
  DriverHandoffTrip? tripOverride;
  DriverHandoffPayment? paymentOverride;
  DriverHandoffReceipt? receiptOverride;
  Future<DriverHandoffRead<DriverHandoffTrip>> Function()? tripHandler;
  Future<DriverHandoffRead<DriverHandoffPayment>> Function()? paymentHandler;
  Future<DriverHandoffRead<DriverHandoffReceipt>> Function()? receiptHandler;
  final calls = <String>[];
  DriverHandoffRead<T> reply<T>(DriverHandoffReadState state, [T? evidence]) =>
      DriverHandoffRead(
          scope: replyScope ?? currentScope,
          tripId: f.tripId,
          state: state,
          evidence: state == DriverHandoffReadState.verified ? evidence : null);
  @override
  Future<DriverHandoffRead<DriverHandoffTrip>> readTrip(String tripId) async {
    calls.add('trip:$tripId');
    if (tripHandler != null) return tripHandler!();
    return reply(
        tripState,
        tripOverride ??
            DriverHandoffTrip(
                tripId: f.tripId,
                driverId: f.driverId,
                status: status,
                version: tripVersion,
                method: method));
  }

  DriverHandoffPayment payment() =>
      paymentOverride ??
      (method == PaymentMethod.cash
          ? DriverHandoffCashPayment(
              paymentId: handoffPaymentId,
              tripId: f.tripId,
              version: paymentVersion,
              status: cashStatus)
          : DriverHandoffCardPayment(
              paymentId: handoffPaymentId,
              tripId: f.tripId,
              version: paymentVersion,
              status: cardStatus));
  @override
  Future<DriverHandoffRead<DriverHandoffPayment>> readPayment(
      String tripId) async {
    calls.add('payment:$tripId');
    if (paymentHandler != null) return paymentHandler!();
    return reply(paymentState, payment());
  }

  @override
  Future<DriverHandoffRead<DriverHandoffReceipt>> readReceipt(
      String tripId) async {
    calls.add('receipt:$tripId');
    if (receiptHandler != null) return receiptHandler!();
    return reply(
        receiptState,
        receiptOverride ??
            DriverHandoffReceipt(
                receiptId: handoffReceiptId,
                tripId: f.tripId,
                method: method,
                number: 'R-005'));
  }
}
