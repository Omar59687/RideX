import 'package:ridex/core/models/driver_trip_completion.dart';
import 'fake_canonical_driver_port.dart';

/// Local RPC-shaped scripted double. No SDK, payment, receipt or hosted writes.
/// Allowed edges intentionally independent of the production policy under test.
class FakeDriverTripTransitionPort extends FakeCanonicalDriverPort {
  final transitions = <(String, String, int, String)>[];
  final Map<String, (String, int)> _keys = {};

  FakeDriverTripTransitionPort() {
    accept();
  }

  void transition(
    String id,
    DriverTripLifecycleStatus target,
    int version,
    String key,
  ) {
    final payload = ('$id|${target.name}', version);
    if (_keys.containsKey(key)) {
      if (_keys[key] != payload) throw StateError('idempotency conflict');
      return;
    }
    if (!valid ||
        user?['role'] != 'driver' ||
        user?['is_blocked'] != false ||
        profile?['approval_status'] != 'approved' ||
        trip?['id'] != id ||
        trip?['driver_id'] != driver) {
      throw StateError('unauthorized');
    }
    if (trip?['version'] != version) throw StateError('stale version');
    const edges = {
      'accepted': {'driverArriving', 'cancelledByDriver'},
      'driverArriving': {'driverArrived', 'cancelledByDriver'},
      'driverArrived': {'inProgress', 'cancelledByDriver'},
      'inProgress': {'completed'},
    };
    if (edges[trip?['status']]?.contains(target.name) != true) {
      throw StateError('invalid transition');
    }
    _keys[key] = payload;
    transitions.add((id, target.name, version, key));
    trip = {...trip!, 'status': target.name, 'version': version + 1};
    if (target == DriverTripLifecycleStatus.completed ||
        target == DriverTripLifecycleStatus.cancelledByDriver) {
      availability = {
        ...availability!,
        'state': 'offline',
        'vehicle_id': null,
        'active_trip_id': null,
        'version': (availability!['version'] as int) + 1,
      };
    }
  }
}
