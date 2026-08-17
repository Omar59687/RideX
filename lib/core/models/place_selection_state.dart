import 'package:equatable/equatable.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/place_prediction.dart';

enum LocationEndpoint { pickup, destination }

enum PlaceSearchStatus {
  idle,
  debouncing,
  loading,
  results,
  empty,
  resolving,
  selected,
  failure,
}

class PlaceSelectionState extends Equatable {
  const PlaceSelectionState({
    this.query = '',
    this.status = PlaceSearchStatus.idle,
    this.predictions = const [],
    this.selected,
    this.message,
  });

  final String query;
  final PlaceSearchStatus status;
  final List<PlacePrediction> predictions;
  final RideLocation? selected;
  final String? message;

  bool get isResolving => status == PlaceSearchStatus.resolving;
  bool get hasUncommittedQuery => query.trim().isNotEmpty;

  PlaceSelectionState copyWith({
    String? query,
    PlaceSearchStatus? status,
    List<PlacePrediction>? predictions,
    RideLocation? selected,
    String? message,
    bool clearPredictions = false,
    bool clearSelected = false,
    bool clearMessage = false,
  }) {
    return PlaceSelectionState(
      query: query ?? this.query,
      status: status ?? this.status,
      predictions:
          clearPredictions ? const [] : predictions ?? this.predictions,
      selected: clearSelected ? null : selected ?? this.selected,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [query, status, predictions, selected, message];
}
