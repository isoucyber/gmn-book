import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await context.lib.auth.login(_user.text, _pw.text);
      if (!mounted) return;
      _pw.clear();
      await context.appRead.signedIn(s);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final reason = context.app.lastSignOutReason;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = Padding(
      padding: const EdgeInsets.all(28),
      child: AutofillGroup(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!wide) ...[const Center(child: BrandMark(size: 44)), const SizedBox(height: 28)],
          Text('Entrar', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Use seu usuário ou o código da carteirinha.', style: t.textTheme.bodyMedium),
          if (reason == 'inatividade') ...[
            const SizedBox(height: 12),
            const StatusPill('Sessão encerrada por inatividade', color: Brand.warn, icon: Icons.lock_clock),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _user,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Usuário ou carteirinha', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: !_show,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _busy ? null : _login(),
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _show ? 'Ocultar senha' : 'Mostrar senha',
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _show = !_show),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Entrar'),
          ),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
              child: const Text('Criar conta de leitor'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecoveryResetScreen())),
              child: const Text('Esqueci a senha'),
            ),
          ]),
        ]),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Brand.petrolDeep, Brand.petrol],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(48),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      const BrandMark(size: 56, light: true),
                      const SizedBox(height: 24),
                      Text('Biblioteca escolar organizada,\nmesmo sem internet.',
                          style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w300)),
                      const SizedBox(height: 16),
                      const Text('Acervo, empréstimos, prazos e backups — tudo salvo neste computador.',
                          style: TextStyle(color: Color(0xFFB9D6DA))),
                    ]),
                  ),
                ),
                SizedBox(width: 460, child: Center(child: SingleChildScrollView(child: form))),
              ])
            : Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: form))),
      ),
    );
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _enr = TextEditingController();
  final _cls = TextEditingController();
  final _gName = TextEditingController();
  final _gPhone = TextEditingController();
  bool _minor = false;
  bool _consent = false;
  bool _gConsent = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final active = await context.lib.auth.signup(SignupData(
        name: _name.text,
        username: _user.text,
        password: _pw.text,
        enrollment: _enr.text,
        className: _cls.text,
        isMinor: _minor,
        guardianName: _gName.text,
        guardianPhone: _gPhone.text,
        consent: _consent,
        guardianConsent: _gConsent,
      ));
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Cadastro enviado'),
          content: Text(active
              ? 'Sua conta está ativa. Faça login com seu usuário e senha.'
              : 'Sua conta será liberada após a aprovação da biblioteca.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta de leitor')),
      body: PageBody(
        maxWidth: 620,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nome completo *'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Obrigatório' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _user, decoration: const InputDecoration(labelText: 'Usuário *'),
                validator: (v) {
                  try {
                    AuthService.validateUsername(v?.trim() ?? '');
                    return null;
                  } catch (e) {
                    return errorText(e);
                  }
                }),
            const SizedBox(height: 12),
            TextFormField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Senha * (mín. 6)'),
                validator: (v) => (v ?? '').length < 6 ? 'Mínimo de 6 caracteres' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _enr, decoration: const InputDecoration(labelText: 'Matrícula (opcional)')),
            const SizedBox(height: 12),
            TextFormField(controller: _cls, decoration: const InputDecoration(labelText: 'Turma (opcional)')),
            SwitchListTile(
              value: _minor,
              onChanged: (v) => setState(() => _minor = v),
              title: const Text('Sou menor de 18 anos'),
            ),
            if (_minor) ...[
              TextFormField(controller: _gName, decoration: const InputDecoration(labelText: 'Nome do responsável *'),
                  validator: (v) => _minor && (v ?? '').trim().isEmpty ? 'Obrigatório para menores' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _gPhone, decoration: const InputDecoration(labelText: 'Telefone do responsável (opcional)')),
              CheckboxListTile(
                value: _gConsent,
                onChanged: (v) => setState(() => _gConsent = v ?? false),
                title: const Text('Meu responsável autorizou este cadastro'),
              ),
            ],
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text('Li e aceito o termo de uso e privacidade'),
              subtitle: const Text(
                  'Seus dados ficam apenas no aparelho da biblioteca e são usados só para controlar empréstimos. '
                  'Você pode pedir a correção ou a anonimização dos seus dados.'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enviar cadastro'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Redefinicao de senha de administrador/auxiliar pelo codigo de recuperacao.
class RecoveryResetScreen extends StatefulWidget {
  const RecoveryResetScreen({super.key});
  @override
  State<RecoveryResetScreen> createState() => _RecoveryResetScreenState();
}

class _RecoveryResetScreenState extends State<RecoveryResetScreen> {
  final _user = TextEditingController();
  final _code = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _newCode;

  Future<void> _submit() async {
    if (_pw.text != _pw2.text) {
      showError(context, 'As senhas não conferem.');
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await context.lib.auth.resetWithRecoveryCode(_user.text, _code.text, _pw.text);
      setState(() => _newCode = c);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar acesso')),
      body: PageBody(
        maxWidth: 560,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (_newCode == null) ...[
            const Text(
                'Administradores e auxiliares podem redefinir a senha com o código de recuperação recebido no cadastro. '
                'Leitores devem pedir à biblioteca uma nova senha.'),
            const SizedBox(height: 16),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Usuário')),
            const SizedBox(height: 12),
            TextField(controller: _code, decoration: const InputDecoration(labelText: 'Código de recuperação', hintText: 'XXXX-XXXX-XXXX-XXXX')),
            const SizedBox(height: 12),
            TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha')),
            const SizedBox(height: 12),
            TextField(controller: _pw2, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme a nova senha')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Redefinir senha'),
            ),
          ] else ...[
            const Icon(Icons.check_circle, color: Brand.ok, size: 48),
            const SizedBox(height: 8),
            Text('Senha redefinida.', style: t.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('O código antigo deixou de valer. Guarde o NOVO código de recuperação:', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SelectableText(_newCode!, textAlign: TextAlign.center,
                    style: t.textTheme.headlineSmall?.copyWith(fontFamily: 'monospace', letterSpacing: 2)),
              ),
            ),
            TextButton.icon(onPressed: () => copyToClipboard(context, _newCode!), icon: const Icon(Icons.copy), label: const Text('Copiar')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Voltar ao login')),
          ],
        ]),
      ),
    );
  }
}

class ForcedPasswordChangeScreen extends StatelessWidget {
  const ForcedPasswordChangeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Defina uma nova senha'),
          actions: [TextButton(onPressed: () => context.appRead.signOut(), child: const Text('Sair'))],
        ),
        body: const PageBody(
          maxWidth: 520,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: ChangePasswordForm(
              intro: 'Sua conta foi criada ou redefinida pela biblioteca. Por segurança, escolha uma senha pessoal.',
            ),
          ),
        ),
      );
}

class ChangePasswordForm extends StatefulWidget {
  const ChangePasswordForm({super.key, this.intro, this.onDone});
  final String? intro;
  final VoidCallback? onDone;
  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _cur = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (_pw.text != _pw2.text) {
      showError(context, 'As senhas não conferem.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.lib.auth.changePassword(context.session, _cur.text, _pw.text);
      if (!mounted) return;
      showInfo(context, 'Senha alterada.');
      context.appRead.passwordChanged();
      widget.onDone?.call();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (widget.intro != null) ...[Text(widget.intro!), const SizedBox(height: 16)],
        TextField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Senha atual')),
        const SizedBox(height: 12),
        TextField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Nova senha')),
        const SizedBox(height: 12),
        TextField(controller: _pw2, obscureText: true, decoration: const InputDecoration(labelText: 'Confirme a nova senha')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar nova senha'),
        ),
      ]);
}
