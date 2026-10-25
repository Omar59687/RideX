import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/card_payment_repository.dart';
import 'package:ridex/core/repositories/canonical_payment_repository.dart';
import 'package:ridex/core/repositories/payment_repository.dart';
import 'package:ridex/core/services/supabase/supabase_client_provider.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';
import 'package:ridex/features/history/presentation/widgets/rider_payment_status_card.dart';

/// Feature-local, read-only payment read-state management (P6-06 Slice 2B).
///
/// This layer turns an explicit, backend-issued payment ID into one of the
/// Slice 2A [RiderPaymentReadState] values by reading the canonical record
/// through the existing read-only repository contracts and mapping it with
/// the Slice 1 presentation model. It is read-only by construction: no
/// payment is created, settled, captured, refunded, or cancelled here, and a
/// read grants no financial authority.
///
/// The production reader uses the application-owned Supabase client only for
/// an authenticated, nonblocked Rider whose SDK identity matches the app
/// session. No Payment ID is inferred here: callers must provide a
/// backend-issued ID from a trusted source. The current demo-backed history
/// does not provide one, so its payment surface remains unavailable.
///
/// Trust safeguards: payment IDs are backend-issued identities supplied by
/// the caller, never derived from demo trip records or reconstructed from
/// booking IDs. This layer never builds Trip evidence, never treats matching
/// identifiers as financial authority, never reaches the test/demo-only
/// display or widget constructors, and never infers receipt issuance from
/// payment status. Rendered success wording stays behind
/// [RiderPaymentStatusDisplay.failClosed].

/// The shared canonical repository is bound to the active app Rider and the
/// existing application Supabase client. It performs participant-scoped reads
/// through migration 027's authorized RPC, never finance-table SELECT.
final riderCanonicalPaymentRepositoryProvider =
    Provider<SupabaseCanonicalPaymentRepository?>((ref) {
      final session = ref.watch(sessionControllerProvider);
      final user = session.user;
      if (session.status != SessionStatus.authenticated ||
          session.role != RideRole.rider ||
          user == null ||
          user.isBlocked ||
          user.id.trim().isEmpty) {
        return null;
      }
      final client = ref.watch(supabaseClientProvider);
      final sdkSession = client?.auth.currentSession;
      if (client == null ||
          sdkSession == null ||
          sdkSession.isExpired ||
          sdkSession.user.id != user.id) {
        return null;
      }
      return SupabaseCanonicalPaymentRepository(client);
    });

/// Cash-side repository injection point. Null means the app Rider/session or
/// authenticated application client is not available.
final riderCashPaymentRepositoryProvider = Provider<PaymentRepository?>(
  (ref) => ref.watch(riderCanonicalPaymentRepositoryProvider),
);

/// Card-side reader injection point; see
/// [riderCashPaymentRepositoryProvider].
final riderCardPaymentRepositoryProvider = Provider<CardPaymentRepository?>(
  (ref) => ref.watch(riderCanonicalPaymentRepositoryProvider),
);

/// The last accepted read request, retained for
/// [RiderPaymentReadController.retry].
final class _RiderPaymentReadRequest {
  const _RiderPaymentReadRequest({
    required this.paymentId,
    required this.method,
  });

  final String paymentId;
  final PaymentMethod method;
}

/// Owns the read outcome for one rider payment record.
///
/// Identity and lifecycle safety: every read carries a generation, and the
/// generation advances on each new read, on any session identity, role, or
/// status change, and on disposal. A completion from an earlier generation
/// is discarded, so rapid payment-ID changes, out-of-order repository
/// completions, a logout or rider switch while a read is pending, and
/// provider disposal can never publish a stale or another rider's record.
/// Session changes also reset the state to [RiderPaymentUnavailable].
///
/// Reads additionally require an authenticated Rider session with a
/// nonblank identity at request time and revalidate the same rider before
/// publishing a completion, so a read started without a trusted Rider
/// session fails closed without repository access.
class RiderPaymentReadController extends Notifier<RiderPaymentReadState> {
  int _generation = 0;
  bool _disposed = false;
  _RiderPaymentReadRequest? _lastRequest;

  @override
  RiderPaymentReadState build() {
    _disposed = false;
    _lastRequest = null;
    ref.listen(sessionControllerProvider, (previous, next) {
      if (previous?.user?.id == next.user?.id &&
          previous?.status == next.status &&
          previous?.role == next.role) {
        return;
      }
      _generation++;
      _lastRequest = null;
      state = const RiderPaymentUnavailable();
    });
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    return const RiderPaymentUnavailable();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  /// The active authenticated Rider's nonblank identity, or null when the
  /// session is not a trusted Rider session (loading, unauthenticated,
  /// non-Rider role, blocked, profile error, or blank identity).
  String? _authenticatedRiderId(SessionState session) {
    final user = session.user;
    if (user == null ||
        session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider) {
      return null;
    }
    final id = user.id.trim();
    return id.isEmpty ? null : id;
  }

  /// Reads the canonical record for an explicit backend-issued [paymentId].
  ///
  /// Requires an authenticated Rider session with a nonblank identity at
  /// request time; a loading, unauthenticated, non-Rider, or blank-identity
  /// session fails closed as [RiderPaymentUnavailable] without repository
  /// access. A missing or blank ID resolves to [RiderPaymentUnavailable]
  /// without a repository call. A nonblank ID is read through the injected
  /// reader for [method]; when no approved reader is configured the read
  /// fails closed as [RiderPaymentUnavailable] untouched. While an accepted
  /// read is in flight the state is [RiderPaymentLoading]. A canonical
  /// record maps through the Slice 1 presentation model into
  /// [RiderPaymentReady] only when the same rider identity is still active;
  /// [PaymentFailure.notFound] and [PaymentFailure.invalidRequest] are read
  /// outcomes, not payment failures, and also resolve to
  /// [RiderPaymentUnavailable]. Any other failure resolves to
  /// [RiderPaymentReadFailure] without exposing exception details.
  Future<void> readPayment({
    required String? paymentId,
    required PaymentMethod method,
  }) async {
    final generation = ++_generation;
    final id = paymentId?.trim();
    final riderId = _authenticatedRiderId(ref.read(sessionControllerProvider));
    if (id == null || id.isEmpty || riderId == null) {
      _lastRequest = null;
      state = const RiderPaymentUnavailable();
      return;
    }

    // Pin the application SDK session too. The canonical repository pins its
    // own RPC session; this outer pin prevents a valid response from a newer
    // SDK account (including A-B-A switching) being published under an older
    // app SessionState that has not refreshed yet.
    final client = ref.read(supabaseClientProvider);
    final sdkSession = client?.auth.currentSession;
    if (client != null &&
        (sdkSession == null ||
            sdkSession.isExpired ||
            sdkSession.user.id != riderId)) {
      _lastRequest = null;
      state = const RiderPaymentAuthorizationFailure();
      return;
    }
    _lastRequest = _RiderPaymentReadRequest(paymentId: id, method: method);

    final bool useCash = method == PaymentMethod.cash;
    final PaymentRepository? cashRepository = useCash
        ? ref.read(riderCashPaymentRepositoryProvider)
        : null;
    final CardPaymentRepository? cardRepository = useCash
        ? null
        : ref.read(riderCardPaymentRepositoryProvider);
    if (cashRepository == null && cardRepository == null) {
      state = const RiderPaymentUnavailable();
      return;
    }

    state = const RiderPaymentLoading();

    final RiderPaymentPresentation presentation;
    try {
      if (cashRepository != null) {
        final payment = await cashRepository.readCashPayment(paymentId: id);
        presentation = RiderPaymentPresentation.fromCash(payment);
      } else {
        final payment = await cardRepository!.readCardPayment(paymentId: id);
        presentation = RiderPaymentPresentation.fromCard(payment);
      }
    } on CanonicalPaymentReadException catch (error) {
      if (!_isCurrent(generation)) return;
      _lastRequest = null;
      state = error.failure == CanonicalPaymentReadFailure.unauthorized
          ? const RiderPaymentAuthorizationFailure()
          : const RiderPaymentReadFailure();
      return;
    } on PaymentException {
      if (!_isCurrent(generation)) return;
      state = const RiderPaymentUnavailable();
      return;
    } catch (_) {
      if (!_isCurrent(generation)) return;
      state = const RiderPaymentReadFailure();
      return;
    }

    if (!_isCurrent(generation)) return;
    if (_authenticatedRiderId(ref.read(sessionControllerProvider)) != riderId ||
        (client != null &&
            !identical(client.auth.currentSession, sdkSession))) {
      _lastRequest = null;
      state = const RiderPaymentAuthorizationFailure();
      return;
    }
    state = RiderPaymentReady(presentation);
  }

  /// Advisory retry of the most recent failed read, if any.
  ///
  /// Re-reads only while the state is a [RiderPaymentReadFailure]; it is
  /// never a payment transition and cannot create or change a payment. In
  /// any other state it is a no-op.
  Future<void> retry() async {
    final request = _lastRequest;
    if (request == null || state is! RiderPaymentReadFailure) {
      return;
    }
    await readPayment(paymentId: request.paymentId, method: request.method);
  }
}

final riderPaymentReadControllerProvider =
    NotifierProvider<RiderPaymentReadController, RiderPaymentReadState>(
      RiderPaymentReadController.new,
    );
