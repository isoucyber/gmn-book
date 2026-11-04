import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../data/schema.dart';
import '../../security/permissions.dart';
import '../../services/backup_service.dart' show appVersion;
import '../app_state.dart';
import '../shell.dart';
import '../widgets.dart';
import 'auth_screens.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.session!;
    final t = Theme.of(context);
    return PageScaffold(
      title: 'Minha conta',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        PageBody(
          maxWidth: 760,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(radius: 24, child: Text(s.name.substring(0, 1).toUpperCase())),
                title: Text(s.name, style: t.textTheme.titleMedium),
                subtitle: Text('${s.username} · ${s.role.label}'),
              ),
            ),
            const SectionTitle('Aparência e acessibilidade'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {app.themeMode},
                    onSelectionChanged: (v) => app.setTheme(v.first),
                  ),
                  const SizedBox(height: 16),
                  Text('Tamanho do texto: ${(app.textScale * 100).round()}%'),
                  Slider(
                    value: app.textScale,
                    min: 0.85,
                    max: 1.5,
                    divisions: 13,
                    label: '${(app.textScale * 100).round()}%',
                    onChanged: app.setTextScale,
                  ),
                ]),
              ),
            ),
            const SectionTitle('Segurança'),
            Card(
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Trocar senha'),
                  onTap: () => showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Trocar senha'),
                      content: SizedBox(width: 420, child: ChangePasswordForm(onDone: () => Navigator.pop(c))),
                    ),
                  ),
                ),
                if (s.role != Role.user)
                  ListTile(
                    leading: const Icon(Icons.key),
                    title: const Text('Gerar novo código de recuperação'),
                    subtitle: const Text('O código anterior deixa de valer'),
                    onTap: () async {
                      final pw = await promptText(context, 'Confirme sua senha', label: 'Senha', obscure: true);
                      if (pw == null || !context.mounted) return;
                      try {
                        final code = await context.lib.users.regenerateOwnRecoveryCode(s, pw);
                        if (!context.mounted) return;
                        await showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Novo código de recuperação'),
                            content: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 22, letterSpacing: 2)),
                            actions: [
                              TextButton(onPressed: () => copyToClipboard(c, code), child: const Text('Copiar')),
                              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Guardei')),
                            ],
                          ),
                        );
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sair'),
                  onTap: () => app.signOut(),
                ),
              ]),
            ),
            const SectionTitle('Privacidade'),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Seus dados ficam guardados apenas no aparelho da biblioteca, em banco de dados criptografado. '
                    'Eles são usados somente para controlar empréstimos e devoluções. Você pode pedir à biblioteca '
                    'a correção dos seus dados a qualquer momento.'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Sobre',
      body: AsyncView<String>(
        load: () => lib.installationId(),
        builder: (context, inst, _) => ListView(padding: const EdgeInsets.all(16), children: [
          PageBody(
            maxWidth: 760,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: BrandMark(size: 52))),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    const InfoRow('Aplicativo', 'GMN BOOK OFFLINE'),
                    const InfoRow('Versão', appVersion),
                    const InfoRow('Versão do banco', '$kSchemaVersion'),
                    InfoRow('ID da instalação', inst),
                    InfoRow('Busca rápida (FTS5)', lib.db.ftsAvailable ? 'ativa' : 'modo compatível'),
                    if (s.role != Role.user && lib.dataDir != null) InfoRow('Pasta de dados', lib.dataDir!.path),
                  ]),
                ),
              ),
              const SectionTitle('Como os dados funcionam'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'O GMN BOOK funciona sem internet e sem servidor. Cada instalação (notebook, celular ou tablet) tem '
                    'seu próprio banco de dados local e criptografado. Não existe sincronização automática: um empréstimo '
                    'registrado no notebook NÃO aparece no celular até que os dados sejam transferidos com '
                    '"Backup e restauração".\n\n'
                    'A internet é usada apenas, e de forma opcional, para sugerir dados de livros pelo ISBN '
                    '(Google Books / Open Library), enviando somente o ISBN.',
                  ),
                ),
              ),
              const SectionTitle('Atalhos de teclado (Windows)'),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    InfoRow('Ctrl + K', 'Busca global'),
                    InfoRow('F2', 'Balcão — novo empréstimo'),
                    InfoRow('F3', 'Balcão — devolução'),
                    InfoRow('Ctrl + N', 'Novo livro'),
                    InfoRow('Leitor USB', 'Clique no campo de código e leia: funciona como teclado'),
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

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: s.role == Role.user ? 'Avisos' : 'Notificações',
      actions: [
        TextButton(
          onPressed: () async {
            await lib.dueControl.markAllRead(s);
            if (context.mounted) context.appRead.dataChanged();
          },
          child: const Text('Marcar todas como lidas'),
        ),
      ],
      body: AsyncView<List<Map<String, Object?>>>(
        load: () async {
          await lib.dueControl.generateNotifications();
          return lib.dueControl.notifications(s);
        },
        builder: (context, rows, _) {
          if (rows.isEmpty) return const EmptyState(icon: Icons.notifications_none, title: 'Nenhum aviso por enquanto');
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final n = rows[i];
              final unread = n['read_at'] == null;
              return PageBody(
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(unread ? Icons.notifications_active : Icons.notifications_none,
                        color: unread ? Theme.of(context).colorScheme.primary : null),
                    title: Text(n['title'] as String, style: TextStyle(fontWeight: unread ? FontWeight.w700 : null)),
                    subtitle: Text('${n['body'] ?? ''}'),
                    trailing: Text(brDateTimeMs(n['created_at'] as int), style: Theme.of(context).textTheme.bodySmall),
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
