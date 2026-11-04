import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Leitura de codigo de barras / QR / ISBN pela camera (Android).
/// No Windows, leitores USB funcionam como teclado: basta focar o campo.
bool get cameraScanAvailable => Platform.isAndroid || Platform.isIOS;

Future<String?> scanCode(BuildContext context, {String title = 'Aponte para o código'}) {
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ScannerPage(title: title)));
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage({required this.title});
  final String title;
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(tooltip: 'Lanterna', icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
          ],
        ),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code == null || code.isEmpty) return;
              _done = true;
              Navigator.of(context).pop(code);
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ]),
      );
}

/// Botao de camera para campos de codigo (aparece so onde ha camera).
class ScanButton extends StatelessWidget {
  const ScanButton({super.key, required this.onCode});
  final ValueChanged<String> onCode;
  @override
  Widget build(BuildContext context) {
    if (!cameraScanAvailable) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Ler com a câmera',
      icon: const Icon(Icons.photo_camera_outlined),
      onPressed: () async {
        final c = await scanCode(context);
        if (c != null) onCode(c);
      },
    );
  }
}
