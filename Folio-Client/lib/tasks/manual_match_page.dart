import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class ManualMatchFileOption {
  const ManualMatchFileOption({
    required this.id,
    required this.fileName,
    this.locator = '',
    this.parsedTitle,
    this.parsedYear,
    this.parsedSeason,
    this.parsedEpisode,
  });

  factory ManualMatchFileOption.fromBrief(LibraryFileBrief file) => ManualMatchFileOption(
        id: file.id,
        fileName: file.fileName,
        locator: file.locator,
        parsedTitle: file.parsedTitle,
        parsedYear: file.parsedYear,
        parsedSeason: file.parsedSeason,
        parsedEpisode: file.parsedEpisode,
      );

  final int id;
  final String fileName;
  final String locator;
  final String? parsedTitle;
  final int? parsedYear;
  final int? parsedSeason;
  final int? parsedEpisode;

  String get displayName {
    final name = fileName.trim();
    if (name.isNotEmpty) return name;
    return locator.trim();
  }
}

class ManualMatchArgs {
  const ManualMatchArgs({
    required this.fileId,
    required this.fileName,
    this.locator = '',
    this.parsedTitle,
    this.parsedYear,
    this.parsedSeason,
    this.parsedEpisode,
    this.initialKind,
    this.title = '人工匹配',
    this.files = const [],
  });

  factory ManualMatchArgs.fromJob(ScrapeJobRow job) => ManualMatchArgs(
        fileId: job.fileId,
        fileName: job.fileName,
        locator: job.locator,
        parsedTitle: job.parsedTitle,
        parsedYear: job.parsedYear,
        parsedSeason: job.parsedSeason,
        parsedEpisode: job.parsedEpisode,
      );

  factory ManualMatchArgs.files({
    required List<LibraryFileBrief> files,
    required String kind,
    String title = '重新匹配',
  }) {
    final first = files.first;
    return ManualMatchArgs(
      fileId: first.id,
      fileName: first.fileName,
      locator: first.locator,
      parsedTitle: first.parsedTitle,
      parsedYear: first.parsedYear,
      parsedSeason: first.parsedSeason,
      parsedEpisode: first.parsedEpisode,
      initialKind: kind,
      title: title,
      files: files.map(ManualMatchFileOption.fromBrief).toList(),
    );
  }

  final int fileId;
  final String fileName;
  final String locator;
  final String? parsedTitle;
  final int? parsedYear;
  final int? parsedSeason;
  final int? parsedEpisode;
  final String? initialKind;
  final String title;
  /// 作品详情重新匹配时可切换的文件列表；任务页人工匹配通常为空。
  final List<ManualMatchFileOption> files;

  /// 优先文件名，没有则用路径。
  String get displayName {
    final name = fileName.trim();
    if (name.isNotEmpty) return name;
    return locator.trim();
  }
}

class ManualMatchPage extends ConsumerStatefulWidget {
  const ManualMatchPage({super.key, required this.args});

  final ManualMatchArgs args;

  @override
  ConsumerState<ManualMatchPage> createState() => _ManualMatchPageState();
}

class _ManualMatchPageState extends ConsumerState<ManualMatchPage> {
  late final TextEditingController _query;
  late final TextEditingController _year;
  late final TextEditingController _season;
  late final TextEditingController _episode;
  late String _kind;
  late int _fileId;
  late String _fileName;
  late String _locator;
  late String? _parsedTitle;
  late int? _parsedYear;
  late int? _parsedSeason;
  late int? _parsedEpisode;
  List<MatchCandidate> _candidates = const [];
  bool _searching = false;
  String? _error;
  late bool _wholeWork;

  ManualMatchArgs get args => widget.args;

  List<ManualMatchFileOption> get _selectableFiles =>
      args.files.isEmpty
          ? [
              ManualMatchFileOption(
                id: args.fileId,
                fileName: args.fileName,
                locator: args.locator,
                parsedTitle: args.parsedTitle,
                parsedYear: args.parsedYear,
                parsedSeason: args.parsedSeason,
                parsedEpisode: args.parsedEpisode,
              ),
            ]
          : args.files;

  bool get _canSwitchFile => _selectableFiles.length > 1;

  String get _displayName {
    final name = _fileName.trim();
    if (name.isNotEmpty) return name;
    return _locator.trim();
  }

  @override
  void initState() {
    super.initState();
    _fileId = args.fileId;
    _fileName = args.fileName;
    _locator = args.locator;
    _parsedTitle = args.parsedTitle;
    _parsedYear = args.parsedYear;
    _parsedSeason = args.parsedSeason;
    _parsedEpisode = args.parsedEpisode;
    _kind = args.initialKind ?? (_parsedSeason != null ? 'series' : 'movie');
    _query = TextEditingController(text: _parsedTitle ?? '');
    _year = TextEditingController();
    _season = TextEditingController(text: _parsedSeason?.toString() ?? '');
    _episode = TextEditingController(text: _parsedEpisode?.toString() ?? '');
    _wholeWork = _selectableFiles.length > 1 && args.initialKind == 'series';
    _search();
  }

  void _selectFile(int fileId) {
    if (fileId == _fileId) return;
    final next = _selectableFiles.where((item) => item.id == fileId).firstOrNull;
    if (next == null) return;
    _fileId = next.id;
    _fileName = next.fileName;
    _locator = next.locator;
    _parsedTitle = next.parsedTitle;
    _parsedYear = next.parsedYear;
    _parsedSeason = next.parsedSeason;
    _parsedEpisode = next.parsedEpisode;
    if (args.initialKind == null) {
      _kind = _parsedSeason != null ? 'series' : 'movie';
    }
    _query.text = _parsedTitle ?? '';
    _year.clear();
    _season.text = _parsedSeason?.toString() ?? '';
    _episode.text = _parsedEpisode?.toString() ?? '';
    setState(() {
      _candidates = const [];
      _error = null;
    });
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    _year.dispose();
    _season.dispose();
    _episode.dispose();
    super.dispose();
  }

  int? _readInt(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value <= 0) return null;
    return value;
  }

  bool _invalid(String raw) => raw.trim().isNotEmpty && _readInt(raw) == null;

  Future<void> _search() async {
    if (_invalid(_year.text) || (_kind == 'series' && (_invalid(_season.text) || _invalid(_episode.text)))) {
      setState(() {
        _error = '年份、季、集请填写正整数，或留空使用默认值';
        _candidates = const [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    final year = _readInt(_year.text);
    try {
      final items = await ref.read(apiClientProvider).get(
            ApiPath.libraryFiles.candidates(_fileId),
            queryParameters: {
              if (_query.text.trim().isNotEmpty) 'q': _query.text.trim(),
              'kind': _kind,
              'year': ?year,
            },
            parser: listParser(MatchCandidate.fromJson),
          );
      if (mounted) setState(() => _candidates = items);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _candidates = const [];
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool get _fixingOne => !_wholeWork || _kind != 'series';

  void _choose(MatchCandidate candidate) {
    if (_invalid(_year.text) || (_fixingOne && _kind == 'series' && (_invalid(_season.text) || _invalid(_episode.text)))) {
      setState(() => _error = '年份、季、集请填写正整数，或留空使用默认值');
      return;
    }
    final tmdbId = int.tryParse(candidate.externalId);
    if (tmdbId == null) {
      setState(() => _error = '候选编号无效');
      return;
    }
    final whole = _wholeWork && _kind == 'series';
    context.pop(MatchChoice(
      fileId: _fileId,
      candidate: candidate,
      tmdbId: tmdbId,
      year: _readInt(_year.text),
      season: whole || _kind != 'series' ? null : _readInt(_season.text),
      episode: whole || _kind != 'series' ? null : _readInt(_episode.text),
      scope: whole ? 'work' : 'file',
    ));
  }

  void _setKind(String value) {
    if (_kind == value) return;
    setState(() => _kind = value);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final yearHint = _kind == 'series'
        ? '留空不限年份'
        : (_parsedYear == null ? '年份' : '默认 $_parsedYear');
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(
                      child: Text(args.title, style: folioDisplay(size: 22, weight: FontWeight.w400)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_canSwitchFile && _fixingOne) ...[
                        const Text('选择视频', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _fileId,
                          isExpanded: true,
                          decoration: const InputDecoration(),
                          items: [
                            for (final file in _selectableFiles)
                              DropdownMenuItem(
                                value: file.id,
                                child: Text(file.displayName, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) _selectFile(value);
                          },
                        ),
                        if (_locator.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _locator.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.35),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ] else if (_wholeWork && _kind == 'series') ...[
                        Text(
                          _wholeWorkHint(),
                          style: const TextStyle(color: FolioColors.inkMuted, fontSize: 14, height: 1.45),
                        ),
                        const SizedBox(height: 8),
                      ] else if (_displayName.isNotEmpty) ...[
                        Text(
                          _displayName,
                          style: const TextStyle(color: FolioColors.inkMuted, fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_canSwitchFile && args.initialKind == 'series')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() => _wholeWork = !_wholeWork),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: FolioColors.copper,
                            ),
                            child: Text(_wholeWork && _kind == 'series' ? '只改一集' : '整部改挂'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _kindToggle(),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _query,
                              decoration: const InputDecoration(hintText: '搜索片名…'),
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _search(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _searchButton(),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _year,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '年份',
                                hintText: yearHint,
                              ),
                            ),
                          ),
                          if (_kind == 'series' && _fixingOne) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _season,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '季',
                                  hintText: _parsedSeason == null ? '季' : '默认 $_parsedSeason',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _episode,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: '集',
                                  hintText: _parsedEpisode == null ? '集' : '默认 $_parsedEpisode',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!, style: const TextStyle(color: FolioColors.danger)),
                        ),
                      const SizedBox(height: 14),
                      Expanded(child: _results()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchButton() {
    return Material(
      color: FolioColors.teal,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _searching ? null : _search,
        borderRadius: BorderRadius.circular(999),
        child: Opacity(
          opacity: _searching ? 0.6 : 1,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              _searching ? '搜索中…' : '搜索',
              style: const TextStyle(
                color: Color(0xFF061312),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kindToggle() {
    const gap = 4.0;
    final series = _kind == 'series';
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x660A0C10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: FolioColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(gap),
          child: SizedBox(
            width: 188,
            height: 36,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final thumb = (constraints.maxWidth - gap) / 2;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      left: series ? thumb + gap : 0,
                      top: 0,
                      bottom: 0,
                      width: thumb,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x38D4A574), Color(0x2E5FB3A8)],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _kindHit('电影', 'movie'),
                        const SizedBox(width: gap),
                        _kindHit('剧集', 'series'),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _wholeWorkHint() {
    final ready = _selectableFiles.where((item) => item.parsedSeason != null && item.parsedEpisode != null).length;
    final skipped = _selectableFiles.length - ready;
    final base = '按各自文件名里的季、集，把 $ready 个视频改挂到所选剧。';
    if (skipped <= 0) return base;
    return '$base有 $skipped 个文件名里没有季或集，会留在待处理。';
  }

  Widget _kindHit(String label, String value) {
    final active = _kind == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setKind(value),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: active ? FolioColors.ink : FolioColors.inkMuted,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _results() {
    if (_searching) {
      return const Center(child: FolioLoading());
    }
    if (_candidates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('暂无结果，可改关键词后重试。', style: TextStyle(color: FolioColors.inkMuted)),
      );
    }
    return ListView.separated(
      itemCount: _candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _candidates[index];
        final title = item.title ?? item.originalTitle ?? '未命名';
        final overview = item.overview?.trim();
        final meta = [
          if (item.originalTitle != null &&
              item.originalTitle!.trim().isNotEmpty &&
              item.originalTitle != item.title)
            item.originalTitle!.trim(),
          if (item.year != null) '${item.year}' else '年份未知',
          item.kind == 'series' ? '剧集' : '电影',
          '相似度 ${item.score.toStringAsFixed(2)}',
        ].join(' · ');
        return Material(
          color: const Color(0xB312151C),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _choose(item),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: FolioColors.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    height: 78,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PosterImage(
                        url: item.posterUrl,
                        fallback: title.isEmpty ? '·' : title.substring(0, 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.35),
                        ),
                        if (overview != null && overview.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _wholeWork && _kind == 'series' ? '整部改挂到这部剧' : '使用此项刮削',
                          style: const TextStyle(color: FolioColors.copper, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MatchChoice {
  const MatchChoice({
    required this.fileId,
    required this.candidate,
    required this.tmdbId,
    this.year,
    this.season,
    this.episode,
    this.scope,
  });

  final int fileId;
  final MatchCandidate candidate;
  final int tmdbId;
  final int? year;
  final int? season;
  final int? episode;
  final String? scope;
}
