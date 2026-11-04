import 'dart:async';

import 'package:flutter/material.dart';

import '../../security/permissions.dart';
import '../../services/catalog_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'book_screens.dart';

/// Catalogo digital com busca offline tolerante e filtros.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _q = TextEditingController();
  Timer? _t;
  String _query = '';
  Availability _avail = Availability.all;
  String? _category;
  bool _archived = false;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final manage = s.can(Permission.catalogManage);
    return PageScaffold(
      title: 'Catálogo',
      fab: manage
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Novo livro'),
              tooltip: 'Novo livro (Ctrl+N)',
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PageBody(
            child: Column(children: [
              TextField(
                controller: _q,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Título, autor, ISBN, editora, categoria ou gênero',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _q.clear();
                            _query = '';
                          }),
                        ),
                ),
                onChanged: (v) {
                  _t?.cancel();
                  _t = Timer(const Duration(milliseconds: 250), () => setState(() => _query = v));
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: lib.catalog.categories(),
                  builder: (context, snap) => ListView(scrollDirection: Axis.horizontal, children: [
                    for (final a in Availability.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(switch (a) {
                            Availability.all => 'Todos',
                            Availability.available => 'Disponíveis',
                            Availability.loaned => 'Emprestados',
                          }),
                          selected: _avail == a,
                          onSelected: (_) => setState(() => _avail = a),
                        ),
                      ),
                    const SizedBox(width: 8),
                    for (final c in snap.data ?? const <Map<String, Object?>>[])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('${c['name']}'),
                          selected: _category == c['id'],
                          onSelected: (v) => setState(() => _category = v ? c['id'] as String : null),
                        ),
                      ),
                    if (manage)
                      FilterChip(
                        label: const Text('Mostrar arquivados'),
                        selected: _archived,
                        onSelected: (v) => setState(() => _archived = v),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        Expanded(
          child: AsyncView<List<Map<String, Object?>>>(
            deps: '$_query|$_avail|$_category|$_archived',
            load: () => lib.catalog.search(s,
                query: _query, availability: _avail, categoryId: _category, includeArchived: _archived),
            builder: (context, rows, _) {
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: _query.isEmpty ? 'Nenhum livro aqui ainda' : 'Nenhum livro encontrado',
                  message: _query.isEmpty && manage ? 'Cadastre o primeiro título em "Novo livro".' : 'Tente outros termos ou filtros.',
                );
              }
              return LayoutBuilder(builder: (context, c) {
                final cols = (c.maxWidth / 360).floor().clamp(1, 4);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => BookCard(book: rows[i]),
                );
              });
            },
          ),
        ),
      ]),
    );
  }
}

class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book});
  final Map<String, Object?> book;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final avail = book['available'] as int? ?? 0;
    final total = book['total'] as int? ?? 0;
    final archived = book['status'] == 'archived';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: book['id'] as String))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            BookCover(fileName: book['cover_file'] as String?, title: book['title'] as String, width: 80),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book['title'] as String,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(book['authors'] as String? ?? 'Autor não informado',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                if (book['category'] != null)
                  Text(book['category'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                const Spacer(),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (archived)
                    StatusPill('Arquivado', color: t.colorScheme.outline)
                  else
                    StatusPill(
                      total == 0 ? 'Sem exemplares' : (avail > 0 ? '$avail de $total disponível(is)' : 'Todos emprestados'),
                      color: avail > 0 ? Brand.ok : Brand.warn,
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
