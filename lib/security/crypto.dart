import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Hash de senhas com Argon2id (recomendacao OWASP: m=19 MiB, t=2, p=1).
/// O formato guardado inclui os parametros, para permitir aumentar o custo
/// no futuro sem invalidar senhas antigas.
class PasswordHasher {
  /// Parametros usados para novos hashes. Os testes reduzem o custo.
  static int memoryKiB = 19456;
  static int iterations = 2;

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static Future<Uint8List> _argon2(String password, List<int> salt, int m, int t, int len) {
    final pw = utf8.encode(password);
    final s = List<int>.from(salt);
    return Isolate.run(() async {
      final algo = Argon2id(parallelism: 1, memory: m, iterations: t, hashLength: len);
      final key = await algo.deriveKey(secretKey: SecretKey(pw), nonce: s);
      return Uint8List.fromList(await key.extractBytes());
    });
  }

  static Future<String> hash(String password) async {
    final salt = randomBytes(16);
    final m = memoryKiB, t = iterations;
    final h = await _argon2(password, salt, m, t, 32);
    return 'argon2id\$m=$m,t=$t,p=1\$${base64Encode(salt)}\$${base64Encode(h)}';
  }

  static Future<bool> verify(String password, String stored) async {
    try {
      final parts = stored.split('\$');
      if (parts.length != 4 || parts[0] != 'argon2id') return false;
      final params = Map.fromEntries(parts[1].split(',').map((kv) {
        final p = kv.split('=');
        return MapEntry(p[0], int.parse(p[1]));
      }));
      final salt = base64Decode(parts[2]);
      final expected = base64Decode(parts[3]);
      final h = await _argon2(password, salt, params['m']!, params['t']!, expected.length);
      return constantTimeEquals(h, expected);
    } catch (_) {
      return false;
    }
  }

  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Deriva chave de 256 bits a partir de senha (usado nos backups).
  static Future<Uint8List> deriveKey(String password, List<int> salt, {int m = 19456, int t = 2}) =>
      _argon2(password, salt, m, t, 32);
}

/// Codigo de recuperacao no formato XXXX-XXXX-XXXX-XXXX (sem caracteres ambiguos).
String generateRecoveryCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  final groups = List.generate(
      4, (_) => List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join());
  return groups.join('-');
}

String normalizeRecoveryCode(String code) =>
    code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Criptografia autenticada AES-256-GCM.
class Aead {
  static final _algo = AesGcm.with256bits();

  static Future<({Uint8List nonce, Uint8List cipher, Uint8List mac})> encrypt(
      List<int> plain, List<int> key) async {
    final nonce = PasswordHasher.randomBytes(12);
    final box = await _algo.encrypt(plain, secretKey: SecretKey(key), nonce: nonce);
    return (
      nonce: nonce,
      cipher: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  /// Lanca SecretBoxAuthenticationError se a senha estiver errada ou o
  /// conteudo tiver sido alterado.
  static Future<Uint8List> decrypt(
      List<int> cipher, List<int> key, List<int> nonce, List<int> mac) async {
    final plain = await _algo.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key));
    return Uint8List.fromList(plain);
  }
}

Future<String> sha256Hex(List<int> data) async {
  final h = await Sha256().hash(data);
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
