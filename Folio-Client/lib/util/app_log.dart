import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:folio/http/api_failure.dart';
import 'package:folio/util/app_log_file_result.dart';
import 'package:folio/util/app_log_file_stub.dart'
    if (dart.library.io) 'package:folio/util/app_log_file_io.dart';

export 'package:folio/util/app_log_file_result.dart';

/// 应用诊断日志：控制台 + 本地文件（Web 只打控制台）。
///
/// [tag] 用来区分模块，例如 `play`。
///
/// ```dart
/// appLog('play', 'probe start');
/// ```
///
/// 文件路径会在首次写入时打印。本地文件只保留最近 7 天。
void appLog(String tag, String message) {
  final line = '${DateTime.now().toIso8601String()} [$tag] $message';
  debugPrint('[Folio] $line');
  appendAppLogLine(line).catchError((Object e, StackTrace st) {
    debugPrint('[Folio] log write failed: $e\n$st');
  });
}

/// 是否支持读取本地 `app_debug.log`（Web 为 false）。
bool get isAppLogFileSupported => appLogFileSupported;

/// 读取本地诊断日志（旧 → 新）；Web 返回 [AppLogFileReadResult.supported] = false。
Future<AppLogFileReadResult> loadAppLogFile() => readAppLogFile();

String appLogPreview(String? text, {int max = 180}) {
  if (text == null || text.isEmpty) return '<empty>';
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.length <= max) return oneLine;
  return '${oneLine.substring(0, max)}…(len=${oneLine.length})';
}

String appLogApiFailure(ApiFailure e) {
  final buf = StringBuffer('status=${e.statusCode} message=${e.message}');
  final err = e.error;
  if (err is DioException) {
    buf.write(' dioType=${err.type} path=${err.requestOptions.path}');
    final data = err.response?.data;
    if (data != null) {
      buf.write(' body=${appLogPreview('$data', max: 800)}');
    }
  } else if (err is Response) {
    buf.write(' path=${err.requestOptions.path}');
    if (err.data != null) {
      buf.write(' body=${appLogPreview('${err.data}', max: 800)}');
    }
  }
  return buf.toString();
}
