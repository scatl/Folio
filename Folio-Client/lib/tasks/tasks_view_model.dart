import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/http/scrape_events.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/tasks/tasks_ui_state.dart';

final tasksProvider = NotifierProvider.autoDispose<TasksViewModel, TasksUiState>(
  TasksViewModel.new,
);

class TasksViewModel extends Notifier<TasksUiState> {
  ScrapeBus? _boundBus;
  StreamSubscription<ScrapeJobRow>? _jobSub;
  StreamSubscription<int>? _deletedSub;

  @override
  TasksUiState build() {
    ref.listen(sessionProvider, (previous, next) => _bindBus());
    _bindBus();
    ref.onDispose(() {
      _jobSub?.cancel();
      _deletedSub?.cancel();
    });
    Future.microtask(() => fetch(0, append: false));
    return const TasksUiState();
  }

  void _bindBus() {
    final bus = ref.read(sessionProvider.notifier).bus;
    if (identical(bus, _boundBus)) return;
    _jobSub?.cancel();
    _deletedSub?.cancel();
    _boundBus = bus;
    if (bus == null) {
      _jobSub = null;
      _deletedSub = null;
      return;
    }
    _jobSub = bus.jobs.stream.listen(onJob);
    _deletedSub = bus.deleted.stream.listen(onDeleted);
  }

  ApiClient get _api => ref.read(apiClientProvider);

  final _fetchGen = <String, int>{};

  Future<void> fetch(int nextPage, {required bool append, bool silent = false, String? status}) async {
    final requested = status ?? state.status;
    final current = state.slice(requested);
    if (append && (!current.hasMore || current.loading || current.loadingMore)) return;
    final gen = (_fetchGen[requested] ?? 0) + 1;
    _fetchGen[requested] = gen;
    if (append) {
      state = state.updateSlice(requested, current.copyWith(loadingMore: true));
    } else if (!silent && current.items.isEmpty) {
      state = state.updateSlice(requested, current.copyWith(loading: true, loadingMore: false, error: null));
    } else if (!silent) {
      state = state.updateSlice(requested, current.copyWith(loadingMore: false, error: null));
    }
    try {
      final data = await _api.get(
        ApiPath.scrapeJobs.list,
        queryParameters: {
          if (requested.isNotEmpty) 'status': requested,
          'page': nextPage,
          'size': 50,
        },
        parser: (data) => PageResult.fromJson(Map<String, dynamic>.from(data as Map), ScrapeJobRow.fromJson),
      );
      if (!ref.mounted || _fetchGen[requested] != gen) return;
      final latest = state.slice(requested);
      state = state.updateSlice(
        requested,
        latest.copyWith(
          items: append ? [...latest.items, ...data.items] : data.items,
          page: data.page,
          total: data.total,
          totalPages: data.totalPages,
          loaded: true,
          loading: false,
          loadingMore: false,
          error: null,
        ),
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure) || _fetchGen[requested] != gen) return;
      if (!silent) {
        final latest = state.slice(requested);
        state = state.updateSlice(
          requested,
          latest.copyWith(
            error: failure.message,
            items: append ? latest.items : const [],
            loaded: false,
            loading: false,
            loadingMore: false,
          ),
        );
      }
    } finally {
      if (ref.mounted && _fetchGen[requested] == gen) {
        final latest = state.slice(requested);
        state = state.updateSlice(
          requested,
          latest.copyWith(
            loading: append || silent ? latest.loading : false,
            loadingMore: append ? false : latest.loadingMore,
          ),
        );
      }
    }
  }

  void loadMore([String? status]) {
    final key = status ?? state.status;
    final slice = state.slice(key);
    if (!slice.hasMore || slice.loading || slice.loadingMore) return;
    unawaited(fetch(slice.page + 1, append: true, status: key));
  }

  void setStatus(String value) {
    if (state.status == value) return;
    state = state.copyWith(status: value);
    if (state.slice(value).loaded) return;
    unawaited(fetch(0, append: false, status: value));
  }

  bool matchesFilter(String status, ScrapeJobRow job) {
    if (job.matchStatus == 'matched') return false;
    switch (status) {
      case '':
        return true;
      case 'queued':
        return job.status == 'queued';
      case 'running':
        return job.status == 'running' && job.matchStatus != 'matched';
      case 'needs_review':
        return job.matchStatus == 'needs_review';
      case 'failed':
        return job.matchStatus != 'needs_review' &&
            job.matchStatus != 'matched' &&
            (job.status == 'failed' || job.matchStatus == 'failed');
      default:
        return true;
    }
  }

  void onJob(ScrapeJobRow job) {
    state = _mapLoaded((status, slice) => _applyJob(slice, status, job));
  }

  void onDeleted(int id) {
    state = _mapLoaded((status, slice) => _without(slice, id));
  }

  TaskSlice _applyJob(TaskSlice slice, String status, ScrapeJobRow job) {
    final index = slice.items.indexWhere((item) => item.id == job.id);
    if (!matchesFilter(status, job)) {
      if (index < 0) return slice;
      return slice.copyWith(
        items: slice.items.where((item) => item.id != job.id).toList(),
        total: (slice.total - 1).clamp(0, 1 << 30),
      );
    }
    if (index >= 0) {
      final next = [...slice.items];
      next[index] = job;
      return slice.copyWith(items: next);
    }
    return slice.copyWith(items: [job, ...slice.items], total: slice.total + 1);
  }

  TaskSlice _without(TaskSlice slice, int id) {
    final before = slice.items.length;
    final items = slice.items.where((item) => item.id != id).toList();
    if (items.length == before) return slice;
    return slice.copyWith(items: items, total: (slice.total - 1).clamp(0, 1 << 30));
  }

  TasksUiState _mapLoaded(TaskSlice Function(String status, TaskSlice slice) apply) {
    final next = <String, TaskSlice>{};
    for (final entry in state.slices.entries) {
      next[entry.key] = entry.value.loaded ? apply(entry.key, entry.value) : entry.value;
    }
    return state.copyWith(slices: next);
  }

  Future<void> remove(ScrapeJobRow job) async {
    if (!job.canDelete || state.deletingId != null || state.retryingId != null) return;
    state = state.copyWith(deletingId: job.id, actionError: null);
    try {
      await _api.delete<Object?>(ApiPath.scrapeJobs.job(job.id));
      if (!ref.mounted) return;
      state = _mapLoaded((status, slice) => _without(slice, job.id)).copyWith(deletingId: null);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(deletingId: null, actionError: failure.message);
    }
  }

  Future<void> retry(ScrapeJobRow job) async {
    if (!job.canRetry || state.retryingId != null || state.deletingId != null) return;
    state = state.copyWith(retryingId: job.id, actionError: null);
    try {
      final updated = await _api.post(ApiPath.scrapeJobs.retry(job.id), parser: jsonParser(ScrapeJobRow.fromJson));
      if (!ref.mounted) return;
      state = _mapLoaded((status, slice) => _applyJob(slice, status, updated)).copyWith(retryingId: null);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(retryingId: null, actionError: failure.message);
    }
  }

  Future<void> confirmMatch({
    required ScrapeJobRow job,
    int? fileId,
    required String kind,
    required int tmdbId,
    int? year,
    int? season,
    int? episode,
    String? scope,
  }) async {
    try {
      await _api.post<Object?>(
        ApiPath.libraryFiles.match(fileId ?? job.fileId),
        data: {
          'kind': kind,
          'tmdbId': tmdbId,
          'year': ?year,
          'season': ?season,
          'episode': ?episode,
          'scope': ?scope,
        },
      );
      if (!ref.mounted) return;
      state = _mapLoaded((status, slice) {
        final index = slice.items.indexWhere((item) => item.id == job.id);
        if (index < 0 || slice.items[index].matchStatus != 'needs_review') return slice;
        final current = slice.items[index];
        return _applyJob(
          slice,
          status,
          ScrapeJobRow(
            id: current.id,
            status: 'running',
            attempts: current.attempts,
            maxAttempts: current.maxAttempts,
            progress: '人工匹配中',
            lastError: null,
            fileId: current.fileId,
            fileName: current.fileName,
            locator: current.locator,
            matchStatus: 'pending',
            parsedTitle: current.parsedTitle,
            parsedYear: current.parsedYear,
            parsedSeason: current.parsedSeason,
            parsedEpisode: current.parsedEpisode,
            confidence: current.confidence,
            message: '人工匹配中',
            workId: current.workId,
            mediaLibraryId: current.mediaLibraryId,
            mediaLibraryName: current.mediaLibraryName,
          ),
        );
      });
    } on ApiFailure catch (failure) {
      if (ref.mounted) state = state.copyWith(actionError: failure.message);
    }
  }

  Future<bool> _unauthorized(ApiFailure failure) async {
    if (!failure.unauthorized) return false;
    await ref.read(sessionProvider.notifier).signOut();
    return true;
  }
}
