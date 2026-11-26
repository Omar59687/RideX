import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';

/// Supplies a normal-user, RLS-authorized canonical Trip read.
///
/// The A04 financial response does not contain Booking, Rider, or Driver IDs.
/// This source must therefore remain the authority for those fields; an A04
/// row is never enough on its own to construct [RiderCheckoutTrip].
abstract interface class A04AuthorizedTripContextReader {
  Future<RiderCheckoutTrip?> readAuthorizedTrip({
    required String tripId,
    required String riderId,
  });
}

/// Injectable transport for the exact, read-only A04 result.
///
/// A Supabase implementation is intentionally not provided here. Production
/// wiring must wait until a Card-capable authorized Trip reader is approved.
abstract interface class A04FinancialReadTransport {
  Future<Object?> readFinancialRow({required String tripId});
}

enum A04ReceiptEvidence { linked, unverified }

/// Strictly parsed A04 v1 row. `linked` proves the server's exact receipt link
/// only; it does not imply provider settlement.
final class A04FinancialReadRecord {
  const A04FinancialReadRecord({
    required this.tripId,
    required this.tripVersion,
    required this.tripStatus,
    required this.paymentId,
    required this.paymentVersion,
    required this.paymentMethod,
    required this.amountFils,
    required this.currency,
    required this.cardStatus,
    required this.receiptEvidence,
    required this.receipt,
  });

  final String tripId;
  final int tripVersion;
  final DriverTripLifecycleStatus tripStatus;
  final String paymentId;
  final int paymentVersion;
  final PaymentMethod paymentMethod;
  final int amountFils;
  final String currency;
  final CardPaymentStatus cardStatus;
  final A04ReceiptEvidence receiptEvidence;
  final RiderVerifiedReceipt? receipt;

  CardPayment toCardPayment({required RiderCheckoutTrip context}) =>
      CardPayment(
        paymentId: paymentId,
        bookingRequestId: context.bookingRequestId,
        tripId: tripId,
        amountFils: amountFils,
        currency: currency,
        status: cardStatus,
        version: paymentVersion,
      );
}

/// Pure, fail-closed parser for the one-row result of
/// `user_trip_financial_read_v1`.
abstract final class A04FinancialReadParser {
  static const int _maxPostgresInteger = 2147483647;

  static A04FinancialReadRecord parse(Object? response) {
    if (response is! List || response.length != 1) {
      throw const FormatException('Expected exactly one A04 result row.');
    }
    final raw = response.single;
    if (raw is! Map) throw const FormatException('A04 row must be an object.');
    final row = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('A04 field names must be strings.');
      }
      row[key] = entry.value;
    }
    const requiredFields = {
      'contract_version',
      'trip_id',
      'trip_version',
      'trip_status',
      'payment_id',
      'payment_version',
      'payment_method',
      'amount_fils',
      'currency',
      'cash_status',
      'card_status',
      'receipt_evidence',
      'receipt_id',
      'receipt_number',
      'receipt_amount_fils',
      'receipt_currency',
      'receipt_issued_at',
    };
    if (!row.keys.toSet().containsAll(requiredFields)) {
      throw const FormatException('A04 row is missing contract fields.');
    }

    int integer(String key, {required int minimum}) {
      final value = row[key];
      if (value is! int || value < minimum || value > _maxPostgresInteger) {
        throw FormatException('Invalid A04 integer field: $key.');
      }
      return value;
    }

    String string(String key) {
      final value = row[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Invalid A04 text field: $key.');
      }
      return value;
    }

    T enumValue<T>(String key, T Function(String) parse) {
      try {
        return parse(string(key));
      } on ArgumentError {
        throw FormatException('Invalid A04 enum field: $key.');
      }
    }

    String uuid(String key) {
      final value = string(key);
      if (!isCanonicalTripId(value)) {
        throw FormatException('Invalid A04 UUID field: $key.');
      }
      return value;
    }

    final contractVersion = integer('contract_version', minimum: 1);
    if (contractVersion != 1) {
      throw const FormatException('Unsupported A04 contract version.');
    }
    final tripId = uuid('trip_id');
    final tripVersion = integer('trip_version', minimum: 1);
    final tripStatus = enumValue(
      'trip_status',
      DriverTripLifecycleStatus.fromBackendValue,
    );
    final paymentId = uuid('payment_id');
    final paymentVersion = integer('payment_version', minimum: 1);
    final paymentMethod = enumValue(
      'payment_method',
      PaymentMethod.fromBackendValue,
    );
    final amountFils = integer('amount_fils', minimum: 0);
    final currency = string('currency');
    if (currency != 'JOD' || paymentMethod != PaymentMethod.card) {
      throw const FormatException('A04 row is not a supported Card/JOD row.');
    }
    if (row['cash_status'] != null) {
      throw const FormatException('Card A04 row cannot include cash status.');
    }
    final cardStatus = enumValue(
      'card_status',
      CardPaymentStatus.fromBackendValue,
    );

    final evidenceValue = string('receipt_evidence');
    final evidence = switch (evidenceValue) {
      'linked' => A04ReceiptEvidence.linked,
      'unverified' => A04ReceiptEvidence.unverified,
      _ => throw const FormatException('Unknown A04 receipt evidence value.'),
    };

    final receiptFields = [
      row['receipt_id'],
      row['receipt_number'],
      row['receipt_amount_fils'],
      row['receipt_currency'],
      row['receipt_issued_at'],
    ];
    RiderVerifiedReceipt? receipt;
    if (evidence == A04ReceiptEvidence.unverified) {
      if (receiptFields.any((value) => value != null)) {
        throw const FormatException(
          'Unverified A04 receipt evidence must not carry receipt fields.',
        );
      }
    } else {
      final receiptId = uuid('receipt_id');
      final receiptNumber = string('receipt_number');
      final receiptAmount = integer('receipt_amount_fils', minimum: 0);
      final receiptCurrency = string('receipt_currency');
      final issuedAtText = string('receipt_issued_at');
      final issuedAt = DateTime.tryParse(issuedAtText);
      if (!RegExp(r'^RDX-[0-9]{8}-[A-Z0-9]{8}$').hasMatch(receiptNumber) ||
          receiptCurrency != 'JOD' ||
          receiptAmount != amountFils ||
          issuedAt == null ||
          !issuedAt.isUtc) {
        throw const FormatException('Invalid linked A04 receipt fields.');
      }
      receipt = RiderVerifiedReceipt(
        receiptId: receiptId,
        receiptNumber: receiptNumber,
        tripId: tripId,
        paymentId: paymentId,
        amountPaidFils: receiptAmount,
        currency: receiptCurrency,
        paymentMethod: paymentMethod,
        issuedAt: issuedAt,
      );
    }

    return A04FinancialReadRecord(
      tripId: tripId,
      tripVersion: tripVersion,
      tripStatus: tripStatus,
      paymentId: paymentId,
      paymentVersion: paymentVersion,
      paymentMethod: paymentMethod,
      amountFils: amountFils,
      currency: currency,
      cardStatus: cardStatus,
      receiptEvidence: evidence,
      receipt: receipt,
    );
  }
}

/// Feature-local adapter for deterministic A04 contract testing.
///
/// This class is not installed in application providers. It composes a
/// separately authenticated Trip context with the A04 financial row and
/// fences each result to the exact immutable [SessionState] instance.
final class A04RiderFinancialReadAdapter
    implements RiderCheckoutReader, RiderReceiptReader {
  A04RiderFinancialReadAdapter({
    required A04AuthorizedTripContextReader tripReader,
    required A04FinancialReadTransport transport,
    required SessionState Function() readSession,
  })  : _tripReader = tripReader,
        _transport = transport,
        _readSession = readSession;

  final A04AuthorizedTripContextReader _tripReader;
  final A04FinancialReadTransport _transport;
  final SessionState Function() _readSession;
  RiderCheckoutTrip? _verifiedTrip;
  SessionState? _verifiedSession;
  A04FinancialReadRecord? _lastRecord;
  String? _lastRecordTripId;
  SessionState? _lastRecordSession;
  int _readGeneration = 0;

  @override
  Future<RiderCheckoutTrip?> readTrip({required String tripId}) async {
    final generation = ++_readGeneration;
    _clearTripContext();
    _clearFinancialRecord();
    final owner = _readSession();
    final riderId = _authenticatedRiderId(owner);
    if (!isCanonicalTripId(tripId) || riderId == null) {
      _clearTripContext();
      return null;
    }
    try {
      final trip = await _tripReader.readAuthorizedTrip(
        tripId: tripId,
        riderId: riderId,
      );
      if (generation != _readGeneration || !identical(_readSession(), owner)) {
        _clearTripContext();
        throw const RiderCheckoutTripReadException(
          RiderCheckoutTripReadFailure.unauthorized,
        );
      }
      if (trip == null ||
          trip.tripId.toLowerCase() != tripId.toLowerCase() ||
          trip.riderId.toLowerCase() != riderId.toLowerCase()) {
        _clearTripContext();
        return null;
      }
      _verifiedTrip = trip;
      _verifiedSession = owner;
      return trip;
    } on RiderCheckoutTripReadException {
      rethrow;
    } on Object {
      _clearTripContext();
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unavailable,
      );
    }
  }

  @override
  Future<RiderCheckoutPaymentReadResult> readCardPayment({
    required String tripId,
  }) async {
    final generation = ++_readGeneration;
    _clearFinancialRecord();
    final owner = _readSession();
    final context = _verifiedTrip;
    if (_authenticatedRiderId(owner) == null ||
        !identical(owner, _verifiedSession) ||
        context == null ||
        context.tripId.toLowerCase() != tripId.toLowerCase() ||
        context.paymentMethod != PaymentMethod.card ||
        (!context.isEligibleAssignedCardTrip &&
            context.status != DriverTripLifecycleStatus.completed)) {
      throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unauthorized,
      );
    }
    try {
      final raw = await _transport.readFinancialRow(tripId: tripId);
      if (generation != _readGeneration || !identical(_readSession(), owner)) {
        _clearFinancialRecord();
        throw const RiderCheckoutPaymentReadException(
          RiderCheckoutPaymentReadFailure.unauthorized,
        );
      }
      if (raw is List && raw.isEmpty) {
        // A04 deliberately uses the same empty result for missing,
        // unauthorized, blocked, and inconsistent records.
        throw const RiderCheckoutPaymentReadException(
          RiderCheckoutPaymentReadFailure.unknownOutcome,
        );
      }
      final record = _parseFinancialRow(raw);
      if (record.tripId.toLowerCase() != context.tripId.toLowerCase() ||
          record.tripVersion != context.version ||
          record.tripStatus != context.status ||
          record.paymentMethod != context.paymentMethod ||
          record.amountFils != context.currentFareFils ||
          record.currency != context.currency) {
        throw const RiderCheckoutPaymentReadException(
          RiderCheckoutPaymentReadFailure.unknownOutcome,
        );
      }
      _lastRecord = record;
      _lastRecordTripId = tripId;
      _lastRecordSession = owner;
      return RiderCheckoutPaymentFound(
        record.toCardPayment(context: context),
      );
    } on RiderCheckoutPaymentReadException {
      rethrow;
    } on Object {
      // Includes zero rows, P0002, privacy masking, and transport failure.
      // None proves that the Trip or Payment is absent.
      _clearFinancialRecord();
      throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      );
    }
  }

  @override
  Future<RiderCanonicalReceiptReadResult> readReceipt({
    required String tripId,
    required String paymentId,
  }) async {
    final owner = _readSession();
    final record = _lastRecord;
    if (_authenticatedRiderId(owner) == null ||
        !identical(owner, _verifiedSession) ||
        !identical(owner, _lastRecordSession) ||
        _lastRecordTripId?.toLowerCase() != tripId.toLowerCase() ||
        record?.paymentId.toLowerCase() != paymentId.toLowerCase()) {
      throw const RiderReceiptOutcomeUnknownException();
    }
    if (record!.receiptEvidence == A04ReceiptEvidence.unverified) {
      throw const RiderReceiptOutcomeUnknownException();
    }
    final receipt = record.receipt;
    if (receipt == null ||
        !receipt.matches(tripId: tripId, paymentId: paymentId)) {
      throw const RiderReceiptOutcomeUnknownException();
    }
    return RiderCanonicalReceiptFound(receipt);
  }

  String? _authenticatedRiderId(SessionState session) {
    final user = session.user;
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        user == null ||
        user.isBlocked ||
        !isCanonicalTripId(user.id)) {
      return null;
    }
    return user.id;
  }

  A04FinancialReadRecord _parseFinancialRow(Object? raw) {
    try {
      return A04FinancialReadParser.parse(raw);
    } on Object {
      throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.invalidResponse,
      );
    }
  }

  void _clearTripContext() {
    _verifiedTrip = null;
    _verifiedSession = null;
    _clearFinancialRecord();
  }

  void _clearFinancialRecord() {
    _lastRecord = null;
    _lastRecordTripId = null;
    _lastRecordSession = null;
  }
}
