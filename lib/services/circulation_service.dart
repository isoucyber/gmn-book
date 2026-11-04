import '../core/errors.dart';
import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';
import 'settings_service.dart';

/// Situacao de um emprestimo, sempre CALCULADA a partir das datas.
enum LoanState {
  active('Ativo'),
  nearDue('Próximo do vencimento'),
  overdue('Atrasado'),
  returned('Devolvido'),
  cancelled('Cancelado');

  final String label;
  const LoanState(this.label);
}

LoanState loanStateOf(Map<String, Object?> loan, {required DateTime today, required int nearDueDays}) {
  final status = loan['status'] as String;
  if (status == 'returned') return LoanState.returned;
  if (status == 'cancelled') return LoanState.cancelled;
  final left = daysBetween(today, parseIsoDate(loan['due_date'] as String));
  if (left < 0) return LoanState.overdue;
  if (left <= nearDueDays) return LoanState.nearDue;
  return LoanState.active;
}

int daysLeftOf(Map<String, Object?> loan, DateTime today) =>
    daysBetween(today, parseIsoDate(loan['due_date'] as String));

/// Bloqueio que impede um emprestimo, com motivo legivel.
class LoanBlock {
  final String code;
  final String message;
  LoanBlock(this.code, this.message);
}

class LoanBlockedException extends AppException {
  final List<LoanBlock> blocks;
  LoanBlockedException(this.blocks)
      : super(blocks.map((b) => b.message).join('\n'), code: 'blocked');
}

class _LastOp {
  final String kind; // 'checkout' | 'return'
  final String loanId;
  final String userId;
  final int at;
  final Map<String, Object?> copyBefore;
  _LastOp(this.kind, this.loanId, this.userId, this.at, this.copyBefore);
}

class CirculationService {
  final Library lib;
  CirculationService(this.lib);

  static const undoWindowSeconds = 30;
  _LastOp? _last;

  static const _loanSelect = '''
SELECT l.*, b.title, b.isbn, b.cover_file, bc.accession_number, bc.barcode,
       u.name AS user_name, u.card_code, u.class_name, u.enrollment, u.phone, u.email,
       u.guardian_name, u.guardian_phone, u.contact_authorized,
       cb.name AS created_by_name, rb.name AS returned_by_name
FROM loans l
JOIN books b ON b.id = l.book_id
JOIN book_copies bc ON bc.id = l.copy_id
JOIN users u ON u.id = l.user_id
LEFT JOIN users cb ON cb.id = l.created_by
LEFT JOIN users rb ON rb.id = l.returned_by
''';

  // ---------------------------------------------------------------------------
  // Calculo de prazos

  /// Data prevista = data do emprestimo + prazo. Se cair em dia fechado
  /// (fim de semana configurado, feriado, recesso), passa ao proximo dia util.
  DateTime computeDueDate(DateTime loanDate, int days, LibrarySettings settings, Set<String> holidays) {
    var due = addDays(dateOnly(loanDate), days);
    final closed = settings.closedWeekdays;
    var guard = 0;
    while ((closed.contains(due.weekday) || holidays.contains(isoDate(due))) && guard < 400) {
      due = addDays(due, 1);
      guard++;
    }
    return due;
  }

  int loanDaysFor(Map<String, Object?> book, LibrarySettings settings) =>
      toInt(book['loan_days']) ?? settings.defaultLoanDays;

  Future<DateTime> previewDueDate(String bookId, {DateTime? loanDate, int? days}) async {
    final settings = await lib.settings.load();
    final book = await lib.db.q1('SELECT loan_days FROM books WHERE id = ?', [bookId]);
    final d = days ?? loanDaysFor(book ?? const {}, settings);
    return computeDueDate(loanDate ?? AppClock.today(), d, settings, await lib.settings.holidayDates());
  }

  // ---------------------------------------------------------------------------
  // Bloqueios

  Future<List<LoanBlock>> blocksFor(String userId, {Map<String, Object?>? copy}) async {
    final settings = await lib.settings.load();
    final blocks = <LoanBlock>[];
    final u = await lib.db.q1('SELECT * FROM users WHERE id = ?', [userId]);
    if (u == null) return [LoanBlock('user', 'Usuário não encontrado.')];
    if (u['status'] != 'active') {
      blocks.add(LoanBlock('inactive', 'O usuário não está ativo.'));
    }
    final today = isoDate(AppClock.today());
    final overdue = await lib.db.count(
        "SELECT count(*) FROM loans WHERE user_id = ? AND status = 'active' AND due_date < ?",
        [userId, today]);
    if (overdue > 0 && settings.blockOnOverdue) {
      blocks.add(LoanBlock('overdue', 'O usuário tem $overdue empréstimo(s) em atraso.'));
    }
    final pend = await lib.db.count(
        "SELECT count(*) FROM loans l JOIN book_copies bc ON bc.id = l.copy_id "
        "WHERE l.user_id = ? AND l.status = 'returned' AND bc.status IN ('lost','damaged') "
        "AND l.condition_in IN ('danificado','extraviado') "
        "AND l.returned_at = (SELECT max(l2.returned_at) FROM loans l2 WHERE l2.copy_id = l.copy_id)",
        [userId]);
    if (pend > 0) {
      blocks.add(LoanBlock('pending', 'O usuário tem $pend pendência(s) de perda ou dano.'));
    }
    final active = await lib.db.count(
        "SELECT count(*) FROM loans WHERE user_id = ? AND status = 'active'", [userId]);
    final max = settings.maxLoansFor(Role.fromId(u['role_id'] as String));
    if (active >= max) {
      blocks.add(LoanBlock('limit', 'Limite de $max livro(s) simultâneo(s) atingido.'));
    }
    if (copy != null) {
      if (toBool(copy['restricted'])) {
        final note = copy['restriction_note'] as String?;
        blocks.add(LoanBlock('restricted',
            'Título com restrição de empréstimo${note == null ? '' : ': $note'}.'));
      }
    }
    return blocks;
  }

  // ---------------------------------------------------------------------------
  // Emprestimo

  Future<Map<String, Object?>> checkout(
    Session s, {
    required String userId,
    required String copyId,
    DateTime? loanDate,
    int? days,
    DateTime? dueDate,
    String? notes,
    String? overrideReason,
  }) async {
    s.require(Permission.circulationOperate);
    final settings = await lib.settings.load();
    final copy = await lib.db.q1(
        'SELECT bc.*, b.title, b.loan_days, b.restricted, b.restriction_note, b.status AS book_status '
        'FROM book_copies bc JOIN books b ON b.id = bc.book_id WHERE bc.id = ?',
        [copyId]);
    if (copy == null) throw AppException('Exemplar não encontrado.');
    if (copy['book_status'] != 'active') throw AppException('Este título está arquivado.');
    final st = copy['status'] as String;
    if (st != 'available') {
      final msg = switch (st) {
        'loaned' => 'Este exemplar já está emprestado.',
        'reference' => 'Exemplar de uso local: só pode ser consultado na biblioteca.',
        'reserved' => 'Exemplar separado para uma reserva.',
        _ => 'Exemplar indisponível para empréstimo.',
      };
      throw AppException(msg, code: 'unavailable');
    }
    final blocks = await blocksFor(userId, copy: copy);
    final hard = blocks.where((b) => b.code == 'inactive' || b.code == 'user').toList();
    if (hard.isNotEmpty) throw LoanBlockedException(hard);
    final reason = overrideReason?.trim();
    if (blocks.isNotEmpty) {
      if (reason == null || reason.isEmpty) throw LoanBlockedException(blocks);
      if (!s.can(Permission.circulationOverride)) {
        throw PermissionDenied('liberar bloqueios (apenas administradores)');
      }
    }

    final today = AppClock.today();
    final start = dateOnly(loanDate ?? today);
    if (start.isAfter(today)) throw ValidationException('A data do empréstimo não pode estar no futuro.');
    if (daysBetween(start, today) > 365) throw ValidationException('Data de empréstimo muito antiga.');
    late DateTime due;
    if (dueDate != null) {
      due = dateOnly(dueDate);
      if (due.isBefore(start)) throw ValidationException('A devolução não pode ser antes da retirada.');
    } else {
      final d = days ?? loanDaysFor(copy, settings);
      if (d < 1 || d > 365) throw ValidationException('Prazo deve estar entre 1 e 365 dias.');
      due = computeDueDate(start, d, settings, await lib.settings.holidayDates());
    }

    final loanId = newId();
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      // Atualizacao condicional: se outro operador emprestou o exemplar no
      // mesmo instante, nenhuma linha e afetada e a operacao e abortada.
      final n = await lib.db.upd(
          "UPDATE book_copies SET status = 'loaned', updated_at = ? WHERE id = ? AND status = 'available'",
          [now, copyId]);
      if (n != 1) throw AppException('Este exemplar acabou de ser emprestado.');
      await lib.db.insertMap('loans', {
        'id': loanId,
        'user_id': userId,
        'book_id': copy['book_id'],
        'copy_id': copyId,
        'loan_date': isoDate(start),
        'due_date': isoDate(due),
        'status': 'active',
        'renewals': 0,
        'condition_out': copy['condition'],
        'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
        'override_reason': blocks.isEmpty ? null : reason,
        'created_by': s.userId,
        'created_at': now,
        'updated_at': now,
      });
      await lib.db.insertMap('copy_status_history', {
        'id': newId(),
        'copy_id': copyId,
        'old_status': 'available',
        'new_status': 'loaned',
        'reason': 'empréstimo',
        'by_user': s.userId,
        'at': now,
      });
      await lib.audit.log(s, 'loan.create', 'loans', loanId,
          newValue: {
            'user_id': userId,
            'copy': copy['accession_number'],
            'title': copy['title'],
            'due_date': isoDate(due),
          },
          details: blocks.isEmpty
              ? null
              : 'Bloqueio liberado: ${blocks.map((b) => b.code).join(', ')} — $reason');
    });
    _last = _LastOp('checkout', loanId, s.userId, AppClock.nowMs(), {'status': 'available'});
    return (await lib.db.q1('$_loanSelect WHERE l.id = ?', [loanId]))!;
  }

  // ---------------------------------------------------------------------------
  // Devolucao

  Future<Map<String, Object?>> returnCopy(
    Session s,
    String copyCode, {
    String condition = 'bom',
    bool lost = false,
    String? notes,
  }) async {
    s.require(Permission.circulationOperate);
    if (!['bom', 'regular', 'danificado'].contains(condition)) {
      throw ValidationException('Estado de conservação inválido.');
    }
    final copy = await lib.catalog.findCopyByCode(s, copyCode);
    if (copy == null) throw AppException('Exemplar "$copyCode" não encontrado.');
    final loan = await lib.db.q1(
        "SELECT * FROM loans WHERE copy_id = ? AND status = 'active'", [copy['id']]);
    if (loan == null) throw AppException('O exemplar ${copy['accession_number']} não está emprestado.');
    final today = AppClock.today();
    final newCopyStatus = lost ? 'lost' : (condition == 'danificado' ? 'damaged' : 'available');
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      await lib.db.x(
          "UPDATE loans SET status = 'returned', return_date = ?, returned_at = ?, returned_by = ?, "
          'condition_in = ?, notes = coalesce(?, notes), updated_at = ? WHERE id = ?',
          [isoDate(today), now, s.userId, lost ? 'extraviado' : condition,
            notes?.trim().isEmpty ?? true ? null : notes!.trim(), now, loan['id']]);
      await lib.db.x(
          'UPDATE book_copies SET status = ?, condition = ?, updated_at = ? WHERE id = ?',
          [newCopyStatus, lost ? copy['condition'] : condition, now, copy['id']]);
      await lib.db.insertMap('copy_status_history', {
        'id': newId(),
        'copy_id': copy['id'],
        'old_status': 'loaned',
        'new_status': newCopyStatus,
        'reason': lost ? 'extravio informado na devolução' : 'devolução',
        'by_user': s.userId,
        'at': now,
      });
      final daysLate = -daysBetween(today, parseIsoDate(loan['due_date'] as String));
      await lib.audit.log(s, 'loan.return', 'loans', loan['id'] as String,
          newValue: {
            'copy': copy['accession_number'],
            'title': copy['title'],
            'condition': lost ? 'extraviado' : condition,
            'days_late': daysLate > 0 ? daysLate : 0,
          });
    });
    _last = _LastOp('return', loan['id'] as String, s.userId, AppClock.nowMs(),
        {'status': copy['status'], 'condition': copy['condition']});
    return (await lib.db.q1('$_loanSelect WHERE l.id = ?', [loan['id']]))!;
  }

  // ---------------------------------------------------------------------------
  // Desfazer a ultima operacao (janela curta, registrado em auditoria)

  bool canUndo(Session s) =>
      _last != null &&
      _last!.userId == s.userId &&
      AppClock.nowMs() - _last!.at <= undoWindowSeconds * 1000;

  String? get lastOpKind => _last?.kind;

  Future<void> undoLast(Session s) async {
    s.require(Permission.circulationOperate);
    final op = _last;
    if (op == null || !canUndo(s)) throw AppException('Não há operação recente para desfazer.');
    final loan = await lib.db.q1('SELECT * FROM loans WHERE id = ?', [op.loanId]);
    if (loan == null) throw AppException('Empréstimo não encontrado.');
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      if (op.kind == 'checkout') {
        if (loan['status'] != 'active') throw AppException('O empréstimo já foi alterado.');
        await lib.db.x(
            "UPDATE loans SET status = 'cancelled', notes = coalesce(notes || ' | ', '') || 'Desfeito no balcão', updated_at = ? WHERE id = ?",
            [now, op.loanId]);
        await lib.db.x(
            "UPDATE book_copies SET status = 'available', updated_at = ? WHERE id = ? AND status = 'loaned'",
            [now, loan['copy_id']]);
        await lib.audit.log(s, 'loan.cancel', 'loans', op.loanId, details: 'desfeito no balcão');
      } else {
        if (loan['status'] != 'returned') throw AppException('A devolução já foi alterada.');
        final busy = await lib.db.q1(
            "SELECT 1 FROM loans WHERE copy_id = ? AND status = 'active'", [loan['copy_id']]);
        if (busy != null) throw AppException('O exemplar já foi emprestado novamente.');
        await lib.db.x(
            "UPDATE loans SET status = 'active', return_date = NULL, returned_at = NULL, returned_by = NULL, condition_in = NULL, updated_at = ? WHERE id = ?",
            [now, op.loanId]);
        await lib.db.x("UPDATE book_copies SET status = 'loaned', condition = ?, updated_at = ? WHERE id = ?",
            [op.copyBefore['condition'], now, loan['copy_id']]);
        await lib.audit.log(s, 'loan.undo_return', 'loans', op.loanId);
      }
      await lib.db.insertMap('copy_status_history', {
        'id': newId(),
        'copy_id': loan['copy_id'],
        'old_status': op.kind == 'checkout' ? 'loaned' : null,
        'new_status': op.kind == 'checkout' ? 'available' : 'loaned',
        'reason': 'operação desfeita',
        'by_user': s.userId,
        'at': now,
      });
    });
    _last = null;
  }

  // ---------------------------------------------------------------------------
  // Renovacao e alteracao manual de prazo

  Future<String?> renewBlockReason(Map<String, Object?> loan) async {
    if (loan['status'] != 'active') return 'O empréstimo não está ativo.';
    final book = await lib.db.q1('SELECT * FROM books WHERE id = ?', [loan['book_id']]);
    if (book == null) return 'Livro não encontrado.';
    if (!toBool(book['allow_renewal'])) return 'Este título não permite renovação.';
    final renewals = toInt(loan['renewals']) ?? 0;
    final max = toInt(book['max_renewals']) ?? 0;
    if (renewals >= max) return 'Limite de $max renovação(ões) atingido.';
    final today = AppClock.today();
    if (daysBetween(today, parseIsoDate(loan['due_date'] as String)) < 0) {
      return 'Empréstimo em atraso não pode ser renovado. Registre a devolução.';
    }
    final overdue = await lib.db.count(
        "SELECT count(*) FROM loans WHERE user_id = ? AND status = 'active' AND due_date < ?",
        [loan['user_id'], isoDate(today)]);
    if (overdue > 0) return 'O usuário tem empréstimos em atraso.';
    final waiting = await lib.db.count(
        "SELECT count(*) FROM reservations WHERE book_id = ? AND status IN ('waiting','ready')",
        [loan['book_id']]);
    if (waiting > 0) return 'Há reservas na fila para este título.';
    return null;
  }

  Future<Map<String, Object?>> renew(Session s, String loanId) async {
    final loan = await lib.db.q1('SELECT * FROM loans WHERE id = ?', [loanId]);
    if (loan == null) throw AppException('Empréstimo não encontrado.');
    final settings = await lib.settings.load();
    if (loan['user_id'] == s.userId && s.role == Role.user) {
      if (!settings.userCanRenew) throw PermissionDenied('renovar pelo portal (desativado pela biblioteca)');
    } else {
      s.require(Permission.circulationOperate);
    }
    final reason = await renewBlockReason(loan);
    if (reason != null) throw AppException(reason, code: 'renew_blocked');
    final book = await lib.db.q1('SELECT loan_days FROM books WHERE id = ?', [loan['book_id']]);
    final newDue = computeDueDate(
        AppClock.today(), loanDaysFor(book ?? const {}, settings), settings, await lib.settings.holidayDates());
    final oldDue = loan['due_date'] as String;
    if (!newDue.isAfter(parseIsoDate(oldDue))) {
      throw AppException('A renovação não estenderia o prazo atual (${brDateIso(oldDue)}).');
    }
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      await lib.db.x('UPDATE loans SET due_date = ?, renewals = renewals + 1, updated_at = ? WHERE id = ?',
          [isoDate(newDue), now, loanId]);
      await lib.db.insertMap('renewals', {
        'id': newId(),
        'loan_id': loanId,
        'old_due_date': oldDue,
        'new_due_date': isoDate(newDue),
        'by_user': s.userId,
        'at': now,
      });
      await lib.audit.log(s, 'loan.renew', 'loans', loanId,
          oldValue: {'due_date': oldDue}, newValue: {'due_date': isoDate(newDue)});
    });
    return (await lib.db.q1('$_loanSelect WHERE l.id = ?', [loanId]))!;
  }

  /// Alteracao manual do prazo de um emprestimo especifico (HOST).
  Future<void> changeDueDate(Session s, String loanId, DateTime newDue, String reason) async {
    s.require(Permission.circulationOverride);
    final loan = await lib.db.q1('SELECT * FROM loans WHERE id = ?', [loanId]);
    if (loan == null || loan['status'] != 'active') throw AppException('Empréstimo ativo não encontrado.');
    if (reason.trim().isEmpty) throw ValidationException('Informe o motivo da alteração.');
    final nd = dateOnly(newDue);
    if (nd.isBefore(parseIsoDate(loan['loan_date'] as String))) {
      throw ValidationException('A devolução não pode ser antes da retirada.');
    }
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE loans SET due_date = ?, updated_at = ? WHERE id = ?',
          [isoDate(nd), AppClock.nowMs(), loanId]);
      await lib.audit.log(s, 'loan.due_change', 'loans', loanId,
          oldValue: {'due_date': loan['due_date']}, newValue: {'due_date': isoDate(nd)}, details: reason.trim());
    });
  }

  // ---------------------------------------------------------------------------
  // Consultas

  Future<Map<String, Object?>?> getLoan(Session s, String loanId) async {
    final l = await lib.db.q1('$_loanSelect WHERE l.id = ?', [loanId]);
    if (l == null) return null;
    s.requireSelfOr(l['user_id'] as String, Permission.circulationOperate);
    return l;
  }

  /// Emprestimos de um usuario. Leitores so podem consultar os proprios.
  Future<List<Map<String, Object?>>> userLoans(Session s, String userId, {bool history = false}) async {
    if (userId == s.userId) {
      s.require(Permission.ownLoansView);
    } else {
      s.require(Permission.usersView);
    }
    final rows = await lib.db.q(
        '$_loanSelect WHERE l.user_id = ? AND ${history ? "l.status <> 'active'" : "l.status = 'active'"} '
        'ORDER BY ${history ? 'l.returned_at DESC, l.created_at DESC' : 'l.due_date'} LIMIT 500',
        [userId]);
    if (s.role == Role.user) {
      for (final r in rows) {
        r.remove('created_by_name');
        r.remove('returned_by_name');
        r.remove('override_reason');
      }
    }
    return rows;
  }

  /// Todos os emprestimos ativos (com filtro opcional por usuario/livro).
  Future<List<Map<String, Object?>>> activeLoans(Session s, {String? search}) async {
    s.require(Permission.dueControlView);
    final rows = await lib.db.q("$_loanSelect WHERE l.status = 'active' ORDER BY l.due_date, u.name");
    final q = search?.trim() ?? '';
    if (q.isEmpty) return rows;
    return rows
        .where((r) => fuzzyMatch(
            q,
            normalize('${r['user_name']} ${r['title']} ${r['card_code']} ${r['enrollment'] ?? ''} '
                '${r['class_name'] ?? ''} ${r['accession_number']} ${r['isbn'] ?? ''}')))
        .toList();
  }

  Future<List<Map<String, Object?>>> returnedLoans(Session s, {int limit = 200, String? search}) async {
    s.require(Permission.dueControlView);
    final rows = await lib.db.q(
        "$_loanSelect WHERE l.status = 'returned' ORDER BY l.returned_at DESC LIMIT ?", [limit]);
    final q = search?.trim() ?? '';
    if (q.isEmpty) return rows;
    return rows.where((r) => fuzzyMatch(q, normalize('${r['user_name']} ${r['title']}'))).toList();
  }

  /// "Usuarios com emprestimos ativos": agrupa os livros por pessoa.
  Future<List<Map<String, Object?>>> usersWithActiveLoans(Session s, {String? search}) async {
    final loans = await activeLoans(s, search: search);
    final settings = await lib.settings.load();
    final today = AppClock.today();
    final byUser = <String, Map<String, Object?>>{};
    for (final l in loans) {
      final uid = l['user_id'] as String;
      final entry = byUser.putIfAbsent(
          uid,
          () => {
                'user_id': uid,
                'user_name': l['user_name'],
                'card_code': l['card_code'],
                'class_name': l['class_name'],
                'loans': <Map<String, Object?>>[],
                'overdue': 0,
                'near_due': 0,
              });
      (entry['loans'] as List<Map<String, Object?>>).add(l);
      final st = loanStateOf(l, today: today, nearDueDays: settings.nearDueDays);
      if (st == LoanState.overdue) entry['overdue'] = (entry['overdue'] as int) + 1;
      if (st == LoanState.nearDue) entry['near_due'] = (entry['near_due'] as int) + 1;
    }
    final list = byUser.values.toList()
      ..sort((a, b) => (a['user_name'] as String).compareTo(b['user_name'] as String));
    return list;
  }

  Future<List<Map<String, Object?>>> loanHistoryForBook(Session s, String bookId, {int limit = 100}) async {
    s.require(Permission.circulationOperate);
    return lib.db.q('$_loanSelect WHERE l.book_id = ? ORDER BY l.created_at DESC LIMIT ?', [bookId, limit]);
  }
}
