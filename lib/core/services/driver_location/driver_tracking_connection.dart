enum DriverTrackingConnectionStatus {
  subscribed,
  channelError,
  closed,
  timedOut,
}

abstract interface class DriverTrackingConnection {
  Stream<DriverTrackingConnectionStatus> get statuses;

  Future<void> connect();

  Future<void> disconnect();

  Future<void> dispose();
}

class NoopDriverTrackingConnection implements DriverTrackingConnection {
  const NoopDriverTrackingConnection();

  @override
  Stream<DriverTrackingConnectionStatus> get statuses => const Stream.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
