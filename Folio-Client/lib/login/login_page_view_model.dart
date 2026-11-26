import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/http/api_client.dart';
import 'package:folio/login/login_page_ui_state.dart';
import 'package:folio/session/session_view_model.dart';

final loginPageProvider = NotifierProvider.autoDispose<LoginPageViewModel, LoginPageUiState>(
  LoginPageViewModel.new,
);

class LoginPageViewModel extends Notifier<LoginPageUiState> {
  @override
  LoginPageUiState build() => const LoginPageUiState();

  Future<void> loadPosters(String server) async {
    if (server.trim().isEmpty) return;
    try {
      final urls = await ref.read(sessionProvider.notifier).loginPosters(server);
      state = state.copyWith(posters: urls);
    } catch (_) {
      // 登录页海报只是背景。
    }
  }

  Future<void> submit({
    required String server,
    required String username,
    required String password,
  }) async {
    if (state.submitting) return;
    state = state.copyWith(submitting: true, error: null);
    try {
      await ref.read(sessionProvider.notifier).signIn(
            server: server,
            username: username,
            password: password,
          );
    } on ApiFailure catch (error) {
      state = state.copyWith(submitting: false, error: error.message);
    } catch (_) {
      state = state.copyWith(submitting: false, error: '登录失败');
    }
  }
}
