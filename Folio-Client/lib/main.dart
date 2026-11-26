import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/router/app_router.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: FolioColors.bgDeep,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: FolioApp()));
}

class _ScrapeNotice extends ConsumerWidget {
  const _ScrapeNotice({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionProvider, (previous, next) {
      if (next.scrapeNoticeId == previous?.scrapeNoticeId) return;
      if (next.scrapeReview == 0 && next.scrapeFailed == 0) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: FolioColors.bgSoft,
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (next.scrapeReview > 0)
                Text(
                  '${next.scrapeReview} 项待人工确认',
                  style: const TextStyle(color: FolioColors.copper, fontWeight: FontWeight.w700),
                ),
              if (next.scrapeFailed > 0)
                Text(
                  '${next.scrapeFailed} 项刮削失败',
                  style: const TextStyle(color: FolioColors.danger, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ),
      );
    });
    return child;
  }
}

class FolioApp extends ConsumerWidget {
  const FolioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Folio',
      debugShowCheckedModeBanner: false,
      theme: folioTheme(),
      routerConfig: router,
      builder: (context, child) => _ScrapeNotice(child: child ?? const SizedBox.shrink()),
    );
  }
}
