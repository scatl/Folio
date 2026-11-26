import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/http/scrape_events.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/wall/browse_filter.dart';
import 'package:folio/wall/wall_page_ui_state.dart';

final wallPageProvider = NotifierProvider.autoDispose<WallPageViewModel, WallPageUiState>(
  WallPageViewModel.new,
);

class WallPageViewModel extends Notifier<WallPageUiState> {
  int _generation = 0;
  int _searchGen = 0;
  int? _deletingLibraryId;
  Timer? _searchTimer;
  ScrapeBus? _boundBus;
  StreamSubscription<ScrapeJobRow>? _doneSub;
  StreamSubscription<int>? _removedSub;
  StreamSubscription<PlaybackProgressEvent>? _playbackSub;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  WallPageUiState build() {
    // auth/me 在首页之后才开事件，资料回来时再补上订阅。
    ref.listen(sessionProvider, (previous, next) => _bindBus());
    _bindBus();
    ref.onDispose(() {
      _doneSub?.cancel();
      _removedSub?.cancel();
      _playbackSub?.cancel();
      _searchTimer?.cancel();
    });
    Future.microtask(boot);
    return const WallPageUiState();
  }

  void _bindBus() {
    final bus = ref.read(sessionProvider.notifier).bus;
    if (identical(bus, _boundBus)) return;
    _doneSub?.cancel();
    _removedSub?.cancel();
    _playbackSub?.cancel();
    _boundBus = bus;
    if (bus == null) {
      _doneSub = null;
      _removedSub = null;
      _playbackSub = null;
      return;
    }
    _doneSub = bus.done.stream.listen(_onDone);
    _removedSub = bus.workRemoved.stream.listen(removeWork);
    _playbackSub = bus.playback.stream.listen((event) {
      final username = ref.read(sessionProvider).username;
      if (event.username.isNotEmpty && username.isNotEmpty && event.username != username) return;
      if (!state.home) return;
      unawaited(loadHomeDashboard());
    });
  }

  Future<void> boot() async {
    await loadHomeDashboard();
  }

  Future<void> loadSetup() async {
    if (!ref.read(sessionProvider).isAdmin) return;
    try {
      final settings = await _api.get(ApiPath.settings, parser: jsonParser(AppSettings.fromJson));
      if (!ref.mounted) return;
      state = state.copyWith(tmdbConfigured: settings.tmdbApiKeyConfigured);
    } catch (_) {}
  }

  Future<void> refresh() async {
    final startedHome = state.home;
    final libraryId = state.libraryId;
    final movieTab = state.movieTab;
    // 重试时立刻进入 loading，避免仍停在错误空态。
    if (startedHome) {
      final cold = state.libraries.isEmpty && state.recent.isEmpty;
      state = state.copyWith(
        error: null,
        loading: cold ? true : state.loading,
        librariesLoading: cold ? true : state.librariesLoading,
      );
      unawaited(ref.read(sessionProvider.notifier).loadProfile());
      await loadHomeDashboard();
    } else if (movieTab == 'collections') {
      state = state.copyWith(
        error: null,
        collectionsLoading: state.collections.isEmpty ? true : state.collectionsLoading,
      );
      await loadSetup();
      await loadLibraries();
      if (!ref.mounted || state.home != startedHome || state.libraryId != libraryId) return;
      if (state.movieTab != movieTab) return;
      await loadCollections();
    } else {
      state = state.copyWith(
        error: null,
        loading: state.items.isEmpty ? true : state.loading,
      );
      await loadSetup();
      await loadLibraries();
      if (!ref.mounted || state.home != startedHome || state.libraryId != libraryId) return;
      if (state.movieTab != movieTab) return;
      await fetchPage(0, append: false);
    }
    if (!ref.mounted || state.home != startedHome || state.libraryId != libraryId) return;
    await ref.read(sessionProvider.notifier).refreshTaskBadge();
  }

  Future<void> loadLibraries() async {
    if (state.libraries.isEmpty) state = state.copyWith(librariesLoading: true);
    try {
      final listed = await _api.get(ApiPath.libraries.list, parser: listParser(MediaLibrary.fromJson));
      if (!ref.mounted) return;
      var home = state.home;
      int? libraryId = state.libraryId;
      if (libraryId != null && !listed.any((item) => item.id == libraryId)) {
        libraryId = null;
        home = true;
      }
      state = state.copyWith(
        libraries: listed,
        homeLibrariesOk: true,
        home: home,
        libraryId: libraryId,
        error: null,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(error: failure.message);
    } finally {
      if (ref.mounted) state = state.copyWith(librariesLoading: false);
    }
  }

  Future<void> loadHomeDashboard() async {
    final cold = state.libraries.isEmpty && state.recent.isEmpty;
    if (cold) {
      state = state.copyWith(loading: true, librariesLoading: true, error: null);
    } else {
      state = state.copyWith(error: null);
    }
    try {
      final home = await _api.get(ApiPath.home, parser: jsonParser(HomeView.fromJson));
      if (!ref.mounted) return;
      var nextHome = state.home;
      int? libraryId = state.libraryId;
      final libraries = home.libraries;
      if (libraries != null && libraryId != null && !libraries.any((item) => item.id == libraryId)) {
        libraryId = null;
        nextHome = true;
      }
      state = state.copyWith(
        libraries: libraries ?? const [],
        librariesLoading: false,
        home: nextHome,
        libraryId: libraryId,
        homeLibrariesOk: libraries != null,
        recent: home.recent?.items ?? const [],
        recentTotal: home.recent?.total ?? 0,
        continueWatching: home.continueWatching ?? const [],
        watchlist: home.watchlist ?? const [],
        playlists: home.playlists ?? const [],
        homeRecentOk: home.recent != null,
        homeContinueOk: home.continueWatching != null,
        homeWatchlistOk: home.watchlist != null,
        homePlaylistsOk: home.playlists != null,
        tmdbConfigured: home.setup?.tmdbConfigured,
        loading: false,
        error: null,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(
        libraries: const [],
        recent: const [],
        recentTotal: 0,
        continueWatching: const [],
        watchlist: const [],
        playlists: const [],
        homeLibrariesOk: false,
        homeRecentOk: false,
        homeContinueOk: false,
        homeWatchlistOk: false,
        homePlaylistsOk: false,
        error: failure.message,
        loading: false,
        librariesLoading: false,
      );
    }
  }

  Future<void> loadHome() => loadHomeDashboard();

  Future<void> reloadWatchlist() async {
    try {
      final items = await _api.get(
        ApiPath.watchlist.list,
        parser: listParser(WatchlistItem.fromJson),
      );
      if (!ref.mounted) return;
      state = state.copyWith(watchlist: items, homeWatchlistOk: true);
    } on ApiFailure {
      // 保留上次成功的清单
    }
  }

  Future<void> reloadPlaylists() async {
    try {
      final items = await _api.get(
        ApiPath.playlists.list,
        parser: listParser(PlaylistSummary.fromJson),
      );
      if (!ref.mounted) return;
      state = state.copyWith(playlists: items, homePlaylistsOk: true);
    } on ApiFailure {
      // 保留上次成功的清单
    }
  }

  Future<void> applyBrowse(WorkBrowseFilter filter) async {
    state = state.copyWith(browse: filter);
    if (state.showSearchResults && !state.collectionSearch) {
      await fetchSearch(0, append: false);
      return;
    }
    if (state.home && !filter.active) return;
    await fetchPage(0, append: false);
  }

  Future<void> markWork(WorkCard work, bool watched) async {
    try {
      final row = await _api.put(
        ApiPath.playback.workWatch(work.id),
        data: {'watched': watched},
        parser: (data) => Map<String, dynamic>.from(data as Map),
      );
      final next = row['watchState']?.toString() ?? (watched ? 'watched' : 'unwatched');
      List<WorkCard> paint(List<WorkCard> list) => [
            for (final item in list)
              if (item.id != work.id || state.browse.watch == null || state.browse.watch == next)
                item.id == work.id ? item.copyWith(watchState: next) : item,
          ];
      state = state.copyWith(
        items: paint(state.items),
        recent: paint(state.recent),
        searchResults: paint(state.searchResults),
        continueWatching: next == 'watched'
            ? state.continueWatching.where((item) => item.workId != work.id).toList()
            : state.continueWatching,
        notice: watched ? '已标为已看' : '已标为未看',
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(notice: failure.message);
    }
  }

  Future<void> fetchPage(int nextPage, {required bool append}) async {
    final libraryId = state.libraryId;
    final homeBrowse = state.home && state.browse.active;
    if (!homeBrowse && (state.home || libraryId == null)) return;
    if (append) {
      if (!state.hasMore || state.loadingMore || state.loading) return;
      state = state.copyWith(loadingMore: true);
    } else {
      _generation += 1;
      if (state.items.isEmpty) {
        state = state.copyWith(loading: true, loadingMore: false, error: null);
      } else {
        state = state.copyWith(loadingMore: false, error: null);
      }
    }
    final generation = _generation;
    try {
      final data = await _api.get(
        ApiPath.works.list,
        queryParameters: {
          if (!state.home && libraryId != null) 'libraryId': libraryId,
          ...state.browse.toQuery(),
          'page': nextPage,
          'size': 48,
        },
        parser: (data) => PageResult.fromJson(Map<String, dynamic>.from(data as Map), WorkCard.fromJson),
      );
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        items: append ? [...state.items, ...data.items] : data.items,
        page: data.page,
        total: data.total,
        totalPages: data.totalPages,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || generation != _generation || await _unauthorized(failure)) return;
      state = state.copyWith(error: failure.message, items: append ? state.items : const []);
    } finally {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(
          loading: append ? state.loading : false,
          loadingMore: append ? false : state.loadingMore,
        );
      }
    }
  }

  Future<void> loadMore() {
    if ((state.home && !state.browse.active) || !state.hasMore || state.loading || state.loadingMore) {
      return Future.value();
    }
    if (!state.home && state.libraryId == null) return Future.value();
    return fetchPage(state.page + 1, append: true);
  }

  Future<void> deleteLibrary(MediaLibrary library) async {
    if (_deletingLibraryId != null) return;
    _deletingLibraryId = library.id;
    try {
      await _api.delete<Object>(ApiPath.libraries.one(library.id), parser: (data) => data);
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(error: failure.message);
      return;
    } finally {
      _deletingLibraryId = null;
    }
    if (!ref.mounted) return;
    final viewing = !state.home && state.libraryId == library.id;
    state = state.copyWith(libraries: state.libraries.where((item) => item.id != library.id).toList());
    if (viewing) goHome();
    state = state.copyWith(notice: '已删除「${library.name}」');
  }

  void goHome() {
    _clearSearch();
    state = state.copyWith(
      home: true,
      libraryId: null,
      movieTab: 'all',
      openedCollection: null,
      collectionWorks: const [],
      collections: const [],
      collectionsLoaded: false,
      collectionsLoading: false,
    );
    unawaited(loadHomeDashboard());
  }

  void selectLibrary(int id) {
    _clearSearch();
    if (!state.home && state.libraryId == id) return;
    state = state.copyWith(
      home: false,
      libraryId: id,
      movieTab: 'all',
      openedCollection: null,
      collectionWorks: const [],
      collections: const [],
      collectionsLoaded: false,
      collectionsLoading: false,
      items: const [],
    );
    unawaited(fetchPage(0, append: false));
  }

  void openSearch() {
    if (state.searchOpen) return;
    state = state.copyWith(searchOpen: true, searchError: null);
  }

  void closeSearch() {
    _clearSearch();
  }

  void onSearch(String value) {
    if (!state.searchOpen) return;
    _searchTimer?.cancel();
    if (_collectionNameSearch) {
      _searchGen += 1;
      state = state.copyWith(searchText: value, query: value.trim(), searchLoading: false, searchError: null, searchResults: const []);
      return;
    }
    state = state.copyWith(searchText: value, searchLoading: value.trim().isNotEmpty, searchError: null);
    if (value.trim().isEmpty) {
      _searchGen += 1;
      state = state.copyWith(
        query: '',
        searchResults: const [],
        searchPage: 0,
        searchTotal: 0,
        searchTotalPages: 0,
        searchLoading: false,
        searchLoadingMore: false,
      );
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 320), () {
      if (!ref.mounted || !state.searchOpen || state.searchText != value) return;
      final q = value.trim();
      state = state.copyWith(query: q);
      unawaited(fetchSearch(0, append: false));
    });
  }

  Future<void> loadMoreSearch() {
    if (!state.showSearchResults || state.collectionSearch || !state.searchHasMore || state.searchLoading || state.searchLoadingMore) {
      return Future.value();
    }
    return fetchSearch(state.searchPage + 1, append: true);
  }

  Future<void> refreshSearch() async {
    if (state.collectionSearch) {
      await loadCollections();
      return;
    }
    await fetchSearch(0, append: false);
  }

  Future<void> fetchSearch(int nextPage, {required bool append}) async {
    if (!state.searchOpen || state.collectionSearch) return;
    final q = state.query.trim();
    if (q.isEmpty) return;
    final libraryId = state.home ? null : state.libraryId;
    if (!state.home && libraryId == null) return;
    if (append) {
      if (!state.searchHasMore || state.searchLoadingMore || state.searchLoading) return;
      state = state.copyWith(searchLoadingMore: true);
    } else {
      _searchGen += 1;
      state = state.copyWith(
        searchLoading: true,
        searchLoadingMore: false,
        searchError: null,
        searchResults: const [],
        searchPage: 0,
        searchTotal: 0,
        searchTotalPages: 0,
      );
    }
    final generation = _searchGen;
    try {
      final data = await _api.get(
        ApiPath.works.list,
        queryParameters: {
          'libraryId': ?libraryId,
          'q': q,
          ...state.browse.toQuery(),
          'page': nextPage,
          'size': 48,
        },
        parser: (data) => PageResult.fromJson(Map<String, dynamic>.from(data as Map), WorkCard.fromJson),
      );
      if (!ref.mounted || generation != _searchGen || state.query.trim() != q) return;
      state = state.copyWith(
        searchResults: append ? [...state.searchResults, ...data.items] : data.items,
        searchPage: data.page,
        searchTotal: data.total,
        searchTotalPages: data.totalPages,
      );
    } on ApiFailure catch (failure) {
      if (!ref.mounted || generation != _searchGen || await _unauthorized(failure)) return;
      state = state.copyWith(searchError: failure.message, searchResults: append ? state.searchResults : const []);
    } finally {
      if (ref.mounted && generation == _searchGen) {
        state = state.copyWith(searchLoading: false, searchLoadingMore: false);
      }
    }
  }

  bool get _collectionNameSearch => !state.home && state.isMovie && state.movieTab == 'collections';

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchGen += 1;
    if (!state.searchOpen && state.searchText.isEmpty && state.query.isEmpty && state.searchResults.isEmpty) return;
    state = state.copyWith(
      searchOpen: false,
      searchText: '',
      query: '',
      searchResults: const [],
      searchPage: 0,
      searchTotal: 0,
      searchTotalPages: 0,
      searchLoading: false,
      searchLoadingMore: false,
      searchError: null,
    );
  }

  Future<void> setMovieTab(String tab) async {
    if (tab == 'collections') {
      state = state.copyWith(
        movieTab: tab,
        openedCollection: null,
        collectionWorks: const [],
        error: null,
      );
      // 对齐任务页：未 loaded 才拉取；未加载前 UI 显示加载态而非空态。
      if (!state.collectionsLoaded) await loadCollections();
      return;
    }
    state = state.copyWith(
      movieTab: tab,
      openedCollection: null,
      collectionWorks: const [],
    );
  }

  Future<void> loadCollections() async {
    final id = state.libraryId;
    if (id == null) return;
    if (!state.collectionsLoaded || state.collections.isEmpty) {
      state = state.copyWith(collectionsLoading: true, error: null);
    } else {
      state = state.copyWith(error: null);
    }
    try {
      final items = await _api.get(ApiPath.libraries.collections(id), parser: listParser(CollectionCard.fromJson));
      if (ref.mounted) {
        state = state.copyWith(collections: items, collectionsLoaded: true);
      }
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(error: failure.message, collections: const [], collectionsLoaded: false);
    } finally {
      if (ref.mounted) state = state.copyWith(collectionsLoading: false);
    }
  }

  void clearNotice() {
    if (state.notice == null) return;
    state = state.copyWith(notice: null);
  }

  Future<void> scan() async {
    final id = state.libraryId;
    if (id == null || state.scanning) return;
    state = state.copyWith(scanning: true, error: null);
    try {
      await _api.post<Object?>(ApiPath.libraries.scan(id));
      if (!ref.mounted) return;
      state = state.copyWith(notice: '已开始扫描「${state.library?.name ?? '资料库'}」');
      unawaited(ref.read(sessionProvider.notifier).refreshTaskBadge());
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(error: failure.message);
    } finally {
      if (ref.mounted) state = state.copyWith(scanning: false);
    }
  }

  void noteLibraryCreated(MediaLibrary library) {
    state = state.copyWith(notice: '已创建「${library.name}」，正在后台扫描并入队刮削');
    unawaited(loadLibraries());
    unawaited(ref.read(sessionProvider.notifier).refreshTaskBadge());
  }

  void _onDone(ScrapeJobRow job) {
    if (job.matchStatus == 'matched') {
      unawaited(_upsertFromJob(job));
    }
  }

  Future<void> _upsertFromJob(ScrapeJobRow job) async {
    if (job.workId == null || state.loading) return;
    if (!state.home && job.mediaLibraryId != state.libraryId) return;
    final WorkCard card;
    try {
      card = await _api.get(ApiPath.works.card(job.workId!), parser: jsonParser(WorkCard.fromJson));
    } on ApiFailure {
      return;
    }
    if (!ref.mounted) return;
    if (state.home) {
      final existed = state.recent.any((work) => work.id == card.id);
      state = state.copyWith(
        recent: placeRecentCard(state.recent, card),
        recentTotal: existed ? state.recentTotal : state.recentTotal + 1,
        homeRecentOk: true,
      );
      return;
    }
    final existed = state.items.any((work) => work.id == card.id);
    final total = existed ? state.total : state.total + 1;
    state = state.copyWith(
      items: placeCard(state.items, card, state.hasMore),
      total: total,
      totalPages: total == 0 ? 0 : (total / 48).ceil(),
    );
  }

  void removeWork(int workId) {
    final recentBefore = state.recent.length;
    final recent = state.recent.where((work) => work.id != workId).toList();
    final before = state.items.length;
    final items = state.items.where((work) => work.id != workId).toList();
    final total = items.length < before ? (state.total - 1).clamp(0, 1 << 30) : state.total;
    state = state.copyWith(
      recent: recent,
      recentTotal: recent.length < recentBefore ? (state.recentTotal - 1).clamp(0, 1 << 30) : state.recentTotal,
      items: items,
      total: total,
      totalPages: total == 0 ? 0 : (total / 48).ceil(),
    );
  }

  Future<bool> _unauthorized(ApiFailure failure) async {
    if (!failure.unauthorized) return false;
    await ref.read(sessionProvider.notifier).signOut();
    return true;
  }
}

double _rank(WorkCard work) => work.popularity ?? -1;

bool _comesAfter(WorkCard card, WorkCard other) {
  final left = _rank(card);
  final right = _rank(other);
  if (left != right) return left < right;
  return card.id < other.id;
}

List<WorkCard> placeCard(List<WorkCard> list, WorkCard card, bool windowFull) {
  final exists = list.any((work) => work.id == card.id);
  final rest = list.where((work) => work.id != card.id).toList();
  final last = rest.isEmpty ? null : rest.last;
  if (!exists && windowFull && last != null && _comesAfter(card, last)) return list;
  final next = [...rest, card]..sort((a, b) {
      if (_comesAfter(a, b)) return 1;
      if (_comesAfter(b, a)) return -1;
      return 0;
    });
  return next;
}

/// 首页近期作品：按最近刮削置顶，最多 50 条。
List<WorkCard> placeRecentCard(List<WorkCard> list, WorkCard card) {
  return [card, ...list.where((work) => work.id != card.id)].take(50).toList();
}
