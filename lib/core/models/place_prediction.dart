import 'package:equatable/equatable.dart';

class PlacePrediction extends Equatable {
  const PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;

  String get description =>
      secondaryText.isEmpty ? primaryText : '$primaryText, $secondaryText';

  @override
  List<Object?> get props => [placeId, primaryText, secondaryText];
}
