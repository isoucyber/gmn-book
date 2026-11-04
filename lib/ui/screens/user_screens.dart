import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../security/permissions.dart';
import '../../services/user_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'due_control_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.initialStatus});
  final String? initialStatus;
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _q = '';
  Timer? _t;
  Role? _role;
  late String? _status = widget.initialStatus;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final manage = s.can(Permission.usersManage);
    return PageScaffold(
      title: 'Usuários',
      fab: manage
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserFormScreen())),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Novo usuário'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PageBody(
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nome, usuário, carteirinha, matrícula ou turma'),
                onChanged: (v) {
                  _t?.cancel();
                  _t = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v));
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final r in [null, ...Role.values])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(r == null ? 'Todos' : r.label),
                        selected: _role == r,
                        onSelected: (_) => setState(() => _role = r),
                      ),
                    ),
                  const SizedBox(width: 8),
                  for (final e in UserService.statusLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(e.value),
                        selected: _status == e.key,
                        onSelected: (v) => setState(() => _status = v ? e.key : null),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        Expanded(
          child: AsyncView<List<Map<String, Object?>>>(
            deps: '$_q|$_role|$_status',
            load: () => lib.users.list(s, search: _q, role: _role, status: _status),
            builder: (context, rows, _) {
              if (rows.isEmpty) return const EmptyState(icon: Icons.person_search, title: 'Nenhum usuário encontrado');
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final u = rows[i];
                  final role = Role.fromId(u['role_id'] as String);
                  final locked = (toInt(u['locked_until']) ?? 0) > AppClock.nowMs();
                  return PageBody(
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: role == Role.user ? null : Brand.aqua.withValues(alpha: 0.3),
                          child: Text((u['name'] as String).substring(0, 1).toUpperCase()),
                        ),
                        title: Text(u['name'] as String),
                        subtitle: Text([
                          u['card_code'],
                          role.label,
                          u['class_name'],
                          if (u['status'] != 'active') UserService.statusLabels[u['status']],
                          if (locked) 'bloqueado por tentativas',
                        ].whereType<String>().join(' · ')),
                        trailing: (u['active_loans'] as int? ?? 0) > 0
                            ? StatusPill('${u['active_loans']} livro(s)', color: Brand.aqua)
                            : null,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => UserDetailScreen(userId: u['id'] as String))),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------

class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    final manage = s.can(Permission.usersManage);
    return AsyncView<(Map<String, Object?>?, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      load: () async {
        final u = await lib.users.get(s, userId);
        final active = await lib.circulation.userLoans(s, userId);
        final hist = await lib.circulation.userLoans(s, userId, history: true);
        return (u, active, hist);
      },
      builder: (context, data, reload) {
        final (u, active, hist) = data;
        if (u == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, title: 'Usuário não encontrado'));
        final role = Role.fromId(u['role_id'] as String);
        final locked = (toInt(u['locked_until']) ?? 0) > AppClock.nowMs();
        Future<void> act(Future<void> Function() f, String done) async {
          try {
            await f();
            if (!context.mounted) return;
            showInfo(context, done);
            context.appRead.dataChanged();
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(u['name'] as String),
            actions: [
              if (manage)
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'edit':
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserFormScreen(userId: userId)));
                      case 'approve':
                        await act(() => lib.users.setStatus(s, userId, 'active'), 'Cadastro aprovado.');
                      case 'password':
                        final pw = await promptText(context, 'Nova senha temporária',
                            message: 'O usuário deverá trocá-la no próximo acesso.', label: 'Senha', obscure: true);
                        if (pw != null && pw.isNotEmpty) {
                          await act(() => lib.users.resetPassword(s, userId, pw), 'Senha redefinida.');
                        }
                      case 'unlock':
                        await act(() => lib.users.unlock(s, userId), 'Usuário desbloqueado.');
                      case 'status':
                        if (!context.mounted) return;
                        final st = await showDialog<String>(
                          context: context,
                          builder: (c) => SimpleDialog(title: const Text('Situação'), children: [
                            for (final e in UserService.statusLabels.entries)
                              SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
                          ]),
                        );
                        if (st != null) await act(() => lib.users.setStatus(s, userId, st), 'Situação alterada.');
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Editar cadastro')),
                    if (u['status'] == 'pending') const PopupMenuItem(value: 'approve', child: Text('Aprovar cadastro')),
                    const PopupMenuItem(value: 'password', child: Text('Redefinir senha')),
                    if (locked) const PopupMenuItem(value: 'unlock', child: Text('Desbloquear acesso')),
                    const PopupMenuItem(value: 'status', child: Text('Alterar situação')),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            PageBody(
              maxWidth: 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        StatusPill(role.label, color: Theme.of(context).colorScheme.primary),
                        StatusPill(UserService.statusLabels[u['status']] ?? '${u['status']}',
                            color: u['status'] == 'active' ? Brand.ok : Brand.warn),
                        if (locked) StatusPill('Bloqueado por tentativas', color: Theme.of(context).colorScheme.error),
                      ]),
                      const SizedBox(height: 12),
                      InfoRow('Carteirinha', u['card_code'] as String?),
                      InfoRow('Usuário', u['username'] as String?),
                      InfoRow('Matrícula', u['enrollment'] as String?),
                      InfoRow('Turma / série', [u['class_name'], u['grade']].whereType<String>().join(' · ')),
                      InfoRow('Turno', u['shift'] as String?),
                      InfoRow('E-mail', u['email'] as String?),
                      InfoRow('Telefone', u['phone'] as String?),
                      if (toBool(u['is_minor'])) ...[
                        InfoRow('Responsável', u['guardian_name'] as String?),
                        InfoRow('Tel. responsável', u['guardian_phone'] as String?),
                        InfoRow('Consentimento resp.', u['guardian_consent_at'] == null ? 'não registrado' : brDateTimeMs(u['guardian_consent_at'] as int)),
                      ],
                      InfoRow('Contato autorizado', toBool(u['contact_authorized']) ? 'sim' : 'não'),
                      InfoRow('Último acesso', brDateTimeMs(toInt(u['last_login_at']))),
                    ]),
                  ),
                ),
                SectionTitle('Livros com o usuário (${active.length})'),
                if (active.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhum empréstimo ativo.')))
                else
                  for (final l in active)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: LoanCard(loan: l, showUser: false, showContact: false)),
                SectionTitle('Histórico (${hist.length})'),
                Card(
                  child: hist.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('Sem histórico.'))
                      : Column(children: [
                          for (final l in hist)
                            ListTile(
                              dense: true,
                              title: Text('${l['title']}'),
                              subtitle: Text('${brDateIso(l['loan_date'] as String)} → '
                                  '${l['status'] == 'returned' ? 'devolvido em ${brDateIso(l['return_date'] as String?)}' : 'cancelado'}'),
                            ),
                        ]),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------

class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.userId});
  final String? userId;
  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = {
    for (final k in ['name', 'username', 'password', 'enrollment', 'class_name', 'grade', 'shift', 'school_year', 'email', 'phone', 'guardian_name', 'guardian_phone'])
      k: TextEditingController(),
  };
  Role _role = Role.user;
  bool _minor = false;
  bool _contact = false;
  bool _gConsent = false;
  bool _busy = false;
  bool _loading = true;

  bool get _editing => widget.userId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_editing) {
      final u = await context.lib.users.get(context.session, widget.userId!);
      if (u != null) {
        for (final k in _c.keys) {
          if (k != 'password') _c[k]!.text = (u[k] as String?) ?? '';
        }
        _role = Role.fromId(u['role_id'] as String);
        _minor = toBool(u['is_minor']);
        _contact = toBool(u['contact_authorized']);
        _gConsent = u['guardian_consent_at'] != null;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  UserInput _input() => UserInput(
        role: _role,
        name: _c['name']!.text,
        username: _c['username']!.text,
        enrollment: _c['enrollment']!.text,
        className: _c['class_name']!.text,
        grade: _c['grade']!.text,
        shift: _c['shift']!.text,
        schoolYear: _c['school_year']!.text,
        email: _c['email']!.text,
        phone: _c['phone']!.text,
        isMinor: _minor,
        guardianName: _c['guardian_name']!.text,
        guardianPhone: _c['guardian_phone']!.text,
        contactAuthorized: _contact,
        guardianConsent: _gConsent,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final lib = context.lib;
    final s = context.session;
    setState(() => _busy = true);
    try {
      if (_editing) {
        await lib.users.update(s, widget.userId!, _input());
      } else {
        final r = await lib.users.create(s, _input(), _c['password']!.text);
        if (r.recoveryCode != null && mounted) {
          await showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Código de recuperação'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Entregue este código ao novo administrador/auxiliar. Ele aparece só agora.'),
                const SizedBox(height: 12),
                SelectableText(r.recoveryCode!, style: const TextStyle(fontFamily: 'monospace', fontSize: 22, letterSpacing: 2)),
              ]),
              actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendi'))],
            ),
          );
        }
      }
      if (!mounted) return;
      context.appRead.dataChanged();
      showInfo(context, _editing ? 'Cadastro atualizado.' : 'Usuário cadastrado. Ele deverá trocar a senha no primeiro acesso.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _f(String k, String label, {String? helper, bool obscure = false, String? Function(String?)? v}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[k],
          obscureText: obscure,
          validator: v,
          decoration: InputDecoration(labelText: label, helperText: helper),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.session;
    final canAdmins = s.can(Permission.manageAdmins);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar usuário' : 'Novo usuário')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                PageBody(
                  maxWidth: 720,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (canAdmins) ...[
                      SegmentedButton<Role>(
                        segments: [for (final r in Role.values) ButtonSegment(value: r, label: Text(r.label))],
                        selected: {_role},
                        onSelectionChanged: (v) => setState(() => _role = v.first),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _f('name', 'Nome completo *', v: (v) => (v ?? '').trim().length < 2 ? 'Obrigatório' : null),
                    _f('username', 'Usuário de acesso *', v: (v) => (v ?? '').trim().length < 3 ? 'Mínimo 3 caracteres' : null),
                    if (!_editing)
                      _f('password', 'Senha temporária *',
                          obscure: true,
                          helper: _role == Role.user ? 'Mínimo 6 caracteres' : 'Mínimo 8, com letras e números',
                          v: (v) => (v ?? '').length < (_role == Role.user ? 6 : 8) ? 'Senha curta demais' : null),
                    Row(children: [
                      Expanded(child: _f('enrollment', 'Matrícula')),
                      const SizedBox(width: 12),
                      Expanded(child: _f('class_name', 'Turma')),
                    ]),
                    Row(children: [
                      Expanded(child: _f('grade', 'Série/ano')),
                      const SizedBox(width: 12),
                      Expanded(child: _f('shift', 'Turno')),
                      const SizedBox(width: 12),
                      Expanded(child: _f('school_year', 'Ano letivo')),
                    ]),
                    _f('email', 'E-mail (opcional)'),
                    _f('phone', 'Telefone (opcional)'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _contact,
                      onChanged: (v) => setState(() => _contact = v),
                      title: const Text('Autoriza contato para avisos de devolução'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _minor,
                      onChanged: (v) => setState(() => _minor = v),
                      title: const Text('Menor de idade'),
                    ),
                    if (_minor) ...[
                      _f('guardian_name', 'Nome do responsável'),
                      _f('guardian_phone', 'Telefone do responsável'),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _gConsent,
                        onChanged: (v) => setState(() => _gConsent = v ?? false),
                        title: const Text('Consentimento do responsável registrado'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_editing ? 'Salvar' : 'Cadastrar'),
                    ),
                  ]),
                ),
              ]),
            ),
    );
  }
}
