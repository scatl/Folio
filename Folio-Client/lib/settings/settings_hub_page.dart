import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class SettingsHubPage extends ConsumerWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(sessionProvider.select((session) => session.isAdmin));
    final entries = <_SettingsEntry>[
      const _SettingsEntry('account', '账号', '用户、密码', Icons.person_outline),
      if (admin) ...const [
        _SettingsEntry('source', '元数据源', 'TMDB、OMDb、TVDB', Icons.cloud_outlined),
        _SettingsEntry('playback', '播放', '片头片尾如何记进度', Icons.play_circle_outline),
        _SettingsEntry('match', '匹配与扫描', '阈值、定时扫描、目录监听', Icons.manage_search),
        _SettingsEntry('worker', '刮削任务', '并发、间隔、重试', Icons.bolt_outlined),
        _SettingsEntry('advanced', '高级', '接口地址、超时', Icons.tune),
      ],
    ];
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(child: Text('设置', style: folioDisplay(size: 22, weight: FontWeight.w400))),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(
                    color: FolioColors.line,
                    height: 1,
                    indent: 70,
                    endIndent: 20,
                  ),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      horizontalTitleGap: 14,
                      minLeadingWidth: 36,
                      leading: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0x1AD4A574),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(entry.icon, size: 20, color: FolioColors.copper),
                      ),
                      title: Text(entry.title),
                      subtitle: Text(entry.subtitle, style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, color: FolioColors.inkFaint),
                      onTap: () => context.push('/settings/${entry.id}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsEntry {
  const _SettingsEntry(this.id, this.title, this.subtitle, this.icon);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}
