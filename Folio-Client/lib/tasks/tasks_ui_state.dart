import 'package:folio/api/entity/models.dart';

class TaskSlice {
  const TaskSlice({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.totalPages = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.loaded = false,
  });

  final List<ScrapeJobRow> items;
  final int page;
  final int total;
  final int totalPages;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final bool loaded;

  bool get hasMore => page + 1 < totalPages;

  TaskSlice copyWith({
    List<ScrapeJobRow>? items,
    int? page,
    int? total,
    int? totalPages,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    bool? loaded,
  }) {
    return TaskSlice(
      items: items ?? this.items,
      page: page ?? this.page,
      total: total ?? this.total,
      totalPages: totalPages ?? this.totalPages,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error == _keep ? this.error : error as String?,
      loaded: loaded ?? this.loaded,
    );
  }
}

class TasksUiState {
  const TasksUiState({
    this.slices = const {},
    this.actionError,
    this.status = '',
    this.deletingId,
    this.retryingId,
  });

  final Map<String, TaskSlice> slices;
  final String? actionError;
  final String status;
  final int? deletingId;
  final int? retryingId;

  TaskSlice slice(String status) => slices[status] ?? const TaskSlice();

  TaskSlice get current => slice(status);

  List<ScrapeJobRow> get items => current.items;

  int get page => current.page;

  int get total => current.total;

  int get totalPages => current.totalPages;

  bool get loading => current.loading || (!current.loaded && current.error == null);

  bool get loadingMore => current.loadingMore;

  String? get error => current.error;

  bool get hasMore => current.hasMore;

  TasksUiState copyWith({
    Map<String, TaskSlice>? slices,
    Object? actionError = _keep,
    String? status,
    Object? deletingId = _keep,
    Object? retryingId = _keep,
  }) {
    return TasksUiState(
      slices: slices ?? this.slices,
      actionError: actionError == _keep ? this.actionError : actionError as String?,
      status: status ?? this.status,
      deletingId: deletingId == _keep ? this.deletingId : deletingId as int?,
      retryingId: retryingId == _keep ? this.retryingId : retryingId as int?,
    );
  }

  TasksUiState updateSlice(String status, TaskSlice slice) {
    return copyWith(slices: {...slices, status: slice});
  }
}

const _keep = Object();
