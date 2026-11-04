import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'schema.dart';

/// Banco SQLite local gerenciado pelo Drift.
///
/// O schema e escrito em SQL (lib/data/schema.dart) e acessado por consultas
/// parametrizadas. O Drift cuida da conexao em isolate separado, das
/// transacoes e do versionamento (migrations).
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor, {this.filePath, this.onBeforeUpgrade});

  /// Caminho do arquivo (null para banco em memoria nos testes).
  final String? filePath;

  /// Chamado antes de qualquer migracao de versao (usado para backup automatico).
  final Future<void> Function(AppDatabase db, int fromVersion)? onBeforeUpgrade;

  bool ftsAvailable = false;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final s in schemaV1) {
            await customStatement(s);
          }
        },
        onUpgrade: (m, from, to) async {
          await onBeforeUpgrade?.call(this, from);
          // Migrations futuras entram aqui, sempre incrementais:
          // if (from < 2) { await customStatement('ALTER TABLE ...'); }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          try {
            await customStatement(ftsCreate);
            ftsAvailable = true;
          } catch (_) {
            ftsAvailable = false;
          }
        },
      );

  /// Abre (ou cria) o banco em arquivo. [hexKey] ativa a criptografia do
  /// arquivo inteiro via SQLite3MultipleCiphers.
  static AppDatabase openFile(
    File file, {
    String? hexKey,
    Future<void> Function(AppDatabase db, int fromVersion)? onBeforeUpgrade,
  }) {
    final key = hexKey;
    final executor = NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        if (key != null) {
          raw.execute("PRAGMA hexkey = '$key'");
        }
        raw.execute('PRAGMA busy_timeout = 5000');
        raw.execute('PRAGMA journal_mode = WAL');
        raw.execute('PRAGMA synchronous = NORMAL');
        raw.execute('PRAGMA foreign_keys = ON');
      },
    );
    return AppDatabase(executor, filePath: file.path, onBeforeUpgrade: onBeforeUpgrade);
  }

  static AppDatabase memory() => AppDatabase(NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ));

  // ---------------------------------------------------------------------------
  // Helpers de consulta parametrizada (nunca concatenar valores no SQL).

  static Variable<Object> _v(Object? a) {
    if (a is bool) return Variable<Object>(a ? 1 : 0);
    return Variable<Object>(a);
  }

  static Object? _raw(Object? a) => a is bool ? (a ? 1 : 0) : a;

  Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async {
    final rows = await customSelect(sql, variables: [for (final a in args) _v(a)]).get();
    return [for (final r in rows) Map<String, Object?>.from(r.data)];
  }

  Future<Map<String, Object?>?> q1(String sql, [List<Object?> args = const []]) async {
    final r = await q(sql, args);
    return r.isEmpty ? null : r.first;
  }

  Future<int> count(String sql, [List<Object?> args = const []]) async {
    final r = await q1(sql, args);
    if (r == null || r.isEmpty) return 0;
    final v = r.values.first;
    return v is int ? v : (v as num?)?.toInt() ?? 0;
  }

  Future<void> x(String sql, [List<Object?> args = const []]) =>
      customStatement(sql, [for (final a in args) _raw(a)]);

  /// Executa UPDATE/DELETE e devolve a quantidade de linhas afetadas.
  Future<int> upd(String sql, [List<Object?> args = const []]) =>
      customUpdate(sql, variables: [for (final a in args) _v(a)], updates: const {});

  Future<void> insertMap(String table, Map<String, Object?> row) {
    final cols = row.keys.toList();
    final sql =
        'INSERT INTO $table (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')})';
    return x(sql, [for (final c in cols) row[c]]);
  }

  /// Verifica a integridade do arquivo. Retorna null se estiver integro.
  Future<String?> integrityProblem() async {
    final rows = await q('PRAGMA integrity_check');
    final msgs = rows.map((r) => r.values.first?.toString() ?? '').toList();
    if (msgs.length == 1 && msgs.first == 'ok') return null;
    return msgs.take(5).join('; ');
  }

  /// Copia consistente do arquivo do banco (mesma chave de criptografia).
  Future<void> snapshotTo(String targetPath) async {
    final path = filePath;
    if (path == null) return;
    await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await File(path).copy(targetPath);
  }

  Future<int> userVersion() async {
    final r = await q1('PRAGMA user_version');
    return (r?.values.first as int?) ?? 0;
  }
}
