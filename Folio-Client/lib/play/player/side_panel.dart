part of '../player_page.dart';

/// 分屏会话页。设置菜单 / 子设置 / 选集共用同一宿主。
enum _SplitKind { menu, audio, subtitle, rate, skip, decode, info, catalog, playlist }

extension _PlayerSidePanel on _PlayerPageState {
  bool get _isLandscape =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  bool get _sidePanelOpen => _sidePanel != null;

  /// 横屏用侧栏；竖屏仍用 bottom sheet。
  bool get _embedSettingsInSidePanel => _isLandscape;

  double _sidePanelWidth(double totalWidth) =>
      (totalWidth * 0.38).clamp(280.0, 360.0);

  double get _gestureWidth {
    final size = MediaQuery.sizeOf(context);
    if (!_isLandscape) return size.width;
    final t = Curves.easeOutCubic.transform(_sidePanelAnim.value);
    if (t <= 0) return size.width;
    return size.width - _sidePanelWidth(size.width) * t;
  }

  /// 画面自己的安全区。分屏从右侧盖上来之后，屏幕右缘的刘海不再算进画面。
  EdgeInsets _stageEdgePadding({bool top = true, bool bottom = true}) {
    final inset = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final t = Curves.easeOutCubic.transform(_sidePanelAnim.value);
    final covered = _isLandscape ? _sidePanelWidth(size.width) * t : 0.0;
    final right = (inset.right - covered).clamp(0.0, inset.right);
    return EdgeInsets.only(
      left: inset.left,
      right: right,
      top: top ? inset.top : 0,
      bottom: bottom ? inset.bottom : 0,
    );
  }

  /// 分屏打开中或动画未收完时，顶栏隐藏「更多」。
  bool get _sidePanelChromeActive =>
      _sidePanel != null || _sidePanelAnim.value > 0;

  bool _isSplitRoot(_SplitKind kind) =>
      kind == _SplitKind.menu || kind == _SplitKind.catalog || kind == _SplitKind.playlist;

  /// 打开分屏根页（设置菜单或选集）。
  void _openSplit(_SplitKind kind) {
    _sidePanelPush = true;
    _update(() {
      _sidePanel = kind;
      _showControls = true;
    });
    if (_sidePanelAnim.value == 0) {
      _sidePanelAnim.forward();
    }
    _scheduleHide();
  }

  void _openSidePanel() => _openSplit(_SplitKind.menu);

  void _closeSidePanel({bool animate = true}) {
    if (_sidePanel == null && _sidePanelAnim.value == 0) return;
    if (!animate) {
      _sidePanelAnim.value = 0;
      _update(() => _sidePanel = null);
      return;
    }
    _sidePanelAnim.reverse().whenComplete(() {
      if (!mounted) return;
      if (_sidePanelAnim.value == 0) {
        _update(() => _sidePanel = null);
      }
    });
  }

  /// 在已打开的分屏内推进子页（音轨等）。
  void _pushSplitPage(_SplitKind kind) {
    _sidePanelPush = true;
    _update(() => _sidePanel = kind);
  }

  /// 兼容旧调用名。
  void _openSidePanelPage(_SplitKind kind) => _pushSplitPage(kind);

  void _sidePanelBack() {
    if (_sidePanel == null || _isSplitRoot(_sidePanel!)) {
      _closeSidePanel();
      return;
    }
    _sidePanelPush = false;
    _update(() => _sidePanel = _SplitKind.menu);
  }

  bool _handleSidePanelPop() {
    if (_sidePanel == null && _sidePanelAnim.value == 0) return false;
    if (_sidePanel == null || _isSplitRoot(_sidePanel!)) {
      _closeSidePanel();
    } else {
      _sidePanelBack();
    }
    return true;
  }

  String _sidePanelTitle(_SplitKind kind) => switch (kind) {
        _SplitKind.menu => '设置',
        _SplitKind.audio => '音轨',
        _SplitKind.subtitle => '字幕',
        _SplitKind.rate => '倍速',
        _SplitKind.skip => '跳过片头片尾',
        _SplitKind.decode => '解码',
        _SplitKind.info => '媒体信息',
        _SplitKind.catalog => '选集',
        _SplitKind.playlist => '播放列表',
      };

  Widget _buildSidePanel() {
    final kind = _sidePanel!;
    final scheme = Theme.of(context).colorScheme;
    final root = _isSplitRoot(kind);
    return Material(
      color: const Color(0xFF161A22),
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  if (!root)
                    IconButton(
                      tooltip: '返回',
                      onPressed: _sidePanelBack,
                      icon: const Icon(Icons.arrow_back),
                    )
                  else
                    const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sidePanelTitle(kind),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                  if (kind == _SplitKind.catalog &&
                      _catalog?.isSeries == true) ...[
                    IconButton(
                      tooltip: _catalogGridMode ? '列表' : '宫格',
                      onPressed: () =>
                          _update(() => _catalogGridMode = !_catalogGridMode),
                      icon: Icon(
                        _catalogGridMode
                            ? Icons.view_list_rounded
                            : Icons.grid_view_rounded,
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _closeSidePanel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.08)),
            Expanded(child: _buildSidePanelBody(kind)),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanelBody(_SplitKind kind) {
    final push = _sidePanelPush;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(kind);
          final begin = incoming
              ? Offset(push ? 1.0 : -1.0, 0)
              : Offset(push ? -0.28 : 1.0, 0);
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
              animation,
            ),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0, 0.85),
              ),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(kind),
          child: switch (kind) {
            _SplitKind.menu => _buildSideMenu(),
            _SplitKind.audio => _buildAudioPanel(),
            _SplitKind.subtitle => _buildSubtitlePanel(),
            _SplitKind.rate => _buildRatePanel(),
            _SplitKind.skip => _buildSkipPanel(),
            _SplitKind.decode => _buildDecodePanel(),
            _SplitKind.info => _buildInfoPanel(),
            _SplitKind.catalog => _buildCatalogPanel(),
            _SplitKind.playlist => _buildPlaylistPanel(),
          },
        ),
      ),
    );
  }

  Widget _buildSideMenu() {
    final landscape = _isLandscape;
    final scheme = Theme.of(context).colorScheme;
    final items = <(IconData, String, VoidCallback)>[
      (
        landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape,
        landscape ? '竖屏' : '横屏',
        () async {
          _closeSidePanel();
          await _toggleOrientation();
        },
      ),
      (Icons.audiotrack, '音轨', _showAudioTracks),
      (Icons.subtitles_outlined, '字幕', _showSubtitles),
      (Icons.speed, '倍速\n${_rateLabel(_playbackRate)}', _showPlaybackRate),
      (Icons.skip_next, '片头片尾\n${skipModeLabel(_skipMode)}', _showSkipSettings),
      (
        _PlayerPageState._hardwareDecode ? Icons.memory : Icons.memory_outlined,
        _PlayerPageState._hardwareDecode ? '硬解' : '软解',
        _showHardwareDecode,
      ),
      (Icons.info_outline, 'INFO', _showMediaInfo),
    ];

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 96,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (icon, label, onTap) = items[index];
        return Material(
          color: scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: scheme.onSurface.withValues(alpha: 0.78)),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        color: scheme.onSurface.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
