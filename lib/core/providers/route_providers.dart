import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';

class RouteController extends Notifier<RouteState> {
  int _generation = 0;
  RouteRequest? _pendingRequest;
  bool _syncScheduled = false;
  late final AppErrorReporter _errorReporter;

  @override
  RouteState build() {
    _errorReporter = ref.read(appErrorReporterProvider);
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
    _start(request, previousResult: state.result);
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

  void _start(
    RouteRequest request, {
    bool preserveGeneration = false,
    RouteResult? previousResult,
  }) {
    final generation = preserveGeneration ? _generation : ++_generation;
    _pendingRequest = request;
    state = RouteState.loading(request, previousResult: previousResult);
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
      state = RouteState.failure(
        request,
        error.failure,
        previousResult: state.result,
      );
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'calculating a route',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_isCurrent(request, generation)) return;
      state = RouteState.failure(
        request,
        RouteFailure.unavailable,
        previousResult: state.result,
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
}

final routeControllerProvider =
    NotifierProvider<RouteController, RouteState>(RouteController.new);
