import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/models/rider_live_map_state.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

/// Adapter seam for a map surface.
///
/// The builder is invoked only when the injected revocable state currently
/// exposes an authorized Driver point. Implementations should read the point
/// from [state] while building and must not retain a copied coordinate.
typedef RiderLiveMapRendererBuilder = Widget Function(
  BuildContext context,
  RiderLiveMapState state,
);

/// Standalone Rider tracking presentation.
///
/// This screen is intentionally not wired into app routing or a production
/// tracking provider. A host must explicitly supply a configured renderer;
/// otherwise a safe, non-geographic fallback is shown.
class RiderLiveMapScreen extends StatefulWidget {
  const RiderLiveMapScreen({
    super.key,
    required this.state,
    required this.stateInvalidations,
    this.mapConfigured = false,
    this.rendererBuilder,
    this.clock = DateTime.now,
    this.freshnessWindow = const Duration(seconds: 30),
  }) : assert(freshnessWindow > Duration.zero);

  final RiderLiveMapState state;

  /// Notifies this presentation when its owner changes authorization, Trip, or
  /// session lineage. It is only an invalidation signal, never proof of access.
  /// The owner must notify after every revocation or identity transition it can
  /// observe; the screen cannot detect silent changes by itself.
  final Listenable stateInvalidations;
  final bool mapConfigured;
  final RiderLiveMapRendererBuilder? rendererBuilder;

  /// Must match the clock and freshness window used to create [state].
  final DateTime Function() clock;
  final Duration freshnessWindow;

  @override
  State<RiderLiveMapScreen> createState() => _RiderLiveMapScreenState();
}

class _RiderLiveMapScreenState extends State<RiderLiveMapScreen> {
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    widget.stateInvalidations.addListener(_onStateInvalidated);
    _scheduleFreshnessExpiryAfterBuild();
  }

  @override
  void didUpdateWidget(covariant RiderLiveMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateInvalidations != widget.stateInvalidations) {
      oldWidget.stateInvalidations.removeListener(_onStateInvalidated);
      widget.stateInvalidations.addListener(_onStateInvalidated);
    }
    _cancelFreshnessTimer();
    _scheduleFreshnessExpiryAfterBuild();
  }

  @override
  void dispose() {
    widget.stateInvalidations.removeListener(_onStateInvalidated);
    _cancelFreshnessTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Live trip map',
      maxContentWidth: 720,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final mapHeight = (constraints.maxHeight * 0.46).clamp(220.0, 360.0);
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(
                height: mapHeight,
                child: _MapViewport(
                  state: widget.state,
                  mapConfigured: widget.mapConfigured,
                  rendererBuilder: widget.rendererBuilder,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _TrackingStatusCard(state: widget.state),
              const SizedBox(height: AppSpacing.sm),
              const _RouteUnavailableCard(),
              const SizedBox(height: AppSpacing.md),
            ],
          );
        },
      ),
    );
  }

  void _onStateInvalidated() {
    if (!mounted) return;
    _cancelFreshnessTimer();
    setState(() {});
    _scheduleFreshnessExpiryAfterBuild();
  }

  void _scheduleFreshnessExpiryAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleFreshnessExpiry();
    });
  }

  void _scheduleFreshnessExpiry() {
    _cancelFreshnessTimer();
    final state = widget.state;
    if (!state.hasLiveLocation) return;
    final recordedAt = state.locationRecordedAt;
    if (recordedAt == null) return;

    // Slice 1 treats a sample as fresh through the exact freshness boundary
    // (`age <= freshnessWindow`), so wake just after that deadline.
    final deadline = recordedAt
        .toUtc()
        .add(widget.freshnessWindow)
        .add(const Duration(microseconds: 1));
    final delay = deadline.difference(widget.clock().toUtc());
    _freshnessTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _onFreshnessDeadline,
    );
  }

  void _onFreshnessDeadline() {
    _freshnessTimer = null;
    if (!mounted) return;
    // The state getter rechecks its revocable authorization lease and clock.
    setState(() {});
    _scheduleFreshnessExpiryAfterBuild();
  }

  void _cancelFreshnessTimer() {
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
  }
}

class _MapViewport extends StatelessWidget {
  const _MapViewport({
    required this.state,
    required this.mapConfigured,
    required this.rendererBuilder,
  });

  final RiderLiveMapState state;
  final bool mapConfigured;
  final RiderLiveMapRendererBuilder? rendererBuilder;

  @override
  Widget build(BuildContext context) {
    final canPlot = _hasAuthorizedLocation(state);
    final builder = rendererBuilder;
    final Widget content;
    final String semanticLabel;

    if (mapConfigured && builder != null && canPlot) {
      // The renderer receives the revocable view, not a cached raw coordinate.
      // Recheck immediately before handing over the state.
      if (_hasAuthorizedLocation(state)) {
        content = builder(context, state);
        semanticLabel = _mapSemanticLabel(state);
      } else {
        content = _fallback(context, hasAuthorizedLocation: false);
        semanticLabel =
            _fallbackSemanticLabel(state, hasAuthorizedLocation: false);
      }
    } else {
      content = _fallback(context, hasAuthorizedLocation: canPlot);
      semanticLabel = _fallbackSemanticLabel(
        state,
        hasAuthorizedLocation: canPlot,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Semantics(
        key: const ValueKey('rider-live-map-viewport-semantics'),
        container: true,
        image: true,
        label: semanticLabel,
        child: content,
      ),
    );
  }

  Widget _fallback(
    BuildContext context, {
    required bool hasAuthorizedLocation,
  }) {
    final theme = Theme.of(context);
    final rideXTheme = context.rideXTheme;
    final authorized =
        state.authorizationStatus == RiderLiveMapAuthorizationStatus.authorized;
    final visibleLocation =
        authorized && hasAuthorizedLocation && _hasAuthorizedLocation(state);
    final mapReady = mapConfigured && rendererBuilder != null;
    final title = !authorized
        ? 'Driver marker hidden'
        : visibleLocation
            ? 'Driver marker available'
            : _waitingTitle(state);
    final message = !authorized
        ? 'Trip authorization is unavailable. No Driver location is shown.'
        : mapReady
            ? 'Waiting for an authorized Driver location to plot.'
            : visibleLocation
                ? 'Map display is unavailable. The marker is not geographically plotted.'
                : 'Map display is unavailable. No route or location is invented.';

    return ColoredBox(
      key: const ValueKey('rider-live-map-fallback'),
      color: rideXTheme.mapBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                key: visibleLocation
                    ? const ValueKey('rider-live-map-fallback-marker')
                    : const ValueKey('rider-live-map-fallback-icon'),
                visibleLocation
                    ? Icons.location_on_rounded
                    : Icons.map_outlined,
                size: 36,
                color: visibleLocation
                    ? rideXTheme.mapVehicle
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _mapSemanticLabel(RiderLiveMapState state) {
    return state.hasLiveLocation
        ? 'Map with live authorized Driver marker.'
        : 'Map with authorized last-known Driver marker.';
  }

  String _fallbackSemanticLabel(
    RiderLiveMapState state, {
    required bool hasAuthorizedLocation,
  }) {
    final authorized =
        state.authorizationStatus == RiderLiveMapAuthorizationStatus.authorized;
    if (!authorized) {
      return 'Map unavailable. Driver marker hidden because Trip authorization is unavailable.';
    }
    if (hasAuthorizedLocation && _hasAuthorizedLocation(state)) {
      return 'Map unavailable. Authorized Driver marker is available but not geographically plotted.';
    }
    return 'Map unavailable. Waiting for an authorized Driver location.';
  }

  static bool _hasAuthorizedLocation(RiderLiveMapState state) {
    if (state.authorizationStatus !=
        RiderLiveMapAuthorizationStatus.authorized) {
      return false;
    }
    final locationStatus = state.locationStatus;
    if (locationStatus != RiderLiveMapLocationStatus.fresh &&
        locationStatus != RiderLiveMapLocationStatus.stale) {
      return false;
    }
    final point = state.driverLocation;
    return point != null &&
        point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180 &&
        state.authorizationStatus ==
            RiderLiveMapAuthorizationStatus.authorized &&
        state.driverLocation != null;
  }

  static String _waitingTitle(RiderLiveMapState state) {
    if (state.locationStatus == RiderLiveMapLocationStatus.gpsUnavailable ||
        state.gpsStatus == RiderLiveMapGpsStatus.unavailable) {
      return 'Driver GPS unavailable';
    }
    if (state.connectionStatus == RiderLiveMapConnectionStatus.offline) {
      return 'Offline';
    }
    return 'Waiting for Driver location';
  }
}

class _TrackingStatusCard extends StatelessWidget {
  const _TrackingStatusCard({required this.state});

  final RiderLiveMapState state;

  @override
  Widget build(BuildContext context) {
    final messages = _messages(state);
    final theme = Theme.of(context);
    return Semantics(
      key: const ValueKey('rider-live-map-status-semantics'),
      container: true,
      liveRegion: true,
      label: messages.join('. '),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tracking status', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                for (final message in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          message.icon,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(child: Text(message.text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_StatusMessage> _messages(RiderLiveMapState state) {
    if (state.authorizationStatus !=
        RiderLiveMapAuthorizationStatus.authorized) {
      return const [
        _StatusMessage(
          Icons.lock_outline_rounded,
          'Trip authorization unavailable. Driver location is hidden.',
        ),
      ];
    }

    final messages = <_StatusMessage>[];
    if (state.connectionStatus == RiderLiveMapConnectionStatus.offline) {
      messages.add(const _StatusMessage(
        Icons.wifi_off_rounded,
        'Offline. Location updates are paused.',
      ));
    }
    if (state.gpsStatus == RiderLiveMapGpsStatus.unavailable ||
        state.locationStatus == RiderLiveMapLocationStatus.gpsUnavailable) {
      messages.add(const _StatusMessage(
        Icons.gps_off_rounded,
        'Driver GPS is unavailable.',
      ));
    }
    if (state.locationStatus == RiderLiveMapLocationStatus.stale) {
      messages.add(const _StatusMessage(
        Icons.location_disabled_rounded,
        'Driver location is stale. Showing the last known position.',
      ));
    }
    if (state.hasLiveLocation) {
      messages.add(const _StatusMessage(
        Icons.my_location_rounded,
        'Driver location is live.',
      ));
    } else if (state.locationStatus == RiderLiveMapLocationStatus.unknown &&
        messages.isEmpty) {
      messages.add(const _StatusMessage(
        Icons.location_searching_rounded,
        'Waiting for the Driver location.',
      ));
    }
    return messages;
  }
}

class _RouteUnavailableCard extends StatelessWidget {
  const _RouteUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('rider-live-map-route-status'),
      container: true,
      label: 'Route unavailable. Route geometry and ETA are not available.',
      child: const Card(
        child: ListTile(
          leading: Icon(Icons.route_outlined),
          title: Text('Route unavailable'),
          subtitle: Text('Route geometry and ETA are not available.'),
        ),
      ),
    );
  }
}

final class _StatusMessage {
  const _StatusMessage(this.icon, this.text);

  final IconData icon;
  final String text;
}
