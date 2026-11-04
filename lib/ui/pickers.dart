import 'dart:async';

import 'package:flutter/material.dart';

import '../security/permissions.dart';
import '../services/catalog_service.dart';
import 'app_state.dart';

/// Seleciona um usuario pelo nome, carteirinha, matricula ou turma.
Future<Map<String, Object?>?> pickUser(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _UserPicker());

class _UserPicker extends StatefulWidget {
  const _UserPicker();
  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  List<Map<String, Object?>> _rows = [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final r = await context.lib.users.list(context.session, search: q, status: 'active', limit: 50);
    if (mounted) setState(() => _rows = r);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Selecionar usuário'),
        content: SizedBox(
          width: 520,
          height: 440,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nome, carteirinha, matrícula ou turma'),
              onChanged: (v) {
                _t?.cancel();
                _t = Timer(const Duration(milliseconds: 200), () => _search(v));
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (_, i) {
                  final u = _rows[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text((u['name'] as String).substring(0, 1).toUpperCase())),
                    title: Text(u['name'] as String),
                    subtitle: Text([u['card_code'], u['class_name'], Role.fromId(u['role_id'] as String).label]
                        .whereType<String>()
                        .join(' · ')),
                    trailing: Text('${u['active_loans']} ativo(s)'),
                    onTap: () => Navigator.pop(context, u),
                  );
                },
              ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
}

/// Seleciona um exemplar disponivel a partir da busca no catalogo.
Future<Map<String, Object?>?> pickAvailableCopy(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _CopyPicker());

class _CopyPicker extends StatefulWidget {
  const _CopyPicker();
  @override
  State<_CopyPicker> createState() => _CopyPickerState();
}

class _CopyPickerState extends State<_CopyPicker> {
  List<Map<String, Object?>> _books = [];
  Map<String, Object?>? _book;
  List<Map<String, Object?>> _copies = [];
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final r = await context.lib.catalog.search(context.session, query: q, availability: Availability.available, limit: 50);
    if (mounted) setState(() => _books = r);
  }

  Future<void> _selectBook(Map<String, Object?> b) async {
    final c = await context.lib.catalog.copies(context.session, b['id'] as String);
    if (!mounted) return;
    final avail = c.where((x) => x['status'] == 'available').toList();
    if (avail.length == 1) {
      Navigator.pop(context, {...avail.first, 'title': b['title']});
      return;
    }
    setState(() {
      _book = b;
      _copies = avail;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_book == null ? 'Selecionar livro' : 'Escolha o exemplar'),
        content: SizedBox(
          width: 560,
          height: 460,
          child: _book != null
              ? ListView(children: [
                  Text(_book!['title'] as String, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final c in _copies)
                    ListTile(
                      leading: const Icon(Icons.qr_code_2),
                      title: Text('Tombo ${c['accession_number']}'),
                      subtitle: Text('Estado: ${conditionLabels[c['condition']] ?? c['condition']}'),
                      onTap: () => Navigator.pop(context, {...c, 'title': _book!['title']}),
                    ),
                ])
              : Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Título, autor ou ISBN'),
                    onChanged: (v) {
                      _t?.cancel();
                      _t = Timer(const Duration(milliseconds: 200), () => _search(v));
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _books.length,
                      itemBuilder: (_, i) {
                        final b = _books[i];
                        return ListTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(b['title'] as String),
                          subtitle: Text('${b['authors'] ?? '—'} · ${b['available']} disponível(is)'),
                          onTap: () => _selectBook(b),
                        );
                      },
                    ),
                  ),
                ]),
        ),
        actions: [
          if (_book != null) TextButton(onPressed: () => setState(() => _book = null), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      );
}
