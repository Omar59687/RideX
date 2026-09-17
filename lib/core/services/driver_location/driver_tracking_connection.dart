enum DriverTrackingConnectionStatus {
  subscribed,
  channelError,
  closed,
  timedOut,
}

class DriverTrackingConnectionEvent {
  const DriverTrackingConnectionEvent(this.status, this.generation);

  final DriverTrackingConnectionStatus status;
  final int generation;
}

abstract interface class DriverTrackingConnection {
  Stream<DriverTrackingConnectionEvent> get events;

  Future<int> connect();

  Future<void> disconnect();

  Future<void> dispose();
}

class NoopDriverTrackingConnection implements DriverTrackingConnection {
  const NoopDriverTrackingConnection();

  @override
  Stream<DriverTrackingConnectionEvent> get events => const Stream.empty();

  @override
  Future<int> connect() async => 0;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
