import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/theme/artwork_color.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';
import 'package:folio/work/person_view_model.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class PersonPage extends ConsumerWidget {
  const PersonPage({
    super.key,
    required this.provider,
    required this.externalId,
  });

  final String provider;
  final String externalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (provider: provider, externalId: externalId);
    final ui = ref.watch(personProvider(key));
    final detail = ui.detail;
    return FolioBackdrop(
      child: ArtworkTint(
        url: detail?.profileUrl,
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
                          detail?.name ?? '人物',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: folioDisplay(size: 18).copyWith(fontFamily: folioSystemFont()),
                        ),
                      ),
                      if (detail?.canRefresh == true)
                        TextButton(
                          onPressed: ui.refreshing ? null : () => ref.read(personProvider(key).notifier).refresh(),
                          child: Text(ui.refreshing ? '刷新中…' : '刷新'),
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
                                      onPressed: () => ref.read(personProvider(key).notifier).load(),
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          children: [
                            if (ui.error != null && !ui.loading)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(ui.error!, style: _text(color: FolioColors.danger, size: 13)),
                              ),
                            _Hero(detail: detail),
                            ..._section(
                              context: context,
                              title: '本地',
                              credits: _sortedLocal(detail.credits),
                            ),
                            ..._section(
                              context: context,
                              title: '未入库',
                              credits: _sortedRemote(detail.credits),
                              locked: true,
                            ),
                            if (detail.credits.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: Text('暂无相关作品', style: _text(color: FolioColors.inkMuted)),
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

List<PersonWorkCredit> _sortedLocal(List<PersonWorkCredit> credits) {
  return _sortByTimeNearToFar(credits.where((credit) => credit.inLibrary).toList());
}

List<PersonWorkCredit> _sortedRemote(List<PersonWorkCredit> credits) {
  return _sortByTimeNearToFar(credits.where((credit) => !credit.inLibrary).toList());
}

List<PersonWorkCredit> _sortByTimeNearToFar(List<PersonWorkCredit> credits) {
  final sorted = credits.toList();
  sorted.sort((a, b) => _creditTime(b).compareTo(_creditTime(a)));
  return sorted;
}

int _creditTime(PersonWorkCredit credit) {
  final date = credit.releaseDate?.trim();
  if (date != null && date.isNotEmpty) {
    final parsed = DateTime.tryParse(date);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
  }
  if (credit.year != null) return DateTime.utc(credit.year!).millisecondsSinceEpoch;
  return -1;
}

String _creditYear(PersonWorkCredit credit) => credit.year?.toString() ?? '';

String _mediaTypeLabel(String mediaType) {
  switch (mediaType.trim().toLowerCase()) {
    case 'tv':
      return '剧集';
    case 'movie':
      return '电影';
    case 'stage':
    case 'theatre':
    case 'theater':
      return '话剧';
    default:
      final value = mediaType.trim();
      return value.isEmpty ? '作品' : value;
  }
}

String _creditSubtitle(PersonWorkCredit credit) {
  final year = _creditYear(credit);
  final role = credit.role;
  return [
    if (year.isNotEmpty) year,
    if (role.isNotEmpty) role,
  ].join(' · ');
}

String? _tmdbUrl(PersonWorkCredit credit) {
  final id = credit.tmdbId.trim();
  if (id.isEmpty) return null;
  final path = credit.mediaType.trim().toLowerCase() == 'tv' ? 'tv' : 'movie';
  return 'https://www.themoviedb.org/$path/$id';
}

Future<void> _openTmdb(PersonWorkCredit credit) async {
  final url = _tmdbUrl(credit);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

List<Widget> _section({
  required BuildContext context,
  required String title,
  required List<PersonWorkCredit> credits,
  bool locked = false,
}) {
  if (credits.isEmpty) return const [];
  return [
    const SizedBox(height: 22),
    Text(
      '$title（${credits.length}）',
      style: folioDisplay(size: 18, color: FolioColors.copper).copyWith(fontFamily: folioSystemFont()),
    ),
    const SizedBox(height: 12),
    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: credits.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) => _CreditTile(credit: credits[index], locked: locked),
    ),
  ];
}

void _openCredit(BuildContext context, PersonWorkCredit credit, {required bool locked}) {
  if (credit.workId != null) {
    context.push(RouterPath.work(credit.workId!));
    return;
  }
  final tmdbId = credit.tmdbId.trim();
  if (tmdbId.isNotEmpty) {
    final kind = credit.mediaType.trim().toLowerCase() == 'tv' ? 'tv' : 'movie';
    context.push(
      RouterPath.workExternal(provider: 'tmdb', externalId: tmdbId, kind: kind),
    );
    return;
  }
  showFolioSheet<void>(
    context: context,
    builder: (context) {
      final original = credit.originalTitle?.trim();
      final showOriginal = original != null && original.isNotEmpty && original != credit.title.trim();
      final bits = <String>[
        if (credit.releaseDate != null && credit.releaseDate!.trim().isNotEmpty)
          credit.releaseDate!.trim()
        else if (credit.year != null)
          '${credit.year}',
        _mediaTypeLabel(credit.mediaType),
        if (credit.role.isNotEmpty) credit.role,
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
                      child: PosterImage(url: credit.posterUrl, fallback: credit.title),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(credit.title, style: folioDisplay(size: 20).copyWith(fontFamily: folioSystemFont())),                        if (showOriginal) ...[
                          const SizedBox(height: 4),
                          Text(original, style: _text(color: FolioColors.inkFaint, size: 13)),
                        ],
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(meta, style: _text(color: FolioColors.inkMuted, size: 13)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: FolioColors.ink,
                      side: const BorderSide(color: FolioColors.lineStrong),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('关闭'),
                  ),
                  if (_tmdbUrl(credit) != null) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => _openTmdb(credit),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7ED7F0),
                        backgroundColor: const Color(0x2900B3E5),
                        side: const BorderSide(color: Color(0x7300B3E5)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset('assets/providers/tmdb.svg', height: 12),
                          const SizedBox(width: 6),
                          const Text('TMDB'),
                        ],
                      ),
                    ),
                  ],
                ],
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

  final PersonDetail detail;

  @override
  Widget build(BuildContext context) {
    final biography = detail.biography?.trim();
    final chips = <String>[
      if (detail.knownForDepartment != null && detail.knownForDepartment!.trim().isNotEmpty) detail.knownForDepartment!.trim(),
      if (detail.birthday != null && detail.birthday!.trim().isNotEmpty)
        detail.deathday != null && detail.deathday!.trim().isNotEmpty
            ? '${detail.birthday} – ${detail.deathday}'
            : detail.birthday!.trim(),
      if (detail.placeOfBirth != null && detail.placeOfBirth!.trim().isNotEmpty) detail.placeOfBirth!.trim(),
      '${detail.credits.length} 部作品',
      if (detail.localCount > 0) '${detail.localCount} 部本地',
    ];
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
                child: PosterImage(
                  url: detail.profileUrl,
                  fallback: detail.name.isEmpty ? '·' : detail.name.characters.first,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(detail.name, style: folioDisplay(size: 26).copyWith(fontFamily: folioSystemFont(), height: 1.15)),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final chip in chips) _Chip(label: chip)],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (biography != null && biography.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(biography, style: _text(color: FolioColors.inkMuted, size: 14, height: 1.5)),
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

class _CreditTile extends StatelessWidget {
  const _CreditTile({required this.credit, this.locked = false});

  final PersonWorkCredit credit;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final subtitle = _creditSubtitle(credit);
    return InkWell(
      onTap: () => _openCredit(context, credit, locked: locked),
      borderRadius: BorderRadius.circular(10),
      child: Opacity(
        opacity: locked ? 0.72 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: credit.posterUrl, fallback: credit.title),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xD9080A0E)],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Text(
                        _mediaTypeLabel(credit.mediaType),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: FolioColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              credit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(size: 13, weight: FontWeight.w600),
            ),
            Text(
              subtitle.isNotEmpty ? subtitle : ' ',
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
