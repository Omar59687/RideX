import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import '../domain/driver_completion_handoff.dart';

/// Revocable typed handoff for Omar/Sanad. Not a persisted financial authority.
/// Consumers must honor state getters; a captured event expires on refresh/auth.
final class DriverCompletionHandoffEvent {
  DriverCompletionHandoffEvent._(this._controller, this._revision);
  final DriverCompletionHandoffController _controller;
  final int _revision;
  bool get _current =>
      _controller._current && _controller._revision == _revision;
  DriverHandoffScope? get scope => _current ? _controller._owner : null;
  DriverHandoffReadState get tripState =>
      _current ? _controller._tripState : DriverHandoffReadState.unauthorized;
  DriverHandoffReadState get paymentState => _current
      ? _controller._paymentState
      : DriverHandoffReadState.unauthorized;
  DriverHandoffReadState get receiptState => _current
      ? _controller._receiptState
      : DriverHandoffReadState.unauthorized;
  DriverHandoffTrip? get trip => _current ? _controller._trip : null;
  DriverHandoffPayment? get payment => _current ? _controller._payment : null;
  DriverHandoffReceipt? get receipt => _current ? _controller._receipt : null;
  bool get tripCompleted =>
      tripState == DriverHandoffReadState.verified &&
      trip?.status == DriverTripLifecycleStatus.completed;
}

/// Read-only evidence presentation, not another completion/journal owner.
/// This class has no financial command, SDK, key generation or persistence seam.
final class DriverCompletionHandoffController extends ChangeNotifier {
  DriverCompletionHandoffController(
      {required this.tripId,
      required this.reader,
      required this.connected,
      required Listenable authorityInvalidations})
      : _owner = reader.currentScope,
        _invalidations = authorityInvalidations {
    if (!isCanonicalTripId(tripId)) {
      throw ArgumentError('Canonical Trip locator required.');
    }
    connected.addListener(_connectionChanged);
    _invalidations.addListener(retire);
  }
  final String tripId;
  final DriverCompletionHandoffReader reader;
  final ValueListenable<bool> connected;
  final DriverHandoffScope _owner;
  final Listenable _invalidations;
  bool _disposed = false, _retired = false;
  int _generation = 0, _revision = 0;
  Future<void>? _pending;
  DriverHandoffTrip? _trip, _lastTrip;
  DriverHandoffPayment? _payment, _lastPayment;
  DriverHandoffReceipt? _receipt, _lastReceipt;
  DriverHandoffReadState _tripState = DriverHandoffReadState.notChecked;
  DriverHandoffReadState _paymentState = DriverHandoffReadState.notChecked;
  DriverHandoffReadState _receiptState = DriverHandoffReadState.notChecked;

  bool get _current {
    try {
      if (!_disposed &&
          !_retired &&
          _owner.sameAuthority(reader.currentScope)) {
        return true;
      }
    } on Object {/* Fail closed without exposing raw transport errors. */}
    _retired = true;
    return false;
  }

  bool get canRefresh => _current && connected.value && _pending == null;
  DriverCompletionHandoffEvent get event =>
      DriverCompletionHandoffEvent._(this, _revision);
  void _clear(DriverHandoffReadState state) {
    _trip = null;
    _payment = null;
    _receipt = null;
    _tripState = state;
    _paymentState = state;
    _receiptState = state;
  }

  void _publish() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  bool _owns(int generation) =>
      generation == _generation && _current && connected.value;
  void _connectionChanged() {
    if (!_current) {
      retire();
      return;
    }
    if (!connected.value) {
      _generation++;
      _pending = null;
      _clear(DriverHandoffReadState.unknown);
      _publish();
    } else {
      unawaited(refresh());
    }
  }

  void retire({bool deferNotification = false}) {
    if (_disposed) return;
    _retired = true;
    _generation++;
    _pending = null;
    _clear(DriverHandoffReadState.unauthorized);
    if (deferNotification) {
      _revision++;
      scheduleMicrotask(_publish);
    } else {
      _publish();
    }
  }

  Future<void> refresh() {
    if (!_current) {
      retire();
      return Future<void>.value();
    }
    if (!connected.value) {
      _connectionChanged();
      return Future<void>.value();
    }
    final pending = _pending;
    if (pending != null) return pending;
    final done = Completer<void>();
    final future = done.future;
    _pending = future;
    unawaited(_run(++_generation).whenComplete(() {
      if (identical(_pending, future)) {
        _pending = null;
        _publish();
      }
      done.complete();
    }));
    return future;
  }

  bool _scope<T>(DriverHandoffRead<T> result) =>
      result.scope.sameAuthority(_owner) && _same(result.tripId, tripId);

  Future<void> _run(int generation) async {
    _clear(DriverHandoffReadState.loading);
    _publish();
    if (!_owns(generation)) return;
    try {
      final read = await reader.readTrip(tripId);
      if (!_owns(generation)) return;
      if (!_scope(read)) {
        _tripState = DriverHandoffReadState.error;
        _publish();
        return;
      }
      if (read.state == DriverHandoffReadState.unauthorized) {
        retire();
        return;
      }
      _tripState = read.state;
      final trip = read.evidence;
      if (trip != null) {
        final prior = _lastTrip;
        if (!_same(trip.tripId, tripId) ||
            !_same(trip.driverId, _owner.owner.driverId!) ||
            (prior != null &&
                (trip.version < prior.version ||
                    trip.method != prior.method ||
                    (trip.version == prior.version &&
                        trip.status != prior.status) ||
                    (_terminal(prior.status) &&
                        trip.status != prior.status)))) {
          _tripState = DriverHandoffReadState.error;
          _publish();
          return;
        }
        _trip = trip;
        _lastTrip = trip;
      }
      _paymentState = DriverHandoffReadState.notChecked;
      _receiptState = DriverHandoffReadState.notChecked;
      _publish();
      if (!_owns(generation) || !event.tripCompleted) return;
      try {
        final payment = await reader.readPayment(tripId);
        if (!_owns(generation)) return;
        _paymentState =
            _scope(payment) ? payment.state : DriverHandoffReadState.error;
        if (_scope(payment) && payment.evidence != null) {
          final value = payment.evidence!;
          if (!_validPayment(value)) {
            _paymentState = DriverHandoffReadState.error;
          } else {
            _payment = value;
            _lastPayment = value;
          }
        }
      } on Object {
        if (!_owns(generation)) return;
        _paymentState = DriverHandoffReadState.unknown;
      }
      _publish();
      if (!_owns(generation)) return;
      try {
        final receipt = await reader.readReceipt(tripId);
        if (!_owns(generation)) return;
        _receiptState =
            _scope(receipt) ? receipt.state : DriverHandoffReadState.error;
        if (_scope(receipt) && receipt.evidence != null) {
          final value = receipt.evidence!, prior = _lastReceipt;
          if (!_same(value.tripId, tripId) ||
              value.method != _trip!.method ||
              (prior != null &&
                  (!_same(value.receiptId, prior.receiptId) ||
                      value.number != prior.number))) {
            _receiptState = DriverHandoffReadState.error;
          } else {
            _receipt = value;
            _lastReceipt = value;
          }
        }
      } on Object {
        if (!_owns(generation)) return;
        _receiptState = DriverHandoffReadState.unknown;
      }
      _publish();
    } on Object {
      if (!_owns(generation)) return;
      _clear(DriverHandoffReadState.unknown);
      _publish();
    }
  }

  bool _validPayment(DriverHandoffPayment value) {
    if (!_same(value.tripId, tripId) || value.method != _trip!.method) {
      return false;
    }
    final prior = _lastPayment;
    if (prior == null) return true;
    if (!_same(value.paymentId, prior.paymentId) ||
        value.version < prior.version) {
      return false;
    }
    final sameStatus = _status(value) == _status(prior);
    if (value.version == prior.version) return sameStatus;
    return switch (prior) {
      DriverHandoffCashPayment(:final status)
          when status != CashPaymentStatus.cashSelected =>
        sameStatus,
      DriverHandoffCardPayment(:final status)
          when status == CardPaymentStatus.paymentCancelled ||
              status == CardPaymentStatus.refunded =>
        sameStatus,
      DriverHandoffCardPayment(
        status: CardPaymentStatus.cardPaymentSucceeded
      ) =>
        value is DriverHandoffCardPayment &&
            {
              CardPaymentStatus.cardPaymentSucceeded,
              CardPaymentStatus.refundPending,
              CardPaymentStatus.refunded
            }.contains(value.status),
      DriverHandoffCardPayment(status: CardPaymentStatus.refundPending) =>
        value is DriverHandoffCardPayment &&
            {CardPaymentStatus.refundPending, CardPaymentStatus.refunded}
                .contains(value.status),
      _ => true,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _retired = true;
    _generation++;
    _clear(DriverHandoffReadState.unauthorized);
    connected.removeListener(_connectionChanged);
    _invalidations.removeListener(retire);
    super.dispose();
  }
}

bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();
Object _status(DriverHandoffPayment value) => switch (value) {
      DriverHandoffCashPayment(:final status) => status,
      DriverHandoffCardPayment(:final status) => status,
    };
bool _terminal(DriverTripLifecycleStatus status) => switch (status) {
      DriverTripLifecycleStatus.completed ||
      DriverTripLifecycleStatus.cancelledByRider ||
      DriverTripLifecycleStatus.cancelledByDriver ||
      DriverTripLifecycleStatus.cancelledByAdmin ||
      DriverTripLifecycleStatus.failed =>
        true,
      _ => false,
    };
