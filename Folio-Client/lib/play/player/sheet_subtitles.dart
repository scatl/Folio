part of '../player_page.dart';

extension _PlayerSubtitleSheet on _PlayerPageState {
  Future<String?> _currentSubtitleId(List<SubtitleTrack> tracks) async {
    final chosen = _player.state.track.subtitle.id;
    if (chosen == 'no') return null;
    if (chosen != 'auto' && chosen.isNotEmpty) return chosen;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        final current = (await platform.getProperty('current-tracks/sub/id')).trim();
        if (current.isNotEmpty && current != 'auto' && current != 'no') {
          return current;
        }
      } catch (_) {}
    }
    for (final track in tracks) {
      if (track.isDefault == true) return track.id;
    }
    return tracks.length == 1 ? tracks.first.id : null;
  }

  String _subtitleLabel(SubtitleTrack track) {
    final title = track.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final language = track.language?.trim();
    if (language != null && language.isNotEmpty) return language;
    return '内嵌字幕 ${track.id}';
  }

  bool _isExternalSubtitle(SubtitleTrack track) {
    final title = track.title?.trim();
    if (title == null || title.isEmpty) return false;
    if (_externalSubtitles.contains(title)) return true;
    return _subtitles.any((item) => item.name == title);
  }

  List<SubtitleTrack> _embeddedSubtitleTracks() {
    return _player.state.tracks.subtitle
        .where(
          (track) =>
              track.id != 'auto' &&
              track.id != 'no' &&
              !track.data &&
              !track.uri &&
              !_isExternalSubtitle(track),
        )
        .toList();
  }

  Future<void> _prepareSubtitlePanelState() async {
    final embedded = _embeddedSubtitleTracks();
    final selectedFile = _subtitles.any((item) => item.name == _activeSubtitle)
        ? _activeSubtitle
        : null;
    final selectedId = _activeSubtitle == null
        ? await _currentSubtitleId(embedded)
        : embedded
            .where(
              (track) =>
                  track.id == _activeSubtitle ||
                  _subtitleLabel(track) == _activeSubtitle,
            )
            .map((track) => track.id)
            .firstOrNull;
    _panelEmbeddedSubs = embedded;
    _panelSubtitleSelectedId = selectedId;
    _panelSubtitleSelectedFile = selectedFile;
    _panelSubtitlesOff =
        _activeSubtitle == null && selectedId == null && selectedFile == null;
  }

  Future<void> _showSubtitles() async {
    final embedded = _embeddedSubtitleTracks();
    final selectedFile = _subtitles.any((item) => item.name == _activeSubtitle)
        ? _activeSubtitle
        : null;
    final selectedId = _activeSubtitle == null
        ? await _currentSubtitleId(embedded)
        : embedded
            .where(
              (track) =>
                  track.id == _activeSubtitle ||
                  _subtitleLabel(track) == _activeSubtitle,
            )
            .map((track) => track.id)
            .firstOrNull;
    if (!mounted) return;

    if (_embedSettingsInSidePanel) {
      _panelEmbeddedSubs = embedded;
      _panelSubtitleSelectedId = selectedId;
      _panelSubtitleSelectedFile = selectedFile;
      _panelSubtitlesOff =
          _activeSubtitle == null && selectedId == null && selectedFile == null;
      _openSidePanelPage(_SplitKind.subtitle);
      return;
    }

    final subtitlesOff =
        _activeSubtitle == null && selectedId == null && selectedFile == null;
    await _showSheet(
      (context) => _subtitleSettingsList(
        embedded: embedded,
        selectedId: selectedId,
        selectedFile: selectedFile,
        subtitlesOff: subtitlesOff,
        showTitle: true,
        onCloseHost: () => Navigator.pop(context),
      ),
    );
  }

  Widget _buildSubtitlePanel() {
    return _subtitleSettingsList(
      embedded: _panelEmbeddedSubs,
      selectedId: _panelSubtitleSelectedId,
      selectedFile: _panelSubtitleSelectedFile,
      subtitlesOff: _panelSubtitlesOff,
      showTitle: false,
      onCloseHost: null,
    );
  }

  Widget _subtitleSettingsList({
    required List<SubtitleTrack> embedded,
    required String? selectedId,
    required String? selectedFile,
    required bool subtitlesOff,
    required bool showTitle,
    required VoidCallback? onCloseHost,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final sectionStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: scheme.primary,
    );
    Widget section(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text(label, style: sectionStyle),
        );

    Future<void> refreshPanel() async {
      if (onCloseHost != null) return;
      await _prepareSubtitlePanelState();
      if (mounted) _update(() {});
    }

    return ListView(
      shrinkWrap: onCloseHost != null,
      padding: EdgeInsets.zero,
      children: [
        if (showTitle)
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('字幕', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        _settingsTile(
          title: '关闭字幕',
          leading: const Icon(Icons.subtitles_off_outlined),
          selected: subtitlesOff,
          onTap: () async {
            onCloseHost?.call();
            await _clearSubtitle();
            await refreshPanel();
          },
        ),
        _settingsTile(
          title: '从手机选择字幕',
          leading: const Icon(Icons.phone_android),
          selected: false,
          onTap: () async {
            onCloseHost?.call();
            await _pickLocalSubtitle();
            await refreshPanel();
          },
        ),
        if (embedded.isNotEmpty) ...[
          section('视频内嵌字幕'),
          for (final track in embedded)
            _settingsTile(
              title: _subtitleLabel(track),
              selected: track.id == selectedId,
              onTap: () async {
                onCloseHost?.call();
                await _player.setSubtitleTrack(track);
                if (!mounted) return;
                _update(() => _activeSubtitle = _subtitleLabel(track));
                await refreshPanel();
              },
            ),
        ],
        section('当前文件夹'),
        if (_subtitles.isEmpty)
          _settingsTile(
            title: '没有找到字幕文件',
            selected: false,
            onTap: () {},
          )
        else
          for (final candidate in _subtitles)
            _settingsTile(
              title: candidate.name,
              subtitle: candidate.recommended ? '文件名匹配' : null,
              selected: candidate.name == selectedFile,
              wrapTitle: true,
              onTap: () async {
                onCloseHost?.call();
                await _loadRemoteSubtitle(candidate);
                await refreshPanel();
              },
            ),
      ],
    );
  }
}
