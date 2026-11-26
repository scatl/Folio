import 'package:folio/api/entity/models.dart';

class EpisodeKey {
  const EpisodeKey(this.workId, this.seasonNumber, this.episodeNumber);

  final int workId;
  final int seasonNumber;
  final int episodeNumber;

  @override
  bool operator ==(Object other) =>
      other is EpisodeKey &&
      other.workId == workId &&
      other.seasonNumber == seasonNumber &&
      other.episodeNumber == episodeNumber;

  @override
  int get hashCode => Object.hash(workId, seasonNumber, episodeNumber);
}

class EpisodeUiState {
  const EpisodeUiState({
    this.loading = true,
    this.error,
    this.detail,
  });

  final bool loading;
  final String? error;
  final EpisodeDetail? detail;

  EpisodeUiState copyWith({
    bool? loading,
    String? error,
    EpisodeDetail? detail,
    bool clearError = false,
  }) {
    return EpisodeUiState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      detail: detail ?? this.detail,
    );
  }
}
