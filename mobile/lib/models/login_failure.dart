enum LoginFailureType {
  invalidCredentials,
  unverifiedEmail,
  validation,
  network,
  unknown,
}

class LoginFailureException implements Exception {
  final LoginFailureType type;
  final String message;

  const LoginFailureException({required this.type, required this.message});

  bool get countsAsAttempt => type == LoginFailureType.invalidCredentials;

  @override
  String toString() => message;
}
