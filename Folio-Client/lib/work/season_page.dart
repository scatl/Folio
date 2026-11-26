import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/play/play_continue.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/theme/artwork_color.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:folio/work/season_ui_state.dart';
import 'package:folio/work/season_view_model.dart';
import 'package:go_router/go_router.dart';

class SeasonPage extends ConsumerWidget {
  const SeasonPage({super.key, required this.workId, required this.seasonNumber});

  final int workId;
  final int seasonNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = SeasonKey(workId, seasonNumber);
    final ui = ref.watch(seasonProvider(key));
    final detail = ui.detail;
    return FolioBackdrop(
      child: ArtworkTint(
        url: detail?.posterUrl,
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
                        context.go(RouterPath.work(workId));
                      }
                    },
                    icon: const Icon(Icons.arrow_back, color: FolioColors.ink),
                    tooltip: '返回',
                  ),
                  Expanded(
                    child: Text(
                      detail?.workTitle ?? '',
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
                                Text(ui.error ?? '加载失败', style: _seasonText(color: FolioColors.inkMuted)),
                                TextButton(onPressed: () => ref.read(seasonProvider(key).notifier).load(), child: const Text('重试')),
                              ],
                            ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        _SeasonHero(detail: detail),
                        if (detail.episodes.any((e) => e.files.isNotEmpty)) ...[
                          const SizedBox(height: 18),
                          _SeasonPlayButton(
                            workId: workId,
                            detail: detail,
                            progress: ui.progress,
                          ),
                        ],
                        const SizedBox(height: 22),
                        Text('剧集（${detail.episodes.length}）', style: folioDisplay(size: 18, color: FolioColors.copper).copyWith(fontFamily: folioSystemFont())),
                        const SizedBox(height: 12),
                        if (detail.episodes.isEmpty)
                          Text('这一季还没有分集资料', style: _seasonText(color: FolioColors.inkMuted))
                        else
                          for (var i = 0; i < detail.episodes.length; i++) ...[
                            _EpisodeTile(
                              workId: workId,
                              seasonNumber: detail.seasonNumber,
                              episode: detail.episodes[i],
                            ),
                            if (i < detail.episodes.length - 1) const Divider(height: 28, thickness: 1, color: FolioColors.line),
                          ],
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

TextStyle _seasonText({
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

class _SeasonPlayButton extends ConsumerWidget {
  const _SeasonPlayButton({
    required this.workId,
    required this.detail,
    this.progress,
  });

  final int workId;
  final SeasonDetail detail;
  final PlaybackProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inSeason = progress != null && progress!.seasonNumber == detail.seasonNumber;
    final label = inSeason ? '继续观看' : '播放本季';
    final hint = inSeason
        ? [
            if (progress!.episodeLabel.isNotEmpty) progress!.episodeLabel,
            if (progress!.resumePositionMs != null && progress!.resumePositionMs! > 0)
              '已看至 ${formatPlaybackClock(progress!.resumePositionMs!)}'
            else
              '下一集',
          ].join(' · ')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: () => playSeasonFirstEpisode(
            context,
            ref,
            workId: workId,
            workTitle: detail.workTitle,
            seasonNumber: detail.seasonNumber,
            posterUrl: detail.posterUrl,
            preferProgress: inSeason ? progress : null,
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(label),
        ),
        if (hint != null && hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(hint, style: _seasonText(color: FolioColors.inkMuted, size: 12)),
          ),
      ],
    );
  }
}

class _SeasonHero extends StatelessWidget {
  const _SeasonHero({required this.detail});

  final SeasonDetail detail;

  @override
  Widget build(BuildContext context) {
    final overview = detail.overview?.trim();
    final chips = [
      '${detail.localEpisodeCount} 集本地',
      if (detail.airDate != null && detail.airDate!.isNotEmpty) detail.airDate!,
      if (detail.episodeCount != null) '共 ${detail.episodeCount} 集',
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
                child: PosterImage(url: detail.posterUrl, fallback: 'S${detail.seasonNumber}'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(detail.heading, style: folioDisplay(size: 26).copyWith(fontFamily: folioSystemFont())),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final chip in chips) _SeasonChip(label: chip)],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (overview != null && overview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(overview, style: _seasonText(color: FolioColors.inkMuted, size: 14, height: 1.5)),
          ),
      ],
    );
  }
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({required this.label});

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
      child: Text(label, style: _seasonText(color: FolioColors.inkMuted, size: 12)),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.workId,
    required this.seasonNumber,
    required this.episode,
  });

  final int workId;
  final int seasonNumber;
  final EpisodeRow episode;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (episode.files.isNotEmpty) '本地',
      if (episode.airDate != null && episode.airDate!.isNotEmpty) episode.airDate!,
      if (episode.runtimeMinutes != null) '${episode.runtimeMinutes} 分钟',
    ].join(' · ');
    final overview = episode.overview?.trim();
    return InkWell(
      onTap: () => context.push(RouterPath.episode(workId, seasonNumber, episode.number)),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 128,
                    height: 72,
                    child: PosterImage(url: episode.stillUrl, fallback: '${episode.number}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        episode.heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _seasonText(weight: FontWeight.w600),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(meta, style: _seasonText(color: FolioColors.inkFaint, size: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (overview != null && overview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(overview, maxLines: 3, overflow: TextOverflow.ellipsis, style: _seasonText(color: FolioColors.inkMuted, size: 13, height: 1.45)),
              ),
          ],
        ),
      ),
    );
  }
}
