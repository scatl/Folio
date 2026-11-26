import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/logs/log_filter.dart';
import 'package:folio/logs/log_models.dart';
import 'package:folio/logs/log_record.dart';
import 'package:folio/logs/log_view.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/util/app_log.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> with TickerProviderStateMixin {
  late final TabController _sourceTabs;
  late final TabController _levelTabs;
  final _serverScroll = ScrollController();
  final _localScroll = ScrollController();

  int _serverGen = 0;
  int _contentGen = 0;
  bool _serverLoading = true;
  String? _serverError;
  ServerLogList? _server;
  String? _selected;
  ServerLogContent? _content;
  bool _contentLoading = false;
  String? _contentError;

  bool _localLoading = true;
  String? _localError;
  AppLogFileReadResult? _local;
  String? _localDay;

  @override
  void initState() {
    super.initState();
    _sourceTabs = TabController(length: 2, vsync: this);
    _levelTabs = TabController(length: logLevelLabels.length, vsync: this);
    _sourceTabs.addListener(_onSourceTab);
    _levelTabs.addListener(_onLevelTab);
    Future.microtask(() {
      _loadServer();
      _loadLocal();
    });
  }

  void _onSourceTab() {
    if (_sourceTabs.indexIsChanging || !mounted) return;
    setState(() {});
  }

  void _onLevelTab() {
    if (_levelTabs.indexIsChanging || !mounted) return;
    setState(() {});
  }

  LogLevel get _level => LogLevel.values[_levelTabs.index];

  @override
  void dispose() {
    _sourceTabs.removeListener(_onSourceTab);
    _levelTabs.removeListener(_onLevelTab);
    _sourceTabs.dispose();
    _levelTabs.dispose();
    _serverScroll.dispose();
    _localScroll.dispose();
    super.dispose();
  }

  Future<void> _loadServer({bool keep = false}) async {
    final gen = ++_serverGen;
    setState(() {
      _serverLoading = true;
      _serverError = null;
    });
    try {
      final listed = await ref.read(apiClientProvider).get(
            ApiPath.logs.list,
            parser: jsonParser(ServerLogList.fromJson),
          );
      if (!mounted || gen != _serverGen) return;
      setState(() => _server = listed);
      if (!listed.available || listed.files.isEmpty) {
        _contentGen += 1;
        setState(() {
          _selected = null;
          _content = null;
          _contentError = null;
          _contentLoading = false;
        });
        return;
      }
      final current = keep ? _selected : null;
      final next = listed.files.any((file) => file.name == current) ? current! : listed.files.first.name;
      await _loadContent(next, keep: keep && next == _selected);
    } on ApiFailure catch (error) {
      if (!mounted || gen != _serverGen) return;
      setState(() => _serverError = error.message);
    } finally {
      if (mounted && gen == _serverGen) setState(() => _serverLoading = false);
    }
  }

  Future<void> _loadContent(String name, {required bool keep}) async {
    final gen = ++_contentGen;
    setState(() {
      _selected = name;
      _contentLoading = true;
      _contentError = null;
      if (!keep) _content = null;
    });
    try {
      final content = await ref.read(apiClientProvider).get(
            ApiPath.logs.content,
            queryParameters: {'name': name},
            parser: jsonParser(ServerLogContent.fromJson),
          );
      if (!mounted || gen != _contentGen) return;
      setState(() => _content = content);
    } on ApiFailure catch (error) {
      if (!mounted || gen != _contentGen) return;
      setState(() {
        if (!keep) _content = null;
        _contentError = error.message;
      });
    } finally {
      if (mounted && gen == _contentGen) setState(() => _contentLoading = false);
    }
  }

  Future<void> _loadLocal() async {
    setState(() {
      _localLoading = true;
      _localError = null;
    });
    try {
      final result = await loadAppLogFile();
      if (!mounted) return;
      final days = localLogDays(result.lines);
      final kept = days.any((day) => day.date == _localDay) ? _localDay : days.firstOrNull?.date;
      setState(() {
        _local = result;
        _localDay = kept;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _localError = '$error');
    } finally {
      if (mounted) setState(() => _localLoading = false);
    }
  }

  void _refresh() {
    if (_sourceTabs.index == 0) {
      if (!_serverLoading) _loadServer(keep: true);
    } else if (!_localLoading) {
      _loadLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshing = _sourceTabs.index == 0 ? _serverLoading : _localLoading;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(child: Text('日志', style: folioDisplay(size: 22, weight: FontWeight.w400))),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: refreshing ? null : _refresh,
                      icon: FolioRefreshIcon(spinning: refreshing),
                    ),
                  ],
                ),
              ),
              _tabBar(_sourceTabs, const ['服务器', '本地']),
              _tabBar(_levelTabs, logLevelLabels),
              Expanded(
                child: TabBarView(
                  controller: _sourceTabs,
                  children: [
                    _serverPane(),
                    _localPane(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serverPane() {
    if (_serverLoading && _server == null) {
      return const Center(child: FolioLoading(label: '正在读取日志'));
    }
    if (_serverError != null && _server == null) {
      return EmptyHint(title: '日志读取失败', body: _serverError!, error: true);
    }
    final listed = _server;
    if (listed == null || !listed.available) {
      return EmptyHint(
        title: '没有服务器日志',
        body: listed?.message ?? '日志目录不可用',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listed.files.isEmpty)
          const Expanded(child: EmptyHint(title: '还没有日志文件', body: '服务端开始写文件后，当天和最近几天的日志会出现在这里。'))
        else ...[
          _dateChips([
            for (final file in listed.files)
              (
                label: file.label,
                subtitle: '${_formatBytes(file.size)}${file.compressed ? ' · gz' : ''}',
                active: file.name == _selected,
                onTap: () => _loadContent(file.name, keep: false),
              ),
          ]),
          if (_content?.truncated == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '只显示最后 ${_content!.lineCount} 行，共 ${_content!.totalLines} 行',
                style: const TextStyle(color: FolioColors.copper, fontSize: 12),
              ),
            ),
          Expanded(child: _contentBody()),
        ],
      ],
    );
  }

  Widget _dateChips(List<({String label, String subtitle, bool active, VoidCallback onTap})> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          for (var index = 0; index < chips.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _dateChip(chips[index]),
          ],
        ],
      ),
    );
  }

  Widget _dateChip(({String label, String subtitle, bool active, VoidCallback onTap}) chip) {
    return Material(
      color: chip.active ? const Color(0x2ED4A574) : FolioColors.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: chip.active ? const Color(0x73D4A574) : FolioColors.line),
      ),
      child: InkWell(
        onTap: chip.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chip.label,
                style: const TextStyle(color: FolioColors.ink, fontWeight: FontWeight.w700, fontSize: 13, height: 1.2),
              ),
              Text(
                chip.subtitle,
                style: const TextStyle(color: FolioColors.inkFaint, fontSize: 11, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contentBody() {
    if (_contentLoading && _content == null) {
      return const Center(child: FolioLoading(label: '正在读取日志'));
    }
    if (_contentError != null && _content == null) {
      return EmptyHint(title: '日志读取失败', body: _contentError!, error: true);
    }
    final text = _content?.text ?? '';
    return _logText(_serverScroll, text);
  }

  Widget _localPane() {
    if (_localLoading && _local == null) {
      return const Center(child: FolioLoading(label: '正在读取日志'));
    }
    if (_localError != null && _local == null) {
      return EmptyHint(title: '日志读取失败', body: _localError!, error: true);
    }
    final local = _local;
    if (local == null || !local.supported) {
      return const EmptyHint(
        title: '没有本地日志',
        body: '这个环境不会写本地日志文件。',
      );
    }
    final days = localLogDays(local.lines);
    if (days.isEmpty) {
      return EmptyHint(
        title: '还没有本地日志',
        body: local.path ?? '应用支持目录下的 app_debug.log',
      );
    }
    final selected = days.where((day) => day.date == _localDay).firstOrNull ?? days.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateChips([
          for (final day in days)
            (
              label: day.label,
              subtitle: _formatBytes(day.size),
              active: day.date == selected.date,
              onTap: () => setState(() => _localDay = day.date),
            ),
        ]),
        Expanded(child: _logText(_localScroll, selected.lines.join('\n'))),
      ],
    );
  }

  Widget _tabBar(TabController controller, List<String> labels) {
    return TabBar(
      controller: controller,
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
      tabs: [for (final label in labels) Tab(text: label)],
    );
  }

  Widget _logText(ScrollController scroll, String text) {
    return LogRecordView(
      controller: scroll,
      text: text,
      level: _level,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
