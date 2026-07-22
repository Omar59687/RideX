import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

enum MapMarkerType { pickup, destination, vehicle }

enum MapLiveState { idle, searching, enRoute, arriving }

@immutable
class MapMarker {
  const MapMarker({
    required this.position,
    required this.type,
    this.label,
  });

  /// A normalized position where both axes range from 0 to 1.
  final Offset position;
  final MapMarkerType type;
  final String? label;
}

class MapPlaceholder extends StatefulWidget {
  const MapPlaceholder({
    super.key,
    this.showRoute = true,
    this.showCars = true,
    this.height,
    this.routePoints = const [],
    this.markers = const [],
    this.liveState = MapLiveState.idle,
    this.routeProgress = 1,
    this.borderRadius = AppRadii.sheet,
    this.semanticLabel = 'Stylized ride map',
  });

  final bool showRoute;
  final bool showCars;
  final double? height;
  final List<Offset> routePoints;
  final List<MapMarker> markers;
  final MapLiveState liveState;
  final double routeProgress;
  final double borderRadius;
  final String semanticLabel;

  @override
  State<MapPlaceholder> createState() => _MapPlaceholderState();
}

class _MapPlaceholderState extends State<MapPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.route,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MapPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveState != widget.liveState) _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.liveState != MapLiveState.idle && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Semantics(
      image: true,
      label: widget.semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: ColoredBox(
          color: context.rideXTheme.mapBackground,
          child: CustomPaint(
            painter: _MapPlaceholderPainter(
              rideXTheme: context.rideXTheme,
              colorScheme: theme.colorScheme,
              showRoute: widget.showRoute,
              showCars: widget.showCars,
              routePoints: widget.routePoints,
              markers: widget.markers,
              liveState: widget.liveState,
              routeProgress: widget.routeProgress.clamp(0, 1),
              animation: _controller,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    if (widget.height != null) {
      return SizedBox(height: widget.height, child: content);
    }
    return AspectRatio(aspectRatio: 0.86, child: content);
  }
}

class _MapPlaceholderPainter extends CustomPainter {
  _MapPlaceholderPainter({
    required this.rideXTheme,
    required this.colorScheme,
    required this.showRoute,
    required this.showCars,
    required this.routePoints,
    required this.markers,
    required this.liveState,
    required this.routeProgress,
    required this.animation,
  }) : super(repaint: animation);

  final RideXTheme rideXTheme;
  final ColorScheme colorScheme;
  final bool showRoute;
  final bool showCars;
  final List<Offset> routePoints;
  final List<MapMarker> markers;
  final MapLiveState liveState;
  final double routeProgress;
  final Animation<double> animation;

  static const _defaultRoute = [
    Offset(0.22, 0.78),
    Offset(0.34, 0.65),
    Offset(0.42, 0.54),
    Offset(0.48, 0.35),
    Offset(0.7, 0.2),
  ];

  static const _defaultCars = [
    Offset(0.18, 0.3),
    Offset(0.82, 0.32),
    Offset(0.72, 0.62),
    Offset(0.36, 0.2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _drawDistricts(canvas, size);
    _drawRoads(canvas, size);

    final points = routePoints.length >= 2 ? routePoints : _defaultRoute;
    if (showRoute) _drawRoute(canvas, size, points);
    if (showCars) {
      for (final position in _defaultCars) {
        _drawVehicle(canvas, _resolve(position, size), size);
      }
    }

    final effectiveMarkers = markers.isEmpty
        ? [
            MapMarker(position: points.first, type: MapMarkerType.pickup),
            MapMarker(position: points.last, type: MapMarkerType.destination),
          ]
        : markers;
    for (final marker in effectiveMarkers) {
      if (marker.type == MapMarkerType.vehicle) {
        _drawVehicle(canvas, _resolve(marker.position, size), size);
      } else {
        _drawMarker(canvas, _resolve(marker.position, size), marker.type, size);
      }
    }
  }

  void _drawDistricts(Canvas canvas, Size size) {
    final paint = Paint()..color = rideXTheme.mapDistrict;
    final districts = [
      Rect.fromLTWH(size.width * 0.04, size.height * 0.07, size.width * 0.3,
          size.height * 0.18),
      Rect.fromLTWH(size.width * 0.57, size.height * 0.42, size.width * 0.36,
          size.height * 0.22),
      Rect.fromLTWH(size.width * 0.08, size.height * 0.66, size.width * 0.38,
          size.height * 0.24),
    ];
    for (final district in districts) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(district, const Radius.circular(22)),
        paint,
      );
    }
  }

  void _drawRoads(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = rideXTheme.mapRoadOutline
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final road = Paint()
      ..color = rideXTheme.mapRoad
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final roads = [
      Path()
        ..moveTo(-size.width * 0.05, size.height * 0.28)
        ..cubicTo(size.width * 0.28, size.height * 0.18, size.width * 0.58,
            size.height * 0.45, size.width * 1.05, size.height * 0.34),
      Path()
        ..moveTo(size.width * 0.18, -size.height * 0.05)
        ..cubicTo(size.width * 0.28, size.height * 0.34, size.width * 0.18,
            size.height * 0.68, size.width * 0.38, size.height * 1.05),
      Path()
        ..moveTo(size.width * 0.68, -size.height * 0.05)
        ..cubicTo(size.width * 0.58, size.height * 0.36, size.width * 0.82,
            size.height * 0.62, size.width * 0.72, size.height * 1.05),
    ];
    for (final path in roads) {
      canvas.drawPath(path, outline);
      canvas.drawPath(path, road);
    }
  }

  void _drawRoute(Canvas canvas, Size size, List<Offset> points) {
    final route = Path()
      ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
    for (final point in points.skip(1)) {
      route.lineTo(point.dx * size.width, point.dy * size.height);
    }
    final halo = Paint()
      ..color = rideXTheme.mapRouteHalo
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(route, halo);

    final routePaint = Paint()
      ..shader = rideXTheme.routeGradient.createShader(Offset.zero & size)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (routeProgress >= 1) {
      canvas.drawPath(route, routePaint);
      return;
    }
    for (final metric in route.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * routeProgress),
        routePaint,
      );
    }
  }

  void _drawMarker(
    Canvas canvas,
    Offset center,
    MapMarkerType type,
    Size size,
  ) {
    final color = type == MapMarkerType.pickup
        ? rideXTheme.pickup
        : rideXTheme.destination;
    final scale = (size.shortestSide / 320).clamp(0.82, 1.25);
    if (liveState != MapLiveState.idle) {
      canvas.drawCircle(
        center,
        (14 + animation.value * 8) * scale,
        Paint()..color = color.withValues(alpha: 0.18 * (1 - animation.value)),
      );
    }
    canvas.drawCircle(center, 12 * scale, Paint()..color = color);
    canvas.drawCircle(
      center,
      5 * scale,
      Paint()..color = colorScheme.surface,
    );
  }

  void _drawVehicle(Canvas canvas, Offset center, Size size) {
    final scale = (size.shortestSide / 320).clamp(0.8, 1.2);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 18 * scale, height: 11 * scale),
      Radius.circular(4 * scale),
    );
    canvas.drawRRect(rect, Paint()..color = rideXTheme.mapVehicle);
    final window = Rect.fromCenter(
      center: center.translate(0, -1 * scale),
      width: 8 * scale,
      height: 4 * scale,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(1.5 * scale)),
      Paint()..color = rideXTheme.routeLive,
    );
  }

  Offset _resolve(Offset normalized, Size size) {
    return Offset(normalized.dx * size.width, normalized.dy * size.height);
  }

  @override
  bool shouldRepaint(covariant _MapPlaceholderPainter oldDelegate) {
    return oldDelegate.rideXTheme != rideXTheme ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.showRoute != showRoute ||
        oldDelegate.showCars != showCars ||
        oldDelegate.routePoints != routePoints ||
        oldDelegate.markers != markers ||
        oldDelegate.liveState != liveState ||
        oldDelegate.routeProgress != routeProgress;
  }
}
