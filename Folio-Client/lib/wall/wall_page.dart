import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/wall/browse_filter.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/wall/wall_page_ui_state.dart';
import 'package:folio/wall/wall_page_view_model.dart';
import 'package:folio/widget/dialog/confirm_dialog.dart';
import 'package:folio/widget/folio_nav_icon.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';
import 'package:folio/widget/refresh/paged_refresh_list.dart';
import 'package:folio/widget/refresh/paged_refresh_state.dart';
import 'package:go_router/go_router.dart';

class WallPage extends ConsumerStatefulWidget {
  const WallPage({super.key, this.libraryId});

  final int? libraryId;

  @override
  ConsumerState<WallPage> createState() => _WallPageState();
}

class _WallPageState extends ConsumerState<WallPage> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _homeScroll = ScrollController();
  final _libraryScroll = ScrollController();
  final _searchScroll = ScrollController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final AnimationController _searchAnim;
  late final AnimationController _homeEnter;
  late final TabController _movieTabs;
  bool _fieldOpen = false;
  bool _routeVisible = false;
  bool _homeEnterPlayed = false;

  bool get _isHome => widget.libraryId == null;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _homeEnter = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _movieTabs = TabController(length: 2, vsync: this);
    _movieTabs.addListener(_onMovieTab);
  }

  @override
  void didUpdateWidget(covariant WallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryId == widget.libraryId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFromRoute();
    });
  }

  void _onMovieTab() {
    final tab = _movieTabs.index == 0 ? 'all' : 'collections';
    final ui = ref.read(wallPageProvider);
    if (_isHome || !ui.isMovie || ui.movieTab == tab) return;
    ref.read(wallPageProvider.notifier).setMovieTab(tab);
  }

  void _armHomeEnter(WallPageUiState ui) {
    if (!_isHome || _homeBooting(ui) || _homeEnterPlayed) return;
    _homeEnterPlayed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _homeEnter.forward(from: 0);
    });
  }

  void _syncFromRoute() {
    final vm = ref.read(wallPageProvider.notifier);
    final id = widget.libraryId;
    if (id == null) {
      vm.goHome();
    } else {
      vm.selectLibrary(id);
    }
  }

  void _openHome() {
    _closeDrawer();
    if (_isHome) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouterPath.home);
    }
  }

  void _openLibrary(int id) {
    _closeDrawer();
    if (widget.libraryId == id) return;
    final path = RouterPath.library(id);
    if (_isHome) {
      context.push(path);
    } else {
      context.pushReplacement(path);
    }
  }

  Animation<double> _homeSlot(double begin, double end) {
    return CurvedAnimation(
      parent: _homeEnter,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _movieTabs.removeListener(_onMovieTab);
    _movieTabs.dispose();
    _searchAnim.dispose();
    _homeEnter.dispose();
    _searchFocus.dispose();
    _homeScroll.dispose();
    _libraryScroll.dispose();
    _searchScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _fieldOpen = true);
    ref.read(wallPageProvider.notifier).openSearch();
    _searchAnim.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _dismissSearchField() {
    _searchFocus.unfocus();
    if (_search.text.isNotEmpty) _search.clear();
    _searchAnim.reverse().whenComplete(() {
      if (mounted && !ref.read(wallPageProvider).searchOpen) {
        setState(() => _fieldOpen = false);
      }
    });
  }

  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  Future<void> _createLibrary() async {
    _closeDrawer();
    if (ref.read(wallPageProvider).tmdbConfigured == false) {
      context.push('/settings/source?from=library');
      return;
    }
    final created = await context.push<MediaLibrary>(RouterPath.createLibrary);
    if (created == null || !mounted) return;
    ref.read(wallPageProvider.notifier).noteLibraryCreated(created);
    if (!mounted) return;
    _openLibrary(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.isCurrent ?? false;
    if (current && !_routeVisible) {
      _routeVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncFromRoute();
        if (_isHome) unawaited(ref.read(sessionProvider.notifier).loadProfile());
        ref.read(wallPageProvider.notifier).loadSetup();
      });
    } else if (!current) {
      _routeVisible = false;
    }
    final ui = ref.watch(wallPageProvider);
    ref.listen(sessionProvider.select((session) => session.profileReady), (previous, next) {
      if (next && previous != true) ref.read(wallPageProvider.notifier).loadSetup();
    });
    ref.listen(wallPageProvider, (previous, next) {
      if (previous?.searchOpen == true && !next.searchOpen) {
        _dismissSearchField();
      } else if (next.searchText.isEmpty && _search.text.isNotEmpty) {
        _search.clear();
      }
      final movieIndex = next.movieTab == 'collections' ? 1 : 0;
      if (_movieTabs.index != movieIndex && !_movieTabs.indexIsChanging) {
        _movieTabs.index = movieIndex;
      }
      if (next.query != previous?.query) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchScroll.hasClients) _searchScroll.jumpTo(0);
        });
      }
      final notice = next.notice;
      if (notice != null && notice != previous?.notice) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(notice)));
        ref.read(wallPageProvider.notifier).clearNotice();
      }
    });
    final vm = ref.read(wallPageProvider.notifier);
    _armHomeEnter(ui);
    return FolioBackdrop(
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        drawerEnableOpenDragGesture: false,
        drawer: _drawer(ui, vm),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _appBar(ui, vm),
                  Expanded(
                    child: Stack(
                      children: [
                        if (ui.showSearchResults)
                          Padding(
                            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                            child: _searchResults(ui, vm),
                          )
                        else
                          _mainPanel(ui, vm),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isHome)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _homeEnter,
                      builder: (context, _) {
                        final enter = Curves.easeOut.transform(_homeEnter.value.clamp(0.0, 1.0));
                        final pulse = math.sin(enter * math.pi);
                        final veil = (1 - enter).clamp(0.0, 1.0);
                        return Stack(
                          children: [
                            if (veil > 0.01)
                              ColoredBox(color: Color.fromRGBO(8, 10, 14, 0.5 * veil)),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(-0.7, -0.95),
                                  radius: 1.05,
                                  colors: [
                                    Color.fromRGBO(212, 165, 116, 0.2 * pulse),
                                    Color.fromRGBO(95, 179, 168, 0.1 * pulse),
                                    Colors.transparent,
                                  ],
                                  stops: const [0, 0.4, 1],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawer(WallPageUiState ui, WallPageViewModel vm) {
    return Drawer(
      backgroundColor: FolioColors.bgPanel,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Text('导航', style: folioDisplay(size: 22)),
                  const Spacer(),
                  IconButton(onPressed: _closeDrawer, icon: const Icon(Icons.close)),
                ],
              ),
            ),
            _navTile(
              glyph: FolioNavGlyph.home,
              title: '首页',
              subtitle: '近期作品',
              active: _isHome,
              onTap: _openHome,
            ),
            if (ui.libraries.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('资料库', style: TextStyle(color: FolioColors.inkFaint, fontSize: 12)),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final library in ui.libraries)
                    _navTile(
                      glyph: library.isSeries ? FolioNavGlyph.series : FolioNavGlyph.movie,
                      title: library.name,
                      subtitle: library.kindLabel,
                      active: widget.libraryId == library.id,
                      onTap: () => _openLibrary(library.id),
                    ),
                ],
              ),
            ),
            const Divider(color: FolioColors.line, height: 1),
            if (ref.watch(sessionProvider.select((session) => session.isAdmin))) ...[
              _navTile(glyph: FolioNavGlyph.create, title: '新建资料库', onTap: _createLibrary),
              _navTile(glyph: FolioNavGlyph.logs, title: '日志', onTap: () {
                _closeDrawer();
                context.push(RouterPath.logs);
              }),
            ],
            _navTile(glyph: FolioNavGlyph.settings, title: '设置', onTap: () {
              _closeDrawer();
              context.push(RouterPath.settings);
            }),
            _navTile(
              glyph: FolioNavGlyph.logout,
              title: '退出登录',
              danger: true,
              onTap: () {
                _closeDrawer();
                ref.read(sessionProvider.notifier).signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile({
    required FolioNavGlyph glyph,
    required String title,
    String? subtitle,
    bool active = false,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final color = danger ? FolioColors.danger : (active ? FolioColors.copper : FolioColors.ink);
    return ListTile(
      leading: FolioNavIcon(glyph, active: active),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: FolioColors.inkFaint, fontSize: 11, height: 1.2)),
      selected: active,
      onTap: onTap,
    );
  }

  Widget _appBar(WallPageUiState ui, WallPageViewModel vm) {
    // 以实际列表为准；加载中且列表仍空时不算「有资料库」，避免重试时右侧按钮闪现。
    final hasLibraries = ui.libraries.isNotEmpty;
    final title = _isHome
        ? (!hasLibraries && !ui.librariesLoading && ui.error == null ? '还没有资料库' : 'Folio')
        : (ui.library?.name ?? 'Folio');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: SizedBox(
        height: 48,
        child: AnimatedBuilder(
          animation: _searchAnim,
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_searchAnim.value);
            final admin = ref.watch(sessionProvider.select((session) => session.isAdmin));
            final trailing = _isHome
                ? (hasLibraries && admin ? _taskButton() : null)
                : (ui.library?.canWrite == true || admin ? _libraryMenu(ui, vm) : null);
            return Row(
              children: [
                IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      IgnorePointer(
                        ignoring: t > 0.4,
                        child: Opacity(
                          opacity: (1 - t).clamp(0, 1),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: folioDisplay(size: 22, weight: FontWeight.w400),
                                ),
                              ),
                              if (hasLibraries)
                                IconButton(
                                  tooltip: '搜索',
                                  onPressed: _openSearch,
                                  icon: const Icon(Icons.search),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_fieldOpen)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: t < 0.45,
                            child: Opacity(
                              opacity: t.clamp(0, 1),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    widthFactor: t.clamp(0.001, 1),
                                    child: _searchField(vm),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasLibraries) _filterButton(ui, vm),
                if (trailing != null) _collapseAside(t, trailing),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _searchField(WallPageViewModel vm) {
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _search,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        onChanged: vm.onSearch,
        style: const TextStyle(fontSize: 14, height: 1.1),
        decoration: InputDecoration(
          hintText: '搜索片名、类型、演职员…',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: IconButton(
            tooltip: '关闭搜索',
            onPressed: vm.closeSearch,
            icon: const Icon(Icons.close, size: 18),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: FolioColors.lineStrong)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: FolioColors.lineStrong)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: FolioColors.copper)),
        ),
      ),
    );
  }

  bool _homeBooting(WallPageUiState ui) =>
      _isHome && (ui.loading || ui.librariesLoading) && ui.libraries.isEmpty && ui.recent.isEmpty && ui.error == null;

  bool _showHeaderStatus(WallPageUiState ui, bool noLibraries) {
    // 资料库统计行跟列表一起滚，固定 header 只给首页用。
    if (!_isHome) return false;
    if (_homeBooting(ui)) return false;
    // 全页错误态已有 EmptyHint，顶部不再重复错误文案。
    if (ui.error != null && !ui.loading && ui.libraries.isEmpty && ui.recent.isEmpty) return false;
    return noLibraries || ui.error != null;
  }

  Widget? _worksStatusHeader(WallPageUiState ui) {
    if (ui.loading || ui.librariesLoading) return null;
    if (ui.error != null && ui.items.isEmpty) return null;
    final current = ui.library;
    if (current == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: StatusLine(
        text: '${current.name} · 共 ${ui.total} 部作品',
        error: ui.error != null,
      ),
    );
  }

  Widget? _collectionsStatusHeader(WallPageUiState ui) {
    if (!ui.collectionsLoaded || ui.collectionsLoading || ui.librariesLoading) return null;
    if (ui.error != null && ui.collections.isEmpty) return null;
    final current = ui.library;
    if (current == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: StatusLine(
        text: '${current.name} · ${ui.collections.length} 个系列',
        error: ui.error != null,
      ),
    );
  }

  Widget _header(WallPageUiState ui, WallPageViewModel vm) {
    final admin = ref.watch(sessionProvider.select((session) => session.isAdmin));
    final noLibraries = _isHome
        ? ui.homeLibrariesOk && ui.libraries.isEmpty
        : !ui.librariesLoading && ui.libraries.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (admin && ui.tmdbConfigured == false) ...[
            const SizedBox(height: 8),
            _setupCard(),
          ] else if (_isHome && noLibraries && ui.error == null && admin) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _createLibrary,
              style: FilledButton.styleFrom(backgroundColor: FolioColors.copper, foregroundColor: const Color(0xFF1A1208)),
              child: const Text('新建资料库'),
            ),
          ] else if (_isHome && noLibraries && ui.error == null) ...[
            const SizedBox(height: 16),
            const Text('还没有资料库。请管理员创建。', style: TextStyle(color: FolioColors.inkMuted, height: 1.4)),
          ],
          if (_showHeaderStatus(ui, noLibraries)) ...[
            const SizedBox(height: 12),
            StatusLine(
              text: ui.statusText,
              error: ui.error != null && !ui.loading,
              loading: ui.loading || ui.librariesLoading,
            ),
          ],
        ],
      ),
    );
  }

  Widget _setupCard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x14D4A574),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x73D4A574)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('先配置 TMDB API Key', style: TextStyle(color: FolioColors.ink, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(
                    '只有 TMDB 用来搜索和建档。没有 Key 时无法刮削新的作品。',
                    style: TextStyle(color: FolioColors.inkMuted, fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => context.push('/settings/source?from=library'),
              style: FilledButton.styleFrom(
                backgroundColor: FolioColors.copper,
                foregroundColor: const Color(0xFF1A1208),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('去配置'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryMenu(WallPageUiState ui, WallPageViewModel vm) {
    final library = ui.library;
    if (library == null) return const SizedBox.shrink();
    final admin = ref.watch(sessionProvider.select((session) => session.isAdmin));
    final canScan = library.canWrite || admin;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert),
      color: FolioColors.bgPanel,
      onSelected: (value) {
        if (value == 'scan') vm.scan();
        if (value == 'delete') _confirmDelete(library);
      },
      itemBuilder: (context) => [
        if (canScan)
          PopupMenuItem(
            value: 'scan',
            enabled: !ui.scanning,
            child: Text(ui.scanning ? '扫描中' : '扫描'),
          ),
        if (admin)
          const PopupMenuItem(
            value: 'delete',
            child: Text('删除资料库', style: TextStyle(color: FolioColors.danger)),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(MediaLibrary library) async {
    final ok = await ConfirmDialog.show(
      context,
      title: '删除「${library.name}」',
      message: '磁盘上的视频会保留，已刮削的作品资料也会保留。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok == true && mounted) {
      await ref.read(wallPageProvider.notifier).deleteLibrary(library);
      if (!mounted) return;
      if (widget.libraryId == library.id) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouterPath.home);
        }
      }
    }
  }

  Widget _taskButton() {
    final badge = ref.watch(sessionProvider.select((session) => session.taskBadge));
    return IconButton(
      tooltip: '任务',
      onPressed: () => context.push(RouterPath.tasks),
      icon: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: FolioColors.copper,
        textColor: const Color(0xFF1A1208),
        child: const Icon(Icons.playlist_play, color: FolioColors.ink),
      ),
    );
  }

  Future<void> _openFilter(WallPageUiState ui, WallPageViewModel vm) async {
    final next = await showBrowseSheet(
      context,
      ref.read(apiClientProvider),
      ui.browse,
      libraryId: _isHome ? null : ui.libraryId,
    );
    if (next != null) await vm.applyBrowse(next);
  }

  Widget _filterButton(WallPageUiState ui, WallPageViewModel vm) {
    final count = ui.browse.extraCount;
    return IconButton(
      tooltip: count == 0 ? '筛选' : '筛选 $count',
      onPressed: () => _openFilter(ui, vm),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: FolioColors.copper,
        textColor: const Color(0xFF1A1208),
        child: const Icon(Icons.tune),
      ),
    );
  }

  Widget _collapseAside(double t, Widget child) {
    final keep = (1 - t).clamp(0.0, 1.0);
    if (keep == 0) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: t > 0.4,
      child: Opacity(
        opacity: keep,
        child: ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: keep.clamp(0.001, 1),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _markWork(WorkCard work) async {
    final watched = await showBlurModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (work.watchState != 'watched')
              ListTile(title: const Text('标为已看'), onTap: () => Navigator.pop(context, true)),
            if (work.watchState != 'unwatched')
              ListTile(title: const Text('标为未看'), onTap: () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
    if (watched == null || !mounted) return;
    await ref.read(wallPageProvider.notifier).markWork(work, watched);
  }

  Widget _mainPanel(WallPageUiState ui, WallPageViewModel vm) {
    if (_isHome && ui.browse.active) {
      return _workList(
        works: ui.items,
        loading: ui.loading,
        loadingMore: ui.loadingMore,
        hasMore: ui.hasMore,
        error: ui.error,
        emptyTitle: '没有符合筛选的作品',
        emptyBody: '换一组条件，或清除筛选。',
        onRefresh: () => vm.applyBrowse(ui.browse),
        onLoadMore: vm.loadMore,
        scrollController: _homeScroll,
      );
    }
    if (_isHome) return _homePanel(ui, vm);
    final library = ui.library;
    if (library == null) {
      return const Center(child: FolioLoading());
    }
    return library.kind == 'movie' ? _movieLibrary(ui, vm) : _seriesLibrary(ui, vm);
  }

  Widget _homePanel(WallPageUiState ui, WallPageViewModel vm) {
    final homeError = ui.libraries.isEmpty && ui.recent.isEmpty && ui.error != null;
    return RefreshIndicator(
      key: const ValueKey('home-refresh'),
      color: FolioColors.copper,
      backgroundColor: FolioColors.bgSoft,
      onRefresh: vm.refresh,
      child: CustomScrollView(
        controller: _homeScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _header(ui, vm)),
          if (_homeBooting(ui))
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: FolioLoading()),
            )
          else if (homeError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: EmptyHint(
                  title: '无法连接服务器',
                  body: ui.error!,
                  error: true,
                  action: EmptyHintAction(label: '重试', onPressed: () { vm.refresh(); }),
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(child: _homeBody(ui)),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ],
      ),
    );
  }

  Widget _seriesLibrary(WallPageUiState ui, WallPageViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ui.tmdbConfigured == false) _header(ui, vm),
        Expanded(
          child: _workList(
            works: ui.items,
            loading: ui.loading,
            loadingMore: ui.loadingMore,
            hasMore: ui.hasMore,
            error: ui.error,
            emptyTitle: ui.browse.active ? '没有符合筛选的作品' : '这个资料库还没有作品',
            emptyBody: ui.browse.active ? '换一组条件，或清除筛选。' : '刮削完成后，匹配成功的海报会出现在这里。',
            onRefresh: vm.refresh,
            onLoadMore: vm.loadMore,
            scrollController: _libraryScroll,
            header: _worksStatusHeader(ui),
          ),
        ),
      ],
    );
  }

  Widget _movieLibrary(WallPageUiState ui, WallPageViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ui.tmdbConfigured == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _setupCard(),
          ),
        TabBar(
          controller: _movieTabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorWeight: 0,
          indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x38D4A574), Color(0x2E5FB3A8)],
            ),
          ),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          labelColor: FolioColors.ink,
          unselectedLabelColor: FolioColors.inkMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          dividerColor: Colors.transparent,
          tabs: const [Tab(text: '全部'), Tab(text: '系列')],
        ),
        Expanded(
          child: TabBarView(
            controller: _movieTabs,
            children: [
              _workList(
                works: ui.items,
                loading: ui.loading,
                loadingMore: ui.loadingMore,
                hasMore: ui.hasMore,
                error: ui.error,
                emptyTitle: ui.browse.active ? '没有符合筛选的作品' : '这个资料库还没有作品',
                emptyBody: ui.browse.active ? '换一组条件，或清除筛选。' : '刮削完成后，匹配成功的海报会出现在这里。',
                onRefresh: vm.refresh,
                onLoadMore: vm.loadMore,
                header: _worksStatusHeader(ui),
              ),
              _collectionsBody(ui, vm),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeBody(WallPageUiState ui) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ui.homeContinueOk && ui.continueWatching.isNotEmpty) ...[
            _Reveal(
              animation: _homeSlot(0.22, 0.55),
              child: const _SectionLabel('继续观看'),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = _posterTileWidth(constraints.maxWidth);
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final height = tileWidth * 3 / 2 + 8 + (14 * 1.2 + 2 + 12 * 1.2) * scale + 6;
                return SizedBox(
                  height: height,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ui.continueWatching.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = ui.continueWatching[index];
                      return _Reveal(
                        animation: _homeSlot(
                          (0.26 + index * 0.05).clamp(0.0, 0.75),
                          (0.55 + index * 0.05).clamp(0.4, 0.98),
                        ),
                        slide: 20,
                        child: _ContinueCard(item: item, width: tileWidth),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if (ui.homeWatchlistOk && ui.watchlist.isNotEmpty) ...[
            _Reveal(
              animation: _homeSlot(0.24, 0.58),
              child: const _SectionLabel('想看'),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = _posterTileWidth(constraints.maxWidth);
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final height = tileWidth * 3 / 2 + 8 + (14 * 1.2 + 2 + 12 * 1.2) * scale + 6;
                return SizedBox(
                  height: height,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ui.watchlist.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = ui.watchlist[index];
                      return _Reveal(
                        animation: _homeSlot(
                          (0.28 + index * 0.05).clamp(0.0, 0.75),
                          (0.58 + index * 0.05).clamp(0.4, 0.98),
                        ),
                        slide: 20,
                        child: _WatchCard(item: item, width: tileWidth),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if (ui.homePlaylistsOk && ui.playlists.isNotEmpty) ...[
            _Reveal(
              animation: _homeSlot(0.26, 0.6),
              child: const _SectionLabel('播放列表'),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = _posterTileWidth(constraints.maxWidth);
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final height = tileWidth * 3 / 2 + 8 + (14 * 1.2 + 2 + 12 * 1.2) * scale + 6;
                return SizedBox(
                  height: height,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ui.playlists.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = ui.playlists[index];
                      return _Reveal(
                        animation: _homeSlot(
                          (0.3 + index * 0.05).clamp(0.0, 0.75),
                          (0.6 + index * 0.05).clamp(0.4, 0.98),
                        ),
                        slide: 20,
                        child: _PlaylistCard(item: item, width: tileWidth),
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if (ui.homeRecentOk && ui.recent.isNotEmpty) ...[
            _Reveal(
              animation: _homeSlot(0.28, 0.62),
              child: const _SectionLabel('近期作品'),
            ),
            const SizedBox(height: 14),
            _posterGrid(ui.recent, mainAxisSpacing: 14, staggerEnter: true),
          ] else if (ui.homeRecentOk &&
              ui.homeLibrariesOk &&
              ui.libraries.isNotEmpty &&
              ui.continueWatching.isEmpty &&
              ui.watchlist.isEmpty &&
              ui.playlists.isEmpty)
            _Reveal(
              animation: _homeSlot(0.3, 0.7),
              child: const EmptyHint(title: '还没有作品', body: '资料库扫描并刮削成功后，近期作品会出现在这里。'),
            ),
        ],
      ),
    );
  }

  Widget _collectionsBody(WallPageUiState ui, WallPageViewModel vm) {
    // 对齐任务页懒加载：未 loaded 前不展示空态。
    if (!ui.collectionsLoaded && ui.collections.isEmpty) {
      if (ui.error != null && !ui.collectionsLoading) {
        return Center(
          child: EmptyHint(
            title: '加载失败',
            body: ui.error!,
            error: true,
            action: EmptyHintAction(label: '重试', onPressed: () { vm.refresh(); }),
          ),
        );
      }
      return const Center(child: FolioLoading());
    }
    return _collectionList(
      items: ui.collections,
      loading: ui.collectionsLoading,
      error: ui.error,
      emptyTitle: '还没有可合并的系列',
      emptyBody: '同一系列里至少有两部本地电影时，会出现在这里。',
      onRefresh: vm.refresh,
      onCollection: (card) => context.push(RouterPath.collection(card.id)),
      header: _collectionsStatusHeader(ui),
    );
  }

  Widget _searchResults(WallPageUiState ui, WallPageViewModel vm) {
    if (ui.collectionSearch) {
      final q = ui.searchText.trim().toLowerCase();
      final matched = ui.collections.where((item) => item.name.toLowerCase().contains(q)).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: StatusLine(text: '「${ui.searchText.trim()}」 · ${matched.length} 个系列'),
          ),
          Expanded(
            child: !ui.collectionsLoaded && ui.collections.isEmpty
                ? const Center(child: FolioLoading())
                : _collectionList(
                    items: matched,
                    loading: ui.collectionsLoading && ui.collections.isEmpty,
                    error: null,
                    emptyTitle: '没有找到相关系列',
                    emptyBody: '换个系列名试试。',
                    onRefresh: vm.refreshSearch,
                    scrollController: _searchScroll,
                    onCollection: (card) {
                      vm.closeSearch();
                      context.push(RouterPath.collection(card.id));
                    },
                  ),
          ),
        ],
      );
    }

    final pending = ui.searchText.trim() != ui.query;
    final loading = pending || (ui.searchLoading && ui.searchResults.isEmpty);
    final text = ui.searchError != null && !pending
        ? ui.searchError!
        : (loading ? '正在搜索' : '「${ui.query}」 · 共 ${ui.searchTotal} 部');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: StatusLine(text: text, error: ui.searchError != null && !pending, loading: loading),
        ),
        Expanded(
          child: _workList(
            works: pending ? const [] : ui.searchResults,
            loading: loading,
            loadingMore: ui.searchLoadingMore,
            hasMore: !pending && ui.searchHasMore,
            error: pending ? null : ui.searchError,
            emptyTitle: '没有找到相关作品',
            emptyBody: '换个片名、类型、年份、演职员或文件名试试。',
            onRefresh: vm.refreshSearch,
            onLoadMore: vm.loadMoreSearch,
            scrollController: _searchScroll,
          ),
        ),
      ],
    );
  }

  Widget _workList({
    required List<WorkCard> works,
    required bool loading,
    required bool loadingMore,
    required bool hasMore,
    required String? error,
    required String emptyTitle,
    required String emptyBody,
    required Future<void> Function() onRefresh,
    Future<void> Function()? onLoadMore,
    ScrollController? scrollController,
    Widget? header,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 3;
        final state = PagedRefreshState<WorkCard>()
          ..items = works
          ..initLoading = loading && works.isEmpty
          ..refreshing = loading && works.isNotEmpty
          ..loadingMore = loadingMore
          ..hasMore = hasMore
          ..error = error != null && works.isEmpty
          ..errorMessage = error;
        return PagedRefreshList<WorkCard>(
          state: state,
          scrollController: scrollController,
          onRefresh: onRefresh,
          onLoadMore: onLoadMore,
          enableLoadMore: onLoadMore != null,
          header: header,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          emptyTitle: emptyTitle,
          emptySubtitle: emptyBody,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 0.5,
          ),
          itemBuilder: (context, index, work) => PosterCard(work: work, onTap: () => context.push(RouterPath.work(work.id))),
        );
      },
    );
  }

  Widget _collectionList({
    required List<CollectionCard> items,
    required bool loading,
    required String? error,
    required String emptyTitle,
    required String emptyBody,
    required Future<void> Function() onRefresh,
    required void Function(CollectionCard card) onCollection,
    ScrollController? scrollController,
    Widget? header,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 3;
        final state = PagedRefreshState<CollectionCard>()
          ..items = items
          ..initLoading = loading && items.isEmpty
          ..error = error != null && items.isEmpty
          ..errorMessage = error;
        return PagedRefreshList<CollectionCard>(
          state: state,
          scrollController: scrollController,
          onRefresh: onRefresh,
          enableLoadMore: false,
          header: header,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          emptyTitle: emptyTitle,
          emptySubtitle: emptyBody,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: 0.5,
          ),
          itemBuilder: (context, index, item) {
            return GestureDetector(
              onTap: () => onCollection(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PosterImage(url: item.posterUrl, fallback: '系列'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${item.count} 部', style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _posterGrid(
    List<WorkCard> works, {
    List<CollectionCard> collections = const [],
    void Function(CollectionCard card)? onCollection,
    double mainAxisSpacing = 10,
    bool staggerEnter = false,
  }) {
    final tiles = collections.isNotEmpty ? collections.length : works.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _posterColumns(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiles,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: 8,
            childAspectRatio: 0.5,
          ),
          itemBuilder: (context, index) {
            final Widget tile;
            if (collections.isNotEmpty) {
              final item = collections[index];
              tile = GestureDetector(
                onTap: () => onCollection?.call(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PosterImage(url: item.posterUrl, fallback: '系列'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${item.count} 部', style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12)),
                  ],
                ),
              );
            } else {
              final work = works[index];
              tile = PosterCard(
                work: work,
                onTap: () => context.push(RouterPath.work(work.id)),
                onLongPress: () => _markWork(work),
              );
            }
            if (!staggerEnter) return tile;
            final start = (0.34 + index * 0.045).clamp(0.0, 0.78);
            final end = (start + 0.28).clamp(0.2, 1.0);
            return _Reveal(
              animation: _homeSlot(start, end),
              slide: 26,
              scaleFrom: 0.94,
              child: tile,
            );
          },
        );
      },
    );
  }
}

int _posterColumns(double width) => width >= 720 ? 4 : 3;

double _posterTileWidth(double width) {
  final columns = _posterColumns(width);
  return (width - (columns - 1) * 8) / columns;
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({required this.item, required this.width});

  final WatchlistItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => context.push(RouterPath.work(item.workId)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PosterImage(url: item.posterUrl, fallback: item.workTitle),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.workTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12, height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.item, required this.width});

  final PlaylistSummary item;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => context.push(RouterPath.playlist(item.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PosterImage(url: item.posterUrl, fallback: item.name),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${item.itemCount} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12, height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.item, required this.width});

  final ContinueWatchItem item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio = item.progressRatio.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      child: GestureDetector(
        onTap: () => playContinueItem(context, ref, item),
        onLongPress: () => context.push(RouterPath.work(item.workId)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: item.posterUrl, fallback: item.workTitle),
                    if (ratio > 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xCC12151C),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: FolioColors.line),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              '${(ratio * 100).round().clamp(1, 100)}%',
                              style: const TextStyle(
                                color: FolioColors.copper,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.workTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12, height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.child,
    this.slide = 18,
    this.scaleFrom = 1,
  });

  final Animation<double> animation;
  final Widget child;
  final double slide;
  final double scaleFrom;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        final scale = scaleFrom + (1 - scaleFrom) * t;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, slide * (1 - t)),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: folioDisplay(size: 18, color: FolioColors.copper));
  }
}

class _ListLoading extends StatelessWidget {
  const _ListLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: FolioLoading()),
    );
  }
}
