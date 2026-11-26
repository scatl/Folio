/// 分页刷新状态。从 qBPanel 的 PagedRefreshState 迁来。
class PagedRefreshState<T> {
  List<T> items = [];
  String? errorMessage;

  bool initLoading = false;
  bool refreshing = false;
  bool loadingMore = false;
  bool hasMore = false;
  bool success = false;
  bool error = false;

  bool get isEmpty => items.isEmpty;

  bool get showInitLoading => initLoading && isEmpty && !error;

  bool get showEmptyOrError => isEmpty && !initLoading;
}

/// 重试类型。
enum PagedRetryType { init, loadMore }
