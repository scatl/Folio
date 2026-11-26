import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/play/play_library.dart';
import 'package:folio/play/player_page.dart';

String formatPlaybackClock(int ms) {
  final total = (ms / 1000).floor().clamp(0, 1 << 30);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

Future<PlaybackProgress?> fetchFileProgress(ApiClient api, int libraryFileId) async {
  try {
    return await api.get(
      ApiPath.playback.progress,
      queryParameters: {'libraryFileId': libraryFileId},
      parser: jsonParser(PlaybackProgress.fromJson),
    );
  } on ApiFailure {
    return null;
  }
}

Future<PlaybackProgress?> fetchWorkProgress(ApiClient api, int workId) async {
  try {
    return await api.get(
      ApiPath.playback.workProgress(workId),
      parser: jsonParser(PlaybackProgress.fromJson),
    );
  } on ApiFailure {
    return null;
  }
}

Future<void> playLibraryFile(
  BuildContext context,
  WidgetRef ref, {
  required int fileId,
  required String fileName,
  String? posterUrl,
  PlaybackPrepareMeta? meta,
  PlaybackCatalogContext? catalog,
  int? playlistId,
  int? resumePositionMs,
  bool fetchResume = true,
}) async {
  final api = ref.read(apiClientProvider);
  var resume = resumePositionMs;
  if (resume == null && fetchResume) {
    final progress = await fetchFileProgress(api, fileId);
    resume = progress?.resumePositionMs;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        api: api,
        fileId: fileId,
        fileName: fileName,
        posterUrl: posterUrl,
        prepareMeta: meta,
        catalog: catalog,
        playlistId: playlistId,
        resumePositionMs: resume,
      ),
    ),
  );
}

Future<void> playContinueItem(
  BuildContext context,
  WidgetRef ref,
  ContinueWatchItem item,
) {
  return playLibraryFile(
    context,
    ref,
    fileId: item.libraryFileId,
    fileName: item.fileName ?? 'video',
    posterUrl: item.posterUrl,
    resumePositionMs: item.resumePositionMs,
    fetchResume: false,
    catalog: PlaybackCatalogContext(
      workId: item.workId,
      kind: item.kind,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      showCatalog: true,
    ),
    meta: PlaybackPrepareMeta(
      title: item.workTitle,
      subtitle: item.subtitle,
      playbackTitle: item.kind == 'series' &&
              item.seasonNumber != null &&
              item.episodeNumber != null
          ? seriesPlaybackTitle(
              workTitle: item.workTitle,
              seasonNumber: item.seasonNumber!,
              episodeNumber: item.episodeNumber!,
              episodeTitle: item.episodeTitle,
            )
          : item.workTitle,
      kindLabel: item.kind == 'series' ? '剧集' : '电影',
    ),
  );
}

Future<void> playWorkDetail(
  BuildContext context,
  WidgetRef ref,
  WorkDetail work, {
  bool showCollectionCatalog = false,
  PlaybackProgress? progress,
}) async {
  final api = ref.read(apiClientProvider);
  final resolved = progress ?? await fetchWorkProgress(api, work.id);
  if (!context.mounted) return;

  if (resolved != null) {
    await playLibraryFile(
      context,
      ref,
      fileId: resolved.libraryFileId,
      fileName: resolved.fileName ?? 'video',
      posterUrl: work.posterUrl ?? work.backdropUrl,
      resumePositionMs: resolved.resumePositionMs,
      fetchResume: false,
      meta: work.isSeries &&
              resolved.seasonNumber != null &&
              resolved.episodeNumber != null
          ? PlaybackPrepareMeta(
              title: resolved.episodeTitle?.trim().isNotEmpty == true
                  ? resolved.episodeTitle
                  : work.displayTitle,
              subtitle: [
                work.displayTitle,
                if (resolved.episodeLabel.isNotEmpty) resolved.episodeLabel,
              ].join(' · '),
              playbackTitle: seriesPlaybackTitle(
                workTitle: work.displayTitle,
                seasonNumber: resolved.seasonNumber!,
                episodeNumber: resolved.episodeNumber!,
                episodeTitle: resolved.episodeTitle,
              ),
              kindLabel: '剧集',
              year: work.year,
              genres: work.genres.take(3).toList(),
              ratings: work.sortedRatings,
            )
          : PlaybackPrepareMeta.fromWork(work),
      catalog: PlaybackCatalogContext(
        workId: work.id,
        kind: work.kind,
        seasonNumber: resolved.seasonNumber,
        episodeNumber: resolved.episodeNumber,
        showCatalog: work.isSeries || showCollectionCatalog,
      ),
    );
    return;
  }

  if (!work.isSeries) {
    await playLibraryFiles(
      context,
      ref,
      work.files,
      posterUrl: work.posterUrl ?? work.backdropUrl,
      meta: PlaybackPrepareMeta.fromWork(work),
      catalog: PlaybackCatalogContext(
        workId: work.id,
        kind: 'movie',
        showCatalog: showCollectionCatalog,
      ),
    );
    return;
  }

  final season = work.seasons.where((s) => s.localEpisodeCount > 0).toList()
    ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
  if (season.isEmpty) return;
  await playSeasonFirstEpisode(
    context,
    ref,
    workId: work.id,
    workTitle: work.displayTitle,
    seasonNumber: season.first.seasonNumber,
    posterUrl: work.posterUrl ?? work.backdropUrl,
    genres: work.genres,
    ratings: work.sortedRatings,
  );
}

Future<void> playSeasonFirstEpisode(
  BuildContext context,
  WidgetRef ref, {
  required int workId,
  required String workTitle,
  required int seasonNumber,
  String? posterUrl,
  List<String> genres = const [],
  List<WorkRating> ratings = const [],
  PlaybackProgress? preferProgress,
}) async {
  final api = ref.read(apiClientProvider);
  if (preferProgress != null &&
      preferProgress.seasonNumber == seasonNumber &&
      preferProgress.libraryFileId > 0) {
    await playLibraryFile(
      context,
      ref,
      fileId: preferProgress.libraryFileId,
      fileName: preferProgress.fileName ?? 'video',
      posterUrl: posterUrl,
      resumePositionMs: preferProgress.resumePositionMs,
      fetchResume: false,
      catalog: PlaybackCatalogContext(
        workId: workId,
        kind: 'series',
        seasonNumber: preferProgress.seasonNumber,
        episodeNumber: preferProgress.episodeNumber,
        showCatalog: true,
      ),
      meta: PlaybackPrepareMeta(
        title: preferProgress.episodeTitle ?? workTitle,
        subtitle: '$workTitle · 第 $seasonNumber 季',
        playbackTitle: preferProgress.episodeNumber != null
            ? seriesPlaybackTitle(
                workTitle: workTitle,
                seasonNumber: seasonNumber,
                episodeNumber: preferProgress.episodeNumber!,
                episodeTitle: preferProgress.episodeTitle,
              )
            : workTitle,
        kindLabel: '剧集',
        genres: genres.take(3).toList(),
        ratings: ratings,
      ),
    );
    return;
  }

  final detail = await api.get(
    ApiPath.works.season(workId, seasonNumber),
    parser: jsonParser(SeasonDetail.fromJson),
  );
  if (!context.mounted) return;
  EpisodeRow? episode;
  for (final row in detail.episodes) {
    if (row.files.isNotEmpty) {
      episode = row;
      break;
    }
  }
  if (episode == null) return;
  await playLibraryFiles(
    context,
    ref,
    episode.files,
    posterUrl: episode.stillUrl ?? posterUrl,
    meta: PlaybackPrepareMeta(
      title: episode.heading,
      subtitle: '$workTitle · ${detail.heading}',
      playbackTitle: seriesPlaybackTitle(
        workTitle: workTitle,
        seasonNumber: seasonNumber,
        episodeNumber: episode.number,
        episodeTitle: episode.title,
      ),
      kindLabel: '剧集',
      runtimeLabel: episode.runtimeMinutes == null ? null : '${episode.runtimeMinutes} 分钟',
      genres: genres.take(3).toList(),
      ratings: ratings,
    ),
    catalog: PlaybackCatalogContext(
      workId: workId,
      kind: 'series',
      seasonNumber: seasonNumber,
      episodeNumber: episode.number,
      showCatalog: true,
    ),
  );
}
