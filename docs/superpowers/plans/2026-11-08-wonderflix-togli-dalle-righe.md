# Togliere titoli da "Prossimi episodi" e "Continua a guardare"

Piano breve, approvato in chat il 2026-11-08 (niente spec: modifica piccola, solo app, plugin invariato).

## Perché

Le prove lasciano nella Home serie ed episodi che all'utente non interessano. Jellyfin non ha un "nascondi da Prossimi episodi": la riga viene da `/Shows/NextUp`, calcolata dalla cronologia. "Continua a guardare" invece è `/UserItems/Resume`: un titolo esce se il punto di ripresa torna a 0.

## Comportamento deciso con l'utente

**Prossimi episodi**: lista di WonderFlix per utente, nelle `DisplayPreferences` (`CustomPrefs` dell'oggetto `wonderflix-home`, come la Home).
- Si toglie con la × nell'anteprima della card (desktop/web/touch: `CardPreviewExtra`, come "Non mi interessa" dei consigli) e con "Togli da Prossimi episodi" nel menu "⋯" della scheda della serie (anche TV).
- Si salva la coppia serie → episodio proposto in quel momento. La serie torna da sola quando Jellyfin propone un episodio diverso (ne ha guardato uno). Rivedere un episodio vecchio non la fa tornare.
- Dal menu "⋯" della serie, se è tolta: "Rimetti in Prossimi episodi".
- jellyfin-web continua a mostrarla (accettato).

**Continua a guardare**: via di Jellyfin, punto di ripresa a 0 (`POST /UserItems/{itemId}/UserData?userId=…` con `{"PlaybackPositionTicks": 0}`, risponde `UserItemData`).
- Si toglie con la × sulla card e con "Togli da Continua a guardare" nel menu "⋯" di film ed episodi con un punto di ripresa. Sulla TV gli episodi non hanno il "⋯": la voce sta anche nel "⋯" della serie, per l'episodio che `seriesNextEpisodeProvider` propone quando ha un punto di ripresa.
- Sparisce ovunque e torna solo facendolo ripartire. Lo stato "visto" non si tocca mai.

**Per entrambe** (scelta di Claude): dopo aver tolto, SnackBar "Tolto da <riga>" con "Annulla" (Prossimi episodi: rimette la serie; Continua a guardare: rimanda il punto di ripresa di prima). Se la chiamata fallisce, il titolo torna e una SnackBar lo dice.

**Fuori**: pagina "titoli nascosti", altre righe della Home, plugin.

## Codice esistente da riusare

- `app/lib/core/jellyfin/display_preferences_api.dart`: `_update` rilegge e riscrive l'oggetto intero, le altre voci restano. Aggiungere qui la voce nuova.
- `app/lib/features/recommendations/recommendation_dismissals.dart`: schema da copiare (Notifier, tolto subito, torna se la chiamata fallisce, si azzera al cambio utente).
- `app/lib/features/home/home_row_view.dart`: `_recommended` filtra con il provider e passa `CardPreviewExtra(onDismiss:, dismissTooltip:)`; `_landscapes` serve resume e nextUp.
- `app/lib/ui/landscape_card.dart`: oggi `CardPreviewHost(item:, heroSource:, child:)` senza `extra`; aggiungere `previewExtra` come in `poster_card.dart`.
- `app/lib/features/library/user_data.dart`: `UserDataOverrides` (modifica subito, conferma o torna indietro) e `watchUserData`. Il punto di ripresa va fatto passare da qui, così card, riga e pulsante "Riprendi" si aggiornano insieme.
- `app/lib/core/jellyfin/library_api.dart`: `nextUp(...)`, `resume(...)`, `_toggle`.
- `app/lib/features/home/home_providers.dart` `_libraryRow`: nextUp con `limit: homeRowLimit` (20) e `dateCutoff: nextUpCutoff(clock.now())`.
- `app/lib/features/detail/item_actions_menu.dart`: `ItemActionsButton(extra: [...])` (voci `ExtraItemAction` in cima). `app/lib/features/detail/detail_header.dart`: due chiamate, riga ~320 (con `extra`) e riga ~390 (`tvOnly: tv`, senza `extra`): la voce nuova deve stare in tutte e due.
- `app/lib/features/detail/detail_providers.dart`: `seriesNextEpisodeProvider` (con `enableResumable: true`).
- `jellyfinIdKey` (`core/jellyfin/json_fields.dart`) per confrontare gli id.

## Task 1: Prossimi episodi

1. `DisplayPreferencesApi`: voce `nextUpHidden`, valore `serieId:episodioId` separati da virgole. `readNextUpHidden(userId) → Map<String, String>` (chiavi e valori `jellyfinIdKey`) e `writeNextUpHidden(userId, map)` (mappa vuota → voce rimossa). Le altre voci di `CustomPrefs` restano.
2. `features/home/next_up_hidden.dart`: Notifier per utente (si azzera e si rilegge al cambio utente; lettura fallita → mappa vuota, log info). `hide(seriesId, episodeId)` e `unhide(seriesId)`: stato subito, poi scrittura; fallita → stato di prima e `false`. Scritture una alla volta (rileggono e riscrivono tutto l'oggetto). Funzione pura `bool hiddenFromNextUp(Map<String, String> hidden, JellyfinItem episode)`: vero solo se la serie c'è con lo stesso episodio.
3. Riga: `_libraryRow` chiede `homeRowLimit * 2` episodi (commento `shortcut:`: con più di 20 serie tolte la riga si accorcia). `HomeRowView` per nextUp filtra con il provider, tiene i primi `homeRowLimit`, riga vuota → `SizedBox.shrink()` come `_recommended`. Card con × (`LandscapeCard.previewExtra`).
4. Scheda serie, menu "⋯" (entrambe le chiamate di `detail_header.dart`): provider nuovo per l'episodio della riga di quella serie, con gli stessi parametri della Home (`nextUp(seriesId:, limit: 1, dateCutoff: nextUpCutoff(...))`, senza `enableResumable`). C'è un episodio → "Togli da Prossimi episodi", oppure "Rimetti in Prossimi episodi" se la serie è tolta con quell'episodio. Niente episodio → nessuna voce.
5. Le voci tolte con un episodio diverso da quello attuale restano nella lista (commento `shortcut:`, ripulirle se la voce cresce).
6. Stringhe it/en in `app/l10n/app_it.arb` e `app_en.arb` (poi `flutter gen-l10n`): "Togli da Prossimi episodi", "Rimetti in Prossimi episodi", "Tolto da Prossimi episodi", "Annulla", errore.
7. Test: API (lettura, scrittura, altre voci intatte, voce vuota rimossa), Notifier (subito, ritorno se fallisce), `hiddenFromNextUp`, riga filtrata con × e Annulla, voci del menu "⋯".

## Task 2: Continua a guardare

1. `LibraryApi.setPlaybackPosition(userId, itemId, ticks) → UserItemData` (POST sopra).
2. `UserDataOverrides.setPlaybackPosition(item, ticks)`: stesso schema di `_toggle` (subito, conferma, torna indietro se fallisce e rilancia).
3. Riga resume in `HomeRowView`: nasconde gli elementi con punto di ripresa effettivo (`watchUserData`) a 0; card con ×; SnackBar con Annulla che rimanda i tick di prima.
4. Menu "⋯": film ed episodi con punto di ripresa > 0 → "Togli da Continua a guardare" (testata della scheda in tutte e due le chiamate, riga episodio in `series_detail_view.dart`). Serie: se `seriesNextEpisodeProvider` ha un episodio con punto di ripresa, la stessa voce per quell'episodio.
5. Stringhe it/en ("Togli da Continua a guardare", "Tolto da Continua a guardare", errore).
6. Test: API (percorso, query, corpo), override (subito, ritorno se fallisce), riga filtrata con × e Annulla, voci del menu.

## Fine

- `docs/RELEASING.md`: riga nella checklist di prova manuale (togliere/rimettere da PC e da TV, ritorno dopo aver guardato un episodio, Annulla).
- `flutter gen-l10n`, `flutter analyze`, `flutter test` verdi. Revisione finale. Build exe Windows e APK firmato con la chiave di release per la prova dell'utente.
