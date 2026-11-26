import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:folio/logs/log_record.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';

/// 把日志原文排成记录。点一条打开详情。
class LogRecordView extends StatefulWidget {
  const LogRecordView({
    super.key,
    required this.controller,
    required this.text,
    required this.level,
  });

  final ScrollController controller;
  final String text;
  final LogLevel level;

  @override
  State<LogRecordView> createState() => _LogRecordViewState();
}

class _LogRecordViewState extends State<LogRecordView> {
  @override
  void initState() {
    super.initState();
    _jumpToLatest();
  }

  @override
  void didUpdateWidget(LogRecordView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.level != widget.level) {
      _jumpToLatest();
    }
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.hasClients) return;
      if (widget.controller.offset != 0) widget.controller.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final records = filterRecords(widget.text, widget.level);
    if (widget.text.isNotEmpty && records.isEmpty) {
      return const EmptyHint(title: '没有这个级别的日志', body: '换一个级别，或查看全部。');
    }
    if (records.isEmpty) {
      return const Center(
        child: Text('这个文件是空的', style: TextStyle(color: FolioColors.inkFaint, fontSize: 14)),
      );
    }
    final rows = _rows(records);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FolioColors.line)),
      ),
      child: Scrollbar(
        controller: widget.controller,
        child: ListView.builder(
          controller: widget.controller,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[rows.length - 1 - index];
            if (row is String) return _dayHeader(row);
            return _LogRecordTile(entry: row as LogEntry);
          },
        ),
      ),
    );
  }
}

List<Object> _rows(List<LogEntry> records) {
  final rows = <Object>[];
  String? date;
  for (final record in records) {
    final day = record.date;
    if (day != null && day != date) {
      date = day;
      rows.add(day);
    }
    rows.add(record);
  }
  return rows;
}

Widget _dayHeader(String date) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(
      date,
      style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
    ),
  );
}

class _LogRecordTile extends StatelessWidget {
  const _LogRecordTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(entry.level);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLogDetail(context, entry),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (entry.time != null) ...[
                    Text(
                      entry.time!,
                      style: TextStyle(
                        color: FolioColors.inkMuted,
                        fontSize: 12,
                        height: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontFamily: _monoFamily(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _levelPill(entry.level, color),
                  if (entry.source.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        entry.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ),
                  ],
                ],
              ),
              if (entry.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entry.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: FolioColors.ink, fontSize: 13, height: 1.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showLogDetail(BuildContext context, LogEntry entry) {
  final color = _levelColor(entry.level);
  showFolioSheet<void>(
    context: context,
    builder: (context) {
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      final when = [
        if (entry.date != null) entry.date!,
        if (entry.time != null) entry.time!,
      ].join(' ');
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + inset),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    children: [
                      _levelPill(entry.level, color),
                      if (entry.source.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            entry.source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: FolioColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (when.isNotEmpty)
                        Text(
                          when,
                          style: TextStyle(
                            color: FolioColors.inkMuted,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontFamily: _monoFamily(),
                          ),
                        ),
                    ],
                  ),
                  if (entry.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        entry.detail!,
                        style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.4),
                      ),
                    ),
                  if (entry.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        entry.message,
                        style: const TextStyle(color: FolioColors.ink, fontSize: 14, height: 1.5),
                      ),
                    ),
                  if (entry.extra.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SelectableText(
                        entry.extra.join('\n'),
                        style: TextStyle(
                          color: FolioColors.inkMuted,
                          fontSize: 12,
                          height: 1.45,
                          fontFamily: _monoFamily(),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _levelPill(LogLevel level, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      logLevelName(level),
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, height: 1.2),
    ),
  );
}

Color _levelColor(LogLevel level) {
  return switch (level) {
    LogLevel.debug => FolioColors.inkMuted,
    LogLevel.warn => FolioColors.copper,
    LogLevel.error => FolioColors.danger,
    _ => FolioColors.teal,
  };
}

String _monoFamily() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
    TargetPlatform.windows => 'Consolas',
    _ => 'monospace',
  };
}
