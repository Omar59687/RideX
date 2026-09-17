import 'dart:async';

import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDriverTrackingConnection implements DriverTrackingConnection {
  SupabaseDriverTrackingConnection(this._client);

  final SupabaseClient _client;
  final _statuses =
      StreamController<DriverTrackingConnectionStatus>.broadcast();
  RealtimeChannel? _channel;

  @override
  Stream<DriverTrackingConnectionStatus> get statuses => _statuses.stream;

  @override
  Future<void> connect() async {
    if (_channel != null) return;
    final channel = _client.channel('ridex:driver-tracking');
    _channel = channel;
    channel.subscribe((status, error) {
      _statuses.add(_mapStatus(status));
    });
  }

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _statuses.close();
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
