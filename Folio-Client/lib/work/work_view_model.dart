import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/http/scrape_events.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/wall/wall_page_view_model.dart';
import 'package:folio/work/work_ui_state.dart';

final workProvider = NotifierProvider.autoDispose.family<WorkViewModel, WorkUiState, int>(WorkViewModel.new);

class WorkViewModel extends Notifier<WorkUiState> {
  WorkViewModel(this.workId);

  final int workId;
  Timer? _reloadTimer;
  ScrapeBus? _boundBus;
  StreamSubscription<ScrapeJobRow>? _doneSub;
  StreamSubscription<PlaybackProgressEvent>? _progressSub;

  @override
  WorkUiState build() {
    ref.listen(sessionProvider, (previous, next) => _bindBus());
    _bindBus();
    ref.onDispose(() {
      _doneSub?.cancel();
      _progressSub?.cancel();
      _reloadTimer?.cancel();
    });
    Future.microtask(load);
    return const WorkUiState();
  }

  void _bindBus() {
    final bus = ref.read(sessionProvider.notifier).bus;
    if (identical(bus, _boundBus)) return;
    _doneSub?.cancel();
    _progressSub?.cancel();
    _boundBus = bus;
    if (bus == null) {
      _doneSub = null;
      _progressSub = null;
      return;
    }
    _doneSub = bus.done.stream.listen(_onMatchFinished);
    _progressSub = bus.playback.stream.listen((event) {
      if (event.workId != workId) return;
      final username = ref.read(sessionProvider).username;
      if (event.username.isNotEmpty && username.isNotEmpty && event.username != username) return;
      unawaited(refreshProgress());
    });
  }

  void _onMatchFinished(ScrapeJobRow job) {
    final current = state.work;
    final nextId = job.workId;
    if (current == null || job.matchStatus != 'matched' || nextId == null) return;
    if (nextId != workId) {
      if (!current.files.any((file) => file.id == job.fileId)) return;
      state = state.copyWith(redirectWorkId: nextId);
      return;
    }
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 400), () {
      if (!ref.mounted || state.work?.id != workId) return;
      unawaited(load());
    });
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> load() async {
    if (workId <= 0) {
      state = const WorkUiState(loading: false, error: '作品不存在');
      return;
    }
    state = state.copyWith(loading: state.work == null, clearError: true);
    try {
      final detail = await _api.get(ApiPath.works.one(workId), parser: jsonParser(WorkDetail.fromJson));
      if (!ref.mounted) return;
      final parts = await _collectionParts(detail.collectionExternalId);
      final progress = await fetchWorkProgress(_api, workId);
      final watchState = await _loadWatch();
      final wanted = await _loadWanted();
      if (!ref.mounted) return;
      state = WorkUiState(
        loading: false,
        work: detail,
        parts: parts,
        progress: progress,
        watchState: watchState,
        wanted: wanted,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  Future<String?> _loadWatch() async {
    try {
      final row = await _api.get(
        ApiPath.playback.workWatch(workId),
        parser: (data) => Map<String, dynamic>.from(data as Map),
      );
      return row['watchState']?.toString();
    } on ApiFailure {
      return null;
    }
  }

  Future<bool> _loadWanted() async {
    try {
      final row = await _api.get(
        ApiPath.watchlist.work(workId),
        parser: (data) => Map<String, dynamic>.from(data as Map),
      );
      return row['wanted'] == true;
    } on ApiFailure {
      return false;
    }
  }

  Future<void> setWanted(bool wanted) async {
    if (state.savingWant) return;
    state = state.copyWith(savingWant: true, clearError: true);
    try {
      final row = await _api.put(
        ApiPath.watchlist.work(workId),
        data: {'wanted': wanted},
        parser: (data) => Map<String, dynamic>.from(data as Map),
      );
      if (!ref.mounted) return;
      state = state.copyWith(wanted: row['wanted'] == true, savingWant: false, clearError: true);
      if (ref.exists(wallPageProvider)) {
        unawaited(ref.read(wallPageProvider.notifier).reloadWatchlist());
      }
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(savingWant: false, error: failure.message);
    }
  }

  Future<void> setWatched(bool watched) async {
    try {
      final row = await _api.put(
        ApiPath.playback.workWatch(workId),
        data: {'watched': watched},
        parser: (data) => Map<String, dynamic>.from(data as Map),
      );
      if (!ref.mounted) return;
      state = state.copyWith(watchState: row['watchState']?.toString(), clearError: true);
      await refreshProgress();
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(error: failure.message);
    }
  }

  Future<List<CollectionPart>> _collectionParts(String? collectionId) async {
    final id = collectionId?.trim() ?? '';
    if (id.isEmpty) return const [];
    try {
      final detail = await _api.get(
        ApiPath.collections.one(id),
        parser: jsonParser(CollectionDetail.fromJson),
      );
      final parts = detail.parts.toList();
      parts.sort((a, b) {
        final local = (b.hasLocalMedia ? 1 : 0).compareTo(a.hasLocalMedia ? 1 : 0);
        if (local != 0) return local;
        return _partTime(a).compareTo(_partTime(b));
      });
      return parts;
    } on ApiFailure {
      return const [];
    }
  }

  int _partTime(CollectionPart part) {
    final date = part.releaseDate?.trim();
    if (date != null && date.isNotEmpty) {
      final parsed = DateTime.tryParse(date);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    if (part.year != null) return DateTime.utc(part.year!).millisecondsSinceEpoch;
    return 1 << 62;
  }

  Future<void> refreshProgress() async {
    if (workId <= 0 || state.work == null) return;
    final progress = await fetchWorkProgress(_api, workId);
    if (!ref.mounted) return;
    state = state.copyWith(progress: progress);
  }

  Future<void> refresh() async {
    if (!state.canRefresh || workId <= 0) return;
    state = state.copyWith(refreshing: true, clearError: true);
    try {
      final detail = await _api.post(
        ApiPath.works.refresh(workId),
        parser: jsonParser(WorkDetail.fromJson),
      );
      if (!ref.mounted) return;
      final parts = await _collectionParts(detail.collectionExternalId);
      final progress = await fetchWorkProgress(_api, workId);
      final watchState = await _loadWatch();
      final wanted = await _loadWanted();
      if (!ref.mounted) return;
      state = WorkUiState(
        loading: false,
        work: detail,
        parts: parts,
        progress: progress,
        watchState: watchState,
        wanted: wanted,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(refreshing: false, error: failure.message);
    }
  }
}
