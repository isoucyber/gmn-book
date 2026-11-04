import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../core/util.dart';
import '../data/schema.dart';
import '../library.dart';
import '../security/crypto.dart';
import '../security/permissions.dart';

const appVersion = '1.0.0';

/// Conteudo de um backup ja validado (senha correta, checksums conferidos).
class BackupContents {
  final Map<String, dynamic> header;
  final Map<String, List<Map<String, dynamic>>> tables;
  final Map<String, String> covers; // nome do arquivo -> base64
  BackupContents(this.header, this.tables, this.covers);

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(header['created_at'] as int);
  String get school => header['school'] as String? ?? '';
  String get sourceInstallation => header['installation_id'] as String? ?? '';
  String get version => header['app_version'] as String? ?? '';
  bool get encrypted => header['encrypted'] == true;
  Map<String, int> get counts => {for (final e in tables.entries) e.key: e.value.length};
}

/// Formato .gmnbak (versionado):
///   8 bytes  "GMNBAK" + 0x00 + versao do formato
///   4 bytes  tamanho do cabecalho (big-endian)
///   N bytes  cabecalho JSON (metadados, parametros de criptografia, SHA-256)
///   resto    payload = gzip(JSON) — cifrado com AES-256-GCM quando ha senha
///            (chave derivada da senha por Argon2id).
class BackupService {
  final Library lib;
  BackupService(this.lib);

  static const formatVersion = 1;
  static final _magic = [0x47, 0x4D, 0x4E, 0x42, 0x41, 0x4B, 0x00, formatVersion];
  static const extension = 'gmnbak';

  /// Lembrete: tabelas e metadados que pertencem ao aparelho, nao ao backup.
  static const _deviceMetaKeys = {'installation_id'};

  Future<({Uint8List bytes, String fileName})> create(Session s, {String? password}) async {
    s.require(Permission.backupCreate);
    if (password != null && password.isNotEmpty && password.length < 8) {
      throw ValidationException('A senha do backup precisa ter pelo menos 8 caracteres.');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    // Leitura dentro de transacao = fotografia consistente do banco.
    await lib.db.transaction(() async {
      for (final t in backupTables) {
        tables[t] = await lib.db.q('SELECT * FROM $t');
      }
    });
    final covers = <String, String>{};
    final dir = lib.coversDir;
    if (dir != null && await dir.exists()) {
      final referenced = tables['books']!.map((b) => b['cover_file']).whereType<String>().toSet();
      for (final name in referenced) {
        final f = File(p.join(dir.path, p.basename(name)));
        if (await f.exists()) covers[name] = base64Encode(await f.readAsBytes());
      }
    }
    final plainJson = utf8.encode(jsonEncode({'tables': tables, 'covers': covers}));
    final plain = gzip.encode(plainJson);
    final sha = await sha256Hex(plain);
    final settings = await lib.settings.load();
    final now = AppClock.nowMs();
    final header = <String, dynamic>{
      'format': formatVersion,
      'app': 'GMN BOOK',
      'app_version': appVersion,
      'schema_version': kSchemaVersion,
      'created_at': now,
      'installation_id': await lib.installationId(),
      'school': settings.schoolName,
      'counts': {for (final e in tables.entries) e.key: e.value.length},
      'covers': covers.length,
      'sha256': sha,
    };
    List<int> payload = plain;
    final encrypted = password != null && password.isNotEmpty;
    if (encrypted) {
      final salt = PasswordHasher.randomBytes(16);
      const m = 19456, t = 2;
      final key = await PasswordHasher.deriveKey(password, salt, m: m, t: t);
      final enc = await Aead.encrypt(plain, key);
      payload = enc.cipher;
      header['encrypted'] = true;
      header['kdf'] = {'alg': 'argon2id', 'm': m, 't': t, 'p': 1, 'salt': base64Encode(salt)};
      header['cipher'] = {'alg': 'AES-256-GCM', 'nonce': base64Encode(enc.nonce), 'mac': base64Encode(enc.mac)};
    } else {
      header['encrypted'] = false;
    }
    final headerBytes = utf8.encode(jsonEncode(header));
    final out = BytesBuilder()
      ..add(_magic)
      ..add([
        (headerBytes.length >> 24) & 0xff,
        (headerBytes.length >> 16) & 0xff,
        (headerBytes.length >> 8) & 0xff,
        headerBytes.length & 0xff,
      ])
      ..add(headerBytes)
      ..add(payload);
    final bytes = out.toBytes();
    final stamp = AppClock.now().toIso8601String().replaceAll(':', '').replaceAll('-', '').split('.').first;
    final fileName = 'gmnbook_backup_$stamp.$extension';
    await lib.db.transaction(() async {
      await lib.db.insertMap('backup_history', {
        'id': newId(),
        'kind': 'manual',
        'file_name': fileName,
        'size_bytes': bytes.length,
        'encrypted': encrypted ? 1 : 0,
        'by_user': s.userId,
        'at': now,
      });
      await lib.audit.log(s, 'backup.create', 'backup_history', null,
          details: '$fileName (${(bytes.length / 1024).toStringAsFixed(0)} KB, ${encrypted ? 'criptografado' : 'sem senha'})');
    });
    return (bytes: bytes, fileName: fileName);
  }

  /// Le apenas o cabecalho (para saber se precisa de senha).
  static Map<String, dynamic> readHeader(Uint8List bytes) {
    if (bytes.length < 12) throw AppException('Arquivo de backup inválido ou vazio.');
    for (var i = 0; i < 6; i++) {
      if (bytes[i] != _magic[i]) throw AppException('Este arquivo não é um backup do GMN BOOK.');
    }
    if (bytes[7] > formatVersion) {
      throw AppException('Backup criado por uma versão mais nova do GMN BOOK. Atualize o aplicativo.');
    }
    final len = (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
    if (len <= 0 || 12 + len > bytes.length) throw AppException('Cabeçalho do backup corrompido.');
    try {
      return jsonDecode(utf8.decode(bytes.sublist(12, 12 + len))) as Map<String, dynamic>;
    } catch (_) {
      throw AppException('Cabeçalho do backup corrompido.');
    }
  }

  /// Valida integridade e (se for o caso) decifra. Nao altera nada no banco.
  Future<BackupContents> open(Uint8List bytes, {String? password}) async {
    final header = readHeader(bytes);
    final len = (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
    final payload = bytes.sublist(12 + len);
    if ((header['schema_version'] as int? ?? 0) > kSchemaVersion) {
      throw AppException('Backup de uma versão mais nova do banco. Atualize o aplicativo antes de restaurar.');
    }
    List<int> plain;
    if (header['encrypted'] == true) {
      if (password == null || password.isEmpty) {
        throw AppException('Este backup é protegido por senha.', code: 'password_required');
      }
      final kdf = header['kdf'] as Map<String, dynamic>;
      final cipher = header['cipher'] as Map<String, dynamic>;
      final key = await PasswordHasher.deriveKey(password, base64Decode(kdf['salt'] as String),
          m: kdf['m'] as int, t: kdf['t'] as int);
      try {
        plain = await Aead.decrypt(payload, key, base64Decode(cipher['nonce'] as String),
            base64Decode(cipher['mac'] as String));
      } catch (_) {
        throw AppException('Senha incorreta ou arquivo alterado/corrompido.', code: 'bad_password');
      }
    } else {
      plain = payload;
    }
    if (await sha256Hex(plain) != header['sha256']) {
      throw AppException('Falha na verificação de integridade: o arquivo está corrompido.');
    }
    late Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(gzip.decode(plain))) as Map<String, dynamic>;
    } catch (_) {
      throw AppException('Conteúdo do backup ilegível.');
    }
    final rawTables = data['tables'] as Map<String, dynamic>;
    final tables = <String, List<Map<String, dynamic>>>{
      for (final e in rawTables.entries)
        e.key: (e.value as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
    };
    final counts = (header['counts'] as Map).cast<String, dynamic>();
    for (final e in counts.entries) {
      if ((tables[e.key]?.length ?? 0) != e.value) {
        throw AppException('Contagem de registros não confere (${e.key}). Backup inconsistente.');
      }
    }
    for (final required in ['users', 'books', 'book_copies', 'loans', 'library_settings']) {
      if (!tables.containsKey(required)) throw AppException('Backup incompleto: falta "$required".');
    }
    final covers = (data['covers'] as Map? ?? {}).cast<String, dynamic>().map((k, v) => MapEntry(k, v as String));
    return BackupContents(header, tables, covers);
  }

  /// Substitui TODOS os dados deste aparelho pelos do backup.
  /// Exige reconfirmacao da senha do administrador. Antes, cria uma copia
  /// automatica do banco atual. O banco novo e montado a parte, verificado
  /// e so entao colocado no lugar do atual.
  Future<void> restoreReplaceAll(Session s, BackupContents c, String adminPassword) async {
    s.require(Permission.backupRestore);
    if (!await lib.auth.confirmPassword(s, adminPassword)) {
      throw AppException('Senha do administrador incorreta.');
    }
    if (lib.dataDir == null) throw AppException('Restauração indisponível neste modo.');
    final hasHost = c.tables['users']!.any((u) => u['role_id'] == 'host' && u['status'] == 'active');
    if (!hasHost) throw AppException('O backup não contém nenhum administrador ativo.');

    await lib.autoSnapshot('pre-restauracao');
    await importInto(c);
    await lib.audit.log(null, 'backup.restore', 'backup_history', null,
        actorId: s.userId,
        actorName: s.name,
        details: 'Backup de ${brDateTimeMs(c.header['created_at'] as int)} (${c.school}), origem ${c.sourceInstallation}');
    await lib.db.insertMap('backup_history', {
      'id': newId(),
      'kind': 'restore',
      'file_name': null,
      'size_bytes': null,
      'encrypted': c.encrypted ? 1 : 0,
      'by_user': s.userId,
      'at': AppClock.nowMs(),
    });
    s.close();
  }

  /// Monta um banco novo com o conteudo e o coloca no lugar do atual.
  /// Usado tambem pela tela de recuperacao (banco danificado / chave perdida).
  Future<void> importInto(BackupContents c) async {
    final (scratch, tmpPath) = await lib.createScratchDatabase();
    try {
      await scratch.transaction(() async {
        final currentInstallation = await lib.installationId();
        for (final t in backupTables) {
          final rows = c.tables[t];
          if (rows == null || rows.isEmpty) continue;
          final info = await scratch.q('PRAGMA table_info($t)');
          final cols = info.map((r) => r['name'] as String).toSet();
          for (final r in rows) {
            if (t == 'app_meta' && _deviceMetaKeys.contains(r['key'])) continue;
            final row = <String, Object?>{
              for (final e in r.entries)
                if (cols.contains(e.key)) e.key: e.value,
            };
            await scratch.insertMap(t, row);
          }
        }
        if (currentInstallation.isNotEmpty) {
          await scratch.x(
              "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('installation_id', ?)", [currentInstallation]);
        }
      });
      final problem = await scratch.integrityProblem();
      if (problem != null) throw AppException('O banco reconstruído falhou na verificação: $problem');
      final fk = await scratch.q('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) throw AppException('O backup tem referências inválidas (${fk.length}).');
      await scratch.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e) {
      await scratch.close();
      for (final ext in ['', '-wal', '-shm']) {
        final f = File('$tmpPath$ext');
        if (await f.exists()) await f.delete();
      }
      rethrow;
    }
    await scratch.close();
    for (final ext in ['-wal', '-shm']) {
      final f = File('$tmpPath$ext');
      if (await f.exists()) await f.delete();
    }
    await lib.swapDatabaseFile(tmpPath);

    final dir = lib.coversDir;
    if (dir != null) {
      await dir.create(recursive: true);
      for (final e in c.covers.entries) {
        await File(p.join(dir.path, p.basename(e.key))).writeAsBytes(base64Decode(e.value), flush: true);
      }
    }
    await lib.catalog.rebuildIndex();
  }

  Future<List<Map<String, Object?>>> history(Session s) async {
    s.require(Permission.backupCreate);
    return lib.db.q(
        'SELECT h.*, u.name AS user_name FROM backup_history h LEFT JOIN users u ON u.id = h.by_user ORDER BY h.at DESC LIMIT 50');
  }

  Future<int?> lastBackupAt() async =>
      toInt((await lib.db.q1("SELECT max(at) AS at FROM backup_history WHERE kind = 'manual'"))?['at']);
}
