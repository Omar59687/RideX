import 'package:flutter/material.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

enum VehicleSilhouetteType { car, taxi, suv }

class VehicleSilhouette extends StatelessWidget {
  const VehicleSilhouette({
    super.key,
    this.type = VehicleSilhouetteType.car,
    this.width = 72,
    this.height = 40,
    this.color,
    this.semanticLabel,
  });

  final VehicleSilhouetteType type;
  final double width;
  final double height;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      image: true,
      label: semanticLabel ?? '${type.name} vehicle',
      child: CustomPaint(
        size: Size(width, height),
        painter: _VehicleSilhouettePainter(
          type: type,
          bodyColor: color ?? context.rideXTheme.brandEmphasis,
          detailColor: theme.colorScheme.surface,
          wheelColor: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _VehicleSilhouettePainter extends CustomPainter {
  const _VehicleSilhouettePainter({
    required this.type,
    required this.bodyColor,
    required this.detailColor,
    required this.wheelColor,
  });

  final VehicleSilhouetteType type;
  final Color bodyColor;
  final Color detailColor;
  final Color wheelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = bodyColor;
    final details = Paint()..color = detailColor.withValues(alpha: 0.75);
    final wheel = Paint()..color = wheelColor;
    final bodyTop = type == VehicleSilhouetteType.suv ? 0.27 : 0.38;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.06,
        size.height * 0.45,
        size.width * 0.88,
        size.height * 0.35,
      ),
      Radius.circular(size.height * 0.12),
    );
    canvas.drawRRect(bodyRect, body);

    final roof = Path()
      ..moveTo(size.width * 0.25, size.height * 0.48)
      ..lineTo(size.width * 0.37, size.height * bodyTop)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * (bodyTop - 0.08),
        size.width * 0.66,
        size.height * bodyTop,
      )
      ..lineTo(size.width * 0.78, size.height * 0.48)
      ..close();
    canvas.drawPath(roof, body);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.39, size.height * (bodyTop + 0.02))
        ..lineTo(size.width * 0.48, size.height * 0.46)
        ..lineTo(size.width * 0.31, size.height * 0.46)
        ..close(),
      details,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.52, size.height * (bodyTop + 0.01))
        ..lineTo(size.width * 0.65, size.height * (bodyTop + 0.03))
        ..lineTo(size.width * 0.73, size.height * 0.46)
        ..lineTo(size.width * 0.52, size.height * 0.46)
        ..close(),
      details,
    );
    if (type == VehicleSilhouetteType.taxi) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * 0.52, size.height * 0.2),
            width: size.width * 0.18,
            height: size.height * 0.1,
          ),
          Radius.circular(size.height * 0.03),
        ),
        body,
      );
    }
    for (final x in [0.25, 0.75]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * 0.8),
        size.height * 0.11,
        wheel,
      );
      canvas.drawCircle(
        Offset(size.width * x, size.height * 0.8),
        size.height * 0.045,
        details,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VehicleSilhouettePainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.bodyColor != bodyColor ||
        oldDelegate.detailColor != detailColor ||
        oldDelegate.wheelColor != wheelColor;
  }
}
