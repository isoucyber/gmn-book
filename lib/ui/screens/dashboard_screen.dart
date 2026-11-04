import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../services/audit_service.dart';
import '../../services/dashboard_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'backup_screen.dart';
import 'due_control_screen.dart';
import 'user_screens.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Painel',
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            await lib.dueControl.generateNotifications();
            if (context.mounted) context.appRead.dataChanged();
          },
        ),
      ],
      body: AsyncView<DashboardStats>(
        load: () => lib.dashboard.load(s),
        builder: (context, d, reload) {
          final w = MediaQuery.sizeOf(context).width;
          final cols = w >= 1300 ? 4 : (w >= 700 ? 3 : 2);
          void push(Widget p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => p));
          final cards = [
            StatCard(label: 'Títulos no acervo', value: '${d.titles}', icon: Icons.auto_stories),
            StatCard(label: 'Exemplares', value: '${d.copies}', icon: Icons.library_books_outlined),
            StatCard(label: 'Disponíveis', value: '${d.available}', icon: Icons.check_circle_outline, color: Brand.ok),
            StatCard(label: 'Emprestados', value: '${d.loaned}', icon: Icons.outbox_outlined, color: Brand.aqua),
            StatCard(label: 'Leitores ativos', value: '${d.users}', icon: Icons.groups_outlined,
                onTap: () => push(const UsersScreen())),
            StatCard(label: 'Empréstimos ativos', value: '${d.activeLoans}', icon: Icons.swap_horiz),
            StatCard(label: 'Próximos do vencimento', value: '${d.nearDue}', icon: Icons.schedule, color: Brand.warn,
                onTap: () => push(const DueControlScreen(initialTab: 0))),
            StatCard(label: 'Em atraso', value: '${d.overdue}', icon: Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
                onTap: () => push(const DueControlScreen(initialTab: 1))),
            StatCard(label: 'Devoluções (7 dias)', value: '${d.returnsLast7}', icon: Icons.assignment_return_outlined,
                onTap: () => push(const DueControlScreen(initialTab: 2))),
            StatCard(label: 'Reservas ativas', value: '${d.activeReservations}', icon: Icons.bookmark_border),
          ];
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              PageBody(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (d.backupOverdue)
                    Card(
                      color: Brand.warn.withValues(alpha: 0.12),
                      child: ListTile(
                        leading: const Icon(Icons.backup_outlined, color: Brand.warn),
                        title: Text(d.lastBackupAt == null
                            ? 'Nenhum backup foi feito ainda'
                            : 'Último backup em ${brDateTimeMs(d.lastBackupAt)}'),
                        subtitle: const Text('Os dados ficam só neste aparelho. Faça backups regularmente.'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => push(const BackupScreen()),
                      ),
                    ),
                  if (d.pendingUsers > 0) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.how_to_reg_outlined),
                        title: Text('${d.pendingUsers} cadastro(s) aguardando aprovação'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => push(const UsersScreen(initialStatus: 'pending')),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: cols == 2 ? 1.9 : 2.6,
                    children: cards,
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(builder: (context, c) {
                    final charts = [
                      _ChartCard(title: 'Empréstimos por mês', data: d.loansPerMonth),
                      _ChartCard(title: 'Categorias mais procuradas', data: d.topCategories, horizontal: true),
                    ];
                    if (c.maxWidth >= 800) {
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: charts[0]),
                        const SizedBox(width: 12),
                        Expanded(child: charts[1]),
                      ]);
                    }
                    return Column(children: [charts[0], const SizedBox(height: 12), charts[1]]);
                  }),
                  const SectionTitle('Atividades recentes'),
                  Card(
                    child: d.recentActivity.isEmpty
                        ? const Padding(padding: EdgeInsets.all(20), child: Text('Nenhuma atividade ainda.'))
                        : Column(children: [
                            for (final a in d.recentActivity)
                              ListTile(
                                dense: true,
                                leading: Icon(_activityIcon(a['action'] as String), size: 20),
                                title: Text(AuditService.describe(a['action'] as String)),
                                subtitle: Text(_activityDetail(a)),
                                trailing: Text(brDateTimeMs(a['at'] as int), style: Theme.of(context).textTheme.bodySmall),
                              ),
                          ]),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  static IconData _activityIcon(String a) => switch (a) {
        'loan.create' => Icons.outbox_outlined,
        'loan.return' => Icons.assignment_return_outlined,
        'loan.renew' => Icons.update,
        'book.create' || 'copy.create' => Icons.library_add_outlined,
        'user.create' => Icons.person_add_alt,
        _ => Icons.backup_outlined,
      };

  static String _activityDetail(Map<String, Object?> a) {
    final nv = a['new_value'] as String?;
    final who = a['user_name'] as String? ?? '';
    if (nv != null) {
      final m = RegExp(r'"title":"([^"]*)"').firstMatch(nv);
      if (m != null) return '${m.group(1)} · por $who';
      final n = RegExp(r'"name":"([^"]*)"').firstMatch(nv);
      if (n != null) return '${n.group(1)} · por $who';
    }
    return [a['details'], 'por $who'].whereType<String>().join(' · ');
  }
}

/// Grafico de barras leve, desenhado sem bibliotecas externas.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.data, this.horizontal = false});
  final String title;
  final List<({String label, int value})> data;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final max = data.isEmpty ? 0 : data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (data.isEmpty || max == 0)
            const SizedBox(height: 120, child: Center(child: Text('Sem dados no período.')))
          else if (horizontal)
            Column(children: [
              for (final e in data)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(e.label, overflow: TextOverflow.ellipsis)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: e.value / max,
                          minHeight: 14,
                          color: Brand.aqua,
                          backgroundColor: t.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.right)),
                  ]),
                ),
            ])
          else
            SizedBox(
              height: 140,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final e in data)
                  Expanded(
                    child: Semantics(
                      label: '${e.label}: ${e.value}',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('${e.value}', style: t.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: e.value / max),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut,
                          builder: (_, v, _) => Container(
                            height: 96 * v + 2,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: t.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(e.label, style: t.textTheme.labelSmall),
                      ]),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
