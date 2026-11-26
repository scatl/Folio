import 'package:dio/dio.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/util/app_log.dart';

/// 选址 + Cookie，供播放页准备阶段调用。
Future<({String url, Map<String, String> headers})> resolvePlaybackMedia(
  ApiClient api,
  int fileId,
) async {
  final base = await resolvePlaybackBase(api);
  final cookie = await _sessionCookie(api);
  return (
    url: ApiClient.resolveUrl(
      ServerConnection.parse(base),
      ApiPath.libraryFiles.content(fileId),
    ),
    headers: {
      if (cookie.isNotEmpty) 'Cookie': cookie,
    },
  );
}

Future<String> resolvePlaybackBase(ApiClient api) async {
  final current = api.baseUrl;
  if (current == null || current.isEmpty) {
    throw const ApiFailure(message: '还没有服务端地址');
  }
  ServerConnections connections;
  try {
    connections = await api.get(ApiPath.server.connections, parser: jsonParser(ServerConnections.fromJson));
  } catch (error) {
    final detail = error is ApiFailure ? appLogApiFailure(error) : '$error';
    appLog('play', 'connections fail, use current=$current $detail');
    return current;
  }
  final locals = connections.local.map((item) => item.url.trim()).where((url) => url.isNotEmpty).toList();
  appLog(
    'play',
    'probe start current=$current serverId=${connections.serverId} remote=${connections.remoteUrl ?? ''} locals=${locals.join(' ')}',
  );
  final matched = await _firstIdentity(locals, connections.serverId);
  final chosen = matched ?? current;
  appLog('play', 'probe chosen base=$chosen via=${matched == null ? 'current' : 'local'}');
  return chosen;
}

Future<String?> _firstIdentity(List<String> urls, String serverId) async {
  if (urls.isEmpty || serverId.isEmpty) return null;
  final pending = <Future<String?>>[];
  for (final url in urls) {
    pending.add(_probe(url, serverId));
  }
  final results = await Future.wait(pending);
  for (final url in results) {
    if (url != null) return url;
  }
  return null;
}

Future<String?> _probe(String base, String serverId) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 800),
      receiveTimeout: const Duration(milliseconds: 800),
      responseType: ResponseType.json,
    ),
  );
  try {
    final response = await dio.get<dynamic>(ApiClient.resolveUrl(ServerConnection.parse(base), ApiPath.server.identity));
    final body = response.data;
    if (body is! Map) {
      appLog('play', 'probe $base invalid body');
      return null;
    }
    final data = body['data'];
    final got = data is Map ? data['serverId']?.toString() : null;
    if (got == serverId) {
      appLog('play', 'probe $base match');
      return base;
    }
    appLog('play', 'probe $base mismatch got=${got ?? ''}');
    return null;
  } catch (error) {
    appLog('play', 'probe $base fail $error');
    return null;
  } finally {
    dio.close(force: true);
  }
}

Future<String> _sessionCookie(ApiClient api) async {
  final base = api.baseUrl;
  if (base == null || base.isEmpty) return '';
  final cookies = await api.jar.loadForRequest(Uri.parse(base));
  return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
}
