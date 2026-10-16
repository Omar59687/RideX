import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable recovery hint for one unresolved driver completion command.
///
/// The persisted record preserves the EXACT original command (canonical
/// Trip UUID, original expected version, original idempotency key) plus
/// the authenticated Driver that owns it and the creation timestamp, so an
/// ambiguous RPC outcome can replay the identical intent after an app
/// restart. It is a recovery HINT, never proof of Trip completion, Cash
/// settlement, or receipt issuance: only the trusted backend plus
/// canonical rereads classify outcomes. It carries no payment, card,
/// token, or secret data.
class PendingCompletionCommand extends Equatable {
  PendingCompletionCommand({
    required String driverId,
    required String tripId,
    required this.expectedTripVersion,
    required String idempotencyKey,
    required DateTime createdAt,
  })  : driverId = driverId.trim(),
        tripId = tripId.trim(),
        idempotencyKey = idempotencyKey.trim(),
        createdAt = createdAt.toUtc() {
    if (this.driverId.isEmpty) {
      throw ArgumentError.value(driverId, 'driverId', 'Must be nonempty.');
    }
    if (!isCanonicalTripId(this.tripId)) {
      throw ArgumentError.value(
        tripId,
        'tripId',
        'Must be a canonical Trip UUID.',
      );
    }
    if (expectedTripVersion <= 0) {
      throw ArgumentError.value(
        expectedTripVersion,
        'expectedTripVersion',
        'Must be positive.',
      );
    }
    if (this.idempotencyKey.isEmpty || this.idempotencyKey.length > 128) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'Must be 1..128 characters after trimming.',
      );
    }
  }

  /// Authenticated Driver that owns this command (session isolation).
  final String driverId;

  /// Canonical backend Trip UUID.
  final String tripId;

  /// Original expected Trip version. Never mutated for an unresolved
  /// command: a bumped version is a different intent, not a replay.
  final int expectedTripVersion;

  /// Original idempotency key supplied by the caller. Never rotated by
  /// this store: key lifecycle belongs to the backend and the authorized
  /// resolution policy, not to local persistence.
  final String idempotencyKey;

  /// When the command was first persisted (UTC). Determines backend-key
  /// age against [SharedPreferencesCompletionCommandStore.backendKeyLifetime].
  final DateTime createdAt;

  /// Bridges the approved completion contract into a storable record.
  factory PendingCompletionCommand.fromCommand({
    required DriverCompleteTripCommand command,
    required String driverId,
    required DateTime createdAt,
  }) {
    return PendingCompletionCommand(
      driverId: driverId,
      tripId: command.tripId,
      expectedTripVersion: command.expectedTripVersion,
      idempotencyKey: command.idempotencyKey,
      createdAt: createdAt,
    );
  }

  /// Restores the exact original command for an idempotent replay.
  DriverCompleteTripCommand get asCommand => DriverCompleteTripCommand(
        tripId: tripId,
        expectedTripVersion: expectedTripVersion,
        idempotencyKey: idempotencyKey,
      );

  Map<String, dynamic> toJson() => {
        'driver_id': driverId,
        'trip_id': tripId,
        'expected_version': expectedTripVersion,
        'idempotency_key': idempotencyKey,
        'created_at': createdAt.toIso8601String(),
      };

  factory PendingCompletionCommand.fromJson(Map<String, dynamic> json) {
    final parsed = tryParse(json);
    if (parsed == null) {
      throw ArgumentError.value(json, 'json', 'Not a valid command record.');
    }
    return parsed;
  }

  /// Returns null for absent or malformed records instead of throwing, so
  /// corrupt recovery evidence degrades to a guarded slot rather than
  /// crashing recovery. Callers must treat null as unknown, never as
  /// proof of a non-commit.
  static PendingCompletionCommand? tryParse(Map<String, dynamic> json) {
    try {
      final createdRaw = json['created_at'];
      final createdAt =
          createdRaw is String ? DateTime.tryParse(createdRaw) : null;
      if (createdAt == null) return null;
      final version = json['expected_version'];
      if (version is! int) return null;
      return PendingCompletionCommand(
        driverId: json['driver_id'] as String,
        tripId: json['trip_id'] as String,
        expectedTripVersion: version,
        idempotencyKey: json['idempotency_key'] as String,
        createdAt: createdAt,
      );
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  List<Object?> get props => [
        driverId,
        tripId,
        expectedTripVersion,
        idempotencyKey,
        createdAt,
      ];

  /// Identity tuple for exclusive unresolved-command ownership.
  ///
  /// Two records are the same lineage only when the owning driver, Trip,
  /// expected version, and idempotency key all match. `createdAt` is
  /// lineage metadata, so it never participates: an exact replay carries
  /// the same tuple even if it was re-created with a fresh timestamp.
  bool hasSameCommandIdentity(PendingCompletionCommand other) {
    return driverId == other.driverId &&
        tripId == other.tripId &&
        expectedTripVersion == other.expectedTripVersion &&
        idempotencyKey == other.idempotencyKey;
  }
}

/// Storage outcome for one driver's pending-completion slot.
enum CompletionCommandSlotStatus {
  /// No pending command exists for this driver.
  absent,

  /// A well-formed, unexpired record owned by this driver.
  valid,

  /// A well-formed record owned by this driver whose backend key reached
  /// the retention boundary. The record is RETAINED (never auto-discarded)
  /// so an authorized policy can reread canonical state first; blind
  /// replay is forbidden and saving over it requires explicit clearing.
  expired,

  /// A record exists but is unreadable, malformed, or owned by a different
  /// driver — or the read itself failed. The raw record is preserved;
  /// [CompletionCommandSlot.detail] carries only a sanitized code (never
  /// raw JSON or identifiers).
  corrupt,
}

/// Inspect result for [DriverCompletionCommandStore.inspectForDriver].
class CompletionCommandSlot {
  const CompletionCommandSlot._({
    required this.status,
    this.command,
    this.detail,
  });

  /// No pending command for the requested driver.
  const CompletionCommandSlot.absent()
      : this._(status: CompletionCommandSlotStatus.absent);

  /// Well-formed, unexpired record for the requested driver.
  const CompletionCommandSlot.valid(PendingCompletionCommand command)
      : this._(status: CompletionCommandSlotStatus.valid, command: command);

  /// Well-formed but key-expired record for the requested driver.
  const CompletionCommandSlot.expired(PendingCompletionCommand command)
      : this._(status: CompletionCommandSlotStatus.expired, command: command);

  /// Unreadable or mismatched record. [detail] is a sanitized code such as
  /// `malformed-json`, `invalid-shape`, `invalid-envelope`,
  /// `driver-mismatch`, or `unreadable-storage`; it never carries raw
  /// payloads or identifiers.
  const CompletionCommandSlot.corrupt([String detail = 'unreadable-storage'])
      : this._(status: CompletionCommandSlotStatus.corrupt, detail: detail);

  final CompletionCommandSlotStatus status;
  final PendingCompletionCommand? command;

  /// Sanitized corrupt code; null for absent/valid/expired slots.
  final String? detail;

  bool get isAbsent => status == CompletionCommandSlotStatus.absent;
  bool get isValid => status == CompletionCommandSlotStatus.valid;
  bool get isExpired => status == CompletionCommandSlotStatus.expired;
  bool get isCorrupt => status == CompletionCommandSlotStatus.corrupt;
}

/// Thrown when saving would overwrite a different unresolved command, or
/// when a stale clear targets newer evidence. Stored evidence is
/// preserved in both cases.
class CompletionCommandConflictException implements Exception {
  const CompletionCommandConflictException(
      [this.message =
          'A different unresolved completion command is already stored.']);

  final String message;

  @override
  String toString() => 'CompletionCommandConflictException: $message';
}

/// Thrown when a slot holds unreadable evidence. The raw record is left
/// untouched; callers must surface a safe blocked state instead of
/// treating the slot as absent or overwriting it.
class CompletionCommandCorruptException implements Exception {
  const CompletionCommandCorruptException(
      [this.message = 'Stored completion evidence is unreadable.']);

  final String message;

  @override
  String toString() => 'CompletionCommandCorruptException: $message';
}

/// Durability boundary for one driver's pending completion command.
///
/// Slots are namespaced per authenticated Driver, so one driver's save can
/// never overwrite or expose another driver's record: a cross-namespace
/// read degrades to a corrupt slot, and conditional clearing compares the
/// exact stored identity (including the owning driver). All operations run
/// through one internal FIFO, so concurrent saves and save/clear pairs
/// resolve deterministically and a stale async cleanup can never remove
/// newer evidence mid-flight.
///
/// The persisted record is a recovery HINT, not authoritative evidence of
/// the server outcome. Storage write failures propagate unwrapped: a throw
/// from [savePending] means "do not dispatch the RPC".
abstract interface class DriverCompletionCommandStore {
  /// Persists [record] before its first RPC attempt and completes the
  /// write before returning. Exact duplicates (same identity tuple) are an
  /// idempotent no-op that preserves the ORIGINAL creation timestamp. A
  /// different unresolved command — including an expired one — throws
  /// [CompletionCommandConflictException]; corrupt slots throw
  /// [CompletionCommandCorruptException].
  Future<void> savePending(PendingCompletionCommand record);

  /// Returns the driver's record for valid AND expired slots, or null
  /// when absent or unreadable. A returned record is never proof of Trip
  /// completion, settlement, or receipt issuance.
  Future<PendingCompletionCommand?> loadPendingForDriver(String driverId);

  /// Distinguishes absent, valid, expired, and corrupt slots without
  /// deleting or exposing the underlying record. Callers must never
  /// overwrite a corrupt or expired slot and must resolve those through
  /// an authorized policy (canonical reread first).
  Future<CompletionCommandSlot> inspectForDriver(String driverId);

  /// Removes the slot only when the stored record carries the exact
  /// identity of [expected] (owning driver included). An absent slot is
  /// an idempotent success; a mismatched (newer or foreign) record throws
  /// [CompletionCommandConflictException] so stale cleanup preserves it;
  /// corrupt slots throw [CompletionCommandCorruptException].
  Future<void> clearPending(PendingCompletionCommand expected);
}

class SharedPreferencesCompletionCommandStore
    implements DriverCompletionCommandStore {
  SharedPreferencesCompletionCommandStore(
    SharedPreferencesAsync preferences, {
    DateTime Function()? clock,
  })  : _preferences = preferences,
        _clock = clock ?? DateTime.now;

  /// Envelope version for safe decoding of persisted records.
  static const int schemaVersion = 1;

  /// Backend idempotency-key retention (`005:120-124`: `created_at +
  /// interval '7 days'`). Records at or past this age are flagged
  /// expired: retained for authorized reconciliation, never blindly
  /// replayed, and never silently replaced.
  static const Duration backendKeyLifetime = Duration(days: 7);

  static String keyForDriver(String driverId) =>
      'pending_completion_command.v1.$driverId';

  final SharedPreferencesAsync _preferences;
  final DateTime Function() _clock;

  DateTime get _now => _clock().toUtc();

  Future<void> _tail = Future.value();

  /// Serializes store operations through one FIFO so concurrent saves and
  /// save/clear pairs cannot interleave a stale read with a newer write.
  /// A failing operation never breaks the chain for later operations.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> savePending(PendingCompletionCommand record) {
    return _serialized(() async {
      final slot = await inspectForDriver(record.driverId);
      if (slot.isCorrupt) throw const CompletionCommandCorruptException();
      final existing = slot.command;
      if (existing != null) {
        if (!existing.hasSameCommandIdentity(record)) {
          throw const CompletionCommandConflictException();
        }
        if (slot.isExpired) {
          // Same triple, dead backend key: replaying it would act as a new
          // backend-key lifecycle while keeping a stale creation timestamp.
          // Force the authorized path instead: explicit conditional clear,
          // canonical reread, then a fresh save with a fresh timestamp.
          throw const CompletionCommandConflictException(
            'The stored command reached backend-key expiry and must be '
            'explicitly cleared after canonical reconciliation.',
          );
        }
        return;
      }
      await _preferences.setString(
        keyForDriver(record.driverId),
        jsonEncode({'schema': schemaVersion, 'command': record.toJson()}),
      );
    });
  }

  @override
  Future<PendingCompletionCommand?> loadPendingForDriver(String driverId) {
    return _serialized(() async {
      final slot = await inspectForDriver(driverId);
      return slot.command;
    });
  }

  @override
  Future<CompletionCommandSlot> inspectForDriver(String driverId) async {
    if (driverId.trim().isEmpty) {
      return const CompletionCommandSlot.corrupt('invalid-driver-namespace');
    }
    final String? raw;
    try {
      raw = await _preferences.getString(keyForDriver(driverId));
    } on Object {
      // Storage read failure: unreadable evidence, never absent. The raw
      // record is left untouched for later diagnosis.
      return const CompletionCommandSlot.corrupt('unreadable-storage');
    }
    return inspectRaw(driverId, raw, now: _now);
  }

  /// Pure slot classification for a raw persisted value. Extracted so
  /// corrupt/expired handling is deterministically testable without
  /// platform channels. Never deletes or exposes the raw record; corrupt
  /// details are sanitized codes only.
  static CompletionCommandSlot inspectRaw(
    String driverId,
    String? raw, {
    required DateTime now,
  }) {
    if (driverId.trim().isEmpty) {
      return const CompletionCommandSlot.corrupt('invalid-driver-namespace');
    }
    if (raw == null) {
      return const CompletionCommandSlot.absent();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const CompletionCommandSlot.corrupt('invalid-shape');
      }
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope['schema'] != schemaVersion || envelope['command'] is! Map) {
        return const CompletionCommandSlot.corrupt('invalid-envelope');
      }
      final record = PendingCompletionCommand.tryParse(
        Map<String, dynamic>.from(envelope['command'] as Map),
      );
      if (record == null) {
        return const CompletionCommandSlot.corrupt('invalid-shape');
      }
      // A slot namespaced for one driver must never yield another
      // driver's command: a mismatch is suspicious evidence, not a valid
      // command and never safe absence.
      if (record.driverId != driverId) {
        return const CompletionCommandSlot.corrupt('driver-mismatch');
      }
      if (isExpiredAt(record, now)) {
        return CompletionCommandSlot.expired(record);
      }
      return CompletionCommandSlot.valid(record);
    } on FormatException {
      return const CompletionCommandSlot.corrupt('malformed-json');
    } on Object {
      return const CompletionCommandSlot.corrupt('invalid-shape');
    }
  }

  /// Whether [record] reached the backend-key retention boundary at [now].
  /// The boundary is inclusive: age equal to the lifetime counts as
  /// expired, so there is no instant where an age-limited key is treated
  /// as safely replayable past its retention.
  static bool isExpiredAt(PendingCompletionCommand record, DateTime now) {
    return now.toUtc().difference(record.createdAt) >= backendKeyLifetime;
  }

  @override
  Future<void> clearPending(PendingCompletionCommand expected) {
    return _serialized(() async {
      final slot = await inspectForDriver(expected.driverId);
      if (slot.isCorrupt) throw const CompletionCommandCorruptException();
      final existing = slot.command;
      if (existing == null) return;
      if (!existing.hasSameCommandIdentity(expected)) {
        // Newer or foreign evidence: a stale cleanup must never remove it.
        throw const CompletionCommandConflictException(
          'Stored completion evidence does not match; refusing to clear.',
        );
      }
      await _preferences.remove(keyForDriver(expected.driverId));
    });
  }
}
