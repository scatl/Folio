import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

class CreateLibraryPage extends ConsumerStatefulWidget {
  const CreateLibraryPage({super.key});

  @override
  ConsumerState<CreateLibraryPage> createState() => _CreateLibraryPageState();
}

class _CreateLibraryPageState extends ConsumerState<CreateLibraryPage> {
  final _name = TextEditingController();
  final _path = TextEditingController();
  String _kind = 'movie';
  bool _submitting = false;
  String? _error;
  BrowseResult? _browse;
  bool _browseLoading = true;
  String? _browseError;

  @override
  void initState() {
    super.initState();
    _path.addListener(() {
      if (mounted) setState(() {});
    });
    _loadBrowse();
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    super.dispose();
  }

  Future<void> _loadBrowse([String? path]) async {
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      final result = await ref.read(apiClientProvider).get(
            ApiPath.libraries.browse,
            queryParameters: {if (path != null && path.isNotEmpty) 'path': path},
            parser: jsonParser(BrowseResult.fromJson),
          );
      if (mounted) setState(() => _browse = result);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _browseError = failure.message);
    } finally {
      if (mounted) setState(() => _browseLoading = false);
    }
  }

  void _selectDir(String path) {
    _path.text = path;
    _loadBrowse(path);
  }

  Future<void> _submit() async {
    final root = _path.text.trim();
    if (root.isEmpty || _submitting) return;
    final name = _name.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final library = await ref.read(apiClientProvider).post(
            ApiPath.libraries.list,
            data: {
              if (name.isNotEmpty) 'name': name,
              'kind': _kind,
              'rootPath': root,
            },
            parser: jsonParser(MediaLibrary.fromJson),
          );
      if (mounted) context.pop(library);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Expanded(child: Text('创建资料库', style: folioDisplay(size: 22, weight: FontWeight.w400))),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择类型与服务器目录。创建后会在后台扫描视频并入队刮削。',
                        style: TextStyle(color: FolioColors.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      const Text('名称（可选）', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
                      const SizedBox(height: 10),
                      TextField(controller: _name, decoration: const InputDecoration(hintText: '例如：家庭电影')),
                      const SizedBox(height: 18),
                      const Text('类型', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
                      const SizedBox(height: 10),
                      _kindToggle(),
                      const SizedBox(height: 18),
                      const Text('服务器目录', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
                      const SizedBox(height: 10),
                      TextField(controller: _path, decoration: const InputDecoration(hintText: '从下方选择，或直接输入路径')),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text('目录浏览', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
                          const Spacer(),
                          _ghostButton(
                            label: '上级',
                            enabled: !_browseLoading && _browse?.parent != null && !_submitting,
                            onTap: () => _loadBrowse(_browse!.parent!.isEmpty ? null : _browse!.parent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _browserPanel()),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: const TextStyle(color: FolioColors.danger)),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _path.text.trim().isEmpty || _submitting ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: FolioColors.copper,
                          foregroundColor: const Color(0xFF1A1208),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(_submitting ? '创建中…' : '创建并开始刮削'),
                      ),
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

  Widget _ghostButton({required String label, required bool enabled, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: FolioColors.line),
            ),
            child: Text(label, style: const TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _browserPanel() {
    final current = _browse?.path.isNotEmpty == true ? _browse!.path : '（根目录）';
    final selected = _path.text.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x590A0C10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FolioColors.lineStrong, style: BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.folder_open_rounded, size: 16, color: FolioColors.teal),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current,
                    style: const TextStyle(color: FolioColors.teal, fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: FolioColors.line),
          Expanded(child: _browserBody(selected)),
        ],
      ),
    );
  }

  Widget _browserBody(String selected) {
    if (_browseError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_browseError!, style: const TextStyle(color: FolioColors.danger, height: 1.4)),
      );
    }
    if (_browseLoading && _browse == null) {
      return const Center(child: FolioSpinner());
    }
    final dirs = _browse?.directories ?? const [];
    if (dirs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '此目录下没有子目录，可直接用作资料库路径。',
          style: TextStyle(color: FolioColors.inkMuted, height: 1.45),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      itemCount: dirs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = dirs[index];
        final active = selected == entry.path;
        return Material(
          color: active ? const Color(0x24D4A574) : const Color(0xB312151C),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _submitting || _browseLoading ? null : () => _selectDir(entry.path),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? const Color(0x73D4A574) : FolioColors.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 20,
                    color: active ? FolioColors.copper : FolioColors.inkMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: FolioColors.inkFaint, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: active ? FolioColors.copper : FolioColors.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  Widget _kindHit(String label, String value) {
    final active = _kind == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_kind == value) return;
          setState(() => _kind = value);
        },
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

}
