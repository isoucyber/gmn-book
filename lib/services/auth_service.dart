import '../core/errors.dart';
import '../core/util.dart';
import '../library.dart';
import '../security/crypto.dart';
import '../security/permissions.dart';
import 'settings_service.dart';

class SetupData {
  final String schoolName;
  final String schoolAddress;
  final String schoolYear;
  final String hostName;
  final String hostUsername;
  final String hostPassword;
  final String? hostEmail;
  final int defaultLoanDays;
  final int maxLoansUser;
  final String alertDays;
  final String signupMode;

  SetupData({
    required this.schoolName,
    this.schoolAddress = '',
    this.schoolYear = '',
    required this.hostName,
    required this.hostUsername,
    required this.hostPassword,
    this.hostEmail,
    this.defaultLoanDays = 14,
    this.maxLoansUser = 2,
    this.alertDays = '7,3,1,0,-1',
    this.signupMode = 'approval',
  });
}

class SignupData {
  final String name;
  final String username;
  final String password;
  final String? enrollment;
  final String? className;
  final bool isMinor;
  final String? guardianName;
  final String? guardianPhone;
  final bool consent;
  final bool guardianConsent;

  SignupData({
    required this.name,
    required this.username,
    required this.password,
    this.enrollment,
    this.className,
    this.isMinor = false,
    this.guardianName,
    this.guardianPhone,
    required this.consent,
    this.guardianConsent = false,
  });
}

/// Primeiro acesso, login com bloqueio por tentativas, autocadastro e
/// recuperacao de senha offline por codigo.
class AuthService {
  final Library lib;
  AuthService(this.lib);

  static final _usernameRe = RegExp(r'^[a-zA-Z0-9._-]{3,40}$');
  static Future<String>? _dummyHash;

  static void validatePassword(String pw, Role role) {
    final min = role == Role.user ? 6 : 8;
    if (pw.length < min) {
      throw ValidationException('A senha precisa ter pelo menos $min caracteres.');
    }
    if (pw.length > 128) throw ValidationException('Senha longa demais (máx. 128).');
    if (role != Role.user &&
        (!RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'[0-9]').hasMatch(pw))) {
      throw ValidationException('Use letras e números na senha de administradores e auxiliares.');
    }
  }

  static void validateUsername(String u) {
    if (!_usernameRe.hasMatch(u)) {
      throw ValidationException(
          'Usuário deve ter de 3 a 40 caracteres: letras, números, ponto, hífen ou sublinhado.');
    }
  }

  /// Executa o assistente de primeira execucao. So funciona uma vez.
  /// Retorna o codigo de recuperacao (exibido uma unica vez).
  Future<String> completeSetup(SetupData d) async {
    if (await lib.isConfigured()) {
      throw AppException('A biblioteca já foi configurada neste aparelho.');
    }
    if (d.schoolName.trim().isEmpty) throw ValidationException('Informe o nome da escola.');
    if (d.hostName.trim().isEmpty) throw ValidationException('Informe o nome do administrador.');
    validateUsername(d.hostUsername.trim());
    validatePassword(d.hostPassword, Role.host);
    if (d.defaultLoanDays < 1 || d.defaultLoanDays > 365) {
      throw ValidationException('Prazo padrão deve estar entre 1 e 365 dias.');
    }
    if (d.maxLoansUser < 1 || d.maxLoansUser > 50) {
      throw ValidationException('Limite de livros deve estar entre 1 e 50.');
    }

    final hash = await PasswordHasher.hash(d.hostPassword);
    final code = generateRecoveryCode();
    final codeHash = await PasswordHasher.hash(normalizeRecoveryCode(code));
    final now = AppClock.nowMs();
    final hostId = newId();

    await lib.db.transaction(() async {
      if (await lib.isConfigured()) throw AppException('A biblioteca já foi configurada.');
      await lib.settings.writeRaw({
        for (final e in settingDefaults.entries) e.key: e.value,
        SettingKeys.schoolName: d.schoolName.trim(),
        SettingKeys.schoolAddress: d.schoolAddress.trim(),
        SettingKeys.schoolYear: d.schoolYear.trim(),
        SettingKeys.defaultLoanDays: '${d.defaultLoanDays}',
        SettingKeys.maxLoansUser: '${d.maxLoansUser}',
        SettingKeys.alertDays: d.alertDays,
        SettingKeys.signupMode: d.signupMode,
      });
      await lib.db.insertMap('users', {
        'id': hostId,
        'role_id': Role.host.id,
        'name': d.hostName.trim(),
        'name_norm': normalize(d.hostName),
        'username': d.hostUsername.trim(),
        'password_hash': hash,
        'card_code': await lib.users.nextCardCode(),
        'email': d.hostEmail,
        'status': 'active',
        'consent_at': now,
        'created_at': now,
        'updated_at': now,
      });
      await lib.db.insertMap('recovery_codes', {
        'id': newId(),
        'user_id': hostId,
        'code_hash': codeHash,
        'created_at': now,
      });
      await lib.db.x("INSERT INTO app_meta (key, value) VALUES ('setup_done', ?)", ['$now']);
      await lib.audit.log(null, 'setup.complete', 'users', hostId,
          actorId: hostId, actorName: d.hostName.trim(), details: d.schoolName.trim());
    });
    return code;
  }

  Future<Session> login(String login, String password) async {
    final ident = login.trim();
    if (ident.isEmpty || password.isEmpty) throw ValidationException('Informe usuário e senha.');
    final u = await lib.db.q1(
        'SELECT * FROM users WHERE deleted_at IS NULL AND (username = ? COLLATE NOCASE OR card_code = ? COLLATE NOCASE) LIMIT 1',
        [ident, ident]);
    final settings = await lib.settings.load();
    const generic = 'Usuário ou senha incorretos.';
    if (u == null) {
      // Gasta tempo similar para nao revelar se o usuario existe.
      await PasswordHasher.verify(password, await (_dummyHash ??= PasswordHasher.hash('gmn-dummy')));
      await lib.audit.log(null, 'auth.login_failed', 'users', null, details: 'login: $ident');
      throw AppException(generic, code: 'auth');
    }
    final now = AppClock.nowMs();
    final lockedUntil = toInt(u['locked_until']);
    if (lockedUntil != null && lockedUntil > now) {
      final mins = ((lockedUntil - now) / 60000).ceil();
      throw AppException(
          'Conta bloqueada por excesso de tentativas. Tente novamente em $mins min ou peça ao administrador para desbloquear.',
          code: 'locked');
    }
    final ok = await PasswordHasher.verify(password, u['password_hash'] as String);
    if (!ok) {
      final attempts = (toInt(u['failed_attempts']) ?? 0) + 1;
      final limit = settings.lockoutAttempts;
      if (attempts >= limit) {
        await lib.db.x(
            'UPDATE users SET failed_attempts = 0, locked_until = ? WHERE id = ?',
            [now + settings.lockoutMinutes * 60000, u['id']]);
        await lib.audit.log(null, 'auth.locked', 'users', u['id'] as String,
            actorId: u['id'] as String, actorName: u['name'] as String);
        throw AppException(
            'Conta bloqueada por ${settings.lockoutMinutes} min após $limit tentativas incorretas.',
            code: 'locked');
      }
      await lib.db.x('UPDATE users SET failed_attempts = ? WHERE id = ?', [attempts, u['id']]);
      await lib.audit.log(null, 'auth.login_failed', 'users', u['id'] as String,
          actorId: u['id'] as String, actorName: u['name'] as String);
      throw AppException('$generic Restam ${limit - attempts} tentativa(s).', code: 'auth');
    }
    final status = u['status'] as String;
    if (status == 'pending') {
      throw AppException('Cadastro aguardando aprovação da biblioteca.', code: 'pending');
    }
    if (status != 'active') {
      throw AppException('Esta conta está inativa. Procure a biblioteca.', code: 'inactive');
    }
    await lib.db.x(
        'UPDATE users SET failed_attempts = 0, locked_until = NULL, last_login_at = ? WHERE id = ?',
        [now, u['id']]);
    final s = Session(
      userId: u['id'] as String,
      name: u['name'] as String,
      username: u['username'] as String,
      role: Role.fromId(u['role_id'] as String),
    );
    await lib.audit.log(s, 'auth.login', 'users', s.userId);
    return s;
  }

  Future<void> logout(Session s) async {
    if (!s.isActive) return;
    await lib.audit.log(s, 'auth.logout', 'users', s.userId);
    s.close();
  }

  Future<bool> mustChangePassword(Session s) async {
    final r = await lib.db.q1('SELECT must_change_password FROM users WHERE id = ?', [s.userId]);
    return toBool(r?['must_change_password']);
  }

  Future<void> changePassword(Session s, String current, String next) async {
    if (!s.isActive) throw PermissionDenied('sessão encerrada');
    final u = await lib.db.q1('SELECT password_hash FROM users WHERE id = ?', [s.userId]);
    if (u == null || !await PasswordHasher.verify(current, u['password_hash'] as String)) {
      throw AppException('Senha atual incorreta.');
    }
    validatePassword(next, s.role);
    if (current == next) throw ValidationException('A nova senha deve ser diferente da atual.');
    final hash = await PasswordHasher.hash(next);
    await lib.db.transaction(() async {
      await lib.db.x(
          'UPDATE users SET password_hash = ?, must_change_password = 0, updated_at = ? WHERE id = ?',
          [hash, AppClock.nowMs(), s.userId]);
      await lib.audit.log(s, 'auth.password_change', 'users', s.userId);
    });
  }

  /// Reconfirma a senha da sessao atual antes de acoes sensiveis.
  Future<bool> confirmPassword(Session s, String password) async {
    final u = await lib.db.q1('SELECT password_hash FROM users WHERE id = ?', [s.userId]);
    if (u == null) return false;
    return PasswordHasher.verify(password, u['password_hash'] as String);
  }

  /// Redefine a senha de um administrador usando o codigo de recuperacao
  /// (funciona offline). Retorna um NOVO codigo; o antigo deixa de valer.
  Future<String> resetWithRecoveryCode(String username, String code, String newPassword) async {
    final u = await lib.db.q1(
        "SELECT * FROM users WHERE username = ? COLLATE NOCASE AND role_id IN ('host','staff') AND deleted_at IS NULL",
        [username.trim()]);
    const err = 'Usuário ou código de recuperação inválido.';
    if (u == null) throw AppException(err);
    final codes = await lib.db.q(
        'SELECT * FROM recovery_codes WHERE user_id = ? AND used_at IS NULL', [u['id']]);
    String? matchedId;
    final norm = normalizeRecoveryCode(code);
    for (final c in codes) {
      if (await PasswordHasher.verify(norm, c['code_hash'] as String)) {
        matchedId = c['id'] as String;
        break;
      }
    }
    if (matchedId == null) {
      await lib.audit.log(null, 'auth.login_failed', 'users', u['id'] as String,
          actorId: u['id'] as String, actorName: u['name'] as String, details: 'código de recuperação inválido');
      throw AppException(err);
    }
    validatePassword(newPassword, Role.fromId(u['role_id'] as String));
    final hash = await PasswordHasher.hash(newPassword);
    final newCode = generateRecoveryCode();
    final newCodeHash = await PasswordHasher.hash(normalizeRecoveryCode(newCode));
    final now = AppClock.nowMs();
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE recovery_codes SET used_at = ? WHERE user_id = ? AND used_at IS NULL',
          [now, u['id']]);
      await lib.db.insertMap('recovery_codes',
          {'id': newId(), 'user_id': u['id'], 'code_hash': newCodeHash, 'created_at': now});
      await lib.db.x(
          'UPDATE users SET password_hash = ?, failed_attempts = 0, locked_until = NULL, must_change_password = 0, updated_at = ? WHERE id = ?',
          [hash, now, u['id']]);
      await lib.audit.log(null, 'auth.recovery_reset', 'users', u['id'] as String,
          actorId: u['id'] as String, actorName: u['name'] as String);
    });
    return newCode;
  }

  /// Autocadastro de leitor, conforme o modo definido pelo HOST.
  /// Retorna true se a conta ja esta ativa, false se aguarda aprovacao.
  Future<bool> signup(SignupData d) async {
    final settings = await lib.settings.load();
    final mode = settings.signupMode;
    if (mode == 'disabled') {
      throw AppException('O cadastro é feito apenas pela biblioteca. Procure o atendimento.');
    }
    if (!d.consent) throw ValidationException('É preciso aceitar o termo de uso e privacidade.');
    if (d.isMinor && (!d.guardianConsent || (d.guardianName ?? '').trim().isEmpty)) {
      throw ValidationException('Menores de idade precisam do nome e do consentimento do responsável.');
    }
    final status = mode == 'open' ? 'active' : 'pending';
    final id = await lib.users.insertUser(
      role: Role.user,
      name: d.name,
      username: d.username,
      password: d.password,
      status: status,
      enrollment: d.enrollment,
      className: d.className,
      isMinor: d.isMinor,
      guardianName: d.guardianName,
      guardianPhone: d.guardianPhone,
      consent: true,
      guardianConsent: d.guardianConsent,
      createdBy: null,
    );
    await lib.audit.log(null, 'auth.signup', 'users', id, actorId: id, actorName: d.name.trim(),
        details: status == 'pending' ? 'aguardando aprovação' : 'ativo');
    return status == 'active';
  }
}
