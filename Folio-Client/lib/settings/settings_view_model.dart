import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/session/session_view_model.dart';
import 'package:folio/settings/settings_ui_state.dart';

const settingsSecretMask = '********';
const defaultTmdbImageBaseUrl = 'https://image.tmdb.org/t/p/original';

final settingsProvider = NotifierProvider.autoDispose<SettingsViewModel, SettingsUiState>(
  SettingsViewModel.new,
);

class SettingsViewModel extends Notifier<SettingsUiState> {
  final tmdbKey = TextEditingController();
  final omdbKey = TextEditingController();
  final tvdbKey = TextEditingController();
  final tvdbPin = TextEditingController();
  final fields = <String, TextEditingController>{};

  @override
  SettingsUiState build() {
    for (final key in const [
      'tmdbBaseUrl',
      'tmdbImageBaseUrl',
      'tmdbLanguage',
      'tmdbSearchLanguage',
      'tmdbRequestsPerSecond',
      'omdbBaseUrl',
      'omdbRequestsPerSecond',
      'tvdbBaseUrl',
      'tvdbRequestsPerSecond',
      'httpTimeoutSeconds',
      'matchAutoThreshold',
      'workerDelayMs',
      'workerMaxAttempts',
      'workerConcurrency',
      'scanIntervalMinutes',
      'playbackIgnoreBelowSeconds',
      'playbackCompleteRemainingSeconds',
    ]) {
      fields[key] = TextEditingController();
    }
    ref.onDispose(() {
      tmdbKey.dispose();
      omdbKey.dispose();
      tvdbKey.dispose();
      tvdbPin.dispose();
      for (final controller in fields.values) {
        controller.dispose();
      }
    });
    Future.microtask(load);
    return const SettingsUiState();
  }

  void setWatchEnabled(bool value) => state = state.copyWith(watchEnabled: value);

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final data = await ref.read(apiClientProvider).get(ApiPath.settings, parser: jsonParser(AppSettings.fromJson));
      if (!ref.mounted) return;
      _apply(data);
      state = state.copyWith(loading: false, snapshot: data);
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  void _apply(AppSettings data) {
    _set('tmdbBaseUrl', data.tmdbBaseUrl);
    _set('tmdbImageBaseUrl', data.tmdbImageBaseUrl);
    _set('tmdbLanguage', data.tmdbLanguage);
    _set('tmdbSearchLanguage', data.tmdbSearchLanguage);
    _set('tmdbRequestsPerSecond', _num(data.tmdbRequestsPerSecond));
    _set('omdbBaseUrl', data.omdbBaseUrl);
    _set('omdbRequestsPerSecond', _num(data.omdbRequestsPerSecond));
    _set('tvdbBaseUrl', data.tvdbBaseUrl);
    _set('tvdbRequestsPerSecond', _num(data.tvdbRequestsPerSecond));
    _set('httpTimeoutSeconds', '${data.httpTimeoutSeconds}');
    _set('matchAutoThreshold', _num(data.matchAutoThreshold));
    _set('workerDelayMs', '${data.workerDelayMs}');
    _set('workerMaxAttempts', '${data.workerMaxAttempts}');
    _set('workerConcurrency', '${data.workerConcurrency}');
    _set('scanIntervalMinutes', '${data.scanIntervalMinutes}');
    _set('playbackIgnoreBelowSeconds', '${data.playbackIgnoreBelowSeconds}');
    _set('playbackCompleteRemainingSeconds', '${data.playbackCompleteRemainingSeconds}');
    tmdbKey.text = data.tmdbApiKeyConfigured ? settingsSecretMask : '';
    omdbKey.text = data.omdbApiKeyConfigured ? settingsSecretMask : '';
    tvdbKey.text = data.tvdbApiKeyConfigured ? settingsSecretMask : '';
    tvdbPin.text = data.tvdbPinConfigured ? settingsSecretMask : '';
    state = state.copyWith(
      watchEnabled: data.watchEnabled,
      snapshot: data,
    );
  }

  /// 返回要提示的文案。会话失效时返回 `null`。
  Future<String?> save() async {
    final snapshot = state.snapshot;
    if (snapshot == null) return null;
    state = state.copyWith(saving: true, error: null);
    final Map<String, dynamic> body;
    try {
      body = {
        'tmdbApiKey': _secret(tmdbKey.text, snapshot.tmdbApiKeyConfigured),
        'tmdbBaseUrl': fields['tmdbBaseUrl']!.text,
        'tmdbImageBaseUrl': fields['tmdbImageBaseUrl']!.text,
        'tmdbLanguage': fields['tmdbLanguage']!.text,
        'tmdbSearchLanguage': fields['tmdbSearchLanguage']!.text,
        'tmdbRequestsPerSecond': _double('tmdbRequestsPerSecond'),
        'omdbApiKey': _secret(omdbKey.text, snapshot.omdbApiKeyConfigured),
        'omdbBaseUrl': fields['omdbBaseUrl']!.text,
        'omdbRequestsPerSecond': _double('omdbRequestsPerSecond'),
        'tvdbEnabled': tvdbKey.text.trim().isNotEmpty,
        'tvdbApiKey': _secret(tvdbKey.text, snapshot.tvdbApiKeyConfigured),
        'tvdbPin': _secret(tvdbPin.text, snapshot.tvdbPinConfigured),
        'tvdbBaseUrl': fields['tvdbBaseUrl']!.text,
        'tvdbRequestsPerSecond': _double('tvdbRequestsPerSecond'),
        'httpTimeoutSeconds': _int('httpTimeoutSeconds'),
        'matchAutoThreshold': _double('matchAutoThreshold'),
        'workerDelayMs': _int('workerDelayMs'),
        'workerMaxAttempts': _int('workerMaxAttempts'),
        'workerConcurrency': _int('workerConcurrency'),
        'scanIntervalMinutes': _int('scanIntervalMinutes'),
        'watchEnabled': state.watchEnabled,
        'playbackIgnoreBelowSeconds': _int('playbackIgnoreBelowSeconds'),
        'playbackCompleteRemainingSeconds': _int('playbackCompleteRemainingSeconds'),
      };
    } on FormatException {
      state = state.copyWith(saving: false);
      return '请检查数字格式';
    }
    try {
      final updated = await ref.read(apiClientProvider).put(
            ApiPath.settings,
            data: body,
            parser: jsonParser(AppSettings.fromJson),
          );
      if (!ref.mounted) return null;
      _apply(updated);
      state = state.copyWith(saving: false, error: null, snapshot: updated);
      return '已保存';
    } on ApiFailure catch (failure) {
      if (!ref.mounted || await _unauthorized(failure)) return null;
      state = state.copyWith(saving: false);
      return failure.message;
    }
  }

  void selectMask(TextEditingController controller) {
    if (controller.text == settingsSecretMask) {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    }
  }

  void resetTmdbImageBaseUrl() {
    fields['tmdbImageBaseUrl']!.text = defaultTmdbImageBaseUrl;
  }

  bool get isTmdbImageBaseUrlDefault =>
      fields['tmdbImageBaseUrl']!.text.trim() == defaultTmdbImageBaseUrl;

  String? _secret(String typed, bool configured) {
    final value = typed.trim();
    if (value == settingsSecretMask) return null;
    if (value.isEmpty) return configured ? '' : null;
    return value;
  }

  void _set(String key, String value) => fields[key]!.text = value;

  String _num(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  double _double(String key) => double.parse(fields[key]!.text.trim());

  int _int(String key) => int.parse(fields[key]!.text.trim());

  Future<bool> _unauthorized(ApiFailure failure) async {
    if (!failure.unauthorized) return false;
    await ref.read(sessionProvider.notifier).signOut();
    return true;
  }
}
