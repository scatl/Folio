import 'package:folio/logs/log_record.dart';

export 'package:folio/logs/log_record.dart' show LogLevel;

const logLevelLabels = ['全部', '调试', '信息', '警告', '错误'];

class FilteredLog {
  const FilteredLog({required this.text, required this.count});

  final String text;
  final int count;
}

/// 按级别筛日志。以时间戳开头的行是一条新记录，后面的堆栈行跟着这条记录的级别。
/// 没有级别标记的记录（客户端诊断日志）算作信息。
FilteredLog filterLog(String text, LogLevel level) {
  final records = filterRecords(text, level);
  return FilteredLog(
    text: records.map((record) => record.lines.join('\n')).join('\n'),
    count: records.length,
  );
}
