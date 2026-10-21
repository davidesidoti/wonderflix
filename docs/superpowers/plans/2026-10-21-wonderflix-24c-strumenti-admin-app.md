# WonderFlix — Piano 24c: strumenti admin per i metadati, app 0.19.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** gli strumenti solo admin della Spec R (§7.8–7.11), nel menu "⋯" del 24b:
- **Modifica metadati**;
- **Identifica** (film e serie);
- **Aggiorna metadati**;
- **Locandina e sfondo**;
- le scorciatoie "Identifica" e "Modifica metadati" nel riquadro delle segnalazioni;
- app **0.19.0**, build per la prova a mano, poi release.

Tutto parla **direttamente con Jellyfin** con il token dell'admin: il plugin non serve, a parte le scorciatoie del riquadro, che ci sono già solo con `reports`.

**Architecture:**
- **Nucleo:** `lib/core/jellyfin/item_edit_api.dart` (`ItemEditApi`) con i modelli in `item_edit_models.dart`, e un timeout per singola richiesta in `JellyfinHttp.post`.
- **Finestre:** in `lib/features/item_edit/` (`edit_metadata_dialog.dart`, `identify_dialog.dart`, `refresh_metadata_dialog.dart`, `images_dialog.dart`). Prendono l'**id** dell'item e leggono da sole quello che serve, così le apre anche il riquadro delle segnalazioni.
- **Dopo ogni cambio** si chiama `libraryRevisionProvider.notifier.bump()`, che rilegge le schede aperte.

**Tech Stack:** Flutter 3.47.5 (Windows), Dart, Riverpod 3, dio (`JellyfinHttp`), `file_selector`, lucide_icons_flutter, `flutter_test`, `fake_async`. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md` (§2 tabella Jellyfin, §3 decisioni 15, 16, 19, 20, 22, §7.2, §7.8–7.11, §8, §11.2, §11.3 passo 4, §12, §13). Il 24b è su `main` (app 0.18.0 rilasciata).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 6):
1. **Modifica = andata e ritorno del JSON grezzo.**
   - `ItemEditApi.rawItem` legge `GET /Items/{id}?userId=` come `Map`. La finestra cambia solo le chiavi dei campi modificati e rimanda la `Map` intera con `POST /Items/{id}`, come jellyfin-web.
   - Verificato sul sorgente 10.11.9 (`ItemUpdateController.UpdateItem`): il server riscrive dal DTO anche `Tags`, `ProviderIds`, `Studios`, `People`, `Genres` e altri campi, quindi una `Map` parziale li cancellerebbe. I dati dell'utente (visto, preferito) non si toccano.
   - Si chiude così il punto aperto del §12.
2. **Cosa si può bloccare:** Jellyfin blocca singolarmente solo i campi di `MetadataField`, e fra quelli dell'editor sono `Name`, `Overview`, `Genres` e `OfficialRating`.
   - Solo questi quattro hanno il lucchetto, e si aggiungono da soli a `LockedFields` quando cambiano (spec, decisione 15).
   - Titolo originale, titolo per l'ordinamento, tagline, anno e data di uscita non si possono bloccare da soli: per loro c'è l'interruttore **"Blocca tutti i metadati"** (`LockData`).
   - La spec, decisione 15, si corregge nel Task 6.
3. **Campi dell'editor:**
   - titolo (`Name`), titolo originale (`OriginalTitle`), titolo per l'ordinamento (`ForcedSortName`);
   - tagline (`Taglines[0]`; non per episodi e stagioni);
   - trama (`Overview`);
   - anno (`ProductionYear`) e data di uscita (`PremiereDate`, solo la data);
   - generi (`Genres`);
   - classificazione per età (`OfficialRating`, dal menu di `ParentalRatingOptions` di `GET /Items/{id}/MetadataEditor`, più "nessuna").
4. **Identifica: timeout lungo.**
   - `JellyfinHttp.post` prende un parametro facoltativo `Duration? receiveTimeout` (dio `Options(receiveTimeout:)`); `ItemEditApi.applyIdentify` usa **3 minuti** (`identifyApplyTimeout`).
   - Un `ServerUnreachableException` durante `Apply` (che con dio è anche il timeout) dà "Jellyfin sta ancora lavorando: ricarica tra poco", non un errore: la scheda si rilegge lo stesso.
5. **Identifica e campi bloccati** (spec, decisione 19): se l'item ha `LockData` o `LockedFields` non vuoti, la conferma mostra "Sblocca i campi modificati a mano", attiva di base. Con la casella attiva, prima di `Apply` si manda la `Map` grezza con `LockData: false` e `LockedFields: []`.
6. **"Aggiorna metadati" è una piccola finestra, non un sottomenu**, con due scelte e la casella "anche le immagini". Un sottomenu dentro il `PopupMenuButton` del 24b non è previsto dal widget Material.
7. **Sfondo in prima posizione** (spec, decisione 16).
   - Verificato su 10.11.9 (`ImageSaver`): uno sfondo scaricato o caricato senza indice va in fondo (indice = numero degli sfondi di prima). Dopo, l'app rilegge `BackdropImageTags` e, se gli sfondi sono più di uno, chiama `POST /Items/{id}/Images/Backdrop/{ultimo}/Index?newIndex=0`.
   - `SwapImagesAsync` scambia due file e **non fa niente se uno dei due non è un file locale** (limite di Jellyfin): in quel caso lo sfondo nuovo resta in fondo, senza errore. Si scrive nella spec.
8. **Schede delle immagini per livello** (spec, decisione 22):
   - film e serie: Locandina (`Primary`) e Sfondo (`Backdrop`);
   - stagioni: solo Locandina;
   - episodi: solo "Immagine" (`Primary`, 16:9).
9. **Dopo ogni cambio** (salvataggio, identifica, immagini) `libraryRevisionProvider.notifier.bump()`. "Aggiorna metadati" è in coda: il bump si fa 10 s dopo (`refreshReloadDelay`).
10. **Scorciatoie del riquadro** (spec, decisione 20): `ReportShortcut` prende `identify` (`Metadata` su `movie`/`series`) e `editMetadata` (`Metadata` su `season`/`episode`), oltre a `subtitles`.
11. **Release 0.19.0 non obbligatoria**; nessun plugin nuovo.

## Global Constraints

- App **0.19.0** (`pubspec.yaml`). Nessuna dipendenza nuova.
- **Jellyfin diretto**, solo admin (il server lo controlla: `RequiresElevation`):

| Chiamata | Uso |
|---|---|
| `GET /Items/{id}?userId=` | `Map` grezza |
| `POST /Items/{id}` | la `Map` intera |
| `GET /Items/{id}/MetadataEditor` | `ParentalRatingOptions: [{Name, Value}]` |
| `POST /Items/RemoteSearch/Movie` e `/Series` | corpo `{SearchInfo: {Name, Year?, ProviderIds: {Tmdb?, Imdb?, Tvdb?}}, ItemId, IncludeDisabledProviders: false}`; risposta `[{Name, ProductionYear?, ProviderIds, ImageUrl?, SearchProviderName?, Overview?}]` |
| `POST /Items/RemoteSearch/Apply/{id}?replaceAllImages=` | corpo il risultato scelto **così com'è** (la `Map` ricevuta), 204 |
| `POST /Items/{id}/Refresh?metadataRefreshMode=FullRefresh&imageRefreshMode=FullRefresh&replaceAllMetadata=&replaceAllImages=` | 204 |
| `GET /Items/{id}/RemoteImages?type=&startIndex=&limit=&includeAllLanguages=` | `{Images: [{ProviderName, Url, ThumbnailUrl?, Width?, Height?, Language?, CommunityRating?, Type}], TotalRecordCount}` |
| `POST /Items/{id}/RemoteImages/Download?type=&imageUrl=` | 204 |
| `POST /Items/{id}/Images/{type}` | corpo l'immagine in **base64** (testo), `Content-Type` `image/jpeg` o `image/png`; 204 |
| `POST /Items/{id}/Images/Backdrop/{index}/Index?newIndex=0` | 204 |

- **Valori:**
  - timeout di Apply **3 min** (`identifyApplyTimeout`);
  - rilettura dopo Aggiorna **10 s** (`refreshReloadDelay`);
  - immagini **30** alla volta (`remoteImagesPageSize`);
  - file immagine al massimo **10 MB** (10 485 760 byte), estensioni `jpg jpeg png`.
- **Campi bloccabili:** `Name`, `Overview`, `Genres`, `OfficialRating` (decisione 2).
- **Testi** it/en: le chiavi e i testi italiani sono nel Task 1. Nessun testo fisso nel codice.
- **Stile:**
  - icone `LucideIcons`, colori `WfColors`, `clock.now()`, durate con `WfMotion`;
  - testi dei provider (trame, nomi) sempre come testo semplice;
  - **nei log mai titoli, trame, URL delle immagini o nomi di file**: solo id, numeri e tipo dell'errore.
- **Build per la prova a mano**, esattamente:
  `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
  `config/wonderflix.json` va copiato nel worktree dal checkout principale e non si committa.
- **Commit:** identità del repository (hash_developer); **mai** `Co-Authored-By` né "Generated with…"; mai `closes`, `fixes`, `resolves`. Niente push.
- **Processi:** **mai** terminarli per nome d'immagine; solo per PID.

## Review Focus

1. **Salvataggio che cancella dati:** la `Map` mandata con `POST /Items/{id}` è quella letta, con solo i campi cambiati; `Tags`, `ProviderIds`, `People`, `Studios` restano identici. Test: Task 2 (`il DTO mandato è quello letto con solo i campi cambiati`).
2. **Identifica lenta:** con Apply oltre i 3 minuti, o un errore di rete durante Apply, niente errore rosso, ma "Jellyfin sta ancora lavorando", e la scheda si rilegge. Test: Task 3 (`Apply che scade: messaggio e rilettura`).
3. **Doppio clic** su Salva, Applica, Usa come sfondo o Carica: una sola chiamata in volo. Test: Task 2, 3, 5 (`doppio clic: una sola chiamata`).
4. **Immagine troppo grande o formato sbagliato:** si ferma nell'app, senza chiamare Jellyfin. Test: Task 5 (`file oltre 10 MB: messaggio e nessuna chiamata`).
5. **Admin tolto mentre la finestra è aperta:** un 403 mostra "Non hai il permesso per farlo" e chiama `refreshUser()`. Test: Task 2 (`un 403 al salvataggio rilegge l'utente`).

---

## Regole per chi esegue

Le stesse del piano 24b (`docs/superpowers/plans/2026-10-21-wonderflix-24b-segnalazioni-app.md`, "Regole per chi esegue"), con:
- **worktree** `.claude/worktrees/piano-24c` (branch `piano-24c` da `main`), e `flutter gen-l10n` prima di tutto;
- **base dei test** da misurare prima del Task 1;
- **percorsi assoluti** per non toccare mai il checkout principale.

## Note tecniche verificate

Sul codice di `main` `2a1cd88` (2026-10-21) e sul sorgente di Jellyfin `v10.11.9`:
- **Menu:** `lib/features/detail/item_actions_menu.dart`:
  - `enum ItemAction { report, mediaInfo, subtitles }`;
  - `itemActionGroups(...)` con il gruppo admin `const []`, `_label`, `ItemActionsButton._run`;
  - `test/features/detail/item_actions_menu_test.dart`.
- **Riquadro:** `lib/features/reports/admin_reports_controller.dart`:
  - `enum ReportShortcut { subtitles }`, `reportShortcut(ItemReport)`;
  - `reports_banner.dart` mostra la scorciatoia (`reportShortcutSubtitles`).
- **HTTP:** `JellyfinHttp.post(path, {body, query, contentType, quietStatuses})` passa `Options(contentType:)` a dio; il timeout di ricezione è 30 s in `BaseOptions` (`jellyfin_http.dart:25-28`). Errori `ApiException` (`ForbiddenException`, `ServerErrorException(status, body)`, `ServerUnreachableException` anche per i timeout).
- **Rilettura:** `libraryRevisionProvider` (`detail_providers.dart` lo guarda in `itemProvider`, `seasonsProvider`, `episodesProvider`); `.notifier.bump()`.
- **Immagini attuali:** `imageUrlsProvider` (`lib/core/jellyfin/image_urls.dart`), `poster(item)`, `backdrop(item)`; `JellyfinItem.imageTags['Primary']`, `backdropTags`. `WfImage` per mostrarle.
- **File:** `avatarFilePickerProvider` e `subtitleFilePickerProvider` (`lib/features/subtitles/subtitle_file_picker.dart`) sono il modello del selettore iniettabile.
- **Finestre e testi:**
  - `showWfDialog`, `showWfConfirmDialog`, `capRunes`, `describeError`, `ErrorBanner`;
  - `sessionControllerProvider.notifier.refreshUser()`, letto prima delle attese (lezione del 24b);
  - l'utente da `currentUserIdProvider`;
  - finti: `FakeLibraryApi`, `testItem`, `FakeAdapter`/`FakeResponse`, `pumpApp`, `adminTestOverrides`, `testAdmin`.
- **Jellyfin 10.11.9:**
  - `UpdateItem` riscrive dal DTO `Name`, `ForcedSortName`, `OriginalTitle`, `CriticRating`, `CommunityRating`, `IndexNumber`, `ParentIndexNumber`, `Overview`, `Genres`, `Taglines` (solo il primo), `Studios`, `PremiereDate`, `ProductionYear`, `OfficialRating`, `CustomRating`, `Tags` (**non null**), `ProductionLocations`, `LockData`, `LockedFields`, `ProviderIds` (**non null**), `People` (se non null);
  - `MetadataField` = `Cast, Genres, ProductionLocations, Studios, Tags, Name, Overview, Runtime, OfficialRating`;
  - `Apply` imposta `ProviderIds` e fa `RefreshFullItem` sincrono (`FullRefresh`, `ReplaceAllMetadata`, `RemoveOldMetadata`);
  - `ImageSaver`: senza indice, per i tipi multipli l'indice è il numero delle immagini di prima;
  - `SwapImagesAsync`: no-op se un'immagine non è locale;
  - `GetRemoteImages`: `includeAllLanguages` falso di base (lingua dell'item più quelle senza lingua).

## File

| File | Responsabilità |
|---|---|
| `lib/core/jellyfin/item_edit_models.dart`, `item_edit_api.dart` (+ `jellyfin_http.dart`) | modelli, chiamate, timeout per richiesta |
| `lib/features/item_edit/item_edit_providers.dart` | `itemEditApiProvider`, `imageFilePickerProvider` |
| `lib/features/item_edit/edit_metadata_dialog.dart` | Modifica metadati |
| `lib/features/item_edit/identify_dialog.dart` | Identifica |
| `lib/features/item_edit/refresh_metadata_dialog.dart` | Aggiorna metadati |
| `lib/features/item_edit/images_dialog.dart` | Locandina e sfondo |
| `lib/features/detail/item_actions_menu.dart`, `lib/features/reports/admin_reports_controller.dart`, `reports_banner.dart` (modifiche) | voci admin e scorciatoie |
| `l10n/app_it.arb`, `l10n/app_en.arb` | testi |
| `test/support/item_edit_fakes.dart` | `FakeItemEditApi`, dati di prova |

---

## Gruppo A — nucleo

### Task 1: chiamate, modelli, timeout e testi

**Files:**
- Create: `lib/core/jellyfin/item_edit_models.dart`, `lib/core/jellyfin/item_edit_api.dart`, `lib/features/item_edit/item_edit_providers.dart`, `test/support/item_edit_fakes.dart`
- Modify: `lib/core/jellyfin/jellyfin_http.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/core/jellyfin/item_edit_api_test.dart`, `test/core/jellyfin/jellyfin_http_test.dart` (un test), `test/app/l10n_plan24c_test.dart`

**Interfaces:**
- Produces:
  - **`JellyfinHttp.post(…, {Duration? receiveTimeout})`:** con il valore, `Options(contentType:, receiveTimeout:)`.
  - **`item_edit_models.dart`:**
    - `const lockableFields = {'Name', 'Overview', 'Genres', 'OfficialRating'}`;
    - `class ParentalRatingOption { String name; String? value; }`;
    - `class RemoteSearchResult { Map<String, dynamic> raw; String name; int? year; String? imageUrl, provider, overview; }`, con `fromJson` che tiene la `Map` intera in `raw`;
    - `enum EditImageType { primary('Primary'), backdrop('Backdrop') }`;
    - `class RemoteImage { String url, provider; String? thumbnailUrl, language; int? width, height; double? rating; }`;
    - `class RemoteImagesPage { List<RemoteImage> images; int total; }`.
  - **`ItemEditApi(JellyfinHttp)`**, che lancia gli `ApiException` così come sono, come `PluginAdminApi`:
    - `Future<Map<String, dynamic>> rawItem(String userId, String itemId)`;
    - `Future<void> updateItem(String itemId, Map<String, dynamic> item)`;
    - `Future<List<ParentalRatingOption>> parentalRatings(String itemId)`;
    - `Future<List<RemoteSearchResult>> searchRemote(ItemKind kind, {required String itemId, required String name, int? year, Map<String, String> providerIds = const {}})`: `Movie` o `Series` secondo il kind, gli id vuoti non si mandano;
    - `Future<void> applyIdentify(String itemId, RemoteSearchResult result, {required bool replaceAllImages})`, con `receiveTimeout: identifyApplyTimeout`;
    - `Future<void> refresh(String itemId, {required bool replaceAllMetadata, required bool replaceAllImages})`;
    - `Future<RemoteImagesPage> remoteImages(String itemId, EditImageType type, {int startIndex = 0, bool allLanguages = false})`, con `limit = remoteImagesPageSize`;
    - `Future<void> downloadImage(String itemId, EditImageType type, String imageUrl)`;
    - `Future<void> uploadImage(String itemId, EditImageType type, Uint8List bytes, {required String mimeType})`: corpo `base64Encode(bytes)` come stringa, `contentType: mimeType`;
    - `Future<void> moveBackdropFirst(String itemId, int fromIndex)`.
    Costanti `identifyApplyTimeout = Duration(minutes: 3)` e `remoteImagesPageSize = 30`. `quietStatuses` `{400, 403, 404}`.
  - **`item_edit_providers.dart`:**
    - `itemEditApiProvider`;
    - `class PickedImageFile { String name; int length; Future<Uint8List> Function() read; }`;
    - `imageFilePickerProvider` con `imageFileExtensions = ['jpg', 'jpeg', 'png']` e `maxImageFileBytes = 10485760`.
  - **`item_edit_fakes.dart`:** `FakeItemEditApi implements ItemEditApi`, con:
    - `Map<String, Map<String, dynamic>> items`;
    - `List<String> calls`;
    - `Object? nextFailure` (una volta sola);
    - `Completer<void>? gate`;
    - `List<RemoteSearchResult> results`, `RemoteImagesPage page`, `List<ParentalRatingOption> ratings`;
    - `Map<String, dynamic>? lastUpdate`.
    Più `Map<String, dynamic> testRawItem({…})`, che restituisce una `Map` realistica con `Tags`, `ProviderIds`, `People`, `Studios`, `Genres`, `LockedFields`, `LockData`, `BackdropImageTags`.

**Testi** (italiano; l'inglese lo scrive chi esegue):

| Chiave | Italiano |
|---|---|
| `itemActionEditMetadata` | Modifica metadati |
| `itemActionIdentify` | Identifica |
| `itemActionRefresh` | Aggiorna metadati… |
| `itemActionImages` | Locandina e sfondo |
| `editMetadataTitle` | Modifica metadati |
| `editFieldName` | Titolo |
| `editFieldOriginalTitle` | Titolo originale |
| `editFieldSortName` | Titolo per l'ordinamento |
| `editFieldTagline` | Tagline |
| `editFieldOverview` | Trama |
| `editFieldYear` | Anno |
| `editFieldPremiereDate` | Data di uscita |
| `editFieldGenres` | Generi |
| `editFieldAddGenre` | Aggiungi un genere |
| `editFieldRating` | Classificazione per età |
| `editRatingNone` | Nessuna |
| `editLockField` | Blocca questo campo |
| `editUnlockField` | Sblocca questo campo |
| `editLockAll` | Blocca tutti i metadati |
| `editLockAllHint` | Un aggiornamento dei metadati non cambierà niente di questo titolo |
| `editSave` | Salva |
| `editSaved` | Metadati salvati |
| `editNoPermission` | Non hai il permesso per farlo |
| `identifyTitle` | Identifica |
| `identifyName` | Nome |
| `identifyYear` | Anno |
| `identifyTmdb` | ID TMDb |
| `identifyImdb` | ID IMDb |
| `identifyTvdb` | ID TVDB |
| `identifySearch` | Cerca |
| `identifyNoResults` | Nessun risultato |
| `identifyConfirm` (`{title}`) | Sostituire metadati e immagini con quelli di {title}? |
| `identifyReplaceImages` | Sostituisci anche le immagini |
| `identifyUnlock` | Sblocca i campi modificati a mano |
| `identifyApply` | Applica |
| `identifyWorking` | Può volerci qualche minuto… |
| `identifyDone` | Titolo identificato |
| `identifyStillWorking` | Jellyfin sta ancora lavorando: ricarica tra poco |
| `refreshTitle` | Aggiorna metadati |
| `refreshMissing` | Cerca dati mancanti |
| `refreshReplaceAll` | Sostituisci tutti i metadati |
| `refreshAlsoImages` | Anche le immagini |
| `refreshStart` | Aggiorna |
| `refreshStarted` | Aggiornamento avviato |
| `imagesTitle` | Locandina e sfondo |
| `imagesPoster` | Locandina |
| `imagesBackdrop` | Sfondo |
| `imagesEpisode` | Immagine |
| `imagesCurrent` | Attuale |
| `imagesNone` | Nessuna immagine |
| `imagesAllLanguages` | Tutte le lingue |
| `imagesMore` | Altre immagini |
| `imagesUse` | Usa questa |
| `imagesUpload` | Carica dal PC… |
| `imagesFileTypes` | Immagini |
| `imagesFileTooLarge` | Il file supera 10 MB |
| `imagesSaved` | Immagine aggiornata |
| `imagesNoResults` | Nessuna immagine dai provider |
| `reportShortcutIdentify` | Identifica |
| `reportShortcutEdit` | Modifica metadati |

- [ ] **Step 1: test che falliscono**
- `item_edit_api_test`, con `FakeAdapter`:
  - `rawItem e updateItem: la Map torna identica` (rotte `/Items/i1?userId=u1` e `POST /Items/i1`);
  - `searchRemote: Movie o Series e corpo con i soli id non vuoti`;
  - `applyIdentify manda il risultato grezzo e replaceAllImages`;
  - `refresh con le query giuste per le due scelte`;
  - `remoteImages con type, startIndex, limit 30 e includeAllLanguages`;
  - `uploadImage manda base64 con il content type`;
  - `moveBackdropFirst chiama Index con newIndex=0`.
- `jellyfin_http_test`: `post con receiveTimeout lo passa a dio` (con `FakeAdapter`, leggendo `options.receiveTimeout` della richiesta).
- `l10n_plan24c_test`: tutte le chiavi it/en, non vuote, e `identifyConfirm` con il titolo.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice**, poi `flutter gen-l10n`.
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): item edit core"`

## Gruppo B — finestre

### Task 2: Modifica metadati e voci admin del menu

**Files:**
- Create: `lib/features/item_edit/edit_metadata_dialog.dart`
- Modify: `lib/features/detail/item_actions_menu.dart`
- Test: `test/features/item_edit/edit_metadata_dialog_test.dart`, `test/features/detail/item_actions_menu_test.dart` (aggiornato)

**Interfaces:**
- Consumes: `ItemEditApi`, `lockableFields`, `ParentalRatingOption`, `FakeItemEditApi` (Task 1).
- Produces:
  - **`enum ItemAction { report, mediaInfo, subtitles, editMetadata, identify, refresh, images }`**. Il gruppo admin di `itemActionGroups`, solo con `isAdmin`:
    - `editMetadata`, `refresh`, `images` per {movie, series, season, episode};
    - `identify` per {movie, series}.
    L'ordine è editMetadata, identify, refresh, images; le voci dei Task 3–5 restano no-op con un commento finché quei task non le collegano.
  - **`Future<void> showEditMetadataDialog(BuildContext context, {required String itemId, required ItemKind kind})`** (`showWfDialog`, `maxWidth: 640`). Legge `rawItem` e `parentalRatings`; durante il caricamento c'è una rotella; con un errore, l'errore e niente form.
  - **`Map<String, dynamic> applyMetadataEdits(Map<String, dynamic> original, MetadataEdits edits)`**, funzione pura. `class MetadataEdits`, con un valore facoltativo per ogni campo della decisione 3 (`null` = non toccato), più `Set<String> lockedFields` e `bool lockAll`.
    - Restituisce una copia di `original` con le sole chiavi cambiate (`Taglines: [tagline]`, `PremiereDate` ISO a mezzanotte UTC, `Genres: [...]`, `OfficialRating` null per "nessuna").
    - `LockedFields` = quelli scelti; un campo bloccabile cambiato si aggiunge da sé.
    - `LockData` = `lockAll`.

**Finestra:**
- campi della decisione 3, con la tagline nascosta per episodi e stagioni;
- generi come chip con ✕, più un campo `editFieldAddGenre` che aggiunge con Invio;
- **lucchetto** (`LucideIcons.lock` / `lockOpen`, tooltip `editLockField`/`editUnlockField`) accanto ai quattro campi bloccabili: mostra lo stato e si può cambiare a mano;
- interruttore `editLockAll` con la riga `editLockAllHint`;
- **Salva**, con una sola chiamata in volo: `updateItem(itemId, applyMetadataEdits(...))`, poi `bump()`, chiusura e snackbar `editSaved`;
- **errori nella finestra**, che resta aperta con i dati: `ForbiddenException` → `editNoPermission` e `refreshUser()` (notifier letto prima dell'attesa); il resto → `describeError`.

- [ ] **Step 1: test che falliscono**
- `applyMetadataEdits`, test puri:
  - `il DTO mandato è quello letto con solo i campi cambiati` (`Tags`, `ProviderIds`, `People`, `Studios` identici; `Name` cambiato);
  - `un campo bloccabile cambiato entra in LockedFields, uno non bloccabile no`;
  - `lucchetto tolto a mano: il campo esce da LockedFields`;
  - `tagline in Taglines[0]`;
  - `data a mezzanotte UTC`;
  - `classificazione nessuna → null`;
  - `lockAll → LockData true`.
- Widget:
  - `campi precompilati dalla Map e tagline nascosta per un episodio`;
  - `Salva: updateItem, bump, snackbar`;
  - `doppio clic: una sola chiamata`;
  - `un 403 al salvataggio rilegge l'utente`;
  - `errore di rete: messaggio e dati rimasti`.
- `item_actions_menu_test`: le voci admin per film, serie, stagione ed episodio; niente voci admin per chi non è admin.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): edit metadata dialog"`

### Task 3: Identifica e scorciatoie del riquadro

**Files:**
- Create: `lib/features/item_edit/identify_dialog.dart`
- Modify: `lib/features/detail/item_actions_menu.dart` (collega `identify`), `lib/features/reports/admin_reports_controller.dart`, `lib/features/reports/reports_banner.dart`
- Test: `test/features/item_edit/identify_dialog_test.dart`, `test/features/reports/reports_banner_test.dart` (test nuovi), `test/features/reports/admin_reports_controller_test.dart` (scorciatoie)

**Interfaces:**
- Consumes: Task 1, `showEditMetadataDialog` (Task 2).
- Produces:
  - `Future<void> showIdentifyDialog(BuildContext context, {required String itemId, required ItemKind kind})` (`showWfDialog`, `maxWidth: 720`);
  - `enum ReportShortcut { subtitles, identify, editMetadata }`; `reportShortcut`:
    - `subtitles` come prima;
    - `ReportType.metadata` su `movie`/`series` → `identify`;
    - su `season`/`episode` → `editMetadata`;
    - altrimenti null;
  - nel riquadro: `reportShortcutIdentify` → `showIdentifyDialog(itemId: report.itemId, kind: …)`; `reportShortcutEdit` → `showEditMetadataDialog`. Il kind si ricava da `report.itemType`.

**Finestra:**
- **ricerca:** campi precompilati da `rawItem`: `Name`, `ProductionYear`, `ProviderIds.Tmdb`/`Imdb` e, per le serie, `Tvdb`. Poi **Cerca** → `searchRemote`;
- **risultati:** una riga ciascuno con `WfImage` della locandina (`imageUrl`, se c'è), nome, anno, provider e trama accorciata a 3 righe; nessuno → `identifyNoResults`;
- **scelta:** una conferma nella stessa finestra con:
  - `identifyConfirm("Nome (anno)")`;
  - la casella `identifyReplaceImages` (attiva);
  - la casella `identifyUnlock` (attiva) solo se l'item ha `LockData` o `LockedFields` non vuoti;
  - **Applica**;
- **Applica:**
  - con `identifyUnlock` prima `updateItem` della `Map` con `LockData: false`, `LockedFields: []`;
  - poi `applyIdentify`, con la rotella e `identifyWorking`, e una sola chiamata in volo;
  - se riesce: `bump()`, chiusura, snackbar `identifyDone`;
  - con `ServerUnreachableException`: `bump()`, chiusura, snackbar `identifyStillWorking`;
  - 403: `editNoPermission` + `refreshUser()`;
  - il resto resta nella finestra.

- [ ] **Step 1: test che falliscono**
- `campi precompilati; Tvdb solo per le serie`.
- `ricerca e risultati`.
- `conferma senza la casella di sblocco se non ci sono blocchi`.
- `sblocco: updateItem con LockData false e LockedFields vuoti, poi apply`.
- `Apply riuscito: bump e snackbar`.
- `Apply che scade: messaggio e rilettura`.
- `doppio clic su Applica: una sola chiamata`.
- Riquadro:
  - `scorciatoia Identifica per i metadati di un film`;
  - `scorciatoia Modifica metadati per un episodio`;
  - `nessuna scorciatoia per Audio o video`.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): identify dialog and report shortcuts"`

### Task 4: Aggiorna metadati

**Files:**
- Create: `lib/features/item_edit/refresh_metadata_dialog.dart`
- Modify: `lib/features/detail/item_actions_menu.dart` (collega `refresh`)
- Test: `test/features/item_edit/refresh_metadata_dialog_test.dart`

**Interfaces:**
- Produces:
  - `const refreshReloadDelay = Duration(seconds: 10)`;
  - `Future<void> showRefreshMetadataDialog(BuildContext context, {required String itemId})`.

**Finestra:**
- due scelte (radio): `refreshMissing` (scelta di base) e `refreshReplaceAll`;
- la casella `refreshAlsoImages`, attiva solo con `refreshReplaceAll`;
- **Aggiorna** (una sola chiamata in volo) → `refresh(itemId, replaceAllMetadata: replaceAll, replaceAllImages: replaceAll && images)`, poi chiusura e snackbar `refreshStarted`;
- dopo `refreshReloadDelay`, un `Timer` fuori dalla finestra chiama `ref.read(libraryRevisionProvider.notifier).bump()` sul container dell'app (`ProviderScope.containerOf(context, listen: false)`, preso prima della chiusura);
- errori come nel Task 2.

- [ ] **Step 1: test che falliscono**
- `cerca dati mancanti: replace falsi`.
- `sostituisci tutto con immagini`.
- `la casella delle immagini è spenta con cerca dati mancanti`.
- `bump 10 s dopo, non prima` (`fake_async`).
- `un 403 rilegge l'utente`.

- [ ] **Step 2–4** come sopra.
- [ ] **Step 5: commit** — `git commit -m "feat(app): refresh metadata dialog"`

### Task 5: Locandina e sfondo

**Files:**
- Create: `lib/features/item_edit/images_dialog.dart`
- Modify: `lib/features/detail/item_actions_menu.dart` (collega `images`)
- Test: `test/features/item_edit/images_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1, `imageUrlsProvider`, `itemProvider`.
- Produces:
  - `Future<void> showImagesDialog(BuildContext context, {required String itemId, required ItemKind kind})` (`showWfDialog`, `maxWidth: 900`);
  - `List<EditImageType> imageTabsFor(ItemKind kind)`: decisione 8;
  - `int? backdropToMoveFirst(int backdropCount)`: `backdropCount - 1` se più di 1, altrimenti null.

**Finestra:**
- **schede** da `imageTabsFor` (testi `imagesPoster`, `imagesBackdrop`, o `imagesEpisode` per un episodio); con una sola scheda, la riga delle schede non c'è;
- **immagine attuale** in alto (`imagesCurrent`, con `imageUrlsProvider` sull'item di `itemProvider(itemId)`), o `imagesNone`;
- **griglia** da `remoteImages`:
  - miniatura (`thumbnailUrl ?? url`), provider, `width×height`, lingua, voto;
  - la casella `imagesAllLanguages` rilegge da capo;
  - **Altre immagini** carica la pagina successiva finché `images.length < total`;
  - nessuna → `imagesNoResults`;
- **"Usa questa":**
  - `downloadImage`;
  - per lo sfondo: rilegge `rawItem` e, se `backdropToMoveFirst(BackdropImageTags.length)` non è null, `moveBackdropFirst`;
  - poi `bump()`, l'immagine attuale si rilegge, snackbar `imagesSaved`;
- **"Carica dal PC…":**
  - `imageFilePickerProvider`; oltre `maxImageFileBytes` → `imagesFileTooLarge` senza chiamate;
  - `mimeType` dall'estensione (`png` → `image/png`, altrimenti `image/jpeg`);
  - `uploadImage`, poi lo stesso spostamento per lo sfondo;
- **una sola operazione alla volta**, con la rotella sulla miniatura scelta o sul bottone;
- errori come nel Task 2.

- [ ] **Step 1: test che falliscono**
- `imageTabsFor per i quattro livelli`.
- `backdropToMoveFirst`.
- `griglia, tutte le lingue, altre immagini`.
- `Usa come locandina: download e bump`.
- `Usa come sfondo: download, rilettura e spostamento dell'ultimo a 0`.
- `un solo sfondo: niente spostamento`.
- `file oltre 10 MB: messaggio e nessuna chiamata`.
- `upload png con il content type giusto`.
- `doppio clic: una sola chiamata`.

- [ ] **Step 2–4** come sopra.
- [ ] **Step 5: commit** — `git commit -m "feat(app): poster and backdrop dialog"`

## Gruppo C — chiusura

### Task 6: versione 0.19.0, spec e build

**Files:**
- Modify: `pubspec.yaml`, `docs/RELEASING.md`, `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md`

- [ ] **Step 1:** `pubspec.yaml` → `version: 0.19.0`. In `docs/RELEASING.md` aggiungi la voce "Strumenti admin dei metadati" con il passo 4 della spec §11.3.
- [ ] **Step 2: la spec**, controllando ogni frase sul codice:
  - **Stato:** "piano 24c realizzato (`docs/superpowers/plans/2026-10-21-wonderflix-24c-strumenti-admin-app.md`)";
  - **§3:** decisione 15 corretta (decisione 2);
  - **§7.8:** andata e ritorno della `Map` (decisione 1), campi (decisione 3);
  - **§7.9:** timeout e messaggio (decisione 4), sblocco (decisione 5);
  - **§7.10:** finestra invece del sottomenu (decisione 6);
  - **§7.11:** spostamento e limite dei file non locali (decisione 7);
  - **§7.4:** scorciatoie (decisione 10);
  - **§12:** chiudi i punti verificati (DTO e dati utente; ordine degli sfondi);
  - **§13:** 24c = 0.19.0;
  - ogni altra differenza venuta fuori.
- [ ] **Step 3:** `flutter analyze` e la suite intera verdi, poi la build esatta (dopo aver copiato `config/wonderflix.json`). Annota l'exe.
- [ ] **Step 4: commit** — `git commit -m "chore: app 0.19.0 and spec aligned with plan 24c"`

### Task 7: STOP — prova a mano con l'utente

Il subagent si ferma dopo il Task 6. L'orchestratore fa la review finale e i ritocchi, poi **aspetta l'utente** prima di lanciare l'app.

Prova (spec §11.3, passo 4), con l'admin:
- reidentificare un film sbagliato;
- modificare un titolo e verificare che, dopo "Aggiorna metadati" → "Cerca dati mancanti", il titolo bloccato resti;
- cambiare locandina e sfondo (anche da file);
- usare le scorciatoie Identifica e Modifica metadati da una segnalazione.

Su un titolo di prova, perché i cambi sono veri.

Con l'ok dell'utente: merge su `main`, push, tag `v0.19.0`, note nella bozza (memoria `release-notes`), pubblicazione dopo l'ok dell'utente.
