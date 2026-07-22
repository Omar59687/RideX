import 'package:flutter/animation.dart';

class AppMotion {
  const AppMotion._();

  static const instant = Duration(milliseconds: 80);
  static const fast = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 260);
  static const sheet = Duration(milliseconds: 340);
  static const route = Duration(milliseconds: 800);
  static const reduced = Duration(milliseconds: 1);

  static const standardCurve = Cubic(0.2, 0.8, 0.2, 1);
  static const enterCurve = Cubic(0.2, 0.85, 0.25, 1);
  static const exitCurve = Cubic(0.4, 0, 1, 1);
}
