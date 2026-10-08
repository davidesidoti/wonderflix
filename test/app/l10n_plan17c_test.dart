import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.profilesEditImage, 'Modifica immagine');
    expect(it.settingsChangeImage, 'Cambia immagine');
    expect(it.profileImageTitle, 'Immagine del profilo');
    expect(it.profileImageAvatars, 'Avatar');
    expect(it.profileImageFromPc, 'Dal PC');
    expect(it.profileImageUseAvatar, 'Usa questo');
    expect(it.profileImageChoose, 'Scegli un\'immagine…');
    expect(it.profileImageUseFile, 'Usa questa');
    expect(it.profileImageRemove, 'Rimuovi immagine');
    expect(it.profileImageTooLarge, 'Immagine troppo grande');
    expect(it.profileImageInvalid, 'Immagine non valida');
    expect(it.profileImageForbidden,
        'Non hai il permesso di cambiare l\'immagine');
    expect(it.profileImageFailed, 'Caricamento non riuscito');
    expect(it.profileImageFiles, 'Immagini');
    expect(it.profileImageZoom, 'Ingrandimento');
    expect(it.profileImageGalleryItem(4), 'Avatar 4');
    expect(en.profileImageGalleryItem(4), 'Avatar 4');
    expect(en.profileImageTitle, 'Profile picture');
    expect(en.settingsChangeImage, 'Change picture');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.profilesEditImage,
        l.settingsChangeImage,
        l.profileImageTitle,
        l.profileImageAvatars,
        l.profileImageFromPc,
        l.profileImageUseAvatar,
        l.profileImageChoose,
        l.profileImageUseFile,
        l.profileImageRemove,
        l.profileImageTooLarge,
        l.profileImageInvalid,
        l.profileImageForbidden,
        l.profileImageFailed,
        l.profileImageFiles,
        l.profileImageZoom,
        l.profileImageGalleryItem(1),
      ], everyElement(isNotEmpty));
    }
  });
}
