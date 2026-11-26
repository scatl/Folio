part of '../player_page.dart';

extension _PlayerPlayback on _PlayerPageState {
  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness.instance.application;
      if (!mounted) return;
      _brightness = value.clamp(0.02, 1.0);
    } catch (_) {}
  }

  Future<void> _loadVolume() async {
    try {
      final value = await VolumeController.instance.getVolume();
      if (!mounted) return;
      _volume = value.clamp(0.0, 1.0);
    } catch (_) {}
  }

  bool _openIsCurrent(int generation) =>
      mounted && generation == _openGeneration;

  Future<void> _applyHwdec() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('hwdec', _PlayerPageState._hardwareDecode ? 'auto-safe' : 'no');
  }
  Future<void> _loadPlaybackRules() async {
    try {
      final settings = await widget.api.get(
        ApiPath.settings,
        parser: jsonParser(AppSettings.fromJson),
      );
      _ignoreBelowMs = settings.playbackIgnoreBelowSeconds * 1000;
      _completeRemainingMs = settings.playbackCompleteRemainingSeconds * 1000;
    } on ApiFailure {
      // 读不到设置时沿用 10 秒 / 30 秒。
    }
  }

  Future<void> _prepareAndOpen() async {
    try {
      await _loadPlaybackRules();
      await _ensureResumeHint();
      final media = await resolvePlaybackMedia(widget.api, _fileId);
      if (!mounted) return;
      _contentUrl = media.url;
      _headers = media.headers;
      _update(() => _prepareError = null);
      // 底层先开播，准备页同时淡出。
      final opening = _open();
      await _prepareFade.animateTo(0, curve: Curves.easeOutCubic);
      if (!mounted) return;
      _update(() => _preparing = false);
      await opening;
      await _loadFolderSubtitles();
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiFailure ? error.message : '$error';
      _update(() {
        _preparing = false;
        _prepareError = message;
      });
      _prepareFade.value = 1;
    }
  }

  Future<void> _ensureResumeHint() async {
    if (_pendingResume != null) return;
    try {
      final progress = await widget.api.get(
        ApiPath.playback.progress,
        queryParameters: {'libraryFileId': _fileId},
        parser: jsonParser(PlaybackProgress.fromJson),
      );
      final resume = progress.resumePositionMs;
      if (resume != null && resume > 0) {
        _pendingResume = Duration(milliseconds: resume);
      }
    } on ApiFailure {
      // 无进度或未登录时忽略。
    }
  }

  void _armProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_reportProgress());
    });
  }

  Future<void> _reportProgress({bool force = false}) async {
    if (!_playbackReady && !force) return;
    final positionMs = _position.inMilliseconds;
    final durationMs = _duration.inMilliseconds;
    if (positionMs < _ignoreBelowMs) {
      final nearEnd = durationMs > 0 && durationMs - positionMs <= _completeRemainingMs;
      if (!nearEnd) return;
    }
    if (!force && (positionMs - _lastReportedMs).abs() < 2_000) return;
    _lastReportedMs = positionMs;
    try {
      await widget.api.put(
        ApiPath.playback.progress,
        data: {
          'libraryFileId': _fileId,
          'positionMs': positionMs,
          if (durationMs > 0) 'durationMs': durationMs,
        },
      );
    } catch (_) {}
  }

  /// 同页换源：保持侧栏/选集打开，重新走准备页。
  Future<void> _switchPlayback({
    required int fileId,
    required String fileName,
    String? posterUrl,
    PlaybackPrepareMeta? prepareMeta,
    PlaybackCatalogContext? catalog,
    int? resumePositionMs,
  }) async {
    await _reportProgress(force: true);
    _progressTimer?.cancel();
    ++_openGeneration;
    try {
      await _player.stop();
    } catch (_) {}
    _contentUrl = null;
    _headers = const {};
    _error = null;
    _playbackReady = false;
    _folderSubsReady = false;
    _didAutoPickSubtitle = false;
    _subtitles.clear();
    _externalSubtitles.clear();
    _activeSubtitle = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _lastReportedMs = -1;
    _pendingResume = resumePositionMs != null && resumePositionMs > 0
        ? Duration(milliseconds: resumePositionMs)
        : null;
    _fileId = fileId;
    _fileName = fileName;
    _segments = const [];
    _skipApplied.clear();
    _userHeldSkips.clear();
    _lastAutoPosMs = -1;
    _manualSeekGrace = null;
    _skipGeneration = 0;
    _segmentsLoadedFor = null;
    unawaited(_loadSegments());
    _posterUrl = posterUrl;
    _prepareMeta = prepareMeta;
    if (catalog != null) {
      final kindChanged = _catalog?.kind != catalog.kind;
      final workChanged = _catalog?.workId != catalog.workId;
      // 电影系列内切换保留 mates；换剧集作品或类型才整表重载。
      final reloadCatalog =
          kindChanged || (catalog.isSeries && workChanged);
      _catalog = catalog;
      if (reloadCatalog) {
        _catalogLoaded = false;
        _catalogMates = const [];
        _catalogSeasons = const [];
        _catalogError = null;
      }
    }
    _prepareFade.value = 1;
    _update(() {
      _preparing = true;
      _prepareError = null;
    });
    if (catalog != null && !_catalogLoaded) {
      _ensureCatalogLoaded();
    }
    await _prepareAndOpen();
  }

  Future<void> _open() async {
    final url = _contentUrl;
    if (url == null || url.isEmpty) return;
    final generation = ++_openGeneration;
    _holdProgress = true;
    _playbackReady = false;
    final start = _pendingResume;
    _pendingResume = null;
    try {
      await _configureAudioOutput();
      await _configureCache();
      await _configureSubtitles();
      await _applyHwdec();
      if (!_openIsCurrent(generation)) return;
      await _openAt(url, start);
      if (!_openIsCurrent(generation)) return;
      await _player.setVolume(100);
      _holdProgress = false;
      await _player.play();
      if (_playbackRate != 1) await _player.setRate(_playbackRate);
      if (!_openIsCurrent(generation)) return;
      _playbackReady = true;
      _armProgressTimer();
      await _maybeAutoSelectMatchedSubtitle();
    } catch (error) {
      if (!_openIsCurrent(generation)) return;
      _holdProgress = false;
      _update(() => _error = '无法播放：$error');
    }
  }

  Future<void> _openAt(String url, Duration? start) async {
    final headers = _headers;
    try {
      await _player.open(Media(url, httpHeaders: headers, start: start), play: false);
    } catch (_) {
      if (start == null) rethrow;
      await _player.open(Media(url, httpHeaders: headers), play: false);
    }
  }

  Future<void> _configureAudioOutput() async {
    final platform = _player.platform;
    if (platform is! NativePlayer || !Platform.isAndroid) return;
    // OpenSL ES stays silent on 5.1 / 7.1 unless the stream is downmixed first.
    await platform.setProperty('ao', 'opensles');
    await platform.setProperty('audio-channels', 'stereo');
    await platform.setProperty('volume', '100');
  }

  Future<void> _configureCache() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // Keep about 30 seconds ahead of the playhead, so 1:00 can buffer to 1:30.
    await platform.setProperty('demuxer-readahead-secs', '30');
    await platform.setProperty('demuxer-max-bytes', '268435456');
  }

  Future<void> _configureSubtitles() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    if (Platform.isAndroid) {
      final data = await rootBundle.load('assets/fonts/DroidSansFallback.ttf');
      final directory = Directory(
        '${(await getApplicationSupportDirectory()).path}/fonts',
      );
      await directory.create(recursive: true);
      final file = File('${directory.path}/DroidSansFallback.ttf');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      await platform.setProperty('sub-fonts-dir', directory.path);
      await platform.setProperty('sub-font', 'Droid Sans Fallback');
    }
    // libass draws onto the video frame. Keep this near mpv's default so
    // plain text and ASS styles stay readable without covering the picture.
    await platform.setProperty('sub-font-size', '48');
    await platform.setProperty('sub-scale', '1');
    await platform.setProperty('sub-ass-override', 'scale');
    await platform.setProperty('sub-border-size', '2');
    await platform.setProperty('sub-margin-y', '48');
  }

  Future<void> _loadPlaylistQueue() {
    final existing = _playlistLoadFuture;
    if (existing != null) return existing;
    final run = _fetchPlaylistQueue();
    _playlistLoadFuture = run;
    run.whenComplete(() {
      if (identical(_playlistLoadFuture, run)) _playlistLoadFuture = null;
    });
    return run;
  }

  Future<void> _fetchPlaylistQueue() async {
    final id = _playlistId;
    if (id == null) return;
    _playlistError = null;
    try {
      final rows = await widget.api.get(
        ApiPath.playlists.queue(id),
        parser: listParser(PlaylistQueueEntry.fromJson),
      );
      if (!mounted || _playlistId != id) return;
      _update(() {
        _playlistQueue = rows;
      });
    } on ApiFailure catch (error) {
      if (!mounted || _playlistId != id) return;
      _update(() {
        _playlistError = error.message;
      });
    } catch (error) {
      if (!mounted || _playlistId != id) return;
      _update(() {
        _playlistError = '$error';
      });
    }
  }

  int _playlistIndex() {
    final byFile = _playlistQueue.indexWhere((entry) => entry.fileId == _fileId);
    if (byFile >= 0) return byFile;
    final workId = _playlistWorkId;
    if (workId == null) return -1;
    final season = _playlistSeason;
    final episode = _playlistEpisode;
    if (season != null && episode != null) {
      final byEpisode = _playlistQueue.indexWhere(
        (entry) => entry.workId == workId && entry.seasonNumber == season && entry.episodeNumber == episode,
      );
      if (byEpisode >= 0) return byEpisode;
    }
    return _playlistQueue.indexWhere((entry) => entry.kind != 'series' && entry.workId == workId);
  }

  Future<void> _playPlaylistEntry(PlaylistQueueEntry entry) async {
    if (entry.fileId == _fileId) return;
    _playlistWorkId = entry.workId;
    _playlistSeason = entry.seasonNumber;
    _playlistEpisode = entry.episodeNumber;
    int? resume;
    try {
      final progress = await widget.api.get(
        ApiPath.playback.progress,
        queryParameters: {'libraryFileId': entry.fileId},
        parser: jsonParser(PlaybackProgress.fromJson),
      );
      resume = progress.resumePositionMs;
    } on ApiFailure {
      resume = null;
    }
    if (!mounted) return;
    final series = entry.kind == 'series' && entry.seasonNumber != null && entry.episodeNumber != null;
    await _switchPlayback(
      fileId: entry.fileId,
      fileName: entry.fileName,
      posterUrl: entry.posterUrl ?? _posterUrl,
      resumePositionMs: resume,
      prepareMeta: PlaybackPrepareMeta(
        title: entry.workTitle,
        playbackTitle: series
            ? seriesPlaybackTitle(
                workTitle: entry.workTitle,
                seasonNumber: entry.seasonNumber!,
                episodeNumber: entry.episodeNumber!,
                episodeTitle: entry.episodeTitle,
              )
            : entry.workTitle,
        kindLabel: entry.kind == 'series' ? '剧集' : '电影',
      ),
    );
  }

  Future<void> _playAdjacentPlaylist(int delta) async {
    if (_playlistQueue.isEmpty) await _loadPlaylistQueue();
    if (!mounted) return;
    if (_playlistQueue.isEmpty) {
      _toast(_playlistError ?? '这个播放列表没有可播放的视频');
      return;
    }
    final index = _playlistIndex();
    if (index < 0) {
      _toast('找不到当前视频在播放列表中的位置');
      return;
    }
    final next = index + delta;
    if (next < 0 || next >= _playlistQueue.length) {
      _toast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频');
      return;
    }
    await _playPlaylistEntry(_playlistQueue[next]);
  }

  Future<void> _playNext() => _playAdjacent(1);

  Future<void> _playPrevious() => _playAdjacent(-1);

  Future<void> _playAdjacent(int delta) async {
    if (_playlistMode) {
      await _playAdjacentPlaylist(delta);
      return;
    }
    if (!_showCatalog) {
      _toast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频');
      return;
    }
    final ready = await _ensureCatalogReady();
    if (!mounted) return;
    if (!ready) {
      _toast(_catalogError ?? '选集加载失败');
      return;
    }
    final catalog = _catalog;
    if (catalog == null) {
      _toast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频');
      return;
    }
    if (catalog.isMovie) {
      await _playAdjacentMovie(delta);
    } else {
      await _playAdjacentEpisode(delta);
    }
  }

  Future<void> _playAdjacentMovie(int delta) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final mates = _catalogMates;
    final idx = mates.indexWhere((mate) => mate.id == catalog.workId);
    if (idx < 0) {
      _toast('找不到当前影片在系列中的位置');
      return;
    }
    var cursor = idx + delta;
    while (cursor >= 0 && cursor < mates.length) {
      final ok = await _playCatalogMovie(mates[cursor], pickFirstFile: true);
      if (!mounted) return;
      if (ok) return;
      cursor += delta;
    }
    _toast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频');
  }

  Future<void> _playAdjacentEpisode(int delta) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final queue = <(int season, EpisodeRow episode)>[];
    for (final season in _catalogSeasons) {
      for (final episode in season.episodes) {
        if (episode.files.isNotEmpty) {
          queue.add((season.seasonNumber, episode));
        }
      }
    }
    if (queue.isEmpty) {
      _toast('没有可播放的剧集');
      return;
    }
    final idx = queue.indexWhere(
      (item) =>
          item.$1 == catalog.seasonNumber &&
          item.$2.number == catalog.episodeNumber,
    );
    if (idx < 0) {
      _toast('找不到当前集在列表中的位置');
      return;
    }
    final next = idx + delta;
    if (next < 0 || next >= queue.length) {
      _toast(delta > 0 ? '已经是最后一个视频' : '已经是第一个视频');
      return;
    }
    final (seasonNumber, episode) = queue[next];
    await _playCatalogEpisode(seasonNumber, episode, pickFirstFile: true);
  }

  Future<void> _exitPlayer() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await _player.pause();
    } catch (_) {}
    if (_PlayerPageState._openCount <= 1) {
      _stopOrientationFollow();
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      final deadline = DateTime.now().add(const Duration(milliseconds: 400));
      while (mounted &&
          MediaQuery.orientationOf(context) != Orientation.portrait &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }
    unawaited(_reportProgress(force: true));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _useSubtitleData(String title, String data) async {
    await _player.setSubtitleTrack(SubtitleTrack.data(data, title: title));
    if (!mounted) return;
    _update(() {
      _externalSubtitles.add(title);
      _activeSubtitle = title;
    });
  }

  Future<void> _clearSubtitle() async {
    await _player.setSubtitleTrack(SubtitleTrack.no());
    if (!mounted) return;
    _update(() => _activeSubtitle = null);
  }

  /// `.../files/{id}/content` → `.../files/{id}`
  String _fileResourceBase() {
    final url = _contentUrl ?? '';
    const suffix = '/content';
    if (url.endsWith(suffix)) {
      return url.substring(0, url.length - suffix.length);
    }
    return url;
  }

  Future<void> _loadFolderSubtitles() async {
    final base = _fileResourceBase();
    if (base.isEmpty) {
      _folderSubsReady = true;
      return;
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        headers: {
          Headers.acceptHeader: 'application/json',
          ..._headers,
        },
      ),
    );
    try {
      final response = await dio.get<dynamic>('$base/subtitles');
      final body = response.data;
      if (body is! Map) return;
      final code = body['code'];
      final data = body['data'];
      if (code != 0 || data is! List) return;
      final names = data.map((item) => item.toString()).toList();
      if (!mounted) return;
      _update(() {
        _subtitles
          ..clear()
          ..addAll(rankSubtitles(_fileName, names));
      });
      _folderSubsReady = true;
      await _maybeAutoSelectMatchedSubtitle();
    } catch (_) {
      // 列表失败时字幕菜单仍可「从手机选择」。
      _folderSubsReady = true;
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _maybeAutoSelectMatchedSubtitle() async {
    if (_didAutoPickSubtitle || !_playbackReady || !_folderSubsReady) return;
    if (_activeSubtitle != null) {
      _didAutoPickSubtitle = true;
      return;
    }
    SubtitleCandidate? match;
    for (final candidate in _subtitles) {
      if (candidate.recommended) {
        match = candidate;
        break;
      }
    }
    _didAutoPickSubtitle = true;
    if (match == null || !mounted) return;
    await _loadRemoteSubtitle(match, quiet: true);
  }

  Future<void> _loadRemoteSubtitle(
    SubtitleCandidate candidate, {
    bool quiet = false,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.bytes,
        headers: {..._headers},
      ),
    );
    try {
      final response = await dio.get<List<int>>(
        '${_fileResourceBase()}/subtitles/content',
        queryParameters: {'name': candidate.name},
      );
      final raw = response.data;
      if (raw == null || raw.isEmpty) {
        if (!quiet) _toast('没有读到字幕内容');
        return;
      }
      final bytes = Uint8List.fromList(raw);
      if (looksBinary(bytes)) {
        if (!quiet) _toast('这个字幕不是文本格式，播放器无法加载');
        return;
      }
      await _useSubtitleData(candidate.name, decodeSubtitleBytes(bytes));
    } catch (_) {
      if (!quiet) _toast('加载字幕失败');
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _pickLocalSubtitle() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub', 'smi'],
    );
    if (file == null) return;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      _toast('没有读到字幕内容');
      return;
    }
    if (looksBinary(bytes)) {
      _toast('这个字幕不是文本格式，播放器无法加载');
      return;
    }
    await _useSubtitleData(file.name, decodeSubtitleBytes(bytes));
  }

}
