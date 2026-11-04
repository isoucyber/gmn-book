import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:gmn_book/core/errors.dart';
import 'package:gmn_book/core/util.dart';
import 'package:gmn_book/library.dart';
import 'package:gmn_book/security/crypto.dart';
import 'package:gmn_book/security/permissions.dart';
import 'package:gmn_book/services/auth_service.dart';
import 'package:gmn_book/services/backup_service.dart';
import 'package:gmn_book/services/catalog_service.dart';
import 'package:gmn_book/services/circulation_service.dart';
import 'package:gmn_book/services/settings_service.dart';
import 'package:gmn_book/services/user_service.dart';

/// Segunda-feira, 02/03/2026, 10h.
final monday = DateTime(2026, 3, 2, 10);
DateTime fakeNow = monday;

void travelTo(DateTime d) => fakeNow = d;
void travelDays(int n) => fakeNow = fakeNow.add(Duration(days: n));

Future<(Library, Session)> bootstrap() async {
  final lib = await Library.inMemory();
  final code = await lib.auth.completeSetup(SetupData(
    schoolName: 'Escola Teste',
    hostName: 'Ana Bibliotecária',
    hostUsername: 'ana',
    hostPassword: 'Senha123',
  ));
  expect(code, matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')));
  final s = await lib.auth.login('ana', 'Senha123');
  return (lib, s);
}

Future<String> addReader(Library lib, Session host, String name, String user, {String? cls}) async {
  final r = await lib.users.create(host, UserInput(role: Role.user, name: name, username: user, className: cls), 'leitor1');
  return r.id;
}

Future<String> addBook(Library lib, Session host, String title,
    {int copies = 1, int? loanDays, List<String> authors = const ['Machado de Assis'], String? isbn}) {
  return lib.catalog.createBook(
      host, BookInput(title: title, authors: authors, loanDays: loanDays, category: 'Literatura', isbn: isbn),
      copies: copies);
}

Future<Map<String, Object?>> firstCopy(Library lib, Session s, String bookId, {String status = 'available'}) async {
  final c = await lib.catalog.copies(s, bookId);
  return c.firstWhere((x) => x['status'] == status);
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // Custo reduzido de Argon2id apenas nos testes.
    PasswordHasher.memoryKiB = 64;
    PasswordHasher.iterations = 1;
  });
  setUp(() {
    fakeNow = monday;
    AppClock.override(() => fakeNow);
  });
  tearDown(AppClock.reset);

  group('Utilitarios', () {
    test('normalizacao e busca tolerante', () {
      expect(normalize('Ação  É Ótima!'), 'acao e otima');
      expect(fuzzyMatch('machado de assiz', normalize('Dom Casmurro Machado de Assis')), isTrue);
      expect(fuzzyMatch('casmuro', normalize('Dom Casmurro')), isTrue);
      expect(fuzzyMatch('harry', normalize('Dom Casmurro')), isFalse);
    });
    test('validacao de ISBN', () {
      expect(cleanIsbn('978-85-359-0277-8'), '9788535902778');
      expect(cleanIsbn('9788535902777'), isNull);
      expect(cleanIsbn('0-306-40615-2'), '0306406152');
    });
    test('UUID v4', () {
      final ids = {for (var i = 0; i < 1000; i++) newId()};
      expect(ids.length, 1000);
      expect(ids.first, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
    test('hash de senha Argon2id', () async {
      final h = await PasswordHasher.hash('segredo123');
      expect(h, startsWith('argon2id\$'));
      expect(await PasswordHasher.verify('segredo123', h), isTrue);
      expect(await PasswordHasher.verify('errada', h), isFalse);
    });
  });

  group('Primeiro acesso e autenticacao', () {
    test('setup so pode ser feito uma vez e nao ha senha padrao', () async {
      final (lib, _) = await bootstrap();
      expect(await lib.isConfigured(), isTrue);
      expect(
          () => lib.auth.completeSetup(SetupData(
              schoolName: 'X', hostName: 'Y', hostUsername: 'outro', hostPassword: 'Senha123')),
          throwsA(isA<AppException>()));
      expect(() => lib.auth.login('admin', 'admin'), throwsA(isA<AppException>()));
    });

    test('bloqueio apos tentativas excessivas e expiracao do bloqueio', () async {
      final (lib, _) = await bootstrap();
      for (var i = 0; i < 4; i++) {
        await expectLater(lib.auth.login('ana', 'errada'), throwsA(isA<AppException>()));
      }
      await expectLater(
          lib.auth.login('ana', 'errada'), throwsA(predicate((e) => e is AppException && e.code == 'locked')));
      // Mesmo com a senha certa, continua bloqueado.
      await expectLater(
          lib.auth.login('ana', 'Senha123'), throwsA(predicate((e) => e is AppException && e.code == 'locked')));
      fakeNow = fakeNow.add(const Duration(minutes: 16));
      final s = await lib.auth.login('ana', 'Senha123');
      expect(s.role, Role.host);
    });

    test('recuperacao de senha por codigo (offline) e codigo de uso unico', () async {
      final lib = await Library.inMemory();
      final code = await lib.auth.completeSetup(
          SetupData(schoolName: 'E', hostName: 'Ana', hostUsername: 'ana', hostPassword: 'Senha123'));
      final newCode = await lib.auth.resetWithRecoveryCode('ana', code.toLowerCase(), 'NovaSenha9');
      expect(newCode, isNot(code));
      expect((await lib.auth.login('ana', 'NovaSenha9')).role, Role.host);
      await expectLater(lib.auth.resetWithRecoveryCode('ana', code, 'Outra1234'), throwsA(isA<AppException>()));
    });

    test('autocadastro respeita o modo configurado', () async {
      final (lib, host) = await bootstrap();
      final active = await lib.auth.signup(SignupData(name: 'Joao', username: 'joao', password: 'abc123', consent: true));
      expect(active, isFalse);
      await expectLater(lib.auth.login('joao', 'abc123'), throwsA(predicate((e) => e is AppException && e.code == 'pending')));
      final id = (await lib.users.list(host, search: 'joao')).first['id'] as String;
      await lib.users.setStatus(host, id, 'active');
      expect((await lib.auth.login('joao', 'abc123')).role, Role.user);

      await lib.settings.save(host, {SettingKeys.signupMode: 'disabled'});
      await expectLater(
          lib.auth.signup(SignupData(name: 'Maria', username: 'maria', password: 'abc123', consent: true)),
          throwsA(isA<AppException>()));
      await expectLater(
          lib.auth.signup(SignupData(name: 'Sem termo', username: 'x1', password: 'abc123', consent: false)),
          throwsA(isA<AppException>()));
    });

    test('conta criada pela biblioteca exige troca de senha', () async {
      final (lib, host) = await bootstrap();
      await addReader(lib, host, 'Pedro', 'pedro');
      final s = await lib.auth.login('pedro', 'leitor1');
      expect(await lib.auth.mustChangePassword(s), isTrue);
      await lib.auth.changePassword(s, 'leitor1', 'nova123');
      expect(await lib.auth.mustChangePassword(s), isFalse);
    });
  });

  group('Permissoes reais (nos servicos)', () {
    test('USER nao cadastra livros, nao ve outros usuarios nem emprestimos alheios', () async {
      final (lib, host) = await bootstrap();
      final joao = await addReader(lib, host, 'Joao', 'joao');
      final maria = await addReader(lib, host, 'Maria', 'maria');
      final s = await lib.auth.login('joao', 'leitor1');
      await expectLater(lib.catalog.createBook(s, BookInput(title: 'X')), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.users.list(s), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.circulation.userLoans(s, maria), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.dueControl.overdue(s), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.backup.create(s), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.settings.save(s, {SettingKeys.defaultLoanDays: '30'}), throwsA(isA<PermissionDenied>()));
      await expectLater(lib.audit.list(s), throwsA(isA<PermissionDenied>()));
      expect(await lib.circulation.userLoans(s, joao), isEmpty);
      // Catalogo continua acessivel.
      expect(await lib.catalog.search(s), isA<List>());
    });

    test('AUXILIAR registra emprestimos mas nao altera regras nem cria administradores', () async {
      final (lib, host) = await bootstrap();
      final r = await lib.users.create(host, UserInput(role: Role.staff, name: 'Aux', username: 'aux'), 'Auxiliar1');
      expect(r.recoveryCode, isNotNull);
      final aux = await lib.auth.login('aux', 'Auxiliar1');
      await expectLater(lib.settings.save(aux, {SettingKeys.defaultLoanDays: '30'}), throwsA(isA<PermissionDenied>()));
      await expectLater(
          lib.users.create(aux, UserInput(role: Role.host, name: 'Hacker', username: 'hk'), 'Hacker123'),
          throwsA(isA<PermissionDenied>()));
      final reader = await addReader(lib, host, 'Leitor', 'leitor');
      final book = await addBook(lib, host, 'Dom Casmurro');
      final copy = await firstCopy(lib, aux, book);
      final loan = await lib.circulation.checkout(aux, userId: reader, copyId: copy['id'] as String);
      expect(loan['status'], 'active');
    });

    test('sessao encerrada nao acessa mais nada', () async {
      final (lib, host) = await bootstrap();
      await lib.auth.logout(host);
      await expectLater(lib.catalog.search(host), throwsA(isA<PermissionDenied>()));
    });

    test('nao e possivel remover o ultimo administrador', () async {
      final (lib, host) = await bootstrap();
      await expectLater(lib.users.setStatus(host, host.userId, 'inactive'), throwsA(isA<AppException>()));
    });
  });

  group('Acervo', () {
    test('cadastro, exemplares com tombo unico, busca offline e arquivamento', () async {
      final (lib, host) = await bootstrap();
      final id = await addBook(lib, host, 'Dom Casmurro', copies: 3, loanDays: 14, isbn: '978-85-359-0277-8');
      final b = await lib.catalog.getBook(host, id);
      expect(b!['total'], 3);
      expect(b['available'], 3);
      expect(b['loan_days'], 14);
      final copies = await lib.catalog.copies(host, id);
      expect(copies.map((c) => c['accession_number']).toSet().length, 3);

      final more = await lib.catalog.addCopies(host, id, 2);
      expect(more.first, greaterThan(copies.map((c) => c['accession_number'] as int).reduce((a, b) => a > b ? a : b)));

      await addBook(lib, host, 'O Pequeno Príncipe', authors: ['Antoine de Saint-Exupéry']);
      expect((await lib.catalog.search(host, query: 'machado de assiz')).first['id'], id);
      expect((await lib.catalog.search(host, query: 'pequeno principe')).length, 1);
      expect((await lib.catalog.search(host, query: '9788535902778')).first['id'], id);
      expect((await lib.catalog.findDuplicates(host, isbn: '9788535902778')).length, 1);
      expect((await lib.catalog.findDuplicates(host, title: 'dom casmurro')).length, 1);

      await lib.catalog.setArchived(host, id, true);
      expect(await lib.catalog.search(host, query: 'casmurro'), isEmpty);
      expect((await lib.catalog.search(host, query: 'casmurro', includeArchived: true)).length, 1);
    });

    test('ISBN invalido e rejeitado', () async {
      final (lib, host) = await bootstrap();
      await expectLater(addBook(lib, host, 'X', isbn: '9788535902777'), throwsA(isA<ValidationException>()));
    });
  });

  group('Circulacao e prazos', () {
    test('prazo do titulo e usado automaticamente e pula fim de semana e feriado', () async {
      final (lib, host) = await bootstrap();
      final reader = await addReader(lib, host, 'Joao', 'joao');
      final b14 = await addBook(lib, host, 'Dom Casmurro', loanDays: 14);
      final b12 = await addBook(lib, host, 'Memórias Póstumas', loanDays: 12);
      final l1 = await lib.circulation.checkout(host, userId: reader, copyId: (await firstCopy(lib, host, b14))['id'] as String);
      expect(l1['due_date'], '2026-03-16'); // segunda + 14 = segunda
      await lib.settings.addClosedDays(host, DateTime(2026, 3, 16), DateTime(2026, 3, 16), 'Feriado municipal');
      final reader2 = await addReader(lib, host, 'Maria', 'maria');
      final l2 = await lib.circulation.checkout(host, userId: reader2, copyId: (await firstCopy(lib, host, b12))['id'] as String);
      // segunda + 12 = sabado -> domingo -> segunda (feriado) -> terca
      expect(l2['due_date'], '2026-03-17');
    });

    test('prazo padrao da biblioteca e alteracao manual', () async {
      final (lib, host) = await bootstrap();
      await lib.settings.save(host, {SettingKeys.defaultLoanDays: '7'});
      final reader = await addReader(lib, host, 'Joao', 'joao');
      final b = await addBook(lib, host, 'Livro sem prazo proprio');
      final l = await lib.circulation.checkout(host, userId: reader, copyId: (await firstCopy(lib, host, b))['id'] as String);
      expect(l['due_date'], '2026-03-09');
      await lib.circulation.changeDueDate(host, l['id'] as String, DateTime(2026, 3, 20), 'Trabalho escolar');
      expect((await lib.circulation.getLoan(host, l['id'] as String))!['due_date'], '2026-03-20');
      // Prazo manual informado no ato do emprestimo.
      final b2 = await addBook(lib, host, 'Outro');
      final l2 = await lib.circulation.checkout(host,
          userId: reader, copyId: (await firstCopy(lib, host, b2))['id'] as String, dueDate: DateTime(2026, 3, 25));
      expect(l2['due_date'], '2026-03-25');
    });

    test('exemplar nao pode ser emprestado a duas pessoas e disponibilidade e atualizada', () async {
      final (lib, host) = await bootstrap();
      final a = await addReader(lib, host, 'Ana Leitora', 'leitora');
      final b = await addReader(lib, host, 'Bruno Leitor', 'leitorb');
      final book = await addBook(lib, host, 'Unico', copies: 1);
      final copy = (await firstCopy(lib, host, book))['id'] as String;
      await lib.circulation.checkout(host, userId: a, copyId: copy);
      expect((await lib.catalog.getBook(host, book))!['available'], 0);
      await expectLater(lib.circulation.checkout(host, userId: b, copyId: copy), throwsA(isA<AppException>()));
      // A restricao tambem existe no banco (indice unico parcial).
      await expectLater(
          lib.db.x("INSERT INTO loans (id, user_id, book_id, copy_id, loan_date, due_date, status, created_by, created_at, updated_at) "
              "VALUES ('x', ?, ?, ?, '2026-03-02', '2026-03-10', 'active', ?, 0, 0)", [b, book, copy, host.userId]),
          throwsA(anything));
      final ret = await lib.circulation.returnCopy(host, copy);
      expect(ret['status'], 'returned');
      expect((await lib.catalog.getBook(host, book))!['available'], 1);
      await lib.circulation.checkout(host, userId: b, copyId: copy);
    });

    test('limite de livros e bloqueio por atraso com liberacao justificada', () async {
      final (lib, host) = await bootstrap();
      final r = await addReader(lib, host, 'Joao', 'joao');
      final books = [for (var i = 0; i < 3; i++) await addBook(lib, host, 'Livro $i', loanDays: 7)];
      await lib.circulation.checkout(host, userId: r, copyId: (await firstCopy(lib, host, books[0]))['id'] as String);
      await lib.circulation.checkout(host, userId: r, copyId: (await firstCopy(lib, host, books[1]))['id'] as String);
      final third = (await firstCopy(lib, host, books[2]))['id'] as String;
      await expectLater(lib.circulation.checkout(host, userId: r, copyId: third),
          throwsA(predicate((e) => e is LoanBlockedException && e.blocks.any((b) => b.code == 'limit'))));
      final ok = await lib.circulation.checkout(host, userId: r, copyId: third, overrideReason: 'Projeto de leitura');
      expect(ok['override_reason'], 'Projeto de leitura');

      travelDays(10); // todos vencidos
      final r2 = await addReader(lib, host, 'Outro', 'outro');
      final extra = await addBook(lib, host, 'Extra');
      await lib.circulation.returnCopy(host, (await firstCopy(lib, host, books[0], status: 'loaned'))['barcode'] as String);
      final blocks = await lib.circulation.blocksFor(r);
      expect(blocks.any((b) => b.code == 'overdue'), isTrue);
      expect(await lib.circulation.blocksFor(r2), isEmpty);
      await lib.circulation.checkout(host, userId: r2, copyId: (await firstCopy(lib, host, extra))['id'] as String);
    });

    test('renovacao respeita regras do titulo e atraso', () async {
      final (lib, host) = await bootstrap();
      final r = await addReader(lib, host, 'Joao', 'joao');
      final b = await lib.catalog.createBook(host, BookInput(title: 'Renovavel', loanDays: 7, maxRenewals: 1));
      final nb = await lib.catalog.createBook(host, BookInput(title: 'Nao renovavel', loanDays: 7, allowRenewal: false));
      final l = await lib.circulation.checkout(host, userId: r, copyId: (await firstCopy(lib, host, b))['id'] as String);
      final l2 = await lib.circulation.checkout(host, userId: r, copyId: (await firstCopy(lib, host, nb))['id'] as String);
      travelDays(3);
      final renewed = await lib.circulation.renew(host, l['id'] as String);
      expect(renewed['due_date'], '2026-03-12'); // 05/03 + 7
      expect(renewed['renewals'], 1);
      await expectLater(lib.circulation.renew(host, l['id'] as String), throwsA(isA<AppException>()));
      await expectLater(lib.circulation.renew(host, l2['id'] as String), throwsA(isA<AppException>()));
      // Leitor nao renova pelo portal com a opcao desligada.
      final s = await lib.auth.login('joao', 'leitor1');
      await expectLater(lib.circulation.renew(s, l2['id'] as String), throwsA(isA<PermissionDenied>()));
    });

    test('desfazer a ultima operacao dentro da janela', () async {
      final (lib, host) = await bootstrap();
      final r = await addReader(lib, host, 'Joao', 'joao');
      final b = await addBook(lib, host, 'Livro');
      final copy = await firstCopy(lib, host, b);
      final l = await lib.circulation.checkout(host, userId: r, copyId: copy['id'] as String);
      await lib.circulation.undoLast(host);
      expect((await lib.circulation.getLoan(host, l['id'] as String))!['status'], 'cancelled');
      expect((await lib.catalog.getBook(host, b))!['available'], 1);

      await lib.circulation.checkout(host, userId: r, copyId: copy['id'] as String);
      await lib.circulation.returnCopy(host, copy['barcode'] as String);
      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await lib.circulation.undoLast(host);
      expect((await lib.catalog.getBook(host, b))!['loaned'], 1);
      fakeNow = fakeNow.add(const Duration(minutes: 5));
      await expectLater(lib.circulation.undoLast(host), throwsA(isA<AppException>()));
    });

    test('devolucao com dano e extravio muda o exemplar e gera pendencia', () async {
      final (lib, host) = await bootstrap();
      final r = await addReader(lib, host, 'Joao', 'joao');
      final b = await addBook(lib, host, 'Livro', copies: 2);
      final copies = await lib.catalog.copies(host, b);
      await lib.circulation.checkout(host, userId: r, copyId: copies[0]['id'] as String);
      await lib.circulation.returnCopy(host, copies[0]['barcode'] as String, lost: true);
      final after = await lib.catalog.copies(host, b);
      expect(after.firstWhere((c) => c['id'] == copies[0]['id'])['status'], 'lost');
      expect((await lib.circulation.blocksFor(r)).any((x) => x.code == 'pending'), isTrue);
    });
  });

  group('Controle de devolucoes e alertas (simulando datas)', () {
    test('proximos, atrasados e devolvidos sao calculados pela data atual', () async {
      final (lib, host) = await bootstrap();
      final joao = await addReader(lib, host, 'Joao', 'joao');
      final maria = await addReader(lib, host, 'Maria', 'maria');
      final pedro = await addReader(lib, host, 'Pedro', 'pedro');
      final b1 = await addBook(lib, host, 'Dom Casmurro', loanDays: 3);
      final b2 = await addBook(lib, host, 'O Pequeno Príncipe', loanDays: 1);
      final b3 = await addBook(lib, host, 'A Revolução dos Bichos', loanDays: 14);
      await lib.circulation.checkout(host, userId: joao, copyId: (await firstCopy(lib, host, b1))['id'] as String);
      await lib.circulation.checkout(host, userId: maria, copyId: (await firstCopy(lib, host, b2))['id'] as String);
      final l3 = await lib.circulation.checkout(host, userId: pedro, copyId: (await firstCopy(lib, host, b3))['id'] as String);

      var upcoming = await lib.dueControl.upcoming(host);
      expect(upcoming.map((l) => l['days_left']).toList(), [1, 3]);
      expect(await lib.dueControl.overdue(host), isEmpty);

      travelDays(2); // quarta
      upcoming = await lib.dueControl.upcoming(host);
      expect(upcoming.first['user_name'], 'Joao');
      expect(upcoming.first['days_left'], 1);
      final overdue = await lib.dueControl.overdue(host);
      expect(overdue.single['user_name'], 'Maria');
      expect(overdue.single['days_left'], -1);
      expect(overdue.single['state'], LoanState.overdue.name);

      travelTo(DateTime(2026, 3, 16, 9)); // dia do vencimento do Pedro
      upcoming = await lib.dueControl.upcoming(host);
      expect(upcoming.single['id'], l3['id']);
      expect(daysLeftLabel(upcoming.single['days_left'] as int), 'vence hoje');

      await lib.circulation.returnCopy(host, (await firstCopy(lib, host, b3, status: 'loaned'))['barcode'] as String);
      final returned = await lib.circulation.returnedLoans(host);
      expect(returned.single['user_name'], 'Pedro');
    });

    test('notificacoes internas nos dias configurados, sem duplicar', () async {
      final (lib, host) = await bootstrap();
      await lib.settings.save(host, {SettingKeys.alertDays: '3,1,0,-1'});
      final joao = await addReader(lib, host, 'Joao', 'joao');
      final b = await addBook(lib, host, 'Dom Casmurro', loanDays: 5); // vence sabado -> segunda 09/03
      final l = await lib.circulation.checkout(host, userId: joao, copyId: (await firstCopy(lib, host, b))['id'] as String);
      expect(l['due_date'], '2026-03-09');

      expect(await lib.dueControl.generateNotifications(), 0); // faltam 7 dias
      travelTo(DateTime(2026, 3, 6, 8)); // faltam 3
      expect(await lib.dueControl.generateNotifications(), 2); // HOST + leitor
      expect(await lib.dueControl.generateNotifications(), 0); // idempotente
      travelTo(DateTime(2026, 3, 9, 8)); // vence hoje
      expect(await lib.dueControl.generateNotifications(), 2);
      travelTo(DateTime(2026, 3, 11, 8)); // 2 dias de atraso
      expect(await lib.dueControl.generateNotifications(), 2);

      final s = await lib.auth.login('joao', 'leitor1');
      final mine = await lib.dueControl.notifications(s);
      expect(mine.length, 3);
      expect(mine.every((n) => n['user_id'] == joao), isTrue);
      expect(await lib.dueControl.unreadCount(s), 3);
      await lib.dueControl.markAllRead(s);
      expect(await lib.dueControl.unreadCount(s), 0);
      final staff = await lib.dueControl.notifications(host);
      expect(staff.where((n) => n['audience'] == 'staff').length, 3);
    });

    test('mensagem de cobranca usa o modelo', () async {
      final (lib, host) = await bootstrap();
      final joao = await addReader(lib, host, 'Joao Silva', 'joao');
      final b = await addBook(lib, host, 'Dom Casmurro', loanDays: 14);
      final l = await lib.circulation.checkout(host, userId: joao, copyId: (await firstCopy(lib, host, b))['id'] as String);
      travelDays(12);
      final msg = await lib.dueControl.reminderMessage(l);
      expect(msg, contains('Joao'));
      expect(msg, contains('Dom Casmurro'));
      expect(msg, contains('vence em 2 dia'));
    });

    test('quem esta com cada livro / usuarios com emprestimos', () async {
      final (lib, host) = await bootstrap();
      final joao = await addReader(lib, host, 'Joao', 'joao');
      final b1 = await addBook(lib, host, 'Livro A');
      final b2 = await addBook(lib, host, 'Livro B');
      await lib.circulation.checkout(host, userId: joao, copyId: (await firstCopy(lib, host, b1))['id'] as String);
      await lib.circulation.checkout(host, userId: joao, copyId: (await firstCopy(lib, host, b2))['id'] as String);
      final copies = await lib.catalog.copies(host, b1);
      expect(copies.single['borrower_name'], 'Joao');
      final grouped = await lib.circulation.usersWithActiveLoans(host, search: 'joao');
      expect((grouped.single['loans'] as List).length, 2);
    });
  });

  group('Auditoria', () {
    test('registros sao imutaveis', () async {
      final (lib, host) = await bootstrap();
      final logs = await lib.audit.list(host);
      expect(logs, isNotEmpty);
      await expectLater(lib.db.x('UPDATE audit_logs SET action = ?', ['x']), throwsA(anything));
      await expectLater(lib.db.x('DELETE FROM audit_logs'), throwsA(anything));
      expect(logs.any((l) => (l['old_value'] ?? '').toString().contains('password_hash')), isFalse);
    });
  });

  group('Backup e restauracao (banco em arquivo, criptografado)', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('gmn_test_'));
    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('dados persistem apos fechar e reabrir', () async {
      final keys = MemoryKeyStore();
      var lib = await Library.open(Directory('${tmp.path}/data'), keys);
      await lib.auth.completeSetup(SetupData(schoolName: 'E', hostName: 'Ana', hostUsername: 'ana', hostPassword: 'Senha123'));
      final host = await lib.auth.login('ana', 'Senha123');
      await addBook(lib, host, 'Persistente');
      await lib.close();

      lib = await Library.open(Directory('${tmp.path}/data'), keys);
      expect(lib.state, StartupState.ok);
      final s = await lib.auth.login('ana', 'Senha123');
      expect((await lib.catalog.search(s, query: 'persistente')).length, 1);
      await lib.close();

      // O arquivo do banco esta criptografado: sem a chave, nao abre.
      final raw = await File('${tmp.path}/data/${Library.dbFileName}').readAsBytes();
      expect(String.fromCharCodes(raw.take(15)), isNot('SQLite format 3'));
      final noKey = await Library.open(Directory('${tmp.path}/data'), MemoryKeyStore());
      expect(noKey.state, StartupState.keyMissing);
    });

    test('backup criptografado: senha errada, restauracao e integridade', () async {
      final keys = MemoryKeyStore();
      final a = await Library.open(Directory('${tmp.path}/a'), keys);
      await a.auth.completeSetup(SetupData(schoolName: 'Escola A', hostName: 'Ana', hostUsername: 'ana', hostPassword: 'Senha123'));
      final ha = await a.auth.login('ana', 'Senha123');
      final reader = await addReader(a, ha, 'Joao', 'joao');
      final book = await addBook(a, ha, 'Dom Casmurro', copies: 2, loanDays: 14);
      await a.catalog.setCover(ha, book, TestImages.png, 'png');
      await a.circulation.checkout(ha, userId: reader, copyId: (await firstCopy(a, ha, book))['id'] as String);
      final backup = await a.backup.create(ha, password: 'backup-forte-1');
      expect(backup.fileName, endsWith('.gmnbak'));

      await expectLater(a.backup.open(backup.bytes), throwsA(isA<AppException>()));
      await expectLater(a.backup.open(backup.bytes, password: 'errada123'), throwsA(isA<AppException>()));
      final tampered = Uint8List.fromList(backup.bytes)..[backup.bytes.length - 5] ^= 0xff;
      await expectLater(a.backup.open(tampered, password: 'backup-forte-1'), throwsA(isA<AppException>()));

      // Outro aparelho, com seus proprios dados.
      final keysB = MemoryKeyStore();
      final b = await Library.open(Directory('${tmp.path}/b'), keysB);
      await b.auth.completeSetup(SetupData(schoolName: 'Escola B', hostName: 'Bia', hostUsername: 'bia', hostPassword: 'Senha456'));
      final hb = await b.auth.login('bia', 'Senha456');
      final contents = await b.backup.open(backup.bytes, password: 'backup-forte-1');
      expect(contents.counts['books'], 1);
      expect(contents.counts['loans'], 1);
      await expectLater(b.backup.restoreReplaceAll(hb, contents, 'senhaErrada'), throwsA(isA<AppException>()));
      final installB = await b.installationId();
      await b.backup.restoreReplaceAll(hb, contents, 'Senha456');
      expect(hb.isActive, isFalse);

      final s = await b.auth.login('ana', 'Senha123');
      final books = await b.catalog.search(s, query: 'casmurro');
      expect(books.single['loaned'], 1);
      expect((await b.circulation.activeLoans(s)).single['user_name'], 'Joao');
      expect((await b.settings.load()).schoolName, 'Escola A');
      expect(await b.installationId(), installB);
      expect(b.catalog.coverFile(books.single['cover_file'] as String?), isNotNull);
      expect(b.listAutoSnapshots(), isNotEmpty); // copia automatica antes de restaurar
      expect(await b.db.integrityProblem(), isNull);
      await a.close();
      await b.close();
    });

    test('backup sem senha tambem e verificado', () async {
      final (lib, host) = await bootstrap();
      await addBook(lib, host, 'Livro');
      final bk = await lib.backup.create(host);
      final c = await lib.backup.open(bk.bytes);
      expect(c.encrypted, isFalse);
      expect(c.counts['books'], 1);
      expect(() => BackupService.readHeader(Uint8List.fromList(List.filled(40, 1))), throwsA(isA<AppException>()));
    });
  });
}

/// Imagem PNG minima (1x1) para testar capas.
class TestImages {
  static final png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);
}
