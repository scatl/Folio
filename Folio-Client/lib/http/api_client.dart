import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/http/api_failure.dart';
import 'package:folio/http/server_connection.dart';

export 'package:folio/http/api_failure.dart';
export 'package:folio/http/server_connection.dart';

/// Folio HTTP 客户端。
///
/// - 默认 [get]/[post]/[put]/[delete] 使用 [use] 绑定的服务端
/// - [getWithConfig] / [postWithConfig] 使用调用方传入的地址（登录前探测）
/// - 成功时剥掉 `{code,data,msg}`，parser 收到的是 `data`
/// - 失败抛出 [ApiFailure]
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

class ApiClient {
  ApiClient() {
    dio.interceptors.add(CookieManager(_cookieJar));
  }

  final Dio dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      headers: const {Headers.acceptHeader: 'application/json'},
    ),
  );

  CookieJar _cookieJar = CookieJar();
  ServerConnection? _connection;

  CookieJar get jar => _cookieJar;

  String? get baseUrl => _connection?.baseUrl;

  void close() {
    dio.close(force: true);
  }

  Future<void> usePersistentCookies(String directory) async {
    final persistent = PersistCookieJar(storage: FileStorage(directory));
    dio.interceptors.removeWhere((item) => item is CookieManager);
    _cookieJar = persistent;
    dio.interceptors.add(CookieManager(persistent));
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();

  /// 之后的 [get]/[post]/[put]/[delete] 都发到这个服务端。
  void use(ServerConnection connection) {
    _connection = connection;
  }

  static String resolveUrl(ServerConnection connection, String apiPath) {
    final base = connection.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final suffix = apiPath.startsWith('/') ? apiPath : '/$apiPath';
    return '$base$suffix';
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () {
        final connection = _requireConnection();
        return dio.get<dynamic>(
          resolveUrl(connection, path),
          queryParameters: queryParameters,
          options: options,
          cancelToken: cancelToken,
        );
      },
      parser,
    );
  }

  Future<T> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () {
        final connection = _requireConnection();
        return dio.post<dynamic>(
          resolveUrl(connection, path),
          data: data,
          queryParameters: queryParameters,
          options: _json(options, data),
          cancelToken: cancelToken,
        );
      },
      parser,
    );
  }

  Future<T> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () {
        final connection = _requireConnection();
        return dio.put<dynamic>(
          resolveUrl(connection, path),
          data: data,
          queryParameters: queryParameters,
          options: _json(options, data),
          cancelToken: cancelToken,
        );
      },
      parser,
    );
  }

  Future<T> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () {
        final connection = _requireConnection();
        return dio.patch<dynamic>(
          resolveUrl(connection, path),
          data: data,
          queryParameters: queryParameters,
          options: _json(options, data),
          cancelToken: cancelToken,
        );
      },
      parser,
    );
  }

  Future<T> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () {
        final connection = _requireConnection();
        return dio.delete<dynamic>(
          resolveUrl(connection, path),
          data: data,
          queryParameters: queryParameters,
          options: _json(options, data),
          cancelToken: cancelToken,
        );
      },
      parser,
    );
  }

  Future<T> getWithConfig<T>({
    required ServerConnection config,
    required String apiPath,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () => dio.get<dynamic>(
        resolveUrl(config, apiPath),
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      ),
      parser,
    );
  }

  Future<T> postWithConfig<T>({
    required ServerConnection config,
    required String apiPath,
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    T Function(dynamic data)? parser,
  }) {
    return _request(
      () => dio.post<dynamic>(
        resolveUrl(config, apiPath),
        data: data,
        queryParameters: queryParameters,
        options: _json(options, data),
        cancelToken: cancelToken,
      ),
      parser,
    );
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data)? parser,
  ) async {
    final T data;
    try {
      final response = await _send(request);
      data = _decode(response.data, parser);
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw ApiFailure.from(error);
    }
    return data;
  }

  T _decode<T>(dynamic raw, T Function(dynamic data)? parser) {
    final parse = parser;
    if (parse == null) return raw as T;
    if (raw == null) throw const ApiFailure(message: '响应数据为空');
    return parse(raw);
  }

  ServerConnection _requireConnection() {
    final connection = _connection;
    if (connection == null) throw NoActiveServerError();
    return connection;
  }

  Options _json(Options? options, Object? data) {
    if (data == null) return options ?? Options();
    return (options ?? Options()).copyWith(contentType: Headers.jsonContentType);
  }

  Future<Response<dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    final response = await request();
    final body = response.data;
    if (body is! Map) return response;
    final map = Map<String, dynamic>.from(body);
    final code = map['code'];
    if (code is! num) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: '响应格式无效',
      );
    }
    if (code != 0) {
      final status = response.statusCode != null && response.statusCode! >= 400 ? response.statusCode! : code.toInt();
      throw DioException(
        requestOptions: response.requestOptions,
        response: Response<dynamic>(
          requestOptions: response.requestOptions,
          statusCode: status == 0 ? 400 : status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
        message: map['msg']?.toString(),
      );
    }
    if (map['data'] == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: map['msg']?.toString().isNotEmpty == true ? map['msg'].toString() : '响应数据为空',
      );
    }
    return Response<dynamic>(
      requestOptions: response.requestOptions,
      statusCode: response.statusCode,
      data: map['data'],
    );
  }
}
