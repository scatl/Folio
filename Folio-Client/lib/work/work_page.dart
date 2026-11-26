import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/artwork_color.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/widget/rating_chip.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/tasks/manual_match_page.dart';
import 'package:folio/work/playlist_sheet.dart';
import 'package:folio/work/video_info_sheet.dart';
import 'package:folio/work/work_view_model.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class WorkPage extends ConsumerWidget {
  const WorkPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(workProvider(id));
    ref.listen(workProvider(id), (previous, next) {
      final target = next.redirectWorkId;
      if (target != null && target != id && context.mounted) {
        context.go(RouterPath.work(target));
      }
      final message = next.error;
      if (message != null &&
          next.work != null &&
          message != previous?.error &&
          context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    });
    final work = ui.work;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: work == null
            ? _Status(loading: ui.loading, error: ui.error, onRetry: () => ref.read(workProvider(id).notifier).load())
            : _DetailBody(work: work, parts: ui.parts, progress: ui.progress),
      ),
    );
  }
}

TextStyle _body({Color color = FolioColors.ink, double height = 1.55}) {
  return TextStyle(fontFamily: folioSystemFont(), fontSize: 15, height: height, color: color);
}

TextStyle _caption({Color color = FolioColors.inkMuted, double size = 13, FontStyle? style}) {
  return TextStyle(fontFamily: folioSystemFont(), fontSize: size, color: color, fontStyle: style);
}

class _Status extends StatelessWidget {
  const _Status({required this.loading, required this.error, required this.onRetry});

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BackBar(),
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
  const _DetailBody({required this.work, required this.parts, this.progress});

  final WorkDetail work;
  final List<CollectionPart> parts;
  final PlaybackProgress? progress;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  final _scroll = ScrollController();
  double _offset = 0;
  Color _background = FolioColors.bgDeep;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!mounted) return;
      setState(() => _offset = _scroll.offset);
    });
    _loadBackground();
  }

  @override
  void didUpdateWidget(covariant _DetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.work.backdropUrl ?? widget.work.posterUrl;
    final previous = oldWidget.work.backdropUrl ?? oldWidget.work.posterUrl;
    if (next != previous) _loadBackground();
  }

  Future<void> _loadBackground() async {
    final url = widget.work.backdropUrl ?? widget.work.posterUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _background = FolioColors.bgDeep);
      return;
    }
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
    final work = widget.work;
    final top = MediaQuery.paddingOf(context).top;
    final original = work.originalTitle.trim();
    final showOriginal = original.isNotEmpty && original != work.displayTitle;
    return LayoutBuilder(
      builder: (context, constraints) {
        final backdropHeight = top + constraints.maxWidth * 2 / 3;
        final shift = _offset * 0.72;
        final barFade = (_offset / (backdropHeight * 0.55)).clamp(0.0, 1.0);
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
                  PosterImage(url: work.backdropUrl ?? work.posterUrl, fallback: work.displayTitle),
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
                            Text(work.displayTitle, textAlign: TextAlign.center, style: folioDisplay(size: 26)),
                            if (showOriginal)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(original, textAlign: TextAlign.center, style: _caption()),
                              ),
                            if (work.tagline != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  work.tagline!,
                                  textAlign: TextAlign.center,
                                  style: _caption(color: FolioColors.copper, style: FontStyle.italic),
                                ),
                              ),
                            const SizedBox(height: 10),
                            _MetaLine(work: work),
                            if ((!work.isSeries && work.files.isNotEmpty) ||
                                (work.isSeries &&
                                    work.seasons.any((s) => s.localEpisodeCount > 0))) ...[
                              const SizedBox(height: 16),
                              Consumer(
                                builder: (context, ref, _) {
                                  final progress = widget.progress;
                                  final continuing = progress != null;
                                  final subtitle = continuing
                                      ? [
                                          if (progress.episodeLabel.isNotEmpty) progress.episodeLabel,
                                          if (progress.resumePositionMs != null && progress.resumePositionMs! > 0)
                                            '已看至 ${formatPlaybackClock(progress.resumePositionMs!)}'
                                          else if (progress.episodeLabel.isNotEmpty)
                                            '下一集'
                                          else
                                            '继续播放',
                                        ].join(' · ')
                                      : null;
                                  return Column(
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => playWorkDetail(
                                          context,
                                          ref,
                                          work,
                                          showCollectionCatalog: widget.parts.any((part) => part.hasLocalMedia),
                                          progress: progress,
                                        ),
                                        icon: const Icon(Icons.play_arrow_rounded),
                                        label: Text(continuing ? '继续观看' : '播放'),
                                      ),
                                      if (subtitle != null && subtitle.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(subtitle, style: _caption(size: 12)),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            if (work.sortedRatings.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: [for (final rating in work.sortedRatings) RatingChip(rating: rating)],
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
                      if (widget.parts.isNotEmpty || (work.collectionExternalId?.trim().isNotEmpty ?? false))
                        _Block(
                          title: work.collectionName?.trim().isNotEmpty == true ? work.collectionName!.trim() : '系列',
                          trailing: work.collectionExternalId?.trim().isNotEmpty == true
                              ? TextButton(
                                  onPressed: () => context.push(RouterPath.collection(work.collectionExternalId!.trim())),
                                  child: const Text('查看系列'),
                                )
                              : null,
                          child: widget.parts.isEmpty
                              ? null
                              : _MateRail(parts: widget.parts, currentId: work.id),
                        ),
                      if (work.seasons.isNotEmpty) _Block(title: '季（${work.seasons.length}）', child: _SeasonRail(workId: work.id, seasons: work.seasons)),
                      if (work.overview != null) _Block(title: '简介', child: Text(work.overview!, style: _body())),
                      if (work.facts.isNotEmpty) _Block(title: '基本信息', child: _Facts(facts: work.facts)),
                      if (work.keywords.isNotEmpty) _Block(title: '关键词', child: _KeywordWrap(keywords: work.keywords)),
                      if (work.sortedRatings.isNotEmpty)
                        _Block(
                          title: '评分',
                          child: _Facts(
                            facts: [
                              for (final rating in work.sortedRatings)
                                WorkFact(
                                  rating.kindLabel != null && rating.kindLabel != rating.label
                                      ? '${rating.label} · ${rating.kindLabel}'
                                      : rating.label,
                                  '${rating.display}${rating.votes != null ? rating.votesLabel : ''}',
                                ),
                            ],
                          ),
                        ),
                      if (work.externalIds.isNotEmpty)
                        _Block(
                          title: '外部 ID',
                          child: _Facts(
                            facts: [
                              for (final item in work.externalIds)
                                WorkFact(item.title, item.externalId, href: item.urlFor(work.kind)),
                            ],
                          ),
                        ),
                      if (work.countries.isNotEmpty) _Block(title: '国家 / 地区', child: _CountryList(countries: work.countries)),
                      if (work.spokenLanguages.isNotEmpty) _Block(title: '对白语言', child: _LanguageList(languages: work.spokenLanguages)),
                      if (work.companies.isNotEmpty) _Block(title: '公司', child: _CompanyList(companies: work.companies)),
                      if (work.videos.isNotEmpty) _Block(title: '相关视频', child: _VideoList(videos: work.videos)),
                      if (work.artworksByKind.isNotEmpty) _Block(title: '图片素材（${work.artworks.length}）', child: _ArtworkGroups(groups: work.artworksByKind)),
                      if (work.cast.isNotEmpty)
                        _Block(
                          title: '演员',
                          child: _PeopleRail(
                            people: [
                              for (final person in work.cast)
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
                      if (work.crew.isNotEmpty)
                        _Block(
                          title: '制作人员',
                          child: _PeopleRail(
                            people: [
                              for (final person in work.crew)
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
                      if (work.people.isNotEmpty)
                        _Block(
                          title: '关联人物',
                          child: _PeopleRail(
                            people: [
                              for (final person in work.people)
                                _Face(
                                  name: person.name,
                                  subtitle: person.subtitle,
                                  imageUrl: person.imageUrl,
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
                  child: _BackBar(work: work),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BackBar extends ConsumerWidget {
  const _BackBar({this.work});

  final WorkDetail? work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = work;
    final files = current?.files ?? const <LibraryFileBrief>[];
    final canRematch = ref.watch(
      sessionProvider.select((session) => session.isAdmin || session.hasWriteLibrary),
    );
    final hasTmdb =
        current?.externalIds.any((item) => item.provider.trim().toLowerCase() == 'tmdb') == true;
    final showRematch = canRematch && files.isNotEmpty;
    final showRefreshMetadata = hasTmdb && files.isEmpty;
    final showVideo = current != null && !current.isSeries && files.isNotEmpty;
    final playable = current != null &&
        ((!current.isSeries && files.isNotEmpty) ||
            (current.isSeries && current.seasons.any((season) => season.localEpisodeCount > 0)));
    final ui = current == null ? null : ref.watch(workProvider(current.id));
    final refreshing = ui?.refreshing == true;
    final watched = ui?.watchState == 'watched';
    final series = current?.isSeries == true;
    return SizedBox(
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
          const Spacer(),
          if (playable && ui != null) ...[
            IconButton(
              tooltip: watched
                  ? (series ? '整部标为未看' : '标为未看')
                  : (series ? '整部标为已看' : '标为已看'),
              onPressed: () => ref.read(workProvider(current.id).notifier).setWatched(!watched),
              icon: Icon(
                watched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                color: watched ? FolioColors.copper : FolioColors.ink,
              ),
            ),
            IconButton(
              tooltip: ui.savingWant ? '保存中…' : (ui.wanted ? '已想看' : '想看'),
              onPressed: ui.savingWant
                  ? null
                  : () => ref.read(workProvider(current.id).notifier).setWanted(!ui.wanted),
              icon: Icon(
                ui.wanted ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: ui.wanted ? FolioColors.copper : FolioColors.ink,
              ),
            ),
          ],
          if (current != null)
            _MoreMenu(
              entries: [
                (_MoreAction.playlist, '添加到播放列表'),
                if (showRematch) (_MoreAction.rematch, '重新匹配'),
                if (showRefreshMetadata) (_MoreAction.refreshMetadata, refreshing ? '刷新中…' : '刷新元数据'),
                if (showVideo) (_MoreAction.videoInfo, '视频信息'),
              ],
              onSelected: (action) {
                if (action == _MoreAction.playlist) {
                  showFolioSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PlaylistPickerSheet(workId: current.id),
                  );
                } else if (action == _MoreAction.rematch) {
                  _rematch(context, files, current.kind);
                } else if (action == _MoreAction.refreshMetadata) {
                  if (refreshing) return;
                  ref.read(workProvider(current.id).notifier).refresh();
                } else {
                  _videoInfo(context, files);
                }
              },
            ),
        ],
      ),
    );
  }
}

enum _MoreAction { playlist, rematch, refreshMetadata, videoInfo }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.entries, required this.onSelected});

  final List<(_MoreAction, String)> entries;
  final ValueChanged<_MoreAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MoreAction>(
      tooltip: '更多',
      padding: EdgeInsets.zero,
      color: FolioColors.bgPanel,
      icon: const Icon(Icons.more_vert, color: FolioColors.ink),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries)
          PopupMenuItem(value: entry.$1, child: Text(entry.$2, style: const TextStyle(color: FolioColors.ink))),
      ],
    );
  }
}

void _videoInfo(BuildContext context, List<LibraryFileBrief> files) {
  showFolioSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => VideoInfoSheet(files: files),
  );
}

Future<void> _rematch(BuildContext context, List<LibraryFileBrief> files, String kind) async {
  if (files.isEmpty) return;
  final choice = await context.push<MatchChoice>(
    RouterPath.manualMatch(files.first.id),
    extra: ManualMatchArgs.files(files: files, kind: kind),
  );
  if (choice == null || !context.mounted) return;
  try {
    await ProviderScope.containerOf(context).read(apiClientProvider).post<Object?>(
      ApiPath.libraryFiles.match(choice.fileId),
        data: {
          'kind': choice.candidate.kind,
          'tmdbId': choice.tmdbId,
          'year': ?choice.year,
          'season': ?choice.season,
          'episode': ?choice.episode,
          'scope': ?choice.scope,
        },
    );
  } on ApiFailure catch (failure) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.work});

  final WorkDetail work;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (work.year != null) '${work.year}',
      ...work.genres.take(3),
      if (work.runtimeMinutes != null) '${work.runtimeMinutes} 分钟',
      if (work.numberOfSeasons != null) '${work.numberOfSeasons} 季',
      if (work.numberOfEpisodes != null) '${work.numberOfEpisodes} 集',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  ·  '), textAlign: TextAlign.center, style: _caption(size: 13));
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, this.child, this.trailing});

  final String title;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: folioDisplay(size: 18, color: FolioColors.copper))),
              ?trailing,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );
  }
}

class _SeasonRail extends StatelessWidget {
  const _SeasonRail({required this.workId, required this.seasons});

  final int workId;
  final List<SeasonCard> seasons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final season = seasons[index];
          return GestureDetector(
            onTap: () => context.push(RouterPath.season(workId, season.seasonNumber)),
            child: SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PosterImage(url: season.posterUrl, fallback: 'S${season.seasonNumber}'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(season.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: _caption(color: FolioColors.ink, size: 13)),
                  Text('${season.localEpisodeCount} 集本地', style: _caption(size: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MateRail extends StatelessWidget {
  const _MateRail({required this.parts, required this.currentId});

  final List<CollectionPart> parts;
  final int currentId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: parts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final part = parts[index];
          final current = part.workId == currentId;
          return SizedBox(
            width: 108,
            child: _CollectionPoster(part: part, current: current),
          );
        },
      ),
    );
  }
}

class _CollectionPoster extends StatelessWidget {
  const _CollectionPoster({required this.part, required this.current});

  final CollectionPart part;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: current
          ? null
          : () {
              final workId = part.workId;
              if (workId != null) {
                context.push(RouterPath.work(workId));
                return;
              }
              final tmdbId = part.tmdbId.trim();
              if (tmdbId.isEmpty) return;
              context.push(RouterPath.workExternal(provider: 'tmdb', externalId: tmdbId, kind: 'movie'));
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: current ? FolioColors.copper : FolioColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: part.posterUrl, fallback: part.title),
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 4,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (current) const _PosterTag('当前', accent: true),
                          if (part.hasLocalMedia) const _PosterTag('本地'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            part.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _caption(color: FolioColors.ink, size: 12),
          ),
          if (part.year != null)
            Text('${part.year}', style: _caption(size: 11)),
        ],
      ),
    );
  }
}

class _PosterTag extends StatelessWidget {
  const _PosterTag(this.label, {this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xB8080A0E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent ? FolioColors.copper : FolioColors.line),
      ),
      child: Text(label, style: _caption(size: 10, color: accent ? FolioColors.copper : FolioColors.inkMuted)),
    );
  }
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
                Text(
                  person.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caption(size: 11),
                ),
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

Future<void> _openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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

class _KeywordWrap extends StatelessWidget {
  const _KeywordWrap({required this.keywords});

  final List<WorkKeyword> keywords;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final keyword in keywords)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x0AF2EFE8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: FolioColors.lineStrong),
            ),
            child: Text(keyword.name, style: _caption(size: 13)),
          ),
      ],
    );
  }
}

class _CountryList extends StatelessWidget {
  const _CountryList({required this.countries});

  final List<WorkCountry> countries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final country in countries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(country.label, style: _body()),
                const SizedBox(width: 8),
                Expanded(child: Text('${country.code} · ${country.kind}', style: _caption())),
              ],
            ),
          ),
      ],
    );
  }
}

class _LanguageList extends StatelessWidget {
  const _LanguageList({required this.languages});

  final List<WorkLanguage> languages;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final language in languages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(language.label, style: _body()),
                const SizedBox(width: 8),
                Text(language.code, style: _caption()),
              ],
            ),
          ),
      ],
    );
  }
}

class _CompanyList extends StatelessWidget {
  const _CompanyList({required this.companies});

  final List<WorkCompany> companies;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final company in companies)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: company.logoUrl == null || company.logoUrl!.isEmpty
                        ? PosterImage.placeholder()
                        : CachedNetworkImage(
                            imageUrl: company.logoUrl!,
                            fit: BoxFit.contain,
                            memCacheWidth: folioMemCachePx(context, 42),
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (_, _) => PosterImage.placeholder(),
                            errorWidget: (_, _, _) => PosterImage.placeholder(),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.name, style: _body()),
                      Text(
                        [
                          company.roleLabel,
                          if (company.originCountry != null && company.originCountry!.trim().isNotEmpty) company.originCountry!.trim(),
                        ].join(' · '),
                        style: _caption(size: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
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
            height: _artHeight(group.kind),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final art = group.items[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: _artWidth(group.kind),
                    child: CachedNetworkImage(
                      imageUrl: art.remoteUrl,
                      fit: group.kind == 'logo' ? BoxFit.contain : BoxFit.cover,
                      memCacheWidth: folioMemCachePx(context, _artWidth(group.kind)),
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

  double _artWidth(String kind) {
    switch (kind) {
      case 'backdrop':
      case 'still':
      case 'collection_backdrop':
        return 168;
      case 'logo':
        return 120;
      default:
        return 96;
    }
  }

  double _artHeight(String kind) {
    switch (kind) {
      case 'backdrop':
      case 'still':
      case 'collection_backdrop':
        return 94;
      case 'logo':
        return 64;
      default:
        return 144;
    }
  }
}

