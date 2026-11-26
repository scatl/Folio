import 'package:material_ui/material_ui.dart';
import 'package:folio/login/login_page.dart';
import 'package:folio/logs/logs_page.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/settings/account_settings_page.dart';
import 'package:folio/settings/settings_hub_page.dart';
import 'package:folio/settings/settings_page.dart';
import 'package:folio/tasks/manual_match_page.dart';
import 'package:folio/tasks/tasks_page.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/wall/create_library_page.dart';
import 'package:folio/wall/wall_page.dart';
import 'package:folio/work/collection_page.dart';
import 'package:folio/work/episode_page.dart';
import 'package:folio/work/person_page.dart';
import 'package:folio/work/season_page.dart';
import 'package:folio/work/playlist_page.dart';
import 'package:folio/work/work_external_page.dart';
import 'package:folio/work/work_page.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: RouterPath.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      if (session.bootstrapping) {
        return location == RouterPath.splash ? null : RouterPath.splash;
      }
      if (!session.signedIn) {
        return location == RouterPath.login ? null : RouterPath.login;
      }
      if (location == RouterPath.login || location == RouterPath.splash) {
        return RouterPath.home;
      }
      // 首页的 auth/me 还没回来时先按普通用户，不要因此把深链踢走。
      if (session.profileReady && !session.isAdmin) {
        if (location == RouterPath.logs ||
            location == RouterPath.tasks ||
            location == RouterPath.createLibrary ||
            location.contains('/match')) {
          return RouterPath.home;
        }
        if (location.startsWith('/settings/') && location != '/settings/account') {
          return RouterPath.settings;
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: RouterPath.splash,
        builder: (context, state) => const _SplashPage(),
      ),
      GoRoute(
        path: RouterPath.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RouterPath.home,
        builder: (context, state) => const WallPage(),
      ),
      GoRoute(
        path: RouterPath.createLibrary,
        builder: (context, state) => const CreateLibraryPage(),
      ),
      GoRoute(
        path: '/libraries/:id',
        builder: (context, state) => WallPage(libraryId: _pathId(state, 'id')),
      ),
      GoRoute(
        path: RouterPath.settings,
        builder: (context, state) => const SettingsHubPage(),
        routes: [
          GoRoute(
            path: 'account',
            builder: (context, state) => const AccountSettingsPage(),
          ),
          GoRoute(
            path: 'source',
            builder: (context, state) => const SettingsSectionPage(section: 'source'),
          ),
          GoRoute(
            path: 'playback',
            builder: (context, state) => const SettingsSectionPage(section: 'playback'),
          ),
          GoRoute(
            path: 'match',
            builder: (context, state) => const SettingsSectionPage(section: 'match'),
          ),
          GoRoute(
            path: 'worker',
            builder: (context, state) => const SettingsSectionPage(section: 'worker'),
          ),
          GoRoute(
            path: 'advanced',
            builder: (context, state) => const SettingsSectionPage(section: 'advanced'),
          ),
        ],
      ),
      GoRoute(
        path: RouterPath.logs,
        builder: (context, state) => const LogsPage(),
      ),
      GoRoute(
        path: RouterPath.tasks,
        builder: (context, state) => const TasksPage(),
      ),
      GoRoute(
        path: '/library/files/:fileId/match',
        builder: (context, state) {
          final fileId = _pathId(state, 'fileId');
          final extra = state.extra;
          final args = extra is ManualMatchArgs
              ? extra
              : ManualMatchArgs(
                  fileId: fileId,
                  fileName: state.uri.queryParameters['fileName'] ?? '',
                  parsedTitle: state.uri.queryParameters['parsedTitle'],
                  parsedYear: int.tryParse(state.uri.queryParameters['parsedYear'] ?? ''),
                  parsedSeason: int.tryParse(state.uri.queryParameters['parsedSeason'] ?? ''),
                  parsedEpisode: int.tryParse(state.uri.queryParameters['parsedEpisode'] ?? ''),
                  initialKind: state.uri.queryParameters['kind'],
                  title: state.uri.queryParameters['title'] ?? '人工匹配',
                );
          return ManualMatchPage(args: args);
        },
      ),
      GoRoute(
        path: '/works/detail',
        builder: (context, state) => WorkExternalPage(
          provider: state.uri.queryParameters['provider'] ?? 'tmdb',
          externalId: state.uri.queryParameters['externalId'] ?? '',
          kind: state.uri.queryParameters['kind'] ?? '',
        ),
      ),
      GoRoute(
        path: '/works/:id',
        builder: (context, state) => WorkPage(id: _pathId(state, 'id')),
        routes: [
          GoRoute(
            path: 'seasons/:season',
            builder: (context, state) => SeasonPage(
              workId: _pathId(state, 'id'),
              seasonNumber: _pathId(state, 'season'),
            ),
            routes: [
              GoRoute(
                path: 'episodes/:episode',
                builder: (context, state) => EpisodePage(
                  workId: _pathId(state, 'id'),
                  seasonNumber: _pathId(state, 'season'),
                  episodeNumber: _pathId(state, 'episode'),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/playlists/:id',
        builder: (context, state) => PlaylistPage(id: _pathId(state, 'id')),
      ),
      GoRoute(
        path: '/collections/:id',
        builder: (context, state) => CollectionPage(
          id: Uri.decodeComponent(state.pathParameters['id'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/people/:provider/:externalId',
        builder: (context, state) => PersonPage(
          provider: Uri.decodeComponent(state.pathParameters['provider'] ?? ''),
          externalId: Uri.decodeComponent(state.pathParameters['externalId'] ?? ''),
        ),
      ),
    ],
  );
});

int _pathId(GoRouterState state, String name) => int.tryParse(state.pathParameters[name] ?? '') ?? 0;

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(sessionProvider, (previous, next) => notifyListeners());
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: FolioColors.bgDeep);
  }
}
