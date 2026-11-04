import '../core/errors.dart';
import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';

/// Chaves e valores padrao das regras da biblioteca.
class SettingKeys {
  static const schoolName = 'school_name';
  static const schoolAddress = 'school_address';
  static const schoolYear = 'school_year';
  static const defaultLoanDays = 'default_loan_days';
  static const maxLoansUser = 'max_loans_user';
  static const maxLoansStaff = 'max_loans_staff';
  static const nearDueDays = 'near_due_days';
  static const alertDays = 'alert_days';
  static const signupMode = 'signup_mode';
  static const lockoutAttempts = 'lockout_attempts';
  static const lockoutMinutes = 'lockout_minutes';
  static const sessionTimeoutMinutes = 'session_timeout_minutes';
  static const closedWeekdays = 'closed_weekdays';
  static const backupReminderDays = 'backup_reminder_days';
  static const blockOnOverdue = 'block_on_overdue';
  static const userCanRenew = 'user_can_renew';
  static const messageTemplate = 'message_template';
}

const Map<String, String> settingDefaults = {
  SettingKeys.schoolName: 'Minha Escola',
  SettingKeys.schoolAddress: '',
  SettingKeys.schoolYear: '',
  SettingKeys.defaultLoanDays: '14',
  SettingKeys.maxLoansUser: '2',
  SettingKeys.maxLoansStaff: '5',
  SettingKeys.nearDueDays: '3',
  SettingKeys.alertDays: '7,3,1,0,-1',
  SettingKeys.signupMode: 'approval',
  SettingKeys.lockoutAttempts: '5',
  SettingKeys.lockoutMinutes: '15',
  SettingKeys.sessionTimeoutMinutes: '10',
  SettingKeys.closedWeekdays: '6,7',
  SettingKeys.backupReminderDays: '7',
  SettingKeys.blockOnOverdue: '1',
  SettingKeys.userCanRenew: '0',
  SettingKeys.messageTemplate:
      'Olá, {nome}! O livro "{livro}" emprestado pela biblioteca {escola} {situacao} (devolução: {data}).',
};

class LibrarySettings {
  final Map<String, String> values;
  LibrarySettings(this.values);

  String str(String k) => values[k] ?? settingDefaults[k] ?? '';
  int integer(String k) => int.tryParse(str(k)) ?? int.parse(settingDefaults[k] ?? '0');
  bool flag(String k) => str(k) == '1';

  String get schoolName => str(SettingKeys.schoolName);
  int get defaultLoanDays => integer(SettingKeys.defaultLoanDays);
  int get nearDueDays => integer(SettingKeys.nearDueDays);
  int get lockoutAttempts => integer(SettingKeys.lockoutAttempts);
  int get lockoutMinutes => integer(SettingKeys.lockoutMinutes);
  int get sessionTimeoutMinutes => integer(SettingKeys.sessionTimeoutMinutes);
  int get backupReminderDays => integer(SettingKeys.backupReminderDays);
  bool get blockOnOverdue => flag(SettingKeys.blockOnOverdue);
  bool get userCanRenew => flag(SettingKeys.userCanRenew);
  String get signupMode => str(SettingKeys.signupMode);

  int maxLoansFor(Role r) =>
      r == Role.user ? integer(SettingKeys.maxLoansUser) : integer(SettingKeys.maxLoansStaff);

  /// Dias de alerta (positivos = antes do vencimento, 0 = no dia, negativos = depois).
  List<int> get alertDays => str(SettingKeys.alertDays)
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));

  /// Dias da semana fechados (1 = segunda ... 7 = domingo).
  Set<int> get closedWeekdays => str(SettingKeys.closedWeekdays)
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .where((d) => d >= 1 && d <= 7)
      .toSet();
}

class SettingsService {
  final Library lib;
  SettingsService(this.lib);

  Future<LibrarySettings> load() async {
    final rows = await lib.db.q('SELECT key, value FROM library_settings');
    return LibrarySettings({for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''});
  }

  /// Escrita interna (sem verificacao; usada pelo assistente de configuracao).
  Future<void> writeRaw(Map<String, String> values) async {
    final now = AppClock.nowMs();
    for (final e in values.entries) {
      await lib.db.x(
          'INSERT INTO library_settings (key, value, updated_at) VALUES (?, ?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
          [e.key, e.value, now]);
    }
  }

  Future<void> save(Session s, Map<String, String> values) async {
    s.require(Permission.settingsManage);
    _validate(values);
    await lib.db.transaction(() async {
      final old = await load();
      final changed = <String, String>{};
      final before = <String, String>{};
      for (final e in values.entries) {
        if (old.str(e.key) != e.value) {
          changed[e.key] = e.value;
          before[e.key] = old.str(e.key);
        }
      }
      if (changed.isEmpty) return;
      await writeRaw(changed);
      await lib.audit.log(s, 'settings.update', 'library_settings', null,
          oldValue: before, newValue: changed);
    });
  }

  void _validate(Map<String, String> v) {
    int? n(String k) => v.containsKey(k) ? int.tryParse(v[k]!) : null;
    void range(String k, int lo, int hi, String label) {
      if (!v.containsKey(k)) return;
      final x = n(k);
      if (x == null || x < lo || x > hi) {
        throw ValidationException('$label deve estar entre $lo e $hi.');
      }
    }

    range(SettingKeys.defaultLoanDays, 1, 365, 'Prazo padrão');
    range(SettingKeys.maxLoansUser, 1, 50, 'Limite de livros por leitor');
    range(SettingKeys.maxLoansStaff, 1, 100, 'Limite de livros por funcionário');
    range(SettingKeys.nearDueDays, 0, 30, 'Dias para "próximo do vencimento"');
    range(SettingKeys.lockoutAttempts, 3, 20, 'Tentativas de login');
    range(SettingKeys.lockoutMinutes, 1, 1440, 'Tempo de bloqueio');
    range(SettingKeys.sessionTimeoutMinutes, 1, 240, 'Tempo de inatividade');
    range(SettingKeys.backupReminderDays, 1, 365, 'Lembrete de backup');
    if (v.containsKey(SettingKeys.signupMode) &&
        !['open', 'approval', 'disabled'].contains(v[SettingKeys.signupMode])) {
      throw ValidationException('Modo de cadastro inválido.');
    }
    if (v.containsKey(SettingKeys.alertDays)) {
      final parts = v[SettingKeys.alertDays]!.split(',').where((e) => e.trim().isNotEmpty);
      for (final p in parts) {
        final d = int.tryParse(p.trim());
        if (d == null || d < -60 || d > 60) {
          throw ValidationException('Dias de alerta devem ser números entre -60 e 60.');
        }
      }
    }
    if (v.containsKey(SettingKeys.closedWeekdays)) {
      final days = v[SettingKeys.closedWeekdays]!
          .split(',')
          .where((e) => e.trim().isNotEmpty)
          .map((e) => int.tryParse(e.trim()));
      if (days.any((d) => d == null || d < 1 || d > 7)) {
        throw ValidationException('Dias fechados inválidos.');
      }
      if (days.toSet().length >= 7) {
        throw ValidationException('A biblioteca precisa abrir pelo menos um dia da semana.');
      }
    }
  }

  // --- Calendario (feriados, recessos, ferias) -------------------------------

  Future<List<Map<String, Object?>>> holidays() =>
      lib.db.q('SELECT * FROM holidays ORDER BY date');

  Future<Set<String>> holidayDates() async =>
      (await lib.db.q('SELECT date FROM holidays')).map((r) => r['date'] as String).toSet();

  /// Adiciona um dia fechado ou um intervalo (recesso/ferias).
  Future<int> addClosedDays(Session s, DateTime from, DateTime to, String description) async {
    s.require(Permission.settingsManage);
    if (description.trim().isEmpty) throw ValidationException('Informe a descrição.');
    final start = dateOnly(from), end = dateOnly(to);
    if (end.isBefore(start)) throw ValidationException('A data final é anterior à inicial.');
    if (daysBetween(start, end) > 120) throw ValidationException('Intervalo máximo de 120 dias.');
    var added = 0;
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
        final n = await lib.db.upd(
            'INSERT OR IGNORE INTO holidays (id, date, description, created_at, updated_at) VALUES (?,?,?,?,?)',
            [newId(), isoDate(d), description.trim(), now, now]);
        added += n;
      }
      await lib.audit.log(s, 'calendar.add', 'holidays', null,
          details: '${isoDate(start)} a ${isoDate(end)}: $description');
    });
    return added;
  }

  Future<void> removeClosedDay(Session s, String id) async {
    s.require(Permission.settingsManage);
    final row = await lib.db.q1('SELECT * FROM holidays WHERE id = ?', [id]);
    if (row == null) return;
    await lib.db.transaction(() async {
      await lib.db.x('DELETE FROM holidays WHERE id = ?', [id]);
      await lib.audit.log(s, 'calendar.remove', 'holidays', id, oldValue: row);
    });
  }
}
