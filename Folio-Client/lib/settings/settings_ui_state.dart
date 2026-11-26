import 'package:folio/api/entity/models.dart';

class SettingsUiState {
  const SettingsUiState({
    this.loading = true,
    this.saving = false,
    this.watchEnabled = true,
    this.section = 'source',
    this.error,
    this.snapshot,
  });

  final bool loading;
  final bool saving;
  final bool watchEnabled;
  final String section;
  final String? error;
  final AppSettings? snapshot;

  SettingsUiState copyWith({
    bool? loading,
    bool? saving,
    bool? watchEnabled,
    String? section,
    Object? error = _keep,
    Object? snapshot = _keep,
  }) {
    return SettingsUiState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      watchEnabled: watchEnabled ?? this.watchEnabled,
      section: section ?? this.section,
      error: error == _keep ? this.error : error as String?,
      snapshot: snapshot == _keep ? this.snapshot : snapshot as AppSettings?,
    );
  }
}

const _keep = Object();
