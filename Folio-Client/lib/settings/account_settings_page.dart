import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/dialog/blur_dialog_scaffold.dart';
import 'package:folio/widget/dialog/confirm_dialog.dart';
import 'package:folio/widget/folio_widgets.dart';
import 'package:go_router/go_router.dart';

final accountSettingsProvider = NotifierProvider.autoDispose<AccountSettingsViewModel, AccountSettingsState>(
  AccountSettingsViewModel.new,
);

class AccountSettingsState {
  const AccountSettingsState({
    this.loading = true,
    this.saving = false,
    this.users = const [],
    this.error,
  });

  final bool loading;
  final bool saving;
  final List<AuthUser> users;
  final String? error;

  AccountSettingsState copyWith({
    bool? loading,
    bool? saving,
    List<AuthUser>? users,
    Object? error = _keep,
  }) {
    return AccountSettingsState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      users: users ?? this.users,
      error: error == _keep ? this.error : error as String?,
    );
  }
}

const _keep = Object();

class AccountSettingsViewModel extends Notifier<AccountSettingsState> {
  @override
  AccountSettingsState build() {
    Future.microtask(load);
    return const AccountSettingsState();
  }

  bool get _admin => ref.read(sessionProvider).isAdmin;

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = ref.read(apiClientProvider);
      final List<AuthUser> users;
      if (_admin) {
        users = await api.get(ApiPath.users.list, parser: listParser(AuthUser.fromJson));
      } else {
        final me = await api.get(ApiPath.auth.me, parser: jsonParser(AuthUser.fromJson));
        users = [me];
      }
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, users: users);
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  Future<String?> createUser({
    required String username,
    required String password,
    required String role,
    List<LibraryPermission> libraries = const [],
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(apiClientProvider).post<AuthUser>(
            ApiPath.users.list,
            data: {
              'username': username,
              'password': password,
              'role': role,
              'libraries': role == 'ADMIN' ? const [] : libraries.map((item) => item.toJson()).toList(),
            },
            parser: jsonParser(AuthUser.fromJson),
          );
      if (!ref.mounted) return null;
      state = state.copyWith(saving: false);
      await load();
      return '已创建用户';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      state = state.copyWith(saving: false);
      return failure.message;
    }
  }

  Future<String?> updateUser({
    required AuthUser user,
    required String username,
    required String password,
    required String currentPassword,
  }) async {
    final session = ref.read(sessionProvider);
    final self = user.id == session.userId;
    state = state.copyWith(saving: true, error: null);
    try {
      final api = ref.read(apiClientProvider);
      if (!session.isAdmin) {
        await api.post<AuthUser>(
          ApiPath.auth.account,
          data: {
            'currentPassword': currentPassword,
            'username': username == user.username ? null : username,
            'newPassword': password.isEmpty ? null : password,
          },
          parser: jsonParser(AuthUser.fromJson),
        );
      } else {
        await api.patch<AuthUser>(
          ApiPath.users.one(user.id),
          data: {
            'username': username == user.username ? null : username,
            'newPassword': password.isEmpty ? null : password,
          },
          parser: jsonParser(AuthUser.fromJson),
        );
      }
      if (!ref.mounted) return null;
      if (self && (username != user.username || password.isNotEmpty)) {
        if (username != user.username) {
          await ref.read(sessionProvider.notifier).renameUser(username);
        }
        await ref.read(sessionProvider.notifier).signOut();
        return null;
      }
      state = state.copyWith(saving: false);
      await load();
      return '已保存';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      state = state.copyWith(saving: false);
      return failure.message;
    }
  }

  Future<String?> updateLibraries(AuthUser user, List<LibraryPermission> libraries) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(apiClientProvider).patch<AuthUser>(
            ApiPath.users.one(user.id),
            data: {'libraries': libraries.map((item) => item.toJson()).toList()},
            parser: jsonParser(AuthUser.fromJson),
          );
      if (!ref.mounted) return null;
      state = state.copyWith(saving: false);
      await load();
      return '已保存资料库权限';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      state = state.copyWith(saving: false);
      return failure.message;
    }
  }

  Future<String?> setDisabled(AuthUser user, bool disabled) async {
    state = state.copyWith(error: null);
    try {
      await ref.read(apiClientProvider).patch<AuthUser>(
            ApiPath.users.one(user.id),
            data: {'disabled': disabled},
            parser: jsonParser(AuthUser.fromJson),
          );
      if (!ref.mounted) return null;
      await load();
      return disabled ? '已禁用' : '已启用';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      return failure.message;
    }
  }

  Future<String?> deleteUser(AuthUser user) async {
    state = state.copyWith(error: null);
    try {
      await ref.read(apiClientProvider).delete<Object?>(ApiPath.users.one(user.id));
      if (!ref.mounted) return null;
      await load();
      return '已删除';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      return failure.message;
    }
  }

  Future<bool> _unauthorized(ApiFailure failure) async {
    if (!failure.unauthorized) return false;
    await ref.read(sessionProvider.notifier).signOut();
    return true;
  }
}

class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  ConsumerState<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTab);
  }

  void _onTab() {
    if (_tabs.indexIsChanging || !mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    super.dispose();
  }

  bool get _adminTab => _tabs.index == 0;

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(accountSettingsProvider);
    final session = ref.watch(sessionProvider);
    final admins = ui.users.where((user) => user.isAdmin).toList();
    final members = ui.users.where((user) => !user.isAdmin).toList();
    final visible = !session.isAdmin
        ? ui.users
        : (_adminTab ? admins : members);
    final activeAdmins = admins.where((user) => !user.disabled).length;
    return FolioBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: session.isAdmin
            ? FloatingActionButton(
                tooltip: '新建用户',
                onPressed: ui.saving ? null : () => _create(context, ref),
                child: const Icon(Icons.add),
              )
            : null,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                child: Row(
                  children: [
                    IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back)),
                    Expanded(child: Text('账号', style: folioDisplay(size: 22, weight: FontWeight.w400))),
                  ],
                ),
              ),
              if (ui.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(ui.error!, style: const TextStyle(color: FolioColors.danger, fontSize: 13)),
                ),
              if (session.isAdmin) _roleTabBar(const ['管理员', '普通用户']),
              Expanded(
                child: ui.loading
                    ? const Center(child: Text('加载中…', style: TextStyle(color: FolioColors.inkMuted)))
                    : visible.isEmpty
                        ? Center(
                            child: Text(
                              _adminTab ? '还没有管理员。' : '还没有普通用户。',
                              style: const TextStyle(color: FolioColors.inkMuted),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, session.isAdmin ? 88 : 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final user = visible[index];
                              final lastAdmin = user.isAdmin && !user.disabled && activeAdmins <= 1;
                              final canModerate = session.isAdmin && user.id != session.userId && !lastAdmin;
                              final isSelf = user.id == session.userId;
                              return _UserTile(
                                user: user,
                                isSelf: isSelf,
                                saving: ui.saving,
                                onEdit: isSelf ? () => _edit(context, ref, user) : null,
                                onLibraries: session.isAdmin && !user.isAdmin
                                    ? () => _editLibraries(context, ref, user)
                                    : null,
                                onToggle: canModerate ? () => _toggle(context, ref, user) : null,
                                onDelete: canModerate ? () => _delete(context, ref, user) : null,
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

  Widget _roleTabBar(List<String> labels) {
    return TabBar(
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
      tabs: [for (final label in labels) Tab(text: label)],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final libraries = await _loadLibraries(ref);
    if (!context.mounted) return;
    final result = await showFolioDialog<_EditorInput>(
      context: context,
      builder: (context, animation) => _AccountDialog(
        animation: animation,
        creating: true,
        availableLibraries: libraries,
      ),
    );
    if (result == null) return;
    final message = await ref.read(accountSettingsProvider.notifier).createUser(
          username: result.username,
          password: result.password,
          role: result.role,
          libraries: result.libraries,
        );
    if (context.mounted) _showMessage(context, message);
  }

  Future<void> _editLibraries(BuildContext context, WidgetRef ref, AuthUser user) async {
    final libraries = await _loadLibraries(ref);
    if (!context.mounted) return;
    final result = await showFolioDialog<List<LibraryPermission>>(
      context: context,
      builder: (context, animation) => _LibraryPermissionDialog(
        animation: animation,
        username: user.username,
        availableLibraries: libraries,
        initial: user.libraries,
      ),
    );
    if (result == null) return;
    final message = await ref.read(accountSettingsProvider.notifier).updateLibraries(user, result);
    if (context.mounted) _showMessage(context, message);
  }

  Future<List<MediaLibrary>> _loadLibraries(WidgetRef ref) async {
    try {
      return await ref.read(apiClientProvider).get(
            ApiPath.libraries.list,
            parser: listParser(MediaLibrary.fromJson),
          );
    } on ApiFailure {
      return const [];
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AuthUser user) async {
    final admin = ref.read(sessionProvider).isAdmin;
    final result = await showFolioDialog<_EditorInput>(
      context: context,
      builder: (context, animation) => _AccountDialog(
        animation: animation,
        creating: false,
        user: user,
        requireCurrentPassword: !admin,
      ),
    );
    if (result == null) return;
    final message = await ref.read(accountSettingsProvider.notifier).updateUser(
          user: user,
          username: result.username,
          password: result.password,
          currentPassword: result.currentPassword,
        );
    if (context.mounted) _showMessage(context, message);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, AuthUser user) async {
    final next = !user.disabled;
    final ok = await ConfirmDialog.show(
      context,
      title: '${next ? '禁用' : '启用'}「${user.username}」',
      confirmText: next ? '禁用' : '启用',
      destructive: next,
    );
    if (ok != true || !context.mounted) return;
    final message = await ref.read(accountSettingsProvider.notifier).setDisabled(user, next);
    if (context.mounted) _showMessage(context, message);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AuthUser user) async {
    final ok = await ConfirmDialog.show(
      context,
      title: '删除「${user.username}」',
      message: '该用户的播放进度会一起删除。',
      confirmText: '删除',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    final message = await ref.read(accountSettingsProvider.notifier).deleteUser(user);
    if (context.mounted) _showMessage(context, message);
  }
}

void _showMessage(BuildContext context, String? message) {
  if (message == null) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}

enum _UserAction { edit, libraries, toggle, delete }

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.saving,
    this.onEdit,
    this.onLibraries,
    this.onToggle,
    this.onDelete,
  });

  final AuthUser user;
  final bool isSelf;
  final bool saving;
  final VoidCallback? onEdit;
  final VoidCallback? onLibraries;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final initial = user.username.trim().isEmpty ? '?' : user.username.trim().characters.first.toUpperCase();
    final chips = <({String label, _ChipTone tone})>[
      if (!user.isAdmin) (label: user.libraries.isEmpty ? '无资料库' : '${user.libraries.length} 个库', tone: _ChipTone.soft),
      if (user.disabled) (label: '已禁用', tone: _ChipTone.danger),
      if (isSelf) (label: '当前', tone: _ChipTone.accent),
    ];
    final menuItems = <PopupMenuEntry<_UserAction>>[
      if (onEdit != null) const PopupMenuItem(value: _UserAction.edit, child: Text('修改密码')),
      if (onLibraries != null) const PopupMenuItem(value: _UserAction.libraries, child: Text('资料库权限')),
      if (onToggle != null) PopupMenuItem(value: _UserAction.toggle, child: Text(user.disabled ? '启用' : '禁用')),
      if (onDelete != null)
        const PopupMenuItem(
          value: _UserAction.delete,
          child: Text('删除', style: TextStyle(color: FolioColors.danger)),
        ),
    ];
    return Opacity(
      opacity: user.disabled ? 0.72 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelf ? const Color(0x47D4A574) : FolioColors.line),
          gradient: isSelf
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x1AD4A574), Color(0x6912151C)],
                )
              : null,
          color: isSelf ? null : const Color(0x6B12151C),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelf ? const Color(0x47D4A574) : FolioColors.copperSoft,
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: isSelf ? FolioColors.ink : FolioColors.copper,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      user.username,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                    ),
                    for (final chip in chips) _MetaChip(label: chip.label, tone: chip.tone),
                  ],
                ),
              ),
              if (menuItems.isNotEmpty)
                PopupMenuButton<_UserAction>(
                  tooltip: '更多',
                  enabled: !saving,
                  color: FolioColors.bgPanel,
                  onSelected: (action) {
                    switch (action) {
                      case _UserAction.edit:
                        onEdit?.call();
                      case _UserAction.libraries:
                        onLibraries?.call();
                      case _UserAction.toggle:
                        onToggle?.call();
                      case _UserAction.delete:
                        onDelete?.call();
                    }
                  },
                  itemBuilder: (_) => menuItems,
                  icon: const Icon(Icons.more_vert, color: FolioColors.inkMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ChipTone { soft, accent, danger }

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.tone});

  final String label;
  final _ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color border, Color bg) = switch (tone) {
      _ChipTone.accent => (FolioColors.copper, const Color(0x66D4A574), const Color(0x1AD4A574)),
      _ChipTone.danger => (FolioColors.danger, const Color(0x66E07A6B), const Color(0x1AE07A6B)),
      _ChipTone.soft => (FolioColors.inkMuted, FolioColors.line, const Color(0x14F2EFE8)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
        color: bg,
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, height: 1.2)),
    );
  }
}

class _EditorInput {
  const _EditorInput({
    required this.username,
    required this.password,
    required this.currentPassword,
    required this.role,
    this.libraries = const [],
  });

  final String username;
  final String password;
  final String currentPassword;
  final String role;
  final List<LibraryPermission> libraries;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.animation,
    required this.creating,
    this.user,
    this.requireCurrentPassword = false,
    this.availableLibraries = const [],
  });

  final Animation<double> animation;
  final bool creating;
  final AuthUser? user;
  final bool requireCurrentPassword;
  final List<MediaLibrary> availableLibraries;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _username;
  final _password = TextEditingController();
  final _currentPassword = TextEditingController();
  String _role = 'USER';
  String? _error;
  late final Map<int, String> _libraryAccess;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.user?.username ?? '');
    if (widget.user?.isAdmin == true) _role = 'ADMIN';
    _libraryAccess = {
      for (final library in widget.availableLibraries) library.id: '',
    };
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.length < 2) {
      setState(() => _error = '用户名至少 2 个字符');
      return;
    }
    if (widget.creating && password.length < 4) {
      setState(() => _error = '密码至少 4 个字符');
      return;
    }
    if (password.isNotEmpty && password.length < 4) {
      setState(() => _error = '密码至少 4 个字符');
      return;
    }
    if (widget.requireCurrentPassword && _currentPassword.text.isEmpty) {
      setState(() => _error = '请输入当前密码');
      return;
    }
    if (!widget.creating && username == widget.user?.username && password.isEmpty) {
      setState(() => _error = '没有要修改的内容');
      return;
    }
    Navigator.pop(
      context,
      _EditorInput(
        username: username,
        password: password,
        currentPassword: _currentPassword.text,
        role: _role,
        libraries: _selectedLibraries(),
      ),
    );
  }

  List<LibraryPermission> _selectedLibraries() {
    if (_role == 'ADMIN') return const [];
    return _libraryAccess.entries
        .where((entry) => entry.value == 'READ' || entry.value == 'WRITE')
        .map((entry) => LibraryPermission(libraryId: entry.key, access: entry.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.86;
    return BlurDialogScaffold(
      animation: widget.animation,
      onBarrierTap: () => Navigator.pop(context),
      panelConstraints: BoxConstraints.tightFor(width: width),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.creating ? '新建用户' : '修改账号', style: folioDisplay(size: 20)),
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              decoration: const InputDecoration(labelText: '用户名'),
              autocorrect: false,
            ),
            if (widget.requireCurrentPassword) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _currentPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: widget.creating ? '密码' : '新密码（不改可留空）'),
            ),
            if (widget.creating) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                dropdownColor: FolioColors.bgSoft,
                decoration: const InputDecoration(labelText: '角色'),
                items: const [
                  DropdownMenuItem(value: 'USER', child: Text('普通用户')),
                  DropdownMenuItem(value: 'ADMIN', child: Text('管理员')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              if (_role == 'USER') ...[
                const SizedBox(height: 16),
                _LibraryPermissionList(
                  libraries: widget.availableLibraries,
                  access: _libraryAccess,
                  onChanged: (libraryId, value) => setState(() => _libraryAccess[libraryId] = value),
                ),
              ],
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: FolioColors.danger, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            FolioDialogActions(
              cancelText: '取消',
              confirmText: '保存',
              onCancel: () => Navigator.pop(context),
              onConfirm: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryPermissionDialog extends StatefulWidget {
  const _LibraryPermissionDialog({
    required this.animation,
    required this.username,
    required this.availableLibraries,
    required this.initial,
  });

  final Animation<double> animation;
  final String username;
  final List<MediaLibrary> availableLibraries;
  final List<LibraryPermission> initial;

  @override
  State<_LibraryPermissionDialog> createState() => _LibraryPermissionDialogState();
}

class _LibraryPermissionDialogState extends State<_LibraryPermissionDialog> {
  late final Map<int, String> _access;

  @override
  void initState() {
    super.initState();
    _access = {
      for (final library in widget.availableLibraries) library.id: '',
    };
    for (final item in widget.initial) {
      _access[item.libraryId] = item.access;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.86;
    return BlurDialogScaffold(
      animation: widget.animation,
      onBarrierTap: () => Navigator.pop(context),
      panelConstraints: BoxConstraints.tightFor(width: width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('资料库权限 · ${widget.username}', style: folioDisplay(size: 20)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            child: _LibraryPermissionList(
              libraries: widget.availableLibraries,
              access: _access,
              onChanged: (libraryId, value) => setState(() => _access[libraryId] = value),
            ),
          ),
          const SizedBox(height: 20),
          FolioDialogActions(
            cancelText: '取消',
            confirmText: '保存',
            onCancel: () => Navigator.pop(context),
            onConfirm: () {
              final selected = _access.entries
                  .where((entry) => entry.value == 'READ' || entry.value == 'WRITE')
                  .map((entry) => LibraryPermission(libraryId: entry.key, access: entry.value))
                  .toList();
              Navigator.pop(context, selected);
            },
          ),
        ],
      ),
    );
  }
}

class _LibraryPermissionList extends StatelessWidget {
  const _LibraryPermissionList({
    required this.libraries,
    required this.access,
    required this.onChanged,
  });

  final List<MediaLibrary> libraries;
  final Map<int, String> access;
  final void Function(int libraryId, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    if (libraries.isEmpty) {
      return const Text('还没有资料库可分配。', style: TextStyle(color: FolioColors.inkMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('资料库权限', style: TextStyle(color: FolioColors.inkMuted, fontSize: 13)),
        const SizedBox(height: 8),
        for (final library in libraries) ...[
          Row(
            children: [
              Expanded(
                child: Text(library.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
                child: DropdownButtonFormField<String>(
                  initialValue: access[library.id] ?? '',
                  dropdownColor: FolioColors.bgSoft,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('无')),
                    DropdownMenuItem(value: 'READ', child: Text('只读')),
                    DropdownMenuItem(value: 'WRITE', child: Text('读写')),
                  ],
                  onChanged: (value) {
                    if (value != null) onChanged(library.id, value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
