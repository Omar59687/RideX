import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_colors.dart';

@immutable
class RideXTheme extends ThemeExtension<RideXTheme> {
  const RideXTheme({
    required this.surfaceLive,
    required this.pickup,
    required this.destination,
    required this.routeLive,
    required this.brandEmphasis,
    required this.brandDepth,
    required this.success,
    required this.warning,
    required this.information,
    required this.focus,
    required this.disabledBackground,
    required this.disabledContent,
    required this.brandGradient,
    required this.routeGradient,
    required this.rewardGradient,
    required this.cardShadows,
    required this.floatingShadows,
    required this.sheetShadows,
    required this.mapBackground,
    required this.mapDistrict,
    required this.mapRoad,
    required this.mapRoadOutline,
    required this.mapLabel,
    required this.mapRouteHalo,
    required this.mapVehicle,
  });

  final Color surfaceLive;
  final Color pickup;
  final Color destination;
  final Color routeLive;
  final Color brandEmphasis;
  final Color brandDepth;
  final Color success;
  final Color warning;
  final Color information;
  final Color focus;
  final Color disabledBackground;
  final Color disabledContent;
  final LinearGradient brandGradient;
  final LinearGradient routeGradient;
  final LinearGradient rewardGradient;
  final List<BoxShadow> cardShadows;
  final List<BoxShadow> floatingShadows;
  final List<BoxShadow> sheetShadows;
  final Color mapBackground;
  final Color mapDistrict;
  final Color mapRoad;
  final Color mapRoadOutline;
  final Color mapLabel;
  final Color mapRouteHalo;
  final Color mapVehicle;

  static const light = RideXTheme(
    surfaceLive: AppColors.aqua50,
    pickup: AppColors.coral700,
    destination: AppColors.midnight700,
    routeLive: AppColors.aqua700,
    brandEmphasis: AppColors.iris700,
    brandDepth: AppColors.violet500,
    success: Color(0xFF28765E),
    warning: Color(0xFF9A5B00),
    information: AppColors.iris700,
    focus: AppColors.aqua700,
    disabledBackground: AppColors.pearl300,
    disabledContent: AppColors.pearl700,
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.iris500, AppColors.violet500],
    ),
    routeGradient: LinearGradient(
      colors: [AppColors.iris500, AppColors.aqua500],
    ),
    rewardGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.coral500, Color(0xFFFFAA91)],
    ),
    cardShadows: [
      BoxShadow(
        color: Color(0x0E28234A),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    floatingShadows: [
      BoxShadow(
        color: Color(0x1C625BF6),
        offset: Offset(0, 10),
        blurRadius: 28,
      ),
    ],
    sheetShadows: [
      BoxShadow(
        color: Color(0x1F28234A),
        offset: Offset(0, -14),
        blurRadius: 40,
      ),
    ],
    mapBackground: AppColors.pearl50,
    mapDistrict: Color(0xB3FFFFFF),
    mapRoad: Color(0xFFD9D5E2),
    mapRoadOutline: Color(0xBFFFFFFF),
    mapLabel: Color(0xFF6F6B7D),
    mapRouteHalo: Color(0x33625BF6),
    mapVehicle: AppColors.midnight700,
  );

  static const dark = RideXTheme(
    surfaceLive: Color(0xFF203E49),
    pickup: AppColors.coral300,
    destination: AppColors.iris50,
    routeLive: AppColors.aqua300,
    brandEmphasis: AppColors.iris100,
    brandDepth: AppColors.violet300,
    success: Color(0xFF73C5A7),
    warning: Color(0xFFF5BC65),
    information: AppColors.iris300,
    focus: AppColors.aqua300,
    disabledBackground: Color(0xFF3C3856),
    disabledContent: AppColors.midnight300,
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.iris500, AppColors.violet500],
    ),
    routeGradient: LinearGradient(
      colors: [AppColors.violet500, AppColors.aqua500],
    ),
    rewardGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.coral700, AppColors.coral300],
    ),
    cardShadows: [
      BoxShadow(
        color: Color(0x5219162B),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    floatingShadows: [
      BoxShadow(
        color: Color(0x38625BF6),
        offset: Offset(0, 10),
        blurRadius: 28,
      ),
    ],
    sheetShadows: [
      BoxShadow(
        color: Color(0x6619162B),
        offset: Offset(0, -14),
        blurRadius: 40,
      ),
    ],
    mapBackground: AppColors.midnight900,
    mapDistrict: Color(0xFF332C5C),
    mapRoad: AppColors.midnight500,
    mapRoadOutline: Color(0x335F5A78),
    mapLabel: Color(0xFFC5C0D2),
    mapRouteHalo: Color(0x4DA8A4FF),
    mapVehicle: AppColors.iris50,
  );

  @override
  RideXTheme copyWith({
    Color? surfaceLive,
    Color? pickup,
    Color? destination,
    Color? routeLive,
    Color? brandEmphasis,
    Color? brandDepth,
    Color? success,
    Color? warning,
    Color? information,
    Color? focus,
    Color? disabledBackground,
    Color? disabledContent,
    LinearGradient? brandGradient,
    LinearGradient? routeGradient,
    LinearGradient? rewardGradient,
    List<BoxShadow>? cardShadows,
    List<BoxShadow>? floatingShadows,
    List<BoxShadow>? sheetShadows,
    Color? mapBackground,
    Color? mapDistrict,
    Color? mapRoad,
    Color? mapRoadOutline,
    Color? mapLabel,
    Color? mapRouteHalo,
    Color? mapVehicle,
  }) {
    return RideXTheme(
      surfaceLive: surfaceLive ?? this.surfaceLive,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      routeLive: routeLive ?? this.routeLive,
      brandEmphasis: brandEmphasis ?? this.brandEmphasis,
      brandDepth: brandDepth ?? this.brandDepth,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      information: information ?? this.information,
      focus: focus ?? this.focus,
      disabledBackground: disabledBackground ?? this.disabledBackground,
      disabledContent: disabledContent ?? this.disabledContent,
      brandGradient: brandGradient ?? this.brandGradient,
      routeGradient: routeGradient ?? this.routeGradient,
      rewardGradient: rewardGradient ?? this.rewardGradient,
      cardShadows: cardShadows ?? this.cardShadows,
      floatingShadows: floatingShadows ?? this.floatingShadows,
      sheetShadows: sheetShadows ?? this.sheetShadows,
      mapBackground: mapBackground ?? this.mapBackground,
      mapDistrict: mapDistrict ?? this.mapDistrict,
      mapRoad: mapRoad ?? this.mapRoad,
      mapRoadOutline: mapRoadOutline ?? this.mapRoadOutline,
      mapLabel: mapLabel ?? this.mapLabel,
      mapRouteHalo: mapRouteHalo ?? this.mapRouteHalo,
      mapVehicle: mapVehicle ?? this.mapVehicle,
    );
  }

  @override
  RideXTheme lerp(covariant RideXTheme? other, double t) {
    if (other == null) return this;
    return RideXTheme(
      surfaceLive: Color.lerp(surfaceLive, other.surfaceLive, t)!,
      pickup: Color.lerp(pickup, other.pickup, t)!,
      destination: Color.lerp(destination, other.destination, t)!,
      routeLive: Color.lerp(routeLive, other.routeLive, t)!,
      brandEmphasis: Color.lerp(brandEmphasis, other.brandEmphasis, t)!,
      brandDepth: Color.lerp(brandDepth, other.brandDepth, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      information: Color.lerp(information, other.information, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      disabledBackground:
          Color.lerp(disabledBackground, other.disabledBackground, t)!,
      disabledContent: Color.lerp(disabledContent, other.disabledContent, t)!,
      brandGradient:
          LinearGradient.lerp(brandGradient, other.brandGradient, t)!,
      routeGradient:
          LinearGradient.lerp(routeGradient, other.routeGradient, t)!,
      rewardGradient:
          LinearGradient.lerp(rewardGradient, other.rewardGradient, t)!,
      cardShadows: BoxShadow.lerpList(cardShadows, other.cardShadows, t)!,
      floatingShadows:
          BoxShadow.lerpList(floatingShadows, other.floatingShadows, t)!,
      sheetShadows: BoxShadow.lerpList(sheetShadows, other.sheetShadows, t)!,
      mapBackground: Color.lerp(mapBackground, other.mapBackground, t)!,
      mapDistrict: Color.lerp(mapDistrict, other.mapDistrict, t)!,
      mapRoad: Color.lerp(mapRoad, other.mapRoad, t)!,
      mapRoadOutline: Color.lerp(mapRoadOutline, other.mapRoadOutline, t)!,
      mapLabel: Color.lerp(mapLabel, other.mapLabel, t)!,
      mapRouteHalo: Color.lerp(mapRouteHalo, other.mapRouteHalo, t)!,
      mapVehicle: Color.lerp(mapVehicle, other.mapVehicle, t)!,
    );
  }
}

extension RideXThemeContext on BuildContext {
  RideXTheme get rideXTheme => Theme.of(this).extension<RideXTheme>()!;
}
