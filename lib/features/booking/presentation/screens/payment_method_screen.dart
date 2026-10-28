import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/router/route_names.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';

/// Immutable handoff from the fare screen. Only a persisted, locked fare is
/// allowed to back this review surface; illustrative demo amounts are never
/// passed here.
@immutable
class PaymentMethodRouteData {
  const PaymentMethodRouteData({required this.quote, required this.riderId});

  final FareQuote quote;
  final String riderId;
}

class PaymentMethodScreen extends ConsumerStatefulWidget {
  const PaymentMethodScreen({super.key, required this.data});

  final PaymentMethodRouteData? data;

  @override
  ConsumerState<PaymentMethodScreen> createState() =>
      _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen> {
  PaymentMethod? _canonicalMethod;
  BookingHandoff? _canonicalHandoff;
  bool _loading = true;
  bool _navigating = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCanonical());
  }

  @override
  void didUpdateWidget(covariant PaymentMethodScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data?.quote != widget.data?.quote ||
        oldWidget.data?.riderId != widget.data?.riderId) {
      _loadCanonical();
    }
  }

  Future<void> _loadCanonical() async {
    final data = widget.data;
    final session = ref.read(sessionControllerProvider);
    final generation = ++_generation;
    if (data == null ||
        session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        session.user?.id != data.riderId ||
        !validLockedSnapshot(data.quote)) {
      if (mounted) {
        setState(() {
          _canonicalMethod = null;
          _canonicalHandoff = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _canonicalMethod = null;
      _canonicalHandoff = null;
      _loading = true;
    });
    try {
      final handoff = await ref
          .read(pendingFareLockControllerProvider.notifier)
          .bookingHandoff(bookingRequestId: data.quote.bookingRequestId);
      final current = ref.read(sessionControllerProvider);
      if (!mounted ||
          generation != _generation ||
          !identical(session, current) ||
          current.user?.id != data.riderId ||
          handoff.quote != data.quote ||
          handoff.booking.id != data.quote.bookingRequestId ||
          handoff.booking.riderId != data.riderId) {
        return;
      }
      setState(() {
        _canonicalHandoff = handoff;
        _canonicalMethod = handoff.booking.paymentMethod;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _canonicalMethod = null;
        _canonicalHandoff = null;
        _loading = false;
      });
    }
  }

  Future<void> _continueWithCanonicalCash() async {
    if (!mounted || _navigating) return;
    final data = widget.data;
    final displayedHandoff = _canonicalHandoff;
    final session = ref.read(sessionControllerProvider);
    final generation = _generation;
    if (data == null ||
        displayedHandoff == null ||
        displayedHandoff.booking.paymentMethod != PaymentMethod.cash ||
        session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider ||
        session.user?.id != data.riderId) {
      return;
    }

    setState(() => _navigating = true);
    try {
      final current = await ref
          .read(pendingFareLockControllerProvider.notifier)
          .bookingHandoff(bookingRequestId: data.quote.bookingRequestId);
      final currentSession = ref.read(sessionControllerProvider);
      if (!mounted ||
          generation != _generation ||
          !identical(session, currentSession) ||
          widget.data?.quote != data.quote ||
          widget.data?.riderId != data.riderId) {
        return;
      }

      if (current.booking.id != data.quote.bookingRequestId ||
          current.booking.riderId != data.riderId ||
          current.quote != data.quote ||
          !validLockedSnapshot(current.quote)) {
        setState(() {
          _canonicalMethod = null;
          _canonicalHandoff = null;
          _loading = false;
        });
        return;
      }

      setState(() {
        _canonicalHandoff = current;
        _canonicalMethod = current.booking.paymentMethod;
        _loading = false;
      });
      if (current.booking.paymentMethod != PaymentMethod.cash) return;

      await context.pushNamed<void>(RouteNames.confirmation,
          queryParameters: {'booking': data.quote.bookingRequestId});
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _canonicalMethod = null;
          _canonicalHandoff = null;
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    ref.listen(sessionControllerProvider, (previous, next) {
      if (!identical(previous, next)) _loadCanonical();
    });
    final data = widget.data;
    final payment = _canonicalMethod;
    final quote = data?.quote;
    final authorized = data != null &&
        quote != null &&
        session.status == SessionStatus.authenticated &&
        session.role == RideRole.rider &&
        session.user?.id == data.riderId &&
        validLockedSnapshot(quote) &&
        !_loading &&
        payment != null;
    final canContinue =
        authorized && payment == PaymentMethod.cash && !_navigating;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to booking',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Payment Method'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: _loading || _navigating
                    ? 'Verifying payment method'
                    : payment == null
                        ? 'Payment method unavailable'
                        : payment == PaymentMethod.card
                            ? 'Card currently unavailable'
                            : 'Continue with Cash',
                semanticLabel: _loading || _navigating
                    ? 'Verifying the locked booking payment method'
                    : payment == null
                        ? 'Payment method unavailable; continuation disabled'
                        : payment == PaymentMethod.card
                            ? 'Card payment currently unavailable'
                            : 'Continue with Cash',
                onPressed: canContinue ? _continueWithCanonicalCash : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                payment == PaymentMethod.card
                    ? 'Card payment is unavailable for this locked booking.'
                    : payment == null
                        ? 'Verifying the payment method saved on this booking.'
                        : 'You will not be charged now.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Payment method locked with this fare',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _MethodCard(
                    selected: payment == PaymentMethod.cash,
                    icon: Icons.payments_outlined,
                    title: 'Cash',
                    subtitle: 'Pay your driver after the trip',
                    onTap: null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MethodCard(
                    selected: payment == PaymentMethod.card,
                    icon: Icons.credit_card_outlined,
                    title: 'Card',
                    subtitle: 'Pay securely with your card',
                    availability: 'Currently unavailable',
                    onTap: null,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: theme.brightness == Brightness.light ? .62 : .5,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            payment == PaymentMethod.cash
                                ? 'Pay your driver when your trip is completed.'
                                : 'Card payment is not available yet. No card details are collected.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Fare summary',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              if (authorized)
                                _LockedChip(color: colors.primary),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (authorized) ...[
                            _FareRow(
                              label: 'Locked ride fare',
                              value: formatFareFils(quote.fixedFareFils),
                            ),
                            const Divider(height: AppSpacing.xl),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Total',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  formatFareFils(quote.fixedFareFils),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(color: colors.primary),
                                ),
                              ],
                            ),
                          ] else
                            Text(
                              _loading
                                  ? 'Verifying the locked booking and payment method…'
                                  : 'A verified locked booking and payment method are required before continuing.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!authorized) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      payment == PaymentMethod.card
                          ? 'This locked booking cannot continue as Cash. Card payment is unavailable.'
                          : 'Fare, payment method, or Rider session is unavailable. Return to booking and verify again.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.availability,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? availability;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderColor = selected ? colors.primary : colors.outlineVariant;
    return Semantics(
      container: true,
      selected: selected,
      enabled: onTap != null,
      label: [
        title,
        subtitle,
        if (availability != null) availability!,
      ].join(', '),
      child: Material(
        color: selected ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: borderColor, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 100),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          selected ? colors.surface : colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color:
                          selected ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (selected)
                              Text(
                                'Selected',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (availability != null)
                          Text(
                            availability!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.outline,
                    semanticLabel: selected ? 'Selected' : 'Not selected',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
}

class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Locked',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      );
}
