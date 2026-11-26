import 'package:folio/api/entity/models.dart';

class CollectionUiState {
  const CollectionUiState({
    this.loading = true,
    this.error,
    this.detail,
  });

  final bool loading;
  final String? error;
  final CollectionDetail? detail;

  CollectionUiState copyWith({
    bool? loading,
    Object? error = _keep,
    Object? detail = _keep,
  }) {
    return CollectionUiState(
      loading: loading ?? this.loading,
      error: error == _keep ? this.error : error as String?,
      detail: detail == _keep ? this.detail : detail as CollectionDetail?,
    );
  }
}

const _keep = Object();
