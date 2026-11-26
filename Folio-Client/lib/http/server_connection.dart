import 'package:folio/http/api_failure.dart';

/// 一次请求用的服务端地址。
class ServerConnection {
  const ServerConnection({
    required this.host,
    required this.useHttps,
    this.port,
    this.path = '',
  });

  factory ServerConnection.parse(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw InvalidServerUrlError('请填写服务端地址');
    }
    if (!text.contains('://')) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw InvalidServerUrlError('服务端地址无效');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw InvalidServerUrlError('仅支持 http 或 https');
    }
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') path = '';
    return ServerConnection(
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      useHttps: uri.scheme == 'https',
      path: path,
    );
  }

  final String host;
  final int? port;
  final bool useHttps;
  final String path;

  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    final authority = port == null ? host : '$host:$port';
    final prefix = path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (prefix.isEmpty) return '$scheme://$authority';
    return '$scheme://$authority/$prefix';
  }
}
