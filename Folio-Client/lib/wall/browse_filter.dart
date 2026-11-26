import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/dialog/blur_dialog_scaffold.dart';
import 'package:folio/widget/sheet/blur_modal_bottom_sheet.dart';

class FacetOption {
  const FacetOption({required this.id, required this.label, required this.count});

  final String id;
  final String label;
  final int count;

  factory FacetOption.fromJson(Map<String, dynamic> json) => FacetOption(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        count: asIntOrNull(json['count']) ?? 0,
      );
}

class WorkFacets {
  const WorkFacets({
    this.genres = const [],
    this.countries = const [],
    this.languages = const [],
    this.keywords = const [],
    this.companies = const [],
    this.collections = const [],
    this.videoCodecs = const [],
    this.dynamicRanges = const [],
    this.audioCodecs = const [],
    this.people = const [],
    this.yearMin,
    this.yearMax,
  });

  final List<FacetOption> genres;
  final List<FacetOption> countries;
  final List<FacetOption> languages;
  final List<FacetOption> keywords;
  final List<FacetOption> companies;
  final List<FacetOption> collections;
  final List<String> videoCodecs;
  final List<String> dynamicRanges;
  final List<String> audioCodecs;
  final List<FacetOption> people;
  final int? yearMin;
  final int? yearMax;

  factory WorkFacets.fromJson(Map<String, dynamic> json) => WorkFacets(
        genres: _options(json['genres']),
        countries: _options(json['countries']),
        languages: _options(json['languages']),
        keywords: _options(json['keywords']),
        companies: _options(json['companies']),
        collections: _options(json['collections']),
        videoCodecs: _strings(json['videoCodecs']),
        dynamicRanges: _strings(json['dynamicRanges']),
        audioCodecs: _strings(json['audioCodecs']),
        people: _options(json['people']),
        yearMin: asIntOrNull(json['yearMin']),
        yearMax: asIntOrNull(json['yearMax']),
      );

  WorkFacets copyPeople(List<FacetOption> next) => WorkFacets(
        genres: genres,
        countries: countries,
        languages: languages,
        keywords: keywords,
        companies: companies,
        collections: collections,
        videoCodecs: videoCodecs,
        dynamicRanges: dynamicRanges,
        audioCodecs: audioCodecs,
        people: next,
        yearMin: yearMin,
        yearMax: yearMax,
      );
}

class WorkBrowseFilter {
  const WorkBrowseFilter({
    this.watch,
    this.sort = 'popularity',
    this.genreIds = const [],
    this.yearFrom,
    this.yearTo,
    this.ratingProvider,
    this.ratingMin,
    this.countries = const [],
    this.languages = const [],
    this.runtimes = const [],
    this.keywordIds = const [],
    this.personId,
    this.personLabel,
    this.companyIds = const [],
    this.collectionIds = const [],
    this.inCollection = false,
    this.showStatuses = const [],
    this.resolutions = const [],
    this.dynamicRanges = const [],
    this.videoCodecs = const [],
    this.audioCodecs = const [],
    this.subtitle,
  });

  final String? watch;
  final String sort;
  final List<String> genreIds;
  final String? yearFrom;
  final String? yearTo;
  final String? ratingProvider;
  final String? ratingMin;
  final List<String> countries;
  final List<String> languages;
  final List<String> runtimes;
  final List<String> keywordIds;
  final String? personId;
  final String? personLabel;
  final List<String> companyIds;
  final List<String> collectionIds;
  final bool inCollection;
  final List<String> showStatuses;
  final List<String> resolutions;
  final List<String> dynamicRanges;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final String? subtitle;

  bool get active => toQuery().isNotEmpty;

  int get extraCount {
    var count = 0;
    void add(String? value) {
      if (value != null && value.trim().isNotEmpty) count += 1;
    }

    add(watch);
    if (sort != 'popularity') count += 1;
    count += genreIds.length;
    add(yearFrom);
    add(yearTo);
    add(ratingProvider);
    add(ratingMin);
    count += countries.length + languages.length + runtimes.length + keywordIds.length;
    add(personId);
    count += companyIds.length + collectionIds.length;
    if (inCollection) count += 1;
    count += showStatuses.length + resolutions.length + dynamicRanges.length + videoCodecs.length + audioCodecs.length;
    add(subtitle);
    return count;
  }

  Map<String, dynamic> toQuery() {
    final query = <String, dynamic>{};
    void put(String key, String? value) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) query[key] = text;
    }

    void putAll(String key, List<String> values) {
      if (values.isNotEmpty) query[key] = values.join(',');
    }

    put('watch', watch);
    if (sort != 'popularity') query['sort'] = sort;
    putAll('genreId', genreIds);
    put('yearFrom', yearFrom);
    put('yearTo', yearTo);
    put('ratingProvider', ratingProvider);
    put('ratingMin', ratingMin);
    putAll('country', countries);
    putAll('language', languages);
    putAll('runtime', runtimes);
    putAll('keywordId', keywordIds);
    put('personId', personId);
    putAll('companyId', companyIds);
    putAll('collectionId', collectionIds);
    if (inCollection) query['inCollection'] = true;
    putAll('showStatus', showStatuses);
    putAll('resolution', resolutions);
    putAll('dynamicRange', dynamicRanges);
    putAll('videoCodec', videoCodecs);
    putAll('audioCodec', audioCodecs);
    put('subtitle', subtitle);
    return query;
  }
}

Future<WorkFacets> loadWorkFacets(ApiClient api, {int? libraryId, String? personQ}) {
  return api.get(
    ApiPath.works.facets,
    queryParameters: {
      'libraryId': ?libraryId,
      if (personQ != null && personQ.trim().isNotEmpty) 'personQ': personQ.trim(),
    },
    parser: jsonParser(WorkFacets.fromJson),
  );
}

Future<WorkBrowseFilter?> showBrowseSheet(
  BuildContext context,
  ApiClient api,
  WorkBrowseFilter initial, {
  int? libraryId,
}) {
  return showFolioSheet<WorkBrowseFilter>(
    context: context,
    maxHeightFactor: 0.88,
    builder: (context) => _BrowseSheet(api: api, initial: initial, libraryId: libraryId),
  );
}

class _BrowseSheet extends StatefulWidget {
  const _BrowseSheet({required this.api, required this.initial, required this.libraryId});

  final ApiClient api;
  final WorkBrowseFilter initial;
  final int? libraryId;

  @override
  State<_BrowseSheet> createState() => _BrowseSheetState();
}

class _BrowseSheetState extends State<_BrowseSheet> {
  late WorkBrowseFilter _filter = widget.initial;
  WorkFacets _facets = const WorkFacets();
  String? _error;
  final _person = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _person.dispose();
    super.dispose();
  }

  Future<void> _load({String? personQ}) async {
    try {
      final data = await loadWorkFacets(widget.api, libraryId: widget.libraryId, personQ: personQ);
      if (!mounted) return;
      setState(() {
        _facets = personQ == null ? data : _facets.copyPeople(data.people);
        _error = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }

  void _set(WorkBrowseFilter next) => setState(() => _filter = next);

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Text('筛选', style: folioDisplay(size: 20)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context, const WorkBrowseFilter()),
                child: const Text('清除'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, filter),
                child: const Text('完成'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: FolioColors.danger)),
            ),
          _menu('观看状态', filter.watch ?? '', const [
            ('', '全部'),
            ('unwatched', '未看'),
            ('watching', '在看'),
            ('watched', '已看'),
          ], (value) => _copy(watch: value.isEmpty ? null : value)),
          _menu('排序', filter.sort, const [
            ('popularity', '热度'),
            ('year', '年份'),
            ('rating', '评分'),
            ('added', '入库时间'),
          ], (value) => _copy(sort: value)),
          _options('类型', filter.genreIds, _facets.genres, (value) => _copy(genreIds: value)),
          _field('年份从', filter.yearFrom, (value) => _copy(yearFrom: value)),
          _field('年份到', filter.yearTo, (value) => _copy(yearTo: value)),
          _menu('评分来源', filter.ratingProvider ?? '', const [
            ('', '不限'),
            ('tmdb', 'TMDB'),
            ('imdb', 'IMDb'),
            ('rottentomatoes', '烂番茄'),
            ('metacritic', 'Metacritic'),
          ], (value) => _copy(ratingProvider: value.isEmpty ? null : value)),
          _field('最低评分', filter.ratingMin, (value) => _copy(ratingMin: value)),
          _options('地区', filter.countries, _facets.countries, (value) => _copy(countries: value)),
          _options('语言', filter.languages, _facets.languages, (value) => _copy(languages: value)),
          _many('片长', filter.runtimes, const [
            ('lt90', '90 分钟内'),
            ('m90', '90–120 分钟'),
            ('m120', '120–150 分钟'),
            ('m150', '150 分钟以上'),
          ], (value) => _copy(runtimes: value)),
          _options('关键词', filter.keywordIds, _facets.keywords, (value) => _copy(keywordIds: value)),
          _block(TextField(
            controller: _person,
            decoration: InputDecoration(
              labelText: filter.personLabel == null ? '演职员' : '演职员：${filter.personLabel}',
              suffixIcon: filter.personId == null
                  ? null
                  : IconButton(onPressed: () => _copy(personId: null, personLabel: null), icon: const Icon(Icons.close)),
            ),
            onChanged: (value) {
              if (value.trim().isEmpty) {
                setState(() => _facets = _facets.copyPeople(const []));
                return;
              }
              _load(personQ: value);
            },
          )),
          for (final person in _facets.people)
            ListTile(
              dense: true,
              title: Text(person.label),
              onTap: () {
                _person.clear();
                _copy(personId: person.id, personLabel: person.label);
                setState(() => _facets = _facets.copyPeople(const []));
              },
            ),
          _options('出品公司', filter.companyIds, _facets.companies, (value) => _copy(companyIds: value)),
          _options('系列', filter.collectionIds, _facets.collections, (value) => _copy(collectionIds: value)),
          _block(SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('只看系列作品'),
            value: filter.inCollection,
            onChanged: (value) => _copy(inCollection: value),
          )),
          _many('连载状态', filter.showStatuses, const [
            ('airing', '连载中'),
            ('ended', '已完结'),
            ('canceled', '已取消'),
          ], (value) => _copy(showStatuses: value)),
          _many('分辨率', filter.resolutions, const [
            ('2160', '4K'),
            ('1080', '1080p'),
            ('720', '720p'),
            ('sd', '标清'),
          ], (value) => _copy(resolutions: value)),
          _many('动态范围', filter.dynamicRanges, [
            for (final item in ['sdr', ..._facets.dynamicRanges])
              if (item.isNotEmpty) (item, item == 'sdr' ? 'SDR' : item),
          ], (value) => _copy(dynamicRanges: value)),
          _many('视频编码', filter.videoCodecs, [
            for (final item in _facets.videoCodecs)
              if (item.isNotEmpty) (item, item),
          ], (value) => _copy(videoCodecs: value)),
          _many('音轨编码', filter.audioCodecs, [
            for (final item in _facets.audioCodecs)
              if (item.isNotEmpty) (item, item),
          ], (value) => _copy(audioCodecs: value)),
          _menu('字幕', filter.subtitle ?? '', const [
            ('', '不限'),
            ('embedded', '有内嵌字幕'),
            ('none', '无内嵌字幕'),
          ], (value) => _copy(subtitle: value.isEmpty ? null : value)),
        ],
      ),
    );
  }

  void _copy({
    Object? watch = _keep,
    Object? sort = _keep,
    Object? genreIds = _keep,
    Object? yearFrom = _keep,
    Object? yearTo = _keep,
    Object? ratingProvider = _keep,
    Object? ratingMin = _keep,
    Object? countries = _keep,
    Object? languages = _keep,
    Object? runtimes = _keep,
    Object? keywordIds = _keep,
    Object? personId = _keep,
    Object? personLabel = _keep,
    Object? companyIds = _keep,
    Object? collectionIds = _keep,
    bool? inCollection,
    Object? showStatuses = _keep,
    Object? resolutions = _keep,
    Object? dynamicRanges = _keep,
    Object? videoCodecs = _keep,
    Object? audioCodecs = _keep,
    Object? subtitle = _keep,
  }) {
    final current = _filter;
    List<String> many(Object? next, List<String> previous) => next == _keep ? previous : List<String>.from(next as List);
    _set(WorkBrowseFilter(
      watch: watch == _keep ? current.watch : watch as String?,
      sort: sort == _keep ? current.sort : sort as String,
      genreIds: many(genreIds, current.genreIds),
      yearFrom: yearFrom == _keep ? current.yearFrom : yearFrom as String?,
      yearTo: yearTo == _keep ? current.yearTo : yearTo as String?,
      ratingProvider: ratingProvider == _keep ? current.ratingProvider : ratingProvider as String?,
      ratingMin: ratingMin == _keep ? current.ratingMin : ratingMin as String?,
      countries: many(countries, current.countries),
      languages: many(languages, current.languages),
      runtimes: many(runtimes, current.runtimes),
      keywordIds: many(keywordIds, current.keywordIds),
      personId: personId == _keep ? current.personId : personId as String?,
      personLabel: personLabel == _keep ? current.personLabel : personLabel as String?,
      companyIds: many(companyIds, current.companyIds),
      collectionIds: many(collectionIds, current.collectionIds),
      inCollection: inCollection ?? current.inCollection,
      showStatuses: many(showStatuses, current.showStatuses),
      resolutions: many(resolutions, current.resolutions),
      dynamicRanges: many(dynamicRanges, current.dynamicRanges),
      videoCodecs: many(videoCodecs, current.videoCodecs),
      audioCodecs: many(audioCodecs, current.audioCodecs),
      subtitle: subtitle == _keep ? current.subtitle : subtitle as String?,
    ));
  }

  Widget _block(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: child,
    );
  }

  Widget _menu(String label, String value, List<(String, String)> items, ValueChanged<String> onChanged) {
    final current = items.any((item) => item.$1 == value) ? value : '';
    final display = items.where((item) => item.$1 == current).map((item) => item.$2).firstOrNull ?? '';
    return _choice(label, display, items, current, onChanged);
  }

  Widget _options(String label, List<String> selected, List<FacetOption> options, ValueChanged<List<String>> onChanged) {
    final items = <(String, String)>[
      for (final item in options)
        if (item.id.isNotEmpty) (item.id, item.label),
    ];
    for (final id in selected) {
      if (id.isNotEmpty && items.every((item) => item.$1 != id)) items.add((id, id));
    }
    return _many(label, selected, items, onChanged);
  }

  Widget _many(String label, List<String> selected, List<(String, String)> items, ValueChanged<List<String>> onChanged) {
    final seen = <String>{};
    final rows = <(String, String)>[
      for (final item in items)
        if (item.$1.isNotEmpty && seen.add(item.$1)) item,
    ];
    final display = selected.isEmpty
        ? '不限'
        : selected.map((id) => rows.where((item) => item.$1 == id).map((item) => item.$2).firstOrNull ?? id).join('、');
    return _block(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final next = await _pickMany(label, rows, selected);
            if (next != null) onChanged(next);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }

  Future<List<String>?> _pickMany(String title, List<(String, String)> items, List<String> current) {
    final picked = List<String>.from(current);
    return showFolioDialog<List<String>>(
      context: context,
      builder: (ctx, animation) {
        final maxHeight = math.min(480.0, MediaQuery.sizeOf(ctx).height * 0.7);
        final width = math.min(300.0, MediaQuery.sizeOf(ctx).width - 48);
        return StatefulBuilder(
          builder: (context, setLocal) {
            return BlurDialogScaffold(
              animation: animation,
              onBarrierTap: () => Navigator.of(ctx).pop(),
              panelConstraints: BoxConstraints.tightFor(width: width),
              panelPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(title, style: folioDisplay(size: 20)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(List<String>.from(picked)),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                    Flexible(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: items.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final selected = picked.isEmpty;
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              leading: _FolioCheck(checked: selected),
                              title: Text('不限', style: TextStyle(color: selected ? FolioColors.copper : FolioColors.ink)),
                              onTap: () => Navigator.of(ctx).pop(<String>[]),
                            );
                          }
                          final item = items[index - 1];
                          final selected = picked.contains(item.$1);
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            leading: _FolioCheck(checked: selected),
                            title: Text(
                              item.$2,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: selected ? FolioColors.copper : FolioColors.ink),
                            ),
                            onTap: () {
                              setLocal(() {
                                if (selected) {
                                  picked.remove(item.$1);
                                } else {
                                  picked.add(item.$1);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _choice(
    String label,
    String display,
    List<(String, String)> items,
    String current,
    ValueChanged<String> onChanged,
  ) {
    return _block(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final next = await _pickOption(label, items, current);
            if (next != null) onChanged(next);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }

  Future<String?> _pickOption(String title, List<(String, String)> items, String current) {
    return showFolioDialog<String>(
      context: context,
      builder: (ctx, animation) {
        final maxHeight = math.min(480.0, MediaQuery.sizeOf(ctx).height * 0.7);
        final width = math.min(300.0, MediaQuery.sizeOf(ctx).width - 48);
        return BlurDialogScaffold(
          animation: animation,
          onBarrierTap: () => Navigator.of(ctx).pop(),
          panelConstraints: BoxConstraints.tightFor(width: width),
          panelPadding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                  child: Text(title, style: folioDisplay(size: 20)),
                ),
                Flexible(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final selected = item.$1 == current;
                      return ListTile(
                        dense: true,
                        title: Text(
                          item.$2,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: selected ? FolioColors.copper : FolioColors.ink),
                        ),
                        trailing: selected ? const Icon(Icons.check, color: FolioColors.copper, size: 20) : null,
                        onTap: () => Navigator.of(ctx).pop(item.$1),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _field(String label, String? value, ValueChanged<String?> onChanged) {
    return _block(TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onChanged: (next) => onChanged(next.trim().isEmpty ? null : next.trim()),
    ));
  }
}

const _keep = Object();

List<FacetOption> _options(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((item) => FacetOption.fromJson(Map<String, dynamic>.from(item))).where((item) => item.id.isNotEmpty).toList();
}

List<String> _strings(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
}

class _FolioCheck extends StatelessWidget {
  const _FolioCheck({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: checked ? 1 : 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, t, _) {
        final amount = t.clamp(0.0, 1.0);
        final fill = Color.lerp(Colors.transparent, FolioColors.copper, amount)!;
        final border = Color.lerp(FolioColors.lineStrong, FolioColors.copper, amount)!;
        final scale = 0.86 + 0.14 * t.clamp(0.0, 1.12);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: 1.5),
            ),
            child: CustomPaint(
              painter: _CheckPainter(amount, const Color(0xFF1A1208)),
            ),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.24, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.7)
      ..lineTo(size.width * 0.76, size.height * 0.34);
    final metric = path.computeMetrics().first;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) => oldDelegate.t != t || oldDelegate.color != color;
}
