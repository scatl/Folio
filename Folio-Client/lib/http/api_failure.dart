import 'package:dio/dio.dart';

/// API 调用失败信息（网络 / HTTP / 业务码 / 地址无效）。
class ApiFailure {
  const ApiFailure({
    required this.message,
    this.error,
    this.statusCode,
    this.isCancel = false,
  });

  final String message;
  final Object? error;
  final int? statusCode;
  final bool isCancel;

  bool get unauthorized => statusCode == 401;

  factory ApiFailure.from(Object error) {
    if (error is ApiFailure) return error;
    if (error is NoActiveServerError) {
      return ApiFailure(message: '尚未配置服务端', error: error);
    }
    if (error is InvalidServerUrlError) {
      return ApiFailure(message: error.message, error: error);
    }
    if (error is DioException) {
      return ApiFailure(
        message: _dioMessage(error),
        error: error,
        statusCode: error.response?.statusCode,
        isCancel: error.type == DioExceptionType.cancel,
      );
    }
    if (error is StateError) {
      return ApiFailure(message: error.message.toString(), error: error);
    }
    return ApiFailure(message: error.toString(), error: error);
  }

  static String _dioMessage(DioException error) {
    final body = error.response?.data;
    if (body is Map) {
      final msg = body['msg']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return '无法连接服务端';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == 401) return '未登录';
        return '请求失败 (${code ?? 0})';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.unknown:
        return error.message ?? '请求失败';
    }
  }
}

class NoActiveServerError extends StateError {
  NoActiveServerError() : super('no_active_server');
}

class InvalidServerUrlError extends StateError {
  InvalidServerUrlError(super.message);
}

/// 把 JSON object 转成实体。
T Function(dynamic data) jsonParser<T>(T Function(Map<String, dynamic> json) fromJson) {
  return (data) => fromJson(Map<String, dynamic>.from(data as Map));
}

/// 把 JSON array 转成实体列表。
List<T> Function(dynamic data) listParser<T>(T Function(Map<String, dynamic> json) fromJson) {
  return (data) {
    if (data is! List) return <T>[];
    return data.whereType<Map>().map((item) => fromJson(Map<String, dynamic>.from(item))).toList();
  };
}
