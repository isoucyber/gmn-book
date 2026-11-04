import 'dart:async';

import 'package:flutter/material.dart';

import '../library.dart';
import '../security/permissions.dart';

/// Estado global da interface: sessao atual, tema e "versao dos dados"
/// (incrementada a cada alteracao, para as telas recarregarem).
class AppState extends ChangeNotifier {
  AppState(this.lib);

  final Library lib;
  Session? session;
  bool? configured;
  bool mustChangePassword = false;
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1.0;
  int dataVersion = 0;

  Timer? _idleTimer;
  Timer? _dueTimer;
  int _timeoutMinutes = 10;

  Future<void> init() async {
    configured = await lib.isConfigured();
    notifyListeners();
  }

  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  Future<void> signedIn(Session s) async {
    session = s;
    mustChangePassword = await lib.auth.mustChangePassword(s);
    _timeoutMinutes = (await lib.settings.load()).sessionTimeoutMinutes;
    await lib.dueControl.generateNotifications();
    _dueTimer?.cancel();
    // Verificacao periodica de prazos (funciona offline).
    _dueTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      await lib.dueControl.generateNotifications();
      dataChanged();
    });
    touch();
    notifyListeners();
  }

  /// Reinicia o contador de inatividade (chamado a cada toque/tecla).
  void touch() {
    if (session == null) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(minutes: _timeoutMinutes), () => signOut(reason: 'inatividade'));
  }

  String? lastSignOutReason;

  Future<void> signOut({String? reason}) async {
    final s = session;
    _idleTimer?.cancel();
    _dueTimer?.cancel();
    session = null;
    mustChangePassword = false;
    lastSignOutReason = reason;
    if (s != null && s.isActive) {
      try {
        await lib.auth.logout(s);
      } catch (_) {}
    }
    notifyListeners();
  }

  void passwordChanged() {
    mustChangePassword = false;
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    notifyListeners();
  }

  void setTextScale(double v) {
    textScale = v;
    notifyListeners();
  }

  /// Apos restaurar um backup ou recuperar o banco.
  Future<void> reloadAfterRestore() async {
    _idleTimer?.cancel();
    _dueTimer?.cancel();
    session = null;
    configured = await lib.isConfigured();
    dataVersion++;
    notifyListeners();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _dueTimer?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  AppState get appRead => AppScope.read(this);
  Library get lib => AppScope.read(this).lib;
  Session get session => AppScope.read(this).session!;
}
