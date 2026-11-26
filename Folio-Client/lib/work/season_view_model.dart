import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/http/scrape_events.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/work/season_ui_state.dart';

final seasonProvider = NotifierProvider.autoDispose.family<SeasonViewModel, SeasonUiState, SeasonKey>(SeasonViewModel.new);

class SeasonViewModel extends Notifier<SeasonUiState> {
  SeasonViewModel(this.key);

  final SeasonKey key;
  ScrapeBus? _boundBus;
  StreamSubscription<PlaybackProgressEvent>? _progressSub;

  @override
  SeasonUiState build() {
    ref.listen(sessionProvider, (previous, next) => _bindBus());
    _bindBus();
    ref.onDispose(() => _progressSub?.cancel());
    Future.microtask(load);
    return const SeasonUiState();
  }

  void _bindBus() {
    final bus = ref.read(sessionProvider.notifier).bus;
    if (identical(bus, _boundBus)) return;
    _progressSub?.cancel();
    _boundBus = bus;
    if (bus == null) {
      _progressSub = null;
      return;
    }
    _progressSub = bus.playback.stream.listen((event) {
      if (event.workId != key.workId) return;
      final username = ref.read(sessionProvider).username;
      if (event.username.isNotEmpty && username.isNotEmpty && event.username != username) return;
      unawaited(refreshProgress());
    });
  }

  Future<void> load() async {
    if (key.workId <= 0) {
      state = const SeasonUiState(loading: false, error: '作品不存在');
      return;
    }
    state = state.copyWith(loading: state.detail == null, clearError: true);
    try {
      final api = ref.read(apiClientProvider);
      final detail = await api.get(
        ApiPath.works.season(key.workId, key.seasonNumber),
        parser: jsonParser(SeasonDetail.fromJson),
      );
      final progress = await fetchWorkProgress(api, key.workId);
      if (!ref.mounted) return;
      state = SeasonUiState(loading: false, detail: detail, progress: progress);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  Future<void> refreshProgress() async {
    if (key.workId <= 0 || state.detail == null) return;
    final progress = await fetchWorkProgress(ref.read(apiClientProvider), key.workId);
    if (!ref.mounted) return;
    state = state.copyWith(progress: progress);
  }
}
