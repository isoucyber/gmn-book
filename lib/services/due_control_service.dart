import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';
import 'circulation_service.dart';
import 'settings_service.dart';

/// "CONTROLE DE DEVOLUCOES": proximos do vencimento, atrasados e devolvidos,
/// alem das notificacoes internas geradas a partir dos dias de alerta.
/// Tudo e calculado localmente, sem internet.
class DueControlService {
  final Library lib;
  DueControlService(this.lib);

  Future<List<Map<String, Object?>>> _withState(Session s) async {
    final settings = await lib.settings.load();
    final today = AppClock.today();
    final loans = await lib.circulation.activeLoans(s);
    for (final l in loans) {
      l['days_left'] = daysLeftOf(l, today);
      l['state'] = loanStateOf(l, today: today, nearDueDays: settings.nearDueDays).name;
    }
    return loans;
  }

  /// Emprestimos que vencem em ate [withinDays] dias (inclui "vence hoje").
  Future<List<Map<String, Object?>>> upcoming(Session s, {int? withinDays}) async {
    s.require(Permission.dueControlView);
    final settings = await lib.settings.load();
    final limit = withinDays ?? _maxAlertBefore(settings);
    final rows = (await _withState(s))
        .where((l) => (l['days_left'] as int) >= 0 && (l['days_left'] as int) <= limit)
        .toList()
      ..sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
    return _maskContacts(rows);
  }

  int _maxAlertBefore(LibrarySettings settings) {
    final before = settings.alertDays.where((d) => d >= 0);
    final m = before.isEmpty ? 0 : before.reduce((a, b) => a > b ? a : b);
    return m > settings.nearDueDays ? m : settings.nearDueDays;
  }

  Future<List<Map<String, Object?>>> overdue(Session s) async {
    s.require(Permission.dueControlView);
    final rows = (await _withState(s)).where((l) => (l['days_left'] as int) < 0).toList()
      ..sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
    return _maskContacts(rows);
  }

  /// Contato so aparece quando autorizado no cadastro.
  List<Map<String, Object?>> _maskContacts(List<Map<String, Object?>> rows) {
    for (final r in rows) {
      if (!toBool(r['contact_authorized'])) {
        r['phone'] = null;
        r['email'] = null;
        r['guardian_phone'] = null;
      }
    }
    return rows;
  }

  /// Gera notificacoes internas conforme os dias de alerta configurados.
  /// Idempotente (dedupe_key), pode ser chamado periodicamente.
  Future<int> generateNotifications() async {
    final settings = await lib.settings.load();
    final alertDays = settings.alertDays;
    if (alertDays.isEmpty) return 0;
    final today = AppClock.today();
    final loans = await lib.db.q(
        "SELECT l.id, l.user_id, l.due_date, b.title, u.name AS user_name FROM loans l "
        "JOIN books b ON b.id = l.book_id JOIN users u ON u.id = l.user_id WHERE l.status = 'active'");
    final afterDue = alertDays.where((d) => d < 0).toList();
    var created = 0;
    final now = AppClock.nowMs();
    for (final l in loans) {
      final left = daysBetween(today, parseIsoDate(l['due_date'] as String));
      String? key;
      if (alertDays.contains(left)) {
        key = '${l['id']}:${l['due_date']}:$left';
      } else if (left < 0 && afterDue.isNotEmpty) {
        // Apos o vencimento: um alerta por dia de atraso a partir do primeiro configurado.
        final first = afterDue.reduce((a, b) => a > b ? a : b);
        if (left <= first) key = '${l['id']}:${l['due_date']}:overdue:${isoDate(today)}';
      }
      if (key == null) continue;
      final title = left < 0 ? 'Empréstimo em atraso' : (left == 0 ? 'Devolução hoje' : 'Devolução próxima');
      final body = '${l['user_name']} — ${l['title']} — ${daysLeftLabel(left)} (${brDateIso(l['due_date'] as String)})';
      created += await lib.db.upd(
          'INSERT OR IGNORE INTO notifications (id, user_id, audience, kind, title, body, ref_id, dedupe_key, created_at) '
          "VALUES (?, NULL, 'staff', 'due', ?, ?, ?, ?, ?)",
          [newId(), title, body, l['id'], 'staff:$key', now]);
      final userBody = '"${l['title']}" — ${daysLeftLabel(left)} (devolução: ${brDateIso(l['due_date'] as String)})';
      created += await lib.db.upd(
          'INSERT OR IGNORE INTO notifications (id, user_id, audience, kind, title, body, ref_id, dedupe_key, created_at) '
          "VALUES (?, ?, 'user', 'due', ?, ?, ?, ?, ?)",
          [newId(), l['user_id'], title, userBody, l['id'], 'user:$key', now]);
    }
    return created;
  }

  Future<List<Map<String, Object?>>> notifications(Session s, {bool unreadOnly = false, int limit = 100}) {
    final staff = s.can(Permission.dueControlView);
    final where = staff
        ? "(audience = 'staff' OR (audience = 'user' AND user_id = ?))"
        : "(audience = 'user' AND user_id = ?)";
    return lib.db.q(
        'SELECT * FROM notifications WHERE $where ${unreadOnly ? 'AND read_at IS NULL' : ''} '
        'ORDER BY created_at DESC LIMIT ?',
        [s.userId, limit]);
  }

  Future<int> unreadCount(Session s) async {
    final staff = s.can(Permission.dueControlView);
    final where = staff
        ? "(audience = 'staff' OR (audience = 'user' AND user_id = ?))"
        : "(audience = 'user' AND user_id = ?)";
    return lib.db.count('SELECT count(*) FROM notifications WHERE $where AND read_at IS NULL', [s.userId]);
  }

  Future<void> markAllRead(Session s) async {
    final staff = s.can(Permission.dueControlView);
    final where = staff
        ? "(audience = 'staff' OR (audience = 'user' AND user_id = ?))"
        : "(audience = 'user' AND user_id = ?)";
    await lib.db.x('UPDATE notifications SET read_at = ? WHERE $where AND read_at IS NULL',
        [AppClock.nowMs(), s.userId]);
  }

  /// Texto de cobranca pronto para WhatsApp, e-mail ou SMS (modelo editavel).
  Future<String> reminderMessage(Map<String, Object?> loan) async {
    final settings = await lib.settings.load();
    final left = daysLeftOf(loan, AppClock.today());
    final situacao = left < 0
        ? 'está em atraso há ${-left} dia(s)'
        : (left == 0 ? 'vence hoje' : 'vence em $left dia(s)');
    final firstName = (loan['user_name'] as String? ?? '').split(' ').first;
    return settings
        .str(SettingKeys.messageTemplate)
        .replaceAll('{nome}', firstName)
        .replaceAll('{livro}', loan['title'] as String? ?? '')
        .replaceAll('{escola}', settings.schoolName)
        .replaceAll('{situacao}', situacao)
        .replaceAll('{data}', brDateIso(loan['due_date'] as String?));
  }
}
