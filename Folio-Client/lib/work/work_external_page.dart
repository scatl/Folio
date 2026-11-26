import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/router/router_path.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

/// 按 TMDB 外部键打开作品：页内拉取/懒入库后 replace 到 `/works/{id}`。
class WorkExternalPage extends ConsumerStatefulWidget {
  const WorkExternalPage({
    super.key,
    required this.provider,
    required this.externalId,
    required this.kind,
  });

  final String provider;
  final String externalId;
  final String kind;

  @override
  ConsumerState<WorkExternalPage> createState() => _WorkExternalPageState();
}

class _WorkExternalPageState extends ConsumerState<WorkExternalPage> {
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final provider = widget.provider.trim();
    final externalId = widget.externalId.trim();
    final kind = widget.kind.trim();
    if (provider.isEmpty || externalId.isEmpty || kind.isEmpty) {
      setState(() {
        _loading = false;
        _error = '无效的作品参数';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final detail = await api.get(
        ApiPath.works.detail,
        queryParameters: {
          'provider': provider,
          'externalId': externalId,
          'kind': kind,
        },
        parser: jsonParser(WorkDetail.fromJson),
      );
      if (!mounted) return;
      context.go(RouterPath.work(detail.id));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(RouterPath.home);
                        }
                      },
                      icon: const Icon(Icons.arrow_back, color: FolioColors.ink),
                      tooltip: '返回',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: _loading
                      ? const FolioLoading()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error ?? '加载失败',
                              style: TextStyle(fontFamily: folioSystemFont(), color: FolioColors.inkMuted),
                            ),
                            const SizedBox(height: 12),
                            TextButton(onPressed: _load, child: const Text('重试')),
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
}
