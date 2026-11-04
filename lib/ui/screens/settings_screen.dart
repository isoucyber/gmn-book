import 'package:flutter/material.dart';

import '../../core/util.dart';
import '../../services/settings_service.dart';
import '../app_state.dart';
import '../shell.dart';
import '../widgets.dart';

/// Regras da biblioteca, alertas, calendario e mensagens (somente HOST).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  Set<int> _closed = {};
  String _signup = 'approval';
  bool _blockOverdue = true;
  bool _userRenew = false;
  bool _loading = true;
  bool _busy = false;

  static const _fields = [
    SettingKeys.schoolName,
    SettingKeys.schoolAddress,
    SettingKeys.schoolYear,
    SettingKeys.defaultLoanDays,
    SettingKeys.maxLoansUser,
    SettingKeys.maxLoansStaff,
    SettingKeys.nearDueDays,
    SettingKeys.alertDays,
    SettingKeys.lockoutAttempts,
    SettingKeys.lockoutMinutes,
    SettingKeys.sessionTimeoutMinutes,
    SettingKeys.backupReminderDays,
    SettingKeys.messageTemplate,
  ];

  @override
  void initState() {
    super.initState();
    for (final k in _fields) {
      _c[k] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final st = await context.lib.settings.load();
    for (final k in _fields) {
      _c[k]!.text = st.str(k);
    }
    _closed = st.closedWeekdays;
    _signup = st.signupMode;
    _blockOverdue = st.blockOnOverdue;
    _userRenew = st.userCanRenew;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.lib.settings.save(context.session, {
        for (final k in _fields) k: _c[k]!.text.trim(),
        SettingKeys.closedWeekdays: (_closed.toList()..sort()).join(','),
        SettingKeys.signupMode: _signup,
        SettingKeys.blockOnOverdue: _blockOverdue ? '1' : '0',
        SettingKeys.userCanRenew: _userRenew ? '1' : '0',
      });
      if (!mounted) return;
      showInfo(context, 'Regras salvas.');
      context.appRead.dataChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(String k, String label, {String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[k],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, helperText: helper),
          validator: (v) => int.tryParse(v ?? '') == null ? 'Informe um número' : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return PageScaffold(
      title: 'Regras e calendário',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            onPressed: _busy || _loading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar'),
          ),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                PageBody(
                  maxWidth: 860,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _card(t, 'Escola', [
                      TextFormField(controller: _c[SettingKeys.schoolName], decoration: const InputDecoration(labelText: 'Nome da escola')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _c[SettingKeys.schoolAddress], decoration: const InputDecoration(labelText: 'Endereço')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _c[SettingKeys.schoolYear], decoration: const InputDecoration(labelText: 'Ano letivo')),
                    ]),
                    _card(t, 'Empréstimos', [
                      _num(SettingKeys.defaultLoanDays, 'Prazo padrão (dias)', helper: 'Usado quando o título não tem prazo próprio'),
                      _num(SettingKeys.maxLoansUser, 'Máximo de livros simultâneos — leitores'),
                      _num(SettingKeys.maxLoansStaff, 'Máximo de livros simultâneos — funcionários/professores'),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _blockOverdue,
                        onChanged: (v) => setState(() => _blockOverdue = v),
                        title: const Text('Bloquear novos empréstimos de quem tem atraso'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _userRenew,
                        onChanged: (v) => setState(() => _userRenew = v),
                        title: const Text('Leitor pode renovar pelo próprio portal'),
                      ),
                    ]),
                    _card(t, 'Alertas de devolução', [
                      _num(SettingKeys.nearDueDays, '"Próximo do vencimento" a partir de quantos dias antes'),
                      TextFormField(
                        controller: _c[SettingKeys.alertDays],
                        decoration: const InputDecoration(
                          labelText: 'Dias de alerta',
                          helperText: 'Números separados por vírgula. 7 = 7 dias antes, 0 = no dia, -1 = após o vencimento',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _c[SettingKeys.messageTemplate],
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Modelo da mensagem de cobrança',
                          helperText: 'Campos: {nome} {livro} {escola} {situacao} {data}',
                        ),
                      ),
                    ]),
                    _card(t, 'Dias em que a biblioteca fecha', [
                      const Text('Se a devolução cair num dia fechado, o prazo passa para o próximo dia útil.'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        for (var d = 1; d <= 7; d++)
                          FilterChip(
                            label: Text(days[d - 1]),
                            selected: _closed.contains(d),
                            onSelected: (v) => setState(() => v ? _closed.add(d) : _closed.remove(d)),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      const _HolidayList(),
                    ]),
                    _card(t, 'Acesso e segurança', [
                      Text('Cadastro de leitores pelo aplicativo', style: t.textTheme.labelLarge),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'approval', label: Text('Com aprovação')),
                          ButtonSegment(value: 'open', label: Text('Livre')),
                          ButtonSegment(value: 'disabled', label: Text('Só a biblioteca')),
                        ],
                        selected: {_signup},
                        onSelectionChanged: (s) => setState(() => _signup = s.first),
                      ),
                      const SizedBox(height: 12),
                      _num(SettingKeys.lockoutAttempts, 'Tentativas de login antes do bloqueio'),
                      _num(SettingKeys.lockoutMinutes, 'Minutos de bloqueio'),
                      _num(SettingKeys.sessionTimeoutMinutes, 'Encerrar sessão após minutos de inatividade'),
                      _num(SettingKeys.backupReminderDays, 'Lembrar de fazer backup a cada (dias)'),
                    ]),
                  ]),
                ),
              ]),
            ),
    );
  }

  Widget _card(ThemeData t, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: t.textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ]),
          ),
        ),
      );
}

class _HolidayList extends StatelessWidget {
  const _HolidayList();

  @override
  Widget build(BuildContext context) {
    final lib = context.lib;
    final s = context.session;
    return AsyncView<List<Map<String, Object?>>>(
      load: () => lib.settings.holidays(),
      builder: (context, rows, reload) {
        final upcoming = rows.where((r) => !parseIsoDate(r['date'] as String).isBefore(AppClock.today())).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Feriados, recessos e férias (${upcoming.length} próximos)', style: Theme.of(context).textTheme.labelLarge)),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: addDays(AppClock.today(), -30),
                  lastDate: addDays(AppClock.today(), 730),
                  helpText: 'Período fechado',
                );
                if (range == null || !context.mounted) return;
                final desc = await promptText(context, 'Descrição', label: 'Ex.: Recesso de julho');
                if (desc == null || desc.trim().isEmpty || !context.mounted) return;
                try {
                  final n = await lib.settings.addClosedDays(s, range.start, range.end, desc);
                  if (context.mounted) showInfo(context, '$n dia(s) adicionado(s) ao calendário.');
                  reload();
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
          ]),
          for (final h in upcoming.take(40))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy, size: 20),
              title: Text('${brDateIso(h['date'] as String)} (${weekdayName(parseIsoDate(h['date'] as String))})'),
              subtitle: Text(h['description'] as String),
              trailing: IconButton(
                tooltip: 'Remover',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await lib.settings.removeClosedDay(s, h['id'] as String);
                  reload();
                },
              ),
            ),
        ]);
      },
    );
  }
}
