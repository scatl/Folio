import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/work/episode_ui_state.dart';

final episodeProvider = NotifierProvider.autoDispose.family<EpisodeViewModel, EpisodeUiState, EpisodeKey>(
  EpisodeViewModel.new,
);

class EpisodeViewModel extends Notifier<EpisodeUiState> {
  EpisodeViewModel(this.key);

  final EpisodeKey key;

  @override
  EpisodeUiState build() {
    Future.microtask(load);
    return const EpisodeUiState();
  }

  Future<void> load() async {
    if (key.workId <= 0 || key.seasonNumber < 0 || key.episodeNumber <= 0) {
      state = const EpisodeUiState(loading: false, error: '集不存在');
      return;
    }
    state = state.copyWith(loading: state.detail == null, clearError: true);
    try {
      final detail = await ref.read(apiClientProvider).get(
            ApiPath.works.episode(key.workId, key.seasonNumber, key.episodeNumber),
            parser: jsonParser(EpisodeDetail.fromJson),
          );
      if (!ref.mounted) return;
      state = EpisodeUiState(loading: false, detail: detail);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }
}
