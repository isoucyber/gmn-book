import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmn_book/core/util.dart';
import 'package:gmn_book/library.dart';
import 'package:gmn_book/main.dart' show SecureKeyStore;
import 'package:gmn_book/services/auth_service.dart';
import 'package:gmn_book/services/catalog_service.dart';
import 'package:gmn_book/services/user_service.dart';
import 'package:gmn_book/security/permissions.dart';
import 'package:gmn_book/ui/app.dart';
import 'package:gmn_book/ui/app_state.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Executado no aparelho/sistema real (Windows e emulador Android no CI):
/// usa o SQLite criptografado nativo, o armazenamento seguro do sistema e
/// o diretorio persistente do aplicativo.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fluxo completo na plataforma real', (tester) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'it_${DateTime.now().millisecondsSinceEpoch}'));
    final keys = SecureKeyStore();

    // 1. Primeiro acesso + login
    var lib = await Library.open(dir, keys);
    expect(lib.state, StartupState.ok);
    expect(await lib.isConfigured(), isFalse);
    await lib.auth.completeSetup(SetupData(
        schoolName: 'Escola CI', hostName: 'Ana CI', hostUsername: 'ana', hostPassword: 'Senha123'));
    final host = await lib.auth.login('ana', 'Senha123');

    // 2. Acervo e leitor
    final bookId = await lib.catalog.createBook(
        host, BookInput(title: 'Dom Casmurro', authors: ['Machado de Assis'], loanDays: 14), copies: 2);
    final reader = (await lib.users.create(host, UserInput(role: Role.user, name: 'Joao', username: 'joao'), 'leitor1')).id;
    expect((await lib.catalog.search(host, query: 'machado de assiz')).single['id'], bookId);

    // 3. Emprestimo, alerta com data simulada, devolucao
    final copy = (await lib.catalog.copies(host, bookId)).first;
    final loan = await lib.circulation.checkout(host, userId: reader, copyId: copy['id'] as String);
    expect(parseIsoDate(loan['due_date'] as String).isAfter(AppClock.today()), isTrue);
    AppClock.override(() => parseIsoDate(loan['due_date'] as String).add(const Duration(days: 2, hours: 9)));
    expect((await lib.dueControl.overdue(host)).single['user_name'], 'Joao');
    expect(await lib.dueControl.generateNotifications(), greaterThan(0));
    AppClock.reset();
    await lib.circulation.returnCopy(host, copy['barcode'] as String);
    expect((await lib.catalog.getBook(host, bookId))!['available'], 2);

    // 4. Backup criptografado
    final bk = await lib.backup.create(host, password: 'senha-backup-1');
    final contents = await lib.backup.open(bk.bytes, password: 'senha-backup-1');
    expect(contents.counts['loans'], 1);

    // 5. Persistencia: fecha e reabre
    await lib.close();
    lib = await Library.open(dir, keys);
    expect(lib.state, StartupState.ok);
    final again = await lib.auth.login('ana', 'Senha123');
    expect((await lib.circulation.returnedLoans(again)).length, 1);

    // 6. Restauracao (substitui tudo) e integridade
    await lib.backup.restoreReplaceAll(again, contents, 'Senha123');
    final s3 = await lib.auth.login('ana', 'Senha123');
    expect((await lib.catalog.getBook(s3, bookId))!['total'], 2);
    expect(await lib.db.integrityProblem(), isNull);
    await lib.close();

    // 7. Interface: abre e mostra a tela de login
    final uiLib = await Library.open(dir, keys);
    final state = AppState(uiLib);
    await state.init();
    await tester.pumpWidget(GmnBookApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Usuário ou carteirinha'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'ana');
    await tester.enterText(find.byType(TextField).at(1), 'Senha123');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    for (var i = 0; i < 40 && state.session == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(state.session, isNotNull);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Painel'), findsWidgets);
    await uiLib.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
