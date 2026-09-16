import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

class RouteController extends Notifier<RouteState> {
  int _generation = 0;
  RouteRequest? _pendingRequest;
  bool _syncScheduled = false;

  @override
  RouteState build() {
    ref.onDispose(() => _generation++);
    ref.listen<RouteRequest?>(
      bookingControllerProvider.select(RouteRequest.fromDraft),
      (_, request) => _queue(request),
    );
    scheduleMicrotask(() {
      _queue(RouteRequest.fromDraft(ref.read(bookingControllerProvider)));
    });
    return const RouteState();
  }

  void retry() {
    final request = RouteRequest.fromDraft(ref.read(bookingControllerProvider));
    if (request == null) {
      _clear();
      return;
    }
    _start(request);
  }

  void _queue(RouteRequest? request) {
    if (request == state.request) return;

    _generation++;
    _pendingRequest = request;
    state = request == null ? const RouteState() : RouteState.loading(request);
    if (request == null || _syncScheduled) return;

    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      final pending = _pendingRequest;
      if (pending == null) return;
      _start(pending, preserveGeneration: true);
    });
  }

  void _start(RouteRequest request, {bool preserveGeneration = false}) {
    final generation = preserveGeneration ? _generation : ++_generation;
    _pendingRequest = request;
    state = RouteState.loading(request);
    unawaited(_load(request, generation));
  }

  Future<void> _load(RouteRequest request, int generation) async {
    try {
      final result =
          await ref.read(routeRepositoryProvider).calculateRoute(request);
      if (!_isCurrent(request, generation)) return;
      if (result.request != request) {
        throw const RouteException(RouteFailure.invalidResponse);
      }
      state = RouteState.ready(result);
    } on RouteException catch (error) {
      if (!_isCurrent(request, generation)) return;
      state = RouteState.failure(request, _messageFor(error.failure));
    } catch (_) {
      if (!_isCurrent(request, generation)) return;
      state = RouteState.failure(
        request,
        'Route calculation is unavailable. Please try again.',
      );
    }
  }

  bool _isCurrent(RouteRequest request, int generation) {
    return generation == _generation &&
        state.request == request &&
        RouteRequest.fromDraft(ref.read(bookingControllerProvider)) == request;
  }

  void _clear() {
    _generation++;
    _pendingRequest = null;
    state = const RouteState();
  }

  static String _messageFor(RouteFailure failure) => switch (failure) {
        RouteFailure.notFound =>
          'No driving route was found for these locations.',
        RouteFailure.timedOut =>
          'Route calculation timed out. Please try again.',
        RouteFailure.unsupportedStops =>
          'Intermediate stops are not available yet.',
        _ => 'Route calculation is unavailable. Please try again.',
      };
}

final routeControllerProvider =
    NotifierProvider<RouteController, RouteState>(RouteController.new);
