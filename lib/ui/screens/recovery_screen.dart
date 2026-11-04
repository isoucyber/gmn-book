import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../library.dart';
import '../../services/backup_service.dart';
import '../app_state.dart';
import '../file_io.dart';
import '../theme.dart';
import '../widgets.dart';

/// Exibida quando o banco local nao pode ser usado (arquivo danificado,
/// chave de protecao ausente). Nada e apagado: os arquivos antigos sao
/// movidos para a pasta de copias automaticas.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});
  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      await context.appRead.reloadAfterRestore();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromBackupFile() async {
    final f = await FileIO.pickFile();
    if (f == null || !mounted) return;
    final lib = context.lib;
    try {
      final header = BackupService.readHeader(f.bytes);
      String? pw;
      if (header['encrypted'] == true) {
        pw = await promptText(context, 'Senha do backup', obscure: true, label: 'Senha');
        if (pw == null) return;
      }
      final contents = await lib.backup.open(f.bytes, password: pw);
      if (!mounted) return;
      final ok = await confirm(context, 'Restaurar backup?',
          'Backup de ${contents.school}, criado em ${brDateTime(contents.createdAt)}. '
          'Contém ${contents.counts['books']} livros, ${contents.counts['users']} usuários e ${contents.counts['loans']} empréstimos.');
      if (!ok) return;
      await _run(() => lib.backup.importInto(contents));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final t = Theme.of(context);
    final snapshots = lib.state == StartupState.keyMissing ? <File>[] : lib.listAutoSnapshots();
    final title = switch (lib.state) {
      StartupState.corrupted => 'O banco de dados apresentou problemas',
      StartupState.keyMissing => 'Chave de proteção não encontrada',
      StartupState.openFailed => 'Não foi possível abrir o banco de dados',
      StartupState.ok => 'Tudo certo',
    };
    return Scaffold(
      body: SafeArea(
        child: PageBody(
          maxWidth: 680,
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.health_and_safety_outlined, size: 56, color: Brand.warn),
            const SizedBox(height: 12),
            Text(title, style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(lib.stateDetail ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Nenhum arquivo será apagado. Escolha como recuperar:', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_busy) const LinearProgressIndicator(),
            if (snapshots.isNotEmpty) ...[
              const SectionTitle('Cópias automáticas deste aparelho'),
              for (final s in snapshots.take(5))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(p.basename(s.path)),
                    subtitle: Text(brDateTime(s.lastModifiedSync())),
                    trailing: const Icon(Icons.restore),
                    onTap: _busy ? null : () => _run(() => lib.restoreAutoSnapshot(s)),
                  ),
                ),
            ],
            const SectionTitle('Outras opções'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Restaurar de um arquivo de backup (.gmnbak)'),
                subtitle: const Text('Backup manual feito pelo administrador'),
                onTap: _busy ? null : _fromBackupFile,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.restart_alt, color: t.colorScheme.error),
                title: const Text('Começar do zero'),
                subtitle: const Text('O arquivo atual será guardado na pasta de cópias, não apagado.'),
                onTap: _busy
                    ? null
                    : () async {
                        final ok = await confirm(context, 'Começar do zero?',
                            'A biblioteca ficará vazia e será preciso fazer a configuração inicial novamente.',
                            destructive: true, ok: 'Começar do zero');
                        if (ok) await _run(lib.startFresh);
                      },
              ),
            ),
            const SizedBox(height: 16),
            if (lib.dataDir != null)
              SelectableText('Pasta de dados: ${lib.dataDir!.path}', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

String brDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
