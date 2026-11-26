part of '../player_page.dart';

extension _PlayerSheets on _PlayerPageState {
  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 设置列表统一样式（自绘行，避免 ListTile 额外左缩进）。
  Widget _settingsTile({
    required String title,
    String? subtitle,
    Widget? leading,
    required bool selected,
    required VoidCallback onTap,
    /// 为 true 时标题完整换行显示（如字幕文件名）。
    bool wrapTitle = false,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final titleColor = selected ? accent : FolioColors.ink;
    final subtitleColor =
        selected ? accent.withValues(alpha: 0.72) : FolioColors.inkMuted;
    final hasSubtitle = subtitle != null && subtitle.isNotEmpty;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: hasSubtitle || wrapTitle ? 56 : 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              crossAxisAlignment: wrapTitle
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[
                  Padding(
                    padding: EdgeInsets.only(top: wrapTitle ? 1 : 0),
                    child: IconTheme(
                      data: IconThemeData(
                        size: 22,
                        color: selected ? accent : FolioColors.inkMuted,
                      ),
                      child: leading,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: wrapTitle ? null : 1,
                        softWrap: wrapTitle,
                        overflow: wrapTitle
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: titleColor,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: EdgeInsets.only(top: wrapTitle ? 1 : 0),
                    child: Icon(Icons.check, size: 20, color: accent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<T?> _showSheet<T>(
    Widget Function(BuildContext context) builder, {
    /// 相对屏高的最大高度；sheet 本身仍按内容收缩。
    double maxHeightFactor = 0.75,
  }) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    return showFolioSheet<T>(
      context: context,
      showDragHandle: true,
      maxHeightFactor: maxHeightFactor,
      constraints: landscape
          ? BoxConstraints(maxWidth: size.shortestSide)
          : null,
      builder: (context) => MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeRight: true,
        child: SafeArea(
          left: false,
          right: false,
          child: builder(context),
        ),
      ),
    );
  }

  Widget _animatedControls({required bool fromTop, required Widget child}) {
    return IgnorePointer(
      ignoring: !_showControls,
      child: AnimatedSlide(
        offset: _showControls ? Offset.zero : Offset(0, fromTop ? -1 : 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: child,
        ),
      ),
    );
  }
}
