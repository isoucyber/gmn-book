import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../security/permissions.dart';
import 'app_state.dart';
import 'screens/account_screens.dart';
import 'screens/backup_screen.dart';
import 'screens/book_screens.dart';
import 'screens/catalog_screen.dart';
import 'screens/counter_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/due_control_screen.dart';
import 'screens/portal_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/user_screens.dart';
import 'screens/who_has_screens.dart';
import 'global_search.dart';
import 'theme.dart';
import 'widgets.dart';

class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
  final bool primary;
  const NavItem(this.id, this.label, this.icon, this.selectedIcon, this.builder, {this.primary = false});
}

List<NavItem> navItemsFor(Session s) {
  if (s.role == Role.user) {
    return [
      NavItem('inicio', 'Início', Icons.home_outlined, Icons.home, () => const PortalHomeScreen(), primary: true),
      NavItem('catalogo', 'Catálogo', Icons.auto_stories_outlined, Icons.auto_stories, () => const CatalogScreen(), primary: true),
      NavItem('favoritos', 'Favoritos', Icons.favorite_border, Icons.favorite, () => const FavoritesScreen(), primary: true),
      NavItem('historico', 'Histórico', Icons.history, Icons.history, () => const PortalHistoryScreen(), primary: true),
      NavItem('notificacoes', 'Avisos', Icons.notifications_none, Icons.notifications, () => const NotificationsScreen()),
      NavItem('conta', 'Minha conta', Icons.person_outline, Icons.person, () => const AccountScreen()),
      NavItem('sobre', 'Sobre', Icons.info_outline, Icons.info, () => const AboutScreen()),
    ];
  }
  return [
    if (s.can(Permission.dashboardView))
      NavItem('painel', 'Painel', Icons.space_dashboard_outlined, Icons.space_dashboard, () => const DashboardScreen(), primary: true),
    if (s.can(Permission.circulationOperate))
      NavItem('balcao', 'Balcão', Icons.qr_code_scanner_outlined, Icons.qr_code_scanner, () => const CounterScreen(), primary: true),
    if (s.can(Permission.dueControlView))
      NavItem('devolucoes', 'Devoluções', Icons.event_note_outlined, Icons.event_note, () => const DueControlScreen(), primary: true),
    NavItem('catalogo', 'Catálogo', Icons.auto_stories_outlined, Icons.auto_stories, () => const CatalogScreen(), primary: true),
    if (s.can(Permission.circulationOperate))
      NavItem('quem', 'Quem está com cada livro?', Icons.person_search_outlined, Icons.person_search, () => const WhoHasScreen()),
    if (s.can(Permission.dueControlView))
      NavItem('com_emprestimos', 'Usuários com empréstimos', Icons.groups_outlined, Icons.groups, () => const UsersWithLoansScreen()),
    if (s.can(Permission.usersView))
      NavItem('usuarios', 'Usuários', Icons.badge_outlined, Icons.badge, () => const UsersScreen()),
    NavItem('notificacoes', 'Notificações', Icons.notifications_none, Icons.notifications, () => const NotificationsScreen()),
    if (s.can(Permission.settingsManage))
      NavItem('regras', 'Regras e calendário', Icons.tune_outlined, Icons.tune, () => const SettingsScreen()),
    if (s.can(Permission.backupCreate))
      NavItem('backup', 'Backup e restauração', Icons.backup_outlined, Icons.backup, () => const BackupScreen()),
    if (s.can(Permission.auditView))
      NavItem('auditoria', 'Auditoria', Icons.policy_outlined, Icons.policy, () => const AuditScreen()),
    NavItem('conta', 'Minha conta', Icons.person_outline, Icons.person, () => const AccountScreen()),
    NavItem('sobre', 'Sobre', Icons.info_outline, Icons.info, () => const AboutScreen()),
  ];
}

/// Navegacao adaptativa: menu lateral em telas largas (notebook/tablet),
/// barra inferior + "Mais" em celulares.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String _current = '';

  void go(String id) => setState(() => _current = id);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.session!;
    final items = navItemsFor(s);
    if (_current.isEmpty || !items.any((i) => i.id == _current)) _current = items.first.id;
    final idx = items.indexWhere((i) => i.id == _current);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final page = KeyedSubtree(key: ValueKey(_current), child: items[idx].builder());

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => showGlobalSearch(context),
      if (s.can(Permission.circulationOperate)) ...{
        const SingleActivator(LogicalKeyboardKey.f2): () {
          counterTab.value = 0;
          go('balcao');
        },
        const SingleActivator(LogicalKeyboardKey.f3): () {
          counterTab.value = 1;
          go('balcao');
        },
      },
      if (s.can(Permission.catalogManage))
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const BookFormScreen())),
    };

    Widget body;
    if (wide) {
      final extended = width >= 1250;
      body = Material(child: Row(children: [
        NavigationRail(
          extended: extended,
          minExtendedWidth: 250,
          selectedIndex: idx,
          onDestinationSelected: (i) => go(items[i].id),
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: extended
                ? const BrandMark(size: 34, light: true)
                : const Icon(Icons.menu_book_rounded, color: Brand.aqua, size: 32),
          ),
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Busca global (Ctrl+K)',
                    icon: const Icon(Icons.search, color: Color(0xFFB9D6DA)),
                    onPressed: () => showGlobalSearch(context),
                  ),
                  IconButton(
                    tooltip: 'Sair (${s.name})',
                    icon: const Icon(Icons.logout, color: Color(0xFFB9D6DA)),
                    onPressed: () => app.signOut(),
                  ),
                ]),
              ),
            ),
          ),
          destinations: [
            for (final it in items)
              NavigationRailDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selectedIcon), label: Text(it.label)),
          ],
        ),
        Expanded(child: page),
      ]));
    } else {
      final primary = items.where((i) => i.primary).take(4).toList();
      final selPrimary = primary.indexWhere((i) => i.id == _current);
      body = Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selPrimary >= 0 ? selPrimary : primary.length,
          onDestinationSelected: (i) {
            if (i < primary.length) {
              go(primary[i].id);
            } else {
              _openMore(context, items.where((x) => !primary.contains(x)).toList());
            }
          },
          destinations: [
            for (final it in primary)
              NavigationDestination(icon: Icon(it.icon), selectedIcon: Icon(it.selectedIcon), label: it.label),
            const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Mais'),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(autofocus: true, child: body),
    );
  }

  void _openMore(BuildContext context, List<NavItem> rest) {
    final app = context.appRead;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Busca global'),
            onTap: () {
              Navigator.pop(c);
              showGlobalSearch(context);
            },
          ),
          for (final it in rest)
            ListTile(
              leading: Icon(it.icon),
              title: Text(it.label),
              selected: it.id == _current,
              onTap: () {
                Navigator.pop(c);
                go(it.id);
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text('Sair (${app.session?.name ?? ''})'),
            onTap: () {
              Navigator.pop(c);
              app.signOut();
            },
          ),
        ]),
      ),
    );
  }
}

/// Cabecalho padrao das paginas principais.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.body, this.actions, this.fab, this.bottom});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions, bottom: bottom),
        floatingActionButton: fab,
        body: body,
      );
}
