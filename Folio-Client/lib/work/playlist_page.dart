import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/play/playback_catalog_context.dart';
import 'package:folio/play/playback_prepare_meta.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/wall/wall_page_view_model.dart';
import 'package:folio/widget/dialog/confirm_dialog.dart';
import 'package:folio/widget/dialog/prompt_dialog.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class PlaylistPage extends ConsumerStatefulWidget {
  const PlaylistPage({super.key, required this.id});

  final int id;

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  PlaylistDetail? _detail;
  var _loading = true;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ref.read(apiClientProvider).get(
            ApiPath.playlists.one(widget.id),
            parser: jsonParser(PlaylistDetail.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _play(PlaylistItem item) async {
    final fileId = item.playFileId;
    final detail = _detail;
    if (fileId == null || detail == null) {
      _snack('没有可播放的文件');
      return;
    }
    final series = item.kind == 'series' && item.seasonNumber != null && item.episodeNumber != null;
    await playLibraryFile(
      context,
      ref,
      fileId: fileId,
      fileName: item.playFileName ?? 'video',
      posterUrl: item.posterUrl,
      playlistId: detail.id,
      catalog: PlaybackCatalogContext(
        workId: item.workId,
        kind: item.kind,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        showCatalog: false,
      ),
      meta: PlaybackPrepareMeta(
        title: item.workTitle,
        subtitle: item.subtitle,
        playbackTitle: series
            ? seriesPlaybackTitle(
                workTitle: item.workTitle,
                seasonNumber: item.seasonNumber!,
                episodeNumber: item.episodeNumber!,
                episodeTitle: item.episodeTitle,
              )
            : item.workTitle,
        kindLabel: item.kind == 'series' ? '剧集' : '电影',
        year: item.year,
      ),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final detail = _detail;
    if (detail == null || _saving) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final items = [...detail.items];
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    setState(() {
      _detail = PlaylistDetail(id: detail.id, name: detail.name, items: items);
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(apiClientProvider).put(
            ApiPath.playlists.order(detail.id),
            data: {'workIds': items.map((item) => item.workId).toList()},
            parser: jsonParser(PlaylistDetail.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _saving = false;
      });
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message);
      await _load();
    }
  }

  Future<void> _remove(PlaylistItem item) async {
    final detail = _detail;
    if (detail == null || _saving) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(apiClientProvider).delete(
            ApiPath.playlists.item(detail.id, item.workId),
            parser: jsonParser(PlaylistDetail.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _saving = false;
      });
      _refreshHome();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message);
    }
  }

  Future<void> _rename() async {
    final detail = _detail;
    if (detail == null || _saving) return;
    final name = await FolioPromptDialog.show(
      context,
      title: '重命名',
      initialText: detail.name,
      maxLength: 40,
    );
    final next = name?.trim() ?? '';
    if (next.isEmpty || next == detail.name || !mounted) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(apiClientProvider).patch(
            ApiPath.playlists.one(detail.id),
            data: {'name': next},
            parser: jsonParser(PlaylistDetail.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _saving = false;
      });
      _refreshHome();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message);
    }
  }

  Future<void> _delete() async {
    final detail = _detail;
    if (detail == null || _saving) return;
    final ok = await ConfirmDialog.show(
      context,
      title: '删除播放列表',
      message: '删除「${detail.name}」？里面的作品不会从资料库移除。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).delete(
            ApiPath.playlists.one(detail.id),
            parser: (data) => data,
          );
      _refreshHome();
      if (mounted) context.pop();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.message);
    }
  }

  void _refreshHome() {
    ref.read(wallPageProvider.notifier).reloadPlaylists();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: FolioColors.ink,
          title: Text(detail?.name ?? '播放列表', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (detail != null) ...[
              IconButton(
                tooltip: '重命名',
                onPressed: _saving ? null : _rename,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: FolioColors.copper))
            : _error != null && detail == null
                ? Center(child: Text(_error!, style: const TextStyle(color: FolioColors.inkMuted)))
                : detail == null
                    ? const SizedBox.shrink()
                    : detail.items.isEmpty
                        ? const Center(child: Text('这个播放列表还是空的', style: TextStyle(color: FolioColors.inkMuted)))
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            buildDefaultDragHandles: false,
                            itemCount: detail.items.length,
                            onReorder: _reorder,
                            proxyDecorator: (child, index, animation) {
                              return Opacity(
                                opacity: 0.45,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: child,
                                ),
                              );
                            },
                            itemBuilder: (context, index) {
                              final item = detail.items[index];
                              final playable = item.playFileId != null;
                              return Padding(
                                key: ValueKey(item.workId),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: FolioColors.line),
                                  ),
                                  child: Material(
                                    color: FolioColors.bgPanel.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(15),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: playable ? () => _play(item) : null,
                                      splashColor: const Color(0x40D4A574),
                                      highlightColor: const Color(0x24D4A574),
                                      child: Padding(
                                        padding: const EdgeInsets.all(9),
                                        child: Row(
                                          children: [
                                            ReorderableDragStartListener(
                                              index: index,
                                              child: const _PlaylistGrip(),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Opacity(
                                                opacity: playable ? 1 : 0.6,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 58,
                                                        child: AspectRatio(
                                                          aspectRatio: 2 / 3,
                                                          child: ClipRRect(
                                                            borderRadius: BorderRadius.circular(8),
                                                            child: ColoredBox(
                                                              color: FolioColors.bgSoft,
                                                              child: PosterImage(
                                                                url: item.posterUrl,
                                                                fallback: item.workTitle,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              item.workTitle,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w600,
                                                                color: FolioColors.ink,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 3),
                                                            Text(
                                                              playable
                                                                  ? item.subtitle
                                                                  : '${item.subtitle} · 没有可播放的文件',
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                color: FolioColors.inkMuted,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              tooltip: '移除',
                                              onPressed: _saving ? null : () => _remove(item),
                                              style: IconButton.styleFrom(
                                                foregroundColor: FolioColors.ink,
                                                backgroundColor: const Color(0x730A0C10),
                                                disabledForegroundColor: FolioColors.inkFaint,
                                                side: const BorderSide(color: FolioColors.lineStrong),
                                                shape: const CircleBorder(),
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(39, 39),
                                                fixedSize: const Size(39, 39),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                              icon: const _StrokeX(size: 18),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
      ),
    );
  }
}

class _PlaylistGrip extends StatelessWidget {
  const _PlaylistGrip();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 38,
      child: CustomPaint(painter: _GripPainter()),
    );
  }
}

class _GripPainter extends CustomPainter {
  const _GripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = FolioColors.inkFaint;
    const radius = 1.15;
    const gap = 4.5;
    final origin = Offset(
      (size.width - gap) / 2,
      (size.height - gap * 2) / 2,
    );
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawCircle(origin + Offset(col * gap, row * gap), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StrokeX extends StatelessWidget {
  const _StrokeX({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? FolioColors.ink;
    return CustomPaint(
      size: Size.square(size),
      painter: _StrokeXPainter(color),
    );
  }
}

class _StrokeXPainter extends CustomPainter {
  const _StrokeXPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 4.0;
    canvas.drawLine(const Offset(inset, inset), Offset(size.width - inset, size.height - inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(inset, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeXPainter oldDelegate) => oldDelegate.color != color;
}
