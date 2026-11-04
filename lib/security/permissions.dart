import '../core/errors.dart';
import '../core/util.dart';

/// Papeis do sistema. HOST = administrador, STAFF = auxiliar/monitor,
/// USER = aluno/leitor.
enum Role {
  host('host', 'Administrador (HOST)'),
  staff('staff', 'Auxiliar / Monitor'),
  user('user', 'Leitor (USER)');

  final String id;
  final String label;
  const Role(this.id, this.label);

  static Role fromId(String id) =>
      Role.values.firstWhere((r) => r.id == id, orElse: () => Role.user);
}

enum Permission {
  catalogView,
  catalogManage,
  usersView,
  usersManage,
  manageAdmins,
  circulationOperate,
  circulationOverride,
  dueControlView,
  dashboardView,
  settingsManage,
  backupCreate,
  backupRestore,
  auditView,
  ownLoansView,
  favoritesManage,
}

const Map<Role, Set<Permission>> rolePermissions = {
  Role.host: {
    Permission.catalogView,
    Permission.catalogManage,
    Permission.usersView,
    Permission.usersManage,
    Permission.manageAdmins,
    Permission.circulationOperate,
    Permission.circulationOverride,
    Permission.dueControlView,
    Permission.dashboardView,
    Permission.settingsManage,
    Permission.backupCreate,
    Permission.backupRestore,
    Permission.auditView,
    Permission.ownLoansView,
    Permission.favoritesManage,
  },
  Role.staff: {
    Permission.catalogView,
    Permission.usersView,
    Permission.circulationOperate,
    Permission.dueControlView,
    Permission.dashboardView,
    Permission.ownLoansView,
    Permission.favoritesManage,
  },
  Role.user: {
    Permission.catalogView,
    Permission.ownLoansView,
    Permission.favoritesManage,
  },
};

/// Sessao autenticada. Todos os servicos recebem a sessao e chamam
/// [require] antes de qualquer leitura ou escrita protegida.
class Session {
  final String userId;
  final String name;
  final String username;
  final Role role;
  final int startedAt;
  bool _closed = false;

  Session({
    required this.userId,
    required this.name,
    required this.username,
    required this.role,
  }) : startedAt = AppClock.nowMs();

  bool get isActive => !_closed;
  void close() => _closed = true;

  bool can(Permission p) => !_closed && (rolePermissions[role]?.contains(p) ?? false);

  void require(Permission p) {
    if (_closed) throw PermissionDenied('sessão encerrada');
    if (!can(p)) throw PermissionDenied(_describe(p));
  }

  /// Garante que um leitor so acesse os proprios dados.
  void requireSelfOr(String targetUserId, Permission p) {
    if (_closed) throw PermissionDenied('sessão encerrada');
    if (targetUserId == userId) return;
    require(p);
  }

  static String _describe(Permission p) => switch (p) {
        Permission.catalogView => 'consultar o catálogo',
        Permission.catalogManage => 'gerenciar o acervo',
        Permission.usersView => 'consultar usuários',
        Permission.usersManage => 'gerenciar usuários',
        Permission.manageAdmins => 'gerenciar administradores',
        Permission.circulationOperate => 'registrar empréstimos e devoluções',
        Permission.circulationOverride => 'liberar bloqueios de empréstimo',
        Permission.dueControlView => 'ver o controle de devoluções',
        Permission.dashboardView => 'ver o painel administrativo',
        Permission.settingsManage => 'alterar as regras da biblioteca',
        Permission.backupCreate => 'criar backups',
        Permission.backupRestore => 'restaurar backups',
        Permission.auditView => 'ver a auditoria',
        Permission.ownLoansView => 'ver empréstimos',
        Permission.favoritesManage => 'gerenciar favoritos',
      };
}
