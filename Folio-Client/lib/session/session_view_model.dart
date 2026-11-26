import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/http/scrape_events.dart';
import 'package:folio/session/session_ui_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sessionProvider = NotifierProvider<SessionViewModel, SessionUiState>(
  SessionViewModel.new,
);

class SessionViewModel extends Notifier<SessionUiState> {
  static const _serverKey = 'folio.server';
  static const _usernameKey = 'folio.username';

  SharedPreferences? _prefs;
  ScrapeBus? bus;
  ScrapeEventClient? _events;
  StreamSubscription<dynamic>? _statsSub;
  StreamSubscription<dynamic>? _doneSub;
  Timer? _batchSettle;
  bool _batchOpen = false;
  int _batchReview = 0;
  int _batchFailed = 0;
  final Set<int> _batchSeen = {};
  Future<void>? _profileLoad;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  SessionUiState build() {
    ref.onDispose(_stopEvents);
    Future.microtask(_bootstrap);
    return const SessionUiState();
  }

  Future<void> _bootstrap() async {
    var serverUrl = '';
    var username = 'folio';
    try {
      final prefs = await SharedPreferences.getInstance();
      final dir = await getApplicationSupportDirectory();
      _prefs = prefs;
      await _api.usePersistentCookies('${dir.path}/cookies');
      serverUrl = prefs.getString(_serverKey) ?? '';
      username = prefs.getString(_usernameKey) ?? 'folio';
      if (serverUrl.isNotEmpty) {
        _api.use(ServerConnection.parse(serverUrl));
      }
    } catch (_) {
      // 本地初始化失败时仍进入登录页。
    }
    if (!ref.mounted) return;
    // 有保存的服务器地址就直接进首页。auth/me 由首页再请求，避免启动时闪登录页。
    state = state.copyWith(
      bootstrapping: false,
      signedIn: serverUrl.isNotEmpty,
      serverUrl: serverUrl,
      username: username,
    );
  }

  /// 首页进入时补齐当前用户。成功后不再重复请求；401 退出，断网留在首页。
  Future<void> loadProfile() {
    if (!state.signedIn || state.profileReady) return Future<void>.value();
    final pending = _profileLoad;
    if (pending != null) return pending;
    final task = _loadProfile();
    _profileLoad = task;
    return task.whenComplete(() {
      if (identical(_profileLoad, task)) _profileLoad = null;
    });
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _api.get(ApiPath.auth.me, parser: jsonParser(AuthUser.fromJson));
      if (!ref.mounted || !state.signedIn) return;
      _startEvents();
      state = state.copyWith(
        profileReady: true,
        username: user.username,
        userId: user.id,
        role: user.role,
        libraries: user.libraries,
      );
      if (state.isAdmin) unawaited(refreshTaskBadge());
    } on ApiFailure catch (failure) {
      if (failure.unauthorized && ref.mounted && state.signedIn) await signOut();
    } catch (_) {
      // 超时或断网：保持已登录，首页自己展示失败和重试。
    }
  }

  Future<void> signIn({
    required String server,
    required String username,
    required String password,
  }) async {
    final prefs = _prefs;
    if (prefs == null) {
      throw const ApiFailure(message: '客户端尚未就绪');
    }
    final connection = ServerConnection.parse(server);
    if (_api.baseUrl != connection.baseUrl) {
      await _api.clearCookies();
    }
    final user = await _api.postWithConfig(
      config: connection,
      apiPath: ApiPath.auth.login,
      data: {'username': username.trim(), 'password': password},
      parser: jsonParser(AuthUser.fromJson),
    );
    _api.use(connection);
    await prefs.setString(_serverKey, connection.baseUrl);
    await prefs.setString(_usernameKey, user.username);
    _startEvents();
    state = state.copyWith(
      signedIn: true,
      profileReady: true,
      serverUrl: connection.baseUrl,
      username: user.username,
      userId: user.id,
      role: user.role,
      libraries: user.libraries,
      bootstrapping: false,
    );
    if (state.isAdmin) unawaited(refreshTaskBadge());
  }

  Future<void> signOut() async {
    try {
      await _api.post<Object?>(ApiPath.auth.logout);
    } catch (_) {
      // 会话失效时仍然清理本地登录态。
    }
    _stopEvents();
    await _api.clearCookies();
    _profileLoad = null;
    state = state.copyWith(
      signedIn: false,
      profileReady: false,
      userId: 0,
      role: 'USER',
      libraries: const [],
      taskBadge: 0,
      reviewTotal: 0,
    );
  }

  Future<void> refreshTaskBadge() async {
    if (!state.signedIn || !state.isAdmin) return;
    try {
      final stats = await _api.get(ApiPath.scrapeJobs.stats, parser: jsonParser(ScrapeJobStats.fromJson));
      final review = await _api.get(
        ApiPath.libraryFiles.list,
        queryParameters: const {'status': 'needs_review', 'page': 0, 'size': 1},
        parser: (data) => PageResult.fromJson(Map<String, dynamic>.from(data as Map), (json) => json).total,
      );
      if (!ref.mounted || !state.signedIn) return;
      state = state.copyWith(
        reviewTotal: review,
        taskBadge: stats.active > review ? stats.active : review,
      );
    } on ApiFailure catch (failure) {
      if (failure.unauthorized && ref.mounted) await signOut();
    }
  }

  void noteReviewArrived() {
    final reviewTotal = state.reviewTotal + 1;
    state = state.copyWith(
      reviewTotal: reviewTotal,
      taskBadge: state.taskBadge < reviewTotal ? reviewTotal : state.taskBadge,
    );
  }

  Future<void> renameUser(String next) async {
    await _prefs?.setString(_usernameKey, next);
    state = state.copyWith(username: next);
  }

  Future<List<String>> loginPosters(String server) async {
    try {
      final connection = ServerConnection.parse(server);
      return await _api.getWithConfig(
        config: connection,
        apiPath: ApiPath.auth.posters,
        parser: (data) {
          if (data is! List) return const <String>[];
          return data.map((item) => item.toString()).where((url) => url.isNotEmpty).toList();
        },
      );
    } catch (_) {
      return const [];
    }
  }

  void _startEvents() {
    _stopEvents();
    final client = _api;
    if (client.baseUrl == null) return;
    final next = ScrapeBus();
    bus = next;
    _statsSub = next.stats.stream.listen((stats) {
      final reviewTotal = state.reviewTotal;
      state = state.copyWith(
        taskBadge: stats.active > reviewTotal ? stats.active : reviewTotal,
      );
      _onBatchStats(stats.active);
    });
    _doneSub = next.done.stream.listen((job) {
      if (job.matchStatus == 'needs_review') noteReviewArrived();
      _onBatchDone(job);
    });
    _events = ScrapeEventClient(client, next)..start();
  }

  void _onBatchStats(int active) {
    if (active > 0) {
      _batchSettle?.cancel();
      _batchSettle = null;
      if (!_batchOpen) {
        _batchOpen = true;
        _batchReview = 0;
        _batchFailed = 0;
        _batchSeen.clear();
      }
      return;
    }
    if (!_batchOpen) return;
    _batchSettle?.cancel();
    _batchSettle = Timer(const Duration(milliseconds: 400), _finishBatch);
  }

  void _onBatchDone(ScrapeJobRow job) {
    if (!_batchOpen || !_batchSeen.add(job.id)) return;
    if (job.matchStatus == 'needs_review') {
      _batchReview += 1;
    } else if (job.matchStatus == 'failed' || job.status == 'failed') {
      _batchFailed += 1;
    }
  }

  void _finishBatch() {
    _batchSettle = null;
    if (!_batchOpen) return;
    _batchOpen = false;
    final review = _batchReview;
    final failed = _batchFailed;
    _batchReview = 0;
    _batchFailed = 0;
    _batchSeen.clear();
    if (review == 0 && failed == 0) return;
    state = state.copyWith(
      scrapeNoticeId: state.scrapeNoticeId + 1,
      scrapeReview: review,
      scrapeFailed: failed,
    );
  }

  void _stopEvents() {
    _batchSettle?.cancel();
    _batchSettle = null;
    _batchOpen = false;
    _events?.stop();
    _events = null;
    _statsSub?.cancel();
    _doneSub?.cancel();
    _statsSub = null;
    _doneSub = null;
    bus?.close();
    bus = null;
  }
}
