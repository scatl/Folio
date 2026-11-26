part of '../player_page.dart';

extension _PlayerInfoSheet on _PlayerPageState {
  Future<String?> _playerProperty(String name) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return null;
    try {
      final value = (await platform.getProperty(name)).trim();
      if (!_usefulInfo(value)) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  bool _usefulInfo(String value) {
    final text = value.trim().toLowerCase();
    return text.isNotEmpty &&
        text != 'auto' &&
        text != 'unknown' &&
        text != 'none' &&
        text != 'nil' &&
        text != 'n/a' &&
        text != 'nan' &&
        text != 'undefined';
  }

  Future<Map<String, String>> _playerProperties(List<String> names) async {
    final values = await Future.wait(names.map(_playerProperty));
    return {
      for (var i = 0; i < names.length; i++)
        if (values[i] != null) names[i]: values[i]!,
    };
  }

  String _info(Map<String, String> props, String name) => props[name] ?? '';

  String _bitrateText(num? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) return '';
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    if (bitsPerSecond >= 1000) {
      return '${(bitsPerSecond / 1000).toStringAsFixed(0)} kbps';
    }
    return '${bitsPerSecond.round()} bps';
  }

  String _bitrateProp(String? raw) {
    return _bitrateText(double.tryParse(raw ?? ''));
  }

  String _fpsText(double? fps) {
    if (fps == null || fps <= 0) return '';
    if (fps == fps.roundToDouble()) return '${fps.round()} fps';
    return '${fps.toStringAsFixed(3)} fps';
  }

  String _fpsProp(String? raw) => _fpsText(double.tryParse(raw ?? ''));

  String _sizeText(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) return '';
    return '$width×$height';
  }

  String _aspectText(String? raw) {
    final aspect = double.tryParse(raw ?? '');
    if (aspect == null || aspect <= 0) return '';
    const named = <(double, String)>[
      (1.778, '16:9'),
      (1.333, '4:3'),
      (2.333, '21:9'),
      (2.39, '2.39:1'),
      (2.35, '2.35:1'),
      (1.85, '1.85:1'),
    ];
    for (final entry in named) {
      if ((aspect - entry.$1).abs() < 0.03) return '${entry.$2} ($aspect)';
    }
    return aspect.toStringAsFixed(3);
  }

  Future<void> _showMediaInfo() async {
    final embed = _embedSettingsInSidePanel;
    if (embed) {
      _panelInfoLoading = true;
      _panelInfoRows = const [];
      _openSidePanelPage(_SplitKind.info);
    }
    final accent = Theme.of(context).colorScheme.primary;
    const names = [
      'file-format',
      'file-size',
      'container-fps',
      'estimated-vf-fps',
      'video-bitrate',
      'audio-bitrate',
      'video-codec',
      'audio-codec',
      'hwdec-current',
      'current-ao',
      'video-params/pixelformat',
      'video-params/hw-pixelformat',
      'video-params/colormatrix',
      'video-params/colorlevels',
      'video-params/primaries',
      'video-params/gamma',
      'video-params/sig-peak',
      'video-params/light',
      'video-params/chroma-location',
      'video-params/rotate',
      'video-params/aspect',
      'video-params/par',
      'video-params/average-bpp',
      'video-params/w',
      'video-params/h',
      'video-params/dw',
      'video-params/dh',
      'video-params/alpha',
      'audio-params/format',
      'audio-params/samplerate',
      'audio-params/hr-channels',
      'audio-out-params/samplerate',
      'audio-out-params/hr-channels',
      'audio-out-params/format',
      'current-tracks/video/codec',
      'current-tracks/video/demux-w',
      'current-tracks/video/demux-h',
      'current-tracks/video/demux-fps',
      'current-tracks/video/demux-bitrate',
      'current-tracks/video/lang',
      'current-tracks/video/title',
      'current-tracks/video/decoder-desc',
      'current-tracks/audio/codec',
      'current-tracks/audio/demux-samplerate',
      'current-tracks/audio/demux-bitrate',
      'current-tracks/audio/demux-channels',
      'current-tracks/audio/demux-channel-count',
      'current-tracks/audio/lang',
      'current-tracks/audio/title',
      'current-tracks/audio/decoder-desc',
      'current-tracks/sub/codec',
      'current-tracks/sub/lang',
      'current-tracks/sub/title',
      'metadata/title',
    ];
    final props = await _playerProperties(names);
    if (!mounted) return;

    final state = _player.state;
    final video = state.track.video;
    final videoParams = state.videoParams;
    final fileSize = int.tryParse(_info(props, 'file-size').split('.').first);
    final sourceSize = _sizeText(
      int.tryParse(_info(props, 'current-tracks/video/demux-w')) ?? video.w,
      int.tryParse(_info(props, 'current-tracks/video/demux-h')) ?? video.h,
    );
    final displaySize = _sizeText(
      int.tryParse(_info(props, 'video-params/dw')) ?? videoParams.dw,
      int.tryParse(_info(props, 'video-params/dh')) ?? videoParams.dh,
    );
    final frameSize = _sizeText(
      int.tryParse(_info(props, 'video-params/w')) ?? videoParams.w ?? state.width,
      int.tryParse(_info(props, 'video-params/h')) ?? videoParams.h ?? state.height,
    );
    final hwdec = props['hwdec-current'];
    final decoder = _info(props, 'current-tracks/video/decoder-desc');
    final videoDecoder = hwdec == null
        ? decoder
        : hwdec == 'no'
        ? '软解${decoder.isEmpty ? '' : ' · $decoder'}'
        : '硬解 · $hwdec${decoder.isEmpty ? '' : ' · $decoder'}';
    final containerFps = _fpsProp(props['container-fps']);
    final estimatedFps = _fpsProp(props['estimated-vf-fps']);
    final demuxFps = _fpsProp(props['current-tracks/video/demux-fps']);
    final fps = demuxFps.isNotEmpty
        ? demuxFps
        : _fpsText(video.fps).isNotEmpty
        ? _fpsText(video.fps)
        : containerFps;
    final subtitle = _activeSubtitle ??
        (state.track.subtitle.id == 'no' ||
                state.track.subtitle.id.isEmpty ||
                state.track.subtitle.id == 'auto'
            ? null
            : _subtitleLabel(state.track.subtitle));
    final videos = state.tracks.video
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    final audios = state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    final subtitles = state.tracks.subtitle
        .where(
          (track) =>
              track.id != 'auto' &&
              track.id != 'no' &&
              !track.data &&
              !track.uri &&
              !_isExternalSubtitle(track),
        )
        .toList();
    final audioId = await _currentAudioId(audios);

    final rows = <(String, String)>[];
    String? section;
    void add(String name, String label, String? value) {
      final text = value?.trim() ?? '';
      if (!_usefulInfo(text) || text == '0' || text.toLowerCase() == 'no') {
        return;
      }
      if (section != name) {
        rows.add((name, ''));
        section = name;
      }
      rows.add((label, text));
    }

    add('文件', '文件名', _fileName);
    add('文件', '标题', props['metadata/title']);
    add('文件', '格式', props['file-format']);
    add('文件', '大小', fileSize == null ? '' : formatBytes(fileSize));
    add('文件', '时长', _duration > Duration.zero ? formatDuration(_duration) : '');
    add('文件', '进度', formatDuration(_scrubbing ? _seekPreview : _position));
    add('文件', '倍速', state.rate == 1 ? '' : '${state.rate}×');
    add(
      '文件',
      '缓冲',
      state.buffer > Duration.zero ? formatDuration(state.buffer) : '',
    );

    add('视频', '分辨率', sourceSize.isNotEmpty ? sourceSize : frameSize);
    if (displaySize.isNotEmpty && displaySize != sourceSize && displaySize != frameSize) {
      add('视频', '显示尺寸', displaySize);
    }
    add('视频', '编码', props['video-codec'] ?? video.codec);
    add('视频', '帧率', fps);
    if (estimatedFps.isNotEmpty && estimatedFps != fps) {
      add('视频', '实际帧率', estimatedFps);
    }
    add(
      '视频',
      '码率',
      _bitrateProp(
        props['current-tracks/video/demux-bitrate'] ?? props['video-bitrate'],
      ).isNotEmpty
          ? _bitrateProp(
              props['current-tracks/video/demux-bitrate'] ?? props['video-bitrate'],
            )
          : _bitrateText(video.bitrate?.toDouble()),
    );
    add(
      '视频',
      '像素格式',
      props['video-params/pixelformat'] ?? videoParams.pixelformat,
    );
    add(
      '视频',
      '硬件格式',
      props['video-params/hw-pixelformat'] ?? videoParams.hwPixelformat,
    );
    add('视频', '宽高比', _aspectText(props['video-params/aspect']));
    final par = props['video-params/par'];
    if (par != null && par != '1' && par != '1.000000') add('视频', '像素比', par);
    final rotate = props['video-params/rotate'];
    if (rotate != null && rotate != '0') add('视频', '旋转', '$rotate°');
    add('视频', '色彩矩阵', props['video-params/colormatrix']);
    add('视频', '色域', props['video-params/primaries']);
    add('视频', '传输', props['video-params/gamma']);
    add('视频', '色阶', props['video-params/colorlevels']);
    add('视频', '色度', props['video-params/chroma-location']);
    add('视频', '峰值亮度', props['video-params/sig-peak']);
    add('视频', '光源', props['video-params/light']);
    add('视频', '位深', props['video-params/average-bpp']);
    add('视频', '透明', props['video-params/alpha']);
    add('视频', '解码', videoDecoder);
    add('视频', '标题', props['current-tracks/video/title'] ?? video.title);
    add('视频', '语言', props['current-tracks/video/lang'] ?? video.language);
    if (videos.length > 1) add('视频', '轨道数', '${videos.length}');

    add('音频', '输出声道', props['audio-out-params/hr-channels']);
    final outRate = props['audio-out-params/samplerate'];
    add('音频', '输出采样率', outRate == null ? '' : '$outRate Hz');
    add('音频', '输出格式', props['audio-out-params/format']);
    add('音频', '输出设备', props['current-ao']);
    if (audios.isEmpty) {
      add('音频', '音轨', '没有音轨');
    } else {
      for (var i = 0; i < audios.length; i++) {
        final track = audios[i];
        final current = track.id == audioId;
        add(
          '音频',
          '音轨#${i + 1}${current ? ' 当前' : ''}',
          _audioSummary(track),
        );
      }
    }

    if (subtitles.isEmpty && _externalSubtitles.isEmpty && subtitle == null) {
      add('字幕', '当前', '关闭');
    } else {
      for (var i = 0; i < subtitles.length; i++) {
        final track = subtitles[i];
        final current = subtitle == null
            ? track.id == state.track.subtitle.id ||
                _subtitleLabel(track) == _activeSubtitle
            : _subtitleLabel(track) == subtitle || track.id == subtitle;
        add(
          '字幕',
          '字幕#${i + 1}${current ? ' 当前' : ''}',
          _subtitleSummary(track),
        );
      }
      var externalIndex = 0;
      for (final name in _externalSubtitles) {
        externalIndex++;
        add(
          '字幕',
          '外挂#$externalIndex${name == _activeSubtitle ? ' 当前' : ''}',
          name,
        );
      }
    }

    if (embed) {
      _panelInfoRows = rows;
      _panelInfoLoading = false;
      if (_sidePanel == _SplitKind.info) _update(() {});
      return;
    }

    await _showSheet(
      maxHeightFactor: 0.72,
      (context) => _mediaInfoList(rows: rows, showTitle: true, accent: accent),
    );
  }

  Widget _buildInfoPanel() {
    if (_panelInfoLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _mediaInfoList(
      rows: _panelInfoRows,
      showTitle: false,
      accent: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _mediaInfoList({
    required List<(String, String)> rows,
    required bool showTitle,
    required Color accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 12,
      height: 1.25,
      color: scheme.onSurface.withValues(alpha: 0.55),
    );
    final valueStyle = TextStyle(
      fontSize: 13,
      height: 1.3,
      color: scheme.onSurface.withValues(alpha: 0.92),
    );
    final sectionStyle = TextStyle(
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: accent,
    );
    final titleOffset = showTitle ? 1 : 0;
    return ListView.builder(
      shrinkWrap: showTitle,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: rows.length + titleOffset,
      itemBuilder: (context, index) {
        if (showTitle && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '媒体信息',
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.9),
              ),
            ),
          );
        }
        final row = rows[index - titleOffset];
        if (row.$2.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(
              top: index == titleOffset ? 0 : 12,
              bottom: 6,
            ),
            child: Text(row.$1, style: sectionStyle),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 88, child: Text(row.$1, style: labelStyle)),
              const SizedBox(width: 8),
              Expanded(child: Text(row.$2, style: valueStyle)),
            ],
          ),
        );
      },
    );
  }
}
