import 'package:ridex/core/models/driver_trip_completion.dart';

/// Production driver completion contract (local slice).
///
/// The future production adapter will invoke only
/// `public.driver_transition_trip` with `requested_status = 'completed'`
/// and map transport/SQL outcomes to [DriverCompletionFailure]. It will never
/// set payment state client-side: Cash settlement and receipt issuance stay
/// trusted backend consequences of completion (`017:263-264`). This interface
/// exists so Developer 3 can build controller tests against the deterministic
/// fake below without any backend-SDK, provider, or Driver UI dependency.
abstract class DriverTripCompletionRepository {
  /// Attempts the trusted completion for [command].
  ///
  /// Returns the canonical result on success. Throws
  /// [DriverTripCompletionException] for every failure category, including
  /// [DriverCompletionFailure.unknownResult] when the outcome cannot be
  /// confirmed. Never returns fabricated versions or receipts.
  ///
  /// Adapter handoff: [DriverCompletionAttemptException] adds stage, original
  /// command, and write evidence without changing this signature. Post-write
  /// read errors remain unknownResult to legacy callers; receipt-read errors
  /// additionally retain canonical completed Trip/version evidence. Receipt
  /// absence returns completed with receiptVerified false. Neither result nor
  /// exception authorizes replay, journal retirement, or payment success.
  Future<DriverCompleteTripResult> completeTrip(
    DriverCompleteTripCommand command,
  );
}

/// Deterministic scripted scenario for [FakeDriverTripCompletionRepository].
enum FakeCompletionScenario {
  success,
  unauthorized,
  tripNotFound,
  staleVersion,
  invalidTransition,
  idempotencyConflict,
  unknownResult,
  malformedResponse,
}

/// In-memory deterministic completion double for controller tests.
///
/// Test/demo-only: it performs no backend call and simulates no Cash
/// settlement or receipt issuance as a trusted payment event. For [success]
/// it returns [_successResult] (or a default unverified `completed` result
/// for the requested trip). For every other scenario it throws the matching
/// [DriverTripCompletionException]. All invocations are recorded in [calls]
/// so tests can verify exact command replay (identical triple).
///
/// Never wire this concrete fake as a production completion authority.
class FakeDriverTripCompletionRepository
    implements DriverTripCompletionRepository {
  FakeDriverTripCompletionRepository({
    this.scenario = FakeCompletionScenario.success,
    DriverCompleteTripResult? successResult,
  }) : _successResult = successResult;

  /// Scripted outcome. Mutable so one fake can cover sequential test phases.
  FakeCompletionScenario scenario;

  final DriverCompleteTripResult? _successResult;

  final List<DriverCompleteTripCommand> _calls = [];

  /// Immutable view of recorded commands in call order.
  List<DriverCompleteTripCommand> get calls => List.unmodifiable(_calls);

  /// Number of recorded invocations.
  int get callCount => _calls.length;

  @override
  Future<DriverCompleteTripResult> completeTrip(
    DriverCompleteTripCommand command,
  ) async {
    _calls.add(command);
    switch (scenario) {
      case FakeCompletionScenario.success:
        final scripted = _successResult;
        if (scripted != null) {
          if (scripted.tripId != command.tripId) {
            throw const DriverTripCompletionException(
              DriverCompletionFailure.malformedResponse,
            );
          }
          return scripted;
        }
        return DriverCompleteTripResult(
          tripId: command.tripId,
          status: DriverTripLifecycleStatus.completed,
        );
      case FakeCompletionScenario.unauthorized:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.unauthorized,
        );
      case FakeCompletionScenario.tripNotFound:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.tripNotFound,
        );
      case FakeCompletionScenario.staleVersion:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.staleVersion,
        );
      case FakeCompletionScenario.invalidTransition:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.invalidTransition,
        );
      case FakeCompletionScenario.idempotencyConflict:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.idempotencyConflict,
        );
      case FakeCompletionScenario.unknownResult:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.unknownResult,
        );
      case FakeCompletionScenario.malformedResponse:
        throw const DriverTripCompletionException(
          DriverCompletionFailure.malformedResponse,
        );
    }
  }
}
