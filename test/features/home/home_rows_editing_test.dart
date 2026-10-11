import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_rows_editing.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  const resume = HomeRowKind.resume;
  const nextUp = HomeRowKind.nextUp;
  const myList = HomeRowKind.myList;
  const sagas = HomeRowKind.continueSaga;

  group('moveRow', () {
    test('sposta alla posizione finale, contata dopo aver tolto la riga', () {
      expect(moveRow([resume, nextUp, myList], resume, 2),
          [nextUp, myList, resume]);
      expect(moveRow([resume, nextUp, myList], myList, 0),
          [myList, resume, nextUp]);
      expect(moveRow([resume, nextUp, myList], nextUp, 1),
          [resume, nextUp, myList]);
    });

    test('fuori dai limiti va al bordo; una riga che non c\'è non cambia niente',
        () {
      expect(moveRow([resume, nextUp], resume, 9), [nextUp, resume]);
      expect(moveRow([resume, nextUp], nextUp, -3), [nextUp, resume]);
      expect(moveRow([resume, nextUp], myList, 0), [resume, nextUp]);
    });
  });

  group('keepForeignIds', () {
    test('keepForeignIds: gli id estranei restano dopo il loro vicino', () {
      expect(
          keepForeignIds(
              stored: ['resume', 'future', 'myList'],
              edited: ['myList', 'resume']),
          ['myList', 'resume', 'future']);
      expect(
          keepForeignIds(stored: ['future', 'resume'], edited: ['resume']),
          ['future', 'resume']);
      expect(
          keepForeignIds(
              stored: ['resume', 'a', 'b', 'nextUp'],
              edited: ['nextUp', 'resume']),
          ['nextUp', 'resume', 'a', 'b']);
    });

    test('niente estranei: l\'elenco com\'è; doppioni non ripetuti', () {
      expect(keepForeignIds(stored: [], edited: ['nextUp', 'resume']),
          ['nextUp', 'resume']);
      expect(
          keepForeignIds(stored: ['x', 'x', 'resume'], edited: ['resume']),
          ['x', 'resume']);
    });

    test('un estraneo in mezzo resta in mezzo, tra i suoi vicini', () {
      expect(
          keepForeignIds(
              stored: ['resume', 'F', 'nextUp'], edited: ['resume', 'nextUp']),
          ['resume', 'F', 'nextUp']);
    });

    test('un id mostrato ripetuto in stored non sposta gli estranei', () {
      expect(
          keepForeignIds(
              stored: ['resume', 'x', 'resume', 'y'], edited: ['resume']),
          ['resume', 'x', 'y']);
    });
  });

  test('homeUserPrefsToSave: conserva righe e nascoste che l\'elenco non mostra',
      () {
    const stored = HomeUserPrefs(
      rows: ['myList', 'continueSaga', 'future', 'resume'],
      hidden: ['continueSaga', 'future'],
    );
    // L'admin ha spento continueSaga: l'elenco mostra solo resume e myList.
    final prefs = homeUserPrefsToSave(
        rows: [resume, myList], hidden: {myList}, stored: stored);
    expect(prefs.rows, ['resume', 'myList', 'continueSaga', 'future']);
    expect(prefs.hidden, ['myList', 'continueSaga', 'future']);
  });

  test('homeUserPrefsToSave: senza ritocchi salvati, l\'elenco', () {
    final prefs = homeUserPrefsToSave(
        rows: [nextUp, resume], hidden: {}, stored: HomeUserPrefs.none);
    expect(prefs.rows, ['nextUp', 'resume']);
    expect(prefs.hidden, isEmpty);
  });

  test('homeUserPrefsToSave: una riga mostrata e non più nascosta esce da '
      'hidden; un estraneo doppio resta una volta', () {
    final prefs = homeUserPrefsToSave(
        rows: [resume, nextUp],
        hidden: {},
        stored: const HomeUserPrefs(
            rows: ['resume', 'nextUp'], hidden: ['resume', 'X', 'X']));
    expect(prefs.hidden, ['X']);
  });

  group('Home per tutti', () {
    test('mai impostata: tutte accese, nell\'ordine predefinito', () {
      expect(adminEditorRows(null), HomeRowKind.values);
      expect(adminEditorOn(null), HomeRowKind.values.toSet());
      expect(adminRowsEffective(null),
          [for (final row in HomeRowKind.values) row.id]);
    });

    test('mai impostata: la lista è una copia, il chiamante può cambiarla', () {
      final rows = adminEditorRows(null);
      rows.removeAt(0);
      expect(rows, hasLength(HomeRowKind.values.length - 1));
      expect(HomeRowKind.values, hasLength(HomeRowKind.values.length));
    });

    test('accese nell\'ordine dell\'admin, spente in fondo nell\'ordine '
        'predefinito', () {
      final rows = adminEditorRows(['myList', 'resume', 'bogus']);
      expect(rows.take(2), [myList, resume]);
      expect(rows.skip(2).first, nextUp);
      expect(rows, hasLength(HomeRowKind.values.length));
      expect(adminEditorOn(['myList', 'resume']), {myList, resume});
      expect(adminRowsEffective(['myList', 'bogus', 'resume']),
          ['myList', 'resume']);
    });

    test('tutte spente: nessuna accesa, tutte nell\'elenco', () {
      expect(adminEditorRows([]), HomeRowKind.values);
      expect(adminEditorOn([]), isEmpty);
      expect(adminRowsToSave(HomeRowKind.values, {}), isEmpty);
    });

    test('da salvare: le accese nell\'ordine dell\'elenco', () {
      expect(adminRowsToSave([myList, sagas, resume], {resume, myList}),
          ['myList', 'resume']);
    });
  });

  group('testi', () {
    final l = lookupAppLocalizations(const Locale('it'));

    test('nomi delle righe', () {
      expect(homeRowName(l, resume), l.homeContinueWatching);
      expect(homeRowName(l, HomeRowKind.becauseYouWatched),
          'Perché hai visto…');
      expect(homeRowName(l, myList), l.navMyList);
      for (final row in HomeRowKind.values) {
        expect(homeRowName(l, row), isNotEmpty);
      }
    });

    test('fonti: solo le righe esterne', () {
      expect(homeRowSource(l, HomeRowKind.requests), 'da Seerr');
      expect(homeRowSource(l, HomeRowKind.upcomingSeries), 'da Sonarr');
      expect(homeRowSource(l, HomeRowKind.upcomingMovies), 'da Radarr');
      expect(homeRowSource(l, resume), isNull);
    });

    test('motivi', () {
      expect(homeRowGateReason(l, HomeRowGate.available), isNull);
      expect(homeRowGateReason(l, HomeRowGate.seerrOff),
          'Seerr non è configurato');
      expect(homeRowGateReason(l, HomeRowGate.noSeerrAccount),
          'Collega il tuo account a Seerr');
      expect(homeRowGateReason(l, HomeRowGate.sagasOff),
          'Serve il plugin 1.5.0');
      expect(homeRowGateReason(l, HomeRowGate.sonarrOff),
          'Sonarr non è configurato');
      expect(homeRowGateReason(l, HomeRowGate.radarrOff),
          'Radarr non è configurato');
    });
  });
}
