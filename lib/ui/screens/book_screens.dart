import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../security/permissions.dart';
import '../../services/catalog_service.dart';
import '../../services/isbn_lookup.dart';
import '../app_state.dart';
import '../file_io.dart';
import '../scanner.dart';
import '../theme.dart';
import '../widgets.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.fileName, required this.title, this.width = 80});
  final String? fileName;
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final f = context.lib.catalog.coverFile(fileName);
    final h = width * 1.45;
    if (f != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(f, width: width, height: h, fit: BoxFit.cover, semanticLabel: 'Capa de $title'),
      );
    }
    final initials = title.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Brand.petrol, Brand.petrolDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(color: Brand.aquaSoft, fontSize: width * 0.3, fontWeight: FontWeight.w700)),
    );
  }
}

// -----------------------------------------------------------------------------

class BookDetailScreen extends StatelessWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final manage = s.can(Permission.catalogManage);
    final staff = s.can(Permission.circulationOperate);
    return AsyncView<(Map<String, Object?>?, List<Map<String, Object?>>, bool)>(
      load: () async {
        final b = await lib.catalog.getBook(s, bookId);
        final c = b == null ? <Map<String, Object?>>[] : await lib.catalog.copies(s, bookId);
        final fav = await lib.catalog.isFavorite(s, bookId);
        return (b, c, fav);
      },
      builder: (context, data, reload) {
        final (b, copies, fav) = data;
        if (b == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Livro não encontrado'));
        }
        final t = Theme.of(context);
        final archived = b['status'] == 'archived';
        final avail = b['available'] as int? ?? 0;
        return Scaffold(
          appBar: AppBar(
            title: Text(b['title'] as String),
            actions: [
              if (s.role == Role.user || s.can(Permission.favoritesManage))
                IconButton(
                  tooltip: fav ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
                  icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Brand.danger : null),
                  onPressed: () async {
                    await lib.catalog.toggleFavorite(s, bookId);
                    reload();
                  },
                ),
              if (manage)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    try {
                      switch (v) {
                        case 'edit':
                          await Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => BookFormScreen(bookId: bookId)));
                        case 'copies':
                          await addCopiesDialog(context, bookId);
                        case 'cover':
                          final img = await FileIO.pickImage();
                          if (img != null) {
                            await lib.catalog.setCover(s, bookId, img.bytes, img.name.split('.').last);
                          }
                        case 'archive':
                          if (await confirm(context, archived ? 'Reativar título?' : 'Arquivar título?',
                              archived ? 'O título volta a aparecer no catálogo.' : 'O título deixa de aparecer no catálogo, mas o histórico é mantido.')) {
                            await lib.catalog.setArchived(s, bookId, !archived);
                          }
                      }
                      if (context.mounted) context.appRead.dataChanged();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar livro')),
                    const PopupMenuItem(value: 'copies', child: Text('Adicionar exemplares')),
                    const PopupMenuItem(value: 'cover', child: Text('Trocar capa')),
                    PopupMenuItem(value: 'archive', child: Text(archived ? 'Reativar' : 'Arquivar')),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            PageBody(
              maxWidth: 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 20, runSpacing: 16, children: [
                  BookCover(fileName: b['cover_file'] as String?, title: b['title'] as String, width: 140),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b['title'] as String, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (b['subtitle'] != null) Text(b['subtitle'] as String, style: t.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(b['authors'] as String? ?? 'Autor não informado', style: t.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (archived) StatusPill('Arquivado', color: t.colorScheme.outline),
                        StatusPill(avail > 0 ? '$avail disponível(is)' : 'Indisponível no momento',
                            color: avail > 0 ? Brand.ok : Brand.warn),
                        StatusPill('${b['total']} exemplar(es)', color: t.colorScheme.primary),
                        if ((b['loaned'] as int? ?? 0) > 0) StatusPill('${b['loaned']} emprestado(s)', color: Brand.aqua),
                        if (toBool(b['restricted'])) StatusPill('Empréstimo restrito', color: t.colorScheme.error),
                      ]),
                      const SizedBox(height: 12),
                      if (b['description'] != null) Text(b['description'] as String),
                    ]),
                  ),
                ]),
                const SectionTitle('Informações'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      InfoRow('ISBN', b['isbn'] as String?),
                      InfoRow('Editora', b['publisher'] as String?),
                      InfoRow('Ano', b['year']?.toString()),
                      InfoRow('Categoria', b['category'] as String?),
                      InfoRow('Gênero', b['genre'] as String?),
                      InfoRow('Idioma', b['language'] as String?),
                      InfoRow('Páginas', b['pages']?.toString()),
                      InfoRow('Localização', b['location'] as String?),
                      if (staff) ...[
                        InfoRow('Prazo do título', b['loan_days'] == null ? 'padrão da biblioteca' : '${b['loan_days']} dias'),
                        InfoRow('Renovação', toBool(b['allow_renewal']) ? 'permitida (máx. ${b['max_renewals']})' : 'não permitida'),
                        InfoRow('Reserva', toBool(b['allow_reservation']) ? 'permitida' : 'não permitida'),
                        if (toBool(b['restricted'])) InfoRow('Restrição', b['restriction_note'] as String? ?? 'sim'),
                        InfoRow('Cadastrado em', brDateTimeMs(b['created_at'] as int?)),
                      ],
                    ]),
                  ),
                ),
                SectionTitle('Exemplares (${copies.length})'),
                if (copies.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhum exemplar cadastrado.')))
                else
                  Card(
                    child: Column(children: [
                      for (final c in copies) _CopyTile(copy: c, staff: staff, manage: manage),
                    ]),
                  ),
                if (staff) ...[
                  const SectionTitle('Histórico de empréstimos'),
                  AsyncView<List<Map<String, Object?>>>(
                    load: () => lib.circulation.loanHistoryForBook(s, bookId),
                    builder: (context, rows, _) => Card(
                      child: rows.isEmpty
                          ? const Padding(padding: EdgeInsets.all(16), child: Text('Este título ainda não foi emprestado.'))
                          : Column(children: [
                              for (final l in rows.take(30))
                                ListTile(
                                  dense: true,
                                  title: Text('${l['user_name']} · tombo ${l['accession_number']}'),
                                  subtitle: Text('${brDateIso(l['loan_date'] as String)} → '
                                      '${l['status'] == 'returned' ? 'devolvido ${brDateIso(l['return_date'] as String?)}' : (l['status'] == 'active' ? 'previsto ${brDateIso(l['due_date'] as String)}' : 'cancelado')}'),
                                ),
                            ]),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _CopyTile extends StatelessWidget {
  const _CopyTile({required this.copy, required this.staff, required this.manage});
  final Map<String, Object?> copy;
  final bool staff;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = copy['status'] as String;
    final color = switch (status) {
      'available' => Brand.ok,
      'loaned' => Brand.aqua,
      'reference' => t.colorScheme.primary,
      _ => Brand.warn,
    };
    String? sub;
    if (staff && status == 'loaned' && copy['borrower_name'] != null) {
      final left = daysBetween(AppClock.today(), parseIsoDate(copy['due_date'] as String));
      sub = 'Com ${copy['borrower_name']} desde ${brDateIso(copy['loan_date'] as String)} · '
          'devolução ${brDateIso(copy['due_date'] as String)} (${daysLeftLabel(left)})';
    } else if (staff) {
      sub = 'Estado: ${conditionLabels[copy['condition']] ?? copy['condition'] ?? '—'}'
          '${copy['acquisition'] != null ? ' · ${copy['acquisition']}' : ''}';
    }
    return ListTile(
      leading: const Icon(Icons.qr_code_2),
      title: Text('Tombo ${copy['accession_number']}'),
      subtitle: sub == null ? null : Text(sub),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StatusPill(copyStatusLabels[status] ?? status, color: color),
        if (manage && status != 'loaned')
          IconButton(
            tooltip: 'Alterar situação',
            icon: const Icon(Icons.more_vert),
            onPressed: () => copyStatusDialog(context, copy),
          ),
      ]),
    );
  }
}

Future<void> addCopiesDialog(BuildContext context, String bookId) async {
  final n = TextEditingController(text: '1');
  final acq = TextEditingController();
  String cond = 'bom';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Adicionar exemplares'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: cond,
            decoration: const InputDecoration(labelText: 'Estado'),
            items: [for (final e in conditionLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => cond = v ?? 'bom'),
          ),
          const SizedBox(height: 12),
          TextField(controller: acq, decoration: const InputDecoration(labelText: 'Origem (compra, doação de…, PNLD)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Adicionar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final r = await context.lib.catalog
        .addCopies(context.session, bookId, int.tryParse(n.text) ?? 0, condition: cond, acquisition: acq.text);
    if (!context.mounted) return;
    showInfo(context, r.length == 1 ? 'Exemplar criado: tombo ${r.first}.' : 'Criados os tombos ${r.first} a ${r.last}.');
    context.appRead.dataChanged();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<void> copyStatusDialog(BuildContext context, Map<String, Object?> copy) async {
  String status = copy['status'] as String;
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('Tombo ${copy['accession_number']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(labelText: 'Situação'),
            items: [
              for (final e in copyStatusLabels.entries)
                if (e.key != 'loaned') DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => set(() => status = v ?? status),
          ),
          const SizedBox(height: 12),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Motivo / observação')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await context.lib.catalog.setCopyStatus(context.session, copy['id'] as String, status, reason: reason.text);
    if (context.mounted) context.appRead.dataChanged();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

// -----------------------------------------------------------------------------

/// Cadastro/edicao de livro, com leitura de ISBN, preenchimento automatico
/// (quando ha internet), deteccao de duplicidade e regras de prazo do titulo.
class BookFormScreen extends StatefulWidget {
  const BookFormScreen({super.key, this.bookId});
  final String? bookId;
  @override
  State<BookFormScreen> createState() => _BookFormScreenState();
}

class _BookFormScreenState extends State<BookFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{
    for (final k in [
      'title', 'subtitle', 'isbn', 'authors', 'publisher', 'category', 'year', 'genre', 'language',
      'pages', 'description', 'location', 'loan_days', 'max_renewals', 'restriction_note', 'copies', 'acquisition',
    ])
      k: TextEditingController(),
  };
  bool _allowRenewal = true;
  bool _allowReservation = true;
  bool _restricted = false;
  bool _customDays = false;
  bool _busy = false;
  bool _loading = true;
  bool _lookingUp = false;
  int _defaultDays = 14;
  Uint8List? _coverBytes;
  String _coverExt = 'jpg';
  String? _lookupNote;

  bool get _editing => widget.bookId != null;

  @override
  void initState() {
    super.initState();
    _c['copies']!.text = '1';
    _c['max_renewals']!.text = '1';
    _c['language']!.text = 'Português';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final lib = context.lib;
    final settings = await lib.settings.load();
    _defaultDays = settings.defaultLoanDays;
    if (_editing) {
      final b = await lib.catalog.getBook(context.session, widget.bookId!);
      if (b != null) {
        for (final k in ['title', 'subtitle', 'isbn', 'publisher', 'category', 'genre', 'language', 'description', 'location', 'restriction_note']) {
          _c[k]!.text = (b[k] as String?) ?? '';
        }
        _c['year']!.text = b['year']?.toString() ?? '';
        _c['pages']!.text = b['pages']?.toString() ?? '';
        _c['authors']!.text =
            (b['author_list'] as List).map((a) => (a as Map)['name'] as String).join('; ');
        _customDays = b['loan_days'] != null;
        _c['loan_days']!.text = (b['loan_days'] ?? _defaultDays).toString();
        _c['max_renewals']!.text = (b['max_renewals'] ?? 1).toString();
        _allowRenewal = toBool(b['allow_renewal']);
        _allowReservation = toBool(b['allow_reservation']);
        _restricted = toBool(b['restricted']);
      }
    } else {
      _c['loan_days']!.text = '$_defaultDays';
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _int(String k) => int.tryParse(_c[k]!.text.trim());

  BookInput _input() => BookInput(
        title: _c['title']!.text,
        subtitle: _c['subtitle']!.text,
        isbn: _c['isbn']!.text,
        authors: _c['authors']!.text.split(RegExp(r'[;\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        publisher: _c['publisher']!.text,
        category: _c['category']!.text,
        year: _int('year'),
        genre: _c['genre']!.text,
        language: _c['language']!.text,
        pages: _int('pages'),
        description: _c['description']!.text,
        location: _c['location']!.text,
        loanDays: _customDays ? _int('loan_days') : null,
        allowRenewal: _allowRenewal,
        maxRenewals: _int('max_renewals') ?? 0,
        allowReservation: _allowReservation,
        restricted: _restricted,
        restrictionNote: _c['restriction_note']!.text,
      );

  Future<void> _lookup() async {
    final isbn = cleanIsbn(_c['isbn']!.text);
    if (isbn == null) {
      showError(context, 'Digite ou leia um ISBN válido primeiro.');
      return;
    }
    if (await _checkDuplicate()) return;
    setState(() {
      _lookingUp = true;
      _lookupNote = null;
    });
    final sug = await IsbnLookup.lookup(isbn);
    if (!mounted) return;
    if (sug == null) {
      setState(() {
        _lookingUp = false;
        _lookupNote = 'Sem resultado (ou sem internet). Preencha manualmente.';
      });
      return;
    }
    void fill(String k, String? v) {
      if (v != null && v.trim().isNotEmpty && _c[k]!.text.trim().isEmpty) _c[k]!.text = v.trim();
    }

    fill('title', sug.title);
    fill('subtitle', sug.subtitle);
    fill('authors', sug.authors.join('; '));
    fill('publisher', sug.publisher);
    fill('year', sug.year?.toString());
    fill('pages', sug.pages?.toString());
    fill('description', sug.description);
    fill('category', sug.category);
    if (sug.language != null) _c['language']!.text = sug.language!;
    if (sug.coverUrl != null && _coverBytes == null) {
      final img = await IsbnLookup.downloadCover(sug.coverUrl!);
      if (img != null) {
        _coverBytes = Uint8List.fromList(img);
        _coverExt = 'jpg';
      }
    }
    if (!mounted) return;
    setState(() {
      _lookingUp = false;
      _lookupNote = 'Dados sugeridos por ${sug.source}. Revise antes de salvar.';
    });
  }

  /// Retorna true se o usuario escolheu adicionar exemplar ao titulo existente.
  Future<bool> _checkDuplicate() async {
    final dups = await context.lib.catalog.findDuplicates(context.session,
        isbn: _c['isbn']!.text, title: _c['title']!.text, excludeId: widget.bookId);
    if (dups.isEmpty || !mounted) return false;
    final d = dups.first;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Este título já está cadastrado'),
        content: Text('"${d['title']}" (${d['authors'] ?? 'autor não informado'}) já existe com ${d['total']} exemplar(es). '
            'Deseja adicionar um novo exemplar a ele em vez de criar outro título?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'continue'), child: const Text('Criar outro título')),
          FilledButton(onPressed: () => Navigator.pop(c, 'copy'), child: const Text('Adicionar exemplar')),
        ],
      ),
    );
    if (choice == 'copy' && mounted) {
      await addCopiesDialog(context, d['id'] as String);
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: d['id'] as String)));
      }
      return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final lib = context.lib;
    final s = context.session;
    if (!_editing && await _checkDuplicate()) return;
    setState(() => _busy = true);
    try {
      String id;
      if (_editing) {
        id = widget.bookId!;
        await lib.catalog.updateBook(s, id, _input());
      } else {
        id = await lib.catalog.createBook(s, _input(), copies: _int('copies') ?? 0, acquisition: _c['acquisition']!.text);
      }
      if (_coverBytes != null) await lib.catalog.setCover(s, id, _coverBytes!, _coverExt);
      if (!mounted) return;
      context.appRead.dataChanged();
      showInfo(context, _editing ? 'Livro atualizado.' : 'Livro cadastrado.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _f(String k, String label, {String? helper, TextInputType? kb, int lines = 1, String? Function(String?)? v, Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[k],
          keyboardType: kb,
          maxLines: lines,
          validator: v,
          decoration: InputDecoration(labelText: label, helperText: helper, suffixIcon: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar livro' : 'Novo livro')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                PageBody(
                  maxWidth: 820,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('Identificação', style: t.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _c['isbn'],
                            decoration: InputDecoration(
                              labelText: 'ISBN',
                              helperText: 'Leitor USB: clique aqui e leia o código de barras do livro',
                              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                                ScanButton(onCode: (c) {
                                  _c['isbn']!.text = c;
                                  _lookup();
                                }),
                                IconButton(
                                  tooltip: 'Buscar dados pelo ISBN (requer internet)',
                                  icon: _lookingUp
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.travel_explore),
                                  onPressed: _lookingUp ? null : _lookup,
                                ),
                              ]),
                            ),
                            onFieldSubmitted: (_) => _lookup(),
                            validator: (v) => (v ?? '').trim().isEmpty || cleanIsbn(v) != null ? null : 'ISBN inválido',
                          ),
                          if (_lookupNote != null)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text(_lookupNote!, style: t.textTheme.bodySmall)),
                          const SizedBox(height: 12),
                          _f('title', 'Título *', v: (v) => (v ?? '').trim().isEmpty ? 'Obrigatório' : null),
                          _f('subtitle', 'Subtítulo'),
                          _f('authors', 'Autor(es)', helper: 'Separe vários autores com ponto e vírgula (;)'),
                          _f('publisher', 'Editora'),
                          Row(children: [
                            Expanded(child: _f('year', 'Ano', kb: TextInputType.number)),
                            const SizedBox(width: 12),
                            Expanded(child: _f('pages', 'Páginas', kb: TextInputType.number)),
                          ]),
                          Row(children: [
                            Expanded(child: _f('category', 'Categoria')),
                            const SizedBox(width: 12),
                            Expanded(child: _f('genre', 'Gênero')),
                          ]),
                          Row(children: [
                            Expanded(child: _f('language', 'Idioma')),
                            const SizedBox(width: 12),
                            Expanded(child: _f('location', 'Localização física', helper: 'Ex.: Estante 3, prateleira B')),
                          ]),
                          _f('description', 'Descrição / sinopse', lines: 4),
                          Row(children: [
                            if (_coverBytes != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.memory(_coverBytes!, width: 56, height: 80, fit: BoxFit.cover),
                              ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.image_outlined),
                              label: Text(_coverBytes == null ? 'Escolher capa' : 'Trocar capa'),
                              onPressed: () async {
                                final img = await FileIO.pickImage();
                                if (img != null) {
                                  setState(() {
                                    _coverBytes = img.bytes;
                                    _coverExt = img.name.split('.').last;
                                  });
                                }
                              },
                            ),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('Regras de empréstimo deste título', style: t.textTheme.titleMedium),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _customDays,
                            onChanged: (v) => setState(() => _customDays = v),
                            title: const Text('Prazo próprio para este título'),
                            subtitle: Text(_customDays ? 'Usará o prazo abaixo' : 'Usa o prazo padrão da biblioteca ($_defaultDays dias)'),
                          ),
                          if (_customDays)
                            _f('loan_days', 'Prazo padrão de empréstimo (dias)', kb: TextInputType.number, v: (v) {
                              final n = int.tryParse(v ?? '');
                              return n == null || n < 1 || n > 365 ? 'Entre 1 e 365' : null;
                            }),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _allowRenewal,
                            onChanged: (v) => setState(() => _allowRenewal = v),
                            title: const Text('Permite renovação'),
                          ),
                          if (_allowRenewal) _f('max_renewals', 'Máximo de renovações', kb: TextInputType.number),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _allowReservation,
                            onChanged: (v) => setState(() => _allowReservation = v),
                            title: const Text('Permite reserva'),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _restricted,
                            onChanged: (v) => setState(() => _restricted = v),
                            title: const Text('Possui restrição de empréstimo'),
                            subtitle: const Text('Exige liberação justificada por um administrador'),
                          ),
                          if (_restricted) _f('restriction_note', 'Descrição da restrição'),
                        ]),
                      ),
                    ),
                    if (!_editing) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text('Exemplares', style: t.textTheme.titleMedium),
                            const SizedBox(height: 12),
                            _f('copies', 'Quantidade de exemplares', kb: TextInputType.number,
                                helper: 'Cada exemplar recebe um número de tombo único'),
                            _f('acquisition', 'Origem (compra, doação, PNLD…)'),
                          ]),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_editing ? 'Salvar alterações' : 'Cadastrar livro'),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ]),
            ),
    );
  }
}
