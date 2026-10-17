import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_loading.dart';
import 'package:ridex/core/widgets/status_chip.dart';
import 'package:ridex/features/history/presentation/models/rider_payment_presentation.dart';

/// Read/UI state for a rider payment record.
///
/// These states describe the read outcome only. They are never canonical
/// Card/Cash payment statuses: [RiderPaymentReadFailure] is a connection or
/// read problem that must not be displayed as a payment failure, and
/// [RiderPaymentUnavailable] only means no record is available to present.
sealed class RiderPaymentReadState {
  const RiderPaymentReadState();
}

/// The payment record is still being read.
final class RiderPaymentLoading extends RiderPaymentReadState {
  const RiderPaymentLoading();
}

/// No payment record is available for the presented context.
final class RiderPaymentUnavailable extends RiderPaymentReadState {
  const RiderPaymentUnavailable();
}

/// The payment record could not be read (for example a connection problem).
final class RiderPaymentReadFailure extends RiderPaymentReadState {
  const RiderPaymentReadFailure();
}

/// A canonical payment record is available for presentation.
final class RiderPaymentReady extends RiderPaymentReadState {
  const RiderPaymentReady(this.presentation);

  final RiderPaymentPresentation presentation;
}

/// Fail-closed, presentation-only resolution of a [RiderPaymentPresentation].
///
/// Payment success is never confirmed from [RiderPaymentPresentation]
/// alone: Slice 1 documents that its Trip evidence object is
/// caller-constructible and cannot establish backend trust, so a reported
/// success resolves to an explicit unverified state instead of a confirmed
/// "Payment completed"/"Payment captured" claim. Every non-success canonical
/// state renders its Slice 1 label and description unchanged because those
/// states make no success claim.
///
/// A later slice may confirm success only through an approved canonical
/// Trip-to-payment reader (see [RiderPaymentTripEvidence]).
@immutable
final class RiderPaymentStatusDisplay {
  const RiderPaymentStatusDisplay._({
    required this.title,
    required this.message,
    required this.amountDisplay,
    this.unverifiedSuccess = false,
    this.isSimulated = false,
    this.markerLabel,
    this.markerTone,
    this.markerIcon,
  });

  /// Resolves a presentation for production-facing rendering.
  factory RiderPaymentStatusDisplay.failClosed(
    RiderPaymentPresentation presentation,
  ) {
    if (!presentation.canDescribeAsPaid) {
      return RiderPaymentStatusDisplay._(
        title: presentation.statusLabel,
        message: presentation.statusDescription,
        amountDisplay: presentation.formattedAmount,
      );
    }
    return RiderPaymentStatusDisplay._(
      title: 'Payment status unverified',
      message: 'A successful payment status was reported, but no approved '
          'canonical Trip-to-payment linkage can confirm it. Treat this '
          'payment as unconfirmed.',
      amountDisplay: presentation.formattedAmount,
      unverifiedSuccess: true,
      markerLabel: 'Unverified',
      markerTone: StatusChipTone.warning,
      markerIcon: Icons.report_problem_outlined,
    );
  }

  /// Test/demo-only resolution that may render canonical success wording.
  ///
  /// Never use this in production code: the analyzer flags calls with
  /// `invalid_use_of_visible_for_testing_member`, and every rendering is
  /// explicitly labeled "Simulated data". It exists so tests and isolated
  /// demos can show how a canonical success description looks without
  /// letting caller-constructible evidence authorize a production claim.
  @visibleForTesting
  factory RiderPaymentStatusDisplay.simulated(
    RiderPaymentPresentation presentation,
  ) {
    return RiderPaymentStatusDisplay._(
      title: presentation.statusLabel,
      message: 'Simulated data: ${presentation.statusDescription}',
      amountDisplay: presentation.formattedAmount,
      isSimulated: true,
      markerLabel: _simulatedMarkerLabel,
      markerTone: StatusChipTone.information,
      markerIcon: Icons.science_outlined,
    );
  }

  static const String _simulatedMarkerLabel = 'Simulated data';

  final String title;
  final String message;
  final String amountDisplay;

  /// True when a reported success could not be trusted, so the displayed
  /// wording is intentionally unverified.
  final bool unverifiedSuccess;

  /// True only for test/demo-only simulated resolution.
  final bool isSimulated;

  final String? markerLabel;
  final StatusChipTone? markerTone;
  final IconData? markerIcon;
}

/// Compact, read-only status card for a rider payment record.
///
/// Stateless and side-effect free: no navigation, no payment transitions, no
/// receipt claims, and no mutation controls. Production rendering fails
/// closed (see [RiderPaymentStatusDisplay.failClosed]).
class RiderPaymentStatusCard extends StatelessWidget {
  const RiderPaymentStatusCard({
    super.key,
    required this.readState,
    this.onRetry,
  }) : isSimulated = false;

  /// Test/demo-only constructor that may render canonical success wording,
  /// always explicitly marked "Simulated data". Never use in production code.
  @visibleForTesting
  RiderPaymentStatusCard.simulated({
    super.key,
    required RiderPaymentPresentation presentation,
    this.onRetry,
  })  : readState = RiderPaymentReady(presentation),
        isSimulated = true;

  final RiderPaymentReadState readState;

  /// Advisory retry for [RiderPaymentReadFailure]. A retry re-reads the
  /// record; it is never a payment transition.
  final VoidCallback? onRetry;

  /// True only for the test/demo-only simulated constructor.
  final bool isSimulated;

  @override
  Widget build(BuildContext context) {
    return switch (readState) {
      RiderPaymentLoading() => const _ReadStateCard(
          cardKey: ValueKey('rider-payment-status-loading'),
          child: AppLoading(label: 'Loading payment status'),
        ),
      RiderPaymentUnavailable() => const _ReadStateCard(
          cardKey: ValueKey('rider-payment-status-unavailable'),
          icon: Icons.receipt_long_outlined,
          title: 'Payment record unavailable',
          message: 'No payment record is available for this trip yet. '
              'This is not a payment failure.',
        ),
      RiderPaymentReadFailure() => _ReadStateCard(
          cardKey: const ValueKey('rider-payment-status-read-failure'),
          icon: Icons.cloud_off_outlined,
          title: 'Payment status could not be loaded',
          message: 'A connection or read problem occurred. '
              'This is not a payment failure.',
          onRetry: onRetry,
        ),
      RiderPaymentReady(:final presentation) => _ReadyStatusCard(
          presentation: presentation,
          display: isSimulated
              ? RiderPaymentStatusDisplay.simulated(presentation)
              : RiderPaymentStatusDisplay.failClosed(presentation),
        ),
    };
  }
}

class _ReadStateCard extends StatelessWidget {
  const _ReadStateCard({
    required this.cardKey,
    this.icon,
    this.title,
    this.message,
    this.onRetry,
    this.child,
  });

  final Key cardKey;
  final IconData? icon;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        key: cardKey,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: child ??
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    child: Icon(
                      icon,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(title!, style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      key: const ValueKey('rider-payment-status-retry'),
                      label: 'Try again',
                      onPressed: onRetry,
                      isExpanded: false,
                    ),
                  ],
                ],
              ),
        ),
      ),
    );
  }
}

class _ReadyStatusCard extends StatelessWidget {
  const _ReadyStatusCard({
    required this.presentation,
    required this.display,
  });

  final RiderPaymentPresentation presentation;
  final RiderPaymentStatusDisplay display;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markerLabel = display.markerLabel;
    return Semantics(
      container: true,
      label: _semanticsLabel(),
      excludeSemantics: true,
      child: Card(
        key: const ValueKey('rider-payment-status-card'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (markerLabel != null) ...[
                StatusChip(
                  label: markerLabel,
                  tone: display.markerTone ?? StatusChipTone.neutral,
                  icon: display.markerIcon,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                presentation.methodLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      display.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    display.amountDisplay,
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                display.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final buffer = StringBuffer()
      ..write(presentation.methodLabel)
      ..write('. ')
      ..write(display.title)
      ..write('. ')
      ..write(display.message)
      ..write('. Amount ')
      ..write(display.amountDisplay);
    final marker = display.markerLabel;
    if (marker != null) {
      buffer
        ..write('. ')
        ..write(marker);
    }
    buffer.write('.');
    return buffer.toString();
  }
}
