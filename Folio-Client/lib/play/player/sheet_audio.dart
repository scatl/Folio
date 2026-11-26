part of '../player_page.dart';

extension _PlayerAudioSheet on _PlayerPageState {
  Future<void> _showAudioTracks() async {
    final tracks = _player.state.tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    final selected = await _currentAudioId(tracks);
    if (_embedSettingsInSidePanel) {
      _panelAudioTracks = tracks;
      _panelAudioSelectedId = selected;
      _openSidePanelPage(_SplitKind.audio);
      return;
    }
    return _showSheet(
      (context) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('音轨', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          if (tracks.isEmpty)
            _settingsTile(
              title: '没有找到音轨',
              selected: false,
              onTap: () {},
            )
          else
            for (var i = 0; i < tracks.length; i++)
              _settingsTile(
                title: _audioLabel(tracks[i], i),
                subtitle: _audioSummaryLine(tracks[i]),
                leading: const Icon(Icons.audiotrack),
                selected: tracks[i].id == selected,
                onTap: () async {
                  Navigator.pop(context);
                  await _player.setAudioTrack(tracks[i]);
                },
              ),
        ],
      ),
    );
  }

  Widget _buildAudioPanel() {
    final tracks = _panelAudioTracks;
    final selected = _panelAudioSelectedId;
    if (tracks.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          _settingsTile(title: '没有找到音轨', selected: false, onTap: () {}),
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < tracks.length; i++)
          _settingsTile(
            title: _audioLabel(tracks[i], i),
            subtitle: _audioSummaryLine(tracks[i]),
            leading: const Icon(Icons.audiotrack),
            selected: tracks[i].id == selected,
            onTap: () async {
              await _player.setAudioTrack(tracks[i]);
              if (!mounted) return;
              _update(() => _panelAudioSelectedId = tracks[i].id);
            },
          ),
      ],
    );
  }

  Future<String> _currentAudioId(List<AudioTrack> tracks) async {
    final chosen = _player.state.track.audio.id;
    if (chosen != 'auto' && chosen != 'no' && chosen.isNotEmpty) return chosen;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        final current = (await platform.getProperty('current-tracks/audio/id'))
            .trim();
        if (current.isNotEmpty && current != 'auto' && current != 'no') {
          return current;
        }
      } catch (_) {}
    }
    for (final track in tracks) {
      if (track.isDefault == true) return track.id;
    }
    return tracks.isEmpty ? chosen : tracks.first.id;
  }

  String _audioLabel(AudioTrack track, int index) {
    final title = track.title?.trim();
    final language = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      if (language != null &&
          language.isNotEmpty &&
          !title.toLowerCase().contains(language.toLowerCase())) {
        return '$title · $language';
      }
      return title;
    }
    if (language != null && language.isNotEmpty) return language;
    return '音轨 ${index + 1}';
  }

  String _audioSummary(AudioTrack track) {
    final channels = _channelText(track);
    final bitrate = _bitrateText(track.bitrate?.toDouble());
    final parts = <String>[
      if (track.codec != null && track.codec!.isNotEmpty) track.codec!,
      ?channels,
      if (track.samplerate != null && track.samplerate! > 0)
        '${track.samplerate} Hz',
      if (bitrate.isNotEmpty) bitrate,
      if ((track.language ?? '').trim().isNotEmpty) track.language!.trim(),
      if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
      if ((track.decoder ?? '').trim().isNotEmpty) track.decoder!.trim(),
    ];
    return parts.isEmpty ? track.id : parts.join(' · ');
  }

  /// 列表副标题：去掉与标题重复的字段，保持短一行。
  String? _audioSummaryLine(AudioTrack track) {
    final channels = _channelText(track);
    final bitrate = _bitrateText(track.bitrate?.toDouble());
    final parts = <String>[
      if (track.codec != null && track.codec!.isNotEmpty) track.codec!,
      ?channels,
      if (track.samplerate != null && track.samplerate! > 0)
        '${track.samplerate} Hz',
      if (bitrate.isNotEmpty) bitrate,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String _subtitleSummary(SubtitleTrack track) {
    final parts = <String>[
      if ((track.codec ?? '').trim().isNotEmpty) track.codec!.trim(),
      if ((track.language ?? '').trim().isNotEmpty) track.language!.trim(),
      if ((track.title ?? '').trim().isNotEmpty) track.title!.trim(),
    ];
    return parts.isEmpty ? _subtitleLabel(track) : parts.join(' · ');
  }

  String? _channelText(AudioTrack track) {
    final raw = track.channels?.trim() ?? '';
    final unknown = RegExp(
      r'^unknown(\d+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (unknown != null) return '${unknown.group(1)} 声道';
    if (raw.isNotEmpty) return raw;
    final count = track.channelscount;
    if (count != null && count > 0) return '$count 声道';
    return null;
  }
}
