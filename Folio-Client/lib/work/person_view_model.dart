import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/api/api_path.dart';
import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/work/person_ui_state.dart';

typedef PersonKey = ({String provider, String externalId});

final personProvider = NotifierProvider.autoDispose.family<PersonViewModel, PersonUiState, PersonKey>(
  PersonViewModel.new,
);

class PersonViewModel extends Notifier<PersonUiState> {
  PersonViewModel(this.key);

  final PersonKey key;

  ApiClient get _api => ref.read(apiClientProvider);

  @override
  PersonUiState build() {
    Future.microtask(load);
    return const PersonUiState();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final detail = await _api.get(
        ApiPath.people.one(key.provider, key.externalId),
        parser: jsonParser(PersonDetail.fromJson),
      );
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, detail: detail, error: null);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  Future<void> refresh() async {
    final current = state.detail;
    if (current == null || !current.canRefresh || state.refreshing) return;
    state = state.copyWith(refreshing: true, error: null);
    try {
      final detail = await _api.post(
        ApiPath.people.refresh(key.provider, key.externalId),
        parser: jsonParser(PersonDetail.fromJson),
      );
      if (!ref.mounted) return;
      state = state.copyWith(refreshing: false, detail: detail, error: null);
    } on ApiFailure catch (failure) {
      if (!ref.mounted) return;
      state = state.copyWith(refreshing: false, error: failure.message);
    }
  }
}
