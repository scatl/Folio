import 'package:folio/api/entity/models.dart';

class SeasonKey {
  const SeasonKey(this.workId, this.seasonNumber);

  final int workId;
  final int seasonNumber;

  @override
  bool operator ==(Object other) => other is SeasonKey && other.workId == workId && other.seasonNumber == seasonNumber;

  @override
  int get hashCode => Object.hash(workId, seasonNumber);
}

class SeasonUiState {
  const SeasonUiState({this.loading = true, this.detail, this.progress, this.error});

  final bool loading;
  final SeasonDetail? detail;
  final PlaybackProgress? progress;
  final String? error;

  SeasonUiState copyWith({
    bool? loading,
    SeasonDetail? detail,
    Object? progress = _keep,
    String? error,
    bool clearError = false,
  }) {
    return SeasonUiState(
      loading: loading ?? this.loading,
      detail: detail ?? this.detail,
      progress: progress == _keep ? this.progress : progress as PlaybackProgress?,
      error: clearError ? null : error ?? this.error,
    );
  }
}

const _keep = Object();
