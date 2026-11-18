import 'package:flutter/material.dart';
import 'package:ridex/features/history/data/rider_exact_trip_detail.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// Feature-local exact-ID details. Intentionally not wired into global router.
/// Payment/receipt are never inferred from a completed Trip.
class CanonicalRiderTripDetail extends StatefulWidget {
  const CanonicalRiderTripDetail({
    required this.reader,
    required this.riderId,
    required this.tripId,
    required this.isCurrentRider,
    super.key,
  });

  final RiderExactTripDetailReader reader;
  final String riderId;
  final String tripId;
  final bool Function() isCurrentRider;

  @override
  State<CanonicalRiderTripDetail> createState() =>
      _CanonicalRiderTripDetailState();
}

class _CanonicalRiderTripDetailState extends State<CanonicalRiderTripDetail> {
  int _generation = 0;
  bool _loading = false;
  bool _error = false;
  RiderExactTripDetail? _detail;
  bool _loaded = false;

  bool get _current => widget.isCurrentRider();

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant CanonicalRiderTripDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.riderId != widget.riderId ||
        oldWidget.tripId != widget.tripId ||
        !identical(oldWidget.reader, widget.reader) ||
        !identical(oldWidget.isCurrentRider, widget.isCurrentRider)) {
      _generation++;
      _detail = null;
      _loaded = false;
      _error = false;
      _loading = false;
      _read();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _read() async {
    final generation = ++_generation;
    if (!_current) {
      setState(() {
        _detail = null;
        _loaded = true;
        _loading = false;
        _error = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
      _detail = null;
    });
    try {
      final detail = await widget.reader.readExact(
        riderId: widget.riderId,
        tripId: widget.tripId,
      );
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _loaded = true;
      });
    } on Object {
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        _detail = null;
        _loading = false;
        _loaded = true;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) {
      return const Center(
        child: Text('Trip access could not be verified.'),
      );
    }
    if (_loading || !_loaded) {
      return const Center(
        child: CircularProgressIndicator(key: Key('exact-trip-loading')),
      );
    }
    if (_error) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Trip details could not be loaded.'),
          TextButton(
            key: const Key('exact-trip-retry'),
            onPressed: _read,
            child: const Text('Retry'),
          ),
        ]),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return const Center(child: Text('Trip not available.'));
    }
    final trip = detail.trip;
    final evidence = detail.financial;
    return ListView(
      key: const Key('exact-trip-details'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Trip status: ${trip.status.backendValue}'),
        const SizedBox(height: 8),
        Text('Pickup: ${trip.pickupLabel}'),
        Text('Destination: ${trip.destinationLabel}'),
        Text('Trip date: ${trip.createdAt.toUtc().toIso8601String()}'),
        Text('Locked fare: ${trip.currency} ${(trip.lockedFareFils / 1000).toStringAsFixed(3)}'),
        const Divider(),
        Text('Payment: ${_paymentLabel(evidence?.payment)}'),
        Text('Receipt: ${_receiptLabel(evidence?.receipt)}'),
        const SizedBox(height: 16),
        const Text('Payment and receipt status require separate authorized backend evidence.'),
      ],
    );
  }
}

String _paymentLabel(RiderDetailPaymentState? state) => switch (state) {
      null || RiderDetailPaymentState.unavailable => 'Not verified',
      RiderDetailPaymentState.cashSelectedUnpaid => 'Cash selected — unpaid',
      RiderDetailPaymentState.cashReportedPaidUnverified =>
        'Cash reported paid — verification pending',
      RiderDetailPaymentState.cardPending => 'Card pending',
      RiderDetailPaymentState.cardUnknown => 'Card status unknown',
      RiderDetailPaymentState.cardReportedCapturedUnverified =>
        'Card capture reported — verification pending',
      RiderDetailPaymentState.cancelled => 'Cancelled',
    };

String _receiptLabel(RiderDetailReceiptState? state) => switch (state) {
      null || RiderDetailReceiptState.unavailable =>
        'Unavailable (not proof of non-issuance)',
      RiderDetailReceiptState.unverified => 'Unverified',
      RiderDetailReceiptState.reportedIssuedUnverified =>
        'Reported issued — verification pending',
    };
