import 'dart:convert';

import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';

/// Registro de auditoria imutavel (o banco rejeita UPDATE e DELETE).
class AuditService {
  final Library lib;
  AuditService(this.lib);

  static const _sensitive = {'password_hash', 'code_hash', 'password'};

  static String? _enc(Object? v) {
    if (v == null) return null;
    if (v is Map) {
      final clean = Map<String, Object?>.from(v.cast<String, Object?>())
        ..removeWhere((k, _) => _sensitive.contains(k));
      return jsonEncode(clean);
    }
    return v is String ? v : jsonEncode(v);
  }

  Future<void> log(
    Session? s,
    String action,
    String? entity,
    String? entityId, {
    Object? oldValue,
    Object? newValue,
    String? details,
    String? actorId,
    String? actorName,
  }) =>
      lib.db.insertMap('audit_logs', {
        'id': newId(),
        'at': AppClock.nowMs(),
        'user_id': s?.userId ?? actorId,
        'user_name': s?.name ?? actorName,
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'old_value': _enc(oldValue),
        'new_value': _enc(newValue),
        'details': details,
      });

  Future<List<Map<String, Object?>>> list(Session s,
      {String? search, int limit = 200, int offset = 0}) async {
    s.require(Permission.auditView);
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      return lib.db.q(
          'SELECT * FROM audit_logs WHERE action LIKE ? OR user_name LIKE ? OR details LIKE ? '
          'ORDER BY at DESC LIMIT ? OFFSET ?',
          [like, like, like, limit, offset]);
    }
    return lib.db.q('SELECT * FROM audit_logs ORDER BY at DESC LIMIT ? OFFSET ?', [limit, offset]);
  }

  static String describe(String action) => const {
        'setup.complete': 'Configuração inicial',
        'auth.login': 'Login',
        'auth.login_failed': 'Falha de login',
        'auth.locked': 'Conta bloqueada por tentativas',
        'auth.logout': 'Saída',
        'auth.recovery_reset': 'Senha redefinida por código de recuperação',
        'auth.password_change': 'Troca de senha',
        'auth.signup': 'Autocadastro',
        'user.create': 'Usuário cadastrado',
        'user.update': 'Usuário alterado',
        'user.status': 'Situação do usuário alterada',
        'user.password_reset': 'Senha redefinida pelo administrador',
        'user.unlock': 'Usuário desbloqueado',
        'user.recovery_code': 'Novo código de recuperação',
        'book.create': 'Livro cadastrado',
        'book.update': 'Livro alterado',
        'book.archive': 'Livro arquivado',
        'book.unarchive': 'Livro reativado',
        'copy.create': 'Exemplares adicionados',
        'copy.status': 'Situação de exemplar alterada',
        'loan.create': 'Empréstimo',
        'loan.return': 'Devolução',
        'loan.renew': 'Renovação',
        'loan.cancel': 'Empréstimo cancelado',
        'loan.undo_return': 'Devolução desfeita',
        'loan.due_change': 'Prazo alterado',
        'settings.update': 'Regras alteradas',
        'calendar.add': 'Calendário: dias fechados',
        'calendar.remove': 'Calendário: dia removido',
        'backup.create': 'Backup criado',
        'backup.restore': 'Backup restaurado',
      }[action] ??
      action;
}
