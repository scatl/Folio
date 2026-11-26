abstract final class RouterPath {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/';
  static const settings = '/settings';
  static const logs = '/logs';
  static const tasks = '/tasks';
  static const createLibrary = '/libraries/create';

  static String library(int id) => '/libraries/$id';

  static String work(int id) => '/works/$id';

  static String playlist(int id) => '/playlists/$id';

  static String workExternal({
    required String provider,
    required String externalId,
    required String kind,
  }) {
    final query = Uri(
      queryParameters: {
        'provider': provider,
        'externalId': externalId,
        'kind': kind,
      },
    ).query;
    return '/works/detail?$query';
  }

  static String season(int id, int seasonNumber) => '/works/$id/seasons/$seasonNumber';

  static String episode(int id, int seasonNumber, int episodeNumber) =>
      '/works/$id/seasons/$seasonNumber/episodes/$episodeNumber';

  static String collection(String id) => '/collections/${Uri.encodeComponent(id)}';

  static String person(String provider, String externalId) =>
      '/people/${Uri.encodeComponent(provider)}/${Uri.encodeComponent(externalId)}';

  static String manualMatch(int fileId) => '/library/files/$fileId/match';
}
