class LoginPageUiState {
  const LoginPageUiState({
    this.submitting = false,
    this.error,
    this.posters = const [],
  });

  final bool submitting;
  final String? error;
  final List<String> posters;

  LoginPageUiState copyWith({
    bool? submitting,
    Object? error = _keep,
    List<String>? posters,
  }) {
    return LoginPageUiState(
      submitting: submitting ?? this.submitting,
      error: error == _keep ? this.error : error as String?,
      posters: posters ?? this.posters,
    );
  }
}

const _keep = Object();
