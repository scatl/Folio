abstract final class ApiPath {
  static const auth = _Auth();
  static const libraries = _Libraries();
  static const works = _Works();
  static const scrapeJobs = _ScrapeJobs();
  static const libraryFiles = _LibraryFiles();
  static const playback = _Playback();
  static const watchlist = _Watchlist();
  static const playlists = _Playlists();
  static const settings = '/api/settings';
  static const home = '/api/home';
  static const events = '/api/events';
  static const users = _Users();
  static const server = _Server();
  static const logs = _Logs();
  static const collections = _Collections();
  static const people = _People();
}

class _Auth {
  const _Auth();
  static const _base = '/api/auth';

  final login = '$_base/login';
  final logout = '$_base/logout';
  final me = '$_base/me';
  final posters = '$_base/posters';
  final account = '$_base/account';
}

class _Libraries {
  const _Libraries();
  static const _base = '/api/libraries';

  final list = _base;
  final browse = '$_base/browse';

  String one(int id) => '$_base/$id';

  String scan(int id) => '$_base/$id/scan';

  String collections(int id) => '$_base/$id/collections';

  String collectionWorks(int id) => '$_base/$id/collections/works';
}

class _Works {
  const _Works();
  static const _base = '/api/works';

  final list = _base;

  final facets = '$_base/facets';

  final detail = '$_base/detail';

  String card(int id) => '$_base/$id/card';

  String one(int id) => '$_base/$id';

  String refresh(int id) => '$_base/$id/refresh';

  String collection(int id) => '$_base/$id/collection';

  String season(int id, int seasonNumber) => '$_base/$id/seasons/$seasonNumber';

  String episode(int id, int seasonNumber, int episodeNumber) =>
      '$_base/$id/seasons/$seasonNumber/episodes/$episodeNumber';
}

class _ScrapeJobs {
  const _ScrapeJobs();
  static const _base = '/api/scrape-jobs';

  final list = _base;
  final stats = '$_base/stats';

  String job(int id) => '$_base/$id';

  String retry(int id) => '$_base/$id/retry';
}

class _Users {
  const _Users();
  static const _base = '/api/users';

  final list = _base;

  String one(int id) => '$_base/$id';
}

class _Server {
  const _Server();
  static const _base = '/api/server';

  final identity = '$_base/identity';
  final connections = '$_base/connections';
  final remote = '$_base/remote';
}

class _Logs {
  const _Logs();
  static const _base = '/api/logs/server';

  final list = _base;
  final content = '$_base/content';
}

class _Collections {
  const _Collections();
  static const _base = '/api/collections';

  String one(String id) => '$_base/${Uri.encodeComponent(id)}';
}

class _People {
  const _People();
  static const _base = '/api/people';

  String one(String provider, String externalId) =>
      '$_base/${Uri.encodeComponent(provider)}/${Uri.encodeComponent(externalId)}';

  String refresh(String provider, String externalId) => '${one(provider, externalId)}/refresh';
}

class _LibraryFiles {
  const _LibraryFiles();
  static const _base = '/api/library/files';

  final list = _base;

  String one(int id) => '$_base/$id';

  String content(int id) => '$_base/$id/content';

  String probe(int id) => '$_base/$id/probe';

  String subtitles(int id) => '$_base/$id/subtitles';

  String segments(int id) => '$_base/$id/segments';

  String subtitleContent(int id) => '$_base/$id/subtitles/content';

  String candidates(int id) => '$_base/$id/candidates';

  String match(int id) => '$_base/$id/match';
}

class _Playback {
  const _Playback();
  static const _base = '/api/playback';

  final progress = '$_base/progress';
  final continueWatching = '$_base/continue';

  String workProgress(int workId) => '$_base/progress/work/$workId';

  String workWatch(int workId) => '$_base/works/$workId';
}

class _Watchlist {
  const _Watchlist();
  static const _base = '/api/watchlist';

  final list = _base;

  String work(int workId) => '$_base/works/$workId';
}

class _Playlists {
  const _Playlists();
  static const _base = '/api/playlists';

  final list = _base;

  String one(int id) => '$_base/$id';

  String queue(int id) => '$_base/$id/queue';

  String items(int id) => '$_base/$id/items';

  String order(int id) => '$_base/$id/items/order';

  String item(int id, int workId) => '$_base/$id/items/$workId';
}
