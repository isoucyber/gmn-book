import 'dart:io';

import 'package:path/path.dart' as p;

import 'core/util.dart';
import 'data/database.dart';
import 'security/crypto.dart';
import 'services/audit_service.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/catalog_service.dart';
import 'services/circulation_service.dart';
import 'services/dashboard_service.dart';
import 'services/due_control_service.dart';
import 'services/settings_service.dart';
import 'services/user_service.dart';

/// Onde a chave do banco fica guardada (Keystore/DPAPI na versao instalada).
abstract class KeyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String value);
}

class MemoryKeyStore implements KeyStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String name) async => _m[name];
  @override
  Future<void> write(String name, String value) async => _m[name] = value;
}

enum StartupState { ok, corrupted, keyMissing, openFailed }

/// Contexto da biblioteca: banco, pastas e servicos.
class Library {
  Library._(this.dataDir, this._db, this.keyStore, this._hexKey);

  final Directory? dataDir;
  final KeyStore keyStore;
  AppDatabase _db;
  String? _hexKey;
  StartupState state = StartupState.ok;
  String? stateDetail;

  AppDatabase get db => _db;

  late final audit = AuditService(this);
  late final settings = SettingsService(this);
  late final auth = AuthService(this);
  late final users = UserService(this);
  late final catalog = CatalogService(this);
  late final circulation = CirculationService(this);
  late final dueControl = DueControlService(this);
  late final dashboard = DashboardService(this);
  late final backup = BackupService(this);

  static const dbFileName = 'gmn_book.db';
  static const keyName = 'gmn_book_db_key';

  String? get dbPath => dataDir == null ? null : p.join(dataDir!.path, dbFileName);
  Directory? get coversDir => dataDir == null ? null : Directory(p.join(dataDir!.path, 'covers'));
  Directory? get autoBackupDir =>
      dataDir == null ? null : Directory(p.join(dataDir!.path, 'auto_backups'));

  /// Banco em memoria, para testes automatizados.
  static Future<Library> inMemory() async {
    final lib = Library._(null, AppDatabase.memory(), MemoryKeyStore(), null);
    await lib._postOpen();
    return lib;
  }

  /// Abre a biblioteca no diretorio persistente do aplicativo.
  static Future<Library> open(Directory dataDir, KeyStore keyStore) async {
    await dataDir.create(recursive: true);
    await Directory(p.join(dataDir.path, 'covers')).create(recursive: true);
    await Directory(p.join(dataDir.path, 'auto_backups')).create(recursive: true);

    final dbFile = File(p.join(dataDir.path, dbFileName));
    final exists = await dbFile.exists() && await dbFile.length() > 0;
    var key = await keyStore.read(keyName);
    var state = StartupState.ok;
    if (key == null) {
      if (exists) {
        state = StartupState.keyMissing;
      } else {
        key = PasswordHasher.randomBytes(32)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        await keyStore.write(keyName, key);
      }
    }

    late Library lib;
    if (state == StartupState.keyMissing) {
      // Abre um banco temporario vazio so para a tela de recuperacao.
      lib = Library._(dataDir, AppDatabase.memory(), keyStore, null);
      lib.state = state;
      lib.stateDetail =
          'O arquivo de dados existe, mas a chave de proteção deste aparelho não foi encontrada.';
      await lib._postOpen();
      return lib;
    }

    lib = Library._(dataDir, _openFile(dbFile, key, null), keyStore, key);
    lib._db = _openFile(dbFile, key, lib);
    try {
      await lib.db.q('SELECT count(*) FROM sqlite_master');
      final problem = await lib.db.integrityProblem();
      if (problem != null) {
        lib.state = StartupState.corrupted;
        lib.stateDetail = problem;
      }
      await lib._postOpen();
    } catch (e) {
      lib.state = StartupState.openFailed;
      lib.stateDetail = e.toString();
    }
    return lib;
  }

  static AppDatabase _openFile(File f, String? key, Library? lib) => AppDatabase.openFile(
        f,
        hexKey: key,
        onBeforeUpgrade: (db, from) async {
          // Backup automatico antes de qualquer migracao de versao.
          if (lib != null) await lib.autoSnapshot('pre-migracao-v$from', db: db);
        },
      );

  Future<void> _postOpen() async {
    final inst = await _db.q1("SELECT value FROM app_meta WHERE key = 'installation_id'");
    if (inst == null) {
      await _db.x("INSERT OR IGNORE INTO app_meta (key, value) VALUES ('installation_id', ?)", [newId()]);
    }
  }

  Future<String> installationId() async =>
      (await _db.q1("SELECT value FROM app_meta WHERE key = 'installation_id'"))?['value'] as String? ??
      '';

  Future<bool> isConfigured() async =>
      (await _db.q1("SELECT value FROM app_meta WHERE key = 'setup_done'")) != null;

  /// Copia do arquivo do banco para auto_backups (mantem as 10 mais recentes).
  Future<String?> autoSnapshot(String reason, {AppDatabase? db}) async {
    final dir = autoBackupDir;
    if (dir == null) return null;
    await dir.create(recursive: true);
    final stamp = AppClock.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final target = p.join(dir.path, 'auto_${stamp}_$reason.db');
    await (db ?? _db).snapshotTo(target);
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.skip(10)) {
      try {
        await f.delete();
      } catch (_) {}
    }
    return target;
  }

  List<File> listAutoSnapshots() {
    final dir = autoBackupDir;
    if (dir == null || !dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Substitui o banco atual por outro arquivo ja validado.
  /// O arquivo atual e preservado (renomeado), nunca apagado.
  Future<void> swapDatabaseFile(String newFilePath) async {
    final path = dbPath;
    if (path == null) throw StateError('banco em memória');
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await _db.close();
    final stamp = AppClock.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final current = File(path);
    if (await current.exists()) {
      await current.rename(p.join(autoBackupDir!.path, 'substituido_$stamp.db.old'));
    }
    for (final ext in ['-wal', '-shm']) {
      final f = File('$path$ext');
      if (await f.exists()) await f.delete();
    }
    await File(newFilePath).rename(path);
    _db = _openFile(File(path), _hexKey, this);
    await _db.q('SELECT count(*) FROM sqlite_master');
    state = StartupState.ok;
    stateDetail = null;
    await _postOpen();
  }

  /// Cria um banco novo (com a chave deste aparelho) em caminho temporario.
  Future<(AppDatabase, String)> createScratchDatabase() async {
    final dir = dataDir!;
    final tmp = p.join(dir.path, 'restore_${AppClock.nowMs()}.db');
    final key = _hexKey ?? await _ensureNewKey();
    final db = AppDatabase.openFile(File(tmp), hexKey: key);
    await db.q('SELECT count(*) FROM sqlite_master');
    return (db, tmp);
  }

  Future<String> _ensureNewKey() async {
    final key =
        PasswordHasher.randomBytes(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await keyStore.write(keyName, key);
    _hexKey = key;
    return key;
  }

  /// Inicia do zero quando o banco nao pode ser aberto. O arquivo antigo
  /// e movido para auto_backups, nunca apagado.
  Future<void> startFresh() async {
    final path = dbPath;
    if (path == null) return;
    try {
      await _db.close();
    } catch (_) {}
    final stamp = AppClock.now().toIso8601String().replaceAll(':', '-').split('.').first;
    for (final ext in ['', '-wal', '-shm']) {
      final f = File('$path$ext');
      if (await f.exists()) {
        await f.rename(p.join(autoBackupDir!.path, 'inacessivel_$stamp.db$ext.old'));
      }
    }
    final key = _hexKey ?? await _ensureNewKey();
    _db = _openFile(File(path), key, this);
    await _db.q('SELECT count(*) FROM sqlite_master');
    state = StartupState.ok;
    stateDetail = null;
    await _postOpen();
  }

  Future<void> restoreAutoSnapshot(File snapshot) async {
    final tmp = p.join(dataDir!.path, 'snapshot_restore_${AppClock.nowMs()}.db');
    await snapshot.copy(tmp);
    final probe = AppDatabase.openFile(File(tmp), hexKey: _hexKey);
    try {
      await probe.q('SELECT count(*) FROM sqlite_master');
      final problem = await probe.integrityProblem();
      if (problem != null) throw StateError('Cópia automática também está danificada: $problem');
      await probe.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      await probe.close();
    }
    await swapDatabaseFile(tmp);
  }

  Future<void> close() => _db.close();
}
