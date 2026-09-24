import 'dart:async';

import 'package:ridex/core/errors/driver_location_exception.dart';
import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:ridex/core/services/diagnostics/app_error_reporter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDriverTrackingConnection implements DriverTrackingConnection {
  SupabaseDriverTrackingConnection(this._client, this._errorReporter);

  final SupabaseClient _client;
  final AppErrorReporter _errorReporter;
  final _statuses = StreamController<DriverTrackingConnectionEvent>.broadcast();
  RealtimeChannel? _channel;
  int _generation = 0;

  @override
  Stream<DriverTrackingConnectionEvent> get events => _statuses.stream;

  @override
  Future<int> connect() async {
    if (_channel != null) return _generation;
    try {
      final generation = ++_generation;
      final channel = _client.channel('ridex:driver-tracking');
      _channel = channel;
      channel.subscribe((status, error) {
        if (_channel != channel) return;
        if (error != null || status != RealtimeSubscribeStatus.subscribed) {
          _errorReporter.report(
            operation: 'maintaining the driver tracking connection',
            error: error ?? status,
          );
        }
        _statuses.add(
          DriverTrackingConnectionEvent(_mapStatus(status), generation),
        );
      });
      return generation;
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'starting the driver tracking connection',
        error: error,
        stackTrace: stackTrace,
      );
      throw const DriverLocationException(
        DriverLocationFailure.networkFailure,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'stopping the driver tracking connection',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    try {
      await _statuses.close();
    } on Object catch (error, stackTrace) {
      _errorReporter.report(
        operation: 'disposing the driver tracking connection',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  DriverTrackingConnectionStatus _mapStatus(RealtimeSubscribeStatus status) =>
      switch (status) {
        RealtimeSubscribeStatus.subscribed =>
          DriverTrackingConnectionStatus.subscribed,
        RealtimeSubscribeStatus.channelError =>
          DriverTrackingConnectionStatus.channelError,
        RealtimeSubscribeStatus.closed => DriverTrackingConnectionStatus.closed,
        RealtimeSubscribeStatus.timedOut =>
          DriverTrackingConnectionStatus.timedOut,
      };
}
