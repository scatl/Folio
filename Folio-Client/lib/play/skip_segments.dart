class MediaSegmentSpan {
  const MediaSegmentSpan({
    required this.kind,
    required this.startMs,
    this.endMs,
  });

  final String kind;
  final int startMs;
  final int? endMs;

  factory MediaSegmentSpan.fromJson(Map<String, dynamic> json) {
    return MediaSegmentSpan(
      kind: json['kind']?.toString() ?? '',
      startMs: _asInt(json['startMs']),
      endMs: _asIntOrNull(json['endMs']),
    );
  }
}

class MediaSegmentsPayload {
  const MediaSegmentsPayload({required this.segments});

  final List<MediaSegmentSpan> segments;

  factory MediaSegmentsPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['segments'];
    return MediaSegmentsPayload(
      segments: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => MediaSegmentSpan.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}

class SkipAction {
  const SkipAction({
    required this.key,
    required this.label,
    required this.targetMs,
    required this.advance,
  });

  final String key;
  final String label;
  final int targetMs;
  final bool advance;
}

enum SkipMode { off, button, auto }

const skipModeStorageKey = 'folio.player.skipSegments';

SkipMode skipModeFromStored(String? raw) {
  return switch (raw) {
    'off' => SkipMode.off,
    'auto' => SkipMode.auto,
    _ => SkipMode.button,
  };
}

String skipModeStored(SkipMode mode) {
  return switch (mode) {
    SkipMode.off => 'off',
    SkipMode.button => 'button',
    SkipMode.auto => 'auto',
  };
}

String skipModeLabel(SkipMode mode) {
  return switch (mode) {
    SkipMode.off => '关闭',
    SkipMode.button => '显示按钮',
    SkipMode.auto => '自动跳过',
  };
}

const _minMs = 5000;
const _gapMs = 2000;

class _Range {
  _Range(this.start, this.end);
  int start;
  int end;
}

int? _resolveEnd(int? endMs, int durationMs) {
  if (endMs != null) return endMs;
  if (durationMs > 0) return durationMs;
  return null;
}

List<_Range> _mergeRanges(List<MediaSegmentSpan> segments, Set<String> kinds, int durationMs) {
  final rows = <_Range>[];
  for (final item in segments) {
    if (!kinds.contains(item.kind)) continue;
    final end = _resolveEnd(item.endMs, durationMs);
    if (end == null || end - item.startMs < _minMs) continue;
    rows.add(_Range(item.startMs < 0 ? 0 : item.startMs, end));
  }
  rows.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Range>[];
  for (final row in rows) {
    if (merged.isNotEmpty && row.start <= merged.last.end + _gapMs) {
      if (row.end > merged.last.end) merged.last.end = row.end;
    } else {
      merged.add(_Range(row.start, row.end));
    }
  }
  return merged;
}

int? _postCreditStart(List<MediaSegmentSpan> segments) {
  int? start;
  for (final item in segments) {
    final end = item.endMs;
    if (item.kind != 'post_credits' || end == null || end - item.startMs < _minMs) continue;
    if (start == null || item.startMs < start) start = item.startMs;
  }
  return start;
}

bool _insidePostCredits(int positionMs, List<MediaSegmentSpan> segments) {
  for (final item in segments) {
    final end = item.endMs;
    if (item.kind != 'post_credits' || end == null) continue;
    if (positionMs >= item.startMs && positionMs < end) return true;
  }
  return false;
}

SkipAction? skipActionFor({
  required int positionMs,
  required int durationMs,
  required List<MediaSegmentSpan> segments,
  required bool series,
  required Set<String> dismissed,
}) {
  if (segments.isEmpty || positionMs < 0 || _insidePostCredits(positionMs, segments)) return null;
  final post = _postCreditStart(segments);
  final groups = [
    (label: '跳过片头', ranges: _mergeRanges(segments, {'intro', 'recap'}, durationMs), credits: false),
    (label: '跳过片尾', ranges: _mergeRanges(segments, {'credits', 'preview'}, durationMs), credits: true),
  ];
  for (final group in groups) {
    for (final range in group.ranges) {
      if (positionMs < range.start || positionMs >= range.end - 400) continue;
      final key = '${group.label}:${range.start}';
      if (dismissed.contains(key)) continue;
      var targetMs = range.end;
      if (group.credits && post != null && post > range.start + 1000 && post < range.end + 1500) {
        targetMs = post;
      }
      final atEnd = durationMs > 0 && targetMs >= durationMs - 3000;
      return SkipAction(
        key: key,
        label: group.label,
        targetMs: targetMs,
        advance: group.credits && series && atEnd && targetMs == range.end,
      );
    }
  }
  return null;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

int? _asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
