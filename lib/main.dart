import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library.dart';
import 'ui/app.dart';
import 'ui/app_state.dart';

/// Guarda a chave do banco no armazenamento seguro do sistema
/// (Android Keystore / Windows Credential Manager com DPAPI).
class SecureKeyStore implements KeyStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String name) => _s.read(key: name);
  @override
  Future<void> write(String name, String value) => _s.write(key: name, value: value);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diretorio persistente proprio do app (AppData no Windows, dados internos no
  // Android). Nunca usa caminhos da maquina de desenvolvimento.
  final base = await getApplicationSupportDirectory();
  final dataDir = Directory(p.join(base.path, 'data'));
  Library lib;
  try {
    lib = await Library.open(dataDir, SecureKeyStore());
  } catch (e) {
    runApp(FatalErrorApp(message: e.toString(), dataPath: dataDir.path));
    return;
  }
  final state = AppState(lib);
  await state.init();
  runApp(GmnBookApp(state: state));
}
