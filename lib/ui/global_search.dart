import 'dart:async';

import 'package:flutter/material.dart';

import '../core/util.dart';
import '../security/permissions.dart';
import 'app_state.dart';
import 'screens/book_screens.dart';
import 'screens/user_screens.dart';

/// Busca global (Ctrl+K): livros, usuarios e emprestimos ativos.
Future<void> showGlobalSearch(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const _GlobalSearchDialog(),
    );

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog();
  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, Object?>> _books = [];
  List<Map<String, Object?>> _users = [];
  List<Map<String, Object?>> _loans = [];

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _run(v));
  }

  Future<void> _run(String v) async {
    final lib = context.lib;
    final s = context.session;
    if (v.trim().isEmpty) {
      setState(() => _books = _users = _loans = []);
      return;
    }
    final books = await lib.catalog.search(s, query: v, limit: 8);
    final users = s.can(Permission.usersView) ? await lib.users.list(s, search: v, limit: 8) : <Map<String, Object?>>[];
    final loans = s.can(Permission.dueControlView)
        ? (await lib.circulation.activeLoans(s, search: v)).take(8).toList()
        : <Map<String, Object?>>[];
    if (mounted) {
      setState(() {
        _books = books;
        _users = users;
        _loans = loans;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _open(Widget page) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar livro, usuário ou empréstimo…',
              ),
            ),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              if (_books.isNotEmpty) _header(t, 'Livros'),
              for (final b in _books)
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(b['title'] as String),
                  subtitle: Text('${b['authors'] ?? '—'} · ${b['available']}/${b['total']} disponíveis'),
                  onTap: () => _open(BookDetailScreen(bookId: b['id'] as String)),
                ),
              if (_users.isNotEmpty) _header(t, 'Usuários'),
              for (final u in _users)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(u['name'] as String),
                  subtitle: Text('${u['card_code']}${u['class_name'] != null ? ' · ${u['class_name']}' : ''}'),
                  onTap: () => _open(UserDetailScreen(userId: u['id'] as String)),
                ),
              if (_loans.isNotEmpty) _header(t, 'Empréstimos ativos'),
              for (final l in _loans)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text('${l['title']}'),
                  subtitle: Text('${l['user_name']} · devolução ${brDateIso(l['due_date'] as String)}'),
                  onTap: () => _open(UserDetailScreen(userId: l['user_id'] as String)),
                ),
              if (_q.text.isNotEmpty && _books.isEmpty && _users.isEmpty && _loans.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nada encontrado.'))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header(ThemeData t, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(s, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
      );
}
