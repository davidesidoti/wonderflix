import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

/// Le chiavi del piano 24c (Task 1).
const _keys = [
  'itemActionEditMetadata',
  'itemActionIdentify',
  'itemActionRefresh',
  'itemActionImages',
  'editMetadataTitle',
  'editFieldName',
  'editFieldOriginalTitle',
  'editFieldSortName',
  'editFieldTagline',
  'editFieldOverview',
  'editFieldYear',
  'editFieldPremiereDate',
  'editFieldGenres',
  'editFieldAddGenre',
  'editFieldRating',
  'editRatingNone',
  'editLockField',
  'editUnlockField',
  'editLockAll',
  'editLockAllHint',
  'editLockAllHintFolder',
  'editSave',
  'editSaved',
  'editNoPermission',
  'identifyTitle',
  'identifyName',
  'identifyYear',
  'identifyTmdb',
  'identifyImdb',
  'identifyTvdb',
  'identifySearch',
  'identifyNoResults',
  'identifyConfirm',
  'identifyConfirmNoImages',
  'identifyReplaceImages',
  'identifyUnlock',
  'identifyApply',
  'identifyWorking',
  'identifyDone',
  'identifyStillWorking',
  'refreshTitle',
  'refreshMissing',
  'refreshReplaceAll',
  'refreshAlsoImages',
  'refreshStart',
  'refreshStarted',
  'imagesTitle',
  'imagesPoster',
  'imagesBackdrop',
  'imagesEpisode',
  'imagesCurrent',
  'imagesNone',
  'imagesAllLanguages',
  'imagesMore',
  'imagesUse',
  'imagesUpload',
  'imagesFileTypes',
  'imagesFileTooLarge',
  'imagesSaved',
  'imagesNoResults',
  'reportShortcutIdentify',
  'reportShortcutEdit',
];

Map<String, dynamic> _arb(String name) =>
    jsonDecode(File('l10n/app_$name.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('tutte le chiavi del piano 24c ci sono, non vuote, in it ed en', () {
    for (final lang in ['it', 'en']) {
      final arb = _arb(lang);
      for (final key in _keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$lang: manca $key');
        expect((value as String).trim(), isNotEmpty, reason: '$lang: $key vuota');
      }
    }
  });

  test('testi italiani e segnaposto', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.itemActionRefresh, 'Aggiorna metadati…');
    expect(it.editLockAllHint,
        'Un aggiornamento dei metadati non cambierà niente di questo titolo');
    expect(it.identifyConfirm('Dark'),
        'Sostituire metadati e immagini con quelli di Dark?');
    expect(it.identifyStillWorking,
        'Jellyfin sta ancora lavorando: ricarica tra poco');
    expect(it.imagesFileTooLarge, 'Il file supera 10 MB');
    expect(it.identifyConfirmNoImages('Dark'),
        'Sostituire i metadati con quelli di Dark?');
    expect(it.editLockAllHintFolder, contains('stagioni ed episodi'));
    expect(en.identifyConfirm('Dark'), contains('Dark'));
    expect(en.identifyConfirmNoImages('Dark'), contains('Dark'));
  });
}
