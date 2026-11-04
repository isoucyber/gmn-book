import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/util.dart';
import '../../security/permissions.dart';
import '../../services/circulation_service.dart';
import '../app_state.dart';
import '../pickers.dart';
import '../scanner.dart';
import '../theme.dart';
import '../widgets.dart';

/// Aba ativa do balcao (F2 = emprestimo, F3 = devolucao).
final counterTab = ValueNotifier<int>(0);

/// Balcao rapido: ler carteirinha + exemplar e concluir em segundos.
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: counterTab.value);

  @override
  void initState() {
    super.initState();
    counterTab.addListener(_sync);
    _tabs.addListener(() => counterTab.value = _tabs.index);
  }

  void _sync() {
    if (_tabs.index != counterTab.value) _tabs.animateTo(counterTab.value);
  }

  @override
  void dispose() {
    counterTab.removeListener(_sync);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Balcão'),
          bottom: TabBar(controller: _tabs, tabs: const [
            Tab(icon: Icon(Icons.outbox_outlined), text: 'Empréstimo (F2)'),
            Tab(icon: Icon(Icons.assignment_return_outlined), text: 'Devolução (F3)'),
          ]),
        ),
        body: TabBarView(controller: _tabs, children: const [_CheckoutTab(), _ReturnTab()]),
      );
}

// -----------------------------------------------------------------------------

class _CheckoutTab extends StatefulWidget {
  const _CheckoutTab();
  @override
  State<_CheckoutTab> createState() => _CheckoutTabState();
}

class _CheckoutTabState extends State<_CheckoutTab> with AutomaticKeepAliveClientMixin {
  final _userCode = TextEditingController();
  final _copyCode = TextEditingController();
  final _days = TextEditingController();
  final _notes = TextEditingController();
  final _copyFocus = FocusNode();
  final _userFocus = FocusNode();

  Map<String, Object?>? _user;
  List<LoanBlock> _blocks = [];
  List<Map<String, Object?>> _userLoans = [];
  Map<String, Object?>? _copy;
  DateTime? _due;
  DateTime? _manualDue;
  bool _busy = false;
  final List<Map<String, Object?>> _done = [];

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadUser(String code) async {
    final lib = context.lib;
    final s = context.session;
    try {
      final u = await lib.users.findByCode(s, code);
      if (u == null) {
        if (mounted) showError(context, 'Usuário "$code" não encontrado.');
        return;
      }
      await _setUser(u);
      _copyFocus.requestFocus();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setUser(Map<String, Object?> u) async {
    final lib = context.lib;
    final s = context.session;
    final blocks = await lib.circulation.blocksFor(u['id'] as String);
    final loans = await lib.circulation.userLoans(s, u['id'] as String);
    setState(() {
      _user = u;
      _userCode.text = u['card_code'] as String;
      _blocks = blocks;
      _userLoans = loans;
    });
  }

  Future<void> _loadCopy(String code) async {
    final lib = context.lib;
    final s = context.session;
    try {
      var c = await lib.catalog.findCopyByCode(s, code);
      if (c == null) {
        // Leitura de ISBN: escolhe automaticamente um exemplar disponivel.
        final isbn = cleanIsbn(code);
        if (isbn != null) {
          final books = await lib.catalog.search(s, query: isbn, limit: 1);
          if (books.isNotEmpty) {
            final copies = await lib.catalog.copies(s, books.first['id'] as String);
            final avail = copies.where((x) => x['status'] == 'available').toList();
            if (avail.isEmpty) throw AppException('Nenhum exemplar disponível de "${books.first['title']}".');
            c = await lib.catalog.findCopyByCode(s, avail.first['id'] as String);
          }
        }
      }
      if (c == null) throw AppException('Exemplar "$code" não encontrado.');
      await _setCopy(c);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setCopy(Map<String, Object?> c) async {
    final lib = context.lib;
    final copy = await lib.catalog.findCopyByCode(context.session, c['id'] as String);
    if (copy == null) return;
    final settings = await lib.settings.load();
    final days = lib.circulation.loanDaysFor(copy, settings);
    final due = await lib.circulation.previewDueDate(copy['book_id'] as String, days: days);
    setState(() {
      _copy = copy;
      _copyCode.text = copy['barcode'] as String;
      _days.text = '$days';
      _due = due;
      _manualDue = null;
    });
  }

  Future<void> _recalc() async {
    final c = _copy;
    final d = int.tryParse(_days.text);
    if (c == null || d == null || d < 1 || d > 365) return;
    final due = await context.lib.circulation.previewDueDate(c['book_id'] as String, days: d);
    setState(() {
      _due = due;
      _manualDue = null;
    });
  }

  Future<void> _confirm({String? override}) async {
    final u = _user, c = _copy;
    if (u == null || c == null) return;
    final lib = context.lib;
    final s = context.session;
    setState(() => _busy = true);
    try {
      final loan = await lib.circulation.checkout(
        s,
        userId: u['id'] as String,
        copyId: c['id'] as String,
        days: _manualDue == null ? int.tryParse(_days.text) : null,
        dueDate: _manualDue,
        notes: _notes.text,
        overrideReason: override,
      );
      if (!mounted) return;
      context.appRead.dataChanged();
      setState(() {
        _done.insert(0, loan);
        _copy = null;
        _copyCode.clear();
        _notes.clear();
        _due = null;
        _manualDue = null;
      });
      await _setUser(u);
      if (!mounted) return;
      showInfo(context, 'Empréstimo registrado: devolução em ${brDateIso(loan['due_date'] as String)}.',
          seconds: CirculationService.undoWindowSeconds,
          action: SnackBarAction(label: 'Desfazer', onPressed: _undo));
      _copyFocus.requestFocus();
    } on LoanBlockedException catch (e) {
      if (!mounted) return;
      if (!s.can(Permission.circulationOverride)) {
        showError(context, '${e.message}\nApenas um administrador pode liberar.');
        return;
      }
      final reason = await promptText(context, 'Empréstimo bloqueado',
          message: '${e.message}\n\nPara liberar mesmo assim, informe a justificativa (fica registrada na auditoria).',
          label: 'Justificativa',
          ok: 'Liberar e emprestar');
      if (reason != null && reason.trim().isNotEmpty) await _confirm(override: reason);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    final lib = context.lib;
    try {
      await lib.circulation.undoLast(context.session);
      if (!mounted) return;
      context.appRead.dataChanged();
      setState(() => _done.removeAt(0));
      if (_user != null) await _setUser(_user!);
      if (mounted) showInfo(context, 'Empréstimo desfeito.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _clearUser() => setState(() {
        _user = null;
        _blocks = [];
        _userLoans = [];
        _userCode.clear();
        _userFocus.requestFocus();
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = Theme.of(context);
    final settingsDays = _days;
    return ListView(padding: const EdgeInsets.all(16), children: [
      PageBody(
        maxWidth: 900,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 1. Usuario
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('1. Leitor', style: t.textTheme.titleMedium),
                const SizedBox(height: 10),
                if (_user == null)
                  TextField(
                    controller: _userCode,
                    focusNode: _userFocus,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _loadUser,
                    decoration: InputDecoration(
                      labelText: 'Carteirinha, matrícula ou usuário',
                      helperText: 'Leia o código com o leitor ou digite e tecle Enter',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        ScanButton(onCode: _loadUser),
                        IconButton(
                          tooltip: 'Procurar por nome',
                          icon: const Icon(Icons.person_search),
                          onPressed: () async {
                            final lib = context.lib;
                            final session = context.session;
                            final u = await pickUser(context);
                            if (u != null) {
                              final full = await lib.users.findByCode(session, u['card_code'] as String);
                              if (full != null) await _setUser(full);
                              _copyFocus.requestFocus();
                            }
                          },
                        ),
                      ]),
                    ),
                  )
                else
                  _UserSummary(user: _user!, blocks: _blocks, loans: _userLoans, onClear: _clearUser),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // 2. Exemplar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('2. Exemplar', style: t.textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _copyCode,
                  focusNode: _copyFocus,
                  enabled: _user != null,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _loadCopy,
                  decoration: InputDecoration(
                    labelText: 'Código do exemplar (tombo) ou ISBN',
                    prefixIcon: const Icon(Icons.qr_code_2),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      ScanButton(onCode: _loadCopy),
                      IconButton(
                        tooltip: 'Procurar no catálogo',
                        icon: const Icon(Icons.manage_search),
                        onPressed: _user == null
                            ? null
                            : () async {
                                final c = await pickAvailableCopy(context);
                                if (c != null) await _setCopy(c);
                              },
                      ),
                    ]),
                  ),
                ),
                if (_copy != null) ...[
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.menu_book, size: 32),
                    title: Text(_copy!['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Tombo ${_copy!['accession_number']} · estado: ${_copy!['condition']}'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: settingsDays,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Prazo (dias)'),
                        onChanged: (_) => _recalc(),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text('Devolução: ${_manualDue != null ? brDate(_manualDue!) : (_due != null ? brDate(_due!) : '—')}'),
                      onPressed: () async {
                        final today = AppClock.today();
                        final d = await showDatePicker(
                          context: context,
                          firstDate: today,
                          lastDate: addDays(today, 365),
                          initialDate: _manualDue ?? _due ?? today,
                          helpText: 'Data prevista de devolução',
                        );
                        if (d != null) setState(() => _manualDue = d);
                      },
                    ),
                    if (_manualDue != null) const StatusPill('Prazo alterado manualmente', color: Brand.warn),
                  ]),
                  if (_due != null && _manualDue == null) ...[
                    const SizedBox(height: 6),
                    Text('Calculado: ${weekdayName(_due!)}, ${brDate(_due!)} (dias fechados e feriados são pulados).',
                        style: t.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Observações (opcional)')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _confirm(),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar empréstimo'),
                  ),
                ],
              ]),
            ),
          ),
          if (_done.isNotEmpty) ...[
            const SectionTitle('Empréstimos nesta sessão'),
            for (final l in _done)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('${l['title']}'),
                  subtitle: Text('${l['user_name']} · tombo ${l['accession_number']} · devolver até ${brDateIso(l['due_date'] as String)}'),
                ),
              ),
          ],
        ]),
      ),
    ]);
  }
}

class _UserSummary extends StatelessWidget {
  const _UserSummary({required this.user, required this.blocks, required this.loans, required this.onClear});
  final Map<String, Object?> user;
  final List<LoanBlock> blocks;
  final List<Map<String, Object?>> loans;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final today = AppClock.today();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        CircleAvatar(radius: 24, child: Text((user['name'] as String).substring(0, 1).toUpperCase())),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user['name'] as String, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text([user['card_code'], user['class_name'], Role.fromId(user['role_id'] as String).label]
                .whereType<String>()
                .join(' · ')),
          ]),
        ),
        TextButton.icon(onPressed: onClear, icon: const Icon(Icons.swap_horiz), label: const Text('Trocar')),
      ]),
      if (blocks.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: StatusPill(b.message, color: t.colorScheme.error, icon: Icons.block),
          ),
      ],
      if (loans.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Com o leitor agora (${loans.length}):', style: t.textTheme.labelLarge),
        for (final l in loans)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Icon(Icons.chevron_right, size: 16),
              Expanded(child: Text('${l['title']} — ${brDateIso(l['due_date'] as String)}')),
              Text(daysLeftLabel(daysLeftOf(l, today)),
                  style: TextStyle(color: daysLeftOf(l, today) < 0 ? t.colorScheme.error : null)),
            ]),
          ),
      ],
    ]);
  }
}

// -----------------------------------------------------------------------------

class _ReturnTab extends StatefulWidget {
  const _ReturnTab();
  @override
  State<_ReturnTab> createState() => _ReturnTabState();
}

class _ReturnTabState extends State<_ReturnTab> with AutomaticKeepAliveClientMixin {
  final _code = TextEditingController();
  final _notes = TextEditingController();
  final _focus = FocusNode();
  String _condition = 'bom';
  bool _lost = false;
  bool _busy = false;
  final List<Map<String, Object?>> _done = [];

  @override
  bool get wantKeepAlive => true;

  Future<void> _return([String? code]) async {
    final c = (code ?? _code.text).trim();
    if (c.isEmpty) return;
    final lib = context.lib;
    final s = context.session;
    if (_lost) {
      final ok = await confirm(context, 'Registrar extravio?',
          'O exemplar será marcado como extraviado e o leitor ficará com pendência até a reposição.',
          destructive: true);
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      final loan = await lib.circulation.returnCopy(s, c, condition: _condition, lost: _lost, notes: _notes.text);
      if (!mounted) return;
      context.appRead.dataChanged();
      final daysLate = -daysBetween(parseIsoDate(loan['return_date'] as String), parseIsoDate(loan['due_date'] as String));
      setState(() {
        _done.insert(0, {...loan, 'days_late': daysLate > 0 ? daysLate : 0});
        _code.clear();
        _notes.clear();
        _condition = 'bom';
        _lost = false;
      });
      showInfo(context, daysLate > 0 ? 'Devolvido com $daysLate dia(s) de atraso.' : 'Devolução registrada no prazo.',
          seconds: CirculationService.undoWindowSeconds,
          action: SnackBarAction(label: 'Desfazer', onPressed: _undo));
      _focus.requestFocus();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    try {
      await context.lib.circulation.undoLast(context.session);
      if (!mounted) return;
      context.appRead.dataChanged();
      setState(() => _done.removeAt(0));
      showInfo(context, 'Devolução desfeita.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = Theme.of(context);
    return ListView(padding: const EdgeInsets.all(16), children: [
      PageBody(
        maxWidth: 900,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Leia o código do exemplar devolvido', style: t.textTheme.titleMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: _busy ? null : _return,
                  decoration: InputDecoration(
                    labelText: 'Código do exemplar (tombo)',
                    prefixIcon: const Icon(Icons.qr_code_2),
                    suffixIcon: ScanButton(onCode: _return),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Estado de conservação na devolução', style: t.textTheme.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'bom', label: Text('Bom')),
                    ButtonSegment(value: 'regular', label: Text('Regular')),
                    ButtonSegment(value: 'danificado', label: Text('Danificado')),
                  ],
                  selected: {_condition},
                  onSelectionChanged: _lost ? null : (s) => setState(() => _condition = s.first),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _lost,
                  onChanged: (v) => setState(() => _lost = v ?? false),
                  title: const Text('Leitor informou perda (extravio)'),
                ),
                TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Observações (opcional)')),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _return(),
                  icon: const Icon(Icons.assignment_return),
                  label: const Text('Registrar devolução'),
                ),
              ]),
            ),
          ),
          if (_done.isNotEmpty) ...[
            const SectionTitle('Devoluções nesta sessão'),
            for (final l in _done)
              Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: (l['days_late'] as int) > 0 ? Brand.warn : Brand.ok),
                  title: Text('${l['title']}'),
                  subtitle: Text('${l['user_name']} · tombo ${l['accession_number']}'
                      '${(l['days_late'] as int) > 0 ? ' · ${l['days_late']} dia(s) de atraso' : ' · no prazo'}'
                      '${l['condition_in'] != 'bom' ? ' · ${l['condition_in']}' : ''}'),
                ),
              ),
          ],
        ]),
      ),
    ]);
  }
}
