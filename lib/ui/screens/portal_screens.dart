import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../services/circulation_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'book_screens.dart';
import 'catalog_screen.dart';

/// Portal do leitor: apenas os proprios emprestimos e informacoes.
class PortalHomeScreen extends StatelessWidget {
  const PortalHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final t = Theme.of(context);
    return PageScaffold(
      title: 'Olá, ${s.name.split(' ').first}!',
      body: AsyncView<(List<Map<String, Object?>>, int, bool)>(
        load: () async {
          final loans = await lib.circulation.userLoans(s, s.userId);
          await lib.dueControl.generateNotifications();
          final unread = await lib.dueControl.unreadCount(s);
          final st = await lib.settings.load();
          return (loans, unread, st.userCanRenew);
        },
        builder: (context, data, reload) {
          final (loans, unread, canRenew) = data;
          final today = AppClock.today();
          return ListView(padding: const EdgeInsets.all(16), children: [
            PageBody(
              maxWidth: 900,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (unread > 0)
                  Card(
                    color: Brand.warn.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active, color: Brand.warn),
                      title: Text('Você tem $unread aviso(s) novo(s)'),
                    ),
                  ),
                SectionTitle('Meus empréstimos (${loans.length})'),
                if (loans.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Você não está com nenhum livro no momento. Que tal explorar o catálogo?'),
                    ),
                  ),
                for (final l in loans)
                  Builder(builder: (context) {
                    final left = daysLeftOf(l, today);
                    final state = left < 0 ? LoanState.overdue : (left <= 3 ? LoanState.nearDue : LoanState.active);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          BookCover(fileName: l['cover_file'] as String?, title: l['title'] as String, width: 56),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l['title'] as String, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text('Retirado em ${brDateIso(l['loan_date'] as String)}'),
                              Text('Devolver até ${weekdayName(parseIsoDate(l['due_date'] as String))}, ${brDateIso(l['due_date'] as String)}'),
                              const SizedBox(height: 6),
                              StatusPill(daysLeftLabel(left), color: loanStateColor(state, context)),
                            ]),
                          ),
                          if (canRenew && left >= 0)
                            TextButton(
                              onPressed: () async {
                                try {
                                  final r = await lib.circulation.renew(s, l['id'] as String);
                                  if (!context.mounted) return;
                                  showInfo(context, 'Renovado até ${brDateIso(r['due_date'] as String)}.');
                                  reload();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                              child: const Text('Renovar'),
                            ),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  'Os prazos mostrados são os registrados neste aparelho. Em caso de dúvida, confirme no balcão da biblioteca.',
                  style: t.textTheme.bodySmall,
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Favoritos',
      body: AsyncView<List<Map<String, Object?>>>(
        load: () => lib.catalog.favorites(s),
        builder: (context, rows, _) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.favorite_border,
              title: 'Nenhum favorito ainda',
              message: 'Toque no coração na página de um livro para guardá-lo aqui.',
            );
          }
          return LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 360).floor().clamp(1, 4);
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols, mainAxisExtent: 148, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemCount: rows.length,
              itemBuilder: (_, i) => BookCard(book: rows[i]),
            );
          });
        },
      ),
    );
  }
}

class PortalHistoryScreen extends StatelessWidget {
  const PortalHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Meu histórico',
      body: AsyncView<List<Map<String, Object?>>>(
        load: () => lib.circulation.userLoans(s, s.userId, history: true),
        builder: (context, rows, _) {
          if (rows.isEmpty) return const EmptyState(icon: Icons.history, title: 'Seu histórico de leitura aparecerá aqui');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final l = rows[i];
              return PageBody(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: BookCover(fileName: l['cover_file'] as String?, title: l['title'] as String, width: 36),
                    title: Text(l['title'] as String),
                    subtitle: Text(l['status'] == 'returned'
                        ? 'Lido de ${brDateIso(l['loan_date'] as String)} a ${brDateIso(l['return_date'] as String?)}'
                        : 'Empréstimo cancelado'),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: l['book_id'] as String))),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
