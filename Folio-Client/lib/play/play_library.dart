import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/play/playback_catalog_context.dart';
import 'package:folio/play/playback_prepare_meta.dart';
import 'package:folio/play/player_page.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';

export 'package:folio/play/playback_catalog_context.dart';
export 'package:folio/play/playback_prepare_meta.dart';

Future<void> playLibraryFiles(
  BuildContext context,
  WidgetRef ref,
  List<LibraryFileBrief> files, {
  String? posterUrl,
  PlaybackPrepareMeta? meta,
  PlaybackCatalogContext? catalog,
  int? resumePositionMs,
  bool fetchResume = true,
}) async {
  if (files.isEmpty) return;
  final chosen = files.length == 1 ? files.first : await chooseLibraryFile(context, files);
  if (chosen == null || !context.mounted) return;
  final api = ref.read(apiClientProvider);
  final resolvedMeta = meta == null
      ? null
      : PlaybackPrepareMeta(
          title: meta.title,
          subtitle: meta.subtitle,
          playbackTitle: meta.playbackTitle,
          kindLabel: meta.kindLabel,
          year: meta.year,
          runtimeLabel: meta.runtimeLabel ??
              (chosen.durationMs == null
                  ? null
                  : formatRuntimeMs(chosen.durationMs!)),
          genres: meta.genres,
          ratings: meta.ratings,
        );
  var resume = resumePositionMs;
  if (resume == null && fetchResume) {
    try {
      final progress = await api.get(
        ApiPath.playback.progress,
        queryParameters: {'libraryFileId': chosen.id},
        parser: jsonParser(PlaybackProgress.fromJson),
      );
      resume = progress.resumePositionMs;
    } on ApiFailure {
      resume = null;
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        api: api,
        fileId: chosen.id,
        fileName: chosen.fileName,
        posterUrl: posterUrl,
        prepareMeta: resolvedMeta,
        catalog: catalog,
        resumePositionMs: resume,
      ),
    ),
  );
}

String formatRuntimeMs(int ms) {
  final total = (ms / 1000).round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (hours > 0) return '$hours 小时 $minutes 分钟';
  if (minutes > 0) return '$minutes 分钟';
  return '$total 秒';
}

Future<LibraryFileBrief?> chooseLibraryFile(
  BuildContext context,
  List<LibraryFileBrief> files,
) {
  return showFolioSheet<LibraryFileBrief>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('选择要播放的文件', style: TextStyle(color: FolioColors.ink))),
          for (final file in files)
            ListTile(
              title: Text(file.fileName, style: const TextStyle(color: FolioColors.ink)),
              onTap: () => Navigator.pop(context, file),
            ),
        ],
      ),
    ),
  );
}
