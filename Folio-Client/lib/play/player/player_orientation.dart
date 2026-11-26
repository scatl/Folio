part of '../player_page.dart';

enum _DeviceHold { landscapeLeft, landscapeRight, portrait }

const _orientationChannel = MethodChannel('com.scatl.folio/orientation');
const _gravityChannel = EventChannel('com.scatl.folio/orientation_gravity');

extension _PlayerOrientation on _PlayerPageState {
  void _startOrientationFollow() {
    if (!Platform.isAndroid || _orientationListening) return;
    _orientationListening = true;
    _gravitySub = _gravityChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! List || event.length < 2) return;
        final x = (event[0] as num).toDouble();
        final y = (event[1] as num).toDouble();
        _onGravity(x, y);
      },
      onError: (_) {},
    );
  }

  void _stopOrientationFollow() {
    _orientationListening = false;
    _orientationHoldTimer?.cancel();
    _orientationHoldTimer = null;
    _gravitySub?.cancel();
    _gravitySub = null;
    _pendingHold = null;
    _buttonHold = null;
  }

  /// 机身明确横过来时才认定方向。竖着拿或放平不产生方向，避免锁定时在横竖屏之间跳动。
  void _onGravity(double x, double y) {
    if (!_orientationListening || _leaving) return;
    const minAxis = 6.5;
    _DeviceHold? hold;
    if (x.abs() >= minAxis && x.abs() > y.abs()) {
      // 机顶朝左时加速度 x 为正，对应 landscapeLeft。
      hold = x > 0 ? _DeviceHold.landscapeLeft : _DeviceHold.landscapeRight;
    } else if (y > minAxis && y.abs() > x.abs()) {
      hold = _DeviceHold.portrait;
    }
    if (hold == null || hold == _pendingHold) return;
    final settled = hold;
    _pendingHold = settled;
    _orientationHoldTimer?.cancel();
    _orientationHoldTimer = Timer(const Duration(milliseconds: 180), () {
      if (!_orientationListening || _pendingHold != settled) return;
      _stableHold = settled;
      unawaited(_applyHeld(settled));
    });
  }

  Future<void> _applyHeld(_DeviceHold hold) async {
    if (hold == _DeviceHold.portrait) {
      if (_buttonHold == _DeviceHold.portrait) _buttonHold = null;
      return;
    }
    if (_buttonHold != null) return;
    final locked = await _rotationLocked();
    if (!_orientationListening || !mounted || _leaving) return;
    if (_buttonHold != null) return;
    if (locked && MediaQuery.orientationOf(context) != Orientation.landscape) {
      _pendingHold = null;
      return;
    }
    final next = hold == _DeviceHold.landscapeRight
        ? DeviceOrientation.landscapeRight
        : DeviceOrientation.landscapeLeft;
    if (next == _requestedOrientation) return;
    _requestedOrientation = next;
    await SystemChrome.setPreferredOrientations([next]);
  }

  Future<bool> _rotationLocked() async {
    try {
      return await _orientationChannel.invokeMethod<bool>('rotationLocked') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
