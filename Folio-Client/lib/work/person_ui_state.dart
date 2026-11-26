import 'package:folio/api/entity/models.dart';

class PersonUiState {
  const PersonUiState({
    this.loading = true,
    this.refreshing = false,
    this.error,
    this.detail,
  });

  final bool loading;
  final bool refreshing;
  final String? error;
  final PersonDetail? detail;

  PersonUiState copyWith({
    bool? loading,
    bool? refreshing,
    Object? error = _keep,
    Object? detail = _keep,
  }) {
    return PersonUiState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: error == _keep ? this.error : error as String?,
      detail: detail == _keep ? this.detail : detail as PersonDetail?,
    );
  }
}

const _keep = Object();
