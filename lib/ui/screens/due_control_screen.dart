import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../security/permissions.dart';
import '../../services/circulation_service.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'user_screens.dart';

/// CONTROLE DE DEVOLUCOES: proximos do vencimento, em atraso e devolvidos.
class DueControlScreen extends StatelessWidget {
  const DueControlScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Controle de devoluções'),
            bottom: const TabBar(isScrollable: false, tabs: [
              Tab(text: 'Próximos do vencimento'),
              Tab(text: 'Em atraso'),
              Tab(text: 'Devolvidos'),
            ]),
          ),
          body: const TabBarView(children: [_DueList(kind: 0), _DueList(kind: 1), _ReturnedList()]),
        ),
      );
}

class _DueList extends StatelessWidget {
  const _DueList({required this.kind});
  final int kind;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return AsyncView<List<Map<String, Object?>>>(
      load: () => kind == 0 ? lib.dueControl.upcoming(s) : lib.dueControl.overdue(s),
      builder: (context, rows, reload) {
        if (rows.isEmpty) {
          return EmptyState(
            icon: kind == 0 ? Icons.event_available : Icons.verified_outlined,
            title: kind == 0 ? 'Nenhum empréstimo perto do vencimento' : 'Nenhum empréstimo em atraso',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => PageBody(child: LoanCard(loan: rows[i], showContact: kind == 1)),
        );
      },
    );
  }
}

class _ReturnedList extends StatelessWidget {
  const _ReturnedList();
  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return AsyncView<List<Map<String, Object?>>>(
      load: () => lib.circulation.returnedLoans(s),
      builder: (context, rows, _) {
        if (rows.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, title: 'Nenhuma devolução registrada');
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final l = rows[i];
            final daysLate = daysBetween(parseIsoDate(l['due_date'] as String), parseIsoDate(l['return_date'] as String));
            return PageBody(
              child: Card(
                child: ListTile(
                  leading: Icon(Icons.assignment_turned_in_outlined, color: daysLate > 0 ? Brand.warn : Brand.ok),
                  title: Text('${l['user_name']} — ${l['title']}'),
                  subtitle: Text('Retirado ${brDateIso(l['loan_date'] as String)} · previsto ${brDateIso(l['due_date'] as String)} · '
                      'devolvido ${brDateIso(l['return_date'] as String)}${daysLate > 0 ? ' ($daysLate dia(s) de atraso)' : ''}'
                      '${l['condition_in'] != null && l['condition_in'] != 'bom' ? ' · ${l['condition_in']}' : ''}'),
                  trailing: Text('tombo ${l['accession_number']}'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Cartao de emprestimo ativo com situacao, dias restantes e acoes.
class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.loan, this.showContact = false, this.showUser = true});
  final Map<String, Object?> loan;
  final bool showContact;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lib = context.lib;
    final s = context.session;
    final today = AppClock.today();
    final left = daysLeftOf(loan, today);
    final state = loan['state'] is String
        ? LoanState.values.byName(loan['state'] as String)
        : (left < 0 ? LoanState.overdue : (left <= 3 ? LoanState.nearDue : LoanState.active));
    final color = loanStateColor(state, context);
    final contacts = [
      if (loan['phone'] != null) 'Tel.: ${loan['phone']}',
      if (loan['email'] != null) 'E-mail: ${loan['email']}',
      if (loan['guardian_phone'] != null) 'Responsável: ${loan['guardian_name'] ?? ''} ${loan['guardian_phone']}',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showUser)
                  Text('${loan['user_name']}${loan['class_name'] != null ? ' · ${loan['class_name']}' : ''}',
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                Text('${loan['title']} (tombo ${loan['accession_number']})'),
                Text('Retirado ${brDateIso(loan['loan_date'] as String)} · devolução ${brDateIso(loan['due_date'] as String)}',
                    style: t.textTheme.bodySmall),
                if (showContact && contacts.isNotEmpty) Text(contacts.join(' · '), style: t.textTheme.bodySmall),
              ]),
            ),
            StatusPill(daysLeftLabel(left), color: color),
          ]),
          Wrap(alignment: WrapAlignment.end, children: [
            if (showUser)
              TextButton.icon(
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Leitor'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => UserDetailScreen(userId: loan['user_id'] as String))),
              ),
            TextButton.icon(
              icon: const Icon(Icons.message_outlined, size: 18),
              label: const Text('Mensagem de cobrança'),
              onPressed: () async {
                final msg = await lib.dueControl.reminderMessage(loan);
                if (!context.mounted) return;
                await showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Mensagem pronta'),
                    content: SelectableText(msg),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fechar')),
                      FilledButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar'),
                        onPressed: () {
                          Navigator.pop(c);
                          copyToClipboard(context, msg, done: 'Mensagem copiada. Cole no WhatsApp, e-mail ou SMS.');
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
            if (s.can(Permission.circulationOperate) && left >= 0)
              TextButton.icon(
                icon: const Icon(Icons.update, size: 18),
                label: const Text('Renovar'),
                onPressed: () async {
                  try {
                    final r = await lib.circulation.renew(s, loan['id'] as String);
                    if (!context.mounted) return;
                    showInfo(context, 'Renovado até ${brDateIso(r['due_date'] as String)}.');
                    context.appRead.dataChanged();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
            if (s.can(Permission.circulationOverride))
              TextButton.icon(
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Alterar prazo'),
                onPressed: () => changeDueDialog(context, loan),
              ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> changeDueDialog(BuildContext context, Map<String, Object?> loan) async {
  final lib = context.lib;
  final s = context.session;
  final current = parseIsoDate(loan['due_date'] as String);
  final loanDate = parseIsoDate(loan['loan_date'] as String);
  final d = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: loanDate,
    lastDate: addDays(AppClock.today(), 365),
    helpText: 'Nova data de devolução',
  );
  if (d == null || !context.mounted) return;
  final reason = await promptText(context, 'Motivo da alteração', label: 'Motivo');
  if (reason == null || reason.trim().isEmpty || !context.mounted) return;
  try {
    await lib.circulation.changeDueDate(s, loan['id'] as String, d, reason);
    if (!context.mounted) return;
    showInfo(context, 'Prazo alterado para ${brDate(d)}.');
    context.appRead.dataChanged();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
