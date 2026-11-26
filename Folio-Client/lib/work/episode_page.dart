import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/play/play_library.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/theme/artwork_color.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';
import 'package:folio/work/episode_ui_state.dart';
import 'package:folio/work/episode_view_model.dart';
import 'package:folio/work/playlist_sheet.dart';
import 'package:folio/work/video_info_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class EpisodePage extends ConsumerWidget {
  const EpisodePage({
    super.key,
    required this.workId,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final int workId;
  final int seasonNumber;
  final int episodeNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = EpisodeKey(workId, seasonNumber, episodeNumber);
    final ui = ref.watch(episodeProvider(key));
    final detail = ui.detail;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: detail == null
            ? _Status(
                loading: ui.loading,
                error: ui.error,
                workId: workId,
                seasonNumber: seasonNumber,
                onRetry: () => ref.read(episodeProvider(key).notifier).load(),
              )
            : _DetailBody(detail: detail),
      ),
    );
  }
}

TextStyle _body({Color color = FolioColors.ink, double height = 1.55}) {
  return TextStyle(fontFamily: folioSystemFont(), fontSize: 15, height: height, color: color);
}

TextStyle _caption({Color color = FolioColors.inkMuted, double size = 13}) {
  return TextStyle(fontFamily: folioSystemFont(), fontSize: size, color: color);
}

class _Status extends StatelessWidget {
  const _Status({
    required this.loading,
    required this.error,
    required this.workId,
    required this.seasonNumber,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final int workId;
  final int seasonNumber;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackBar(workId: workId, seasonNumber: seasonNumber),
          Expanded(
            child: Center(
              child: loading
                  ? const FolioLoading()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error ?? '加载失败', style: _caption()),
                        const SizedBox(height: 12),
                        TextButton(onPressed: onRetry, child: const Text('重试')),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({required this.detail});

  final EpisodeDetail detail;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  final _scroll = ScrollController();
  var _offset = 0.0;
  Color _background = FolioColors.bgDeep;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!mounted) return;
      setState(() => _offset = _scroll.offset.clamp(0, 400));
    });
    _loadTint();
  }

  Future<void> _loadTint() async {
    final url = widget.detail.episode.stillUrl;
    if (url == null || url.isEmpty) return;
    try {
      final color = await artworkBackground(url);
      if (mounted) setState(() => _background = color);
    } catch (_) {
      if (mounted) setState(() => _background = FolioColors.bgDeep);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final episode = detail.episode;
    final top = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, constraints) {
        final backdropHeight = top + constraints.maxWidth * 2 / 3;
        final shift = _offset * 0.72;
        final barFade = (_offset / (backdropHeight * 0.55)).clamp(0.0, 1.0);
        final meta = [
          detail.seasonHeading,
          if (episode.airDate != null && episode.airDate!.isNotEmpty) episode.airDate!,
          if (episode.runtimeMinutes != null) '${episode.runtimeMinutes} 分钟',
          if (episode.voteAverage != null && episode.voteAverage! > 0)
            '★ ${episode.voteAverage!.toStringAsFixed(1)}',
        ];
        final facts = <(String, String)>[
          ('剧集', detail.workTitle),
          ('季', detail.seasonHeading),
          if (episode.airDate != null && episode.airDate!.isNotEmpty) ('播出', episode.airDate!),
          if (episode.runtimeMinutes != null) ('片长', '${episode.runtimeMinutes} 分钟'),
          if (episode.voteAverage != null)
            (
              '评分',
              episode.voteCount != null
                  ? '${episode.voteAverage!.toStringAsFixed(1)}（${episode.voteCount}）'
                  : episode.voteAverage!.toStringAsFixed(1),
            ),
          if (episode.absoluteNumber != null) ('绝对集', '${episode.absoluteNumber}'),
          if (detail.productionCode != null && detail.productionCode!.trim().isNotEmpty)
            ('制作编号', detail.productionCode!.trim()),
        ];
        final cast = detail.cast;
        final crew = detail.crew;
        final arts = episode.artworksByKind;
        return Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: _background)),
            Positioned(
              top: -shift,
              left: 0,
              right: 0,
              height: backdropHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: episode.stillUrl, fallback: episode.heading),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [const Color(0x99080A0E), const Color(0x66080A0E), const Color(0xB3080A0E), _background],
                        stops: const [0, 0.42, 0.75, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(height: backdropHeight - 40),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Column(
                          children: [
                            Text(episode.heading, textAlign: TextAlign.center, style: folioDisplay(size: 26)),
                            const SizedBox(height: 10),
                            Text(
                              meta.join(' · '),
                              textAlign: TextAlign.center,
                              style: _caption(),
                            ),
                            if (episode.files.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Consumer(
                                builder: (context, ref, _) => FilledButton.icon(
                                  onPressed: () => playLibraryFiles(
                                    context,
                                    ref,
                                    episode.files,
                                    posterUrl: episode.stillUrl,
                                    meta: PlaybackPrepareMeta.fromEpisode(detail),
                                    catalog: PlaybackCatalogContext(
                                      workId: detail.workId,
                                      kind: 'series',
                                      seasonNumber: detail.seasonNumber,
                                      episodeNumber: episode.number,
                                      showCatalog: true,
                                    ),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('播放'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _Block(
                        title: '简介',
                        child: Text(
                          (episode.overview?.trim().isNotEmpty ?? false) ? episode.overview!.trim() : '暂无简介',
                          style: _body(color: FolioColors.inkMuted),
                        ),
                      ),
                      if (facts.isNotEmpty)
                        _Block(
                          title: '基本信息',
                          child: _Facts(facts: [for (final row in facts) WorkFact(row.$1, row.$2)]),
                        ),
                      if (detail.externalIds.isNotEmpty)
                        _Block(
                          title: '外部 ID',
                          child: _Facts(
                            facts: [
                              for (final item in detail.externalIds)
                                WorkFact(item.title, item.externalId, href: item.urlFor('episode')),
                            ],
                          ),
                        ),
                      if (detail.videos.isNotEmpty)
                        _Block(
                          title: '相关视频',
                          child: _VideoList(videos: detail.videos),
                        ),
                      if (arts.isNotEmpty)
                        _Block(
                          title: '图片素材（${episode.artworks.length}）',
                          child: _ArtworkGroups(groups: arts),
                        ),
                      if (cast.isNotEmpty)
                        _Block(
                          title: '演员 / 嘉宾',
                          child: _PeopleRail(
                            people: [
                              for (final person in cast)
                                _Face(
                                  name: person.name,
                                  subtitle: person.subtitle,
                                  imageUrl: person.profileUrl,
                                  provider: person.provider,
                                  externalId: person.externalId,
                                ),
                            ],
                          ),
                        ),
                      if (crew.isNotEmpty)
                        _Block(
                          title: '制作人员',
                          child: _PeopleRail(
                            people: [
                              for (final person in crew)
                                _Face(
                                  name: person.name,
                                  subtitle: person.subtitle,
                                  imageUrl: person.profileUrl,
                                  provider: person.provider,
                                  externalId: person.externalId,
                                ),
                            ],
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: _background.withValues(alpha: barFade),
                child: Padding(
                  padding: EdgeInsets.only(top: top),
                  child: _BackBar(
                    workId: detail.workId,
                    seasonNumber: detail.seasonNumber,
                    files: episode.files,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({
    required this.workId,
    required this.seasonNumber,
    this.files = const [],
  });

  final int workId;
  final int seasonNumber;
  final List<LibraryFileBrief> files;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(RouterPath.season(workId, seasonNumber));
              }
            },
            icon: const Icon(Icons.arrow_back, color: FolioColors.ink),
            tooltip: '返回',
          ),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: '更多',
            padding: EdgeInsets.zero,
            color: FolioColors.bgPanel,
            onSelected: (value) {
              if (value == 'playlist') {
                showFolioSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PlaylistPickerSheet(workId: workId),
                );
                return;
              }
              showFolioSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => VideoInfoSheet(files: files),
              );
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'playlist',
                child: Text('添加到播放列表', style: TextStyle(color: FolioColors.ink)),
              ),
              if (files.isNotEmpty)
                const PopupMenuItem(
                  value: 'info',
                  child: Text('视频信息', style: TextStyle(color: FolioColors.ink)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: folioDisplay(size: 18, color: FolioColors.copper).copyWith(fontFamily: folioSystemFont())),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<WorkFact> facts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final fact in facts)
              SizedBox(
                width: width,
                child: DecoratedBox(
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FolioColors.line))),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fact.label, style: _caption(size: 11, color: FolioColors.inkFaint)),
                        const SizedBox(height: 2),
                        if (fact.href != null)
                          GestureDetector(
                            onTap: () => _openExternal(fact.href!),
                            child: Text(fact.value, style: _body(color: FolioColors.teal)),
                          )
                        else
                          Text(fact.value, style: _body()),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _Face {
  const _Face({
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    this.provider = '',
    this.externalId = '',
  });

  final String name;
  final String subtitle;
  final String? imageUrl;
  final String provider;
  final String externalId;

  bool get canOpen => provider.trim().isNotEmpty && externalId.trim().isNotEmpty;
}

class _PeopleRail extends StatelessWidget {
  const _PeopleRail({required this.people});

  final List<_Face> people;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final person = people[index];
          final tile = SizedBox(
            width: 84,
            child: Column(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: PosterImage(url: person.imageUrl, fallback: person.name.isEmpty ? '·' : person.name.characters.first),
                  ),
                ),
                const SizedBox(height: 6),
                Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: _caption(color: FolioColors.ink, size: 13)),
                Text(person.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _caption(size: 11)),
              ],
            ),
          );
          if (!person.canOpen) return tile;
          return InkWell(
            onTap: () => context.push(RouterPath.person(person.provider, person.externalId)),
            borderRadius: BorderRadius.circular(12),
            child: tile,
          );
        },
      ),
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList({required this.videos});

  final List<WorkVideo> videos;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final video in videos)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(video.heading, style: _body()),
                      Text(video.meta, style: _caption(size: 12)),
                    ],
                  ),
                ),
                if (video.url != null)
                  GestureDetector(
                    onTap: () => _openExternal(video.url!),
                    child: Text('打开', style: _caption(color: FolioColors.teal, size: 13)),
                  )
                else if (video.key != null && video.key!.isNotEmpty)
                  Text(video.key!, style: _caption(size: 12)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ArtworkGroups extends StatelessWidget {
  const _ArtworkGroups({required this.groups});

  final List<({String kind, List<WorkArtwork> items})> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          Text(artworkKindLabel(group.kind), style: _caption(color: FolioColors.ink, size: 13)),
          const SizedBox(height: 8),
          SizedBox(
            height: group.kind == 'still' || group.kind == 'backdrop' ? 94 : 144,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final art = group.items[index];
                final width = group.kind == 'still' || group.kind == 'backdrop' ? 168.0 : 96.0;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: width,
                    child: CachedNetworkImage(
                      imageUrl: art.remoteUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: folioMemCachePx(context, width),
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => PosterImage.placeholder(),
                      errorWidget: (_, _, _) => PosterImage.placeholder(),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
