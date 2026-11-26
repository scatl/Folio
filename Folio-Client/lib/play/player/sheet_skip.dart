part of '../player_page.dart';

extension _PlayerSkip on _PlayerPageState {
  Future<void> _loadSkipMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _update(() => _skipMode = skipModeFromStored(prefs.getString(skipModeStorageKey)));
    await _loadSegments();
  }

  Future<void> _loadSegments() async {
    if (_skipMode == SkipMode.off) return;
    final fileId = _fileId;
    if (fileId <= 0 || _segmentsLoadedFor == fileId) return;
    try {
      final payload = await widget.api.get(
        ApiPath.libraryFiles.segments(fileId),
        parser: (data) => MediaSegmentsPayload.fromJson(Map<String, dynamic>.from(data as Map)),
      );
      if (!mounted || fileId != _fileId) return;
      _segmentsLoadedFor = fileId;
      _update(() => _segments = payload.segments);
      _maybeAutoSkip();
    } catch (_) {}
  }

  Future<void> _applySkipMode(SkipMode mode) async {
    if (mode != _skipMode) {
      _update(() => _skipMode = mode);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(skipModeStorageKey, skipModeStored(mode));
    if (!mounted || mode == SkipMode.off) return;
    await _loadSegments();
    _maybeAutoSkip();
  }

  SkipAction? _segmentAt(int positionMs) {
    return skipActionFor(
      positionMs: positionMs,
      durationMs: _duration.inMilliseconds,
      segments: _segments,
      series: _segmentSeries,
      dismissed: const {},
    );
  }

  void _noteManualSeek(int positionMs) {
    _skipGeneration += 1;
    _manualSeekGrace = DateTime.now().add(const Duration(milliseconds: 1500));
    _lastAutoPosMs = positionMs;
    final segment = _segmentAt(positionMs);
    if (segment != null) {
      _userHeldSkips.add(segment.key);
    } else {
      _userHeldSkips.clear();
    }
  }

  void _maybeAutoSkip() {
    if (_skipMode != SkipMode.auto || !_playbackReady || _scrubbing || _seeking || _holdProgress) return;
    final position = _position.inMilliseconds;
    final previous = _lastAutoPosMs;
    _lastAutoPosMs = position;
    final segment = _segmentAt(position);
    final jumped = previous >= 0 && (position - previous).abs() > 2500;
    final grace = _manualSeekGrace;
    final inGrace = grace != null && DateTime.now().isBefore(grace);
    if (jumped) {
      if (segment != null) {
        _userHeldSkips.add(segment.key);
      } else if (!inGrace) {
        _userHeldSkips.clear();
      }
      return;
    }
    if (inGrace) return;
    if (segment == null) {
      _userHeldSkips.clear();
      return;
    }
    if (_userHeldSkips.contains(segment.key)) return;
    final action = skipActionFor(
      positionMs: position,
      durationMs: _duration.inMilliseconds,
      segments: _segments,
      series: _segmentSeries,
      dismissed: _skipApplied,
    );
    if (action == null) return;
    _skipApplied.add(action.key);
    unawaited(_performSkip(action));
  }

  Future<void> _performSkip(SkipAction action) async {
    final generation = _skipGeneration;
    if (action.advance) {
      final before = _fileId;
      await _playNext();
      if (!mounted || generation != _skipGeneration || _fileId != before) return;
    }
    if (!mounted || generation != _skipGeneration) return;
    final target = Duration(milliseconds: action.targetMs);
    try {
      await _player.seek(target);
    } catch (_) {}
    if (!mounted || generation != _skipGeneration) return;
    _showSeekResult(target);
  }

  Widget _buildSkipPanel() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final mode in SkipMode.values)
          _settingsTile(
            title: skipModeLabel(mode),
            subtitle: _skipModeHint(mode),
            selected: mode == _skipMode,
            onTap: () => _applySkipMode(mode),
          ),
      ],
    );
  }

  Future<void> _showSkipSettings() async {
    if (_embedSettingsInSidePanel) {
      _openSidePanelPage(_SplitKind.skip);
      return;
    }
    final selected = await _showSheet<SkipMode>(
      (context) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('跳过片头片尾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final mode in SkipMode.values)
            _settingsTile(
              title: skipModeLabel(mode),
              subtitle: _skipModeHint(mode),
              selected: mode == _skipMode,
              onTap: () => Navigator.pop(context, mode),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _applySkipMode(selected);
  }

  String _skipModeHint(SkipMode mode) {
    return switch (mode) {
      SkipMode.off => '不显示，也不自动跳',
      SkipMode.button => '播到片头或片尾时出现按钮',
      SkipMode.auto => '播到片头或片尾时直接跳过',
    };
  }
}
