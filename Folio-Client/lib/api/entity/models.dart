int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

double? asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool asBool(dynamic value) {
  if (value is bool) return value;
  return value.toString() == 'true';
}

bool? asBoolOrNull(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  final text = value.toString();
  if (text == 'true') return true;
  if (text == 'false') return false;
  return null;
}

class ServerIdentity {
  const ServerIdentity({required this.serverId});

  final String serverId;

  factory ServerIdentity.fromJson(Map<String, dynamic> json) {
    return ServerIdentity(serverId: json['serverId']?.toString() ?? '');
  }
}

class LocalEndpoint {
  const LocalEndpoint({
    required this.name,
    required this.address,
    required this.url,
  });

  final String name;
  final String address;
  final String url;

  factory LocalEndpoint.fromJson(Map<String, dynamic> json) {
    return LocalEndpoint(
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

class ServerConnections {
  const ServerConnections({
    required this.serverId,
    required this.local,
    required this.remoteUrl,
  });

  final String serverId;
  final List<LocalEndpoint> local;
  final String? remoteUrl;

  factory ServerConnections.fromJson(Map<String, dynamic> json) {
    return ServerConnections(
      serverId: json['serverId']?.toString() ?? '',
      local: _maps(json['local']).map(LocalEndpoint.fromJson).toList(),
      remoteUrl: json['remoteUrl']?.toString(),
    );
  }
}

class LibraryPermission {
  const LibraryPermission({required this.libraryId, required this.access});

  final int libraryId;
  final String access;

  bool get canWrite => access == 'WRITE';

  factory LibraryPermission.fromJson(Map<String, dynamic> json) {
    return LibraryPermission(
      libraryId: asInt(json['libraryId']),
      access: json['access']?.toString() ?? 'READ',
    );
  }

  Map<String, dynamic> toJson() => {'libraryId': libraryId, 'access': access};
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.role,
    required this.disabled,
    this.libraries = const [],
  });

  final int id;
  final String username;
  final String role;
  final bool disabled;
  final List<LibraryPermission> libraries;

  bool get isAdmin => role == 'ADMIN';

  bool get hasWriteLibrary => isAdmin || libraries.any((item) => item.canWrite);

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final librariesRaw = json['libraries'];
    return AuthUser(
      id: asInt(json['id']),
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'USER',
      disabled: asBool(json['disabled']),
      libraries: librariesRaw is List
          ? librariesRaw
              .whereType<Map>()
              .map((item) => LibraryPermission.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}

class MediaLibrary {
  const MediaLibrary({
    required this.id,
    required this.name,
    required this.kind,
    required this.rootPath,
    required this.workCount,
    this.access = 'READ',
  });

  final int id;
  final String name;
  final String kind;
  final String rootPath;
  final int? workCount;
  final String access;

  bool get isSeries => kind == 'series';

  bool get canWrite => access == 'WRITE';

  String get kindLabel => isSeries ? '剧集' : '电影';

  factory MediaLibrary.fromJson(Map<String, dynamic> json) {
    return MediaLibrary(
      id: asInt(json['id']),
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'movie',
      rootPath: json['rootPath']?.toString() ?? '',
      workCount: asIntOrNull(json['workCount']),
      access: json['access']?.toString() ?? 'READ',
    );
  }

  MediaLibrary withWorkCount(int count) => MediaLibrary(
        id: id,
        name: name,
        kind: kind,
        rootPath: rootPath,
        workCount: count,
        access: access,
      );
}

class WorkCard {
  const WorkCard({
    required this.id,
    required this.kind,
    required this.originalTitle,
    required this.title,
    required this.year,
    required this.posterUrl,
    required this.rating,
    required this.genres,
    required this.popularity,
    this.watchState,
  });

  final int id;
  final String kind;
  final String originalTitle;
  final String title;
  final int? year;
  final String? posterUrl;
  final double? rating;
  final List<String> genres;
  final double? popularity;
  final String? watchState;

  WorkCard copyWith({String? watchState}) => WorkCard(
        id: id,
        kind: kind,
        originalTitle: originalTitle,
        title: title,
        year: year,
        posterUrl: posterUrl,
        rating: rating,
        genres: genres,
        popularity: popularity,
        watchState: watchState ?? this.watchState,
      );

  String get kindLabel => kind == 'series' ? '剧集' : '电影';

  factory WorkCard.fromJson(Map<String, dynamic> json) {
    final genres = json['genres'];
    return WorkCard(
      id: asInt(json['id']),
      kind: json['kind']?.toString() ?? 'movie',
      originalTitle: json['originalTitle']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      year: asIntOrNull(json['year']),
      posterUrl: json['posterUrl']?.toString(),
      rating: asDouble(json['rating']),
      genres: genres is List ? genres.map((item) => item.toString()).toList() : const [],
      popularity: asDouble(json['popularity']),
      watchState: json['watchState']?.toString(),
    );
  }
}

class PageResult<T> {
  const PageResult({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
    required this.totalPages,
  });

  final List<T> items;
  final int page;
  final int size;
  final int total;
  final int totalPages;

  factory PageResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) decode) {
    final raw = json['items'];
    return PageResult(
      items: raw is List
          ? raw.whereType<Map>().map((item) => decode(Map<String, dynamic>.from(item))).toList()
          : const [],
      page: asInt(json['page']),
      size: asInt(json['size']),
      total: asInt(json['total']),
      totalPages: asInt(json['totalPages']),
    );
  }
}

class HomeSetup {
  const HomeSetup({required this.tmdbConfigured});

  final bool tmdbConfigured;

  factory HomeSetup.fromJson(Map<String, dynamic> json) {
    return HomeSetup(tmdbConfigured: asBool(json['tmdbConfigured']));
  }
}

class HomeView {
  const HomeView({
    required this.libraries,
    required this.recent,
    required this.continueWatching,
    required this.watchlist,
    required this.playlists,
    required this.setup,
  });

  final List<MediaLibrary>? libraries;
  final PageResult<WorkCard>? recent;
  final List<ContinueWatchItem>? continueWatching;
  final List<WatchlistItem>? watchlist;
  final List<PlaylistSummary>? playlists;
  final HomeSetup? setup;

  factory HomeView.fromJson(Map<String, dynamic> json) {
    final librariesRaw = json['libraries'];
    final recentRaw = json['recent'];
    final continueRaw = json['continueWatching'];
    final watchRaw = json['watchlist'];
    final playlistRaw = json['playlists'];
    final setupRaw = json['setup'];
    return HomeView(
      libraries: librariesRaw is List
          ? librariesRaw.whereType<Map>().map((item) => MediaLibrary.fromJson(Map<String, dynamic>.from(item))).toList()
          : null,
      recent: recentRaw is Map
          ? PageResult.fromJson(Map<String, dynamic>.from(recentRaw), WorkCard.fromJson)
          : null,
      continueWatching: continueRaw is List
          ? continueRaw
              .whereType<Map>()
              .map((item) => ContinueWatchItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : null,
      watchlist: watchRaw is List
          ? watchRaw
              .whereType<Map>()
              .map((item) => WatchlistItem.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : null,
      playlists: playlistRaw is List
          ? playlistRaw
              .whereType<Map>()
              .map((item) => PlaylistSummary.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : null,
      setup: setupRaw is Map ? HomeSetup.fromJson(Map<String, dynamic>.from(setupRaw)) : null,
    );
  }
}

class PlaybackProgress {
  const PlaybackProgress({
    required this.libraryFileId,
    this.workId,
    this.episodeId,
    this.fileName,
    required this.positionMs,
    this.durationMs,
    required this.completed,
    this.resumePositionMs,
    required this.updatedAt,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
  });

  final int libraryFileId;
  final int? workId;
  final int? episodeId;
  final String? fileName;
  final int positionMs;
  final int? durationMs;
  final bool completed;
  final int? resumePositionMs;
  final String updatedAt;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;

  String get episodeLabel {
    final s = seasonNumber;
    final e = episodeNumber;
    if (s == null || e == null) return '';
    return 'S${s}E$e';
  }

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) {
    return PlaybackProgress(
      libraryFileId: asInt(json['libraryFileId']),
      workId: asIntOrNull(json['workId']),
      episodeId: asIntOrNull(json['episodeId']),
      fileName: json['fileName']?.toString(),
      positionMs: asInt(json['positionMs']),
      durationMs: asIntOrNull(json['durationMs']),
      completed: asBool(json['completed']),
      resumePositionMs: asIntOrNull(json['resumePositionMs']),
      updatedAt: json['updatedAt']?.toString() ?? '',
      seasonNumber: asIntOrNull(json['seasonNumber']),
      episodeNumber: asIntOrNull(json['episodeNumber']),
      episodeTitle: json['episodeTitle']?.toString(),
    );
  }
}

class ContinueWatchItem {
  const ContinueWatchItem({
    required this.workId,
    required this.workTitle,
    required this.kind,
    this.posterUrl,
    required this.libraryFileId,
    this.fileName,
    required this.positionMs,
    this.durationMs,
    required this.completed,
    this.resumePositionMs,
    required this.progressRatio,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    required this.subtitle,
  });

  final int workId;
  final String workTitle;
  final String kind;
  final String? posterUrl;
  final int libraryFileId;
  final String? fileName;
  final int positionMs;
  final int? durationMs;
  final bool completed;
  final int? resumePositionMs;
  final double progressRatio;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String subtitle;

  factory ContinueWatchItem.fromJson(Map<String, dynamic> json) {
    return ContinueWatchItem(
      workId: asInt(json['workId']),
      workTitle: json['workTitle']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      posterUrl: json['posterUrl']?.toString(),
      libraryFileId: asInt(json['libraryFileId']),
      fileName: json['fileName']?.toString(),
      positionMs: asInt(json['positionMs']),
      durationMs: asIntOrNull(json['durationMs']),
      completed: asBool(json['completed']),
      resumePositionMs: asIntOrNull(json['resumePositionMs']),
      progressRatio: asDouble(json['progressRatio']) ?? 0,
      seasonNumber: asIntOrNull(json['seasonNumber']),
      episodeNumber: asIntOrNull(json['episodeNumber']),
      episodeTitle: json['episodeTitle']?.toString(),
      subtitle: json['subtitle']?.toString() ?? '',
    );
  }
}

class WatchlistItem {
  const WatchlistItem({
    required this.workId,
    required this.workTitle,
    required this.kind,
    this.year,
    this.posterUrl,
    required this.subtitle,
  });

  final int workId;
  final String workTitle;
  final String kind;
  final int? year;
  final String? posterUrl;
  final String subtitle;

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      workId: asInt(json['workId']),
      workTitle: json['workTitle']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      year: asIntOrNull(json['year']),
      posterUrl: json['posterUrl']?.toString(),
      subtitle: json['subtitle']?.toString() ?? '',
    );
  }
}

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.itemCount,
    this.posterUrl,
    this.contains = false,
  });

  final int id;
  final String name;
  final int itemCount;
  final String? posterUrl;
  final bool contains;

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: asInt(json['id']),
      name: json['name']?.toString() ?? '',
      itemCount: asInt(json['itemCount']),
      posterUrl: json['posterUrl']?.toString(),
      contains: asBool(json['contains']),
    );
  }
}

class PlaylistItem {
  const PlaylistItem({
    required this.workId,
    required this.workTitle,
    required this.kind,
    this.year,
    this.posterUrl,
    required this.subtitle,
    this.playFileId,
    this.playFileName,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
  });

  final int workId;
  final String workTitle;
  final String kind;
  final int? year;
  final String? posterUrl;
  final String subtitle;
  final int? playFileId;
  final String? playFileName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      workId: asInt(json['workId']),
      workTitle: json['workTitle']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      year: asIntOrNull(json['year']),
      posterUrl: json['posterUrl']?.toString(),
      subtitle: json['subtitle']?.toString() ?? '',
      playFileId: asIntOrNull(json['playFileId']),
      playFileName: json['playFileName']?.toString(),
      seasonNumber: asIntOrNull(json['seasonNumber']),
      episodeNumber: asIntOrNull(json['episodeNumber']),
      episodeTitle: json['episodeTitle']?.toString(),
    );
  }
}

class PlaylistDetail {
  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.items,
  });

  final int id;
  final String name;
  final List<PlaylistItem> items;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PlaylistDetail(
      id: asInt(json['id']),
      name: json['name']?.toString() ?? '',
      items: raw is List
          ? raw.whereType<Map>().map((item) => PlaylistItem.fromJson(Map<String, dynamic>.from(item))).toList()
          : const [],
    );
  }
}

class PlaylistQueueEntry {
  const PlaylistQueueEntry({
    required this.workId,
    required this.workTitle,
    required this.kind,
    this.posterUrl,
    required this.fileId,
    required this.fileName,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    required this.label,
  });

  final int workId;
  final String workTitle;
  final String kind;
  final String? posterUrl;
  final int fileId;
  final String fileName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String label;

  factory PlaylistQueueEntry.fromJson(Map<String, dynamic> json) {
    return PlaylistQueueEntry(
      workId: asInt(json['workId']),
      workTitle: json['workTitle']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      posterUrl: json['posterUrl']?.toString(),
      fileId: asInt(json['fileId']),
      fileName: json['fileName']?.toString() ?? 'video',
      seasonNumber: asIntOrNull(json['seasonNumber']),
      episodeNumber: asIntOrNull(json['episodeNumber']),
      episodeTitle: json['episodeTitle']?.toString(),
      label: json['label']?.toString() ?? '',
    );
  }
}

class CollectionCard {
  const CollectionCard({
    required this.id,
    required this.name,
    required this.posterUrl,
    required this.count,
  });

  final String id;
  final String name;
  final String? posterUrl;
  final int count;

  factory CollectionCard.fromJson(Map<String, dynamic> json) {
    return CollectionCard(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      posterUrl: json['posterUrl']?.toString(),
      count: asInt(json['count']),
    );
  }
}

class CollectionPart {
  const CollectionPart({
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.year,
    required this.releaseDate,
    required this.posterUrl,
    required this.backdropUrl,
    required this.workId,
    required this.hasLocalMedia,
    required this.rating,
    required this.voteCount,
    required this.genres,
    required this.originalLanguage,
  });

  final String tmdbId;
  final String title;
  final String? originalTitle;
  final String? overview;
  final int? year;
  final String? releaseDate;
  final String? posterUrl;
  final String? backdropUrl;
  final int? workId;
  final bool hasLocalMedia;
  final double? rating;
  final int? voteCount;
  final List<String> genres;
  final String? originalLanguage;

  bool get inLibrary => hasLocalMedia;

  factory CollectionPart.fromJson(Map<String, dynamic> json) {
    return CollectionPart(
      tmdbId: json['tmdbId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      originalTitle: json['originalTitle']?.toString(),
      overview: json['overview']?.toString(),
      year: asIntOrNull(json['year']),
      releaseDate: json['releaseDate']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      workId: asIntOrNull(json['workId']),
      hasLocalMedia: json['hasLocalMedia'] == true,
      rating: asDouble(json['rating']),
      voteCount: asIntOrNull(json['voteCount']),
      genres: _stringList(json['genres']),
      originalLanguage: json['originalLanguage']?.toString(),
    );
  }
}

class CollectionDetail {
  const CollectionDetail({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterUrl,
    required this.backdropUrl,
    required this.parts,
    required this.localCount,
  });

  final String id;
  final String name;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final List<CollectionPart> parts;
  final int localCount;

  factory CollectionDetail.fromJson(Map<String, dynamic> json) {
    return CollectionDetail(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      overview: json['overview']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      parts: _maps(json['parts']).map(CollectionPart.fromJson).toList(),
      localCount: asInt(json['localCount']),
    );
  }
}

class PersonWorkCredit {
  const PersonWorkCredit({
    required this.mediaType,
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.releaseDate,
    required this.posterUrl,
    required this.character,
    required this.job,
    required this.department,
    required this.workId,
    required this.hasLocalMedia,
  });

  final String mediaType;
  final String tmdbId;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? releaseDate;
  final String? posterUrl;
  final String? character;
  final String? job;
  final String? department;
  final int? workId;
  final bool hasLocalMedia;

  bool get inLibrary => hasLocalMedia;

  String get role {
    final characterName = character?.trim();
    if (characterName != null && characterName.isNotEmpty) return characterName;
    final jobName = job?.trim();
    if (jobName != null && jobName.isNotEmpty) return jobName;
    return department?.trim() ?? '';
  }

  factory PersonWorkCredit.fromJson(Map<String, dynamic> json) {
    return PersonWorkCredit(
      mediaType: json['mediaType']?.toString() ?? 'movie',
      tmdbId: json['tmdbId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      originalTitle: json['originalTitle']?.toString(),
      year: asIntOrNull(json['year']),
      releaseDate: json['releaseDate']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      character: json['character']?.toString(),
      job: json['job']?.toString(),
      department: json['department']?.toString(),
      workId: asIntOrNull(json['workId']),
      hasLocalMedia: json['hasLocalMedia'] == true,
    );
  }
}

class PersonDetail {
  const PersonDetail({
    required this.provider,
    required this.externalId,
    required this.name,
    required this.biography,
    required this.birthday,
    required this.deathday,
    required this.placeOfBirth,
    required this.profileUrl,
    required this.knownForDepartment,
    required this.alsoKnownAs,
    required this.credits,
    required this.localCount,
    required this.detailFetchedAt,
  });

  final String provider;
  final String externalId;
  final String name;
  final String? biography;
  final String? birthday;
  final String? deathday;
  final String? placeOfBirth;
  final String? profileUrl;
  final String? knownForDepartment;
  final List<String> alsoKnownAs;
  final List<PersonWorkCredit> credits;
  final int localCount;
  final String? detailFetchedAt;

  bool get canRefresh => provider.trim().toLowerCase() == 'tmdb';

  factory PersonDetail.fromJson(Map<String, dynamic> json) {
    final aka = json['alsoKnownAs'];
    return PersonDetail(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      biography: json['biography']?.toString(),
      birthday: json['birthday']?.toString(),
      deathday: json['deathday']?.toString(),
      placeOfBirth: json['placeOfBirth']?.toString(),
      profileUrl: json['profileUrl']?.toString(),
      knownForDepartment: json['knownForDepartment']?.toString(),
      alsoKnownAs: aka is List
          ? aka.map((item) => item?.toString().trim() ?? '').where((item) => item.isNotEmpty).toList()
          : const [],
      credits: _maps(json['credits']).map(PersonWorkCredit.fromJson).toList(),
      localCount: asInt(json['localCount']),
      detailFetchedAt: json['detailFetchedAt']?.toString(),
    );
  }
}

class ScrapeJobStats {
  const ScrapeJobStats({required this.active});

  final int active;

  factory ScrapeJobStats.fromJson(Map<String, dynamic> json) {
    return ScrapeJobStats(active: asInt(json['active']));
  }
}

class ScrapeJobRow {
  const ScrapeJobRow({
    required this.id,
    required this.status,
    required this.attempts,
    required this.maxAttempts,
    required this.progress,
    required this.lastError,
    required this.fileId,
    required this.fileName,
    required this.locator,
    required this.matchStatus,
    required this.parsedTitle,
    required this.parsedYear,
    required this.parsedSeason,
    required this.parsedEpisode,
    required this.confidence,
    required this.message,
    required this.workId,
    required this.mediaLibraryId,
    required this.mediaLibraryName,
  });

  final int id;
  final String status;
  final int attempts;
  final int maxAttempts;
  final String? progress;
  final String? lastError;
  final int fileId;
  final String fileName;
  final String locator;
  final String matchStatus;
  final String? parsedTitle;
  final int? parsedYear;
  final int? parsedSeason;
  final int? parsedEpisode;
  final double? confidence;
  final String? message;
  final int? workId;
  final int? mediaLibraryId;
  final String? mediaLibraryName;

  bool get canManualMatch =>
      matchStatus == 'needs_review' || matchStatus == 'failed' || matchStatus == 'matched';

  bool get canDelete => status != 'running';

  bool get canRetry => status == 'failed' || matchStatus == 'failed';

  bool get isLive => status == 'queued' || status == 'running';

  factory ScrapeJobRow.fromJson(Map<String, dynamic> json) {
    return ScrapeJobRow(
      id: asInt(json['id']),
      status: json['status']?.toString() ?? '',
      attempts: asInt(json['attempts']),
      maxAttempts: asInt(json['maxAttempts']),
      progress: json['progress']?.toString(),
      lastError: json['lastError']?.toString(),
      fileId: asInt(json['fileId']),
      fileName: json['fileName']?.toString() ?? '',
      locator: json['locator']?.toString() ?? '',
      matchStatus: json['matchStatus']?.toString() ?? '',
      parsedTitle: json['parsedTitle']?.toString(),
      parsedYear: asIntOrNull(json['parsedYear']),
      parsedSeason: asIntOrNull(json['parsedSeason']),
      parsedEpisode: asIntOrNull(json['parsedEpisode']),
      confidence: asDouble(json['confidence']),
      message: json['message']?.toString(),
      workId: asIntOrNull(json['workId']),
      mediaLibraryId: asIntOrNull(json['mediaLibraryId']),
      mediaLibraryName: json['mediaLibraryName']?.toString(),
    );
  }
}

class MatchCandidate {
  const MatchCandidate({
    required this.provider,
    required this.kind,
    required this.externalId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.overview,
    required this.posterUrl,
    required this.score,
  });

  final String provider;
  final String kind;
  final String externalId;
  final String? title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterUrl;
  final double score;

  factory MatchCandidate.fromJson(Map<String, dynamic> json) {
    return MatchCandidate(
      provider: json['provider']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'movie',
      externalId: json['externalId']?.toString() ?? '',
      title: json['title']?.toString(),
      originalTitle: json['originalTitle']?.toString(),
      year: asIntOrNull(json['year']),
      overview: json['overview']?.toString(),
      posterUrl: json['posterUrl']?.toString(),
      score: asDouble(json['score']) ?? 0,
    );
  }
}

class BrowseEntry {
  const BrowseEntry({required this.name, required this.path});

  final String name;
  final String path;

  factory BrowseEntry.fromJson(Map<String, dynamic> json) {
    return BrowseEntry(
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
    );
  }
}

class BrowseResult {
  const BrowseResult({
    required this.path,
    required this.parent,
    required this.directories,
  });

  final String path;
  final String? parent;
  final List<BrowseEntry> directories;

  factory BrowseResult.fromJson(Map<String, dynamic> json) {
    final dirs = json['directories'];
    return BrowseResult(
      path: json['path']?.toString() ?? '',
      parent: json['parent']?.toString(),
      directories: dirs is List
          ? dirs.whereType<Map>().map((item) => BrowseEntry.fromJson(Map<String, dynamic>.from(item))).toList()
          : const [],
    );
  }
}

class AppSettings {
  const AppSettings({
    required this.tmdbApiKeyConfigured,
    required this.tmdbBaseUrl,
    required this.tmdbImageBaseUrl,
    required this.tmdbLanguage,
    required this.tmdbSearchLanguage,
    required this.tmdbRequestsPerSecond,
    required this.omdbApiKeyConfigured,
    required this.omdbBaseUrl,
    required this.omdbRequestsPerSecond,
    required this.tvdbEnabled,
    required this.tvdbApiKeyConfigured,
    required this.tvdbPinConfigured,
    required this.tvdbBaseUrl,
    required this.tvdbRequestsPerSecond,
    required this.httpTimeoutSeconds,
    required this.matchAutoThreshold,
    required this.workerDelayMs,
    required this.workerMaxAttempts,
    required this.workerConcurrency,
    required this.scanIntervalMinutes,
    required this.watchEnabled,
    required this.playbackIgnoreBelowSeconds,
    required this.playbackCompleteRemainingSeconds,
  });

  final bool tmdbApiKeyConfigured;
  final String tmdbBaseUrl;
  final String tmdbImageBaseUrl;
  final String tmdbLanguage;
  final String tmdbSearchLanguage;
  final double tmdbRequestsPerSecond;
  final bool omdbApiKeyConfigured;
  final String omdbBaseUrl;
  final double omdbRequestsPerSecond;
  final bool tvdbEnabled;
  final bool tvdbApiKeyConfigured;
  final bool tvdbPinConfigured;
  final String tvdbBaseUrl;
  final double tvdbRequestsPerSecond;
  final int httpTimeoutSeconds;
  final double matchAutoThreshold;
  final int workerDelayMs;
  final int workerMaxAttempts;
  final int workerConcurrency;
  final int scanIntervalMinutes;
  final bool watchEnabled;
  final int playbackIgnoreBelowSeconds;
  final int playbackCompleteRemainingSeconds;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      tmdbApiKeyConfigured: asBool(json['tmdbApiKeyConfigured']),
      tmdbBaseUrl: json['tmdbBaseUrl']?.toString() ?? '',
      tmdbImageBaseUrl: json['tmdbImageBaseUrl']?.toString() ?? '',
      tmdbLanguage: json['tmdbLanguage']?.toString() ?? '',
      tmdbSearchLanguage: json['tmdbSearchLanguage']?.toString() ?? '',
      tmdbRequestsPerSecond: asDouble(json['tmdbRequestsPerSecond']) ?? 30,
      omdbApiKeyConfigured: asBool(json['omdbApiKeyConfigured']),
      omdbBaseUrl: json['omdbBaseUrl']?.toString() ?? '',
      omdbRequestsPerSecond: asDouble(json['omdbRequestsPerSecond']) ?? 30,
      tvdbEnabled: asBool(json['tvdbEnabled']),
      tvdbApiKeyConfigured: asBool(json['tvdbApiKeyConfigured']),
      tvdbPinConfigured: asBool(json['tvdbPinConfigured']),
      tvdbBaseUrl: json['tvdbBaseUrl']?.toString() ?? '',
      tvdbRequestsPerSecond: asDouble(json['tvdbRequestsPerSecond']) ?? 30,
      httpTimeoutSeconds: asInt(json['httpTimeoutSeconds']),
      matchAutoThreshold: asDouble(json['matchAutoThreshold']) ?? 0.72,
      workerDelayMs: asInt(json['workerDelayMs']),
      workerMaxAttempts: asInt(json['workerMaxAttempts']),
      workerConcurrency: asInt(json['workerConcurrency']),
      scanIntervalMinutes: asInt(json['scanIntervalMinutes']),
      watchEnabled: asBool(json['watchEnabled']),
      playbackIgnoreBelowSeconds: asIntOrNull(json['playbackIgnoreBelowSeconds']) ?? 10,
      playbackCompleteRemainingSeconds: asIntOrNull(json['playbackCompleteRemainingSeconds']) ?? 30,
    );
  }
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item?.toString().trim() ?? '').where((item) => item.isNotEmpty).toList();
}

class WorkTranslation {
  const WorkTranslation({required this.locale, required this.title, required this.overview, required this.tagline});

  final String locale;
  final String title;
  final String? overview;
  final String? tagline;

  factory WorkTranslation.fromJson(Map<String, dynamic> json) {
    return WorkTranslation(
      locale: json['locale']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      overview: json['overview']?.toString(),
      tagline: json['tagline']?.toString(),
    );
  }
}

class WorkRating {
  const WorkRating({
    required this.provider,
    required this.value,
    required this.votes,
    required this.scale,
  });

  final String provider;
  final double value;
  final int? votes;
  final double scale;

  String get label {
    switch (provider) {
      case 'imdb':
        return 'IMDb';
      case 'tmdb':
        return 'TMDB';
      case 'tvdb':
        return 'TVDB';
      case 'rottentomatoes':
        return '烂番茄';
      case 'rt_audience':
        return '观众';
      case 'metacritic':
        return 'MC';
      default:
        return provider.toUpperCase();
    }
  }

  String get text {
    if (provider == 'rottentomatoes' || provider == 'rt_audience' || scale == 100) {
      return '${value.round()}';
    }
    return value.toStringAsFixed(1);
  }

  String get display => provider == 'rottentomatoes' || provider == 'rt_audience' ? '$text%' : text;

  String? get kindLabel {
    if (provider == 'rottentomatoes') return '影评';
    if (provider == 'rt_audience') return '观众';
    return null;
  }

  String get votesLabel {
    final count = votes;
    if (count == null) return '';
    final digits = count.toString();
    final grouped = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
      grouped.write(digits[i]);
    }
    return '（$grouped 票）';
  }

  String? get logoAsset => providerLogoAsset(provider);

  factory WorkRating.fromJson(Map<String, dynamic> json) {
    return WorkRating(
      provider: json['provider']?.toString() ?? '',
      value: asDouble(json['value']) ?? 0,
      votes: asIntOrNull(json['votes']),
      scale: asDouble(json['scale']) ?? 10,
    );
  }
}

class WorkCredit {
  const WorkCredit({
    required this.provider,
    required this.externalId,
    required this.name,
    required this.profileUrl,
    required this.department,
    required this.job,
    required this.character,
    required this.order,
  });

  final String provider;
  final String externalId;
  final String name;
  final String? profileUrl;
  final String? department;
  final String? job;
  final String? character;
  final int order;

  bool get isCast =>
      (character != null && character!.isNotEmpty) ||
      department == 'Acting' ||
      department == 'cast' ||
      job == 'Actor' ||
      job == 'actor' ||
      job == 'guest_star';

  String get subtitle => isCast
      ? (character?.isNotEmpty == true ? character! : (job == 'guest_star' ? '嘉宾' : '演员'))
      : (job ?? department ?? '制作');

  factory WorkCredit.fromJson(Map<String, dynamic> json) {
    return WorkCredit(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      profileUrl: json['profileUrl']?.toString(),
      department: json['department']?.toString(),
      job: json['job']?.toString(),
      character: json['character']?.toString(),
      order: asIntOrNull(json['order']) ?? 0,
    );
  }
}

class SeasonCard {
  const SeasonCard({
    required this.seasonNumber,
    required this.name,
    required this.localEpisodeCount,
    required this.episodeCount,
    required this.airDate,
    required this.posterUrl,
  });

  final int seasonNumber;
  final String? name;
  final int localEpisodeCount;
  final int? episodeCount;
  final String? airDate;
  final String? posterUrl;

  String get heading {
    final base = '第 $seasonNumber 季';
    final label = name?.trim();
    if (label == null || label.isEmpty || label == base || RegExp(r'^season\s*\d+$', caseSensitive: false).hasMatch(label)) {
      return base;
    }
    return '$base $label';
  }

  factory SeasonCard.fromJson(Map<String, dynamic> json) {
    final arts = _maps(json['artworks']);
    String? poster;
    for (final art in arts) {
      final url = art['remoteUrl']?.toString();
      if (url == null || url.isEmpty) continue;
      if (art['kind'] == 'poster') {
        poster = url;
        break;
      }
      poster ??= url;
    }
    return SeasonCard(
      seasonNumber: asInt(json['seasonNumber']),
      name: json['name']?.toString(),
      localEpisodeCount: asIntOrNull(json['localEpisodeCount']) ?? 0,
      episodeCount: asIntOrNull(json['episodeCount']),
      airDate: json['airDate']?.toString(),
      posterUrl: poster,
    );
  }
}

class WorkFact {
  const WorkFact(this.label, this.value, {this.href});

  final String label;
  final String value;
  final String? href;
}

class WorkExternalId {
  const WorkExternalId({required this.provider, required this.externalId});

  final String provider;
  final String externalId;

  String get title => providerTitle(provider);

  String? get logoAsset => providerLogoAsset(provider);

  String? urlFor(String kind) {
    if (externalId.startsWith('http://') || externalId.startsWith('https://')) return externalId;
    switch (provider) {
      case 'tmdb':
        if (kind == 'episode') return 'https://www.themoviedb.org/tv/episode/$externalId';
        return kind == 'series' ? 'https://www.themoviedb.org/tv/$externalId' : 'https://www.themoviedb.org/movie/$externalId';
      case 'imdb':
        return 'https://www.imdb.com/title/$externalId';
      case 'tvdb':
        return kind == 'episode'
            ? 'https://www.thetvdb.com/?tab=episode&id=$externalId'
            : 'https://www.thetvdb.com/?tab=series&id=$externalId';
      case 'wikidata':
        return 'https://www.wikidata.org/wiki/$externalId';
      case 'facebook':
        return 'https://www.facebook.com/$externalId';
      case 'instagram':
        return 'https://www.instagram.com/$externalId';
      case 'twitter':
        return 'https://twitter.com/$externalId';
      default:
        return null;
    }
  }

  factory WorkExternalId.fromJson(Map<String, dynamic> json) {
    return WorkExternalId(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
    );
  }
}

class WorkArtwork {
  const WorkArtwork({required this.kind, required this.remoteUrl});

  final String kind;
  final String remoteUrl;

  factory WorkArtwork.fromJson(Map<String, dynamic> json) {
    return WorkArtwork(
      kind: json['kind']?.toString() ?? '',
      remoteUrl: json['remoteUrl']?.toString() ?? '',
    );
  }
}

class WorkKeyword {
  const WorkKeyword({required this.name});

  final String name;

  factory WorkKeyword.fromJson(Map<String, dynamic> json) {
    return WorkKeyword(name: json['name']?.toString() ?? '');
  }
}

class WorkCompany {
  const WorkCompany({
    required this.name,
    required this.originCountry,
    required this.logoUrl,
    required this.role,
  });

  final String name;
  final String? originCountry;
  final String? logoUrl;
  final String role;

  String get roleLabel {
    switch (role) {
      case 'production':
        return '制片';
      case 'network':
        return '播出网络';
      case 'distributor':
        return '发行';
      default:
        return role;
    }
  }

  factory WorkCompany.fromJson(Map<String, dynamic> json) {
    return WorkCompany(
      name: json['name']?.toString() ?? '',
      originCountry: json['originCountry']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      role: json['role']?.toString() ?? '',
    );
  }
}

class WorkCountry {
  const WorkCountry({required this.code, required this.name, required this.kind});

  final String code;
  final String? name;
  final String kind;

  String get label => name?.trim().isNotEmpty == true ? name!.trim() : code;

  factory WorkCountry.fromJson(Map<String, dynamic> json) {
    return WorkCountry(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString(),
      kind: json['kind']?.toString() ?? '',
    );
  }
}

class WorkLanguage {
  const WorkLanguage({required this.code, required this.name});

  final String code;
  final String? name;

  String get label => name?.trim().isNotEmpty == true ? name!.trim() : code;

  factory WorkLanguage.fromJson(Map<String, dynamic> json) {
    return WorkLanguage(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString(),
    );
  }
}

class WorkVideo {
  const WorkVideo({
    required this.site,
    required this.type,
    required this.name,
    required this.key,
    required this.language,
    required this.official,
  });

  final String? site;
  final String? type;
  final String? name;
  final String? key;
  final String? language;
  final bool? official;

  String get heading {
    final title = name?.trim();
    if (title != null && title.isNotEmpty) return title;
    final kind = type?.trim();
    if (kind != null && kind.isNotEmpty) return kind;
    return '视频';
  }

  String get meta {
    final parts = [
      if (site != null && site!.trim().isNotEmpty) site!.trim() else '—',
      if (type != null && type!.trim().isNotEmpty) type!.trim(),
      if (language != null && language!.trim().isNotEmpty) language!.trim(),
      if (official != null) (official! ? '官方' : '非官方'),
    ];
    return parts.join(' · ');
  }

  String? get url {
    final id = key?.trim();
    if (id == null || id.isEmpty) return null;
    final host = (site ?? '').toLowerCase();
    if (host.contains('youtube')) return 'https://www.youtube.com/watch?v=$id';
    if (host.contains('vimeo')) return 'https://vimeo.com/$id';
    return null;
  }

  factory WorkVideo.fromJson(Map<String, dynamic> json) {
    return WorkVideo(
      site: json['site']?.toString(),
      type: json['type']?.toString(),
      name: json['name']?.toString(),
      key: json['key']?.toString(),
      language: json['language']?.toString(),
      official: asBoolOrNull(json['official']),
    );
  }
}

class WorkPerson {
  const WorkPerson({
    required this.provider,
    required this.externalId,
    required this.name,
    required this.profileUrl,
    required this.images,
  });

  final String provider;
  final String externalId;
  final String name;
  final String? profileUrl;
  final List<WorkArtwork> images;

  String get subtitle => '${provider.toUpperCase()} · $externalId';

  String? get imageUrl {
    final profile = profileUrl?.trim();
    if (profile != null && profile.isNotEmpty) return profile;
    for (final image in images) {
      if (image.kind == 'poster' || image.kind == 'still') {
        if (image.remoteUrl.isNotEmpty) return image.remoteUrl;
      }
    }
    for (final image in images) {
      if (image.remoteUrl.isNotEmpty) return image.remoteUrl;
    }
    return null;
  }

  factory WorkPerson.fromJson(Map<String, dynamic> json) {
    return WorkPerson(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      profileUrl: json['profileUrl']?.toString(),
      images: _maps(json['images']).map(WorkArtwork.fromJson).where((item) => item.remoteUrl.isNotEmpty).toList(),
    );
  }
}

String providerTitle(String provider) {
  switch (provider) {
    case 'tmdb':
      return 'TMDB';
    case 'tvdb':
      return 'TVDB';
    case 'imdb':
      return 'IMDb';
    case 'rottentomatoes':
      return '烂番茄';
    case 'rt_audience':
      return '观众';
    case 'metacritic':
      return 'Metacritic';
    case 'wikidata':
      return 'Wikidata';
    case 'facebook':
      return 'Facebook';
    case 'instagram':
      return 'Instagram';
    case 'twitter':
      return 'X';
    case 'tvrage':
      return 'TVRage';
    case 'freebase':
      return 'Freebase';
    default:
      return provider.toUpperCase();
  }
}

String? providerLogoAsset(String provider) {
  switch (provider) {
    case 'imdb':
      return 'assets/providers/imdb.svg';
    case 'tmdb':
      return 'assets/providers/tmdb.svg';
    case 'tvdb':
      return 'assets/providers/tvdb.png';
    case 'rottentomatoes':
      return 'assets/providers/rt.svg';
    case 'rt_audience':
      return 'assets/providers/rt-audience.svg';
    case 'metacritic':
      return 'assets/providers/metacritic.svg';
    case 'wikidata':
      return 'assets/providers/wikidata.svg';
    case 'facebook':
      return 'assets/providers/facebook.svg';
    case 'instagram':
      return 'assets/providers/instagram.svg';
    case 'twitter':
      return 'assets/providers/twitter.svg';
    case 'freebase':
      return 'assets/providers/freebase.svg';
    default:
      return null;
  }
}

String artworkKindLabel(String kind) {
  switch (kind) {
    case 'poster':
      return '海报';
    case 'backdrop':
      return '背景';
    case 'still':
      return '剧照';
    case 'logo':
      return 'Logo';
    case 'collection_poster':
      return '系列海报';
    case 'collection_backdrop':
      return '系列背景';
    default:
      return kind;
  }
}

class MediaTrack {
  const MediaTrack({
    this.codec,
    this.channels,
    this.language,
    this.bitrate,
    this.sampleRate,
    this.channelLayout,
    this.profile,
  });

  final String? codec;
  final int? channels;
  final String? language;
  final int? bitrate;
  final int? sampleRate;
  final String? channelLayout;
  final String? profile;

  factory MediaTrack.fromJson(Map<String, dynamic> json) {
    return MediaTrack(
      codec: json['codec']?.toString(),
      channels: asIntOrNull(json['channels']),
      language: json['language']?.toString(),
      bitrate: asIntOrNull(json['bitrate']),
      sampleRate: asIntOrNull(json['sampleRate']),
      channelLayout: json['channelLayout']?.toString(),
      profile: json['profile']?.toString(),
    );
  }
}

class LibraryFileBrief {
  const LibraryFileBrief({
    required this.id,
    required this.fileName,
    required this.locator,
    this.parsedTitle,
    this.parsedYear,
    this.parsedSeason,
    this.parsedEpisode,
    this.fileSize,
    this.sourceModifiedAt,
    this.container,
    this.durationMs,
    this.videoCodec,
    this.videoWidth,
    this.videoHeight,
    this.videoFrameRate,
    this.videoBitrate,
    this.videoBitDepth,
    this.videoDynamicRange,
    this.videoProfile,
    this.videoPixelFormat,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
  });

  final int id;
  final String fileName;
  final String locator;
  final String? parsedTitle;
  final int? parsedYear;
  final int? parsedSeason;
  final int? parsedEpisode;
  final int? fileSize;
  final String? sourceModifiedAt;
  final String? container;
  final int? durationMs;
  final String? videoCodec;
  final int? videoWidth;
  final int? videoHeight;
  final double? videoFrameRate;
  final int? videoBitrate;
  final int? videoBitDepth;
  final String? videoDynamicRange;
  final String? videoProfile;
  final String? videoPixelFormat;
  final List<MediaTrack> audioTracks;
  final List<MediaTrack> subtitleTracks;

  factory LibraryFileBrief.fromJson(Map<String, dynamic> json) {
    return LibraryFileBrief(
      id: asInt(json['id']),
      fileName: json['fileName']?.toString() ?? '',
      locator: json['locator']?.toString() ?? '',
      parsedTitle: json['parsedTitle']?.toString(),
      parsedYear: asIntOrNull(json['parsedYear']),
      parsedSeason: asIntOrNull(json['parsedSeason']),
      parsedEpisode: asIntOrNull(json['parsedEpisode']),
      fileSize: asIntOrNull(json['fileSize']),
      sourceModifiedAt: json['sourceModifiedAt']?.toString(),
      container: json['container']?.toString(),
      durationMs: asIntOrNull(json['durationMs']),
      videoCodec: json['videoCodec']?.toString(),
      videoWidth: asIntOrNull(json['videoWidth']),
      videoHeight: asIntOrNull(json['videoHeight']),
      videoFrameRate: asDouble(json['videoFrameRate']),
      videoBitrate: asIntOrNull(json['videoBitrate']),
      videoBitDepth: asIntOrNull(json['videoBitDepth']),
      videoDynamicRange: json['videoDynamicRange']?.toString(),
      videoProfile: json['videoProfile']?.toString(),
      videoPixelFormat: json['videoPixelFormat']?.toString(),
      audioTracks: _maps(json['audioTracks']).map(MediaTrack.fromJson).toList(),
      subtitleTracks: _maps(json['subtitleTracks']).map(MediaTrack.fromJson).toList(),
    );
  }
}

class WorkDetail {
  const WorkDetail({
    required this.id,
    required this.kind,
    required this.originalTitle,
    required this.originalLanguage,
    required this.year,
    required this.premiereDate,
    required this.runtimeMinutes,
    required this.status,
    required this.homepage,
    required this.popularity,
    required this.budget,
    required this.revenue,
    required this.adult,
    required this.showType,
    required this.inProduction,
    required this.lastAirDate,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.collectionExternalId,
    required this.collectionName,
    required this.awards,
    required this.sourceProvider,
    required this.translations,
    required this.externalIds,
    required this.ratings,
    required this.artworks,
    required this.genres,
    required this.credits,
    required this.people,
    required this.companies,
    required this.countries,
    required this.spokenLanguages,
    required this.keywords,
    required this.videos,
    required this.seasons,
    required this.files,
    required this.posterUrl,
    required this.backdropUrl,
  });

  final int id;
  final String kind;
  final String originalTitle;
  final String? originalLanguage;
  final int? year;
  final String? premiereDate;
  final int? runtimeMinutes;
  final String? status;
  final String? homepage;
  final double? popularity;
  final int? budget;
  final int? revenue;
  final bool? adult;
  final String? showType;
  final bool? inProduction;
  final String? lastAirDate;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final String? collectionExternalId;
  final String? collectionName;
  final String? awards;
  final String? sourceProvider;
  final List<WorkTranslation> translations;
  final List<WorkExternalId> externalIds;
  final List<WorkRating> ratings;
  final List<WorkArtwork> artworks;
  final List<String> genres;
  final List<WorkCredit> credits;
  final List<WorkPerson> people;
  final List<WorkCompany> companies;
  final List<WorkCountry> countries;
  final List<WorkLanguage> spokenLanguages;
  final List<WorkKeyword> keywords;
  final List<WorkVideo> videos;
  final List<SeasonCard> seasons;
  final List<LibraryFileBrief> files;
  final String? posterUrl;
  final String? backdropUrl;

  bool get isSeries => kind == 'series';

  String get displayTitle {
    for (final item in translations) {
      if (item.locale == 'zh-CN' && item.title.trim().isNotEmpty) return item.title.trim();
    }
    return originalTitle;
  }

  String? get overview {
    for (final item in translations) {
      final text = item.overview?.trim();
      if (item.locale == 'zh-CN' && text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  String? get tagline {
    for (final item in translations) {
      final text = item.tagline?.trim();
      if (item.locale == 'zh-CN' && text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  List<WorkRating> get sortedRatings {
    int rank(String provider) {
      switch (provider) {
        case 'imdb':
          return 0;
        case 'rottentomatoes':
          return 1;
        case 'rt_audience':
          return 2;
        case 'metacritic':
          return 3;
        case 'tmdb':
          return 4;
        default:
          return 5;
      }
    }

    final rows = [...ratings];
    rows.sort((a, b) => rank(a.provider).compareTo(rank(b.provider)));
    return rows;
  }

  List<WorkCredit> get cast {
    final rows = credits.where((item) => item.isCast).toList();
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  List<WorkCredit> get crew {
    final rows = credits.where((item) => !item.isCast).toList();
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  List<({String kind, List<WorkArtwork> items})> get artworksByKind {
    final grouped = <String, List<WorkArtwork>>{};
    for (final art in artworks) {
      if (art.remoteUrl.isEmpty) continue;
      grouped.putIfAbsent(art.kind, () => []).add(art);
    }
    return [for (final entry in grouped.entries) (kind: entry.key, items: entry.value)];
  }

  List<WorkFact> get facts {
    final rows = <WorkFact>[];
    void push(String label, String? value, {String? href}) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return;
      rows.add(WorkFact(label, text, href: href));
    }

    String? flag(bool? value) {
      if (value == null) return null;
      return value ? '是' : '否';
    }

    String? money(int? value) {
      if (value == null) return null;
      final digits = value.abs().toString();
      final grouped = StringBuffer();
      for (var i = 0; i < digits.length; i++) {
        if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
        grouped.write(digits[i]);
      }
      return '${value < 0 ? '-' : ''}US\$$grouped';
    }

    push('ID', '$id');
    push('类型', kind == 'series' ? '剧集' : '电影');
    push('来源', sourceProvider?.trim().isNotEmpty == true ? sourceProvider!.toUpperCase() : null);
    push('原始片名', originalTitle);
    push('原始语言', originalLanguage);
    push('年份', year?.toString());
    push('首映/首播', premiereDate);
    push('最后播出', lastAirDate);
    push('片长', runtimeMinutes == null ? null : '$runtimeMinutes 分钟');
    push('状态', status);
    push('节目形态', showType);
    push('制作中', flag(inProduction));
    push('成人内容', flag(adult));
    push('季数', numberOfSeasons?.toString());
    push('集数', numberOfEpisodes?.toString());
    push('热度', popularity?.toStringAsFixed(3));
    push('预算', money(budget));
    push('票房', money(revenue));
    push('系列', collectionName);
    push('系列 ID', collectionExternalId);
    push('奖项', awards);
    final site = homepage?.trim();
    push('官网', site, href: site);
    return rows;
  }

  factory WorkDetail.fromJson(Map<String, dynamic> json) {
    final arts = _maps(json['artworks']);
    String? pickArt(String kind, {String? locale}) {
      for (final art in arts) {
        if (art['kind'] != kind) continue;
        if (locale != null && art['locale'] != locale) continue;
        final url = art['remoteUrl']?.toString();
        if (url != null && url.isNotEmpty) return url;
      }
      return null;
    }

    return WorkDetail(
      id: asInt(json['id']),
      kind: json['kind']?.toString() ?? 'movie',
      originalTitle: json['originalTitle']?.toString() ?? '',
      originalLanguage: json['originalLanguage']?.toString(),
      year: asIntOrNull(json['year']),
      premiereDate: json['premiereDate']?.toString(),
      runtimeMinutes: asIntOrNull(json['runtimeMinutes']),
      status: json['status']?.toString(),
      homepage: json['homepage']?.toString(),
      popularity: asDouble(json['popularity']),
      budget: asIntOrNull(json['budget']),
      revenue: asIntOrNull(json['revenue']),
      adult: asBoolOrNull(json['adult']),
      showType: json['showType']?.toString(),
      inProduction: asBoolOrNull(json['inProduction']),
      lastAirDate: json['lastAirDate']?.toString(),
      numberOfSeasons: asIntOrNull(json['numberOfSeasons']),
      numberOfEpisodes: asIntOrNull(json['numberOfEpisodes']),
      collectionExternalId: json['collectionExternalId']?.toString(),
      collectionName: json['collectionName']?.toString(),
      awards: json['awards']?.toString(),
      sourceProvider: json['sourceProvider']?.toString(),
      translations: _maps(json['translations']).map(WorkTranslation.fromJson).toList(),
      externalIds: _maps(json['externalIds']).map(WorkExternalId.fromJson).where((item) => item.externalId.isNotEmpty).toList(),
      ratings: _maps(json['ratings']).map(WorkRating.fromJson).toList(),
      artworks: arts.map(WorkArtwork.fromJson).where((item) => item.remoteUrl.isNotEmpty).toList(),
      genres: _maps(json['genres']).map((item) => item['name']?.toString() ?? '').where((name) => name.isNotEmpty).toList(),
      credits: _maps(json['credits']).map(WorkCredit.fromJson).toList(),
      people: _maps(json['people']).map(WorkPerson.fromJson).where((item) => item.name.isNotEmpty).toList(),
      companies: _maps(json['companies']).map(WorkCompany.fromJson).where((item) => item.name.isNotEmpty).toList(),
      countries: _maps(json['countries']).map(WorkCountry.fromJson).where((item) => item.code.isNotEmpty || (item.name?.isNotEmpty ?? false)).toList(),
      spokenLanguages: _maps(json['spokenLanguages']).map(WorkLanguage.fromJson).where((item) => item.code.isNotEmpty || (item.name?.isNotEmpty ?? false)).toList(),
      keywords: _maps(json['keywords']).map(WorkKeyword.fromJson).where((item) => item.name.isNotEmpty).toList(),
      videos: _maps(json['videos']).map(WorkVideo.fromJson).toList(),
      seasons: _maps(json['seasons']).map(SeasonCard.fromJson).toList(),
      files: _maps(json['libraryFiles']).map(LibraryFileBrief.fromJson).toList(),
      posterUrl: pickArt('poster', locale: 'zh-CN') ?? pickArt('poster'),
      backdropUrl: pickArt('backdrop'),
    );
  }
}

class EpisodeRow {
  const EpisodeRow({
    required this.id,
    required this.number,
    required this.absoluteNumber,
    required this.title,
    required this.overview,
    required this.airDate,
    required this.runtimeMinutes,
    required this.voteAverage,
    required this.voteCount,
    required this.stillUrl,
    required this.artworks,
    required this.files,
  });

  final int id;
  final int number;
  final int? absoluteNumber;
  final String? title;
  final String? overview;
  final String? airDate;
  final int? runtimeMinutes;
  final double? voteAverage;
  final int? voteCount;
  final String? stillUrl;
  final List<WorkArtwork> artworks;
  final List<LibraryFileBrief> files;

  String get heading {
    final name = title?.trim();
    if (name == null || name.isEmpty) return '第 $number 集';
    return '$number. $name';
  }

  List<({String kind, List<WorkArtwork> items})> get artworksByKind {
    final grouped = <String, List<WorkArtwork>>{};
    for (final art in artworks) {
      if (art.remoteUrl.isEmpty) continue;
      grouped.putIfAbsent(art.kind, () => []).add(art);
    }
    return [for (final entry in grouped.entries) (kind: entry.key, items: entry.value)];
  }

  factory EpisodeRow.fromJson(Map<String, dynamic> json) {
    final arts = _maps(json['artworks']).map(WorkArtwork.fromJson).where((item) => item.remoteUrl.isNotEmpty).toList();
    String? still;
    for (final art in arts) {
      if (art.kind == 'still') {
        still = art.remoteUrl;
        break;
      }
      still ??= art.remoteUrl;
    }
    return EpisodeRow(
      id: asInt(json['id']),
      number: asInt(json['episodeNumber']),
      absoluteNumber: asIntOrNull(json['absoluteNumber']),
      title: json['title']?.toString(),
      overview: json['overview']?.toString(),
      airDate: json['airDate']?.toString(),
      runtimeMinutes: asIntOrNull(json['runtimeMinutes']),
      voteAverage: asDouble(json['voteAverage']),
      voteCount: asIntOrNull(json['voteCount']),
      stillUrl: still,
      artworks: arts,
      files: _maps(json['files']).map(LibraryFileBrief.fromJson).toList(),
    );
  }
}

class EpisodeDetail {
  const EpisodeDetail({
    required this.workId,
    required this.workTitle,
    required this.seasonNumber,
    required this.seasonName,
    required this.episode,
    required this.productionCode,
    required this.credits,
    required this.externalIds,
    required this.videos,
  });

  final int workId;
  final String workTitle;
  final int seasonNumber;
  final String? seasonName;
  final EpisodeRow episode;
  final String? productionCode;
  final List<WorkCredit> credits;
  final List<WorkExternalId> externalIds;
  final List<WorkVideo> videos;

  List<WorkCredit> get cast {
    final rows = credits.where((item) => item.isCast).toList();
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  List<WorkCredit> get crew {
    final rows = credits.where((item) => !item.isCast).toList();
    rows.sort((a, b) => a.order.compareTo(b.order));
    return rows;
  }

  String get seasonHeading {
    final base = '第 $seasonNumber 季';
    final name = seasonName?.trim();
    if (name == null || name.isEmpty || name == base || RegExp(r'^season\s*\d+$', caseSensitive: false).hasMatch(name)) {
      return base;
    }
    return '$base $name';
  }

  factory EpisodeDetail.fromJson(Map<String, dynamic> json) {
    final zh = json['workTitle']?.toString().trim();
    return EpisodeDetail(
      workId: asInt(json['workId']),
      workTitle: (zh != null && zh.isNotEmpty) ? zh : (json['originalTitle']?.toString() ?? ''),
      seasonNumber: asInt(json['seasonNumber']),
      seasonName: json['seasonName']?.toString(),
      episode: EpisodeRow.fromJson(Map<String, dynamic>.from(json['episode'] as Map)),
      productionCode: json['productionCode']?.toString(),
      credits: _maps(json['credits']).map(WorkCredit.fromJson).where((item) => item.name.isNotEmpty).toList(),
      externalIds: _maps(json['externalIds']).map(WorkExternalId.fromJson).where((item) => item.externalId.isNotEmpty).toList(),
      videos: _maps(json['videos']).map(WorkVideo.fromJson).toList(),
    );
  }
}

class SeasonDetail {
  const SeasonDetail({
    required this.workTitle,
    required this.seasonNumber,
    required this.name,
    required this.overview,
    required this.posterUrl,
    required this.localEpisodeCount,
    required this.episodeCount,
    required this.airDate,
    required this.episodes,
  });

  final String workTitle;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterUrl;
  final int localEpisodeCount;
  final int? episodeCount;
  final String? airDate;
  final List<EpisodeRow> episodes;

  String get heading => SeasonCard(
        seasonNumber: seasonNumber,
        name: name,
        localEpisodeCount: localEpisodeCount,
        episodeCount: episodeCount,
        airDate: airDate,
        posterUrl: posterUrl,
      ).heading;

  factory SeasonDetail.fromJson(Map<String, dynamic> json) {
    final season = Map<String, dynamic>.from(json['season'] as Map);
    final card = SeasonCard.fromJson(season);
    final zh = json['workTitle']?.toString();
    return SeasonDetail(
      workTitle: (zh != null && zh.isNotEmpty) ? zh : (json['originalTitle']?.toString() ?? ''),
      seasonNumber: card.seasonNumber,
      name: card.name,
      overview: season['overview']?.toString(),
      posterUrl: card.posterUrl,
      localEpisodeCount: card.localEpisodeCount,
      episodeCount: card.episodeCount,
      airDate: card.airDate,
      episodes: _maps(season['episodes']).map(EpisodeRow.fromJson).toList(),
    );
  }
}
