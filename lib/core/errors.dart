/// Erro de regra de negocio com mensagem pronta para o usuario.
class AppException implements Exception {
  final String message;
  final String? code;
  AppException(this.message, {this.code});
  @override
  String toString() => message;
}

/// Lancado quando a sessao atual nao tem permissao para a operacao.
/// A verificacao acontece nos servicos, nao so na interface.
class PermissionDenied extends AppException {
  PermissionDenied(String what) : super('Acesso negado: $what.', code: 'permission');
}

class ValidationException extends AppException {
  ValidationException(super.message) : super(code: 'validation');
}
