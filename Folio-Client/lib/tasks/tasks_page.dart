import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/tasks/manual_match_page.dart';
import 'package:folio/tasks/tasks_ui_state.dart';
import 'package:folio/tasks/tasks_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/dialog/confirm_dialog.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> with SingleTickerProviderStateMixin {
  static const _filters = [
    (value: '', label: '全部'),
    (value: 'queued', label: '排队中'),
    (value: 'running', label: '执行中'),
    (value: 'needs_review', label: '待人工确认'),
    (value: 'failed', label: '失败'),
  ];

  late final TabController _tabs;
  late final List<ScrollController> _scrolls;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _filters.length, vsync: this);
    _tabs.addListener(_onTab);
    _scrolls = List.generate(_filters.length, (index) {
      final controller = ScrollController();
      controller.addListener(() => _onScroll(index, controller));
      return controller;
    });
  }

  void _onTab() {
    final value = _filters[_tabs.index].value;
    if (ref.read(tasksProvider).status == value) return;
    ref.read(tasksProvider.notifier).setStatus(value);
  }

  void _onScroll(int index, ScrollController controller) {
    if (_tabs.index != index || !controller.hasClients) return;
    final status = _filters[index].value;
    final slice = ref.read(tasksProvider).slice(status);
    if (!slice.hasMore || slice.loading || slice.loadingMore) return;
    if (controller.position.pixels > controller.position.maxScrollExtent - 320) {
      ref.read(tasksProvider.notifier).loadMore(status);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    for (final controller in _scrolls) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _remove(ScrapeJobRow job) async {
    final ok = await ConfirmDialog.show(
      context,
      title: '删除任务',
      message: '确定删除任务「${job.fileName}」？将同时删除对应文件记录。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok == true) await ref.read(tasksProvider.notifier).remove(job);
  }

  Future<void> _match(ScrapeJobRow job) async {
    final choice = await context.push<MatchChoice>(
      RouterPath.manualMatch(job.fileId),
      extra: ManualMatchArgs.fromJob(job),
    );
    if (choice == null || !mounted) return;
    await ref.read(tasksProvider.notifier).confirmMatch(
          job: job,
          fileId: choice.fileId,
          kind: choice.candidate.kind,
          tmdbId: choice.tmdbId,
          year: choice.year,
          season: choice.season,
          episode: choice.episode,
          scope: choice.scope,
        );
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(tasksProvider);
    final vm = ref.read(tasksProvider.notifier);
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(child: Text('刮削任务', style: folioDisplay(size: 22, weight: FontWeight.w400))),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: ui.loading ? null : () => vm.fetch(0, append: false),
                      icon: FolioRefreshIcon(spinning: ui.loading),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 0,
                indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x38D4A574), Color(0x2E5FB3A8)],
                  ),
                ),
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                labelColor: FolioColors.ink,
                unselectedLabelColor: FolioColors.inkMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: [for (final item in _filters) Tab(text: item.label)],
              ),
              if (ui.actionError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
                  child: Text(ui.actionError!, textAlign: TextAlign.center, style: const TextStyle(color: FolioColors.danger)),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (var i = 0; i < _filters.length; i++) _list(ui, vm, status: _filters[i].value, scroll: _scrolls[i]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(TasksUiState ui, TasksViewModel vm, {required String status, required ScrollController scroll}) {
    final slice = ui.slice(status);
    if (!slice.loaded && slice.items.isEmpty) {
      if (slice.error != null) {
        return Center(child: EmptyHint(title: '加载失败', body: slice.error!, error: true));
      }
      return const Center(child: FolioLoading());
    }
    if (slice.items.isEmpty) {
      return const Center(
        child: EmptyHint(title: '暂无刮削任务', body: '创建资料库后，文件会进入这里排队刮削。'),
      );
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: slice.items.length + (slice.loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= slice.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: FolioSpinner()),
          );
        }
        final job = slice.items[index];
        return _JobCard(
          job: job,
          deleting: ui.deletingId == job.id,
          retrying: ui.retryingId == job.id,
          onRetry: () => vm.retry(job),
          onMatch: () => _match(job),
          onDelete: () => _remove(job),
        );
      },
    );
  }

}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.deleting,
    required this.retrying,
    required this.onRetry,
    required this.onMatch,
    required this.onDelete,
  });

  final ScrapeJobRow job;
  final bool deleting;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onMatch;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final season = job.parsedSeason == null
        ? ''
        : ' · S${job.parsedSeason.toString().padLeft(2, '0')}${job.parsedEpisode == null ? '' : 'E${job.parsedEpisode.toString().padLeft(2, '0')}'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xCC12151C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FolioColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.parsedTitle?.isNotEmpty == true ? job.parsedTitle! : job.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(job.locator.isEmpty ? job.fileName : job.locator, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12)),
          if (job.parsedYear != null || season.isNotEmpty)
            Text('${job.parsedYear ?? ''}$season', style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!_hidesCompleted(job)) _statusChip(job.status, _statusLabel(job.status)),
              _matchChip(job.matchStatus, _matchLabel(job.matchStatus)),
              if (_progressText(job).isNotEmpty) _progressLabel(job, _progressText(job)),
              if (job.mediaLibraryName != null && job.mediaLibraryName!.trim().isNotEmpty)
                Text(job.mediaLibraryName!, style: const TextStyle(color: FolioColors.inkFaint, fontSize: 13)),
              Text('尝试次数：${job.attempts}/${job.maxAttempts}', style: const TextStyle(color: FolioColors.inkFaint, fontSize: 13)),
              if (_short(job.lastError ?? job.message).isNotEmpty)
                Text(
                  _short(job.lastError ?? job.message),
                  style: const TextStyle(color: FolioColors.inkFaint, fontSize: 13, height: 1.4),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (job.canRetry)
                _actionButton(retrying ? '重试中…' : '重试', retrying || deleting ? null : onRetry),
              if (job.canManualMatch) _actionButton('人工匹配', onMatch),
              _actionButton(deleting ? '删除中…' : '删除', !job.canDelete || deleting || retrying ? null : onDelete, danger: true),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _statusChip(String status, String label) {
  final color = switch (status) {
    'queued' => FolioColors.ink,
    'running' => FolioColors.copper,
    'failed' => FolioColors.danger,
    'succeeded' => FolioColors.teal,
    _ => FolioColors.inkMuted,
  };
  return _chip(label, color);
}

Widget _matchChip(String status, String label) {
  final color = switch (status) {
    'failed' => FolioColors.danger,
    'matched' => FolioColors.teal,
    'needs_review' => FolioColors.copper,
    _ => FolioColors.inkMuted,
  };
  return _chip(label, color);
}

Widget _chip(String text, Color color) {
  return Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color));
}

Widget _progressLabel(ScrapeJobRow job, String text) {
  final live = job.status == 'queued' || job.status == 'running';
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (live) ...[
        const _LiveDot(),
        const SizedBox(width: 6),
      ],
      Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: live ? FolioColors.copper : FolioColors.inkMuted),
      ),
    ],
  );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: FolioColors.copper,
            boxShadow: [
              BoxShadow(
                color: FolioColors.copper.withValues(alpha: 0.45 * (1 - t)),
                blurRadius: 0,
                spreadRadius: 8 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _actionButton(String label, VoidCallback? onPressed, {bool danger = false}) {
  final color = danger ? FolioColors.danger : FolioColors.inkMuted;
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      disabledForegroundColor: color.withValues(alpha: 0.45),
      side: BorderSide(color: danger ? const Color(0x73E07A6B) : FolioColors.lineStrong),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
    ),
    child: Text(label),
  );
}

bool _hidesCompleted(ScrapeJobRow job) {
  return job.status == 'succeeded' && (job.matchStatus == 'needs_review' || job.matchStatus == 'failed');
}

String _statusLabel(String status) {
  switch (status) {
    case 'queued':
      return '排队中';
    case 'running':
      return '执行中';
    case 'succeeded':
      return '已完成';
    case 'failed':
      return '失败';
    default:
      return status;
  }
}

String _matchLabel(String status) {
  switch (status) {
    case 'pending':
      return '待匹配';
    case 'matched':
      return '已匹配';
    case 'needs_review':
      return '待人工确认';
    case 'failed':
      return '匹配失败';
    default:
      return status;
  }
}

String _progressText(ScrapeJobRow job) {
  final progress = job.progress?.trim();
  if (progress != null && progress.isNotEmpty) {
    if (progress == '待人工确认') return '';
    if (_hidesCompleted(job) && progress == '已完成') return '';
    return progress;
  }
  switch (job.status) {
    case 'queued':
      return '等待执行';
    case 'running':
      return '执行中…';
    case 'succeeded':
      return _hidesCompleted(job) ? '' : '已完成';
    case 'failed':
      return '失败';
    default:
      return '';
  }
}

String _short(String? message) {
  if (message == null || message.trim().isEmpty) return '';
  final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length > 72 ? '${compact.substring(0, 72)}…' : compact;
}
