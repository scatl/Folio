/// 播放页选集所需的作品上下文。
class PlaybackCatalogContext {
  const PlaybackCatalogContext({
    required this.workId,
    required this.kind,
    this.seasonNumber,
    this.episodeNumber,
    this.showCatalog = true,
  });

  final int workId;

  /// `movie` | `series`
  final String kind;
  final int? seasonNumber;
  final int? episodeNumber;

  /// 详情页已知无系列/无本地集时为 false，隐藏入口。
  final bool showCatalog;

  bool get isSeries => kind == 'series';
  bool get isMovie => kind == 'movie';

  PlaybackCatalogContext copyWith({
    int? workId,
    String? kind,
    int? seasonNumber,
    int? episodeNumber,
    bool? showCatalog,
  }) {
    return PlaybackCatalogContext(
      workId: workId ?? this.workId,
      kind: kind ?? this.kind,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      showCatalog: showCatalog ?? this.showCatalog,
    );
  }
}
