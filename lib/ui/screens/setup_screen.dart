import 'package:flutter/material.dart';

import '../../security/permissions.dart';
import '../../services/auth_service.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Assistente de primeira execucao: escola, administrador (HOST) e regras.
/// Nao existe senha padrao: o HOST define a propria senha aqui.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0;
  bool _busy = false;
  String? _recoveryCode;
  bool _saved = false;

  final _school = TextEditingController();
  final _address = TextEditingController();
  final _year = TextEditingController(text: '${DateTime.now().year}');
  final _hostName = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _email = TextEditingController();
  final _days = TextEditingController(text: '14');
  final _max = TextEditingController(text: '2');
  final _alerts = TextEditingController(text: '7,3,1,0,-1');
  String _signup = 'approval';
  bool _showPw = false;

  final _forms = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];

  Future<void> _finish() async {
    if (!_forms[2].currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final code = await context.lib.auth.completeSetup(SetupData(
        schoolName: _school.text,
        schoolAddress: _address.text,
        schoolYear: _year.text,
        hostName: _hostName.text,
        hostUsername: _user.text,
        hostPassword: _pw.text,
        hostEmail: _email.text.trim().isEmpty ? null : _email.text.trim(),
        defaultLoanDays: int.parse(_days.text),
        maxLoansUser: int.parse(_max.text),
        alertDays: _alerts.text.replaceAll(' ', ''),
        signupMode: _signup,
      ));
      setState(() => _recoveryCode = code);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_recoveryCode != null) return _codeScreen(t);
    return Scaffold(
      body: SafeArea(
        child: PageBody(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 12),
            const BrandMark(size: 44),
            const SizedBox(height: 16),
            Text('Bem-vindo! Vamos configurar a biblioteca.', style: t.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Tudo fica salvo apenas neste aparelho. Nenhuma conexão com a internet é necessária.',
                style: t.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Stepper(
              physics: const NeverScrollableScrollPhysics(),
              currentStep: _step,
              onStepTapped: (i) {
                if (i < _step) setState(() => _step = i);
              },
              controlsBuilder: (context, d) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(children: [
                  FilledButton(
                    onPressed: _busy ? null : d.onStepContinue,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_step == 2 ? 'Concluir configuração' : 'Continuar'),
                  ),
                  if (_step > 0) ...[
                    const SizedBox(width: 12),
                    TextButton(onPressed: d.onStepCancel, child: const Text('Voltar')),
                  ],
                ]),
              ),
              onStepContinue: () {
                if (_step < 2) {
                  if (_forms[_step].currentState!.validate()) setState(() => _step++);
                } else {
                  _finish();
                }
              },
              onStepCancel: () => setState(() => _step--),
              steps: [
                Step(
                  title: const Text('Escola'),
                  isActive: _step >= 0,
                  content: Form(
                    key: _forms[0],
                    child: Column(children: [
                      TextFormField(controller: _school, decoration: const InputDecoration(labelText: 'Nome da escola *'), validator: _req),
                      const SizedBox(height: 12),
                      TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Endereço')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _year, decoration: const InputDecoration(labelText: 'Ano letivo')),
                    ]),
                  ),
                ),
                Step(
                  title: const Text('Administrador (HOST)'),
                  isActive: _step >= 1,
                  content: Form(
                    key: _forms[1],
                    child: Column(children: [
                      TextFormField(controller: _hostName, decoration: const InputDecoration(labelText: 'Seu nome completo *'), validator: _req),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _user,
                        decoration: const InputDecoration(labelText: 'Usuário de acesso *', helperText: 'Letras, números, ponto ou hífen'),
                        validator: (v) {
                          try {
                            AuthService.validateUsername(v?.trim() ?? '');
                            return null;
                          } catch (e) {
                            return errorText(e);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'E-mail (opcional)')),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pw,
                        obscureText: !_showPw,
                        decoration: InputDecoration(
                          labelText: 'Senha *',
                          helperText: 'Mínimo de 8 caracteres, com letras e números',
                          suffixIcon: IconButton(
                            tooltip: _showPw ? 'Ocultar senha' : 'Mostrar senha',
                            icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPw = !_showPw),
                          ),
                        ),
                        validator: (v) {
                          try {
                            AuthService.validatePassword(v ?? '', Role.host);
                            return null;
                          } catch (e) {
                            return errorText(e);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pw2,
                        obscureText: !_showPw,
                        decoration: const InputDecoration(labelText: 'Confirme a senha *'),
                        validator: (v) => v != _pw.text ? 'As senhas não conferem' : null,
                      ),
                    ]),
                  ),
                ),
                Step(
                  title: const Text('Regras da biblioteca'),
                  isActive: _step >= 2,
                  content: Form(
                    key: _forms[2],
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextFormField(
                        controller: _days,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Prazo padrão de empréstimo (dias)', helperText: 'Cada livro pode ter um prazo próprio'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 365 ? 'Entre 1 e 365' : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _max,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Máximo de livros simultâneos por aluno'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 1 || n > 50 ? 'Entre 1 e 50' : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _alerts,
                        decoration: const InputDecoration(
                          labelText: 'Dias de alerta',
                          helperText: 'Ex.: 7,3,1,0,-1 → 7, 3 e 1 dia antes, no dia e após o vencimento',
                        ),
                        validator: (v) {
                          final parts = (v ?? '').split(',').where((e) => e.trim().isNotEmpty);
                          if (parts.any((e) => int.tryParse(e.trim()) == null)) return 'Use números separados por vírgula';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Cadastro de alunos pelo próprio aplicativo', style: t.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'approval', label: Text('Com aprovação')),
                          ButtonSegment(value: 'open', label: Text('Livre')),
                          ButtonSegment(value: 'disabled', label: Text('Só a biblioteca')),
                        ],
                        selected: {_signup},
                        onSelectionChanged: (s) => setState(() => _signup = s.first),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _codeScreen(ThemeData t) => Scaffold(
        body: SafeArea(
          child: PageBody(
            maxWidth: 620,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const SizedBox(height: 24),
              const Icon(Icons.key_rounded, size: 56, color: Brand.aqua),
              const SizedBox(height: 12),
              Text('Guarde seu código de recuperação', style: t.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Se você esquecer a senha, este código permite criar uma nova, mesmo sem internet. '
                'Ele aparece só agora: anote, imprima ou guarde em local seguro.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    _recoveryCode!,
                    textAlign: TextAlign.center,
                    style: t.textTheme.headlineMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 2, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => copyToClipboard(context, _recoveryCode!),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar código'),
              ),
              CheckboxListTile(
                value: _saved,
                onChanged: (v) => setState(() => _saved = v ?? false),
                title: const Text('Guardei o código em local seguro'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saved ? () => context.appRead.init() : null,
                child: const Text('Ir para o login'),
              ),
            ]),
          ),
        ),
      );
}
