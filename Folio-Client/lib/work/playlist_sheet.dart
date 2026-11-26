import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/wall/wall_page_view_model.dart';

class PlaylistPickerSheet extends ConsumerStatefulWidget {
  const PlaylistPickerSheet({super.key, required this.workId});

  final int workId;

  @override
  ConsumerState<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<PlaylistPickerSheet> {
  final _name = TextEditingController();
  var _loading = true;
  var _saving = false;
  String? _error;
  List<PlaylistSummary> _lists = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lists = await ref.read(apiClientProvider).get(
            ApiPath.playlists.list,
            queryParameters: {'workId': widget.workId, 'limit': 100},
            parser: listParser(PlaylistSummary.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loading = false;
      });
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _refreshHome() {
    ref.read(wallPageProvider.notifier).reloadPlaylists();
  }

  Future<void> _toggle(PlaylistSummary item) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (item.contains) {
        await ref.read(apiClientProvider).delete(
              ApiPath.playlists.item(item.id, widget.workId),
              parser: jsonParser(PlaylistDetail.fromJson),
            );
        if (!mounted) return;
        setState(() {
          _lists = [
            for (final row in _lists)
              if (row.id == item.id)
                PlaylistSummary(
                  id: row.id,
                  name: row.name,
                  itemCount: row.itemCount > 0 ? row.itemCount - 1 : 0,
                  posterUrl: row.posterUrl,
                  contains: false,
                )
              else
                row,
          ];
          _saving = false;
        });
      } else {
        final updated = await ref.read(apiClientProvider).post(
              ApiPath.playlists.items(item.id),
              data: {'workId': widget.workId},
              parser: jsonParser(PlaylistSummary.fromJson),
            );
        if (!mounted) return;
        setState(() {
          _lists = [
            for (final row in _lists)
              if (row.id == item.id) updated else row,
          ];
          _saving = false;
        });
      }
      _refreshHome();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写播放列表名称');
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(apiClientProvider).post(
            ApiPath.playlists.list,
            data: {'name': name, 'workId': widget.workId},
            parser: jsonParser(PlaylistSummary.fromJson),
          );
      if (!mounted) return;
      setState(() {
        _lists = [created, ..._lists.where((item) => item.id != created.id)];
        _saving = false;
      });
      _name.clear();
      _refreshHome();
    } on ApiFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('添加到播放列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    maxLength: 40,
                    style: const TextStyle(color: FolioColors.ink),
                    decoration: const InputDecoration(
                      hintText: '新播放列表名称',
                      counterText: '',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _create,
                  style: FilledButton.styleFrom(backgroundColor: FolioColors.copper, foregroundColor: const Color(0xFF1A140E)),
                  child: const Text('创建'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFE7B2A4))),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: FolioColors.copper))
                : _lists.isEmpty
                    ? const Center(child: Text('还没有播放列表', style: TextStyle(color: FolioColors.inkMuted)))
                    : ListView.builder(
                        itemCount: _lists.length,
                        itemBuilder: (context, index) {
                          final item = _lists[index];
                          return ListTile(
                            enabled: !_saving,
                            onTap: () => _toggle(item),
                            leading: Icon(
                              item.contains ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              color: item.contains ? FolioColors.copper : FolioColors.inkMuted,
                            ),
                            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.itemCount} 项'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
