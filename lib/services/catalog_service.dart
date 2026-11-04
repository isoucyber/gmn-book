import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../core/util.dart';
import '../library.dart';
import '../security/permissions.dart';

class BookInput {
  final String title;
  final String? subtitle;
  final String? isbn;
  final List<String> authors;
  final String? publisher;
  final String? category;
  final int? year;
  final String? genre;
  final String? language;
  final int? pages;
  final String? description;
  final String? location;
  final int? loanDays;
  final bool allowRenewal;
  final int maxRenewals;
  final bool allowReservation;
  final bool restricted;
  final String? restrictionNote;

  BookInput({
    required this.title,
    this.subtitle,
    this.isbn,
    this.authors = const [],
    this.publisher,
    this.category,
    this.year,
    this.genre,
    this.language,
    this.pages,
    this.description,
    this.location,
    this.loanDays,
    this.allowRenewal = true,
    this.maxRenewals = 1,
    this.allowReservation = true,
    this.restricted = false,
    this.restrictionNote,
  });
}

enum Availability { all, available, loaned }

const copyStatusLabels = {
  'available': 'Disponível',
  'loaned': 'Emprestado',
  'reserved': 'Reservado (aguardando retirada)',
  'maintenance': 'Em manutenção/restauro',
  'lost': 'Extraviado',
  'damaged': 'Danificado',
  'withdrawn': 'Baixado (descartado)',
  'reference': 'Uso local (só consulta)',
};

const conditionLabels = {'bom': 'Bom', 'regular': 'Regular', 'danificado': 'Danificado'};

class CatalogService {
  final Library lib;
  CatalogService(this.lib);

  static const _summarySelect = '''
SELECT b.id, b.title, b.subtitle, b.isbn, b.year, b.genre, b.language, b.pages, b.cover_file,
       b.status, b.location, b.loan_days, b.created_at,
       p.name AS publisher, c.name AS category, c.id AS category_id,
       (SELECT group_concat(a.name, ', ') FROM book_authors ba JOIN authors a ON a.id = ba.author_id
          WHERE ba.book_id = b.id) AS authors,
       (SELECT count(*) FROM book_copies bc WHERE bc.book_id = b.id AND bc.deleted_at IS NULL
          AND bc.status <> 'withdrawn') AS total,
       (SELECT count(*) FROM book_copies bc WHERE bc.book_id = b.id AND bc.deleted_at IS NULL
          AND bc.status = 'available') AS available,
       (SELECT count(*) FROM book_copies bc WHERE bc.book_id = b.id AND bc.status = 'loaned') AS loaned,
       (SELECT count(*) FROM book_copies bc WHERE bc.book_id = b.id AND bc.status = 'reference') AS reference_only
FROM books b
LEFT JOIN publishers p ON p.id = b.publisher_id
LEFT JOIN categories c ON c.id = b.category_id
''';

  // ---------------------------------------------------------------------------
  // Consulta

  Future<List<Map<String, Object?>>> search(
    Session s, {
    String query = '',
    Availability availability = Availability.all,
    String? categoryId,
    String? authorId,
    bool includeArchived = false,
    int limit = 200,
  }) async {
    s.require(Permission.catalogView);
    if (includeArchived) s.require(Permission.catalogManage);
    final where = <String>['b.deleted_at IS NULL'];
    final args = <Object?>[];
    if (!includeArchived) where.add("b.status = 'active'");
    if (categoryId != null) {
      where.add('b.category_id = ?');
      args.add(categoryId);
    }
    if (authorId != null) {
      where.add('EXISTS (SELECT 1 FROM book_authors ba WHERE ba.book_id = b.id AND ba.author_id = ?)');
      args.add(authorId);
    }
    switch (availability) {
      case Availability.available:
        where.add("EXISTS (SELECT 1 FROM book_copies bc WHERE bc.book_id = b.id AND bc.status = 'available' AND bc.deleted_at IS NULL)");
      case Availability.loaned:
        where.add("EXISTS (SELECT 1 FROM book_copies bc WHERE bc.book_id = b.id AND bc.status = 'loaned')");
      case Availability.all:
        break;
    }

    final q = query.trim();
    if (q.isEmpty) {
      return lib.db.q('$_summarySelect WHERE ${where.join(' AND ')} ORDER BY b.title COLLATE NOCASE LIMIT ?',
          [...args, limit]);
    }

    final ids = await _matchIds(q, limit);
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await lib.db.q(
        '$_summarySelect WHERE ${where.join(' AND ')} AND b.id IN ($placeholders)', [...args, ...ids]);
    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    rows.sort((a, b) => order[a['id']]!.compareTo(order[b['id']]!));
    return rows;
  }

  /// Busca por FTS5 (rapida) complementada por correspondencia tolerante a
  /// acentos e pequenos erros ("machado de assiz" encontra Machado de Assis).
  Future<List<String>> _matchIds(String q, int limit) async {
    final result = <String>[];
    final seen = <String>{};
    final isbn = q.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (isbn.length >= 10) {
      for (final r in await lib.db.q('SELECT id FROM books WHERE isbn = ?', [isbn.toUpperCase()])) {
        if (seen.add(r['id'] as String)) result.add(r['id'] as String);
      }
    }
    final toks = tokens(q);
    if (lib.db.ftsAvailable && toks.isNotEmpty) {
      final match = toks.map((t) => '"$t"*').join(' ');
      try {
        final rows = await lib.db.q(
            'SELECT book_id FROM books_fts WHERE books_fts MATCH ? ORDER BY rank LIMIT ?', [match, limit]);
        for (final r in rows) {
          if (seen.add(r['book_id'] as String)) result.add(r['book_id'] as String);
        }
      } catch (_) {/* consulta FTS invalida: segue com a busca tolerante */}
    }
    if (result.length < 30) {
      final all = await lib.db.q('SELECT id, search_text FROM books WHERE deleted_at IS NULL');
      for (final r in all) {
        if (result.length >= limit) break;
        final id = r['id'] as String;
        if (seen.contains(id)) continue;
        if (fuzzyMatch(q, r['search_text'] as String? ?? '')) {
          seen.add(id);
          result.add(id);
        }
      }
    }
    return result.take(limit).toList();
  }

  Future<Map<String, Object?>?> getBook(Session s, String id) async {
    s.require(Permission.catalogView);
    final b = await lib.db.q1('$_summarySelect WHERE b.id = ?', [id]);
    if (b == null) return null;
    if (b['status'] == 'archived' && !s.can(Permission.catalogManage)) return null;
    final full = await lib.db.q1('SELECT * FROM books WHERE id = ?', [id]);
    final authors = await lib.db.q(
        'SELECT a.id, a.name, ba.role FROM book_authors ba JOIN authors a ON a.id = ba.author_id '
        'WHERE ba.book_id = ? ORDER BY ba.position',
        [id]);
    return {...full!, ...b, 'author_list': authors};
  }

  Future<List<Map<String, Object?>>> copies(Session s, String bookId) async {
    s.require(Permission.catalogView);
    if (s.can(Permission.circulationOperate)) {
      return lib.db.q(
          'SELECT bc.*, l.due_date, l.loan_date, u.name AS borrower_name, u.id AS borrower_id, l.id AS loan_id '
          'FROM book_copies bc '
          "LEFT JOIN loans l ON l.copy_id = bc.id AND l.status = 'active' "
          'LEFT JOIN users u ON u.id = l.user_id '
          'WHERE bc.book_id = ? AND bc.deleted_at IS NULL ORDER BY bc.accession_number',
          [bookId]);
    }
    // Leitor: apenas situacao e localizacao, sem dados de outros usuarios.
    return lib.db.q(
        'SELECT id, accession_number, status FROM book_copies WHERE book_id = ? AND deleted_at IS NULL '
        "AND status <> 'withdrawn' ORDER BY accession_number",
        [bookId]);
  }

  Future<List<Map<String, Object?>>> categories() => lib.db.q(
      'SELECT c.id, c.name, (SELECT count(*) FROM books b WHERE b.category_id = c.id AND b.status = \'active\') AS books '
      'FROM categories c WHERE c.deleted_at IS NULL ORDER BY c.name COLLATE NOCASE');

  Future<List<Map<String, Object?>>> authors({String? search}) {
    if (search != null && search.trim().isNotEmpty) {
      return lib.db.q('SELECT id, name FROM authors WHERE name_norm LIKE ? ORDER BY name LIMIT 50',
          ['%${normalize(search)}%']);
    }
    return lib.db.q('SELECT id, name FROM authors ORDER BY name COLLATE NOCASE LIMIT 500');
  }

  Future<List<String>> publisherNames() async =>
      (await lib.db.q('SELECT name FROM publishers ORDER BY name COLLATE NOCASE'))
          .map((r) => r['name'] as String)
          .toList();

  /// Detecta titulos ja cadastrados com o mesmo ISBN ou titulo.
  Future<List<Map<String, Object?>>> findDuplicates(Session s,
      {String? isbn, String? title, String? excludeId}) async {
    s.require(Permission.catalogView);
    final results = <Map<String, Object?>>[];
    final clean = isbn == null ? null : isbn.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
    if (clean != null && clean.isNotEmpty) {
      results.addAll(await lib.db.q(
          '$_summarySelect WHERE b.isbn = ? AND b.deleted_at IS NULL AND b.id <> ?',
          [clean, excludeId ?? '']));
    }
    if (results.isEmpty && title != null && title.trim().isNotEmpty) {
      final norm = normalize(title);
      final rows = await lib.db.q('SELECT id, title FROM books WHERE deleted_at IS NULL AND id <> ?',
          [excludeId ?? '']);
      for (final r in rows) {
        if (normalize(r['title'] as String) == norm) {
          final b = await lib.db.q1('$_summarySelect WHERE b.id = ?', [r['id']]);
          if (b != null) results.add(b);
        }
      }
    }
    return results;
  }

  Future<Map<String, Object?>?> findCopyByCode(Session s, String code) async {
    s.require(Permission.catalogView);
    final c = code.trim();
    if (c.isEmpty) return null;
    final n = int.tryParse(c);
    return lib.db.q1(
        'SELECT bc.*, b.title, b.loan_days, b.restricted, b.restriction_note, b.status AS book_status '
        'FROM book_copies bc JOIN books b ON b.id = bc.book_id '
        'WHERE bc.deleted_at IS NULL AND (bc.barcode = ? OR bc.accession_number = ? OR bc.id = ?) LIMIT 1',
        [c, n ?? -1, c]);
  }

  // ---------------------------------------------------------------------------
  // Cadastro

  Future<String?> _findOrCreate(String table, String? name) async {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return null;
    final norm = normalize(n);
    final ex = await lib.db.q1('SELECT id FROM $table WHERE name_norm = ?', [norm]);
    if (ex != null) return ex['id'] as String;
    final id = newId();
    final now = AppClock.nowMs();
    await lib.db.insertMap(table, {
      'id': id,
      'name': n,
      'name_norm': norm,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  void _validate(BookInput d) {
    if (d.title.trim().isEmpty) throw ValidationException('Informe o título.');
    if (d.title.length > 300) throw ValidationException('Título longo demais.');
    if (d.isbn != null && d.isbn!.trim().isNotEmpty && cleanIsbn(d.isbn) == null) {
      throw ValidationException('ISBN inválido (verifique os dígitos).');
    }
    if (d.year != null && (d.year! < 0 || d.year! > AppClock.now().year + 1)) {
      throw ValidationException('Ano de publicação inválido.');
    }
    if (d.pages != null && (d.pages! < 0 || d.pages! > 100000)) {
      throw ValidationException('Número de páginas inválido.');
    }
    if (d.loanDays != null && (d.loanDays! < 1 || d.loanDays! > 365)) {
      throw ValidationException('O prazo do título deve estar entre 1 e 365 dias.');
    }
    if (d.maxRenewals < 0 || d.maxRenewals > 20) {
      throw ValidationException('Renovações devem estar entre 0 e 20.');
    }
  }

  Map<String, Object?> _bookCols(BookInput d, String? publisherId, String? categoryId) => {
        'title': d.title.trim(),
        'subtitle': _nn(d.subtitle),
        'isbn': (d.isbn == null || d.isbn!.trim().isEmpty) ? null : cleanIsbn(d.isbn),
        'publisher_id': publisherId,
        'category_id': categoryId,
        'year': d.year,
        'genre': _nn(d.genre),
        'language': _nn(d.language),
        'pages': d.pages,
        'description': _nn(d.description),
        'location': _nn(d.location),
        'loan_days': d.loanDays,
        'allow_renewal': d.allowRenewal ? 1 : 0,
        'max_renewals': d.maxRenewals,
        'allow_reservation': d.allowReservation ? 1 : 0,
        'restricted': d.restricted ? 1 : 0,
        'restriction_note': _nn(d.restrictionNote),
      };

  String? _nn(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<String> createBook(Session s, BookInput d, {int copies = 1, String? acquisition}) async {
    s.require(Permission.catalogManage);
    _validate(d);
    if (copies < 0 || copies > 500) throw ValidationException('Quantidade de exemplares inválida.');
    final id = newId();
    await lib.db.transaction(() async {
      final pub = await _findOrCreate('publishers', d.publisher);
      final cat = await _findOrCreate('categories', d.category);
      final now = AppClock.nowMs();
      await lib.db.insertMap('books', {
        'id': id,
        ..._bookCols(d, pub, cat),
        'status': 'active',
        'created_by': s.userId,
        'created_at': now,
        'updated_at': now,
      });
      await _setAuthors(id, d.authors);
      await _reindex(id);
      if (copies > 0) await _addCopies(s, id, copies, acquisition: acquisition);
      await lib.audit.log(s, 'book.create', 'books', id,
          newValue: {'title': d.title.trim(), 'isbn': d.isbn, 'copies': copies});
    });
    return id;
  }

  Future<void> updateBook(Session s, String id, BookInput d) async {
    s.require(Permission.catalogManage);
    _validate(d);
    final old = await lib.db.q1('SELECT * FROM books WHERE id = ?', [id]);
    if (old == null) throw AppException('Livro não encontrado.');
    await lib.db.transaction(() async {
      final pub = await _findOrCreate('publishers', d.publisher);
      final cat = await _findOrCreate('categories', d.category);
      final cols = _bookCols(d, pub, cat);
      final keys = cols.keys.toList();
      await lib.db.x('UPDATE books SET ${keys.map((k) => '$k = ?').join(', ')}, updated_at = ? WHERE id = ?',
          [...keys.map((k) => cols[k]), AppClock.nowMs(), id]);
      await _setAuthors(id, d.authors);
      await _reindex(id);
      await lib.audit.log(s, 'book.update', 'books', id,
          oldValue: {for (final k in keys) k: old[k]}, newValue: cols);
    });
  }

  Future<void> _setAuthors(String bookId, List<String> names) async {
    await lib.db.x('DELETE FROM book_authors WHERE book_id = ?', [bookId]);
    var pos = 0;
    final seen = <String>{};
    for (final n in names) {
      final aid = await _findOrCreate('authors', n);
      if (aid == null || !seen.add(aid)) continue;
      await lib.db.x('INSERT INTO book_authors (book_id, author_id, role, position) VALUES (?,?,?,?)',
          [bookId, aid, 'autor', pos++]);
    }
  }

  /// Atualiza o texto de busca normalizado e o indice FTS5 do titulo.
  Future<void> _reindex(String bookId) async {
    final b = await lib.db.q1(
        'SELECT b.title, b.subtitle, b.isbn, b.genre, p.name AS publisher, c.name AS category, '
        "(SELECT group_concat(a.name, ' ') FROM book_authors ba JOIN authors a ON a.id = ba.author_id WHERE ba.book_id = b.id) AS authors "
        'FROM books b LEFT JOIN publishers p ON p.id = b.publisher_id LEFT JOIN categories c ON c.id = b.category_id '
        'WHERE b.id = ?',
        [bookId]);
    if (b == null) return;
    final text = normalize([
      b['title'],
      b['subtitle'],
      b['authors'],
      b['isbn'],
      b['publisher'],
      b['category'],
      b['genre'],
    ].whereType<String>().join(' '));
    await lib.db.x('UPDATE books SET search_text = ? WHERE id = ?', [text, bookId]);
    if (lib.db.ftsAvailable) {
      await lib.db.x('DELETE FROM books_fts WHERE book_id = ?', [bookId]);
      await lib.db.x('INSERT INTO books_fts (book_id, content) VALUES (?, ?)', [bookId, text]);
    }
  }

  /// Reconstroi todo o indice (usado apos restaurar um backup).
  Future<void> rebuildIndex() async {
    final ids = await lib.db.q('SELECT id FROM books');
    await lib.db.transaction(() async {
      if (lib.db.ftsAvailable) await lib.db.x('DELETE FROM books_fts');
      for (final r in ids) {
        await _reindex(r['id'] as String);
      }
    });
  }

  Future<void> setArchived(Session s, String id, bool archived) async {
    s.require(Permission.catalogManage);
    if (archived) {
      final active = await lib.db.count(
          "SELECT count(*) FROM loans WHERE book_id = ? AND status = 'active'", [id]);
      if (active > 0) {
        throw AppException('Há $active exemplar(es) emprestado(s). Registre as devoluções antes de arquivar.');
      }
    }
    await lib.db.transaction(() async {
      await lib.db.x('UPDATE books SET status = ?, updated_at = ? WHERE id = ?',
          [archived ? 'archived' : 'active', AppClock.nowMs(), id]);
      await lib.audit.log(s, archived ? 'book.archive' : 'book.unarchive', 'books', id);
    });
  }

  Future<int> _nextAccession() async {
    final meta = await lib.db.q1("SELECT value FROM app_meta WHERE key = 'next_accession'");
    final maxRow = await lib.db.q1('SELECT max(accession_number) AS m FROM book_copies');
    final fromMeta = int.tryParse(meta?['value'] as String? ?? '') ?? 1;
    final fromMax = (toInt(maxRow?['m']) ?? 0) + 1;
    return fromMeta > fromMax ? fromMeta : fromMax;
  }

  Future<List<int>> _addCopies(Session s, String bookId, int n,
      {String condition = 'bom', String? acquisition}) async {
    final created = <int>[];
    var next = await _nextAccession();
    final now = AppClock.nowMs();
    for (var i = 0; i < n; i++) {
      final acc = next++;
      final id = newId();
      await lib.db.insertMap('book_copies', {
        'id': id,
        'book_id': bookId,
        'accession_number': acc,
        'barcode': acc.toString().padLeft(6, '0'),
        'status': 'available',
        'condition': condition,
        'acquisition': _nn(acquisition),
        'created_at': now,
        'updated_at': now,
      });
      await lib.db.insertMap('copy_status_history', {
        'id': newId(),
        'copy_id': id,
        'old_status': null,
        'new_status': 'available',
        'reason': 'cadastro',
        'by_user': s.userId,
        'at': now,
      });
      created.add(acc);
    }
    await lib.db.x(
        "INSERT INTO app_meta (key, value) VALUES ('next_accession', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        ['$next']);
    return created;
  }

  /// Adiciona exemplares a um titulo. Retorna os numeros de tombo gerados.
  Future<List<int>> addCopies(Session s, String bookId, int n,
      {String condition = 'bom', String? acquisition}) async {
    s.require(Permission.catalogManage);
    if (n < 1 || n > 500) throw ValidationException('Informe de 1 a 500 exemplares.');
    if (!conditionLabels.containsKey(condition)) throw ValidationException('Estado inválido.');
    final book = await lib.db.q1('SELECT id FROM books WHERE id = ?', [bookId]);
    if (book == null) throw AppException('Livro não encontrado.');
    late List<int> res;
    await lib.db.transaction(() async {
      res = await _addCopies(s, bookId, n, condition: condition, acquisition: acquisition);
      await lib.audit.log(s, 'copy.create', 'book_copies', bookId,
          details: 'tombos ${res.first}–${res.last}');
    });
    return res;
  }

  /// Muda a situacao de um exemplar (manutencao, extraviado, baixa, uso local...).
  Future<void> setCopyStatus(Session s, String copyId, String status,
      {String? reason, String? condition}) async {
    s.require(Permission.catalogManage);
    if (!copyStatusLabels.containsKey(status)) throw ValidationException('Situação inválida.');
    if (status == 'loaned') {
      throw ValidationException('Use o balcão de empréstimo para emprestar um exemplar.');
    }
    if (condition != null && !conditionLabels.containsKey(condition)) {
      throw ValidationException('Estado inválido.');
    }
    final c = await lib.db.q1('SELECT * FROM book_copies WHERE id = ?', [copyId]);
    if (c == null) throw AppException('Exemplar não encontrado.');
    if (c['status'] == 'loaned') {
      throw AppException('Este exemplar está emprestado. Registre a devolução primeiro.');
    }
    if (status == 'withdrawn' && (reason == null || reason.trim().isEmpty)) {
      throw ValidationException('Informe o motivo da baixa.');
    }
    await lib.db.transaction(() async {
      final now = AppClock.nowMs();
      await lib.db.x(
          'UPDATE book_copies SET status = ?, condition = coalesce(?, condition), updated_at = ? WHERE id = ?',
          [status, condition, now, copyId]);
      await lib.db.insertMap('copy_status_history', {
        'id': newId(),
        'copy_id': copyId,
        'old_status': c['status'],
        'new_status': status,
        'reason': _nn(reason),
        'by_user': s.userId,
        'at': now,
      });
      await lib.audit.log(s, 'copy.status', 'book_copies', copyId,
          oldValue: {'status': c['status']}, newValue: {'status': status}, details: reason);
    });
  }

  // ---------------------------------------------------------------------------
  // Capas (arquivos locais; o banco guarda so o nome, nunca caminho absoluto)

  static const maxCoverBytes = 3 * 1024 * 1024;

  Future<void> setCover(Session s, String bookId, Uint8List bytes, String extension) async {
    s.require(Permission.catalogManage);
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      throw ValidationException('Use uma imagem JPG, PNG ou WEBP.');
    }
    if (bytes.length > maxCoverBytes) {
      throw ValidationException('Imagem muito grande (máx. 3 MB). Reduza a foto antes de enviar.');
    }
    final dir = lib.coversDir;
    if (dir == null) return;
    await dir.create(recursive: true);
    final old = await lib.db.q1('SELECT cover_file FROM books WHERE id = ?', [bookId]);
    final name = '${bookId}_${AppClock.nowMs()}.$ext';
    await File(p.join(dir.path, name)).writeAsBytes(bytes, flush: true);
    await lib.db.x('UPDATE books SET cover_file = ?, updated_at = ? WHERE id = ?',
        [name, AppClock.nowMs(), bookId]);
    final oldName = old?['cover_file'] as String?;
    if (oldName != null) {
      final f = File(p.join(dir.path, oldName));
      if (await f.exists()) await f.delete();
    }
    await lib.audit.log(s, 'book.update', 'books', bookId, details: 'capa atualizada');
  }

  File? coverFile(String? name) {
    if (name == null || lib.coversDir == null) return null;
    final f = File(p.join(lib.coversDir!.path, p.basename(name)));
    return f.existsSync() ? f : null;
  }

  // ---------------------------------------------------------------------------
  // Favoritos (somente do proprio leitor)

  Future<bool> isFavorite(Session s, String bookId) async =>
      await lib.db.q1('SELECT 1 FROM favorites WHERE user_id = ? AND book_id = ?', [s.userId, bookId]) !=
      null;

  Future<bool> toggleFavorite(Session s, String bookId) async {
    s.require(Permission.favoritesManage);
    if (await isFavorite(s, bookId)) {
      await lib.db.x('DELETE FROM favorites WHERE user_id = ? AND book_id = ?', [s.userId, bookId]);
      return false;
    }
    await lib.db.x('INSERT INTO favorites (user_id, book_id, created_at) VALUES (?,?,?)',
        [s.userId, bookId, AppClock.nowMs()]);
    return true;
  }

  Future<List<Map<String, Object?>>> favorites(Session s) async {
    s.require(Permission.favoritesManage);
    return lib.db.q(
        "$_summarySelect JOIN favorites f ON f.book_id = b.id WHERE f.user_id = ? AND b.status = 'active' ORDER BY f.created_at DESC",
        [s.userId]);
  }
}
