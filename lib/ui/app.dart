import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../library.dart';
import 'app_state.dart';
import 'screens/auth_screens.dart';
import 'screens/recovery_screen.dart';
import 'screens/setup_screen.dart';
import 'shell.dart';
import 'theme.dart';

class GmnBookApp extends StatelessWidget {
  const GmnBookApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'GMN BOOK',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(state.textScale)),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => state.touch(),
                child: child!,
              ),
            );
          },
          home: const RootRouter(),
        ),
      ),
    );
  }
}

/// Decide a tela inicial: recuperacao, primeiro acesso, login, troca de senha
/// obrigatoria ou o aplicativo.
class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (app.lib.state != StartupState.ok) return const RecoveryScreen();
    if (app.configured == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (app.configured == false) return const SetupScreen();
    if (app.session == null) return const LoginScreen();
    if (app.mustChangePassword) return const ForcedPasswordChangeScreen();
    return AppShell(key: ValueKey(app.session!.userId));
  }
}

class FatalErrorApp extends StatelessWidget {
  const FatalErrorApp({super.key, required this.message, required this.dataPath});
  final String message;
  final String dataPath;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 56, color: Brand.danger),
                const SizedBox(height: 12),
                const Text('Não foi possível iniciar o GMN BOOK', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                SelectableText('Pasta de dados: $dataPath', textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      );
}
