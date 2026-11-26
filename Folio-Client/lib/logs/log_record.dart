enum LogLevel { all, debug, info, warn, error }

final _recordStart = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}');

/// Spring Boot 文件日志：`时间 级别 进程 --- [应用名] [线程] logger : 正文`
/// 应用名和线程各自带方括号，中间有空格。
final _serverLine = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+'
  r'(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)'
  r'(?:\s+(\d+))?'
  r'(?:\s+---)?'
  r'((?:\s+\[[^\]]*\])*)'
  r'\s+(\S+)'
  r'\s+:\s?(.*)$',
);

final _levelHead = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+'
  r'(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\b\s*(.*)$',
);

final _bracket = RegExp(r'\[([^\]]*)\]');

/// 客户端诊断日志：`时间 [tag] 正文`
final _clientLine = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s+'
  r'\[([^\]]+)\]\s?(.*)$',
);

final _timestampLine = RegExp(
  r'^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\s*(.*)$',
);

/// 一条日志记录。以时间戳开头的行是新记录，后面的行算作堆栈或续行。
class LogEntry {
  LogEntry({
    required this.level,
    required this.lines,
    this.date,
    this.time,
    this.source = '',
    this.detail,
    this.message = '',
  });

  final LogLevel level;
  final List<String> lines;
  final String? date;
  final String? time;
  final String source;
  final String? detail;
  final String message;
  final List<String> extra = [];
}

/// 把日志原文拆成记录。筛级别时堆栈跟所属记录走。
List<LogEntry> parseLog(String text) {
  if (text.isEmpty) return const [];
  final records = <LogEntry>[];
  LogEntry? current;
  for (final raw in text.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (current == null || _recordStart.hasMatch(line)) {
      _trimExtra(current);
      current = _entry(line);
      records.add(current);
    } else {
      current.lines.add(line);
      current.extra.add(line);
    }
  }
  _trimExtra(current);
  return records;
}

List<LogEntry> filterRecords(String text, LogLevel level) {
  final records = parseLog(text);
  if (level == LogLevel.all) return records;
  return records.where((record) => record.level == level).toList();
}

void _trimExtra(LogEntry? entry) {
  if (entry == null) return;
  while (entry.extra.isNotEmpty && entry.extra.last.trim().isEmpty) {
    entry.extra.removeLast();
    if (entry.lines.isNotEmpty && entry.lines.last.trim().isEmpty) {
      entry.lines.removeLast();
    }
  }
}

LogEntry _entry(String line) {
  final server = _serverLine.firstMatch(line);
  if (server != null) {
    final brackets = _brackets(server.group(5));
    final thread = brackets.isEmpty ? null : brackets.last;
    final context = brackets.length <= 1 ? const <String>[] : brackets.sublist(0, brackets.length - 1);
    return LogEntry(
      level: logLevelOf(server.group(3)),
      lines: [line],
      date: server.group(1),
      time: server.group(2),
      detail: _detail(pid: server.group(4), context: context, thread: thread),
      message: server.group(7) ?? '',
    );
  }
  final leveled = _levelHead.firstMatch(line);
  if (leveled != null) {
    final rest = (leveled.group(4) ?? '').trim();
    return LogEntry(
      level: logLevelOf(leveled.group(3)),
      lines: [line],
      date: leveled.group(1),
      time: leveled.group(2),
      message: rest,
    );
  }
  final client = _clientLine.firstMatch(line);
  if (client != null) {
    return LogEntry(
      level: LogLevel.info,
      lines: [line],
      date: client.group(1),
      time: client.group(2),
      source: client.group(3) ?? '',
      message: client.group(4) ?? '',
    );
  }
  final plain = _timestampLine.firstMatch(line);
  if (plain != null) {
    return LogEntry(
      level: LogLevel.info,
      lines: [line],
      date: plain.group(1),
      time: plain.group(2),
      message: plain.group(3) ?? '',
    );
  }
  return LogEntry(level: LogLevel.info, lines: [line], message: line);
}

LogLevel logLevelOf(String? token) {
  return switch (token) {
    'TRACE' || 'DEBUG' => LogLevel.debug,
    'WARN' || 'WARNING' => LogLevel.warn,
    'ERROR' || 'FATAL' => LogLevel.error,
    _ => LogLevel.info,
  };
}

String logLevelName(LogLevel level) {
  return switch (level) {
    LogLevel.debug => '调试',
    LogLevel.info => '信息',
    LogLevel.warn => '警告',
    LogLevel.error => '错误',
    LogLevel.all => '全部',
  };
}

List<String> _brackets(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return _bracket.allMatches(raw).map((match) => match.group(1)!).where((name) => name.isNotEmpty).toList();
}

String? _detail({String? pid, List<String> context = const [], String? thread}) {
  final parts = <String>[
    if (pid != null && pid.isNotEmpty) '进程 $pid',
    ...context,
    if (thread != null && thread.isNotEmpty) '线程 $thread',
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// 本地 `app_debug.log` 里的一天。今天排在最前，其余日期从新到旧。
class LocalLogDay {
  const LocalLogDay({required this.date, required this.label, required this.lines, required this.size});

  final String date;
  final String label;
  final List<String> lines;
  final int size;
}

List<LocalLogDay> localLogDays(List<String> lines, {DateTime? now}) {
  if (lines.isEmpty) return const [];
  final today = _dayKey(now ?? DateTime.now());
  final groups = <String, List<String>>{};
  String? current;
  for (final line in lines) {
    if (_recordStart.hasMatch(line)) current = line.substring(0, 10);
    final key = current ?? '';
    (groups[key] ??= []).add(line);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      if (a == today) return -1;
      if (b == today) return 1;
      return b.compareTo(a);
    });
  return [
    for (final key in keys)
      LocalLogDay(
        date: key,
        label: key.isEmpty ? '未标日期' : (key == today ? '今天' : key),
        lines: groups[key]!,
        size: groups[key]!.fold(0, (sum, line) => sum + line.length + 1),
      ),
  ];
}

String _dayKey(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
