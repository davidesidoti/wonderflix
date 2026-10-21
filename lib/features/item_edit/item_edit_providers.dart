import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/item_edit_api.dart';

/// Con il token dell'admin: il server controlla che lo sia.
final itemEditApiProvider = Provider<ItemEditApi>(
    (ref) => ItemEditApi(ref.watch(jellyfinHttpProvider)));

/// Estensioni delle immagini che Jellyfin accetta dall'editor.
const imageFileExtensions = ['jpg', 'jpeg', 'png'];

/// Dimensione massima di un file immagine: 10 MB.
const maxImageFileBytes = 10485760;

/// Un file scelto: nome e dimensione si leggono prima del contenuto.
class PickedImageFile {
  const PickedImageFile({
    required this.name,
    required this.length,
    required this.read,
  });

  final String name;
  final int length;
  final Future<Uint8List> Function() read;
}

/// Sceglie un'immagine dal PC; `null` se si annulla. [label] è il nome del
/// filtro nella finestra di Windows.
typedef ImageFilePicker = Future<PickedImageFile?> Function(String label);

/// Con `file_selector` (nei test si sostituisce: apre una finestra di
/// sistema).
final imageFilePickerProvider = Provider<ImageFilePicker>(
  (ref) => (label) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: imageFileExtensions),
      ],
    );
    if (file == null) return null;
    return PickedImageFile(
      name: file.name,
      length: await file.length(),
      read: file.readAsBytes,
    );
  },
);
