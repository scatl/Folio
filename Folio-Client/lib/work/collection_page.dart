import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/theme/artwork_color.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';
import 'package:folio/work/collection_view_model.dart';
import 'package:go_router/go_router.dart';

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(collectionProvider(id));
    final detail = ui.detail;
    return FolioBackdrop(
      child: ArtworkTint(
        url: detail?.backdropUrl ?? detail?.posterUrl,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(RouterPath.home);
                          }
                        },
                        icon: const Icon(Icons.arrow_back, color: FolioColors.ink),
                        tooltip: '返回',
                      ),
                      Expanded(
                        child: Text(
                          detail?.name ?? '系列',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: folioDisplay(size: 18).copyWith(fontFamily: folioSystemFont()),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: detail == null
                      ? Center(
                          child: ui.loading
                              ? const FolioLoading()
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(ui.error ?? '加载失败', style: _text(color: FolioColors.inkMuted)),
                                    TextButton(
                                      onPressed: () => ref.read(collectionProvider(id).notifier).load(),
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          children: [
                            _Hero(detail: detail),
                            ..._section(
                              context: context,
                              title: '本地',
                              parts: _sortedLocal(detail.parts),
                            ),
                            ..._section(
                              context: context,
                              title: '未入库',
                              parts: _sortedRemote(detail.parts),
                              locked: true,
                            ),
                            if (detail.parts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: Text('这个系列暂时没有作品', style: _text(color: FolioColors.inkMuted)),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<CollectionPart> _sortedLocal(List<CollectionPart> parts) {
  return _sortByTimeNearToFar(parts.where((part) => part.inLibrary).toList());
}

List<CollectionPart> _sortedRemote(List<CollectionPart> parts) {
  return _sortByTimeNearToFar(parts.where((part) => !part.inLibrary).toList());
}

List<CollectionPart> _sortByTimeNearToFar(List<CollectionPart> parts) {
  final sorted = parts.toList();
  sorted.sort((a, b) => _partTime(b).compareTo(_partTime(a)));
  return sorted;
}

int _partTime(CollectionPart part) {
  final date = part.releaseDate?.trim();
  if (date != null && date.isNotEmpty) {
    final parsed = DateTime.tryParse(date);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  if (part.year != null) return DateTime.utc(part.year!).millisecondsSinceEpoch;
  return -1;
}

String _partYear(CollectionPart part) => part.year?.toString() ?? '';

List<Widget> _section({
  required BuildContext context,
  required String title,
  required List<CollectionPart> parts,
  bool locked = false,
}) {
  if (parts.isEmpty) return const [];
  return [
    const SizedBox(height: 22),
    Text(
      '$title（${parts.length}）',
      style: folioDisplay(size: 18, color: FolioColors.copper).copyWith(fontFamily: folioSystemFont()),
    ),
    const SizedBox(height: 12),
    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: parts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) => _PartTile(part: parts[index], locked: locked),
    ),
  ];
}

void _openPart(BuildContext context, CollectionPart part, {required bool locked}) {
  if (part.workId != null) {
    context.push(RouterPath.work(part.workId!));
    return;
  }
  final tmdbId = part.tmdbId.trim();
  if (tmdbId.isNotEmpty) {
    context.push(
      RouterPath.workExternal(provider: 'tmdb', externalId: tmdbId, kind: 'movie'),
    );
    return;
  }
  showFolioSheet<void>(
    context: context,
    builder: (context) {
      final original = part.originalTitle?.trim();
      final showOriginal = original != null && original.isNotEmpty && original != part.title.trim();
      final overview = part.overview?.trim();
      final bits = <String>[
        if (part.releaseDate != null && part.releaseDate!.trim().isNotEmpty) part.releaseDate!.trim() else if (part.year != null) '${part.year}',
        if (part.rating != null && part.rating! > 0) '★ ${part.rating!.toStringAsFixed(1)}',
        if (part.genres.isNotEmpty) part.genres.take(2).join(' / '),
      ];
      final meta = bits.join(' · ');
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 64,
                      height: 96,
                      child: PosterImage(url: part.posterUrl, fallback: part.title),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(part.title, style: folioDisplay(size: 20).copyWith(fontFamily: folioSystemFont())),
                        if (showOriginal) ...[
                          const SizedBox(height: 4),
                          Text(original, style: _text(color: FolioColors.inkFaint, size: 13)),
                        ],
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(meta, style: _text(color: FolioColors.inkMuted, size: 13)),
                        ],
                        if (part.originalLanguage != null && part.originalLanguage!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('语言 ${part.originalLanguage}', style: _text(color: FolioColors.inkFaint, size: 12)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                overview != null && overview.isNotEmpty ? overview : '暂无简介',
                style: _text(color: FolioColors.inkMuted, size: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
    },
  );
}

TextStyle _text({
  Color color = FolioColors.ink,
  double size = 14,
  double? height,
  FontWeight? weight,
}) {
  return TextStyle(
    fontFamily: folioSystemFont(),
    color: color,
    fontSize: size,
    height: height,
    fontWeight: weight,
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final CollectionDetail detail;

  @override
  Widget build(BuildContext context) {
    final overview = detail.overview?.trim();
    final years = detail.parts.map((part) => part.year).whereType<int>().toList();
    String? yearSpan;
    if (years.isNotEmpty) {
      final min = years.reduce((a, b) => a < b ? a : b);
      final max = years.reduce((a, b) => a > b ? a : b);
      yearSpan = min == max ? '$min' : '$min–$max';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 96,
                height: 144,
                child: PosterImage(url: detail.posterUrl, fallback: detail.name),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(detail.name, style: folioDisplay(size: 26).copyWith(fontFamily: folioSystemFont(), height: 1.15)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(label: '${detail.parts.length} 部'),
                      _Chip(label: '${detail.localCount} 部本地'),
                      if (yearSpan != null) _Chip(label: yearSpan),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (overview != null && overview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(overview, style: _text(color: FolioColors.inkMuted, size: 14, height: 1.5)),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x590A0C10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FolioColors.line),
      ),
      child: Text(label, style: _text(color: FolioColors.inkMuted, size: 12)),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.part, this.locked = false});

  final CollectionPart part;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final year = _partYear(part);
    return InkWell(
      onTap: () => _openPart(context, part, locked: locked),
      borderRadius: BorderRadius.circular(10),
      child: Opacity(
        opacity: locked ? 0.72 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PosterImage(url: part.posterUrl, fallback: part.title),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              part.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(size: 13, weight: FontWeight.w600),
            ),
            Text(
              year.isNotEmpty ? year : ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(color: FolioColors.inkFaint, size: 11),
            ),
          ],
        ),
      ),
    );
  }
}
