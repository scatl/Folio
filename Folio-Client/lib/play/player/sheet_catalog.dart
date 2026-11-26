part of '../player_page.dart';

extension _PlayerCatalogSheet on _PlayerPageState {
  Future<void> _openCatalogPanel() async {
    if (_playlistMode) {
      if (_embedSettingsInSidePanel) {
        if (_playlistQueue.isEmpty) unawaited(_loadPlaylistQueue());
        _openSplit(_SplitKind.playlist);
        return;
      }
      await _showPlaylistSheet();
      return;
    }
    final catalog = _catalog;
    if (catalog == null || !catalog.showCatalog) return;
    if (_embedSettingsInSidePanel) {
      _ensureCatalogLoaded();
      _openSplit(_SplitKind.catalog);
      return;
    }
    await _showCatalogSheet();
  }

  Future<void> _showCatalogSheet() async {
    _ensureCatalogLoaded();
    await _showSheet(
      (context) {
        final height = MediaQuery.sizeOf(context).height * 0.72;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: height,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              '选集',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_catalog?.isSeries == true)
                          IconButton(
                            tooltip: _catalogGridMode ? '列表' : '宫格',
                            onPressed: () {
                              _catalogGridMode = !_catalogGridMode;
                              setSheetState(() {});
                              _update(() {});
                            },
                            icon: Icon(
                              _catalogGridMode
                                  ? Icons.view_list_rounded
                                  : Icons.grid_view_rounded,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildCatalogPanel()),
                ],
              ),
            );
          },
        );
      },
      maxHeightFactor: 0.78,
    );
  }

  void _ensureCatalogLoaded() {
    _ensureCatalogReady();
  }

  Future<bool> _ensureCatalogReady() async {
    if (_catalogLoaded) return true;
    if (_catalog == null) return false;
    _catalogLoadFuture ??= _loadCatalogData().whenComplete(() {
      _catalogLoadFuture = null;
    });
    await _catalogLoadFuture;
    return _catalogLoaded;
  }

  Future<void> _loadCatalogData() async {
    final catalog = _catalog;
    if (catalog == null) return;
    _catalogLoading = true;
    _catalogError = null;
    _update(() {});
    try {
      if (catalog.isMovie) {
        final mates = await widget.api.get(
          ApiPath.works.collection(catalog.workId),
          parser: listParser(WorkCard.fromJson),
        );
        if (!mounted) return;
        _catalogMates = mates;
      } else {
        final work = await widget.api.get(
          ApiPath.works.one(catalog.workId),
          parser: jsonParser(WorkDetail.fromJson),
        );
        if (!mounted) return;
        final seasons = work.seasons;
        final details = await Future.wait([
          for (final season in seasons)
            widget.api.get(
              ApiPath.works.season(catalog.workId, season.seasonNumber),
              parser: jsonParser(SeasonDetail.fromJson),
            ),
        ]);
        if (!mounted) return;
        _catalogSeasons = details;
      }
      _catalogLoaded = true;
      _catalogError = null;
    } catch (error) {
      if (!mounted) return;
      _catalogError = error is ApiFailure ? error.message : '$error';
    } finally {
      if (mounted) {
        _catalogLoading = false;
        _update(() {});
      }
    }
  }

  Widget _buildCatalogPanel() {
    if (_catalogLoading && !_catalogLoaded) {
      return const Center(child: CircularProgressIndicator(color: FolioColors.copper));
    }
    if (_catalogError != null && !_catalogLoaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_catalogError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  _catalogLoaded = false;
                  _loadCatalogData();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final catalog = _catalog;
    if (catalog == null) {
      return const Center(child: Text('没有选集信息'));
    }
    if (catalog.isMovie) return _buildMovieCatalog();
    return _catalogGridMode ? _buildSeriesCatalogGrid() : _buildSeriesCatalogList();
  }

  Widget _buildMovieCatalog() {
    if (_catalogMates.isEmpty) {
      return const Center(child: Text('没有系列作品', style: TextStyle(color: FolioColors.inkMuted)));
    }
    final currentId = _catalog?.workId;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      itemCount: _catalogMates.length,
      itemBuilder: (context, index) {
        final mate = _catalogMates[index];
        final selected = mate.id == currentId;
        final accent = Theme.of(context).colorScheme.primary;
        return InkWell(
          onTap: selected ? null : () => _playCatalogMovie(mate),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 48,
                    height: 72,
                    child: PosterImage(url: mate.posterUrl, fallback: mate.title),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mate.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? accent : FolioColors.ink,
                        ),
                      ),
                      if (mate.year != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${mate.year}',
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? accent.withValues(alpha: 0.75)
                                : FolioColors.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) _NowPlayingBars(color: accent, height: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeriesCatalogGrid() {
    if (_catalogSeasons.isEmpty) {
      return const Center(child: Text('没有剧集', style: TextStyle(color: FolioColors.inkMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _catalogSeasons.length,
      itemBuilder: (context, index) {
        final season = _catalogSeasons[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                season.heading,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FolioColors.copper,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final episode in season.episodes)
                    _episodeGridCell(season.seasonNumber, episode),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _episodeGridCell(int seasonNumber, EpisodeRow episode) {
    final playable = episode.files.isNotEmpty;
    final selected = _catalog?.seasonNumber == seasonNumber &&
        _catalog?.episodeNumber == episode.number;
    final accent = Theme.of(context).colorScheme.primary;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.22)
          : scheme.onSurface.withValues(alpha: playable ? 0.08 : 0.03),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: playable ? () => _playCatalogEpisode(seasonNumber, episode) : null,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${episode.number}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: !playable
                        ? FolioColors.inkFaint
                        : selected
                            ? accent
                            : FolioColors.ink,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: 6,
                  bottom: 5,
                  child: _NowPlayingBars(color: accent, height: 8, barWidth: 1.5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesCatalogList() {
    if (_catalogSeasons.isEmpty) {
      return const Center(child: Text('没有剧集', style: TextStyle(color: FolioColors.inkMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      itemCount: _catalogSeasons.length,
      itemBuilder: (context, index) {
        final season = _catalogSeasons[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              child: Text(
                season.heading,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: FolioColors.copper,
                ),
              ),
            ),
            for (final episode in season.episodes)
              _episodeListTile(season.seasonNumber, episode),
          ],
        );
      },
    );
  }

  Widget _episodeListTile(int seasonNumber, EpisodeRow episode) {
    final playable = episode.files.isNotEmpty;
    final selected = _catalog?.seasonNumber == seasonNumber &&
        _catalog?.episodeNumber == episode.number;
    final accent = Theme.of(context).colorScheme.primary;
    final runtime = episode.runtimeMinutes == null ? null : '${episode.runtimeMinutes} 分钟';
    final title = episode.title?.trim();
    final subtitle = [
      if (title != null && title.isNotEmpty) title,
      ?runtime,
    ].join(' · ');
    return InkWell(
      onTap: playable ? () => _playCatalogEpisode(seasonNumber, episode) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '${episode.number}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: !playable
                      ? FolioColors.inkFaint
                      : selected
                          ? accent
                          : FolioColors.ink,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title == null || title.isEmpty ? '第 ${episode.number} 集' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: !playable
                          ? FolioColors.inkFaint
                          : selected
                              ? accent
                              : FolioColors.ink,
                    ),
                  ),
                  if (subtitle.isNotEmpty && title != null && title.isNotEmpty && runtime != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      runtime,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? accent.withValues(alpha: 0.72)
                            : FolioColors.inkMuted,
                      ),
                    ),
                  ] else if (runtime != null && (title == null || title.isEmpty)) ...[
                    const SizedBox(height: 2),
                    Text(
                      runtime,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? accent.withValues(alpha: 0.72)
                            : FolioColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) _NowPlayingBars(color: accent, height: 14),
          ],
        ),
      ),
    );
  }

  /// 返回是否成功发起播放；[pickFirstFile] 为 true 时多文件取第一个（上下集用）。
  Future<bool> _playCatalogMovie(
    WorkCard mate, {
    bool pickFirstFile = false,
  }) async {
    try {
      final work = await widget.api.get(
        ApiPath.works.one(mate.id),
        parser: jsonParser(WorkDetail.fromJson),
      );
      if (!mounted) return false;
      if (work.files.isEmpty) {
        if (!pickFirstFile) _toast('没有可播放的文件');
        return false;
      }
      final LibraryFileBrief? file;
      if (pickFirstFile || work.files.length == 1) {
        file = work.files.first;
      } else {
        file = await chooseLibraryFile(context, work.files);
      }
      if (file == null || !mounted) return false;
      await _switchPlayback(
        fileId: file.id,
        fileName: file.fileName,
        posterUrl: work.posterUrl ?? work.backdropUrl ?? mate.posterUrl,
        prepareMeta: PlaybackPrepareMeta.fromWork(work),
        catalog: PlaybackCatalogContext(
          workId: work.id,
          kind: 'movie',
          showCatalog: true,
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (!pickFirstFile) {
        _toast(error is ApiFailure ? error.message : '打开失败');
      }
      return false;
    }
  }

  Future<bool> _playCatalogEpisode(
    int seasonNumber,
    EpisodeRow episode, {
    bool pickFirstFile = false,
  }) async {
    final catalog = _catalog;
    if (catalog == null || episode.files.isEmpty) return false;
    final LibraryFileBrief? file;
    if (pickFirstFile || episode.files.length == 1) {
      file = episode.files.first;
    } else {
      file = await chooseLibraryFile(context, episode.files);
    }
    if (file == null || !mounted) return false;
    SeasonDetail? season;
    for (final item in _catalogSeasons) {
      if (item.seasonNumber == seasonNumber) {
        season = item;
        break;
      }
    }
    await _switchPlayback(
      fileId: file.id,
      fileName: file.fileName,
      posterUrl: episode.stillUrl ?? _posterUrl,
      prepareMeta: PlaybackPrepareMeta(
        title: episode.heading,
        subtitle: season == null
            ? null
            : '${season.workTitle} · ${season.heading}',
        playbackTitle: seriesPlaybackTitle(
          workTitle: season?.workTitle ?? '',
          seasonNumber: seasonNumber,
          episodeNumber: episode.number,
          episodeTitle: episode.title,
        ),
        kindLabel: '剧集',
        year: episode.airDate != null && episode.airDate!.length >= 4
            ? int.tryParse(episode.airDate!.substring(0, 4))
            : null,
        runtimeLabel:
            episode.runtimeMinutes == null ? null : '${episode.runtimeMinutes} 分钟',
        ratings: episode.voteAverage == null || episode.voteAverage! <= 0
            ? const []
            : [
                WorkRating(
                  provider: 'tmdb',
                  value: episode.voteAverage!,
                  votes: episode.voteCount,
                  scale: 10,
                ),
              ],
      ),
      catalog: catalog.copyWith(
        seasonNumber: seasonNumber,
        episodeNumber: episode.number,
      ),
    );
    return true;
  }

  Widget _buildPlaylistPanel({VoidCallback? beforePlay}) {
    if (_playlistQueue.isEmpty && _playlistError == null) {
      return const Center(child: CircularProgressIndicator(color: FolioColors.copper));
    }
    if (_playlistQueue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _playlistError ?? '这个播放列表没有可播放的视频',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FolioColors.inkMuted),
          ),
        ),
      );
    }
    final current = _playlistIndex();
    return ListView.builder(
      itemCount: _playlistQueue.length,
      itemBuilder: (context, index) {
        final entry = _playlistQueue[index];
        final previous = index == 0 ? null : _playlistQueue[index - 1];
        final showGroup = entry.kind == 'series' && previous?.workId != entry.workId;
        final selected = index == current;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showGroup)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  entry.workTitle,
                  style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13),
                ),
              ),
            ListTile(
              selected: selected,
              selectedColor: FolioColors.copper,
              textColor: FolioColors.ink,
              title: Text(
                entry.kind == 'series' ? entry.label : entry.workTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: entry.kind == 'series'
                  ? null
                  : const Text('电影', style: TextStyle(color: FolioColors.inkMuted)),
              onTap: selected
                  ? null
                  : () {
                      beforePlay?.call();
                      unawaited(_playPlaylistEntry(entry));
                    },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPlaylistSheet() async {
    if (_playlistQueue.isEmpty) await _loadPlaylistQueue();
    if (!mounted) return;
    await _showSheet((context) {
      final height = MediaQuery.sizeOf(context).height * 0.72;
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '播放列表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FolioColors.ink),
              ),
            ),
            Expanded(
              child: _buildPlaylistPanel(
                beforePlay: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// 当前播放指示：三根错峰跳动的竖条。
class _NowPlayingBars extends StatefulWidget {
  const _NowPlayingBars({
    required this.color,
    this.height = 14,
    this.barWidth = 2,
  });

  final Color color;
  final double height;
  final double barWidth;

  @override
  State<_NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<_NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _barHeight(double phase) {
    final t = (_controller.value + phase) % 1.0;
    final wave = math.sin(t * math.pi * 2);
    return widget.height * (0.35 + 0.65 * ((wave + 1) / 2));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          height: widget.height,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(width: widget.barWidth * 0.7),
                Container(
                  width: widget.barWidth,
                  height: _barHeight(i * 0.22),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.barWidth),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

