import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';

class VideoInfoSheet extends ConsumerStatefulWidget {
  const VideoInfoSheet({super.key, required this.files});

  final List<LibraryFileBrief> files;

  @override
  ConsumerState<VideoInfoSheet> createState() => _VideoInfoSheetState();
}

class _VideoInfoSheetState extends ConsumerState<VideoInfoSheet> {
  late List<LibraryFileBrief> _files;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _files = widget.files;
  }

  Future<void> _refresh() async {
    if (_refreshing || _files.isEmpty) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final next = <LibraryFileBrief>[];
      for (final file in _files) {
        next.add(
          await ref.read(apiClientProvider).post(
                ApiPath.libraryFiles.probe(file.id),
                parser: jsonParser(LibraryFileBrief.fromJson),
              ),
        );
      }
      if (mounted) setState(() => _files = next);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Text('视频信息', style: folioDisplay(size: 18)),
              const Spacer(),
              if (ref.watch(sessionProvider.select((session) => session.isAdmin || session.hasWriteLibrary)))
                TextButton(
                  onPressed: _refreshing || _files.isEmpty ? null : _refresh,
                  child: Text(_refreshing ? '刷新中…' : '刷新视频元数据'),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: FolioColors.danger)),
            ),
          if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('没有关联的视频文件', style: TextStyle(color: FolioColors.inkMuted)),
            )
          else
            for (var i = 0; i < _files.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              _FileBlock(file: _files[i]),
            ],
        ],
      ),
    );
  }
}

class _FileBlock extends StatelessWidget {
  const _FileBlock({required this.file});

  final LibraryFileBrief file;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('路径', file.locator),
      if (_size(file.fileSize) != null) ('大小', _size(file.fileSize)!),
      if (file.container != null && file.container!.isNotEmpty) ('容器', file.container!),
      if (_duration(file.durationMs) != null) ('时长', _duration(file.durationMs)!),
      if (_time(file.sourceModifiedAt) != null) ('修改时间', _time(file.sourceModifiedAt)!),
      if (_videoLine(file) != null) ('视频', _videoLine(file)!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) _Fact(label: row.$1, value: row.$2),
        for (var i = 0; i < file.audioTracks.length; i++) _Fact(label: i == 0 ? '音频' : '', value: _audioLine(file.audioTracks[i], i)),
        for (var i = 0; i < file.subtitleTracks.length; i++) _Fact(label: i == 0 ? '字幕' : '', value: _subtitleLine(file.subtitleTracks[i], i)),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(color: FolioColors.inkFaint, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: FolioColors.inkMuted, fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}

String? _size(int? bytes) {
  if (bytes == null || bytes < 0) return null;
  if (bytes >= 1000000000) return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String? _duration(int? ms) {
  if (ms == null || ms <= 0) return null;
  final total = (ms / 1000).round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '$minutes:${two(seconds)}';
}

String? _bitrate(int? bps) {
  if (bps == null || bps <= 0) return null;
  if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} Mbps';
  return '${(bps / 1000).round()} kbps';
}

String _codec(String? codec) {
  if (codec == null || codec.isEmpty) return '';
  switch (codec.toLowerCase()) {
    case 'hevc':
      return 'HEVC';
    case 'h264':
      return 'H.264';
    case 'av1':
      return 'AV1';
    case 'mpeg2video':
      return 'MPEG-2';
    case 'mpeg4':
      return 'MPEG-4';
    case 'vp9':
      return 'VP9';
    case 'aac':
      return 'AAC';
    case 'ac3':
      return 'Dolby Digital';
    case 'eac3':
      return 'Dolby Digital Plus';
    case 'truehd':
      return 'TrueHD';
    case 'dts':
    case 'dca':
      return 'DTS';
    case 'flac':
      return 'FLAC';
    case 'mp3':
      return 'MP3';
    case 'opus':
      return 'Opus';
    case 'subrip':
      return 'SRT';
    case 'ass':
      return 'ASS';
    case 'hdmv_pgs_subtitle':
      return 'PGS';
    case 'dvd_subtitle':
      return 'VOBSUB';
    default:
      return codec.toUpperCase();
  }
}

String? _sampleRate(int? hz) {
  if (hz == null || hz <= 0) return null;
  if (hz % 1000 == 0) return '${hz ~/ 1000} kHz';
  return '$hz Hz';
}

String? _channelLayout(String? raw, int? channels) {
  if (raw != null && raw.isNotEmpty) {
    switch (raw.toLowerCase()) {
      case 'mono':
        return '单声道';
      case 'stereo':
        return '立体声';
      default:
        return raw;
    }
  }
  if (channels != null) return '$channels 声道';
  return null;
}

String? _videoLine(LibraryFileBrief file) {
  final rate = file.videoFrameRate;
  final parts = [
    if (_codec(file.videoCodec).isNotEmpty) _codec(file.videoCodec),
    if (file.videoProfile != null && file.videoProfile!.isNotEmpty) file.videoProfile!,
    if (file.videoWidth != null && file.videoHeight != null) '${file.videoWidth}×${file.videoHeight}',
    if (file.videoPixelFormat != null && file.videoPixelFormat!.isNotEmpty) file.videoPixelFormat!,
    if (rate != null) '${rate.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} fps',
    if (_bitrate(file.videoBitrate) != null) _bitrate(file.videoBitrate)!,
    if (file.videoBitDepth != null) '${file.videoBitDepth} bit',
    if (file.videoDynamicRange != null && file.videoDynamicRange!.isNotEmpty) file.videoDynamicRange!,
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String _audioLine(MediaTrack track, int index) {
  final layout = _channelLayout(track.channelLayout, track.channels);
  return [
    '音轨 ${index + 1}',
    if (_codec(track.codec).isNotEmpty) _codec(track.codec),
    if (track.profile != null && track.profile!.isNotEmpty) track.profile!,
    if (layout != null) layout,
    if (_sampleRate(track.sampleRate) != null) _sampleRate(track.sampleRate)!,
    if (track.language != null && track.language!.isNotEmpty) track.language!,
    if (_bitrate(track.bitrate) != null) _bitrate(track.bitrate)!,
  ].join(' · ');
}

String _subtitleLine(MediaTrack track, int index) {
  return [
    '字幕 ${index + 1}',
    if (_codec(track.codec).isNotEmpty) _codec(track.codec),
    if (track.language != null && track.language!.isNotEmpty) track.language!,
  ].join(' · ');
}

String? _time(String? value) {
  if (value == null || value.isEmpty) return null;
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
}
