import 'dart:async';

import 'package:ridex/core/services/driver_location/driver_tracking_connection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDriverTrackingConnection implements DriverTrackingConnection {
  SupabaseDriverTrackingConnection(this._client);

  final SupabaseClient _client;
  final _statuses = StreamController<DriverTrackingConnectionEvent>.broadcast();
  RealtimeChannel? _channel;
  int _generation = 0;

  @override
  Stream<DriverTrackingConnectionEvent> get events => _statuses.stream;

  @override
  Future<int> connect() async {
    if (_channel != null) return _generation;
    final generation = ++_generation;
    final channel = _client.channel('ridex:driver-tracking');
    _channel = channel;
    channel.subscribe((status, error) {
      if (_channel != channel) return;
      _statuses.add(
        DriverTrackingConnectionEvent(_mapStatus(status), generation),
      );
    });
    return generation;
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
