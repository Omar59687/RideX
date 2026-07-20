import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';

class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({
    super.key,
    this.showRoute = true,
    this.showCars = true,
    this.height,
  });

  final bool showRoute;
  final bool showCars;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(28),
      ),
      child: CustomPaint(
        painter:
            _MapPlaceholderPainter(showRoute: showRoute, showCars: showCars),
        child: const SizedBox.expand(),
      ),
    );

    if (height != null) {
      return SizedBox(height: height, child: content);
    }

    return AspectRatio(
      aspectRatio: 0.86,
      child: content,
    );
  }
}

class _MapPlaceholderPainter extends CustomPainter {
  _MapPlaceholderPainter({required this.showRoute, required this.showCars});

  final bool showRoute;
  final bool showCars;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 0.1; i < 1; i += 0.18) {
      canvas.drawLine(Offset(size.width * i, 0),
          Offset(size.width * i, size.height), gridPaint);
      canvas.drawLine(Offset(0, size.height * i),
          Offset(size.width, size.height * i), gridPaint);
    }
    final routePaint = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final route = Path()
      ..moveTo(size.width * 0.25, size.height * 0.72)
      ..lineTo(size.width * 0.40, size.height * 0.58)
      ..lineTo(size.width * 0.46, size.height * 0.36)
      ..lineTo(size.width * 0.72, size.height * 0.22);
    if (showRoute) canvas.drawPath(route, routePaint);
    if (showCars) {
      for (final offset in [
        Offset(size.width * 0.18, size.height * 0.30),
        Offset(size.width * 0.82, size.height * 0.32),
        Offset(size.width * 0.72, size.height * 0.62),
        Offset(size.width * 0.36, size.height * 0.20),
      ]) {
        _drawCar(canvas, offset);
      }
    }
    _drawPin(
        canvas, Offset(size.width * 0.25, size.height * 0.72), AppColors.info);
    _drawPin(canvas, Offset(size.width * 0.72, size.height * 0.22),
        AppColors.accent);
  }

  void _drawCar(Canvas canvas, Offset center) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 16, height: 9),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.graphite);
    canvas.drawCircle(
        center.translate(-4, 5), 2, Paint()..color = AppColors.info);
    canvas.drawCircle(
        center.translate(4, 5), 2, Paint()..color = AppColors.info);
  }

  void _drawPin(Canvas canvas, Offset center, Color color) {
    final paint = Paint()..color = color;
    canvas.drawCircle(center, 12, paint);
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MapPlaceholderPainter oldDelegate) =>
      oldDelegate.showRoute != showRoute || oldDelegate.showCars != showCars;
}
