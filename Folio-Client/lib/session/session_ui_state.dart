import 'package:folio/api/entity/models.dart';

class SessionUiState {
  const SessionUiState({
    this.bootstrapping = true,
    this.signedIn = false,
    this.serverUrl = '',
    this.username = 'folio',
    this.userId = 0,
    this.role = 'USER',
    this.libraries = const [],
    this.profileReady = false,
    this.taskBadge = 0,
    this.reviewTotal = 0,
    this.scrapeNoticeId = 0,
    this.scrapeReview = 0,
    this.scrapeFailed = 0,
  });

  final bool bootstrapping;
  final bool signedIn;
  final String serverUrl;
  final String username;
  final int userId;
  final String role;
  final List<LibraryPermission> libraries;

  /// 登录响应或首页的 auth/me 已经写入角色和资料库权限。
  final bool profileReady;
  final int taskBadge;
  final int reviewTotal;
  final int scrapeNoticeId;
  final int scrapeReview;
  final int scrapeFailed;

  bool get isAdmin => role == 'ADMIN';

  bool get hasWriteLibrary => isAdmin || libraries.any((item) => item.canWrite);

  SessionUiState copyWith({
    bool? bootstrapping,
    bool? signedIn,
    String? serverUrl,
    String? username,
    int? userId,
    String? role,
    List<LibraryPermission>? libraries,
    bool? profileReady,
    int? taskBadge,
    int? reviewTotal,
    int? scrapeNoticeId,
    int? scrapeReview,
    int? scrapeFailed,
  }) {
    return SessionUiState(
      bootstrapping: bootstrapping ?? this.bootstrapping,
      signedIn: signedIn ?? this.signedIn,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      libraries: libraries ?? this.libraries,
      profileReady: profileReady ?? this.profileReady,
      taskBadge: taskBadge ?? this.taskBadge,
      reviewTotal: reviewTotal ?? this.reviewTotal,
      scrapeNoticeId: scrapeNoticeId ?? this.scrapeNoticeId,
      scrapeReview: scrapeReview ?? this.scrapeReview,
      scrapeFailed: scrapeFailed ?? this.scrapeFailed,
    );
  }
}
