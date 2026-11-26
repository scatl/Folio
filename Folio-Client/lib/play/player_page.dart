import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/play/format.dart';
import 'package:folio/play/play_library.dart';
import 'package:folio/play/playback_resolve.dart';
import 'package:folio/play/skip_segments.dart';
import 'package:folio/play/subtitles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/rating_chip.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';

part 'player/player_playback.dart';
part 'player/player_orientation.dart';
part 'player/player_gestures.dart';
part 'player/player_sheets.dart';
part 'player/side_panel.dart';
part 'player/sheet_hardware.dart';
part 'player/sheet_rate.dart';
part 'player/sheet_skip.dart';
part 'player/sheet_audio.dart';
part 'player/sheet_subtitles.dart';
part 'player/sheet_info.dart';
part 'player/sheet_catalog.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.api,
    required this.fileId,
    required this.fileName,
    this.posterUrl,
    this.prepareMeta,
    this.catalog,
    this.playlistId,
    this.resumePositionMs,
  });

  final ApiClient api;
  final int fileId;
  final String fileName;
  final String? posterUrl;
  final PlaybackPrepareMeta? prepareMeta;
  final PlaybackCatalogContext? catalog;
  final int? playlistId;
  final int? resumePositionMs;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

enum _DragAxis { undecided, horizontal, vertical }

enum _TopBarAction { orientation, audio, subtitle, rate, skip, decode, info }

class _PlayerPageState extends State<PlayerPage> with TickerProviderStateMixin {
  static var _openCount = 0;
  static var _hardwareDecode = true;

  late final Player _player;
  late final VideoController _controller;
  late final AnimationController _sidePanelAnim;
  /// 1 = 准备页可见，0 = 已淡出。
  late final AnimationController _prepareFade;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _seeking = false;
  /// 进度条正在拖动时的目标。松手回调丢失时用来补一次跳转。
  int? _sliderDragMs;
  int _sliderCommit = 0;
  int? _seekAnchorMs;
  DateTime? _seekAnchorUntil;
  bool _scrubbing = false;
  bool _boosting = false;
  double _boostRate = 2;
  double _boostAnchor = 2;
  double _playbackRate = 1;
  double _boostOriginY = 0;
  bool _showControls = true;
  bool _showRemaining = false;
  bool _wasPlaying = false;
  bool _seekRunning = false;
  Duration _seekPreview = Duration.zero;
  Duration _seekOrigin = Duration.zero;
  Duration? _latestSeek;
  Completer<void>? _seekDone;
  String? _error;
  String? _activeSubtitle;
  final List<SubtitleCandidate> _subtitles = [];
  final Set<String> _externalSubtitles = {};
  Timer? _hideTimer;
  Timer? _skipRepeat;
  _DragAxis _dragAxis = _DragAxis.undecided;
  Offset? _panOrigin;
  bool _levelIsBrightness = false;
  bool _showLevel = false;
  double _brightness = 0.5;
  double _volume = 1;
  bool _leaving = false;
  Duration? _pendingResume;
  int _ignoreBelowMs = 10 * 1000;
  int _completeRemainingMs = 30 * 1000;
  Timer? _progressTimer;
  int _lastReportedMs = -1;
  late int _fileId;
  late String _fileName;
  String? _posterUrl;
  PlaybackPrepareMeta? _prepareMeta;
  PlaybackCatalogContext? _catalog;
  int _openGeneration = 0;
  bool _holdProgress = false;
  _SplitKind? _sidePanel;
  /// 侧栏页切换方向：true 推进（从右入），false 返回（从左入）。
  bool _sidePanelPush = true;
  List<AudioTrack> _panelAudioTracks = const [];
  String? _panelAudioSelectedId;
  List<SubtitleTrack> _panelEmbeddedSubs = const [];
  String? _panelSubtitleSelectedId;
  String? _panelSubtitleSelectedFile;
  bool _panelSubtitlesOff = false;
  List<(String, String)> _panelInfoRows = const [];
  bool _panelInfoLoading = false;
  bool _folderSubsReady = false;
  bool _playbackReady = false;
  bool _didAutoPickSubtitle = false;
  String? _contentUrl;
  Map<String, String> _headers = const {};
  bool _preparing = true;
  String? _prepareError;
  bool _ownsOrientation = false;
  bool _orientationListening = false;
  StreamSubscription<dynamic>? _gravitySub;
  Timer? _orientationHoldTimer;
  _DeviceHold? _pendingHold;
  _DeviceHold? _stableHold;
  _DeviceHold? _buttonHold;
  DeviceOrientation? _requestedOrientation;
  bool _catalogGridMode = true;
  bool _catalogLoading = false;
  bool _catalogLoaded = false;
  String? _catalogError;
  List<WorkCard> _catalogMates = const [];
  List<SeasonDetail> _catalogSeasons = const [];
  Future<void>? _catalogLoadFuture;
  int? _playlistId;
  List<PlaylistQueueEntry> _playlistQueue = const [];
  String? _playlistError;
  int? _playlistWorkId;
  int? _playlistSeason;
  int? _playlistEpisode;
  Future<void>? _playlistLoadFuture;
  SkipMode _skipMode = SkipMode.button;
  List<MediaSegmentSpan> _segments = const [];
  final Set<String> _skipApplied = {};
  final Set<String> _userHeldSkips = {};
  int _lastAutoPosMs = -1;
  DateTime? _manualSeekGrace;
  int _skipGeneration = 0;
  int? _segmentsLoadedFor;

  bool get _playlistMode => _playlistId != null;
  bool get _showCatalog => _catalog?.showCatalog == true;

  bool get _segmentSeries {
    if (_playlistMode && _playlistQueue.isNotEmpty) {
      final index = _playlistIndex();
      if (index >= 0 && index < _playlistQueue.length) {
        return _playlistQueue[index].kind == 'series';
      }
    }
    return _catalog?.isSeries == true;
  }

  SkipAction? get _skipOffer {
    if (_skipMode != SkipMode.button || _preparing || _scrubbing || _error != null) return null;
    return skipActionFor(
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
      segments: _segments,
      series: _segmentSeries,
      dismissed: _skipApplied,
    );
  }

  @override
  void initState() {
    super.initState();
    final entering = _openCount == 0;
    _openCount++;
    if (entering) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _ownsOrientation = true;
      _startOrientationFollow();
    }
    _player = Player(
      configuration: const PlayerConfiguration(
        libass: true,
        libassAndroidFont: 'assets/fonts/DroidSansFallback.ttf',
        libassAndroidFontName: 'Droid Sans Fallback',
      ),
    );
    _controller = VideoController(_player);
    _subscriptions.addAll([
      _player.stream.position.listen((position) {
        if (!mounted || _seeking || _holdProgress) return;
        final anchor = _seekAnchorMs;
        final until = _seekAnchorUntil;
        if (anchor != null && until != null) {
          final pending = DateTime.now().isBefore(until) &&
              (position.inMilliseconds - anchor).abs() > 2500;
          if (pending) return;
          _seekAnchorMs = null;
          _seekAnchorUntil = null;
        }
        if (_duration > Duration.zero && position >= _duration) return;
        setState(() => _position = position);
        _maybeAutoSkip();
      }),
      _player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      }),
      _player.stream.buffer.listen((buffer) {
        if (!mounted) return;
        setState(() => _buffered = buffer);
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
        if (playing) {
          _scheduleHide();
        } else if (!_seeking && !_scrubbing) {
          _hideTimer?.cancel();
          setState(() => _showControls = true);
        }
      }),
      _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        setState(() => _buffering = buffering);
      }),
      _player.stream.error.listen((message) {
        if (!mounted || message.isEmpty) return;
        setState(() => _error = message);
      }),
    ]);
    VolumeController.instance.showSystemUI = false;
    _fileId = widget.fileId;
    _fileName = widget.fileName;
    _posterUrl = widget.posterUrl;
    _prepareMeta = widget.prepareMeta;
    _catalog = widget.catalog;
    _playlistId = widget.playlistId;
    _playlistWorkId = widget.catalog?.workId;
    _playlistSeason = widget.catalog?.seasonNumber;
    _playlistEpisode = widget.catalog?.episodeNumber;
    if (_playlistId != null) unawaited(_loadPlaylistQueue());
    unawaited(_loadSkipMode());
    final seed = widget.resumePositionMs;
    if (seed != null && seed > 0) {
      _pendingResume = Duration(milliseconds: seed);
    }
    _sidePanelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _prepareFade = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 420),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _prepareAndOpen();
    if (_showCatalog) _ensureCatalogLoaded();
    _loadBrightness();
    _loadVolume();
  }

  void _update(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  void _showSeekResult(Duration target) {
    _seekAnchorMs = target.inMilliseconds;
    _seekAnchorUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    _update(() {
      _seeking = false;
      _position = target;
    });
  }

  Future<void> _commitSliderSeek(int targetMs) async {
    if (_sliderDragMs != targetMs) return;
    _sliderDragMs = null;
    final generation = ++_sliderCommit;
    _noteManualSeek(targetMs);
    try {
      await _player.seek(Duration(milliseconds: targetMs));
    } catch (_) {}
    if (!mounted || generation != _sliderCommit || _sliderDragMs != null) return;
    _showSeekResult(Duration(milliseconds: targetMs));
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_reportProgress(force: true));
    _hideTimer?.cancel();
    _skipRepeat?.cancel();
    _sidePanelAnim.dispose();
    _prepareFade.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
      (_) {},
    );
    _openCount = (_openCount - 1).clamp(0, 1 << 20);
    if (_ownsOrientation) _stopOrientationFollow();
    if (_openCount == 0) {
      VolumeController.instance.showSystemUI = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  String get _chromeTitle {
    final scraped = _prepareMeta?.chromeTitle?.trim();
    if (scraped != null && scraped.isNotEmpty) return scraped;
    return _fileName;
  }

  Widget _buildTopBar() {
    final landscape = _isLandscape;
    final hideMore = landscape && _sidePanelChromeActive;
    return Row(
      children: [
        IconButton(
          onPressed: _exitPlayer,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            _chromeTitle,
            style: const TextStyle(fontSize: 16, height: 1.25),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_playlistMode || _showCatalog)
          TextButton(
            onPressed: _openCatalogPanel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(_playlistMode ? '播放列表' : '选集'),
          ),
        const _PhoneClock(),
        if (hideMore)
          const SizedBox(width: 16)
        else if (landscape)
          IconButton(
            tooltip: '更多',
            onPressed: _openSidePanel,
            icon: const Icon(Icons.more_vert),
          )
        else
          PopupMenuButton<_TopBarAction>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF2A2A2A),
            onSelected: (action) {
              switch (action) {
                case _TopBarAction.orientation:
                  _toggleOrientation();
                case _TopBarAction.audio:
                  _showAudioTracks();
                case _TopBarAction.subtitle:
                  _showSubtitles();
                case _TopBarAction.rate:
                  _showPlaybackRate();
                case _TopBarAction.skip:
                  _showSkipSettings();
                case _TopBarAction.decode:
                  _showHardwareDecode();
                case _TopBarAction.info:
                  _showMediaInfo();
              }
            },
            itemBuilder: (context) {
              Widget item(IconData icon, String label) {
                return Row(
                  children: [
                    Icon(icon, size: 22, color: Colors.white70),
                    const SizedBox(width: 12),
                    Text(label, style: const TextStyle(color: Colors.white)),
                  ],
                );
              }

              return [
                PopupMenuItem(
                  value: _TopBarAction.orientation,
                  child: item(
                    Icons.stay_current_landscape,
                    '横屏',
                  ),
                ),
                PopupMenuItem(
                  value: _TopBarAction.audio,
                  child: item(Icons.audiotrack, '音轨'),
                ),
                PopupMenuItem(
                  value: _TopBarAction.subtitle,
                  child: item(Icons.subtitles_outlined, '字幕'),
                ),
                PopupMenuItem(
                  value: _TopBarAction.rate,
                  child: item(Icons.speed, '倍速 ${_rateLabel(_playbackRate)}'),
                ),
                PopupMenuItem(
                  value: _TopBarAction.skip,
                  child: item(Icons.skip_next, '片头片尾 · ${skipModeLabel(_skipMode)}'),
                ),
                PopupMenuItem(
                  value: _TopBarAction.decode,
                  child: item(
                    _hardwareDecode ? Icons.memory : Icons.memory_outlined,
                    _hardwareDecode ? '硬解' : '软解',
                  ),
                ),
                PopupMenuItem(
                  value: _TopBarAction.info,
                  child: item(Icons.info_outline, 'INFO'),
                ),
              ];
            },
          ),
      ],
    );
  }

  Widget _buildPlayerStage({required Duration shown}) {
    final maxMillis = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final played = shown.inMilliseconds.clamp(0, maxMillis.round()).toDouble();
    final cached = _buffered.inMilliseconds.clamp(0, maxMillis.round()).toDouble();
    final buffered = cached < played ? played : cached;
    return Stack(
      children: [
        Positioned.fill(
          child: Video(
            controller: _controller,
            controls: NoVideoControls,
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 72),
              style: TextStyle(
                height: 1.3,
                fontSize: 22,
                color: Colors.white,
                backgroundColor: Color(0x99000000),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
            onDoubleTap: _togglePlay,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanCancel,
            onLongPressStart: _startBoost,
            onLongPressMoveUpdate: _updateBoost,
            onLongPressEnd: (_) => _endBoost(),
            onLongPressCancel: _endBoost,
          ),
        ),
        if (_buffering && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ),
        if (_showLevel)
          Align(
            alignment: const Alignment(0, -0.72),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xCC000000),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  _levelIsBrightness
                      ? '亮度 ${(_brightness * 100).round()}%'
                      : '音量 ${(_volume * 100).round()}%',
                ),
              ),
            ),
          ),
        if (_scrubbing)
          Align(
            alignment: const Alignment(0, -0.72),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xCC000000),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  '${_seekPreview < _seekOrigin ? '快退 ' : '快进 '}'
                  '${formatDuration((_seekPreview - _seekOrigin).abs())}'
                  '  ·  ${formatDuration(_seekPreview)}',
                ),
              ),
            ),
          ),
        Positioned(
          key: const ValueKey('player-skip'),
          top: 0,
          bottom: 0,
          right: 18 + _stageEdgePadding(top: false, bottom: false).right,
          child: Center(child: _buildSkipButton()),
        ),
        if (_boosting)
          Align(
            alignment: const Alignment(0, -0.72),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xCC000000),
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text('${_boostRate.toStringAsFixed(1)}×'),
              ),
            ),
          ),
        Positioned(
          key: const ValueKey('player-top'),
          top: 0,
          left: 0,
          right: 0,
          child: _animatedControls(
            fromTop: true,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: _stageEdgePadding(bottom: false),
                child: _buildTopBar(),
              ),
            ),
          ),
        ),
        Positioned(
          key: const ValueKey('player-bottom'),
          left: 0,
          right: 0,
          bottom: 0,
          child: _animatedControls(
            fromTop: false,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: Padding(
                padding: _stageEdgePadding(top: false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final compact = Curves.easeOutCubic.transform(
                          _sidePanelAnim.value,
                        );
                        final skipSize = 35 - 7 * compact;
                        final stepSize = 42 - 10 * compact;
                        final playSize = 56 - 14 * compact;
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _HoldSeekButton(
                                tooltip: '后退5秒',
                                icon: Icons.replay_5,
                                size: skipSize,
                                onTap: () => _skipBy(-5),
                                onHoldStart: () => _startSkipRepeat(-5),
                                onHoldEnd: _stopSkipRepeat,
                              ),
                              IconButton(
                                tooltip: '上一个',
                                onPressed: _playPrevious,
                                icon: Icon(Icons.skip_previous_rounded, size: stepSize),
                              ),
                              IconButton(
                                onPressed: _togglePlay,
                                icon: Icon(
                                  _playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: playSize,
                                ),
                              ),
                              IconButton(
                                tooltip: '下一个',
                                onPressed: _playNext,
                                icon: Icon(Icons.skip_next_rounded, size: stepSize),
                              ),
                              _HoldSeekButton(
                                tooltip: '前进5秒',
                                icon: Icons.forward_5,
                                size: skipSize,
                                onTap: () => _skipBy(5),
                                onHoldStart: () => _startSkipRepeat(5),
                                onHoldEnd: _stopSkipRepeat,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Text(formatDuration(shown)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                inactiveTrackColor: const Color(0x33FFFFFF),
                                secondaryActiveTrackColor: const Color(0x99FFFFFF),
                              ),
                              child: Slider(
                                key: const ValueKey('player-seek'),
                                value: played,
                                secondaryTrackValue: buffered,
                                max: maxMillis,
                                onChanged: _duration == Duration.zero
                                    ? null
                                    : (next) {
                                        final ms = next.round();
                                        _sliderDragMs = ms;
                                        _noteManualSeek(ms);
                                        setState(() {
                                          _seeking = true;
                                          _position = Duration(milliseconds: ms);
                                        });
                                      },
                                onChangeEnd: (next) {
                                  final ms = next.round();
                                  _sliderDragMs = ms;
                                  unawaited(_commitSliderSeek(ms));
                                },
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _showRemaining = !_showRemaining),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              child: Text(_endTimeLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _endTimeLabel {
    if (!_showRemaining || _duration <= Duration.zero) {
      return formatDuration(_duration);
    }
    final shown = _scrubbing ? _seekPreview : _position;
    var left = _duration - shown;
    if (left.isNegative) left = Duration.zero;
    return '-${formatDuration(left)}';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _scrubbing ? _seekPreview : _position;
    if (!_isLandscape && (_sidePanelOpen || _sidePanelAnim.value > 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLandscape) _closeSidePanel(animate: false);
      });
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_handleSidePanelPop()) return;
        _exitPlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panelW = _sidePanelWidth(constraints.maxWidth);
            final t = Curves.easeOutCubic.transform(_sidePanelAnim.value);
            final showPanel = _sidePanel != null || t > 0;
            final stage = _buildPlayerStage(shown: shown);
            final prepareLayer = _prepareError != null
                ? _buildPrepareStage()
                : (_preparing || _prepareFade.value > 0)
                    ? IgnorePointer(
                        ignoring: _prepareFade.value < 0.05,
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _prepareFade,
                            curve: Curves.easeOutCubic,
                          ),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.97, end: 1).animate(
                              CurvedAnimation(
                                parent: _prepareFade,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                            child: _buildPrepareStage(),
                          ),
                        ),
                      )
                    : null;

            Widget videoPane() {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (_prepareError == null &&
                      (!_preparing || _prepareFade.value < 1 || showPanel))
                    stage,
                  ?prepareLayer,
                ],
              );
            }

            if (!showPanel) return videoPane();

            return Row(
              children: [
                Expanded(child: videoPane()),
                SizedBox(
                  width: panelW * t.clamp(0.0, 1.0),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: panelW,
                      maxWidth: panelW,
                      child: SizedBox(
                        width: panelW,
                        height: constraints.maxHeight,
                        child: _sidePanel == null
                            ? const SizedBox.shrink()
                            : _buildSidePanel(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 按钮始终留在树上，只切换透明度。拖进片头或片尾时如果把它插进或移出 Stack，
  /// 进度条会被拆掉，松手跳转丢失，滑块也就停在这段的边界上。
  Widget _buildSkipButton() {
    final offer = _sliderDragMs != null ? null : _skipOffer;
    final visible = offer != null && _prepareError == null;
    return IgnorePointer(
      ignoring: !visible,
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: const Color(0x5C0A0C10),
            foregroundColor: const Color(0xC7F2EFE8),
            overlayColor: const Color(0x14FFFFFF),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const StadiumBorder(
              side: BorderSide(color: Color(0x33FFFFFF)),
            ),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.2),
          ),
          onPressed: offer == null
              ? null
              : () {
                  _skipApplied.add(offer.key);
                  _update(() {});
                  unawaited(_performSkip(offer));
                },
          child: Text(offer?.label ?? ''),
        ),
      ),
    );
  }

  Widget _buildPrepareStage() {
    final failed = _prepareError != null;
    final meta = _prepareMeta;
    final title = meta?.title?.trim().isNotEmpty == true
        ? meta!.title!.trim()
        : _fileName;
    final subtitle = meta?.subtitle?.trim();
    final metaLine = meta?.metaLine;
    final genresLine = meta?.genresLine;
    final ratings = meta?.ratings ?? const [];
    final size = MediaQuery.sizeOf(context);
    final posterH = (size.height * 0.42).clamp(140.0, 220.0);
    final posterUrl = _posterUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (posterUrl != null && posterUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
              child: Transform.scale(
                scale: 1.18,
                alignment: Alignment.centerRight,
                child: PosterImage(url: posterUrl, fallback: title),
              ),
            ),
          )
        else
          const ColoredBox(color: FolioColors.bgDeep),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xB3000000),
                Color(0x99000000),
                Color(0xCC000000),
              ],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: _exitPlayer,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: posterH,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: PosterImage(
                              url: posterUrl,
                              fallback: title,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (size.width - posterH * 2 / 3 - 84)
                              .clamp(160.0, 420.0),
                        ),
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: folioDisplay(size: 22, color: FolioColors.ink),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color: FolioColors.ink.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
                              if (metaLine != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  metaLine,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: FolioColors.ink.withValues(alpha: 0.82),
                                  ),
                                ),
                              ],
                              if (genresLine != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  genresLine,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: FolioColors.ink.withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                              if (ratings.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var i = 0; i < ratings.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 6),
                                      RatingChip(rating: ratings[i]),
                                    ],
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              if (failed)
                                Text(
                                  _prepareError!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: FolioColors.danger,
                                  ),
                                )
                              else
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _PrepareLiveDot(),
                                    SizedBox(width: 8),
                                    Text(
                                      '播放准备中',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: FolioColors.copper,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrepareLiveDot extends StatefulWidget {
  const _PrepareLiveDot();

  @override
  State<_PrepareLiveDot> createState() => _PrepareLiveDotState();
}

class _PrepareLiveDotState extends State<_PrepareLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: FolioColors.copper,
            boxShadow: [
              BoxShadow(
                color: FolioColors.copper.withValues(alpha: 0.45 * (1 - t)),
                blurRadius: 0,
                spreadRadius: 8 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoldSeekButton extends StatelessWidget {
  const _HoldSeekButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.size = 35,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: (_) => onHoldStart(),
        onLongPressEnd: (_) => onHoldEnd(),
        onLongPressCancel: onHoldEnd,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: size),
        ),
      ),
    );
  }
}

class _PhoneClock extends StatefulWidget {
  const _PhoneClock();

  @override
  State<_PhoneClock> createState() => _PhoneClockState();
}

class _PhoneClockState extends State<_PhoneClock> {
  Timer? _timer;
  final Battery _battery = Battery();
  int? _level;

  @override
  void initState() {
    super.initState();
    _readBattery();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {});
        _readBattery();
      }
    });
  }

  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted || level == _level) return;
      setState(() => _level = level);
    } catch (_) {}
  }

  IconData _batteryIcon(int level) {
    if (level >= 90) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 30) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final level = _level;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$hour:$minute',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (level != null) ...[
            const SizedBox(width: 8),
            Icon(_batteryIcon(level), size: 18),
            const SizedBox(width: 2),
            Text(
              '$level%',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
