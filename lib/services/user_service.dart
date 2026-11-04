import '../core/errors.dart';
import '../core/util.dart';
import '../library.dart';
import '../security/crypto.dart';
import '../security/permissions.dart';
import 'auth_service.dart';

class UserInput {
  final Role role;
  final String name;
  final String username;
  final String? enrollment;
  final String? className;
  final String? grade;
  final String? shift;
  final String? schoolYear;
  final String? email;
  final String? phone;
  final bool isMinor;
  final String? guardianName;
  final String? guardianPhone;
  final bool contactAuthorized;
  final bool guardianConsent;

  UserInput({
    required this.role,
    required this.name,
    required this.username,
    this.enrollment,
    this.className,
    this.grade,
    this.shift,
    this.schoolYear,
    this.email,
    this.phone,
    this.isMinor = false,
    this.guardianName,
    this.guardianPhone,
    this.contactAuthorized = false,
    this.guardianConsent = false,
  });
}

/// Cadastro e consulta de usuarios. Usuarios nunca sao apagados: sao
/// inativados, para preservar o historico de emprestimos.
class UserService {
  final Library lib;
  UserService(this.lib);

  static const statusLabels = {
    'active': 'Ativo',
    'pending': 'Aguardando aprovação',
    'inactive': 'Inativo',
    'transferred': 'Transferido',
    'graduated': 'Formado',
  };

  Future<String> nextCardCode() async {
    final r = await lib.db.q1("SELECT value FROM app_meta WHERE key = 'next_card'");
    var n = int.tryParse(r?['value'] as String? ?? '') ?? 1;
    // Garante unicidade mesmo apos restauracoes/mesclas.
    while (await lib.db.q1('SELECT 1 FROM users WHERE card_code = ?', [_card(n)]) != null) {
      n++;
    }
    await lib.db.x(
        "INSERT INTO app_meta (key, value) VALUES ('next_card', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        ['${n + 1}']);
    return _card(n);
  }

  static String _card(int n) => 'U${n.toString().padLeft(6, '0')}';

  String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Insercao de baixo nivel (validacoes comuns). Nao verifica permissao.
  Future<String> insertUser({
    required Role role,
    required String name,
    required String username,
    required String password,
    required String status,
    String? enrollment,
    String? className,
    String? grade,
    String? shift,
    String? schoolYear,
    String? email,
    String? phone,
    bool isMinor = false,
    String? guardianName,
    String? guardianPhone,
    bool contactAuthorized = false,
    bool consent = true,
    bool guardianConsent = false,
    bool mustChangePassword = false,
    String? createdBy,
  }) async {
    if (name.trim().length < 2) throw ValidationException('Informe o nome completo.');
    AuthService.validateUsername(username.trim());
    AuthService.validatePassword(password, role);
    if (email != null && email.trim().isNotEmpty && !email.contains('@')) {
      throw ValidationException('E-mail inválido.');
    }
    final hash = await PasswordHasher.hash(password);
    final id = newId();
    final now = AppClock.nowMs();
    await lib.db.transaction(() async {
      if (await lib.db.q1('SELECT 1 FROM users WHERE username = ? COLLATE NOCASE', [username.trim()]) !=
          null) {
        throw ValidationException('O usuário "${username.trim()}" já existe.');
      }
      final enr = _clean(enrollment);
      if (enr != null && await lib.db.q1('SELECT 1 FROM users WHERE enrollment = ?', [enr]) != null) {
        throw ValidationException('A matrícula $enr já está cadastrada.');
      }
      await lib.db.insertMap('users', {
        'id': id,
        'role_id': role.id,
        'name': name.trim(),
        'name_norm': normalize(name),
        'username': username.trim(),
        'password_hash': hash,
        'card_code': await nextCardCode(),
        'enrollment': enr,
        'class_name': _clean(className),
        'grade': _clean(grade),
        'shift': _clean(shift),
        'school_year': _clean(schoolYear),
        'status': status,
        'email': _clean(email),
        'phone': _clean(phone),
        'guardian_name': _clean(guardianName),
        'guardian_phone': _clean(guardianPhone),
        'contact_authorized': contactAuthorized,
        'is_minor': isMinor,
        'consent_at': consent ? now : null,
        'guardian_consent_at': guardianConsent ? now : null,
        'must_change_password': mustChangePassword,
        'created_by': createdBy,
        'created_at': now,
        'updated_at': now,
      });
    });
    return id;
  }

  void _checkRoleChange(Session s, Role target) {
    if (target != Role.user) s.require(Permission.manageAdmins);
  }

  /// Cadastro feito pelo HOST. Contas criadas pela biblioteca precisam
  /// trocar a senha no primeiro acesso.
  Future<({String id, String? recoveryCode})> create(
      Session s, UserInput d, String initialPassword) async {
    s.require(Permission.usersManage);
    _checkRoleChange(s, d.role);
    final id = await insertUser(
      role: d.role,
      name: d.name,
      username: d.username,
      password: initialPassword,
      status: 'active',
      enrollment: d.enrollment,
      className: d.className,
      grade: d.grade,
      shift: d.shift,
      schoolYear: d.schoolYear,
      email: d.email,
      phone: d.phone,
      isMinor: d.isMinor,
      guardianName: d.guardianName,
      guardianPhone: d.guardianPhone,
      contactAuthorized: d.contactAuthorized,
      guardianConsent: d.guardianConsent,
      mustChangePassword: true,
      createdBy: s.userId,
    );
    await lib.audit.log(s, 'user.create', 'users', id,
        newValue: {'name': d.name.trim(), 'username': d.username.trim(), 'role': d.role.id});
    String? code;
    if (d.role != Role.user) code = await _issueRecoveryCode(id);
    return (id: id, recoveryCode: code);
  }

  Future<String> _issueRecoveryCode(String userId) async {
    final code = generateRecoveryCode();
    final hash = await PasswordHasher.hash(normalizeRecoveryCode(code));
    final now = AppClock.nowMs();
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE recovery_codes SET used_at = ? WHERE user_id = ? AND used_at IS NULL',
          [now, userId]);
      await lib.db.insertMap('recovery_codes',
          {'id': newId(), 'user_id': userId, 'code_hash': hash, 'created_at': now});
    });
    return code;
  }

  /// Gera um novo codigo de recuperacao para a propria conta administrativa.
  Future<String> regenerateOwnRecoveryCode(Session s, String currentPassword) async {
    if (s.role == Role.user) throw PermissionDenied('códigos de recuperação');
    if (!await lib.auth.confirmPassword(s, currentPassword)) {
      throw AppException('Senha incorreta.');
    }
    final code = await _issueRecoveryCode(s.userId);
    await lib.audit.log(s, 'user.recovery_code', 'users', s.userId);
    return code;
  }

  Future<void> update(Session s, String id, UserInput d) async {
    s.require(Permission.usersManage);
    final old = await lib.db.q1('SELECT * FROM users WHERE id = ?', [id]);
    if (old == null) throw AppException('Usuário não encontrado.');
    final oldRole = Role.fromId(old['role_id'] as String);
    if (oldRole != Role.user || d.role != Role.user) s.require(Permission.manageAdmins);
    if (oldRole == Role.host && d.role != Role.host) await _ensureAnotherHost(id);
    if (d.name.trim().length < 2) throw ValidationException('Informe o nome completo.');
    AuthService.validateUsername(d.username.trim());
    await lib.db.transaction(() async {
      if (await lib.db.q1('SELECT 1 FROM users WHERE username = ? COLLATE NOCASE AND id <> ?',
              [d.username.trim(), id]) !=
          null) {
        throw ValidationException('O usuário "${d.username.trim()}" já existe.');
      }
      final enr = _clean(d.enrollment);
      if (enr != null &&
          await lib.db.q1('SELECT 1 FROM users WHERE enrollment = ? AND id <> ?', [enr, id]) != null) {
        throw ValidationException('A matrícula $enr já está cadastrada.');
      }
      final now = AppClock.nowMs();
      final newVals = <String, Object?>{
        'role_id': d.role.id,
        'name': d.name.trim(),
        'name_norm': normalize(d.name),
        'username': d.username.trim(),
        'enrollment': enr,
        'class_name': _clean(d.className),
        'grade': _clean(d.grade),
        'shift': _clean(d.shift),
        'school_year': _clean(d.schoolYear),
        'email': _clean(d.email),
        'phone': _clean(d.phone),
        'is_minor': d.isMinor ? 1 : 0,
        'guardian_name': _clean(d.guardianName),
        'guardian_phone': _clean(d.guardianPhone),
        'contact_authorized': d.contactAuthorized ? 1 : 0,
      };
      if (d.guardianConsent && old['guardian_consent_at'] == null) {
        newVals['guardian_consent_at'] = now;
      }
      final cols = newVals.keys.toList();
      await lib.db.x(
          'UPDATE users SET ${cols.map((c) => '$c = ?').join(', ')}, updated_at = ? WHERE id = ?',
          [...cols.map((c) => newVals[c]), now, id]);
      final before = {for (final c in cols) c: old[c]};
      await lib.audit.log(s, 'user.update', 'users', id, oldValue: before, newValue: newVals);
    });
  }

  Future<void> _ensureAnotherHost(String excludingId) async {
    final n = await lib.db.count(
        "SELECT count(*) FROM users WHERE role_id = 'host' AND status = 'active' AND id <> ?",
        [excludingId]);
    if (n == 0) {
      throw AppException('É preciso manter pelo menos um administrador ativo.');
    }
  }

  Future<void> setStatus(Session s, String id, String status) async {
    s.require(Permission.usersManage);
    if (!statusLabels.containsKey(status)) throw ValidationException('Situação inválida.');
    final old = await lib.db.q1('SELECT * FROM users WHERE id = ?', [id]);
    if (old == null) throw AppException('Usuário não encontrado.');
    final role = Role.fromId(old['role_id'] as String);
    if (role != Role.user) s.require(Permission.manageAdmins);
    if (id == s.userId && status != 'active') {
      throw AppException('Você não pode desativar a própria conta.');
    }
    if (role == Role.host && status != 'active') await _ensureAnotherHost(id);
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE users SET status = ?, updated_at = ? WHERE id = ?',
          [status, AppClock.nowMs(), id]);
      await lib.audit.log(s, 'user.status', 'users', id,
          oldValue: {'status': old['status']}, newValue: {'status': status});
    });
  }

  Future<void> resetPassword(Session s, String id, String newPassword) async {
    s.require(Permission.usersManage);
    final u = await lib.db.q1('SELECT * FROM users WHERE id = ?', [id]);
    if (u == null) throw AppException('Usuário não encontrado.');
    final role = Role.fromId(u['role_id'] as String);
    if (role != Role.user) s.require(Permission.manageAdmins);
    AuthService.validatePassword(newPassword, role);
    final hash = await PasswordHasher.hash(newPassword);
    await lib.db.transaction(() async {
      await lib.db.x(
          'UPDATE users SET password_hash = ?, must_change_password = 1, failed_attempts = 0, locked_until = NULL, updated_at = ? WHERE id = ?',
          [hash, AppClock.nowMs(), id]);
      await lib.audit.log(s, 'user.password_reset', 'users', id);
    });
  }

  Future<void> unlock(Session s, String id) async {
    s.require(Permission.usersManage);
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = ?', [id]);
      await lib.audit.log(s, 'user.unlock', 'users', id);
    });
  }

  Future<List<Map<String, Object?>>> list(Session s,
      {String? search, Role? role, String? status, int limit = 500}) async {
    s.require(Permission.usersView);
    final where = <String>['u.deleted_at IS NULL'];
    final args = <Object?>[];
    if (role != null) {
      where.add('u.role_id = ?');
      args.add(role.id);
    }
    if (status != null) {
      where.add('u.status = ?');
      args.add(status);
    }
    final q = search?.trim() ?? '';
    if (q.isNotEmpty) {
      where.add('(u.name_norm LIKE ? OR u.username LIKE ? OR u.card_code LIKE ? OR u.enrollment LIKE ? OR u.class_name LIKE ?)');
      final like = '%${normalize(q)}%';
      final raw = '%$q%';
      args.addAll([like, raw, raw, raw, raw]);
    }
    args.add(limit);
    return lib.db.q(
        'SELECT u.id, u.name, u.username, u.role_id, u.card_code, u.enrollment, u.class_name, u.grade, '
        'u.status, u.locked_until, u.last_login_at, '
        "(SELECT count(*) FROM loans l WHERE l.user_id = u.id AND l.status = 'active') AS active_loans "
        'FROM users u WHERE ${where.join(' AND ')} ORDER BY u.name_norm LIMIT ?',
        args);
  }

  Future<Map<String, Object?>?> get(Session s, String id) async {
    s.requireSelfOr(id, Permission.usersView);
    final r = await lib.db.q1('SELECT * FROM users WHERE id = ?', [id]);
    if (r == null) return null;
    r.remove('password_hash');
    return r;
  }

  Future<Map<String, Object?>?> findByCode(Session s, String code) async {
    s.require(Permission.usersView);
    final c = code.trim();
    if (c.isEmpty) return null;
    final r = await lib.db.q1(
        'SELECT * FROM users WHERE deleted_at IS NULL AND (card_code = ? COLLATE NOCASE OR enrollment = ? OR username = ? COLLATE NOCASE) LIMIT 1',
        [c, c, c]);
    r?.remove('password_hash');
    return r;
  }
}
