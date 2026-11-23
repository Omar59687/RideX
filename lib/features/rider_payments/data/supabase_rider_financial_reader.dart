import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/rider_payments/models/rider_checkout_state.dart';
import 'package:ridex/features/rider_payments/models/rider_receipt_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow, authenticated read transport used by the Rider payment feature.
/// Implementations cannot mutate financial state or create privileged clients.
abstract interface class RiderFinancialReadTransport {
  Object? get sessionIdentity;
  String? get authenticatedUserId;
  bool get sessionExpired;

  Future<Map<String, Object?>?> readProfile(String riderId);

  /// Uses the normal user's `trips_participant_select` RLS policy.
  Future<Map<String, Object?>?> readTrip({
    required String tripId,
    required String riderId,
  });

  /// Returns the documented v1 `user_trip_financial_read_v1` RPC payload.
  Future<Object?> readTripFinancial(String tripId);
}

/// Production adapter over the application's normal authenticated Supabase
/// client. It has no payment command, provider, service-role, or raw-card API.
final class SupabaseRiderFinancialReadTransport
    implements RiderFinancialReadTransport {
  SupabaseRiderFinancialReadTransport(this._client);

  final SupabaseClient _client;

  @override
  Object? get sessionIdentity => _client.auth.currentSession;

  @override
  String? get authenticatedUserId => _client.auth.currentUser?.id;

  @override
  bool get sessionExpired => _client.auth.currentSession?.isExpired ?? true;

  @override
  Future<Map<String, Object?>?> readProfile(String riderId) async {
    final row = await _client
        .from('users')
        .select('id,role,is_blocked')
        .eq('id', riderId)
        .maybeSingle();
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<Map<String, Object?>?> readTrip({
    required String tripId,
    required String riderId,
  }) async {
    final row = await _client
        .from('trips')
        .select(
          'id,booking_request_id,rider_id,driver_id,version,status,'
          'payment_method,current_fare_fils,currency',
        )
        .eq('id', tripId)
        .eq('rider_id', riderId)
        .maybeSingle();
    return row == null ? null : Map<String, Object?>.from(row);
  }

  @override
  Future<Object?> readTripFinancial(String tripId) => _client.rpc(
        'user_trip_financial_read_v1',
        params: {'target_trip_id': tripId},
      );
}

/// B05 adapter for A04's exact read-only contract.
///
/// A04 intentionally omits Rider/Booking/assigned Driver IDs, so those fields
/// come from a separate exact Trip SELECT with normal-client RLS. Both reads
/// are pinned to the same app Rider state and opaque SDK session, and the Trip
/// version/status/amount/currency must agree across the RPC response.
final class SupabaseRiderFinancialReader
    implements RiderCheckoutReader, RiderReceiptReader {
  SupabaseRiderFinancialReader({
    required RiderFinancialReadTransport transport,
    required SessionState Function() readSession,
  })  : _transport = transport,
        _readSession = readSession;

  factory SupabaseRiderFinancialReader.forClient({
    required SupabaseClient client,
    required SessionState Function() readSession,
  }) =>
      SupabaseRiderFinancialReader(
        transport: SupabaseRiderFinancialReadTransport(client),
        readSession: readSession,
      );

  final RiderFinancialReadTransport _transport;
  final SessionState Function() _readSession;
  _ObservedTrip? _observedTrip;
  _ObservedPayment? _observedPayment;

  @override
  Future<RiderCheckoutTrip?> readTrip({required String tripId}) async {
    final owner = _captureOwner(
      tripFailure: RiderCheckoutTripReadFailure.unauthorized,
    );
    if (!isCanonicalTripId(tripId)) {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.invalidResponse,
      );
    }
    try {
      await _verifyRiderProfile(owner);
      final row = await _readTripRow(owner, tripId);
      if (row == null) {
        _observedTrip = null;
        _observedPayment = null;
        await _verifyRiderProfile(owner);
        return null;
      }
      final trip = _parseTrip(row, requestedTripId: tripId, riderId: owner.riderId);
      await _verifyRiderProfile(owner);
      _requireCurrent(owner);
      _observedTrip = _ObservedTrip(
        owner,
        trip,
        _nonNegativeInt(row, 'current_fare_fils'),
      );
      _observedPayment = null;
      return trip;
    } on RiderCheckoutTripReadException {
      rethrow;
    } on Object catch (error) {
      throw _tripFailure(error);
    }
  }

  @override
  Future<RiderCheckoutPaymentReadResult> readCardPayment({
    required String tripId,
  }) async {
    final owner = _captureOwner(
      paymentFailure: RiderCheckoutPaymentReadFailure.unauthorized,
    );
    final observed = _observedTrip;
    if (!isCanonicalTripId(tripId) ||
        observed == null ||
        !_sameId(observed.trip.tripId, tripId) ||
        !_sameOwner(observed.owner, owner)) {
      throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.invalidResponse,
      );
    }
    try {
      await _verifyRiderProfile(owner);
      final beforeRow = await _readTripRow(owner, tripId);
      if (beforeRow == null) _paymentUnauthorized();
      final before = _parseTrip(
        beforeRow,
        requestedTripId: tripId,
        riderId: owner.riderId,
      );
      if (!_sameTrip(before, observed.trip) ||
          beforeRow['current_fare_fils'] != observed.currentFareFils) {
        _paymentUnknown();
      }

      final response = await _transport.readTripFinancial(tripId);
      _requireCurrent(owner, payment: true);
      final record = _parseFinancialResponse(response);
      if (record == null) _paymentUnknown();
      _validateFinancial(record, observed, requestedPaymentId: null);

      // Reread Trip after the RPC to fence a Trip update during the read.
      final afterRow = await _readTripRow(owner, tripId);
      if (afterRow == null) _paymentUnauthorized();
      final after = _parseTrip(
        afterRow,
        requestedTripId: tripId,
        riderId: owner.riderId,
      );
      if (!_sameTrip(after, before) ||
          afterRow['current_fare_fils'] != observed.currentFareFils) {
        _paymentUnknown();
      }
      await _verifyRiderProfile(owner);
      _requireCurrent(owner, payment: true);

      if (record.paymentMethod != PaymentMethod.card ||
          record.cardStatus == null ||
          record.cashStatus != null) {
        _paymentInvalid();
      }
      final payment = CardPayment(
        paymentId: record.paymentId,
        tripId: record.tripId,
        bookingRequestId: after.bookingRequestId,
        amountFils: record.amountFils,
        currency: record.currency,
        version: record.paymentVersion,
        status: record.cardStatus!,
      );
      final previous = _observedPayment;
      if (previous != null &&
          _sameOwner(previous.owner, owner) &&
          _sameId(previous.payment.paymentId!, payment.paymentId!) &&
          (payment.version < previous.payment.version ||
              (payment.version == previous.payment.version &&
                  payment != previous.payment))) {
        _paymentUnknown();
      }
      _observedPayment = _ObservedPayment(owner, payment);
      return RiderCheckoutPaymentFound(payment);
    } on RiderCheckoutPaymentReadException {
      rethrow;
    } on Object catch (error) {
      throw _paymentFailure(error);
    }
  }

  @override
  Future<RiderCanonicalReceiptReadResult> readReceipt({
    required String tripId,
    required String paymentId,
  }) async {
    final _Owner owner;
    try {
      owner = _captureOwner(
        paymentFailure: RiderCheckoutPaymentReadFailure.unauthorized,
      );
    } on RiderCheckoutPaymentReadException {
      throw const RiderReceiptUnavailableException();
    }
    final observedTrip = _observedTrip;
    final observedPayment = _observedPayment;
    if (!isCanonicalTripId(tripId) ||
        !isCanonicalTripId(paymentId) ||
        observedTrip == null ||
        observedPayment == null ||
        !_sameOwner(observedTrip.owner, owner) ||
        !_sameOwner(observedPayment.owner, owner) ||
        !_sameId(observedTrip.trip.tripId, tripId) ||
        !_sameId(observedPayment.payment.tripId!, tripId) ||
        !_sameId(observedPayment.payment.paymentId!, paymentId)) {
      throw const RiderReceiptOutcomeUnknownException();
    }
    try {
      await _verifyRiderProfile(owner);
      final beforeRow = await _readTripRow(owner, tripId);
      if (beforeRow == null) throw const RiderReceiptOutcomeUnknownException();
      final before = _parseTrip(
        beforeRow,
        requestedTripId: tripId,
        riderId: owner.riderId,
      );
      if (!_sameTrip(before, observedTrip.trip) ||
          beforeRow['current_fare_fils'] != observedTrip.currentFareFils) {
        throw const RiderReceiptOutcomeUnknownException();
      }

      final response = await _transport.readTripFinancial(tripId);
      _requireCurrent(owner, payment: true);
      final record = _parseFinancialResponse(response);
      if (record == null) throw const RiderReceiptOutcomeUnknownException();
      _validateFinancial(record, observedTrip, requestedPaymentId: paymentId);
      _validateSamePayment(record, observedPayment.payment);

      final afterRow = await _readTripRow(owner, tripId);
      if (afterRow == null) throw const RiderReceiptOutcomeUnknownException();
      final after = _parseTrip(
        afterRow,
        requestedTripId: tripId,
        riderId: owner.riderId,
      );
      if (!_sameTrip(after, before) ||
          afterRow['current_fare_fils'] != observedTrip.currentFareFils) {
        throw const RiderReceiptOutcomeUnknownException();
      }
      await _verifyRiderProfile(owner);
      _requireCurrent(owner, payment: true);

      if (record.receiptEvidence == 'unverified') {
        throw const RiderReceiptOutcomeUnknownException();
      }
      if (record.receiptEvidence != 'linked' ||
          record.receiptId == null ||
          record.receiptNumber == null ||
          record.receiptAmountFils == null ||
          record.receiptCurrency == null ||
          record.receiptIssuedAt == null ||
          record.receiptAmountFils != record.amountFils ||
          record.receiptCurrency != 'JOD' ||
          record.currency != 'JOD') {
        throw const RiderReceiptOutcomeUnknownException();
      }

      // A04 returns the canonical Payment ID, not a receipt_payment_id column.
      // `linked` is accepted only because the documented SQL contract joins
      // Receipt on exact Trip, Payment, FareQuote, method and currency identity.
      final receipt = RiderVerifiedReceipt(
        receiptId: record.receiptId!,
        receiptNumber: record.receiptNumber!,
        tripId: record.tripId,
        paymentId: record.paymentId,
        amountPaidFils: record.receiptAmountFils!,
        currency: record.receiptCurrency!,
        paymentMethod: record.paymentMethod,
        issuedAt: record.receiptIssuedAt!,
      );
      if (receipt.paymentId.toLowerCase() != paymentId.toLowerCase()) {
        throw const RiderReceiptOutcomeUnknownException();
      }
      return RiderCanonicalReceiptFound(receipt);
    } on RiderReceiptOutcomeUnknownException {
      rethrow;
    } on RiderCheckoutTripReadException {
      throw const RiderReceiptUnavailableException();
    } on RiderCheckoutPaymentReadException catch (error) {
      if (error.failure == RiderCheckoutPaymentReadFailure.unauthorized) {
        throw const RiderReceiptUnavailableException();
      }
      throw const RiderReceiptOutcomeUnknownException();
    } on Object catch (error) {
      if (_isUnauthorizedError(error)) {
        throw const RiderReceiptUnavailableException();
      }
      throw const RiderReceiptOutcomeUnknownException();
    }
  }

  _Owner _captureOwner({
    RiderCheckoutTripReadFailure? tripFailure,
    RiderCheckoutPaymentReadFailure? paymentFailure,
  }) {
    final session = _readSession();
    final user = session.user;
    final sdkSession = _transport.sessionIdentity;
    final riderId = user?.id;
    final valid = session.status == SessionStatus.authenticated &&
        session.role == RideRole.rider &&
        user != null &&
        !user.isBlocked &&
        riderId != null &&
        isCanonicalTripId(riderId) &&
        _sameId(_transport.authenticatedUserId ?? '', riderId) &&
        sdkSession != null &&
        !_transport.sessionExpired;
    if (!valid) {
      if (tripFailure != null) {
        throw RiderCheckoutTripReadException(tripFailure);
      }
      throw RiderCheckoutPaymentReadException(
        paymentFailure ?? RiderCheckoutPaymentReadFailure.unauthorized,
      );
    }
    return _Owner(session, riderId, sdkSession);
  }

  void _requireCurrent(_Owner owner, {bool payment = false}) {
    final currentSession = _readSession();
    if (!identical(currentSession, owner.appSession) ||
        currentSession.status != SessionStatus.authenticated ||
        currentSession.role != RideRole.rider ||
        currentSession.user?.isBlocked != false ||
        !_sameId(currentSession.user?.id ?? '', owner.riderId) ||
        !identical(_transport.sessionIdentity, owner.sdkSession) ||
        !_sameId(_transport.authenticatedUserId ?? '', owner.riderId) ||
        _transport.sessionExpired) {
      if (payment) _paymentUnauthorized();
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    }
  }

  Future<void> _verifyRiderProfile(_Owner owner) async {
    _requireCurrent(owner);
    final profile = await _transport.readProfile(owner.riderId);
    _requireCurrent(owner);
    if (profile == null ||
        !_sameId(_string(profile, 'id'), owner.riderId) ||
        profile['role'] != 'rider' ||
        profile['is_blocked'] != false) {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    }
  }

  Future<Map<String, Object?>?> _readTripRow(
    _Owner owner,
    String tripId,
  ) async {
    _requireCurrent(owner);
    final row = await _transport.readTrip(tripId: tripId, riderId: owner.riderId);
    _requireCurrent(owner);
    return row;
  }

  RiderCheckoutTrip _parseTrip(
    Map<String, Object?> row, {
    required String requestedTripId,
    required String riderId,
  }) {
    final tripId = _uuid(row, 'id');
    final bookingId = _uuid(row, 'booking_request_id');
    final rowRiderId = _uuid(row, 'rider_id');
    final driverId = _uuid(row, 'driver_id');
    final version = _positiveInt(row, 'version');
    _nonNegativeInt(row, 'current_fare_fils');
    final currency = _string(row, 'currency');
    final statusText = _string(row, 'status');
    final methodText = _string(row, 'payment_method');
    if (!_sameId(tripId, requestedTripId) || !_sameId(rowRiderId, riderId)) {
      throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    }
    if (currency != 'JOD') _tripInvalid();
    try {
      return RiderCheckoutTrip(
        tripId: tripId,
        bookingRequestId: bookingId,
        riderId: rowRiderId,
        driverId: driverId,
        version: version,
        status: DriverTripLifecycleStatus.fromBackendValue(statusText),
        paymentMethod: PaymentMethod.fromBackendValue(methodText),
      );
    } on RiderCheckoutTripReadException {
      rethrow;
    } on Object {
      _tripInvalid();
    }
  }

  _FinancialRecord? _parseFinancialResponse(Object? response) {
    if (response is! List) _paymentInvalid();
    if (response.isEmpty) return null;
    if (response.length != 1 || response.single is! Map) _paymentInvalid();
    final row = Map<String, Object?>.from(response.single as Map);
    final contractVersion = row['contract_version'];
    if (contractVersion != 1) _paymentInvalid();
    final tripId = _uuid(row, 'trip_id');
    final tripVersion = _positiveInt(row, 'trip_version');
    final tripStatus = DriverTripLifecycleStatus.fromBackendValue(
      _string(row, 'trip_status'),
    );
    final paymentId = _uuid(row, 'payment_id');
    final paymentVersion = _positiveInt(row, 'payment_version');
    final paymentMethod = PaymentMethod.fromBackendValue(
      _string(row, 'payment_method'),
    );
    final amountFils = _nonNegativeInt(row, 'amount_fils');
    final currency = _string(row, 'currency');
    if (currency != 'JOD') _paymentInvalid();

    final cashValue = row['cash_status'];
    final cardValue = row['card_status'];
    CashPaymentStatus? cashStatus;
    CardPaymentStatus? cardStatus;
    if (cashValue != null) {
      if (cashValue is! String) _paymentInvalid();
      cashStatus = CashPaymentStatus.fromBackendValue(cashValue);
    }
    if (cardValue != null) {
      if (cardValue is! String) _paymentInvalid();
      cardStatus = CardPaymentStatus.fromBackendValue(cardValue);
    }

    final receiptEvidence = _string(row, 'receipt_evidence');
    if (receiptEvidence != 'linked' && receiptEvidence != 'unverified') {
      _paymentInvalid();
    }
    final receiptId = _nullableUuid(row, 'receipt_id');
    final receiptNumber = _nullableString(row, 'receipt_number');
    final receiptAmount = _nullableNonNegativeInt(row, 'receipt_amount_fils');
    final receiptCurrency = _nullableString(row, 'receipt_currency');
    final issuedAt = _nullableUtcDate(row, 'receipt_issued_at');
    return _FinancialRecord(
      tripId: tripId,
      tripVersion: tripVersion,
      tripStatus: tripStatus,
      paymentId: paymentId,
      paymentVersion: paymentVersion,
      paymentMethod: paymentMethod,
      amountFils: amountFils,
      currency: currency,
      cashStatus: cashStatus,
      cardStatus: cardStatus,
      receiptEvidence: receiptEvidence,
      receiptId: receiptId,
      receiptNumber: receiptNumber,
      receiptAmountFils: receiptAmount,
      receiptCurrency: receiptCurrency,
      receiptIssuedAt: issuedAt,
    );
  }

  void _validateFinancial(
    _FinancialRecord record,
    _ObservedTrip observed, {
    required String? requestedPaymentId,
  }) {
    if (!_sameId(record.tripId, observed.trip.tripId) ||
        record.tripVersion != observed.trip.version ||
        record.tripStatus != observed.trip.status ||
        record.paymentMethod != observed.trip.paymentMethod ||
        record.amountFils != observed.currentFareFils ||
        record.currency != 'JOD' ||
        (requestedPaymentId != null &&
            !_sameId(record.paymentId, requestedPaymentId))) {
      _paymentUnknown();
    }
  }

  void _validateSamePayment(_FinancialRecord record, CardPayment payment) {
    if (!_sameId(record.paymentId, payment.paymentId ?? '') ||
        !_sameId(record.tripId, payment.tripId ?? '') ||
        record.paymentVersion != payment.version ||
        record.amountFils != payment.amountFils ||
        record.currency != payment.currency ||
        record.cardStatus != payment.status) {
      throw const RiderReceiptOutcomeUnknownException();
    }
  }

  RiderCheckoutTripReadException _tripFailure(Object error) {
    if (error is RiderCheckoutTripReadException) return error;
    if (_isUnauthorizedError(error)) {
      return const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.unauthorized,
      );
    }
    if (error is FormatException || error is TypeError || error is ArgumentError) {
      return const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.invalidResponse,
      );
    }
    return const RiderCheckoutTripReadException(
      RiderCheckoutTripReadFailure.unavailable,
    );
  }

  RiderCheckoutPaymentReadException _paymentFailure(Object error) {
    if (error is RiderCheckoutPaymentReadException) return error;
    if (error is RiderCheckoutTripReadException) {
      return RiderCheckoutPaymentReadException(
        switch (error.failure) {
          RiderCheckoutTripReadFailure.unauthorized =>
            RiderCheckoutPaymentReadFailure.unauthorized,
          RiderCheckoutTripReadFailure.invalidResponse =>
            RiderCheckoutPaymentReadFailure.invalidResponse,
          RiderCheckoutTripReadFailure.unavailable =>
            RiderCheckoutPaymentReadFailure.unavailable,
        },
      );
    }
    if (_isUnauthorizedError(error)) {
      return const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unauthorized,
      );
    }
    if (error is FormatException || error is TypeError || error is ArgumentError) {
      return const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.invalidResponse,
      );
    }
    return const RiderCheckoutPaymentReadException(
      RiderCheckoutPaymentReadFailure.unavailable,
    );
  }

  bool _isUnauthorizedError(Object error) =>
      error is AuthException ||
      (error is PostgrestException &&
          (error.code == '42501' ||
              error.code == '401' ||
              error.code == '403' ||
              error.code == 'PGRST301' ||
              error.code == 'PGRST302' ||
              error.code == 'PGRST303'));

  bool _sameOwner(_Owner a, _Owner b) =>
      identical(a.appSession, b.appSession) &&
      _sameId(a.riderId, b.riderId) &&
      identical(a.sdkSession, b.sdkSession);

  bool _sameTrip(RiderCheckoutTrip a, RiderCheckoutTrip b) =>
      _sameId(a.tripId, b.tripId) &&
      _sameId(a.bookingRequestId, b.bookingRequestId) &&
      _sameId(a.riderId, b.riderId) &&
      _sameId(a.driverId, b.driverId) &&
      a.version == b.version &&
      a.status == b.status &&
      a.paymentMethod == b.paymentMethod;

  static String _uuid(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! String || !isCanonicalTripId(value)) {
      throw const FormatException('Invalid canonical UUID.');
    }
    return value;
  }

  static String? _nullableUuid(Map<String, Object?> row, String key) {
    if (!row.containsKey(key)) throw const FormatException('Missing field.');
    final value = row[key];
    if (value == null) return null;
    if (value is! String || !isCanonicalTripId(value)) {
      throw const FormatException('Invalid optional UUID.');
    }
    return value;
  }

  static int _positiveInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! int || value < 1 || value > 2147483647) {
      throw const FormatException('Invalid positive integer.');
    }
    return value;
  }

  static int _nonNegativeInt(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! int || value < 0 || value > 2147483647) {
      throw const FormatException('Invalid integer fils value.');
    }
    return value;
  }

  static int? _nullableNonNegativeInt(Map<String, Object?> row, String key) {
    if (!row.containsKey(key)) throw const FormatException('Missing field.');
    final value = row[key];
    if (value == null) return null;
    if (value is! int || value < 0 || value > 2147483647) {
      throw const FormatException('Invalid optional integer.');
    }
    return value;
  }

  static String _string(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw const FormatException('Invalid canonical string.');
    }
    return value;
  }

  static String? _nullableString(Map<String, Object?> row, String key) {
    if (!row.containsKey(key)) throw const FormatException('Missing field.');
    final value = row[key];
    if (value == null) return null;
    if (value is! String || value.trim() != value) {
      throw const FormatException('Invalid optional string.');
    }
    return value;
  }

  static DateTime? _nullableUtcDate(Map<String, Object?> row, String key) {
    if (!row.containsKey(key)) throw const FormatException('Missing field.');
    final value = row[key];
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid timestamp.');
    return DateTime.parse(value).toUtc();
  }

  Never _tripInvalid() => throw const RiderCheckoutTripReadException(
        RiderCheckoutTripReadFailure.invalidResponse,
      );

  Never _paymentInvalid() => throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.invalidResponse,
      );

  Never _paymentUnknown() => throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unknownOutcome,
      );

  Never _paymentUnauthorized() => throw const RiderCheckoutPaymentReadException(
        RiderCheckoutPaymentReadFailure.unauthorized,
      );
}

final class _Owner {
  const _Owner(this.appSession, this.riderId, this.sdkSession);
  final SessionState appSession;
  final String riderId;
  final Object sdkSession;
}

final class _ObservedTrip {
  const _ObservedTrip(this.owner, this.trip, this.currentFareFils);
  final _Owner owner;
  final RiderCheckoutTrip trip;
  final int currentFareFils;
}

final class _ObservedPayment {
  const _ObservedPayment(this.owner, this.payment);
  final _Owner owner;
  final CardPayment payment;
}

final class _FinancialRecord {
  const _FinancialRecord({
    required this.tripId,
    required this.tripVersion,
    required this.tripStatus,
    required this.paymentId,
    required this.paymentVersion,
    required this.paymentMethod,
    required this.amountFils,
    required this.currency,
    required this.cashStatus,
    required this.cardStatus,
    required this.receiptEvidence,
    required this.receiptId,
    required this.receiptNumber,
    required this.receiptAmountFils,
    required this.receiptCurrency,
    required this.receiptIssuedAt,
  });

  final String tripId;
  final int tripVersion;
  final DriverTripLifecycleStatus tripStatus;
  final String paymentId;
  final int paymentVersion;
  final PaymentMethod paymentMethod;
  final int amountFils;
  final String currency;
  final CashPaymentStatus? cashStatus;
  final CardPaymentStatus? cardStatus;
  final String receiptEvidence;
  final String? receiptId;
  final String? receiptNumber;
  final int? receiptAmountFils;
  final String? receiptCurrency;
  final DateTime? receiptIssuedAt;
}

bool _sameId(String first, String second) =>
    first.toLowerCase() == second.toLowerCase();
