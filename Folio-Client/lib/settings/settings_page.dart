import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/settings/settings_ui_state.dart';
import 'package:folio/settings/settings_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class SettingsSectionPage extends ConsumerWidget {
  const SettingsSectionPage({super.key, required this.section});

  final String section;

  static const titles = {
    'source': '元数据源',
    'playback': '播放',
    'match': '匹配与扫描',
    'worker': '刮削任务',
    'advanced': '高级',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(settingsProvider);
    final vm = ref.read(settingsProvider.notifier);
    final fromLibrary = GoRouterState.of(context).uri.queryParameters['from'] == 'library';
    final title = titles[section] ?? '设置';
    final fields = switch (section) {
      'source' => _source(ui, vm, fromLibrary),
      'playback' => _playback(vm),
      'match' => _match(ui, vm),
      'worker' => _worker(vm),
      'advanced' => _advanced(ui, vm),
      _ => const <Widget>[],
    };
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(child: Text(title, style: folioDisplay(size: 22, weight: FontWeight.w400))),
                    if (!ui.loading)
                      IconButton(
                        tooltip: '保存',
                        onPressed: ui.saving ? null : () => _save(context, vm),
                        icon: ui.saving ? const FolioSpinner() : const Icon(Icons.save_outlined),
                      ),
                  ],
                ),
              ),
              if (ui.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(ui.error!, style: const TextStyle(color: FolioColors.danger, fontSize: 13)),
                ),
              Expanded(
                child: ui.loading
                    ? const Center(child: Text('加载中…', style: TextStyle(color: FolioColors.inkMuted)))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          if (section == 'source' && fromLibrary && ui.snapshot != null && !ui.snapshot!.tmdbApiKeyConfigured)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '创建资料库前需要先配置 TMDB API Key。填好并保存后，再回到首页创建。',
                                style: TextStyle(color: FolioColors.copper, height: 1.4),
                              ),
                            ),
                          ...fields,
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, SettingsViewModel vm) async {
    final message = await vm.save();
    if (!context.mounted || message == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  List<Widget> _source(SettingsUiState ui, SettingsViewModel vm, bool fromLibrary) => [
        if (ui.snapshot != null && !ui.snapshot!.tmdbApiKeyConfigured) ...[
          Text(
            fromLibrary
                ? '请先填写下面的 TMDB API Key 并保存。没有它时无法创建资料库。'
                : '还没有 TMDB API Key。填在下面并保存后，才能刮削作品。',
            style: const TextStyle(color: FolioColors.copper, height: 1.4),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          '只有 TMDB 用来搜索和建档。OMDb、TVDB 只在匹配成功后补充数据。',
          style: TextStyle(color: FolioColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        _label('TMDB API Key'),
        TextField(
          controller: vm.tmdbKey,
          autofocus: ui.snapshot != null && !ui.snapshot!.tmdbApiKeyConfigured,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '必填，唯一匹配来源'),
          onTap: () => vm.selectMask(vm.tmdbKey),
        ),
        _label('详情语言'),
        TextField(controller: vm.fields['tmdbLanguage']),
        _label('搜索语言'),
        TextField(controller: vm.fields['tmdbSearchLanguage']),
        _label('OMDb API Key'),
        TextField(
          controller: vm.omdbKey,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '可选，只补充评分和奖项'),
          onTap: () => vm.selectMask(vm.omdbKey),
        ),
        _label('TVDB API Key'),
        TextField(
          controller: vm.tvdbKey,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '可选，填写后补充资料，不参与匹配'),
          onTap: () => vm.selectMask(vm.tvdbKey),
        ),
        _label('TVDB PIN'),
        TextField(
          controller: vm.tvdbPin,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '没有可留空'),
          onTap: () => vm.selectMask(vm.tvdbPin),
        ),
      ];

  List<Widget> _playback(SettingsViewModel vm) => [
        _label('片头不足多少秒不记进度'),
        TextField(
          controller: vm.fields['playbackIgnoreBelowSeconds'],
          keyboardType: TextInputType.number,
        ),
        const Text(
          '短于这个时间就当没看，下次仍从头播。0 表示一播放就记。',
          style: TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.4),
        ),
        _label('片尾剩余多少秒视为看完'),
        TextField(
          controller: vm.fields['playbackCompleteRemainingSeconds'],
          keyboardType: TextInputType.number,
        ),
        const Text(
          '播到离结尾不超过这个时间，就记为看完。电影会离开继续观看；剧集有下一集会跳到下一集。',
          style: TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.4),
        ),
      ];

  List<Widget> _match(SettingsUiState ui, SettingsViewModel vm) => [
        _label('自动匹配阈值（0.1–1）'),
        TextField(controller: vm.fields['matchAutoThreshold'], keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        _label('定时扫描间隔（分钟）'),
        TextField(controller: vm.fields['scanIntervalMinutes'], keyboardType: TextInputType.number),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('监听资料库目录变化'),
          subtitle: const Text('关闭后仍按间隔扫描', style: TextStyle(color: FolioColors.inkMuted)),
          value: ui.watchEnabled,
          activeThumbColor: FolioColors.copper,
          onChanged: vm.setWatchEnabled,
        ),
      ];

  List<Widget> _worker(SettingsViewModel vm) => [
        _label('同时进行的任务数'),
        TextField(controller: vm.fields['workerConcurrency'], keyboardType: TextInputType.number),
        _label('领取任务间隔（毫秒）'),
        TextField(controller: vm.fields['workerDelayMs'], keyboardType: TextInputType.number),
        _label('单个任务最多尝试次数'),
        TextField(controller: vm.fields['workerMaxAttempts'], keyboardType: TextInputType.number),
      ];

  List<Widget> _advanced(SettingsUiState ui, SettingsViewModel vm) => [
        _label('TMDB API 地址'),
        TextField(controller: vm.fields['tmdbBaseUrl']),
        _label('TMDB 图片地址'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: TextField(controller: vm.fields['tmdbImageBaseUrl'])),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ListenableBuilder(
                listenable: vm.fields['tmdbImageBaseUrl']!,
                builder: (context, _) {
                  final isDefault = vm.isTmdbImageBaseUrlDefault;
                  return TextButton(
                    onPressed: isDefault ? null : vm.resetTmdbImageBaseUrl,
                    style: TextButton.styleFrom(
                      foregroundColor: FolioColors.copper,
                      disabledForegroundColor: FolioColors.inkFaint,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                    ),
                    child: const Text('恢复默认'),
                  );
                },
              ),
            ),
          ],
        ),
        const Text(
          '入库始终用官方地址；此处只影响访问时展示。改前缀后无需重刮。',
          style: TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.4),
        ),
        _label('TMDB 每秒请求上限'),
        TextField(controller: vm.fields['tmdbRequestsPerSecond'], keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        _label('OMDb 地址'),
        TextField(controller: vm.fields['omdbBaseUrl']),
        _label('OMDb 每秒请求上限'),
        TextField(controller: vm.fields['omdbRequestsPerSecond'], keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        _label('TVDB API 地址'),
        TextField(controller: vm.fields['tvdbBaseUrl']),
        _label('TVDB 每秒请求上限'),
        TextField(controller: vm.fields['tvdbRequestsPerSecond'], keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        _label('外部 API 超时（秒）'),
        TextField(controller: vm.fields['httpTimeoutSeconds'], keyboardType: TextInputType.number),
      ];

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
    );
  }
}
