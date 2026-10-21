import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estensioni dei file di sottotitoli che il plugin accetta.
const subtitleFileExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub'];

/// Dimensione massima di un file di sottotitoli: 2 MiB, come il plugin.
const maxSubtitleFileBytes = 2097152;

/// Un file scelto: nome e dimensione si leggono prima del contenuto.
class PickedSubtitleFile {
  const PickedSubtitleFile({
    required this.name,
    required this.length,
    required this.read,
  });

  final String name;
  final int length;
  final Future<Uint8List> Function() read;
}

/// Sceglie un file di sottotitoli dal PC; `null` se si annulla. [label] è il
/// nome del filtro nella finestra di Windows.
typedef SubtitleFilePicker = Future<PickedSubtitleFile?> Function(String label);

/// Con `file_selector` (nei test si sostituisce: apre una finestra di
/// sistema).
final subtitleFilePickerProvider = Provider<SubtitleFilePicker>(
  (ref) => (label) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: subtitleFileExtensions),
      ],
    );
    if (file == null) return null;
    return PickedSubtitleFile(
      name: file.name,
      length: await file.length(),
      read: file.readAsBytes,
    );
  },
);
