import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/work/collection_ui_state.dart';

final collectionProvider = NotifierProvider.autoDispose.family<CollectionViewModel, CollectionUiState, String>(
  CollectionViewModel.new,
);

class CollectionViewModel extends Notifier<CollectionUiState> {
  CollectionViewModel(this.collectionId);

  final String collectionId;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  CollectionUiState build() {
    Future.microtask(load);
    return const CollectionUiState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final detail = await _api.get(
        ApiPath.collections.one(collectionId),
        parser: jsonParser(CollectionDetail.fromJson),
      );
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, detail: detail, error: null);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }
}
