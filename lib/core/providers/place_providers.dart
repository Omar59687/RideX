import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/models/place_selection_state.dart';
import 'package:ridex/core/providers/location_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

class PlaceSelectionController
    extends AutoDisposeFamilyNotifier<PlaceSelectionState, LocationEndpoint> {
  Timer? _debounce;
  int _generation = 0;
  late String _sessionToken;
  late LocationEndpoint _endpoint;
  String? _lastRequestedQuery;

  @override
  PlaceSelectionState build(LocationEndpoint arg) {
    _endpoint = arg;
    _sessionToken = _newSessionToken();
    ref.onDispose(() {
      _debounce?.cancel();
      _generation++;
    });
    final draft = ref.read(bookingControllerProvider);
    return PlaceSelectionState(
      selected:
          arg == LocationEndpoint.pickup ? draft.pickup : draft.destination,
    );
  }

  void search(String value) {
    final query = value.trim();
    _debounce?.cancel();
    final generation = ++_generation;
    if (query.length < 3) {
      _lastRequestedQuery = null;
      if (query.isEmpty) _sessionToken = _newSessionToken();
      state = PlaceSelectionState(
        query: query,
        selected: state.selected,
      );
      return;
    }
    if (query == _lastRequestedQuery &&
        (state.status == PlaceSearchStatus.loading ||
            state.status == PlaceSearchStatus.results ||
            state.status == PlaceSearchStatus.empty)) {
      state = state.copyWith(query: query);
      return;
    }
    state = state.copyWith(
      query: query,
      status: PlaceSearchStatus.debouncing,
      clearPredictions: true,
      clearMessage: true,
    );
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadPredictions(query, generation));
    });
  }

  Future<void> retrySearch() async {
    final query = state.query.trim();
    if (query.length < 3) return;
    _lastRequestedQuery = null;
    final generation = ++_generation;
    await _loadPredictions(query, generation);
  }

  Future<void> selectPrediction(PlacePrediction prediction) async {
    _debounce?.cancel();
    final generation = ++_generation;
    state = state.copyWith(
      status: PlaceSearchStatus.resolving,
      clearMessage: true,
    );
    try {
      final location =
          await ref.read(placeRepositoryProvider).resolvePrediction(
                prediction: prediction,
                sessionToken: _sessionToken,
              );
      if (generation != _generation) return;
      _commit(location);
      _finishSelection(location);
    } on PlaceException catch (error) {
      if (generation == _generation) _fail(_messageFor(error.failure));
    } catch (_) {
      if (generation == _generation) _fail(_unavailableMessage);
    }
  }

  Future<void> submitAddress() async {
    final query = state.query.trim();
    if (query.length < 3) return;
    _debounce?.cancel();
    _sessionToken = _newSessionToken();
    final generation = ++_generation;
    state = state.copyWith(
      status: PlaceSearchStatus.resolving,
      clearMessage: true,
    );
    try {
      final results = await ref.read(placeRepositoryProvider).forwardGeocode(
            address: query,
            bias: _currentBias,
          );
      if (generation != _generation) return;
      if (results.isEmpty) {
        state = state.copyWith(
          status: PlaceSearchStatus.empty,
          clearPredictions: true,
          message: 'No matching location was found.',
        );
        return;
      }
      _commit(results.first);
      _finishSelection(results.first);
    } on PlaceException catch (error) {
      if (generation == _generation) _fail(_messageFor(error.failure));
    } catch (_) {
      if (generation == _generation) _fail(_unavailableMessage);
    }
  }

  Future<void> selectPoint(
    LocationPoint point, {
    required LocationSelectionSource source,
  }) async {
    _debounce?.cancel();
    final generation = ++_generation;
    final fallback = RideLocation(
      point: point,
      label: source == LocationSelectionSource.gps
          ? 'Current location'
          : 'Dropped pin',
      address: 'Address unavailable',
      source: source,
    );
    _commit(fallback);
    state = state.copyWith(
      status: PlaceSearchStatus.resolving,
      selected: fallback,
      clearPredictions: true,
      clearMessage: true,
    );
    try {
      final resolved = await ref.read(placeRepositoryProvider).reverseGeocode(
            point: point,
            source: source,
          );
      if (generation != _generation || state.selected?.point != point) return;
      final location = resolved ?? fallback;
      _commit(location);
      _finishSelection(location);
      if (resolved == null) {
        state = state.copyWith(
          message: 'Address unavailable. The selected pin is still valid.',
        );
      }
    } on PlaceException catch (error) {
      if (generation != _generation || state.selected?.point != point) return;
      state = state.copyWith(
        status: PlaceSearchStatus.selected,
        message: error.failure == PlaceFailure.notFound
            ? 'Address unavailable. The selected pin is still valid.'
            : 'Address lookup failed. The selected pin is still valid.',
      );
    } catch (_) {
      if (generation != _generation || state.selected?.point != point) return;
      state = state.copyWith(
        status: PlaceSearchStatus.selected,
        message: 'Address lookup failed. The selected pin is still valid.',
      );
    }
  }

  Future<void> retryAddress() async {
    final location = state.selected;
    if (location == null) return;
    await selectPoint(location.point, source: location.source);
  }

  void clear() {
    _debounce?.cancel();
    _generation++;
    _lastRequestedQuery = null;
    _sessionToken = _newSessionToken();
    if (_endpoint == LocationEndpoint.pickup) {
      ref.read(bookingControllerProvider.notifier).clearPickup();
    } else {
      ref.read(bookingControllerProvider.notifier).clearDestination();
    }
    state = const PlaceSelectionState();
  }

  Future<void> _loadPredictions(String query, int generation) async {
    if (generation != _generation) return;
    _lastRequestedQuery = query;
    state = state.copyWith(
      status: PlaceSearchStatus.loading,
      clearPredictions: true,
      clearMessage: true,
    );
    try {
      final predictions = await ref.read(placeRepositoryProvider).autocomplete(
            query: query,
            sessionToken: _sessionToken,
            bias: _currentBias,
          );
      if (generation != _generation || state.query.trim() != query) return;
      state = state.copyWith(
        status: predictions.isEmpty
            ? PlaceSearchStatus.empty
            : PlaceSearchStatus.results,
        predictions: predictions,
        message: predictions.isEmpty ? 'No matching places found.' : null,
        clearMessage: predictions.isNotEmpty,
      );
    } on PlaceException catch (error) {
      if (generation == _generation) _fail(_messageFor(error.failure));
    } catch (_) {
      if (generation == _generation) _fail(_unavailableMessage);
    }
  }

  LocationPoint? get _currentBias =>
      ref.read(currentLocationControllerProvider).point;

  void _commit(RideLocation location) {
    final booking = ref.read(bookingControllerProvider.notifier);
    if (_endpoint == LocationEndpoint.pickup) {
      booking.setPickup(location);
    } else {
      booking.setDestination(location);
    }
  }

  void _finishSelection(RideLocation location) {
    state = PlaceSelectionState(
      status: PlaceSearchStatus.selected,
      selected: location,
    );
    _lastRequestedQuery = null;
    _sessionToken = _newSessionToken();
  }

  void _fail(String message) {
    state = state.copyWith(
      status: PlaceSearchStatus.failure,
      clearPredictions: true,
      message: message,
    );
  }

  static String _messageFor(PlaceFailure failure) => switch (failure) {
        PlaceFailure.notFound => 'No matching location was found.',
        PlaceFailure.unauthorized =>
          'Place search is unavailable for this account.',
        PlaceFailure.timedOut => 'Place search timed out. Please try again.',
        PlaceFailure.unavailable ||
        PlaceFailure.invalidResponse =>
          _unavailableMessage,
      };

  static const _unavailableMessage =
      'Place search is unavailable right now. Please try again.';

  static String _newSessionToken() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

final placeSelectionControllerProvider = AutoDisposeNotifierProviderFamily<
    PlaceSelectionController, PlaceSelectionState, LocationEndpoint>(
  PlaceSelectionController.new,
);
