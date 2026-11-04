import 'dart:convert';

import 'package:http/http.dart' as http;

/// Sugestao de dados bibliograficos (sempre editavel antes de salvar).
class IsbnSuggestion {
  final String source;
  final String? title;
  final String? subtitle;
  final List<String> authors;
  final String? publisher;
  final int? year;
  final int? pages;
  final String? description;
  final String? language;
  final String? category;
  final String? coverUrl;

  IsbnSuggestion({
    required this.source,
    this.title,
    this.subtitle,
    this.authors = const [],
    this.publisher,
    this.year,
    this.pages,
    this.description,
    this.language,
    this.category,
    this.coverUrl,
  });
}

/// Preenchimento automatico por ISBN em fontes publicas, quando ha internet.
/// Sem conexao, retorna null e o cadastro manual continua funcionando.
/// Nenhum dado de usuario e enviado: apenas o ISBN.
class IsbnLookup {
  static const _timeout = Duration(seconds: 8);

  static Future<IsbnSuggestion?> lookup(String isbn) async {
    final clean = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (clean.isEmpty) return null;
    final g = await _google(clean);
    if (g != null && g.title != null) return g;
    final o = await _openLibrary(clean);
    if (o != null && o.title != null) return o;
    return null;
  }

  static int? _year(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{4})').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static Future<IsbnSuggestion?> _google(String isbn) async {
    try {
      final r = await http
          .get(Uri.https('www.googleapis.com', '/books/v1/volumes', {'q': 'isbn:$isbn'}))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final items = data['items'] as List?;
      if (items == null || items.isEmpty) return null;
      final v = (items.first as Map)['volumeInfo'] as Map? ?? {};
      final images = v['imageLinks'] as Map?;
      return IsbnSuggestion(
        source: 'Google Books',
        title: v['title'] as String?,
        subtitle: v['subtitle'] as String?,
        authors: ((v['authors'] as List?) ?? []).map((e) => e.toString()).toList(),
        publisher: v['publisher'] as String?,
        year: _year(v['publishedDate'] as String?),
        pages: v['pageCount'] is int ? v['pageCount'] as int : null,
        description: v['description'] as String?,
        language: _lang(v['language'] as String?),
        category: ((v['categories'] as List?)?.isNotEmpty ?? false)
            ? (v['categories'] as List).first.toString()
            : null,
        coverUrl: (images?['thumbnail'] as String?)?.replaceFirst('http://', 'https://'),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<IsbnSuggestion?> _openLibrary(String isbn) async {
    try {
      final r = await http
          .get(Uri.https('openlibrary.org', '/api/books',
              {'bibkeys': 'ISBN:$isbn', 'format': 'json', 'jscmd': 'data'}))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final v = data['ISBN:$isbn'] as Map?;
      if (v == null) return null;
      final pubs = v['publishers'] as List?;
      final subjects = v['subjects'] as List?;
      final cover = v['cover'] as Map?;
      return IsbnSuggestion(
        source: 'Open Library',
        title: v['title'] as String?,
        subtitle: v['subtitle'] as String?,
        authors: ((v['authors'] as List?) ?? [])
            .map((a) => (a as Map)['name']?.toString())
            .whereType<String>()
            .toList(),
        publisher: pubs != null && pubs.isNotEmpty ? (pubs.first as Map)['name']?.toString() : null,
        year: _year(v['publish_date'] as String?),
        pages: v['number_of_pages'] is int ? v['number_of_pages'] as int : null,
        category: subjects != null && subjects.isNotEmpty ? (subjects.first as Map)['name']?.toString() : null,
        coverUrl: cover?['medium'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _lang(String? code) => switch (code) {
        null => null,
        'pt' || 'pt-BR' || 'pt-PT' => 'Português',
        'en' => 'Inglês',
        'es' => 'Espanhol',
        'fr' => 'Francês',
        'it' => 'Italiano',
        'de' => 'Alemão',
        _ => code,
      };

  /// Baixa a imagem de capa sugerida (opcional).
  static Future<List<int>?> downloadCover(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(_timeout);
      if (r.statusCode == 200 && r.bodyBytes.length < 3 * 1024 * 1024) return r.bodyBytes;
    } catch (_) {}
    return null;
  }
}
