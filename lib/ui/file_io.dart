import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Seletor de arquivos nativo. No Android/iOS usa o seletor do sistema
/// (acesso a pastas e restrito); no Windows abre o dialogo padrao.
class FileIO {
  static Future<({String name, Uint8List bytes})?> pickFile({List<String>? extensions}) async {
    final r = await FilePicker.platform.pickFiles(
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return null;
    return (name: f.name, bytes: bytes);
  }

  static Future<({String name, Uint8List bytes})?> pickImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    Uint8List? bytes = f.bytes;
    if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
    if (bytes == null) return null;
    return (name: f.name, bytes: bytes);
  }

  /// Salva em local escolhido pelo usuario. Retorna o caminho (ou null se cancelado).
  static Future<String?> saveFile(String fileName, Uint8List bytes, {String title = 'Salvar arquivo'}) async {
    final path = await FilePicker.platform.saveFile(dialogTitle: title, fileName: fileName, bytes: bytes);
    if (path == null) return null;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }
}
