import 'dart:convert';

import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durability boundary for the pending fare-lock command.
///
/// The persisted record is a recovery HINT, not authoritative evidence of
/// the server outcome: only canonical recovery (later slice) classifies it.
/// Slots are namespaced per rider so one user's save can never overwrite or
/// expose another user's record.
abstract interface class PendingFareLockStore {
  /// Completes the write before returning. Callers dispatch the lock RPC
  /// only after this completes; a throw means "do not dispatch".
  Future<void> save(PendingFareLock command);

  /// Returns the rider's record, or null when absent or unreadable. Null
  /// means unknown, never proof of a non-commit.
  ///
  /// Prefer [inspectForRider] when exclusivity matters: this convenience
  /// collapses corrupt evidence to null, so it must never be used to
  /// authorize overwriting a slot.
  Future<PendingFareLock?> loadForRider(String riderId);

  /// Distinguishes absent, valid, and unreadable/corrupt slots without
  /// deleting or exposing the underlying record. Corrupt includes malformed
  /// JSON, invalid shapes, rider-namespace mismatches, and storage read
  /// failures. Callers must never overwrite a corrupt slot and must surface
  /// a safe blocked state instead of treating it as absent.
  Future<PendingFareLockSlot> inspectForRider(String riderId);

  /// Deletes pending evidence while preserving retained confirmed references
  /// and their retirement guards. Uses the command's own rider, never a
  /// guessed active user.
  Future<void> clearForRider(String riderId);
}

/// Optional capability: one best-effort per-Rider envelope replacement. Stores
/// without this capability cannot authorize retirement. No transaction or
/// guaranteed crash durability is promised by SharedPreferences.
abstract interface class ConfirmedBookingTransferStore {
  Future<void> retireConfirmed(ConfirmedBookingReference reference,
      {required bool Function() isAuthorized});
}

/// Storage outcome for a per-rider pending-lock slot (Slice 1, F4).
enum PendingFareLockSlotStatus {
  /// No pending command exists; confirmed references may still be retained.
  absent,

  /// A well-formed record attributable to the requested rider.
  valid,

  /// A record exists but is unreadable, malformed, or attributable to a
  /// different rider namespace — or the read itself failed. The raw record
  /// is preserved; [PendingFareLockSlot.detail] carries only a sanitized
  /// code (never raw JSON or identifiers).
  corrupt,
}

/// Inspect result for [PendingFareLockStore.inspectForRider].
class PendingFareLockSlot {
  const PendingFareLockSlot._({
    required this.status,
    this.command,
    this.detail,
    this.confirmed = const [],
  });

  /// No pending command for the requested rider.
  const PendingFareLockSlot.absent(
      [List<ConfirmedBookingReference> confirmed = const []])
      : this._(status: PendingFareLockSlotStatus.absent, confirmed: confirmed);

  /// Well-formed record for the requested rider.
  const PendingFareLockSlot.valid(PendingFareLock command,
      [List<ConfirmedBookingReference> confirmed = const []])
      : this._(
            status: PendingFareLockSlotStatus.valid,
            command: command,
            confirmed: confirmed);

  /// Unreadable or mismatched record. [detail] is a sanitized code such as
  /// `malformed-json`, `invalid-shape`, `rider-mismatch`, or
  /// `unreadable-storage`; it never carries raw payloads or identifiers.
  const PendingFareLockSlot.corrupt([String detail = 'unreadable-storage'])
      : this._(status: PendingFareLockSlotStatus.corrupt, detail: detail);

  final PendingFareLockSlotStatus status;
  final PendingFareLock? command;
  final List<ConfirmedBookingReference> confirmed;

  /// Sanitized corrupt code; null for absent/valid slots.
  final String? detail;

  bool get isAbsent => status == PendingFareLockSlotStatus.absent;
  bool get isValid => status == PendingFareLockSlotStatus.valid;
  bool get isCorrupt => status == PendingFareLockSlotStatus.corrupt;
}

class SharedPreferencesPendingFareLockStore
    implements PendingFareLockStore, ConfirmedBookingTransferStore {
  SharedPreferencesPendingFareLockStore(this._preferences);

  static String keyForRider(String riderId) => 'pending_fare_lock.v1.$riderId';

  final SharedPreferencesAsync _preferences;

  Future<void> _write(String riderId, PendingFareLock? pending,
          List<ConfirmedBookingReference> confirmed) =>
      _preferences.setString(
          keyForRider(riderId),
          jsonEncode({
            'schema': 2,
            'pending': pending?.toJson(),
            'confirmed': [
              for (final reference in confirmed) reference.toJson()
            ],
          }));

  @override
  Future<void> save(PendingFareLock command) async {
    final slot = await inspectForRider(command.riderId);
    if (slot.isCorrupt) throw const PendingFareLockCorruptException();
    if (slot.confirmed.any(
            (r) => r.command.bookingRequestId == command.bookingRequestId) ||
        (slot.isValid && !slot.command!.hasSameLockIdentity(command))) {
      throw const PendingFareLockConflictException();
    }
    await _write(command.riderId, command, slot.confirmed);
  }

  @override
  Future<void> retireConfirmed(ConfirmedBookingReference reference,
      {required bool Function() isAuthorized}) async {
    final command = reference.command;
    final slot = await inspectForRider(command.riderId);
    if (!isAuthorized()) throw const PendingFareLockOwnershipException();
    if (slot.isCorrupt) throw const PendingFareLockCorruptException();
    final existing = slot.confirmed
        .where((r) => r.command.bookingRequestId == command.bookingRequestId)
        .toList();
    if (existing.isNotEmpty) {
      if (existing.single.command.hasSameLockIdentity(command) &&
          existing.single.quote == reference.quote) {
        return;
      }
      throw const PendingFareLockConflictException();
    }
    if (!slot.isValid || !slot.command!.hasSameLockIdentity(command)) {
      throw const PendingFareLockConflictException();
    }
    await _write(command.riderId, null, [...slot.confirmed, reference]);
  }

  @override
  Future<PendingFareLock?> loadForRider(String riderId) async {
    final slot = await inspectForRider(riderId);
    return slot.command;
  }

  @override
  Future<PendingFareLockSlot> inspectForRider(String riderId) async {
    if (riderId.trim().isEmpty) {
      return const PendingFareLockSlot.corrupt('invalid-rider-namespace');
    }
    final String? raw;
    try {
      raw = await _preferences.getString(keyForRider(riderId));
    } on Object {
      // Storage read failure: unreadable evidence, never absent. The raw
      // record is left untouched for later diagnosis.
      return const PendingFareLockSlot.corrupt('unreadable-storage');
    }
    return inspectRaw(riderId, raw);
  }

  /// Pure slot classification for a raw persisted value. Extracted so
  /// corrupt-evidence handling (malformed JSON, invalid shapes,
  /// rider-namespace mismatches) is deterministically testable without
  /// platform channels. Never deletes or exposes the raw record; corrupt
  /// details are sanitized codes only.
  static PendingFareLockSlot inspectRaw(String riderId, String? raw) {
    if (riderId.trim().isEmpty) {
      return const PendingFareLockSlot.corrupt('invalid-rider-namespace');
    }
    if (raw == null) {
      return const PendingFareLockSlot.absent();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const PendingFareLockSlot.corrupt('invalid-shape');
      }
      final normalized = Map<String, dynamic>.from(decoded);
      final references = <ConfirmedBookingReference>[];
      Map<String, dynamic>? pending = normalized;
      if (normalized.containsKey('schema')) {
        if (normalized['schema'] != 2 ||
            normalized['confirmed'] is! List ||
            !normalized.containsKey('pending')) {
          return const PendingFareLockSlot.corrupt('invalid-envelope');
        }
        final ids = <String>{};
        for (final rawReference in normalized['confirmed'] as List) {
          final reference = ConfirmedBookingReference.fromJson(
              Map<String, dynamic>.from(rawReference as Map));
          if (reference.command.riderId != riderId ||
              !ids.add(reference.command.bookingRequestId)) {
            return const PendingFareLockSlot.corrupt('invalid-reference');
          }
          references.add(reference);
        }
        final value = normalized['pending'];
        pending =
            value == null ? null : Map<String, dynamic>.from(value as Map);
      }
      if (pending == null) {
        return PendingFareLockSlot.absent(List.unmodifiable(references));
      }
      final parsed = PendingFareLock.tryParse(pending);
      if (parsed == null ||
          references.any(
              (r) => r.command.bookingRequestId == parsed.bookingRequestId)) {
        return const PendingFareLockSlot.corrupt('invalid-shape');
      }
      // A slot namespaced for one rider must never yield another rider's
      // command: a mismatch is suspicious evidence, not a valid command
      // and never safe absence.
      if (parsed.riderId != riderId) {
        return const PendingFareLockSlot.corrupt('rider-mismatch');
      }
      return PendingFareLockSlot.valid(parsed, List.unmodifiable(references));
    } on FormatException {
      return const PendingFareLockSlot.corrupt('malformed-json');
    } on Object {
      return const PendingFareLockSlot.corrupt('invalid-shape');
    }
  }

  @override
  Future<void> clearForRider(String riderId) async {
    final slot = await inspectForRider(riderId);
    if (slot.isCorrupt) throw const PendingFareLockCorruptException();
    if (slot.confirmed.isEmpty) {
      await _preferences.remove(keyForRider(riderId));
    } else {
      await _write(riderId, null, slot.confirmed);
    }
  }
}
