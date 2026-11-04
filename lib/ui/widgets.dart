import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../services/circulation_service.dart';
import 'app_state.dart';
import 'theme.dart';

/// Carrega dados de forma assincrona e recarrega quando os dados do app
/// mudam (AppState.dataVersion) ou quando [deps] muda.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder, this.deps});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;
  final Object? deps;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future;
  int _version = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final v = context.app.dataVersion;
    if (v != _version) {
      _version = v;
      _future = widget.load();
    }
  }

  @override
  void didUpdateWidget(covariant AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (old.deps != widget.deps) _future = widget.load();
  }

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: 'Não foi possível carregar',
            message: errorText(snap.error),
            action: OutlinedButton(onPressed: _reload, child: const Text('Tentar novamente')),
          );
        }
        if (!snap.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

String errorText(Object? e) {
  if (e is AppException) return e.message;
  final s = e.toString();
  return s.length > 300 ? '${s.substring(0, 300)}…' : s;
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(errorText(e)),
    backgroundColor: Theme.of(context).colorScheme.error,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 6),
  ));
}

void showInfo(BuildContext context, String msg, {SnackBarAction? action, int seconds = 4}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    action: action,
    duration: Duration(seconds: seconds),
  ));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirmar', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pede um texto (ex.: justificativa) ou senha.
Future<String?> promptText(BuildContext context, String title,
    {String? message, String label = '', bool obscure = false, String ok = 'Confirmar', String? initial}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) ...[Text(message), const SizedBox(height: 12)],
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: obscure,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(ok)),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: t.colorScheme.primary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ]),
      );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(builder: (context, box) {
          // Em celulares (cartao estreito) o icone fica acima do numero.
          final compact = box.maxWidth < 210;
          final iconBox = Container(
            width: compact ? 32 : 44,
            height: compact ? 32 : 44,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: c, size: compact ? 18 : 24),
          );
          final texts = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(label, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          );
          return Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: compact
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    iconBox,
                    const Spacer(),
                    texts,
                  ])
                : Row(children: [iconBox, const SizedBox(width: 14), Expanded(child: texts)]),
          );
        }),
      ),
    );
  }
}

Color loanStateColor(LoanState s, BuildContext context) => switch (s) {
      LoanState.overdue => Theme.of(context).colorScheme.error,
      LoanState.nearDue => Brand.warn,
      LoanState.active => Brand.ok,
      LoanState.returned => Theme.of(context).colorScheme.outline,
      LoanState.cancelled => Theme.of(context).colorScheme.outline,
    };

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
      );
}

/// Area de conteudo com largura maxima confortavel em telas grandes.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1200});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline))),
        Expanded(child: SelectableText(value == null || value!.isEmpty ? '—' : value!)),
      ]),
    );
  }
}

Future<void> copyToClipboard(BuildContext context, String text, {String done = 'Copiado.'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showInfo(context, done);
}

/// Logotipo desenhado (sem depender de arquivos externos).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.light = false});
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Brand.petrol, Brand.aqua], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(Icons.menu_book_rounded, color: Colors.white, size: size * 0.6),
        ),
        SizedBox(width: size * 0.3),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'GMN ', style: TextStyle(fontWeight: FontWeight.w800, color: light ? Colors.white : null)),
            TextSpan(text: 'BOOK', style: TextStyle(fontWeight: FontWeight.w300, color: light ? Brand.aqua : null)),
          ]),
          style: TextStyle(fontSize: size * 0.5, letterSpacing: 1.2),
        ),
      ]);
}
