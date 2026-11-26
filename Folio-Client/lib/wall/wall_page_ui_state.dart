import 'package:folio/api/entity/models.dart';
import 'package:folio/wall/browse_filter.dart';

class WallPageUiState {
  const WallPageUiState({
    this.libraries = const [],
    this.librariesLoading = true,
    this.home = true,
    this.libraryId,
    this.items = const [],
    this.recent = const [],
    this.recentTotal = 0,
    this.continueWatching = const [],
    this.watchlist = const [],
    this.playlists = const [],
    this.homeLibrariesOk = false,
    this.homeRecentOk = false,
    this.homeContinueOk = false,
    this.homeWatchlistOk = false,
    this.homePlaylistsOk = false,
    this.page = 0,
    this.total = 0,
    this.totalPages = 0,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.notice,
    this.scanning = false,
    this.movieTab = 'all',
    this.collections = const [],
    this.collectionsLoading = false,
    this.collectionsLoaded = false,
    this.openedCollection,
    this.collectionWorks = const [],
    this.query = '',
    this.searchText = '',
    this.searchOpen = false,
    this.searchResults = const [],
    this.searchPage = 0,
    this.searchTotal = 0,
    this.searchTotalPages = 0,
    this.searchLoading = false,
    this.searchLoadingMore = false,
    this.searchError,
    this.tmdbConfigured,
    this.browse = const WorkBrowseFilter(),
  });

  final List<MediaLibrary> libraries;
  final bool librariesLoading;
  final bool home;
  final int? libraryId;
  final List<WorkCard> items;
  final List<WorkCard> recent;
  final int recentTotal;
  final List<ContinueWatchItem> continueWatching;
  final List<WatchlistItem> watchlist;
  final List<PlaylistSummary> playlists;
  final bool homeLibrariesOk;
  final bool homeRecentOk;
  final bool homeContinueOk;
  final bool homeWatchlistOk;
  final bool homePlaylistsOk;
  final int page;
  final int total;
  final int totalPages;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String? notice;
  final bool scanning;
  final String movieTab;
  final List<CollectionCard> collections;
  final bool collectionsLoading;
  /// 系列列表是否已完成过至少一次加载（对齐任务页 slice.loaded 懒加载）。
  final bool collectionsLoaded;
  final CollectionCard? openedCollection;
  final List<WorkCard> collectionWorks;
  final String query;
  final String searchText;
  final bool searchOpen;
  final List<WorkCard> searchResults;
  final int searchPage;
  final int searchTotal;
  final int searchTotalPages;
  final bool searchLoading;
  final bool searchLoadingMore;
  final String? searchError;
  final bool? tmdbConfigured;
  final WorkBrowseFilter browse;

  bool get hasMore => page + 1 < totalPages;

  bool get searchHasMore => searchPage + 1 < searchTotalPages;

  bool get showSearchResults => searchOpen && searchText.trim().isNotEmpty;

  bool get collectionSearch => showSearchResults && !home && isMovie && movieTab == 'collections';

  MediaLibrary? get library {
    for (final item in libraries) {
      if (item.id == libraryId) return item;
    }
    return null;
  }

  bool get isMovie => !home && library?.kind == 'movie';

  String get statusText {
    if (librariesLoading || loading) return home ? '正在加载首页' : '正在整理海报墙';
    if (error != null) return error!;
    if (home) {
      if (homeLibrariesOk && libraries.isEmpty) return '还没有资料库';
      if (homeLibrariesOk && homeRecentOk) return '${libraries.length} 个资料库 · $recentTotal 部作品';
      if (homeLibrariesOk) return '${libraries.length} 个资料库';
      if (homeRecentOk) return '$recentTotal 部作品';
      return '';
    }
    final current = library;
    if (current == null) return '选择一个资料库';
    if (isMovie && movieTab == 'collections') {
      return '${current.name} · ${collections.length} 个系列';
    }
    return '${current.name} · 共 $total 部作品';
  }

  WallPageUiState copyWith({
    List<MediaLibrary>? libraries,
    bool? librariesLoading,
    bool? home,
    Object? libraryId = _keep,
    List<WorkCard>? items,
    List<WorkCard>? recent,
    int? recentTotal,
    List<ContinueWatchItem>? continueWatching,
    List<WatchlistItem>? watchlist,
    List<PlaylistSummary>? playlists,
    bool? homeLibrariesOk,
    bool? homeRecentOk,
    bool? homeContinueOk,
    bool? homeWatchlistOk,
    bool? homePlaylistsOk,
    int? page,
    int? total,
    int? totalPages,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    Object? notice = _keep,
    bool? scanning,
    String? movieTab,
    List<CollectionCard>? collections,
    bool? collectionsLoading,
    bool? collectionsLoaded,
    Object? openedCollection = _keep,
    List<WorkCard>? collectionWorks,
    String? query,
    String? searchText,
    bool? searchOpen,
    List<WorkCard>? searchResults,
    int? searchPage,
    int? searchTotal,
    int? searchTotalPages,
    bool? searchLoading,
    bool? searchLoadingMore,
    Object? searchError = _keep,
    Object? tmdbConfigured = _keep,
    WorkBrowseFilter? browse,
  }) {
    return WallPageUiState(
      libraries: libraries ?? this.libraries,
      librariesLoading: librariesLoading ?? this.librariesLoading,
      home: home ?? this.home,
      libraryId: libraryId == _keep ? this.libraryId : libraryId as int?,
      items: items ?? this.items,
      recent: recent ?? this.recent,
      recentTotal: recentTotal ?? this.recentTotal,
      continueWatching: continueWatching ?? this.continueWatching,
      watchlist: watchlist ?? this.watchlist,
      playlists: playlists ?? this.playlists,
      homeLibrariesOk: homeLibrariesOk ?? this.homeLibrariesOk,
      homeRecentOk: homeRecentOk ?? this.homeRecentOk,
      homeContinueOk: homeContinueOk ?? this.homeContinueOk,
      homeWatchlistOk: homeWatchlistOk ?? this.homeWatchlistOk,
      homePlaylistsOk: homePlaylistsOk ?? this.homePlaylistsOk,
      page: page ?? this.page,
      total: total ?? this.total,
      totalPages: totalPages ?? this.totalPages,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error == _keep ? this.error : error as String?,
      notice: notice == _keep ? this.notice : notice as String?,
      scanning: scanning ?? this.scanning,
      movieTab: movieTab ?? this.movieTab,
      collections: collections ?? this.collections,
      collectionsLoading: collectionsLoading ?? this.collectionsLoading,
      collectionsLoaded: collectionsLoaded ?? this.collectionsLoaded,
      openedCollection: openedCollection == _keep ? this.openedCollection : openedCollection as CollectionCard?,
      collectionWorks: collectionWorks ?? this.collectionWorks,
      query: query ?? this.query,
      searchText: searchText ?? this.searchText,
      searchOpen: searchOpen ?? this.searchOpen,
      searchResults: searchResults ?? this.searchResults,
      searchPage: searchPage ?? this.searchPage,
      searchTotal: searchTotal ?? this.searchTotal,
      searchTotalPages: searchTotalPages ?? this.searchTotalPages,
      searchLoading: searchLoading ?? this.searchLoading,
      searchLoadingMore: searchLoadingMore ?? this.searchLoadingMore,
      searchError: searchError == _keep ? this.searchError : searchError as String?,
      tmdbConfigured: tmdbConfigured == _keep ? this.tmdbConfigured : tmdbConfigured as bool?,
      browse: browse ?? this.browse,
    );
  }
}

const _keep = Object();
