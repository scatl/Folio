import 'package:easy_refresh/easy_refresh.dart';
import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';

import 'paged_refresh_state.dart';

/// 外部触发刷新。
class PagedRefreshController {
  Future<void> Function()? _callRefresh;

  void _attach(Future<void> Function() callRefresh) {
    _callRefresh = callRefresh;
  }

  void _detach() {
    _callRefresh = null;
  }

  Future<void> callRefresh() async {
    await _callRefresh?.call();
  }
}

/// 分页列表。行为对齐 qBPanel 的 PagedRefreshList：
/// 首次在中间转圈，下拉刷新，距底部 [triggerLoadMoreOffset] 条时预加载。
/// 刷新控制器跟这个列表走，页面卸掉后指示器不会留到别的页面。
class PagedRefreshList<T> extends StatefulWidget {
  const PagedRefreshList({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.itemBuilder,
    this.onLoadMore,
    this.controller,
    this.scrollController,
    this.onRetry,
    this.enableRefresh = true,
    this.enableLoadMore = true,
    this.triggerLoadMoreOffset = 5,
    this.padding = EdgeInsets.zero,
    this.header,
    this.emptyTitle,
    this.emptySubtitle,
    this.errorActionText,
    this.itemExtent,
    this.separatorBuilder,
    this.gridDelegate,
    this.gridCrossAxisCount,
    this.gridSpacing = 8,
  });

  final PagedRefreshState<T> state;
  final PagedRefreshController? controller;
  final ScrollController? scrollController;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onLoadMore;
  final void Function(PagedRetryType type)? onRetry;
  final bool enableRefresh;
  final bool enableLoadMore;
  final int triggerLoadMoreOffset;
  final EdgeInsetsGeometry padding;
  /// 随列表一起滚动的顶部内容（如资料库统计行）。
  final Widget? header;
  final String? emptyTitle;
  final String? emptySubtitle;
  final String? errorActionText;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final double? itemExtent;
  final Widget Function(BuildContext context, int index)? separatorBuilder;
  final SliverGridDelegate? gridDelegate;
  final int? gridCrossAxisCount;
  final double gridSpacing;

  @override
  State<PagedRefreshList<T>> createState() => PagedRefreshListState<T>();
}

class PagedRefreshListState<T> extends State<PagedRefreshList<T>> {
  final _refresh = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );

  int _preloadedAtSize = 0;
  bool _retrying = false;

  PagedRefreshState<T> get _state => widget.state;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_handleRefresh);
  }

  @override
  void didUpdateWidget(covariant PagedRefreshList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(_handleRefresh);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    await widget.onRefresh();
    if (!mounted) return;
    _preloadedAtSize = 0;
    setState(() {});
    _refresh
      ..finishRefresh(_state.error && _state.isEmpty ? IndicatorResult.fail : IndicatorResult.success)
      ..resetFooter();
    if (_state.hasMore) {
      _refresh.finishLoad(IndicatorResult.success);
    }
  }

  Future<void> _handleLoad() async {
    if (!_state.hasMore) {
      _refresh.finishLoad(IndicatorResult.success);
      return;
    }
    if (_state.loadingMore || _state.refreshing || _state.initLoading) {
      _refresh.finishLoad(IndicatorResult.success);
      return;
    }
    await widget.onLoadMore?.call();
    if (!mounted) return;
    setState(() {});
    if (_state.error) {
      _refresh.finishLoad(IndicatorResult.fail);
      return;
    }
    _refresh.finishLoad(IndicatorResult.success);
  }

  void _maybePreload(int index) {
    if (!widget.enableLoadMore) return;
    if (!_state.hasMore || _state.loadingMore || _state.refreshing || _state.initLoading || _state.error) return;
    final size = _state.items.length;
    if (size == 0) return;
    if (size - index > widget.triggerLoadMoreOffset) return;
    if (_preloadedAtSize >= size) return;
    _preloadedAtSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_state.loadingMore || !_state.hasMore || _state.error) return;
      widget.onLoadMore?.call().then((_) {
        if (!mounted) return;
        setState(() {});
        _refresh.finishLoad(_state.error ? IndicatorResult.fail : IndicatorResult.success);
      });
    });
  }

  Future<void> _retry(PagedRetryType type) async {
    widget.onRetry?.call(type);
    if (type == PagedRetryType.init) {
      _preloadedAtSize = 0;
      setState(() => _retrying = true);
      try {
        await widget.onRefresh();
      } finally {
        if (mounted) setState(() => _retrying = false);
      }
    } else {
      await widget.onLoadMore?.call();
      if (!mounted) return;
      setState(() {});
      _refresh.finishLoad(_state.error ? IndicatorResult.fail : IndicatorResult.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_retrying || _state.showInitLoading) {
      return const Center(child: FolioLoading());
    }
    final canPull = widget.enableRefresh;
    // 没有下一页时不挂载 footer，避免出现「没有更多」占位。
    final canLoad = widget.enableLoadMore && !_state.isEmpty && _state.hasMore;
    return EasyRefresh(
      controller: _refresh,
      header: const MaterialHeader(color: FolioColors.copper, backgroundColor: FolioColors.bgSoft),
      footer: canLoad
          ? const MaterialFooter(color: FolioColors.copper, backgroundColor: FolioColors.bgSoft)
          : const NotLoadFooter(),
      onRefresh: canPull ? _handleRefresh : null,
      onLoad: canLoad ? _handleLoad : null,
      child: _buildScrollable(context),
    );
  }

  List<Widget> _headerSlivers() {
    final header = widget.header;
    if (header == null) return const [];
    return [SliverToBoxAdapter(child: header)];
  }

  Widget _buildScrollable(BuildContext context) {
    if (_state.showEmptyOrError) {
      return CustomScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ..._headerSlivers(),
          SliverPadding(
            padding: widget.padding,
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.55,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EmptyHint(
                      title: _state.error ? (_state.errorMessage ?? '加载失败') : (widget.emptyTitle ?? '没有内容'),
                      body: _state.error ? '下拉或点重试再加载一次。' : (widget.emptySubtitle ?? ''),
                      error: _state.error,
                      action: _state.error
                          ? EmptyHintAction(
                              label: widget.errorActionText ?? '重试',
                              onPressed: () => _retry(PagedRetryType.init),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final count = _state.items.length;
    final columns = widget.gridCrossAxisCount;
    if (columns != null && columns > 0) {
      final spacing = widget.gridSpacing;
      final rowCount = (count + columns - 1) ~/ columns;
      return CustomScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ..._headerSlivers(),
          SliverPadding(
            padding: widget.padding,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, rowIndex) {
                  final start = rowIndex * columns;
                  final last = (start + columns - 1).clamp(0, count - 1);
                  _maybePreload(last);
                  return Padding(
                    padding: EdgeInsets.only(bottom: rowIndex == rowCount - 1 ? 0 : spacing),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < columns; i++) ...[
                            if (i > 0) SizedBox(width: spacing),
                            Expanded(
                              child: start + i < count
                                  ? widget.itemBuilder(context, start + i, _state.items[start + i])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                childCount: rowCount,
              ),
            ),
          ),
        ],
      );
    }

    final grid = widget.gridDelegate;
    if (grid != null) {
      return CustomScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ..._headerSlivers(),
          SliverPadding(
            padding: widget.padding,
            sliver: SliverGrid(
              gridDelegate: grid,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  _maybePreload(index);
                  return widget.itemBuilder(context, index, _state.items[index]);
                },
                childCount: count,
              ),
            ),
          ),
        ],
      );
    }

    final sep = widget.separatorBuilder;
    final extent = widget.itemExtent;
    final delegate = SliverChildBuilderDelegate(
      (context, index) {
        if (sep != null) {
          final itemIndex = index ~/ 2;
          if (index.isOdd) return sep(context, itemIndex);
          _maybePreload(itemIndex);
          return widget.itemBuilder(context, itemIndex, _state.items[itemIndex]);
        }
        _maybePreload(index);
        return widget.itemBuilder(context, index, _state.items[index]);
      },
      childCount: sep == null ? count : (count == 0 ? 0 : count * 2 - 1),
    );
    return CustomScrollView(
      controller: widget.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        ..._headerSlivers(),
        SliverPadding(
          padding: widget.padding,
          sliver: extent != null && sep == null
              ? SliverFixedExtentList(itemExtent: extent, delegate: delegate)
              : SliverList(delegate: delegate),
        ),
      ],
    );
  }
}
