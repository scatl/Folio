part of '../player_page.dart';

extension _PlayerGestures on _PlayerPageState {
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing && !_boosting) {
        _update(() => _showControls = false);
      }
    });
  }

  Future<void> _toggleOrientation() async {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape) {
      _buttonHold = _DeviceHold.portrait;
      _requestedOrientation = DeviceOrientation.portraitUp;
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      _buttonHold = null;
      final next = _stableHold == _DeviceHold.landscapeRight
          ? DeviceOrientation.landscapeRight
          : DeviceOrientation.landscapeLeft;
      _requestedOrientation = next;
      await SystemChrome.setPreferredOrientations([next]);
    }
    if (!mounted) return;
    _update(() => _showControls = true);
    _scheduleHide();
  }

  void _toggleControls() {
    final show = !_showControls;
    _update(() => _showControls = show);
    if (show && _playing) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _togglePlay() async {
    _update(() => _showControls = true);
    await _player.playOrPause();
    if (_playing) _scheduleHide();
  }

  void _onSeekStart(DragStartDetails details) {
    if (_duration == Duration.zero || _boosting) return;
    _hideTimer?.cancel();
    _wasPlaying = _player.state.playing;
    _update(() {
      _scrubbing = true;
      _seeking = true;
      _seekOrigin = _position;
      _seekPreview = _position;
    });
    if (_wasPlaying) _player.pause();
  }

  void _onSeekUpdateDx(double dx) {
    if (!_scrubbing) return;
    final width = _gestureWidth;
    if (width <= 0) return;
    const span = Duration(seconds: 90);
    final deltaMs = dx / width * span.inMilliseconds;
    final next = (_seekPreview.inMilliseconds + deltaMs).round().clamp(
      0,
      _duration.inMilliseconds,
    );
    final target = Duration(milliseconds: next);
    _update(() => _seekPreview = target);
    _scheduleSeek(target);
  }

  void _onPanStart(DragStartDetails details) {
    if (_boosting) return;
    _panOrigin = details.localPosition;
    _dragAxis = _DragAxis.undecided;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_boosting || _panOrigin == null) return;
    const slop = 18.0;
    if (_dragAxis == _DragAxis.undecided) {
      final total = details.localPosition - _panOrigin!;
      if (total.dx.abs() < slop && total.dy.abs() < slop) return;
      if (total.dx.abs() >= total.dy.abs()) {
        _dragAxis = _DragAxis.horizontal;
        _onSeekStart(DragStartDetails(globalPosition: details.globalPosition));
        _onSeekUpdateDx(total.dx);
      } else {
        _dragAxis = _DragAxis.vertical;
        _beginLevel(_panOrigin!.dx);
        _applyLevel(total.dy);
      }
      return;
    }
    if (_dragAxis == _DragAxis.horizontal) {
      _onSeekUpdateDx(details.delta.dx);
    } else {
      _applyLevel(details.delta.dy);
    }
  }

  void _beginLevel(double x) {
    final width = MediaQuery.sizeOf(context).width;
    _levelIsBrightness = x < width / 2;
    _update(() => _showLevel = true);
  }

  void _applyLevel(double dy) {
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final delta = -dy / height;
    if (_levelIsBrightness) {
      _brightness = (_brightness + delta).clamp(0.02, 1.0);
      ScreenBrightness.instance
          .setApplicationScreenBrightness(_brightness)
          .catchError((_) {});
    } else {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_volume);
    }
    if (mounted) _update(() => _showLevel = true);
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final axis = _dragAxis;
    _dragAxis = _DragAxis.undecided;
    _panOrigin = null;
    if (axis == _DragAxis.horizontal) {
      await _onSeekEnd(details);
    } else if (axis == _DragAxis.vertical && mounted) {
      _update(() => _showLevel = false);
    }
  }

  Future<void> _onPanCancel() async {
    final axis = _dragAxis;
    _dragAxis = _DragAxis.undecided;
    _panOrigin = null;
    if (axis == _DragAxis.horizontal) {
      await _onSeekCancel();
    } else if (axis == _DragAxis.vertical && mounted) {
      _update(() => _showLevel = false);
    }
  }

  Future<void> _scheduleSeek(Duration target) {
    _latestSeek = target;
    _seekDone ??= Completer<void>();
    final done = _seekDone!.future;
    if (!_seekRunning) {
      _seekRunning = true;
      _drainSeeks();
    }
    return done;
  }

  Future<void> _drainSeeks() async {
    var again = false;
    try {
      while (_latestSeek != null) {
        final target = _latestSeek!;
        _latestSeek = null;
        await _player.seek(target);
      }
    } catch (_) {
    } finally {
      _seekRunning = false;
      again = _latestSeek != null;
      if (again) _seekRunning = true;
    }
    if (again) {
      await _drainSeeks();
      return;
    }
    final done = _seekDone;
    _seekDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<void> _onSeekEnd(DragEndDetails details) async {
    if (!_scrubbing) return;
    final target = _seekPreview;
    final resume = _wasPlaying;
    _noteManualSeek(target.inMilliseconds);
    _update(() => _scrubbing = false);
    try {
      await _scheduleSeek(target);
      if (resume && mounted) await _player.play();
    } catch (_) {}
    if (!mounted) return;
    _showSeekResult(target);
    if (resume) _scheduleHide();
  }

  Future<void> _onSeekCancel() async {
    if (!_scrubbing) return;
    final origin = _seekOrigin;
    final resume = _wasPlaying;
    _noteManualSeek(origin.inMilliseconds);
    _update(() {
      _scrubbing = false;
      _seekPreview = origin;
    });
    try {
      await _scheduleSeek(origin);
      if (resume && mounted) await _player.play();
    } catch (_) {}
    if (!mounted) return;
    _showSeekResult(origin);
    if (resume) _scheduleHide();
  }

  double _longPressRate() {
    if (_playbackRate < 2) return 2;
    if (_playbackRate < 3) return 3;
    return 4;
  }

  Future<void> _startBoost(LongPressStartDetails details) async {
    HapticFeedback.mediumImpact();
    _boostOriginY = details.localPosition.dy;
    _boostAnchor = _longPressRate();
    _boostRate = _boostAnchor;
    _update(() => _boosting = true);
    await _player.setRate(_boostAnchor);
    if (!_playing) await _player.play();
  }

  Future<void> _updateBoost(LongPressMoveUpdateDetails details) async {
    if (!_boosting) return;
    final height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final y = details.localPosition.dy.clamp(0.0, height);
    final origin = _boostOriginY.clamp(0.0, height);
    final double raw;
    if (y <= origin) {
      final span = (origin <= 1 ? 1.0 : origin) * 0.65;
      raw = _boostAnchor + (origin - y) / span * (4 - _boostAnchor);
    } else {
      final span = (height - origin <= 1 ? 1.0 : height - origin) * 0.65;
      raw = _boostAnchor - (y - origin) / span * (_boostAnchor - 0.5);
    }
    final rate = ((raw * 10).round() / 10).clamp(0.5, 4.0);
    if (rate == _boostRate) return;
    _boostRate = rate;
    if (mounted) _update(() {});
    await _player.setRate(_boostRate);
  }

  Future<void> _skipBy(int seconds) async {
    if (_duration == Duration.zero) return;
    final nextMs = (_position.inMilliseconds + seconds * 1000).clamp(
      0,
      _duration.inMilliseconds,
    );
    final target = Duration(milliseconds: nextMs);
    _noteManualSeek(nextMs);
    _update(() {
      _seeking = true;
      _position = target;
    });
    try {
      await _player.seek(target);
    } catch (_) {}
    if (!mounted || _skipRepeat != null) return;
    _showSeekResult(target);
  }

  void _startSkipRepeat(int seconds) {
    _skipBy(seconds);
    _skipRepeat?.cancel();
    _skipRepeat = Timer.periodic(const Duration(milliseconds: 280), (_) {
      _skipBy(seconds);
    });
  }

  void _stopSkipRepeat() {
    _skipRepeat?.cancel();
    _skipRepeat = null;
    if (mounted) _update(() => _seeking = false);
  }

  Future<void> _endBoost() async {
    if (!_boosting) return;
    _update(() => _boosting = false);
    await _player.setRate(_playbackRate);
  }

}
