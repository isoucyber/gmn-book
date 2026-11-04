import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';

class DashboardStats {
  final int titles;
  final int copies;
  final int available;
  final int loaned;
  final int users;
  final int pendingUsers;
  final int activeLoans;
  final int nearDue;
  final int overdue;
  final int activeReservations;
  final int returnsLast7;
  final int? lastBackupAt;
  final int backupReminderDays;
  final List<({String label, int value})> loansPerMonth;
  final List<({String label, int value})> topCategories;
  final List<Map<String, Object?>> recentActivity;

  DashboardStats({
    required this.titles,
    required this.copies,
    required this.available,
    required this.loaned,
    required this.users,
    required this.pendingUsers,
    required this.activeLoans,
    required this.nearDue,
    required this.overdue,
    required this.activeReservations,
    required this.returnsLast7,
    required this.lastBackupAt,
    required this.backupReminderDays,
    required this.loansPerMonth,
    required this.topCategories,
    required this.recentActivity,
  });

  bool get backupOverdue {
    if (lastBackupAt == null) return true;
    final days = AppClock.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastBackupAt!))
        .inDays;
    return days >= backupReminderDays;
  }
}

class DashboardService {
  final Library lib;
  DashboardService(this.lib);

  static const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

  Future<DashboardStats> load(Session s) async {
    s.require(Permission.dashboardView);
    final db = lib.db;
    final settings = await lib.settings.load();
    final today = AppClock.today();
    final todayIso = isoDate(today);
    final nearLimit = isoDate(addDays(today, settings.nearDueDays));

    // Ultimos 6 meses de emprestimos (grafico).
    final months = <({String label, int value})>[];
    for (var i = 5; i >= 0; i--) {
      final first = DateTime(today.year, today.month - i, 1);
      final next = DateTime(first.year, first.month + 1, 1);
      final n = await db.count(
          "SELECT count(*) FROM loans WHERE status <> 'cancelled' AND loan_date >= ? AND loan_date < ?",
          [isoDate(first), isoDate(next)]);
      months.add((label: _months[first.month - 1], value: n));
    }

    final cats = await db.q(
        "SELECT coalesce(c.name, 'Sem categoria') AS name, count(*) AS n FROM loans l "
        'JOIN books b ON b.id = l.book_id LEFT JOIN categories c ON c.id = b.category_id '
        "WHERE l.status <> 'cancelled' GROUP BY c.id ORDER BY n DESC LIMIT 5");

    final lastBackup = await db.q1("SELECT max(at) AS at FROM backup_history WHERE kind = 'manual'");

    return DashboardStats(
      titles: await db.count("SELECT count(*) FROM books WHERE status = 'active' AND deleted_at IS NULL"),
      copies: await db.count(
          "SELECT count(*) FROM book_copies bc JOIN books b ON b.id = bc.book_id WHERE bc.deleted_at IS NULL AND bc.status <> 'withdrawn' AND b.status = 'active'"),
      available: await db.count(
          "SELECT count(*) FROM book_copies bc JOIN books b ON b.id = bc.book_id WHERE bc.status = 'available' AND bc.deleted_at IS NULL AND b.status = 'active'"),
      loaned: await db.count("SELECT count(*) FROM book_copies WHERE status = 'loaned'"),
      users: await db.count("SELECT count(*) FROM users WHERE role_id = 'user' AND status = 'active'"),
      pendingUsers: await db.count("SELECT count(*) FROM users WHERE status = 'pending'"),
      activeLoans: await db.count("SELECT count(*) FROM loans WHERE status = 'active'"),
      nearDue: await db.count(
          "SELECT count(*) FROM loans WHERE status = 'active' AND due_date >= ? AND due_date <= ?",
          [todayIso, nearLimit]),
      overdue: await db.count("SELECT count(*) FROM loans WHERE status = 'active' AND due_date < ?", [todayIso]),
      activeReservations:
          await db.count("SELECT count(*) FROM reservations WHERE status IN ('waiting','ready')"),
      returnsLast7: await db.count(
          "SELECT count(*) FROM loans WHERE status = 'returned' AND return_date >= ?",
          [isoDate(addDays(today, -7))]),
      lastBackupAt: toInt(lastBackup?['at']),
      backupReminderDays: settings.backupReminderDays,
      loansPerMonth: months,
      topCategories: [for (final c in cats) (label: c['name'] as String, value: toInt(c['n']) ?? 0)],
      recentActivity: await db.q(
          "SELECT * FROM audit_logs WHERE action IN ('loan.create','loan.return','loan.renew','book.create','user.create','copy.create','backup.create','backup.restore') "
          'ORDER BY at DESC LIMIT 12'),
    );
  }
}
