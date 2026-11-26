import 'package:folio/api/entity/models.dart';

class WorkUiState {
  const WorkUiState({
    this.loading = true,
    this.refreshing = false,
    this.work,
    this.parts = const [],
    this.progress,
    this.watchState,
    this.wanted = false,
    this.savingWant = false,
    this.error,
    this.redirectWorkId,
  });

  final bool loading;
  final bool refreshing;
  final WorkDetail? work;
  final List<CollectionPart> parts;
  final PlaybackProgress? progress;
  final String? watchState;
  final bool wanted;
  final bool savingWant;
  final String? error;
  final int? redirectWorkId;

  bool get canRefresh {
    final current = work;
    if (current == null || refreshing) return false;
    return current.externalIds.any((item) => item.provider.trim().toLowerCase() == 'tmdb');
  }

  WorkUiState copyWith({
    bool? loading,
    bool? refreshing,
    WorkDetail? work,
    List<CollectionPart>? parts,
    Object? progress = _keep,
    Object? watchState = _keep,
    bool? wanted,
    bool? savingWant,
    String? error,
    bool clearError = false,
    int? redirectWorkId,
  }) {
    return WorkUiState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      work: work ?? this.work,
      parts: parts ?? this.parts,
      progress: progress == _keep ? this.progress : progress as PlaybackProgress?,
      watchState: watchState == _keep ? this.watchState : watchState as String?,
      wanted: wanted ?? this.wanted,
      savingWant: savingWant ?? this.savingWant,
      error: clearError ? null : error ?? this.error,
      redirectWorkId: redirectWorkId ?? this.redirectWorkId,
    );
  }
}

const _keep = Object();
