import 'package:folio/api/entity/models.dart';

/// 播放准备页展示用的标题与元数据。
class PlaybackPrepareMeta {
  const PlaybackPrepareMeta({
    this.title,
    this.subtitle,
    this.playbackTitle,
    this.kindLabel,
    this.year,
    this.runtimeLabel,
    this.genres = const [],
    this.ratings = const [],
  });

  final String? title;
  final String? subtitle;
  /// 顶栏播放标题（刮削名）；空则回退 [title]。
  final String? playbackTitle;
  final String? kindLabel;
  final int? year;
  final String? runtimeLabel;
  final List<String> genres;
  final List<WorkRating> ratings;

  /// 顶栏展示：刮削标题优先，否则准备页标题。
  String? get chromeTitle {
    final play = playbackTitle?.trim();
    if (play != null && play.isNotEmpty) return play;
    final fall = title?.trim();
    if (fall != null && fall.isNotEmpty) return fall;
    return null;
  }

  factory PlaybackPrepareMeta.fromWork(WorkDetail work) {
    return PlaybackPrepareMeta(
      title: work.displayTitle,
      playbackTitle: work.displayTitle,
      kindLabel: work.isSeries ? '剧集' : '电影',
      year: work.year,
      runtimeLabel: work.runtimeMinutes == null ? null : '${work.runtimeMinutes} 分钟',
      genres: work.genres.take(3).toList(),
      ratings: work.sortedRatings,
    );
  }

  factory PlaybackPrepareMeta.fromEpisode(EpisodeDetail detail) {
    final episode = detail.episode;
    final air = episode.airDate?.trim();
    int? year;
    if (air != null && air.length >= 4) {
      year = int.tryParse(air.substring(0, 4));
    }
    final score = episode.voteAverage;
    return PlaybackPrepareMeta(
      title: episode.heading,
      subtitle: '${detail.workTitle} · ${detail.seasonHeading}',
      playbackTitle: seriesPlaybackTitle(
        workTitle: detail.workTitle,
        seasonNumber: detail.seasonNumber,
        episodeNumber: episode.number,
        episodeTitle: episode.title,
      ),
      kindLabel: '剧集',
      year: year,
      runtimeLabel: episode.runtimeMinutes == null ? null : '${episode.runtimeMinutes} 分钟',
      ratings: score == null || score <= 0
          ? const []
          : [
              WorkRating(
                provider: 'tmdb',
                value: score,
                votes: episode.voteCount,
                scale: 10,
              ),
            ],
    );
  }

  /// 类型 · 年份 · 片长
  String? get metaLine {
    final parts = <String>[
      if (kindLabel != null && kindLabel!.isNotEmpty) kindLabel!,
      if (year != null) '$year',
      if (runtimeLabel != null && runtimeLabel!.isNotEmpty) runtimeLabel!,
    ];
    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }

  String? get genresLine {
    if (genres.isEmpty) return null;
    return genres.join('  ·  ');
  }
}

/// 剧集顶栏：`作品名 第1季第2集 集标题`
String seriesPlaybackTitle({
  required String workTitle,
  required int seasonNumber,
  required int episodeNumber,
  String? episodeTitle,
}) {
  final work = workTitle.trim();
  final base = work.isEmpty
      ? '第${seasonNumber}季第${episodeNumber}集'
      : '$work 第${seasonNumber}季第${episodeNumber}集';
  final name = episodeTitle?.trim();
  if (name == null || name.isEmpty) return base;
  return '$base $name';
}
