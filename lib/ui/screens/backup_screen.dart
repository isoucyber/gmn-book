import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../security/permissions.dart';
import '../../services/audit_service.dart';
import '../../services/backup_service.dart';
import '../app_state.dart';
import '../file_io.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'recovery_screen.dart' show brDateTime;

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final pw = TextEditingController();
    final pw2 = TextEditingController();
    var protect = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Criar backup'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('O backup contém todos os dados da biblioteca, inclusive dados pessoais de alunos. '
                  'Recomendamos protegê-lo com senha.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: protect,
                onChanged: (v) => set(() => protect = v),
                title: const Text('Proteger com senha (criptografia AES-256)'),
              ),
              if (protect) ...[
                TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Senha do backup (mín. 8)')),
                const SizedBox(height: 8),
                TextField(controller: pw2, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme a senha')),
                const SizedBox(height: 8),
                const Text('Sem esta senha não será possível restaurar o backup.', style: TextStyle(fontSize: 12)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar e salvar')),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    if (protect && pw.text != pw2.text) {
      showError(context, 'As senhas não conferem.');
      return;
    }
    try {
      final r = await context.lib.backup.create(context.session, password: protect ? pw.text : null);
      final path = await FileIO.saveFile(r.fileName, r.bytes, title: 'Salvar backup');
      if (!context.mounted) return;
      context.appRead.dataChanged();
      showInfo(context, path == null ? 'Salvamento cancelado.' : 'Backup salvo: $path', seconds: 8);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _restore(BuildContext context) async {
    final lib = context.lib;
    final s = context.session;
    final f = await FileIO.pickFile();
    if (f == null || !context.mounted) return;
    try {
      final header = BackupService.readHeader(f.bytes);
      String? pw;
      if (header['encrypted'] == true) {
        pw = await promptText(context, 'Senha do backup', label: 'Senha', obscure: true);
        if (pw == null || !context.mounted) return;
      }
      final contents = await lib.backup.open(f.bytes, password: pw);
      if (!context.mounted) return;
      final counts = contents.counts;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Conferir backup'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InfoRow('Escola', contents.school),
              InfoRow('Criado em', brDateTime(contents.createdAt)),
              InfoRow('Versão do app', contents.version),
              InfoRow('Aparelho de origem', contents.sourceInstallation),
              InfoRow('Livros', '${counts['books']}'),
              InfoRow('Exemplares', '${counts['book_copies']}'),
              InfoRow('Usuários', '${counts['users']}'),
              InfoRow('Empréstimos', '${counts['loans']}'),
              InfoRow('Capas', '${contents.covers.length}'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Brand.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                    'ATENÇÃO: todos os dados atuais deste aparelho serão SUBSTITUÍDOS pelos dados do backup. '
                    'Uma cópia automática do estado atual será guardada antes. Depois da restauração, será preciso entrar novamente.'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Substituir dados'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final admin = await promptText(context, 'Confirme sua senha de administrador', label: 'Sua senha', obscure: true);
      if (admin == null || !context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Restaurando…')]),
        ),
      );
      try {
        await lib.backup.restoreReplaceAll(s, contents, admin);
      } finally {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Backup restaurado'),
          content: const Text('Os dados foram restaurados. Entre novamente para continuar.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (context.mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        await context.appRead.reloadAfterRestore();
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final t = Theme.of(context);
    return PageScaffold(
      title: 'Backup e restauração',
      body: AsyncView<List<Map<String, Object?>>>(
        load: () => lib.backup.history(s),
        builder: (context, hist, _) {
          final last = hist.where((h) => h['kind'] == 'manual').firstOrNull;
          return ListView(padding: const EdgeInsets.all(16), children: [
            PageBody(
              maxWidth: 860,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(last == null ? Icons.warning_amber_rounded : Icons.verified_outlined,
                            color: last == null ? Brand.warn : Brand.ok),
                        const SizedBox(width: 8),
                        Text(last == null ? 'Nenhum backup feito ainda' : 'Último backup: ${brDateTimeMs(last['at'] as int)}',
                            style: t.textTheme.titleMedium),
                      ]),
                      const SizedBox(height: 8),
                      const Text(
                          'Os dados ficam somente neste aparelho. Guarde backups em um pendrive, HD externo ou nuvem pessoal. '
                          'O backup também serve para transferir os dados para outro aparelho: cada instalação tem seu próprio banco, '
                          'e um empréstimo registrado aqui só aparece em outro aparelho depois de restaurar um backup nele.'),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        FilledButton.icon(onPressed: () => _create(context), icon: const Icon(Icons.save_alt), label: const Text('Criar backup')),
                        if (s.can(Permission.backupRestore))
                          OutlinedButton.icon(onPressed: () => _restore(context), icon: const Icon(Icons.restore), label: const Text('Restaurar backup')),
                      ]),
                    ]),
                  ),
                ),
                const SectionTitle('Histórico'),
                Card(
                  child: hist.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('Sem registros.'))
                      : Column(children: [
                          for (final h in hist)
                            ListTile(
                              dense: true,
                              leading: Icon(h['kind'] == 'manual' ? Icons.save_alt : Icons.restore),
                              title: Text(h['kind'] == 'manual' ? (h['file_name'] as String? ?? 'Backup') : 'Restauração'),
                              subtitle: Text('${brDateTimeMs(h['at'] as int)} · ${h['user_name'] ?? '—'}'
                                  '${toBool(h['encrypted']) ? ' · criptografado' : ''}'
                                  '${h['size_bytes'] != null ? ' · ${((h['size_bytes'] as int) / 1024).toStringAsFixed(0)} KB' : ''}'),
                            ),
                        ]),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return PageScaffold(
      title: 'Auditoria',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: PageBody(
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filtrar por ação, pessoa ou detalhe'),
              onSubmitted: (v) => setState(() => _q = v),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: PageBody(child: Text('Registros imutáveis: não podem ser editados nem apagados.', style: TextStyle(fontSize: 12))),
        ),
        Expanded(
          child: AsyncView<List<Map<String, Object?>>>(
            deps: _q,
            load: () => lib.audit.list(s, search: _q),
            builder: (context, rows, _) => ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final a = rows[i];
                return PageBody(
                  child: ListTile(
                    dense: true,
                    title: Text(AuditService.describe(a['action'] as String)),
                    subtitle: Text([a['user_name'], a['details'], a['new_value']].whereType<String>().join(' · '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Text(brDateTimeMs(a['at'] as int)),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
