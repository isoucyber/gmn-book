import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../services/catalog_service.dart';
import '../../services/circulation_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'due_control_screen.dart';
import 'user_screens.dart';

/// "QUEM ESTA COM CADA LIVRO?"
class WhoHasScreen extends StatefulWidget {
  const WhoHasScreen({super.key});
  @override
  State<WhoHasScreen> createState() => _WhoHasScreenState();
}

class _WhoHasScreenState extends State<WhoHasScreen> {
  String _q = '';
  Timer? _t;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Quem está com cada livro?',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: PageBody(
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Título, autor ou ISBN'),
              onChanged: (v) {
                _t?.cancel();
                _t = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v));
              },
            ),
          ),
        ),
        Expanded(
          child: AsyncView<List<(Map<String, Object?>, List<Map<String, Object?>>)>>(
            deps: _q,
            load: () async {
              final books = await lib.catalog.search(s, query: _q, availability: Availability.loaned, limit: 60);
              final out = <(Map<String, Object?>, List<Map<String, Object?>>)>[];
              for (final b in books) {
                final copies = await lib.catalog.copies(s, b['id'] as String);
                out.add((b, copies.where((c) => c['status'] == 'loaned').toList()));
              }
              return out;
            },
            builder: (context, rows, _) {
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.person_search,
                  title: _q.isEmpty ? 'Nenhum livro emprestado no momento' : 'Nenhum livro emprestado encontrado',
                );
              }
              final today = AppClock.today();
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                for (final (b, copies) in rows)
                  PageBody(
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(b['title'] as String, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text('${b['authors'] ?? '—'} · ${b['loaned']} de ${b['total']} emprestado(s)', style: Theme.of(context).textTheme.bodySmall),
                          const Divider(),
                          for (final c in copies)
                            _BorrowerRow(copy: c, today: today),
                        ]),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _BorrowerRow extends StatelessWidget {
  const _BorrowerRow({required this.copy, required this.today});
  final Map<String, Object?> copy;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final left = daysBetween(today, parseIsoDate(copy['due_date'] as String));
    final state = left < 0 ? LoanState.overdue : (left <= 3 ? LoanState.nearDue : LoanState.active);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text((copy['borrower_name'] as String? ?? '?').substring(0, 1))),
      title: Text('${copy['borrower_name']}'),
      subtitle: Text('Tombo ${copy['accession_number']} · retirado ${brDateIso(copy['loan_date'] as String)} · '
          'devolução ${brDateIso(copy['due_date'] as String)} · ${state.label}'),
      trailing: StatusPill(daysLeftLabel(left), color: loanStateColor(state, context)),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => UserDetailScreen(userId: copy['borrower_id'] as String))),
    );
  }
}

/// "USUARIOS COM EMPRESTIMOS ATIVOS"
class UsersWithLoansScreen extends StatefulWidget {
  const UsersWithLoansScreen({super.key});
  @override
  State<UsersWithLoansScreen> createState() => _UsersWithLoansScreenState();
}

class _UsersWithLoansScreenState extends State<UsersWithLoansScreen> {
  String _q = '';
  Timer? _t;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Usuários com empréstimos ativos',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: PageBody(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nome, turma ou carteirinha'),
              onChanged: (v) {
                _t?.cancel();
                _t = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v));
              },
            ),
          ),
        ),
        Expanded(
          child: AsyncView<List<Map<String, Object?>>>(
            deps: _q,
            load: () => lib.circulation.usersWithActiveLoans(s, search: _q),
            builder: (context, rows, _) {
              if (rows.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'Ninguém com empréstimo ativo');
              return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
                for (final u in rows)
                  PageBody(
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        shape: const Border(),
                        leading: CircleAvatar(child: Text((u['user_name'] as String).substring(0, 1))),
                        title: Text(u['user_name'] as String),
                        subtitle: Text([
                          u['card_code'],
                          u['class_name'],
                          '${(u['loans'] as List).length} livro(s)',
                        ].whereType<String>().join(' · ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if ((u['overdue'] as int) > 0)
                            StatusPill('${u['overdue']} atrasado(s)', color: Theme.of(context).colorScheme.error),
                          if ((u['near_due'] as int) > 0) ...[
                            const SizedBox(width: 6),
                            StatusPill('${u['near_due']} vencendo', color: Brand.warn),
                          ],
                        ]),
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          for (final l in (u['loans'] as List).cast<Map<String, Object?>>())
                            Padding(padding: const EdgeInsets.only(bottom: 8), child: LoanCard(loan: l, showUser: false)),
                        ],
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
