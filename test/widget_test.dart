import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmn_book/library.dart';
import 'package:gmn_book/security/crypto.dart';
import 'package:gmn_book/services/auth_service.dart';
import 'package:gmn_book/ui/app.dart';
import 'package:gmn_book/ui/app_state.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    PasswordHasher.memoryKiB = 64;
    PasswordHasher.iterations = 1;
  });

  testWidgets('primeira execucao abre o assistente de configuracao', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      final lib = await Library.inMemory();
      state = AppState(lib);
      await state.init();
    });
    await tester.pumpWidget(GmnBookApp(state: state));
    await tester.pump();
    expect(find.text('Bem-vindo! Vamos configurar a biblioteca.'), findsOneWidget);
    expect(find.text('Escola'), findsWidgets);
  });

  testWidgets('apos configurar, mostra a tela de login', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late AppState state;
    await tester.runAsync(() async {
      final lib = await Library.inMemory();
      await lib.auth.completeSetup(
          SetupData(schoolName: 'Escola', hostName: 'Ana', hostUsername: 'ana', hostPassword: 'Senha123'));
      state = AppState(lib);
      await state.init();
    });
    await tester.pumpWidget(GmnBookApp(state: state));
    await tester.pump();
    expect(find.text('Entrar'), findsWidgets);
    expect(find.text('Usuário ou carteirinha'), findsOneWidget);
  });
}
