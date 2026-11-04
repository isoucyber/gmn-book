import 'dart:math';

/// Gerador de UUID v4 com fonte criptograficamente segura.
/// UUIDs permitem mesclar backups de aparelhos diferentes sem colisao de IDs.
String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// Relogio substituivel: os testes usam [AppClock.override] para simular a
/// passagem dos dias e validar alertas de vencimento.
class AppClock {
  static DateTime Function() _now = DateTime.now;
  static DateTime now() => _now();
  static void override(DateTime Function() fn) => _now = fn;
  static void reset() => _now = DateTime.now;
  static int nowMs() => now().millisecondsSinceEpoch;
  static DateTime today() => dateOnly(now());
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Datas de calendario sao gravadas como texto ISO 'AAAA-MM-DD'.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Diferenca em dias de calendario (b - a), imune a horario de verao.
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

const _weekdays = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

String brDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String brDateIso(String? iso) => iso == null || iso.isEmpty ? '—' : brDate(parseIsoDate(iso));

String brDateTimeMs(int? ms) {
  if (ms == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${brDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// Texto amigavel para dias restantes.
String daysLeftLabel(int days) {
  if (days == 0) return 'vence hoje';
  if (days == 1) return 'falta 1 dia';
  if (days > 1) return 'faltam $days dias';
  if (days == -1) return '1 dia de atraso';
  return '${-days} dias de atraso';
}

const _accentMap = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Normaliza para busca: minusculas, sem acentos, so letras/numeros/espacos.
String normalize(String? s) {
  if (s == null) return '';
  final lower = s.toLowerCase();
  final sb = StringBuffer();
  for (final ch in lower.split('')) {
    final m = _accentMap[ch] ?? ch;
    if (RegExp(r'[a-z0-9]').hasMatch(m)) {
      sb.write(m);
    } else {
      sb.write(' ');
    }
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> tokens(String? s) =>
    normalize(s).split(' ').where((t) => t.isNotEmpty).toList();

/// Distancia de Levenshtein limitada (retorna max+1 se exceder).
int levenshtein(String a, String b, {int max = 2}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// Verifica se o termo digitado "casa" com o texto alvo tolerando acentos,
/// maiusculas, prefixos e pequenos erros de digitacao.
bool fuzzyMatch(String query, String targetNormalized) {
  final q = tokens(query);
  if (q.isEmpty) return true;
  final t = targetNormalized.split(' ');
  for (final qt in q) {
    final allowed = qt.length >= 8 ? 2 : (qt.length >= 4 ? 1 : 0);
    final ok = t.any((tt) =>
        tt.startsWith(qt) ||
        (allowed > 0 && levenshtein(qt, tt, max: allowed) <= allowed) ||
        (allowed > 0 && tt.length > qt.length &&
            levenshtein(qt, tt.substring(0, qt.length), max: allowed) <= allowed));
    if (!ok) return false;
  }
  return true;
}

/// Valida ISBN-10 ou ISBN-13 (digitos verificadores). Retorna versao limpa ou null.
String? cleanIsbn(String? raw) {
  if (raw == null) return null;
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  if (s.length == 13 && RegExp(r'^\d{13}$').hasMatch(s)) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(s[i]) * (i.isEven ? 1 : 3);
    }
    final check = (10 - sum % 10) % 10;
    return check == int.parse(s[12]) ? s : null;
  }
  if (s.length == 10 && RegExp(r'^\d{9}[\dX]$').hasMatch(s)) {
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(s[i]) * (10 - i);
    }
    final last = s[9] == 'X' ? 10 : int.parse(s[9]);
    sum += last;
    return sum % 11 == 0 ? s : null;
  }
  return null;
}

int? toInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool toBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
