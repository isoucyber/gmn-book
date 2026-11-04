import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Seletor de arquivos nativo (file_picker 13+). No Android usa o seletor do
/// sistema (acesso a pastas e restrito); no Windows abre o dialogo padrao.
class FileIO {
  static Future<({String name, Uint8List bytes})?> pickFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  }

  static Future<({String name, Uint8List bytes})?> pickImage() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  }

  /// Salva em local escolhido pelo usuario. Retorna o local (ou null se cancelado).
  static Future<String?> saveFile(String fileName, Uint8List bytes, {String title = 'Salvar arquivo'}) async {
    final uri = await FilePicker.saveFile(dialogTitle: title, fileName: fileName, bytes: bytes);
    if (uri == null) return null;
    if (uri.scheme == 'file' || uri.scheme.isEmpty) {
      // No desktop garante a gravacao completa do arquivo.
      final file = File(uri.scheme.isEmpty ? uri.toString() : uri.toFilePath());
      if (!await file.exists() || await file.length() != bytes.length) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return file.path;
    }
    return Uri.decodeFull(uri.toString());
  }
}
