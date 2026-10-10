# WonderFlix — Piano 19c: Home su misura, impostazioni, card dell'admin e "Cosa guardo stasera?"

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte che manca dello Spec M, poi la release:
- **Impostazioni → Home:** l'utente sposta e nasconde le righe accese dall'admin, con salvataggio automatico sul server e "Ripristina la Home predefinita". `/settings?section=home` e il link "Personalizza la Home" in fondo alla Home.
- **Amministrazione → WonderFlix:** le card "Home per tutti" (righe e ordine per tutti) e "Sonarr e Radarr" (prova del collegamento).
- **"Cosa guardo stasera?":** il pulsante con il dado nella Home e la finestra con i filtri, che propone un titolo non visto a caso.
- **Release:** plugin 1.7.0 dal Catalogo e app 0.13.0, non obbligatoria.

**Architecture:**
- **Client** in `lib/core/`:
  - `HomeApi.testArr()` (`POST Upcoming/Test`) con `ArrTestResult`;
  - `LibraryApi.randomUnplayed` (titoli non visti a caso);
  - `JellyfinItem.recursiveItemCount`.
- **Logica pura:**
  - `lib/features/home/home_rows_editing.dart`: spostare una riga, cosa salvare (utente e admin), nomi, fonti e motivi delle righe;
  - `lib/features/tonight/tonight_logic.dart`: filtri, titoli che si possono proporre, riga dei dati.
- **Elenco condiviso:** `HomeRowsEditor` (`lib/features/home/home_rows_editor.dart`), lo stesso widget in modo utente e in modo admin.
- **Controller:**
  - `HomeUserEditor` (`home_user_editor.dart`): legge, salva 500 ms dopo l'ultima modifica, un salvataggio alla volta, torna indietro se fallisce;
  - `AdminHomeEditor` (in `lib/features/admin/home_admin_cards.dart`): bozza, "Salva", "Ripristina";
  - `TonightController` (`lib/features/tonight/tonight_controller.dart`): filtri ricordati per profilo, pescate da 50, niente ripetizioni nella sessione.
- **Interfaccia:**
  - `HomeSettingsSection` in Impostazioni;
  - le due card nella scheda WonderFlix;
  - `TonightDialog` e `TonightButton`, sul carosello (`HeroCarousel.corner`) o in cima alle righe.

**Tech Stack:** Flutter 3.47.5, Riverpod 3, go_router, intl, clock, shared_preferences, `flutter_test`, `fake_async`.

**Spec:** `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md` (§6.3, §6.5, §8.4, §8.5, §8.6, §10, §11, §12.2, §12.3, §15).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 11):
1. **Testi che ci sono già:** si usano invece di quelli nuovi della spec con lo stesso testo.
   - `tonightGenreAll` → `catalogAllGenres` ("Tutti i generi");
   - `tonightSeasons` → `detailSeasons` ("{count} stagioni");
   - "Guarda" → `actionPlay` ("Riproduci"), come dice §10;
   - "Prova collegamento" → `adminSeerrTest`;
   - "Riprova" → `retry`.
2. **Nome di "Perché hai visto X" nell'elenco:** testo nuovo `homeRowsBecauseYouWatched` ("Perché hai visto…"). Il titolo della riga vuole il nome di un film, che nell'elenco non c'è.
3. **Serie mai iniziate (verificato il 2026-10-11):**
   - nella lista di `Items` si chiede il campo `RecursiveItemCount` (numero di episodi);
   - una serie è mai iniziata se `UnplayedItemCount` è uguale a `RecursiveItemCount` ed è più di 0;
   - senza quel campo Jellyfin non calcola `PlayedPercentage` e non c'è modo di distinguerle: `isPlayed=false` dà anche le serie a metà.
4. **Numero di stagioni:** si chiede anche `ChildCount` (verificato: "Marvel's Jessica Jones" ha 3).
5. **Durata con "Entrambi":** il filtro vale solo per i film, le serie passano. Un film senza durata nota non passa un filtro di durata.
6. **Pescate:**
   - 50 titoli per volta (`tonightBatch`);
   - se una pescata non dà un titolo nuovo se ne prova un'altra, fino a 3 (`tonightMaxBatches`), salvo che il totale stia tutto in una pescata;
   - se ci sono solo titoli già proposti si ricomincia con quelli ("finché ce ne sono altri"); se non c'è niente, "Nessun titolo con questi filtri";
   - i titoli già proposti valgono per la sessione dell'app e per l'account (`tonightSeenProvider`), anche cambiando i filtri o riaprendo la finestra.
7. **Riproduci e Dettagli:** la finestra si chiude e restituisce la scelta (`TonightChoice`). La Home chiama `playItem` o `openItem` con il suo `context`: quello di una finestra chiusa non può più navigare.
8. **Generi:** con "Entrambi" l'unione dei generi dei film e delle serie (due letture di `catalogFiltersProvider`). Un genere salvato che non c'è più nell'elenco torna a "Tutti i generi".
9. **L'elenco dell'utente legge le `DisplayPreferences` da solo**, non da `homeUserPrefsProvider`, che trasforma una lettura fallita in "nessun ritocco". Se la lettura fallisce l'elenco mostra l'errore e "Riprova" e non salva niente: salvando si perderebbero i ritocchi.
10. **Id da conservare (nota del 19b):** salvando, gli id che l'elenco non mostra restano al loro posto in `homeRows` e `homeHidden`, dopo l'id che li precedeva. Sono gli id sconosciuti a questa versione e quelli delle righe spente dall'admin: se l'admin le riaccende, l'utente ritrova il suo ordine.
11. **Salvataggi dell'utente:**
    - in coda, uno alla volta;
    - dopo un salvataggio fallito, quelli già in coda non partono e l'elenco torna all'ultimo stato salvato;
    - chiudendo le Impostazioni entro 500 ms, la modifica si salva lo stesso.
12. **Card "Home per tutti":**
    - legge `HomeApi.layout()` da sola, così un errore si vede (`homeAdminRowsProvider` lo nasconde);
    - non si rilegge da sola ogni 30 s come le altre card, perché cancellerebbe le modifiche non salvate;
    - la card resta montata scorrendo;
    - dopo "Salva" e "Ripristina" invalida `homeAdminRowsProvider`, così anche la Home dell'admin cambia subito;
    - i motivi delle righe non disponibili sono solo quelli del plugin: il collegamento a Seerr di chi guarda non conta per tutti.
13. **Card "Sonarr e Radarr":** finché non si prova, "configurato o no" viene dalle funzioni del plugin (`upcomingSeries`, `upcomingMovies`); dopo la prova, dall'esito.
14. **Elenco dell'utente mentre `/Me` si legge:** "Le mie richieste" non ha ancora un motivo, invece di dire per un attimo "Collega il tuo account a Seerr".
15. **Pulsante del dado:**
    - sul carosello, in basso a destra sopra i pallini (`HeroCarousel.corner`);
    - senza carosello, in cima alle righe a destra;
    - anche nella "Home vuota", sotto il testo.
16. **`/settings?section=home`:** `SettingsScreen(section:)`. Dopo il primo fotogramma la pagina scorre fino al titolo della sezione Home con `Scrollable.ensureVisible`; se il parametro cambia con la pagina aperta, scorre di nuovo.
17. **Release:** come nel piano 18c. Plugin 1.7.0: tag, controllo dei riferimenti, manifest, poi il Catalogo al posto della build di prova. App 0.13.0 non obbligatoria, con le note scritte nella bozza. Ogni passo che pubblica va fatto con l'OK dell'utente.

## Global Constraints

- **Righe e id:** `resume`, `nextUp`, `requests`, `latestMovies`, `latestSeries`, `becauseYouWatched`, `continueSaga`, `upcomingSeries`, `upcomingMovies`, `myList` (ordine predefinito).
- **Home dell'utente:** `DisplayPreferences` id `wonderflix-home`, client `wonderflix`, voci `homeRows` e `homeHidden` (id separati da virgole). "Ripristina" toglie le due voci; è disattivato se non ci sono ritocchi.
- **Salvataggio dell'utente:** automatico, **500 ms** dopo l'ultima modifica. Se fallisce, l'elenco torna all'ultimo stato salvato e compare "Non salvato, riprova".
- **Home dell'admin:** `POST /WonderFlixWatchParty/Home/Layout` con `{"Rows": [...]}` (le righe accese, in ordine) o `{"Rows": null}` per l'ordine predefinito; risponde con quella salvata. "Salva" è disattivato senza modifiche; "Ripristina" salva `null` dopo una conferma.
- **Card admin:** dopo Novità, prima di Seerr: "Home per tutti", poi "Sonarr e Radarr". Senza la funzione `home`: "Serve il plugin 1.7.0".
- **Prova Sonarr e Radarr:** `POST /WonderFlixWatchParty/Upcoming/Test` → `{"Sonarr": {"Configured", "Ok", "Version", "Error"}, "Radarr": {…}}`. I campi null possono mancare. `Error` è `NotConfigured`, `Unauthorized` o `Unreachable`.
- **Esiti della prova:**
  - non configurato → "Non configurato";
  - riuscita → "Collegato (versione X)";
  - `Unauthorized` → "Chiave API rifiutata";
  - `Unreachable` o un codice sconosciuto → "Non raggiungibile: controlla l'indirizzo".
- **Cosa guardo stasera?:**
  - pulsante "Cosa guardo stasera?" con `LucideIcons.dices`;
  - filtri:
    - Tipo: Film / Serie / Entrambi (predefinito Entrambi);
    - Durata: Qualsiasi / Meno di 90 min / Meno di 2 h, disattivata con "Serie";
    - Genere: "Tutti i generi" o un genere;
  - preferenze del profilo `tonight.type` (`movies`, `series`, `both`), `tonight.duration` (`any`, `90`, `120`), `tonight.genre`;
  - titoli: film non visti e serie mai iniziate. `Items` con `sortBy=Random`, `isPlayed=false`, tipi e genere, `limit=50`, campi `Overview,ChildCount,RecursiveItemCount`;
  - tasti Riproduci (`playItem`; una serie parte dal primo episodio), Dettagli, Un altro (il dado gira, non con le animazioni ridotte);
  - nessun titolo → "Nessun titolo con questi filtri" e "Togli i filtri"; errore → il messaggio e "Riprova".
- **Impostazioni:** sezione "Home" dopo "Aspetto". Ogni voce dell'elenco ha:
  - maniglia per trascinare;
  - nome e fonte in piccolo ("da Seerr", "da Sonarr", "da Radarr");
  - motivo, se la riga non è disponibile;
  - interruttore.
  Una voce selezionata ha "Sposta su" e "Sposta giù". Sotto: "Vale per questo account su tutti i PC."
- **Testi (it/en, §10 e decisioni 1–2):** le chiavi del Task 1, con quei testi.

## Review Focus

1. **Preferenze non lette:** se la lettura delle `DisplayPreferences` fallisce, l'elenco non deve salvare niente, altrimenti si perdono i ritocchi. Test: Task 5 (`lettura fallita: errore e nessun salvataggio`).
2. **Id che l'elenco non mostra** (versione futura, righe spente dall'admin): salvando restano al loro posto. Test:
   - Task 3 (`keepForeignIds: gli id estranei restano dopo il loro vicino`);
   - Task 5 (`salvando restano gli id che l'elenco non mostra`).
3. **Modifiche rapide e salvataggi insieme:** un salvataggio alla volta e vale l'ultimo stato. Se uno fallisce, quelli in coda non partono e l'elenco torna indietro. Test: Task 5 (`due salvataggi non si sovrappongono, e vale l'ultimo stato`, `un salvataggio fallito ferma quelli in coda`, `salvataggio fallito: si torna all'ultimo salvato`).
4. **Pochi titoli in "Cosa guardo stasera?":**
   - già proposti tutti: si ricomincia, invece di "Nessun titolo";
   - nessuno davvero: "Nessun titolo con questi filtri", senza girare all'infinito.

   Test: Task 8 (`già proposti tutti: si ricomincia`, `nessun titolo: al massimo tre pescate`).
5. **Card "Home per tutti":** le modifiche non salvate non si perdono scorrendo. "Salva" è disattivato senza modifiche. "Ripristina" salva solo dopo la conferma. Test: Task 7 (`Salva solo con modifiche, poi la Home dell'admin si rilegge`, `Ripristina chiede conferma`, `la bozza resta scorrendo`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `flutter`, `dart` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-19c`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera, tutta verde, con **`flutter test --concurrency=4`**. Con i 16 processi predefiniti il PC si è riavviato due volte il 2026-10-10;
  - la base di partenza è di **2721** test verdi (`main` dopo `08d7fcf`): il primo task lo conferma e lo scrive nel report.
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Codice:**
  - durate, misure e limiti come costanti nominate e commentate;
  - commenti in italiano, codice in inglese;
  - icone solo `LucideIcons`, colori `WfColors`;
  - `clock.now()`, mai `DateTime.now()`.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container dei test hanno `retry: (_, _) => null`;
  - in un provider, tutti i `ref.watch` stanno prima del primo `await`;
  - **spinner e `pumpAndSettle`:** il carosello e gli shimmer non si fermano mai. Nei test della Home e delle finestre con `SkeletonBox` usa `pump()` e `pump(durata)`, non `pumpAndSettle`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-11 sul codice di `main` (`08d7fcf`) e sul server (Jellyfin 10.11.9, plugin 1.7.0 di prova), in sola lettura.

**Server** (chiamate con la chiave API e l'id di un admin)
- `GET /Items?includeItemTypes=Series&isPlayed=false&sortBy=Random&fields=Genres,Overview` (senza `RecursiveItemCount`):
  - `UserData.PlayedPercentage` manca sempre e `UnplayedItemCount` c'è (es. "Lupin": 17);
  - le serie a metà non si distinguono da quelle mai iniziate.
- Con `fields=…,RecursiveItemCount`:
  - mai iniziata: `PlayedPercentage` 0 e `UnplayedItemCount` = `RecursiveItemCount` (es. "From": 40 e 40, "Brothers": 4 e 4);
  - "1899", iniziata: `PlayedPercentage` 37.5, `UnplayedItemCount` 5, `RecursiveItemCount` 8.
- Con `fields=…,ChildCount`: le serie hanno il numero di stagioni ("Marvel's Jessica Jones": 3); i film no.
- `sortBy=Random` con `includeItemTypes=Movie,Series`, `isPlayed=false` e `genres=Commedia`: 110 titoli in tutto, un ordine diverso a ogni chiamata.
  - I film hanno `RunTimeTicks`, `CommunityRating`, `Genres` e, con il campo, `Overview`.
  - Alcuni film non hanno uno sfondo (`BackdropImageTags` vuoto).
- `GET /Items/Filters?includeItemTypes=Movie,Series`: 43 generi; solo `Movie` 29, solo `Series` 27. Nella libreria ci sono generi in due lingue (Commedia e Comedy).
- `POST /WonderFlixWatchParty/Upcoming/Test` (plugin, `UpcomingDtos.cs`): `{"Sonarr": {"Configured", "Ok", "Version", "Error"}, "Radarr": {…}}`, solo per l'admin.

**App** (`main`)
- **Impostazioni** (`lib/features/settings/settings_screen.dart`):
  - `SingleChildScrollView` → `StaggerGroup(count: _sectionCount)` → `Column`;
  - ogni sezione è `item(index, [section(titolo), widget])`;
  - `_sectionCount` è 8: il titolo e sette sezioni (Account, Lingua, Aspetto, Player, Lingue di riproduzione, Discord, Supporto);
  - nessun parametro: `/settings` in `lib/app/router.dart` costruisce `const SettingsScreen()`.
- **Navigazione:**
  - `ShellRoute` semplice: andando alle Impostazioni con `context.go` la Home si smonta;
  - `/admin?tab=` e `/requests?tab=` leggono `state.uri.queryParameters` (modello per `section`).
- **Finestre:**
  - `showWfDialog<T>(context, {builder, maxWidth = 480, semanticLabel})` (`lib/ui/wf_dialog.dart`);
  - `showAdminConfirmDialog(context, {title, message, confirmLabel})` (`lib/features/admin/admin_confirm_dialog.dart`), che restituisce `Future<bool>`.
- **Preferenze del profilo** (`ProfilePreferences`, `profilePreferencesProvider`):
  - `getString`/`setString`, `getBool`/`setBool`, `getDouble`/`setDouble`, `clearString`;
  - niente interi;
  - nei test: `SharedPreferences.setMockInitialValues`, `sharedPreferencesProvider.overrideWithValue(prefs)`. Senza `profilesProvider` le chiavi sono quelle del PC, senza prefisso.
- **Elenchi riordinabili:** `ReorderableListView` ha `onReorderItem(from, to)` con `to` già contato dopo aver tolto la riga (`onReorder` è deprecato). Il modello in uso è la coda del player (`queue_rows.dart`: `ReorderableDragStartListener` con `LucideIcons.gripVertical`).
- **Interruttori:** `Switch` in una `Row` (card Novità) o `SwitchListTile` (Discord). Non c'è un widget nostro.
- **Pulsanti:**
  - `WfButton.primary/secondary({key, required String label, required IconData icon, required VoidCallback? onPressed, bool autofocus})`;
  - `AdminActionButton({label, icon, required Future<void> Function()? onPressed})` si disattiva mentre lavora e mostra l'errore in uno `SnackBar`;
  - `FilterPicker<T>({value, items, onChanged})` (`lib/features/catalog/catalog_filters_bar.dart`) è il menu dei filtri del catalogo.
- **Admin:**
  - `WonderflixTab` (`lib/features/admin/wonderflix_tab.dart`) è una `ListView` con `const [AnnouncementCard(), NewTitlesCard(), SeerrCard(), AccountRecoveryCard()]`;
  - `AdminCard({title, icon, child})`, `AdminCardError({error, onRetry})` (`admin_widgets.dart`);
  - `seerrTestLabel` è in `wonderflix_labels.dart`.
- **Test admin:**
  - `adminTestOverrides(FakeAdminApi(), {session, foreground, plugin, features = const SocialFeatures(inbox: true), availability})` (`test/support/admin_fakes.dart`), con l'utente `testAdmin`;
  - non va unito a `homeOverrides`: tutti e due sovrascrivono `socialAvailabilityProvider` e `sessionControllerProvider`.
- **Libreria:**
  - `LibraryApi.filters(userId, ItemKind)` dà i generi di un tipo; `catalogFiltersProvider(kind)` (`lib/features/catalog/catalog_controller.dart`);
  - `cardImageParams['fields']` è `'PrimaryImageAspectRatio,Genres'`;
  - `ItemPage(items, totalCount)`;
  - `JellyfinItem` non ha `copyWith`.
  - `UserItemData` ha `played`, `playedPercentage`, `unplayedItemCount`.
  - `formatRuntime(Duration)` dà "2h 46m" (`lib/features/library/item_labels.dart`).
- **Riproduzione e navigazione:**
  - `playItem(context, ref, item)` (`lib/features/playback/play_launcher.dart`): per una serie parte dal prossimo episodio, cioè dal primo per una serie mai iniziata (`findNextEpisode`);
  - `openItem(context, item)` (`lib/app/navigation.dart`).
- **Carosello:**
  - `HeroCarousel({items})` (`lib/features/home/hero_carousel.dart`), alto 460;
  - i pallini sono `Positioned(right: 32, bottom: 20, child: _dots(motion))` nello `Stack`;
  - i testi della diapositiva sono a sinistra (`left: 32, bottom: 48, width: 560`).
- **Home** (`lib/features/home/home_screen.dart`):
  - la `ListView` ha `[if (featuredItems.isNotEmpty) HeroCarousel(…), ...shown]`, con `top: shellBarHeight` senza carosello;
  - la "Home vuota" è un `Center(Text(l.homeEmpty))`.
- **Animazioni:**
  - `WfMotion.of(context).isReduced`;
  - `WfMotion.slow` (450 ms), `WfMotion.medium` (300 ms), `WfMotion.emphasized`;
  - `motion.duration(full)` dà `fast` con le animazioni ridotte.
- **Immagini:** `imageUrlsProvider`, `urls.backdrop(item)`, `urls.poster(item)`, `BackdropImage({backdrop, fallback})` (`lib/ui/backdrop_image.dart`).
- **Fake:**
  - `FakeLibraryApi` (`test/support/library_fakes.dart`): `_answer` per gli errori e `testItem(...)`;
  - `FakeHomeApi` e `FakeDisplayPreferencesApi` (`test/support/home_fakes.dart`), e `homeOverrides(library:, home:, prefs:, features:, …)`;
  - nei test dei client HTTP: `FakeAdapter`, `FakeResponse`, `RequestOptionsView(adapter.requests.last)` con `.path` e `.query`.
- **Testi già presenti:** `catalogAllGenres`, `detailSeasons`, `actionPlay`, `actionDetails`, `adminSeerrTest`, `retry`, `homeContinueWatching`, `homeNextUp`, `homeMyRequests`, `homeLatestMovies`, `homeLatestSeries`, `homeContinueSaga`, `homeUpcomingSeries`, `homeUpcomingMovies`, `navMyList`.
- **Icone Lucide controllate** (`lucide_icons_flutter` 3.1.20): `dices`, `save`, `calendarClock`, `layoutList`, `chevronUp`, `chevronDown`, `gripVertical`, `rotateCcw`, `slidersHorizontal`, `star`, `play`, `info`, `link`.

## File

| File | Responsabilità |
|---|---|
| `l10n/app_it.arb`, `l10n/app_en.arb` | i testi nuovi (Task 1) |
| `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart` | `ArrTestResult`, `ArrTestResults`, `HomeApi.testArr` (Task 2) |
| `lib/core/jellyfin/item_models.dart`, `lib/core/jellyfin/library_api.dart` | `recursiveItemCount`, `randomUnplayed` (Task 2) |
| `lib/features/home/home_rows_editing.dart` | logica pura dell'elenco (Task 3) |
| `lib/features/home/home_rows_editor.dart` | `HomeRowsEditor` (Task 4) |
| `lib/features/home/home_user_editor.dart` | `HomeUserEditor` (Task 5) |
| `lib/features/settings/home_settings_section.dart` | sezione Home, `openHomeSettings` (Task 6) |
| `lib/features/settings/settings_screen.dart`, `lib/app/router.dart` | la sezione e `?section=home` (Task 6) |
| `lib/features/admin/home_admin_cards.dart` | `AdminHomeEditor`, "Home per tutti", "Sonarr e Radarr" (Task 7) |
| `lib/features/admin/wonderflix_tab.dart` | l'ordine delle card (Task 7) |
| `lib/features/tonight/tonight_logic.dart` | filtri e regole di "Cosa guardo stasera?" (Task 8) |
| `lib/features/tonight/tonight_controller.dart` | `TonightController`, `tonightSeenProvider`, `tonightGenresProvider` (Task 8) |
| `lib/features/tonight/tonight_dialog.dart` | finestra, `TonightButton`, `openTonight` (Task 9) |
| `lib/features/home/hero_carousel.dart`, `lib/features/home/home_screen.dart` | il dado e il link "Personalizza la Home" (Task 6 e 9) |
| `test/support/home_fakes.dart`, `library_fakes.dart`, `admin_fakes.dart` | i fake |

---

## Gruppo A — dati e logica

### Task 1: i testi

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/l10n/home_config_strings_test.dart`

**Interfaces:**
- Produces: le chiavi qui sotto in `AppLocalizations`. `adminArrOk(String version)` ha un segnaposto.

- [ ] **Step 1: il test che fallisce**

`test/l10n/home_config_strings_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('i testi della configurazione della Home (spec M §10)', () {
    expect(it.homeCustomize, 'Personalizza la Home');
    expect(en.homeCustomize, 'Customize Home');
    expect(it.settingsHome, 'Home');
    expect(it.homeRowsBecauseYouWatched, 'Perché hai visto…');
    expect(en.homeRowsBecauseYouWatched, 'Because you watched…');
    expect(it.homeRowsSourceSonarr, 'da Sonarr');
    expect(en.homeRowsMoveDown, 'Move down');
    expect(it.homeRowsReset, 'Ripristina la Home predefinita');
    expect(it.homeRowsSaveFailed, 'Non salvato, riprova');
    expect(it.homeRowsAllPcs, 'Vale per questo account su tutti i PC.');
    expect(it.homeRowUnavailableSeerr, 'Collega il tuo account a Seerr');
    expect(en.homeRowUnavailableSagas, 'Needs plugin 1.5.0');
  });

  test('i testi delle card dell\'admin', () {
    expect(it.adminHomeTitle, 'Home per tutti');
    expect(it.adminHomeResetConfirm, 'Tornare alla Home predefinita per tutti?');
    expect(it.adminNeedsPlugin170, 'Serve il plugin 1.7.0');
    expect(it.adminArrTitle, 'Sonarr e Radarr');
    expect(it.adminArrOk('4.0.20'), 'Collegato (versione 4.0.20)');
    expect(en.adminArrOk('4.0.20'), 'Connected (version 4.0.20)');
    expect(it.adminArrUnreachable, "Non raggiungibile: controlla l'indirizzo");
  });

  test('i testi di "Cosa guardo stasera?"', () {
    expect(it.tonightButton, 'Cosa guardo stasera?');
    expect(en.tonightButton, 'What should I watch tonight?');
    expect(it.tonightTypeBoth, 'Entrambi');
    expect(it.tonightDuration90, 'Meno di 90 min');
    expect(en.tonightDuration120, 'Under 2 h');
    expect(it.tonightAnother, 'Un altro');
    expect(it.tonightEmpty, 'Nessun titolo con questi filtri');
    expect(it.tonightClearFilters, 'Togli i filtri');
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/l10n/home_config_strings_test.dart`
Expected: errori di compilazione (`homeCustomize` non definito).

- [ ] **Step 3: le chiavi**

In `l10n/app_it.arb`, dopo l'ultima voce (aggiungi la virgola dopo la voce che oggi chiude il file), prima della `}` finale:

```json
  "homeCustomize": "Personalizza la Home",
  "settingsHome": "Home",
  "homeRowsBecauseYouWatched": "Perché hai visto…",
  "homeRowsSourceSeerr": "da Seerr",
  "homeRowsSourceSonarr": "da Sonarr",
  "homeRowsSourceRadarr": "da Radarr",
  "homeRowsMoveUp": "Sposta su",
  "homeRowsMoveDown": "Sposta giù",
  "homeRowsReset": "Ripristina la Home predefinita",
  "homeRowsSaveFailed": "Non salvato, riprova",
  "homeRowsAllPcs": "Vale per questo account su tutti i PC.",
  "homeRowUnavailableSeerr": "Collega il tuo account a Seerr",
  "homeRowUnavailableRequests": "Seerr non è configurato",
  "homeRowUnavailableSagas": "Serve il plugin 1.5.0",
  "homeRowUnavailableSonarr": "Sonarr non è configurato",
  "homeRowUnavailableRadarr": "Radarr non è configurato",
  "adminHomeTitle": "Home per tutti",
  "adminHomeSave": "Salva",
  "adminHomeResetConfirm": "Tornare alla Home predefinita per tutti?",
  "adminNeedsPlugin170": "Serve il plugin 1.7.0",
  "adminArrTitle": "Sonarr e Radarr",
  "adminArrNotConfigured": "Non configurato",
  "adminArrOk": "Collegato (versione {version})",
  "@adminArrOk": {"placeholders": {"version": {"type": "String"}}},
  "adminArrUnauthorized": "Chiave API rifiutata",
  "adminArrUnreachable": "Non raggiungibile: controlla l'indirizzo",
  "tonightButton": "Cosa guardo stasera?",
  "tonightTypeMovies": "Film",
  "tonightTypeSeries": "Serie",
  "tonightTypeBoth": "Entrambi",
  "tonightDurationAny": "Qualsiasi",
  "tonightDuration90": "Meno di 90 min",
  "tonightDuration120": "Meno di 2 h",
  "tonightAnother": "Un altro",
  "tonightEmpty": "Nessun titolo con questi filtri",
  "tonightClearFilters": "Togli i filtri"
```

In `l10n/app_en.arb`, nello stesso modo (senza le voci `@`, come il resto del file):

```json
  "homeCustomize": "Customize Home",
  "settingsHome": "Home",
  "homeRowsBecauseYouWatched": "Because you watched…",
  "homeRowsSourceSeerr": "from Seerr",
  "homeRowsSourceSonarr": "from Sonarr",
  "homeRowsSourceRadarr": "from Radarr",
  "homeRowsMoveUp": "Move up",
  "homeRowsMoveDown": "Move down",
  "homeRowsReset": "Restore the default Home",
  "homeRowsSaveFailed": "Not saved, try again",
  "homeRowsAllPcs": "Applies to this account on every PC.",
  "homeRowUnavailableSeerr": "Link your account to Seerr",
  "homeRowUnavailableRequests": "Seerr is not set up",
  "homeRowUnavailableSagas": "Needs plugin 1.5.0",
  "homeRowUnavailableSonarr": "Sonarr is not set up",
  "homeRowUnavailableRadarr": "Radarr is not set up",
  "adminHomeTitle": "Home for everyone",
  "adminHomeSave": "Save",
  "adminHomeResetConfirm": "Restore the default Home for everyone?",
  "adminNeedsPlugin170": "Needs plugin 1.7.0",
  "adminArrTitle": "Sonarr and Radarr",
  "adminArrNotConfigured": "Not set up",
  "adminArrOk": "Connected (version {version})",
  "adminArrUnauthorized": "API key rejected",
  "adminArrUnreachable": "Unreachable: check the address",
  "tonightButton": "What should I watch tonight?",
  "tonightTypeMovies": "Movies",
  "tonightTypeSeries": "Series",
  "tonightTypeBoth": "Both",
  "tonightDurationAny": "Any",
  "tonightDuration90": "Under 90 min",
  "tonightDuration120": "Under 2 h",
  "tonightAnother": "Another one",
  "tonightEmpty": "No titles with these filters",
  "tonightClearFilters": "Clear filters"
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: il test passa**

Run: `flutter test test/l10n/home_config_strings_test.dart`
Expected: PASS. Poi `flutter analyze` e `flutter test --concurrency=4` (scrivi nel report il numero di partenza e quello finale).

- [ ] **Step 5: commit**

```powershell
git add l10n test/l10n/home_config_strings_test.dart
git commit -m "feat(app): texts for the Home settings, the admin cards and tonight"
```

### Task 2: client e modelli

**Files:**
- Modify: `lib/core/social/home_models.dart`, `lib/core/social/home_api.dart`, `lib/core/jellyfin/item_models.dart`, `lib/core/jellyfin/library_api.dart`, `test/support/home_fakes.dart`, `test/support/library_fakes.dart`
- Test: `test/core/social/home_api_test.dart`, `test/core/jellyfin/library_api_test.dart`, `test/core/jellyfin/item_models_test.dart`

**Interfaces:**
- Produces:
  - `class ArrTestResult({required bool configured, required bool ok, String? version, UpcomingError? error})` con `fromJson`;
  - `class ArrTestResults({required ArrTestResult sonarr, required ArrTestResult radarr})` con `fromJson`;
  - `HomeApi.testArr()` → `Future<ArrTestResults>`;
  - `JellyfinItem.recursiveItemCount` (`int?`);
  - `LibraryApi.randomUnplayed(String userId, {required Set<ItemKind> kinds, String? genre, required int limit})` → `Future<ItemPage>`;
  - fake:
    - `FakeHomeApi`: `arrTest`, `arrTestError`, `arrTestCalls`, `setLayoutError`, `setLayoutGate`;
    - `FakeDisplayPreferencesApi`: `writeError`, `writeGate`, `resetError`;
    - `FakeLibraryApi`: `randomPages`, `randomCalls`, `randomGate`, `filtersByKind`;
    - `testItem(recursiveCount:, unplayedCount:)`.

- [ ] **Step 1: i test che falliscono**

In `test/core/social/home_api_test.dart`, in fondo a `main`:

```dart
  test('prova di Sonarr e Radarr: POST Upcoming/Test e i due esiti',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Sonarr': {'Configured': true, 'Ok': true, 'Version': '4.0.20.3014'},
          'Radarr': {'Configured': true, 'Ok': false, 'Error': 'Unauthorized'},
        });
    final result = await api.testArr();
    expect(adapter.requests.last.method, 'POST');
    expect(adapter.requests.last.path, '/WonderFlixWatchParty/Upcoming/Test');
    expect(result.sonarr.configured, isTrue);
    expect(result.sonarr.ok, isTrue);
    expect(result.sonarr.version, '4.0.20.3014');
    expect(result.sonarr.error, isNull);
    expect(result.radarr.ok, isFalse);
    expect(result.radarr.error, UpcomingError.unauthorized);
  });

  test('prova: campi mancanti, servizio non configurato, codice sconosciuto',
      () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Sonarr': {'Configured': false, 'Ok': false, 'Error': 'NotConfigured'},
          'Radarr': {'Configured': true, 'Ok': false, 'Error': 'Boh'},
        });
    final result = await api.testArr();
    expect(result.sonarr.configured, isFalse);
    expect(result.sonarr.error, UpcomingError.notConfigured);
    expect(result.radarr.error, UpcomingError.unreachable);

    adapter.handler = (_) => const FakeResponse(200, <String, dynamic>{});
    final empty = await api.testArr();
    expect(empty.sonarr.configured, isFalse);
    expect(empty.radarr.ok, isFalse);
  });

  test('prova: 403 per chi non è admin', () async {
    adapter.handler = (_) => const FakeResponse(403, <String, dynamic>{});
    await expectLater(api.testArr(), throwsA(isA<ForbiddenException>()));
  });
```

In `test/core/jellyfin/library_api_test.dart`, in fondo a `main`:

```dart
  test('randomUnplayed: a caso, non visti, tipi, genere e i campi in più',
      () async {
    adapter.handler = (_) => FakeResponse(200, itemsResult(['a'], total: 632));
    final page = await api.randomUnplayed('u1',
        kinds: {ItemKind.series, ItemKind.movie}, genre: 'Commedia', limit: 50);
    expect(last().path, '/Items');
    expect(last().query['includeItemTypes'], 'Movie,Series');
    expect(last().query['sortBy'], 'Random');
    expect(last().query['isPlayed'], false);
    expect(last().query['recursive'], true);
    expect(last().query['limit'], 50);
    expect(last().query['genres'], 'Commedia');
    expect(last().query['userId'], 'u1');
    expect(
        last().query['fields'],
        'PrimaryImageAspectRatio,Genres,Overview,ChildCount,'
        'RecursiveItemCount');
    expect(page.items.single.id, 'a');
    expect(page.totalCount, 632);

    await api.randomUnplayed('u1', kinds: {ItemKind.movie}, limit: 50);
    expect(last().query.containsKey('genres'), isFalse);
  });
```

In `test/core/jellyfin/item_models_test.dart`, dopo il test di `premiereDate`:

```dart
  test('recursiveItemCount: gli episodi di una serie, se chiesti', () {
    final series = JellyfinItem.fromJson({
      'Id': 's1',
      'Name': 'From',
      'Type': 'Series',
      'RecursiveItemCount': 40,
      'UserData': {'UnplayedItemCount': 40},
    });
    expect(series.recursiveItemCount, 40);
    expect(series.userData.unplayedItemCount, 40);
    expect(
        JellyfinItem.fromJson({'Id': 's2', 'Name': 'x', 'Type': 'Series'})
            .recursiveItemCount,
        isNull);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/home_api_test.dart test/core/jellyfin/library_api_test.dart test/core/jellyfin/item_models_test.dart`
Expected: errori di compilazione (`testArr`, `randomUnplayed`, `recursiveItemCount` non definiti).

- [ ] **Step 3: il codice**

In `lib/core/social/home_models.dart`, in fondo:

```dart
/// L'esito della prova di un servizio, Sonarr o Radarr (spec M §7.5). I
/// campi null possono mancare: un servizio assente vale non configurato.
class ArrTestResult {
  const ArrTestResult({
    required this.configured,
    required this.ok,
    this.version,
    this.error,
  });

  factory ArrTestResult.fromJson(Map<String, dynamic> json) => ArrTestResult(
        configured: json['Configured'] == true,
        ok: json['Ok'] == true,
        version: jsonString(json['Version']),
        error: UpcomingError.parse(json['Error']),
      );

  final bool configured;
  final bool ok;
  final String? version;

  /// `null` se la prova è riuscita.
  final UpcomingError? error;
}

/// `POST Upcoming/Test`: Sonarr e Radarr insieme.
class ArrTestResults {
  const ArrTestResults({required this.sonarr, required this.radarr});

  factory ArrTestResults.fromJson(Map<String, dynamic> json) => ArrTestResults(
        sonarr: ArrTestResult.fromJson(jsonMap(json['Sonarr']) ?? const {}),
        radarr: ArrTestResult.fromJson(jsonMap(json['Radarr']) ?? const {}),
      );

  final ArrTestResult sonarr;
  final ArrTestResult radarr;
}
```

In `lib/core/social/home_api.dart`, dopo `upcomingMovies`:

```dart
  /// La prova di Sonarr e Radarr (spec M §7.5), solo per l'admin: il plugin
  /// chiama i due servizi, senza cache. Chi non è admin riceve 403.
  Future<ArrTestResults> testArr() async => parseJson(
      await _http.post('$_base/Upcoming/Test', quietStatuses: _quiet),
      ArrTestResults.fromJson);
```

In `lib/core/jellyfin/item_models.dart`, in `JellyfinItem`:
- nel costruttore, dopo `this.childCount,`: `this.recursiveItemCount,`;
- in `fromJson`, dopo `childCount: _int(json['ChildCount']),`: `recursiveItemCount: _int(json['RecursiveItemCount']),`;
- dopo il campo `childCount`:

```dart
  /// Per le serie: numero di episodi. Jellyfin lo manda solo se chiesto
  /// (`RecursiveItemCount`), e solo allora conta gli episodi visti.
  final int? recursiveItemCount;
```

In `lib/core/jellyfin/library_api.dart`, dopo `items`:

```dart
  /// Titoli non visti presi a caso (spec M §8.4, "Cosa guardo stasera?"):
  /// [limit] titoli dei tipi [kinds] e del genere [genre], se c'è. Con la
  /// trama, il numero di stagioni (`ChildCount`) e quello degli episodi
  /// (`RecursiveItemCount`): senza, Jellyfin non conta gli episodi visti di
  /// una serie e non si saprebbe se è mai iniziata.
  Future<ItemPage> randomUnplayed(String userId,
      {required Set<ItemKind> kinds,
      String? genre,
      required int limit}) async {
    final data = await _http.get('/Items', query: {
      ...cardImageParams,
      'fields':
          '${cardImageParams['fields']},Overview,ChildCount,RecursiveItemCount',
      'userId': userId,
      'recursive': true,
      'includeItemTypes':
          (kinds.map((kind) => kind.apiName).toList()..sort()).join(','),
      'isPlayed': false,
      'sortBy': 'Random',
      'limit': limit,
      'enableTotalRecordCount': true,
      'genres': ?genre,
    });
    return parseJson(
        data,
        (json) => ItemPage(
            _items(json), (json['TotalRecordCount'] as num?)?.toInt() ?? 0));
  }
```

`'genres': ?genre` è la voce nulla-facoltativa delle mappe (Dart 3.8, già usata in `library_fakes.dart`). Se l'analyzer non la accetta, scrivi `if (genre != null) 'genres': genre,`.

In `test/support/home_fakes.dart`, in `FakeHomeApi`:

```dart
  /// La risposta di [testArr].
  ArrTestResults arrTest = const ArrTestResults(
    sonarr: ArrTestResult(configured: true, ok: true, version: '4.0.20'),
    radarr: ArrTestResult(configured: true, ok: true, version: '6.4.4'),
  );
  Object? arrTestError;
  int arrTestCalls = 0;

  Object? setLayoutError;

  /// Se valorizzato, [setLayout] aspetta che si completi.
  Completer<void>? setLayoutGate;

  @override
  Future<ArrTestResults> testArr() async {
    arrTestCalls++;
    final error = arrTestError;
    if (error != null) throw error;
    return arrTest;
  }
```

e `setLayout` diventa:

```dart
  @override
  Future<List<String>?> setLayout(List<String>? rows) async {
    setLayoutCalls.add(rows);
    final gate = setLayoutGate;
    if (gate != null) await gate.future;
    final error = setLayoutError;
    if (error != null) throw error;
    layoutRows = rows;
    return rows;
  }
```

In `FakeDisplayPreferencesApi`:

```dart
  Object? writeError;
  Object? resetError;

  /// Se valorizzato, [writeHome] aspetta che si completi (dopo aver
  /// registrato la chiamata).
  Completer<void>? writeGate;

  @override
  Future<void> writeHome(String userId, HomeUserPrefs prefs) async {
    written.add((userId, prefs));
    final gate = writeGate;
    if (gate != null) await gate.future;
    final error = writeError;
    if (error != null) throw error;
    this.prefs = prefs;
  }

  @override
  Future<void> resetHome(String userId) async {
    resets.add(userId);
    final error = resetError;
    if (error != null) throw error;
    prefs = HomeUserPrefs.none;
  }
```

(sostituiscono i due metodi di oggi; `home_fakes.dart` importa già `dart:async`).

In `test/support/library_fakes.dart`, in `FakeLibraryApi`:

```dart
  /// Le risposte di [randomUnplayed], una per chiamata; l'ultima si ripete.
  final randomPages = <ItemPage>[];
  final randomCalls = <({Set<ItemKind> kinds, String? genre, int limit})>[];

  /// Se valorizzato, [randomUnplayed] aspetta che si completi.
  Completer<void>? randomGate;

  /// I generi per tipo; senza voce vale [libraryFilters].
  final filtersByKind = <ItemKind, LibraryFilters>{};

  @override
  Future<ItemPage> randomUnplayed(String userId,
      {required Set<ItemKind> kinds,
      String? genre,
      required int limit}) async {
    randomCalls.add((kinds: kinds, genre: genre, limit: limit));
    final gate = randomGate;
    if (gate != null) await gate.future;
    return _answer(() => randomPages.isEmpty
        ? const ItemPage([], 0)
        : randomPages.length > 1
            ? randomPages.removeAt(0)
            : randomPages.first);
  }
```

`filters` diventa `_answer(() => filtersByKind[kind] ?? libraryFilters)`. In `testItem` aggiungi i parametri `int? recursiveCount` e `int? unplayedCount`: `'RecursiveItemCount': ?recursiveCount` accanto a `'ChildCount'`, e `'UnplayedItemCount': ?unplayedCount` dentro `'UserData'`.

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/social/home_api_test.dart test/core/jellyfin/library_api_test.dart test/core/jellyfin/item_models_test.dart`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/core test/core test/support
git commit -m "feat(app): Sonarr and Radarr test client, random unwatched titles"
```

### Task 3: la logica dell'elenco

**Files:**
- Create: `lib/features/home/home_rows_editing.dart`
- Test: `test/features/home/home_rows_editing_test.dart`

**Interfaces:**
- Consumes: `HomeRowKind`, `parseHomeRows`, `HomeRowGate` (`home_layout.dart`); `HomeUserPrefs`.
- Produces:
  - `List<HomeRowKind> moveRow(List<HomeRowKind> rows, HomeRowKind row, int to)`;
  - `List<String> keepForeignIds({required List<String> stored, required List<String> edited})`;
  - `HomeUserPrefs homeUserPrefsToSave({required List<HomeRowKind> rows, required Set<HomeRowKind> hidden, required HomeUserPrefs stored})`;
  - `List<HomeRowKind> adminEditorRows(List<String>? saved)`, `Set<HomeRowKind> adminEditorOn(List<String>? saved)`, `List<String> adminRowsToSave(List<HomeRowKind> rows, Set<HomeRowKind> on)`, `List<String> adminRowsEffective(List<String>? saved)`;
  - `String homeRowName(AppLocalizations l, HomeRowKind row)`, `String? homeRowSource(AppLocalizations l, HomeRowKind row)`, `String? homeRowGateReason(AppLocalizations l, HomeRowGate gate)`.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_rows_editing_test.dart`:

```dart
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
    expect(prefs.rows, ['resume', 'continueSaga', 'future', 'myList']);
    expect(prefs.hidden, ['myList', 'continueSaga', 'future']);
  });

  test('homeUserPrefsToSave: senza ritocchi salvati, l\'elenco', () {
    final prefs = homeUserPrefsToSave(
        rows: [nextUp, resume], hidden: {}, stored: HomeUserPrefs.none);
    expect(prefs.rows, ['nextUp', 'resume']);
    expect(prefs.hidden, isEmpty);
  });

  group('Home per tutti', () {
    test('mai impostata: tutte accese, nell\'ordine predefinito', () {
      expect(adminEditorRows(null), HomeRowKind.values);
      expect(adminEditorOn(null), HomeRowKind.values.toSet());
      expect(adminRowsEffective(null),
          [for (final row in HomeRowKind.values) row.id]);
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
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_rows_editing_test.dart`
Expected: errori di compilazione (`home_rows_editing.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/home/home_rows_editing.dart`:

```dart
import '../../core/jellyfin/display_preferences_api.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_layout.dart';

/// Sposta [row] alla posizione [to], contata dopo averla tolta (come
/// `onReorderItem`); fuori dai limiti va al bordo più vicino. Una riga che
/// non c'è non cambia niente.
List<HomeRowKind> moveRow(List<HomeRowKind> rows, HomeRowKind row, int to) {
  final from = rows.indexOf(row);
  if (from < 0) return rows;
  final next = [...rows]..removeAt(from);
  next.insert(to.clamp(0, next.length), row);
  return next;
}

/// [edited] più gli id di [stored] che l'elenco non mostra: sconosciuti a
/// questa versione, o di righe spente dall'admin (spec M §8.5, note per il
/// 19c). Ognuno resta dopo l'id che lo precedeva in [stored], o in testa.
List<String> keepForeignIds(
    {required List<String> stored, required List<String> edited}) {
  final shown = edited.toSet();
  final result = [...edited];
  // Dove va il prossimo id estraneo: dopo l'ultimo id mostrato incontrato.
  var cursor = 0;
  for (final id in stored) {
    if (shown.contains(id)) {
      cursor = result.indexOf(id) + 1;
    } else if (!result.contains(id)) {
      result.insert(cursor, id);
      cursor++;
    }
  }
  return result;
}

/// La Home dell'utente da salvare: l'ordine e le nascoste dell'elenco, più
/// gli id che l'elenco non mostra (decisione 10 del piano 19c).
HomeUserPrefs homeUserPrefsToSave({
  required List<HomeRowKind> rows,
  required Set<HomeRowKind> hidden,
  required HomeUserPrefs stored,
}) {
  final shown = {for (final row in rows) row.id};
  return HomeUserPrefs(
    rows: keepForeignIds(
        stored: stored.rows, edited: [for (final row in rows) row.id]),
    hidden: {
      for (final row in rows)
        if (hidden.contains(row)) row.id,
      for (final id in stored.hidden)
        if (!shown.contains(id)) id,
    }.toList(),
  );
}

/// L'elenco della card "Home per tutti" (spec M §8.6): le righe accese
/// nell'ordine dell'admin, poi le spente nell'ordine predefinito. `null`:
/// mai impostata, tutte accese.
List<HomeRowKind> adminEditorRows(List<String>? saved) {
  if (saved == null) return HomeRowKind.values;
  final on = parseHomeRows(saved);
  return [
    ...on,
    for (final row in HomeRowKind.values)
      if (!on.contains(row)) row,
  ];
}

/// Le righe accese di [saved]; `null` le accende tutte.
Set<HomeRowKind> adminEditorOn(List<String>? saved) =>
    saved == null ? HomeRowKind.values.toSet() : parseHomeRows(saved).toSet();

/// La Home dell'admin da salvare: le righe accese, nell'ordine dell'elenco.
List<String> adminRowsToSave(List<HomeRowKind> rows, Set<HomeRowKind> on) => [
      for (final row in rows)
        if (on.contains(row)) row.id,
    ];

/// La Home dell'admin com'è davvero: `null` vale tutte le righe
/// nell'ordine predefinito; gli id sconosciuti non contano.
List<String> adminRowsEffective(List<String>? saved) => [
      for (final row
          in saved == null ? HomeRowKind.values : parseHomeRows(saved))
        row.id,
    ];

/// Il nome di una riga nell'elenco. "Perché hai visto X" qui non ha un
/// titolo (decisione 2 del piano 19c).
String homeRowName(AppLocalizations l, HomeRowKind row) => switch (row) {
      HomeRowKind.resume => l.homeContinueWatching,
      HomeRowKind.nextUp => l.homeNextUp,
      HomeRowKind.requests => l.homeMyRequests,
      HomeRowKind.latestMovies => l.homeLatestMovies,
      HomeRowKind.latestSeries => l.homeLatestSeries,
      HomeRowKind.becauseYouWatched => l.homeRowsBecauseYouWatched,
      HomeRowKind.continueSaga => l.homeContinueSaga,
      HomeRowKind.upcomingSeries => l.homeUpcomingSeries,
      HomeRowKind.upcomingMovies => l.homeUpcomingMovies,
      HomeRowKind.myList => l.navMyList,
    };

/// La fonte esterna, in piccolo sotto il nome; `null` per le righe di
/// Jellyfin.
String? homeRowSource(AppLocalizations l, HomeRowKind row) => switch (row) {
      HomeRowKind.requests => l.homeRowsSourceSeerr,
      HomeRowKind.upcomingSeries => l.homeRowsSourceSonarr,
      HomeRowKind.upcomingMovies => l.homeRowsSourceRadarr,
      _ => null,
    };

/// Perché una riga non c'è (spec M §6.5, §10); `null` se è disponibile.
String? homeRowGateReason(AppLocalizations l, HomeRowGate gate) =>
    switch (gate) {
      HomeRowGate.available => null,
      HomeRowGate.seerrOff => l.homeRowUnavailableRequests,
      HomeRowGate.noSeerrAccount => l.homeRowUnavailableSeerr,
      HomeRowGate.sagasOff => l.homeRowUnavailableSagas,
      HomeRowGate.sonarrOff => l.homeRowUnavailableSonarr,
      HomeRowGate.radarrOff => l.homeRowUnavailableRadarr,
    };
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/home/home_rows_editing_test.dart`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/home/home_rows_editing.dart test/features/home/home_rows_editing_test.dart
git commit -m "feat(app): rules of the Home rows list, user and admin"
```

### Task 4: l'elenco delle righe

**Files:**
- Create: `lib/features/home/home_rows_editor.dart`
- Test: `test/features/home/home_rows_editor_test.dart`

**Interfaces:**
- Consumes: `homeRowName`, `homeRowSource` (Task 3).
- Produces:
  - `class HomeRowsEditorEntry({required HomeRowKind kind, required bool on, String? unavailable})`;
  - `HomeRowsEditor({required List<HomeRowsEditorEntry> entries, required void Function(HomeRowKind row, int to) onMove, required void Function(HomeRowKind row, bool on) onToggle, bool lockUnavailable = true})`;
  - chiavi: `home-rows-<id>` (la voce), `home-rows-switch-<id>`, `home-rows-up`, `home-rows-down`.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_rows_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_rows_editing.dart';
import 'package:wonderflix/features/home/home_rows_editor.dart';

import '../../support/pump_app.dart';

void main() {
  late List<HomeRowKind> rows;
  late Set<HomeRowKind> off;
  late List<(HomeRowKind, int)> moves;
  late List<(HomeRowKind, bool)> toggles;

  setUp(() {
    rows = [HomeRowKind.resume, HomeRowKind.nextUp, HomeRowKind.upcomingSeries];
    off = {};
    moves = [];
    toggles = [];
  });

  /// Un elenco che applica davvero spostamenti e interruttori.
  Future<void> pumpEditor(WidgetTester tester,
      {bool lockUnavailable = true,
      Map<HomeRowKind, String> unavailable = const {}}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: HomeRowsEditor(
              lockUnavailable: lockUnavailable,
              entries: [
                for (final row in rows)
                  HomeRowsEditorEntry(
                      kind: row,
                      on: !off.contains(row),
                      unavailable: unavailable[row]),
              ],
              onMove: (row, to) => setState(() {
                moves.add((row, to));
                rows = moveRow(rows, row, to);
              }),
              onToggle: (row, on) => setState(() {
                toggles.add((row, on));
                on ? off.remove(row) : off.add(row);
              }),
            ),
          ),
        ),
      ),
    );
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('nomi, fonti e motivi', (tester) async {
    await pumpEditor(tester,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    expect(find.text('Serie in arrivo'), findsOneWidget);
    expect(find.text('da Sonarr'), findsOneWidget);
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
    expect(find.byIcon(LucideIcons.gripVertical), findsNWidgets(3));
  });

  testWidgets('una voce selezionata ha le frecce e si sposta', (tester) async {
    await pumpEditor(tester);
    expect(find.byKey(const Key('home-rows-up')), findsNothing);
    await tester.tap(find.text('Prossimi episodi'));
    await tester.pump();
    expect(find.byKey(const Key('home-rows-up')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-rows-down')));
    await tester.pump();
    expect(moves, [(HomeRowKind.nextUp, 2)]);
    expect(top(tester, 'Serie in arrivo'),
        lessThan(top(tester, 'Prossimi episodi')));
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-rows-down')))
            .onPressed,
        isNull,
        reason: 'resta selezionata ed è l\'ultima: non scende più');
  });

  testWidgets('da tastiera: Alt+↑ e Alt+↓ spostano la voce selezionata',
      (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Serie in arrivo'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(moves, [(HomeRowKind.upcomingSeries, 1)]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(moves.last, (HomeRowKind.upcomingSeries, 2));
  });

  testWidgets('trascinando la maniglia', (tester) async {
    await pumpEditor(tester);
    final handle = find.byIcon(LucideIcons.gripVertical).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, isNotEmpty);
    expect(moves.last.$1, HomeRowKind.resume);
    expect(rows.first, isNot(HomeRowKind.resume));
  });

  testWidgets('l\'interruttore accende e spegne', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump();
    expect(toggles, [(HomeRowKind.nextUp, false)]);
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('home-rows-switch-nextUp')))
            .value,
        isFalse);
  });

  testWidgets('modo utente: una riga non disponibile è spenta e ferma, ma si '
      'sposta', (tester) async {
    await pumpEditor(tester,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    final toggle = tester.widget<Switch>(
        find.byKey(const Key('home-rows-switch-upcomingSeries')));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    await tester.tap(find.text('Serie in arrivo'));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('home-rows-up')))
            .onPressed,
        isNotNull);
  });

  testWidgets('modo admin: una riga non disponibile si accende lo stesso',
      (tester) async {
    off = {HomeRowKind.upcomingSeries};
    await pumpEditor(tester,
        lockUnavailable: false,
        unavailable: {HomeRowKind.upcomingSeries: 'Sonarr non è configurato'});
    await tester.tap(find.byKey(const Key('home-rows-switch-upcomingSeries')));
    await tester.pump();
    expect(toggles, [(HomeRowKind.upcomingSeries, true)]);
  });
}
```

Il trascinamento nei test dipende dai tempi del gesto. Se `moves` resta vuoto, aggiungi un `pump(const Duration(milliseconds: 100))` dopo `startGesture` o allunga lo spostamento. Non togliere il controllo su `moves.last.$1`.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_rows_editor_test.dart`
Expected: errori di compilazione (`home_rows_editor.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/home/home_rows_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_layout.dart';
import 'home_rows_editing.dart';

/// Una voce dell'elenco delle righe.
class HomeRowsEditorEntry {
  const HomeRowsEditorEntry(
      {required this.kind, required this.on, this.unavailable});

  final HomeRowKind kind;

  /// Interruttore acceso: la riga si vede (utente) o è accesa per tutti
  /// (admin).
  final bool on;

  /// Perché la riga non c'è (spec M §10); `null` se è disponibile.
  final String? unavailable;
}

/// L'elenco delle righe della Home (spec M §8.5, §8.6), uguale per
/// l'utente e per l'admin: maniglia per trascinare, nome, fonte, motivo se
/// la riga non c'è, interruttore. La voce selezionata ha due frecce per
/// spostarla; da tastiera Alt+↑ e Alt+↓.
class HomeRowsEditor extends StatefulWidget {
  const HomeRowsEditor({
    super.key,
    required this.entries,
    required this.onMove,
    required this.onToggle,
    this.lockUnavailable = true,
  });

  final List<HomeRowsEditorEntry> entries;

  /// [to] è la posizione finale, contata dopo aver tolto la riga.
  final void Function(HomeRowKind row, int to) onMove;

  final void Function(HomeRowKind row, bool on) onToggle;

  /// Modo utente: una riga non disponibile ha l'interruttore spento e
  /// fermo. Modo admin (`false`): si accende lo stesso, e comparirà quando
  /// la fonte c'è.
  final bool lockUnavailable;

  @override
  State<HomeRowsEditor> createState() => _HomeRowsEditorState();
}

class _HomeRowsEditorState extends State<HomeRowsEditor> {
  /// Tiene la tastiera sull'elenco dopo aver scelto una voce.
  final _focus = FocusNode(debugLabel: 'home-rows-editor');

  HomeRowKind? _selected;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _select(HomeRowKind row) {
    setState(() => _selected = row);
    _focus.requestFocus();
  }

  /// Sposta la voce selezionata di una posizione, su (-1) o giù (+1).
  void _step(int delta) {
    final row = _selected;
    if (row == null) return;
    final from = widget.entries.indexWhere((entry) => entry.kind == row);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= widget.entries.length) return;
    widget.onMove(row, to);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _step(1),
      },
      child: Focus(
        focusNode: _focus,
        child: ReorderableListView.builder(
          // Dentro la pagina che scorre: l'elenco è alto quanto le voci.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: widget.entries.length,
          onReorderItem: (from, to) =>
              widget.onMove(widget.entries[from].kind, to),
          proxyDecorator: (child, index, animation) => Material(
            color: WfColors.surfaceHigh,
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
          itemBuilder: (context, index) =>
              _entry(l, widget.entries[index], index),
        ),
      ),
    );
  }

  Widget _entry(AppLocalizations l, HomeRowsEditorEntry entry, int index) {
    final selected = entry.kind == _selected;
    final source = homeRowSource(l, entry.kind);
    final reason = entry.unavailable;
    final locked = widget.lockUnavailable && reason != null;
    const small = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);
    return Material(
      key: ValueKey('home-rows-${entry.kind.id}'),
      color: selected ? WfColors.surfaceHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _select(entry.kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(LucideIcons.gripVertical,
                      size: 18, color: WfColors.creamMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(homeRowName(l, entry.kind),
                        style: TextStyle(
                            color: locked
                                ? WfColors.creamMuted
                                : WfColors.cream)),
                    if (source != null) Text(source, style: small),
                    if (reason != null)
                      Text(reason,
                          style: small.copyWith(color: WfColors.gold)),
                  ],
                ),
              ),
              if (selected) ...[
                IconButton(
                  key: const Key('home-rows-up'),
                  tooltip: l.homeRowsMoveUp,
                  icon: const Icon(LucideIcons.chevronUp, size: 18),
                  onPressed: index > 0 ? () => _step(-1) : null,
                ),
                IconButton(
                  key: const Key('home-rows-down'),
                  tooltip: l.homeRowsMoveDown,
                  icon: const Icon(LucideIcons.chevronDown, size: 18),
                  onPressed: index < widget.entries.length - 1
                      ? () => _step(1)
                      : null,
                ),
              ],
              Switch(
                key: ValueKey('home-rows-switch-${entry.kind.id}'),
                value: entry.on && !locked,
                onChanged:
                    locked ? null : (on) => widget.onToggle(entry.kind, on),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/home/home_rows_editor_test.dart`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/home/home_rows_editor.dart test/features/home/home_rows_editor_test.dart
git commit -m "feat(app): reorderable list of the Home rows"
```

### Task 5: la Home dell'utente, letta e salvata

**Files:**
- Create: `lib/features/home/home_user_editor.dart`
- Test: `test/features/home/home_user_editor_test.dart`

**Interfaces:**
- Consumes: `displayPreferencesApiProvider`, `homeAdminRowsProvider`, `homeUserPrefsProvider` (`home_providers.dart`); `composeHomeLayout`, `parseHomeRows`; `moveRow`, `homeUserPrefsToSave` (Task 3); `currentUserIdProvider`.
- Produces:
  - `const homeEditorSaveDelay = Duration(milliseconds: 500)`;
  - `class HomeUserEditorState({required List<HomeRowKind> rows, required Set<HomeRowKind> hidden, required HomeUserPrefs stored, required List<HomeRowKind> defaultRows, bool saveFailed = false})` con `copyWith` e `bool get canReset`;
  - `class HomeUserEditor extends AsyncNotifier<HomeUserEditorState>` con `move(HomeRowKind row, int to)`, `setVisible(HomeRowKind row, bool visible)`, `Future<void> reset()`;
  - `final homeUserEditorProvider` (`AsyncNotifierProvider.autoDispose`).

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_user_editor_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_user_editor.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeHomeApi home;
  late FakeDisplayPreferencesApi prefs;
  late FakeSessionController session;

  setUp(() {
    home = FakeHomeApi();
    prefs = FakeDisplayPreferencesApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer bare() => ProviderContainer.test(
        overrides: homeOverrides(
            library: FakeLibraryApi(),
            home: home,
            prefs: prefs,
            features: const SocialFeatures(home: true),
            session: session),
        retry: (_, _) => null,
      );

  ProviderContainer container() {
    final c = bare();
    c.listen(homeUserEditorProvider, (_, _) {});
    return c;
  }

  HomeUserEditorState value(ProviderContainer c) =>
      c.read(homeUserEditorProvider).requireValue;

  test('legge la Home dell\'utente e la combina con quella dell\'admin', () {
    fakeAsync((async) {
      home.layoutRows = ['resume', 'nextUp', 'myList'];
      prefs.prefs =
          const HomeUserPrefs(rows: ['myList', 'resume'], hidden: ['nextUp']);
      final c = container();
      async.flushMicrotasks();
      final state = value(c);
      expect(state.rows,
          [HomeRowKind.myList, HomeRowKind.resume, HomeRowKind.nextUp]);
      expect(state.hidden, {HomeRowKind.nextUp});
      expect(state.defaultRows,
          [HomeRowKind.resume, HomeRowKind.nextUp, HomeRowKind.myList]);
      expect(state.canReset, isTrue);
      expect(prefs.readUsers, ['u1']);
    });
  });

  test('una modifica si salva 500 ms dopo, e più modifiche una volta sola',
      () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      expect(value(c).canReset, isFalse);
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(const Duration(milliseconds: 300));
      editor.setVisible(HomeRowKind.nextUp, false);
      expect(value(c).canReset, isTrue, reason: 'c\'è una modifica');
      async.elapse(const Duration(milliseconds: 499));
      expect(prefs.written, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      final (user, saved) = prefs.written.single;
      expect(user, 'u1');
      expect(saved.rows.first, 'myList');
      expect(saved.hidden, ['nextUp']);
      expect(value(c).stored.rows.first, 'myList');
    });
  });

  test('salvando restano gli id che l\'elenco non mostra', () {
    fakeAsync((async) {
      // L'admin ha spento continueSaga; "future" è di una versione nuova.
      home.layoutRows = ['resume', 'myList'];
      prefs.prefs = const HomeUserPrefs(
          rows: ['continueSaga', 'future', 'myList', 'resume'],
          hidden: ['future']);
      final c = container();
      async.flushMicrotasks();
      expect(value(c).rows, [HomeRowKind.myList, HomeRowKind.resume]);
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.resume, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      final saved = prefs.written.single.$2;
      expect(saved.rows, ['continueSaga', 'future', 'resume', 'myList']);
      expect(saved.hidden, ['future']);
    });
  });

  test('salvataggio fallito: si torna all\'ultimo salvato', () {
    fakeAsync((async) {
      prefs.writeError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      final before = value(c).rows;
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      expect(value(c).rows.first, HomeRowKind.myList);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(value(c).rows, before);
      expect(value(c).saveFailed, isTrue);

      prefs.writeError = null;
      c
          .read(homeUserEditorProvider.notifier)
          .setVisible(HomeRowKind.resume, false);
      expect(value(c).saveFailed, isFalse, reason: 'una nuova modifica');
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.prefs.hidden, ['resume']);
    });
  });

  test('due salvataggi non si sovrappongono, e vale l\'ultimo stato', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1), reason: 'il primo è in volo');

      editor.setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1),
          reason: 'il secondo aspetta che il primo finisca');

      prefs.writeGate = null;
      gate.complete();
      async.flushMicrotasks();
      expect(prefs.written, hasLength(2));
      expect(prefs.written.last.$2.hidden, ['nextUp']);
      expect(prefs.written.last.$2.rows.first, 'myList');
    });
  });

  test('un salvataggio fallito ferma quelli in coda', () {
    fakeAsync((async) {
      final gate = prefs.writeGate = Completer<void>();
      prefs.writeError = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      async.elapse(homeEditorSaveDelay);
      editor.setVisible(HomeRowKind.nextUp, false);
      async.elapse(homeEditorSaveDelay);
      async.flushMicrotasks();

      gate.complete();
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1),
          reason: 'il secondo non parte dopo un errore');
      expect(value(c).saveFailed, isTrue);
      expect(value(c).hidden, isEmpty);
    });
  });

  test('lettura fallita: errore e nessun salvataggio', () {
    fakeAsync((async) {
      prefs.error = const ServerUnreachableException();
      final c = container();
      async.flushMicrotasks();
      expect(c.read(homeUserEditorProvider).hasError, isTrue);
      final editor = c.read(homeUserEditorProvider.notifier);
      editor.move(HomeRowKind.myList, 0);
      editor.setVisible(HomeRowKind.resume, false);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(prefs.written, isEmpty);
    });
  });

  test('Ripristina toglie le due voci e la Home si rilegge', () {
    fakeAsync((async) {
      prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
      final c = container();
      c.listen(homeUserPrefsProvider, (_, _) {});
      async.flushMicrotasks();
      final reads = prefs.readUsers.length;
      unawaited(c.read(homeUserEditorProvider.notifier).reset());
      async.flushMicrotasks();
      expect(prefs.resets, ['u1']);
      expect(value(c).hidden, isEmpty);
      expect(value(c).rows, HomeRowKind.values);
      expect(value(c).canReset, isFalse);
      expect(prefs.readUsers.length, greaterThan(reads),
          reason: 'homeUserPrefsProvider si rilegge');
    });
  });

  test('chiudendo prima dei 500 ms la modifica si salva lo stesso', () {
    fakeAsync((async) {
      final c = bare();
      final sub = c.listen(homeUserEditorProvider, (_, _) {});
      async.flushMicrotasks();
      c.read(homeUserEditorProvider.notifier).move(HomeRowKind.myList, 0);
      sub.close();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(prefs.written, hasLength(1));
      expect(prefs.written.single.$2.rows.first, 'myList');
    });
  });

  test('cambiando profilo si legge la Home del nuovo utente', () {
    fakeAsync((async) {
      final c = container();
      async.flushMicrotasks();
      session.set(
          const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
      async.flushMicrotasks();
      expect(prefs.readUsers, ['u1', 'u2']);
      expect(c.read(homeUserEditorProvider).hasValue, isTrue);
    });
  });
}
```

Se `JellyfinUser` ha altri parametri obbligatori, usa quelli di `testUser` in `test/support/test_data.dart`.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_user_editor_test.dart`
Expected: errori di compilazione (`home_user_editor.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/home/home_user_editor.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/display_preferences_api.dart';
import '../library/library_providers.dart';
import 'home_layout.dart';
import 'home_providers.dart';
import 'home_rows_editing.dart';

final _log = Logger('home');

/// Pausa dall'ultima modifica prima di salvare (spec M §8.5): spostando
/// una riga più volte di fila si salva una volta sola.
const homeEditorSaveDelay = Duration(milliseconds: 500);

/// L'elenco di Impostazioni → Home.
@immutable
class HomeUserEditorState {
  const HomeUserEditorState({
    required this.rows,
    required this.hidden,
    required this.stored,
    required this.defaultRows,
    this.saveFailed = false,
  });

  /// Le righe accese dall'admin, nell'ordine dell'utente (spec M §6.4).
  final List<HomeRowKind> rows;

  /// Le righe che l'utente ha nascosto.
  final Set<HomeRowKind> hidden;

  /// La Home dell'utente com'è sul server, con gli id che l'elenco non
  /// mostra.
  final HomeUserPrefs stored;

  /// L'ordine della Home dell'admin, senza ritocchi.
  final List<HomeRowKind> defaultRows;

  /// L'ultimo salvataggio non è riuscito: l'elenco è tornato a [stored].
  final bool saveFailed;

  /// "Ripristina" serve se ci sono ritocchi, salvati o appena fatti.
  bool get canReset =>
      !stored.isEmpty || hidden.isNotEmpty || !listEquals(rows, defaultRows);

  HomeUserEditorState copyWith({
    List<HomeRowKind>? rows,
    Set<HomeRowKind>? hidden,
    HomeUserPrefs? stored,
    bool? saveFailed,
  }) =>
      HomeUserEditorState(
        rows: rows ?? this.rows,
        hidden: hidden ?? this.hidden,
        stored: stored ?? this.stored,
        defaultRows: defaultRows,
        saveFailed: saveFailed ?? this.saveFailed,
      );
}

/// Legge la Home dell'utente e la salva [homeEditorSaveDelay] dopo l'ultima
/// modifica, un salvataggio alla volta: le `DisplayPreferences` si
/// riscrivono intere, e due salvataggi insieme si pesterebbero.
class HomeUserEditor extends AsyncNotifier<HomeUserEditorState> {
  late DisplayPreferencesApi _api;
  late String _userId;
  List<String>? _adminRows;
  Timer? _timer;

  /// Quello che aspetta i 500 ms.
  HomeUserPrefs? _pending;

  /// L'ultimo salvataggio in coda: il prossimo parte quando finisce. Non
  /// finisce mai con un errore.
  Future<void> _saving = Future.value();

  /// Cresce a ogni salvataggio fallito: quelli già in coda non partono.
  var _failures = 0;

  @override
  Future<HomeUserEditorState> build() async {
    _userId = ref.watch(currentUserIdProvider);
    _api = ref.watch(displayPreferencesApiProvider);
    final adminRows = ref.watch(homeAdminRowsProvider.future);
    ref.onDispose(() {
      // Una modifica che aspettava si salva lo stesso, senza più toccare
      // lo stato.
      if (_pending != null) unawaited(_flush());
      _timer?.cancel();
    });
    // Letta qui e non da `homeUserPrefsProvider`, che una lettura fallita
    // la fa diventare "nessun ritocco": salvando si perderebbero (decisione
    // 9 del piano 19c).
    final stored = await _api.readHome(_userId);
    _adminRows = await adminRows;
    return _fromStored(stored);
  }

  HomeUserEditorState _fromStored(HomeUserPrefs stored,
      {bool saveFailed = false}) {
    List<HomeRowKind> order(HomeUserPrefs user) => composeHomeLayout(
            adminRows: _adminRows, user: user, available: (_) => true)
        .order;
    return HomeUserEditorState(
      rows: order(stored),
      hidden: parseHomeRows(stored.hidden).toSet(),
      stored: stored,
      defaultRows: order(HomeUserPrefs.none),
      saveFailed: saveFailed,
    );
  }

  void move(HomeRowKind row, int to) =>
      _edit((state) => state.copyWith(rows: moveRow(state.rows, row, to)));

  void setVisible(HomeRowKind row, bool visible) => _edit((state) =>
      state.copyWith(
          hidden: visible
              ? ({...state.hidden}..remove(row))
              : {...state.hidden, row}));

  void _edit(HomeUserEditorState Function(HomeUserEditorState) change) {
    final current = state.value;
    // Senza la Home letta non si modifica né si salva niente.
    if (current == null) return;
    final next = change(current).copyWith(saveFailed: false);
    state = AsyncData(next);
    _pending = homeUserPrefsToSave(
        rows: next.rows, hidden: next.hidden, stored: next.stored);
    _timer?.cancel();
    _timer = Timer(homeEditorSaveDelay, () => unawaited(_flush()));
  }

  /// Mette in coda quello che aspetta.
  Future<void> _flush() {
    _timer?.cancel();
    _timer = null;
    final prefs = _pending;
    _pending = null;
    if (prefs == null) return _saving;
    final failures = _failures;
    return _saving = _saving.then((_) async {
      if (failures == _failures) await _save(prefs);
    });
  }

  Future<void> _save(HomeUserPrefs prefs) async {
    try {
      await _api.writeHome(_userId, prefs);
    } on Object catch (error) {
      _log.info('Home dell\'utente non salvata: ${error.runtimeType}');
      _failures++;
      if (!ref.mounted) return;
      _timer?.cancel();
      _timer = null;
      _pending = null;
      final current = state.value;
      if (current != null) {
        state = AsyncData(_fromStored(current.stored, saveFailed: true));
      }
      return;
    }
    if (!ref.mounted) return;
    final current = state.value;
    if (current != null) state = AsyncData(current.copyWith(stored: prefs));
    // La Home si ricompone con i ritocchi nuovi (spec M §8.5).
    ref.invalidate(homeUserPrefsProvider);
  }

  /// "Ripristina la Home predefinita": toglie le due voci (spec M §6.3),
  /// dopo i salvataggi in coda.
  Future<void> reset() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    return _saving = _saving.then((_) => _reset());
  }

  Future<void> _reset() async {
    try {
      await _api.resetHome(_userId);
    } on Object catch (error) {
      _log.info('Home dell\'utente non ripristinata: ${error.runtimeType}');
      if (!ref.mounted) return;
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(saveFailed: true));
      }
      return;
    }
    if (!ref.mounted) return;
    state = AsyncData(_fromStored(HomeUserPrefs.none));
    ref.invalidate(homeUserPrefsProvider);
  }
}

final homeUserEditorProvider =
    AsyncNotifierProvider.autoDispose<HomeUserEditor, HomeUserEditorState>(
        HomeUserEditor.new);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/home/home_user_editor_test.dart`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/home/home_user_editor.dart test/features/home/home_user_editor_test.dart
git commit -m "feat(app): the user's Home read and saved, one save at a time"
```

## Gruppo B — Impostazioni e admin

### Task 6: Impostazioni → Home, `/settings?section=home` e il link nella Home

**Files:**
- Create: `lib/features/settings/home_settings_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`, `lib/app/router.dart`, `lib/features/home/home_screen.dart`, `test/support/home_fakes.dart`, `test/features/settings/settings_test.dart`
- Test: `test/features/settings/home_settings_section_test.dart`, `test/features/settings/settings_test.dart`, `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `homeUserEditorProvider` (Task 5), `HomeRowsEditor` (Task 4), `homeRowGate`, `homeRowGateReason`, `requestsMeProvider`, `socialAvailabilityProvider`.
- Produces:
  - `const homeSettingsSection = 'home'`, `void openHomeSettings(BuildContext context)`;
  - `HomeSettingsSection()`;
  - `SettingsScreen({String? section})`;
  - `List<Override> homeSettingsOverrides({FakeDisplayPreferencesApi? prefs, FakeHomeApi? home, SocialFeatures features = SocialFeatures.none})` in `home_fakes.dart`;
  - chiavi: `home-rows-save-failed`, `home-rows-reset`, `home-customize`.

- [ ] **Step 1: i test che falliscono**

In `test/support/home_fakes.dart`, in fondo:

```dart
/// Quello che serve alla sezione Home delle Impostazioni: va aggiunto ai test
/// che montano `SettingsScreen`, che hanno già l'utente collegato.
List<Override> homeSettingsOverrides({
  FakeDisplayPreferencesApi? prefs,
  FakeHomeApi? home,
  SocialFeatures features = SocialFeatures.none,
}) =>
    [
      displayPreferencesApiProvider
          .overrideWithValue(prefs ?? FakeDisplayPreferencesApi()),
      homeApiProvider.overrideWithValue(home ?? FakeHomeApi()),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];
```

`test/features/settings/home_settings_section_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/display_preferences_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/home/home_rows_editor.dart';
import 'package:wonderflix/features/home/home_user_editor.dart';
import 'package:wonderflix/features/settings/home_settings_section.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/requests_fakes.dart';

void main() {
  late FakeDisplayPreferencesApi prefs;
  late FakeHomeApi home;
  late FakeRequestsApi requests;

  setUp(() {
    prefs = FakeDisplayPreferencesApi();
    home = FakeHomeApi();
    requests = FakeRequestsApi();
  });

  Future<void> pumpSection(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(home: true)}) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: HomeSettingsSection())),
      surfaceSize: const Size(1440, 1400),
      overrides: homeOverrides(
          library: FakeLibraryApi(),
          home: home,
          prefs: prefs,
          features: features,
          requests: requests),
    );
    await tester.pump();
    await tester.pump();
  }

  bool resetEnabled(WidgetTester tester) =>
      tester
          .widget<OutlinedButton>(find.descendant(
              of: find.byKey(const Key('home-rows-reset')),
              matching: find.bySubtype<OutlinedButton>()))
          .onPressed !=
      null;

  testWidgets('l\'elenco con i motivi delle righe che non ci sono',
      (tester) async {
    requests.meValue = const RequestsMe(
        canRequest: true, canManage: false, hasAccount: false);
    await pumpSection(tester,
        features: const SocialFeatures(home: true, requests: true));
    expect(find.byType(HomeRowsEditor), findsOneWidget);
    expect(find.text('Collega il tuo account a Seerr'), findsOneWidget);
    expect(find.text('Sonarr non è configurato'), findsOneWidget);
    expect(find.text('Radarr non è configurato'), findsOneWidget);
    expect(find.text('Vale per questo account su tutti i PC.'), findsOneWidget);
  });

  testWidgets('mentre /Me si legge, Le mie richieste non ha un motivo',
      (tester) async {
    requests.meGate = Completer<void>();
    await pumpSection(tester,
        features: const SocialFeatures(home: true, requests: true));
    expect(find.text('Collega il tuo account a Seerr'), findsNothing);
    expect(find.text('Seerr non è configurato'), findsNothing);
    requests.meGate!.complete();
  });

  testWidgets('un interruttore si salva da solo dopo 500 ms', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump();
    expect(prefs.written, isEmpty);
    await tester.pump(homeEditorSaveDelay);
    await tester.pump();
    expect(prefs.written.single.$2.hidden, ['nextUp']);
  });

  testWidgets('salvataggio fallito: "Non salvato, riprova"', (tester) async {
    prefs.writeError = const ServerUnreachableException();
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
    await tester.pump(homeEditorSaveDelay);
    await tester.pump();
    expect(find.byKey(const Key('home-rows-save-failed')), findsOneWidget);
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('home-rows-switch-nextUp')))
            .value,
        isTrue,
        reason: 'l\'elenco è tornato all\'ultimo stato salvato');
  });

  testWidgets('Ripristina: spento senza ritocchi, acceso con, poi li toglie',
      (tester) async {
    await pumpSection(tester);
    expect(resetEnabled(tester), isFalse);

    prefs.prefs = const HomeUserPrefs(rows: ['myList'], hidden: ['resume']);
    await pumpSection(tester);
    expect(resetEnabled(tester), isTrue);
    await tester.tap(find.byKey(const Key('home-rows-reset')));
    await tester.pump();
    await tester.pump();
    expect(prefs.resets, ['u1']);
    expect(resetEnabled(tester), isFalse);
  });

  testWidgets('lettura fallita: errore e Riprova', (tester) async {
    prefs.error = const ServerUnreachableException();
    await pumpSection(tester);
    expect(find.byType(HomeRowsEditor), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);
    prefs.error = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(HomeRowsEditor), findsOneWidget);
  });
}
```

Il secondo `pumpSection` dello stesso test rimonta tutto con un `ProviderScope` nuovo: è voluto, per leggere le preferenze cambiate.

In `test/features/settings/settings_test.dart`:
- aggiungi `...homeSettingsOverrides(),` alle `overrides` di **ogni** `pumpApp(... SettingsScreen ...)` (oggi sono otto, compreso `pumpSettings`), con l'import di `../../support/home_fakes.dart`;
- aggiungi due test:

```dart
  testWidgets('sezione Home dopo Aspetto, con l\'elenco delle righe',
      (tester) async {
    await pumpSettings(tester);
    await tester.pump();
    final appearance = tester.getTopLeft(find.text('Aspetto')).dy;
    final home = tester.getTopLeft(find.text('Home')).dy;
    expect(appearance, lessThan(home));
    expect(home, lessThan(tester.getTopLeft(find.text('Player')).dy));
    expect(find.byType(HomeRowsEditor), findsOneWidget);
  });

  testWidgets('section=home scorre fino alla sezione Home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pumpApp(tester, const Scaffold(body: SettingsScreen(section: 'home')),
        surfaceSize: const Size(1440, 600),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountAvailableProvider.overrideWithValue(false),
          clientInfoProvider.overrideWithValue(testClientInfo),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
          userConfigApiProvider.overrideWithValue(FakeUserConfigApi()),
          ...homeSettingsOverrides(),
        ]);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final scroll =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.getTopLeft(find.text('Home')).dy, inInclusiveRange(0, 600));
  });
```

Se "Player" compare due volte nella pagina, confronta con il titolo che viene dopo ("Lingue di riproduzione"). Gli import di `HomeRowsEditor` e degli altri provider vanno aggiunti dove mancano. `FakeUserConfigApi` è già in `settings_fakes.dart`.

In `test/features/home/home_screen_test.dart`, in fondo a `main` (con gli import di `go_router` e di `../../support/pump_app.dart` per `pumpAppRouter`, se mancano):

```dart
  testWidgets('"Personalizza la Home" in fondo apre le impostazioni sulla '
      'sezione Home', (tester) async {
    someRows();
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: HomeScreen())),
      GoRoute(
          path: '/settings',
          builder: (context, state) => Text(
              'sezione ${state.uri.queryParameters['section']}')),
    ]);
    await pumpAppRouter(tester, router,
        surfaceSize: const Size(1440, 1600),
        overrides: homeOverrides(library: library, home: home, prefs: prefs));
    await settle(tester);
    final link = find.byKey(const Key('home-customize'));
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('sezione home'), findsOneWidget);
  });

  testWidgets('"Personalizza la Home" anche nella Home vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
    expect(find.byKey(const Key('home-customize')), findsOneWidget);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/settings test/features/home/home_screen_test.dart`
Expected: errori di compilazione (`home_settings_section.dart` non esiste, `SettingsScreen` non ha `section`).

- [ ] **Step 3: il codice**

`lib/features/settings/home_settings_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../home/home_layout.dart';
import '../home/home_rows_editing.dart';
import '../home/home_rows_editor.dart';
import '../home/home_user_editor.dart';
import '../requests/requests_providers.dart';
import '../social/social_providers.dart';

/// Il valore di `/settings?section=` che apre la sezione Home (spec M §8.5).
const homeSettingsSection = 'home';

/// "Personalizza la Home": Impostazioni, sulla sezione Home.
void openHomeSettings(BuildContext context) =>
    context.go('/settings?section=$homeSettingsSection');

/// Impostazioni → Home (spec M §8.5): le righe accese dall'admin, da
/// spostare e nascondere, salvate da sole; "Ripristina la Home predefinita".
class HomeSettingsSection extends ConsumerWidget {
  const HomeSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final editor = ref.watch(homeUserEditorProvider);
    final features = ref.watch(socialAvailabilityProvider);
    final me = ref.watch(requestsMeProvider);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);
    final value = editor.value;
    final Widget body;
    if (value == null) {
      body = editor.hasError
          ? Row(
              children: [
                Flexible(
                    child: Text(describeError(l, editor.error!),
                        style: muted)),
                TextButton(
                  onPressed: () => ref.invalidate(homeUserEditorProvider),
                  child: Text(l.retry),
                ),
              ],
            )
          : const SkeletonBox(width: 320, height: 20);
    } else {
      // Finché `/Me` non risponde, "Le mie richieste" non ha un motivo
      // (decisione 14 del piano 19c).
      final seerrAccount = me.isLoading || (me.value?.hasAccount ?? false);
      final notifier = ref.read(homeUserEditorProvider.notifier);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeRowsEditor(
            entries: [
              for (final row in value.rows)
                HomeRowsEditorEntry(
                  kind: row,
                  on: !value.hidden.contains(row),
                  unavailable: homeRowGateReason(l,
                      homeRowGate(row, features, seerrAccount: seerrAccount)),
                ),
            ],
            onMove: notifier.move,
            onToggle: notifier.setVisible,
          ),
          if (value.saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.homeRowsSaveFailed,
                  key: const Key('home-rows-save-failed'),
                  style: const TextStyle(color: WfColors.error)),
            ),
          const SizedBox(height: 12),
          WfButton.secondary(
            key: const Key('home-rows-reset'),
            label: l.homeRowsReset,
            icon: LucideIcons.rotateCcw,
            onPressed: value.canReset ? () => unawaited(notifier.reset()) : null,
          ),
          const SizedBox(height: 8),
          Text(l.homeRowsAllPcs, style: muted),
        ],
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: body,
    );
  }
}
```

`lib/features/settings/settings_screen.dart` diventa:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/staggered_entrance.dart';
import 'account_settings_section.dart';
import 'appearance_settings_section.dart';
import 'discord_settings_section.dart';
import 'home_settings_section.dart';
import 'language_settings_section.dart';
import 'locale_controller.dart';
import 'player_settings_section.dart';
import 'support_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// La sezione da mostrare all'apertura (`/settings?section=…`): per ora
  /// solo [homeSettingsSection]. Le altre si ignorano.
  final String? section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Elementi dell'entrata: il titolo e le otto sezioni.
  static const _sectionCount = 9;

  final _scroll = SmoothScrollController();

  /// Il titolo della sezione Home, dove scorrere con `section=home`.
  final _homeKey = GlobalKey(debugLabel: 'settings-home');

  @override
  void initState() {
    super.initState();
    _scrollToSection();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section) _scrollToSection();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Dopo il fotogramma, quando la sezione ha la sua posizione (decisione
  /// 16 del piano 19c).
  void _scrollToSection() {
    if (widget.section != homeSettingsSection) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _homeKey.currentContext;
      if (!mounted || target == null) return;
      unawaited(Scrollable.ensureVisible(
        target,
        duration: WfMotion.of(context).duration(WfMotion.medium),
        curve: WfMotion.emphasized,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    final version = ref.watch(clientInfoProvider).version;

    Widget section(String title, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: 32, bottom: 12),
          child: Text(title, style: WfText.display(24)),
        );

    // Una sezione (titolo e contenuto) è un elemento dell'entrata.
    Widget item(int index, List<Widget> children) => StaggerItem(
          index: index,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    // Non una ListView: le sezioni uscite dallo schermo verrebbero
    // smontate, e quella delle lingue (provider autoDispose) ricaricata
    // dal server a ogni passaggio.
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(32),
      child: StaggerGroup(
        count: _sectionCount,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaggerItem(
              index: 0,
              child: Text(l.menuSettings.toUpperCase(),
                  style: WfText.display(40)),
            ),
            item(1, [
              section(l.settingsAccount),
              const AccountSettingsSection(),
            ]),
            item(2, [
              section(l.settingsLanguage),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'system', label: Text(l.settingsLanguageSystem)),
                    const ButtonSegment(value: 'it', label: Text('Italiano')),
                    const ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {locale?.languageCode ?? 'system'},
                  onSelectionChanged: (selection) {
                    final code = selection.first;
                    unawaited(ref
                        .read(localeProvider.notifier)
                        .set(code == 'system' ? null : Locale(code)));
                  },
                ),
              ),
            ]),
            item(3, [
              section(l.settingsAppearance),
              const AppearanceSettingsSection(),
            ]),
            item(4, [
              section(l.settingsHome, key: _homeKey),
              const HomeSettingsSection(),
            ]),
            item(5, [
              section(l.settingsPlayer),
              const PlayerSettingsSection(),
            ]),
            item(6, [
              section(l.settingsLanguages),
              const LanguageSettingsSection(),
            ]),
            item(7, [
              section(l.settingsDiscord),
              const DiscordSettingsSection(),
            ]),
            item(8, [
              section(l.settingsSupport),
              const SupportSection(),
              const SizedBox(height: 40),
              Text(l.settingsVersion(version),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            ]),
          ],
        ),
      ),
    );
  }
}
```

In `lib/app/router.dart`, la rotta `/settings`:

```dart
          GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => shellPage(
                  context,
                  state,
                  SettingsScreen(
                      section: state.uri.queryParameters['section']),
                  underBar: true)),
```

In `lib/features/home/home_screen.dart`:
- import `package:lucide_icons_flutter/lucide_icons.dart` e `../settings/home_settings_section.dart`;
- nella `ListView` dei dati, dopo `...shown,`: `const Align(alignment: Alignment.centerLeft, child: _CustomizeLink()),`;
- la "Home vuota" diventa:

```dart
      return (
        'empty',
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.homeEmpty,
                  style: const TextStyle(color: WfColors.creamMuted)),
              const _CustomizeLink(),
            ],
          ),
        ),
      );
```

- in fondo al file:

```dart
/// "Personalizza la Home", in fondo alle righe e nella Home vuota (spec M
/// §8.5).
class _CustomizeLink extends StatelessWidget {
  const _CustomizeLink();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: TextButton.icon(
          key: const Key('home-customize'),
          onPressed: () => openHomeSettings(context),
          icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
          label: Text(AppLocalizations.of(context).homeCustomize),
        ),
      );
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/settings test/features/home`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/settings lib/app/router.dart lib/features/home/home_screen.dart test/support/home_fakes.dart test/features/settings test/features/home/home_screen_test.dart
git commit -m "feat(app): Home section in Settings, opened from the Home"
```

### Task 7: le card "Home per tutti" e "Sonarr e Radarr"

**Files:**
- Create: `lib/features/admin/home_admin_cards.dart`
- Modify: `lib/features/admin/wonderflix_tab.dart`, `test/support/admin_fakes.dart`
- Test: `test/features/admin/home_admin_cards_test.dart`

**Interfaces:**
- Consumes:
  - `homeApiProvider`, `homeAdminRowsProvider`;
  - `HomeRowsEditor` (Task 4);
  - `adminEditorRows`, `adminEditorOn`, `adminRowsToSave`, `adminRowsEffective`, `moveRow`, `homeRowGateReason` (Task 3);
  - `HomeApi.testArr`, `ArrTestResult` (Task 2);
  - `AdminCard`, `AdminCardError`, `AdminActionButton`, `showAdminConfirmDialog`.
- Produces:
  - `class AdminHomeState` (`saved`, `rows`, `on`, `dirty`, `canReset`);
  - `class AdminHomeEditor extends AsyncNotifier<AdminHomeState>` con `move`, `setOn`, `save`, `reset`;
  - `adminHomeEditorProvider`;
  - `HomeForEveryoneCard`, `ArrCard`;
  - `String arrTestLabel(AppLocalizations l, ArrTestResult result)`;
  - `adminTestOverrides(..., FakeHomeApi? home)`;
  - chiavi: `admin-home-save`, `admin-home-reset`, `arr-sonarr`, `arr-radarr`, `arr-test`.

- [ ] **Step 1: i test che falliscono**

In `test/support/admin_fakes.dart`, `adminTestOverrides` riceve `FakeHomeApi? home` e aggiunge `homeApiProvider.overrideWithValue(home ?? FakeHomeApi()),` (import di `package:wonderflix/features/home/home_providers.dart` e di `home_fakes.dart`).

`test/features/admin/home_admin_cards_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/home_models.dart';
import 'package:wonderflix/features/admin/wonderflix_tab.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/home_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeHomeApi home;

  setUp(() => home = FakeHomeApi());

  const all = SocialFeatures(
      inbox: true,
      home: true,
      requests: true,
      collections: true,
      upcomingSeries: true,
      upcomingMovies: true);

  Future<void> pumpTab(WidgetTester tester,
      {SocialFeatures features = all,
      Size size = const Size(1440, 2600)}) async {
    await pumpApp(tester, const Scaffold(body: WonderflixTab()),
        overrides: adminTestOverrides(FakeAdminApi(),
            home: home, features: features),
        surfaceSize: size);
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, Key key) =>
      tester
          .widget<OutlinedButton>(find.descendant(
              of: find.byKey(key), matching: find.bySubtype<OutlinedButton>()))
          .onPressed !=
      null;

  Switch toggle(WidgetTester tester, HomeRowKind row) => tester
      .widget<Switch>(find.byKey(ValueKey('home-rows-switch-${row.id}')));

  testWidgets('senza la funzione home: "Serve il plugin 1.7.0", nessuna '
      'chiamata', (tester) async {
    await pumpTab(tester, features: const SocialFeatures(inbox: true));
    expect(find.text('Serve il plugin 1.7.0'), findsNWidgets(2));
    expect(home.layoutCalls, 0);
    expect(home.arrTestCalls, 0);
  });

  testWidgets('le due card dopo Novità e prima di Seerr', (tester) async {
    await pumpTab(tester);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Novità'), lessThan(y('Home per tutti')));
    expect(y('Home per tutti'), lessThan(y('Sonarr e Radarr')));
    expect(y('Sonarr e Radarr'), lessThan(y('Seerr')));
  });

  group('Home per tutti', () {
    testWidgets('Salva solo con modifiche, poi la Home dell\'admin si rilegge',
        (tester) async {
      await pumpTab(tester);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(WonderflixTab)));
      container.listen(homeAdminRowsProvider, (_, _) {});
      await tester.pump();
      expect(toggle(tester, HomeRowKind.nextUp).value, isTrue);
      expect(enabled(tester, const Key('admin-home-save')), isFalse);

      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      expect(enabled(tester, const Key('admin-home-save')), isTrue);

      final calls = home.layoutCalls;
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls.last, [
        for (final row in HomeRowKind.values)
          if (row != HomeRowKind.nextUp) row.id,
      ]);
      expect(enabled(tester, const Key('admin-home-save')), isFalse);
      expect(home.layoutCalls, greaterThan(calls),
          reason: 'homeAdminRowsProvider invalidato');
    });

    testWidgets('l\'ordine nuovo si salva', (tester) async {
      await pumpTab(tester);
      await tester.tap(find.text('Prossimi episodi'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('home-rows-up')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls.last!.take(2), ['nextUp', 'resume']);
    });

    testWidgets('Ripristina chiede conferma', (tester) async {
      home.layoutRows = ['myList'];
      await pumpTab(tester);
      expect(toggle(tester, HomeRowKind.resume).value, isFalse);
      expect(enabled(tester, const Key('admin-home-reset')), isTrue);

      await tester.tap(find.byKey(const Key('admin-home-reset')));
      await tester.pumpAndSettle();
      expect(find.text('Tornare alla Home predefinita per tutti?'),
          findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls, isEmpty);

      await tester.tap(find.byKey(const Key('admin-home-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, 'Ripristina la Home predefinita'));
      await tester.pumpAndSettle();
      expect(home.setLayoutCalls, [null]);
      expect(toggle(tester, HomeRowKind.resume).value, isTrue);
      expect(enabled(tester, const Key('admin-home-reset')), isFalse);
    });

    testWidgets('una riga non disponibile ha il motivo ma si accende',
        (tester) async {
      home.layoutRows = ['resume'];
      await pumpTab(tester,
          features: const SocialFeatures(inbox: true, home: true));
      expect(find.text('Sonarr non è configurato'), findsOneWidget);
      expect(find.text('Collega il tuo account a Seerr'), findsNothing,
          reason: 'per tutti conta solo il plugin');
      expect(toggle(tester, HomeRowKind.upcomingSeries).onChanged, isNotNull);
    });

    testWidgets('la bozza resta scorrendo', (tester) async {
      await pumpTab(tester, size: const Size(1440, 700));
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      final list = find.byType(ListView).first;
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 4000));
      await tester.pumpAndSettle();
      expect(toggle(tester, HomeRowKind.nextUp).value, isFalse);
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
    });

    testWidgets('lettura fallita: Riprova', (tester) async {
      home.layoutError = const ServerUnreachableException();
      await pumpTab(tester);
      expect(find.text('Riprova'), findsOneWidget);
      home.layoutError = null;
      await tester.tap(find.text('Riprova'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-home-save')), findsOneWidget);
    });

    testWidgets('salvataggio fallito: l\'errore e la bozza resta',
        (tester) async {
      home.setLayoutError = const ServerUnreachableException();
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('home-rows-switch-nextUp')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('admin-home-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(enabled(tester, const Key('admin-home-save')), isTrue);
      expect(toggle(tester, HomeRowKind.nextUp).value, isFalse);
    });
  });

  group('Sonarr e Radarr', () {
    testWidgets('configurati o no, poi l\'esito della prova', (tester) async {
      await pumpTab(tester,
          features: const SocialFeatures(
              inbox: true, home: true, upcomingSeries: true));
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-radarr')),
              matching: find.text('Non configurato')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('arr-sonarr')),
              matching: find.text('Non configurato')),
          findsNothing);

      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(home.arrTestCalls, 1);
      expect(find.text('Collegato (versione 4.0.20)'), findsOneWidget);
      expect(find.text('Collegato (versione 6.4.4)'), findsOneWidget);

      home.arrTest = const ArrTestResults(
        sonarr: ArrTestResult(
            configured: true, ok: false, error: UpcomingError.unauthorized),
        radarr: ArrTestResult(
            configured: true, ok: false, error: UpcomingError.unreachable),
      );
      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(find.text('Chiave API rifiutata'), findsOneWidget);
      expect(find.text("Non raggiungibile: controlla l'indirizzo"),
          findsOneWidget);
    });

    testWidgets('prova fallita: l\'errore nello SnackBar', (tester) async {
      home.arrTestError = const ServerUnreachableException();
      await pumpTab(tester);
      await tester.tap(find.byKey(const Key('arr-test')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
```

Se un'altra card della scheda mostra anche lei "Riprova" con i fake predefiniti, cerca il "Riprova" dentro la card ("Home per tutti") con `find.descendant`.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/admin/home_admin_cards_test.dart`
Expected: errori di compilazione (`adminTestOverrides` non ha `home`, le card non esistono).

- [ ] **Step 3: il codice**

`lib/features/admin/home_admin_cards.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../home/home_layout.dart';
import '../home/home_providers.dart';
import '../home/home_rows_editing.dart';
import '../home/home_rows_editor.dart';
import '../social/social_providers.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_widgets.dart';

/// La bozza della card "Home per tutti" (spec M §8.6).
@immutable
class AdminHomeState {
  const AdminHomeState(
      {required this.saved, required this.rows, required this.on});

  factory AdminHomeState.fromSaved(List<String>? saved) => AdminHomeState(
      saved: saved, rows: adminEditorRows(saved), on: adminEditorOn(saved));

  /// La Home dell'admin sul server; `null`: mai impostata.
  final List<String>? saved;

  /// Tutte le righe, nell'ordine dell'elenco.
  final List<HomeRowKind> rows;

  /// Le righe accese per tutti.
  final Set<HomeRowKind> on;

  /// Diversa da quella salvata: "Salva" si accende.
  bool get dirty =>
      !listEquals(adminRowsToSave(rows, on), adminRowsEffective(saved));

  /// "Ripristina" serve se la Home è impostata o cambiata.
  bool get canReset => saved != null || dirty;

  AdminHomeState copyWith({List<HomeRowKind>? rows, Set<HomeRowKind>? on}) =>
      AdminHomeState(saved: saved, rows: rows ?? this.rows, on: on ?? this.on);
}

/// Legge la Home dell'admin una volta e tiene la bozza finché non si salva.
/// Non si rilegge da sola come le altre card: cancellerebbe le modifiche
/// (decisione 12 del piano 19c).
class AdminHomeEditor extends AsyncNotifier<AdminHomeState> {
  @override
  Future<AdminHomeState> build() async =>
      AdminHomeState.fromSaved(await ref.watch(homeApiProvider).layout());

  void move(HomeRowKind row, int to) =>
      _edit((state) => state.copyWith(rows: moveRow(state.rows, row, to)));

  void setOn(HomeRowKind row, bool on) => _edit((state) => state.copyWith(
      on: on ? {...state.on, row} : ({...state.on}..remove(row))));

  void _edit(AdminHomeState Function(AdminHomeState) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }

  /// "Salva": le righe accese, nell'ordine dell'elenco. Un errore lo mostra
  /// il pulsante, e la bozza resta.
  Future<void> save() async {
    final current = state.value;
    if (current == null) return;
    _saved(await ref
        .read(homeApiProvider)
        .setLayout(adminRowsToSave(current.rows, current.on)));
  }

  /// "Ripristina la Home predefinita" per tutti: si salva `null`.
  Future<void> reset() async =>
      _saved(await ref.read(homeApiProvider).setLayout(null));

  void _saved(List<String>? saved) {
    if (!ref.mounted) return;
    state = AsyncData(AdminHomeState.fromSaved(saved));
    // Anche la Home dell'admin, tenuta 5 minuti, cambia subito.
    ref.invalidate(homeAdminRowsProvider);
  }
}

final adminHomeEditorProvider =
    AsyncNotifierProvider.autoDispose<AdminHomeEditor, AdminHomeState>(
        AdminHomeEditor.new);

/// "Home per tutti" (spec M §8.6): l'admin accende, spegne e ordina le
/// righe della Home di tutti.
class HomeForEveryoneCard extends ConsumerStatefulWidget {
  const HomeForEveryoneCard({super.key});

  @override
  ConsumerState<HomeForEveryoneCard> createState() =>
      _HomeForEveryoneCardState();
}

class _HomeForEveryoneCardState extends ConsumerState<HomeForEveryoneCard>
    with AutomaticKeepAliveClientMixin {
  /// Scorrendo la scheda la card resta montata: la bozza non si perde.
  @override
  bool get wantKeepAlive => true;

  Future<void> _reset() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.homeRowsReset,
      message: l.adminHomeResetConfirm,
      confirmLabel: l.homeRowsReset,
    );
    if (!confirmed || !mounted) return;
    await ref.read(adminHomeEditorProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    return AdminCard(
      title: l.adminHomeTitle,
      icon: LucideIcons.layoutList,
      child: !features.known
          ? const SkeletonBox(width: 240, height: 20)
          : !features.home
              ? Text(l.adminNeedsPlugin170,
                  style: const TextStyle(color: WfColors.creamMuted))
              : _editor(l, features),
    );
  }

  Widget _editor(AppLocalizations l, SocialFeatures features) {
    final data = ref.watch(adminHomeEditorProvider);
    final value = data.value;
    if (value == null) {
      return data.hasError
          ? AdminCardError(
              error: data.error!,
              onRetry: () => ref.invalidate(adminHomeEditorProvider))
          : const SkeletonBox(width: 240, height: 20);
    }
    final editor = ref.read(adminHomeEditorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeRowsEditor(
          lockUnavailable: false,
          entries: [
            for (final row in value.rows)
              HomeRowsEditorEntry(
                kind: row,
                on: value.on.contains(row),
                // Per tutti contano solo le fonti del plugin, non l'account
                // Seerr di chi guarda (decisione 12 del piano 19c).
                unavailable: homeRowGateReason(
                    l, homeRowGate(row, features, seerrAccount: true)),
              ),
          ],
          onMove: editor.move,
          onToggle: editor.setOn,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AdminActionButton(
              key: const Key('admin-home-save'),
              label: l.adminHomeSave,
              icon: LucideIcons.save,
              onPressed: value.dirty ? editor.save : null,
            ),
            AdminActionButton(
              key: const Key('admin-home-reset'),
              label: l.homeRowsReset,
              icon: LucideIcons.rotateCcw,
              onPressed: value.canReset ? _reset : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// L'esito della prova di un servizio (spec M §8.6, §10).
String arrTestLabel(AppLocalizations l, ArrTestResult result) {
  if (!result.configured) return l.adminArrNotConfigured;
  if (result.ok) return l.adminArrOk(result.version ?? '?');
  return switch (result.error) {
    UpcomingError.notConfigured => l.adminArrNotConfigured,
    UpcomingError.unauthorized => l.adminArrUnauthorized,
    _ => l.adminArrUnreachable,
  };
}

/// "Sonarr e Radarr" (spec M §8.6): configurati o no, e la prova del
/// collegamento con l'esito.
class ArrCard extends ConsumerStatefulWidget {
  const ArrCard({super.key});

  @override
  ConsumerState<ArrCard> createState() => _ArrCardState();
}

class _ArrCardState extends ConsumerState<ArrCard>
    with AutomaticKeepAliveClientMixin {
  /// L'esito dell'ultima prova.
  ArrTestResults? _result;

  /// Con un esito da mostrare la card resta montata scorrendo.
  @override
  bool get wantKeepAlive => _result != null;

  Future<void> _test() async {
    final result = await ref.read(homeApiProvider).testArr();
    if (!mounted) return;
    setState(() => _result = result);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    final Widget child;
    if (!features.known) {
      child = const SkeletonBox(width: 240, height: 20);
    } else if (!features.home) {
      child = Text(l.adminNeedsPlugin170,
          style: const TextStyle(color: WfColors.creamMuted));
    } else {
      final result = _result;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _service(l, 'Sonarr',
              key: const Key('arr-sonarr'),
              configured: features.upcomingSeries,
              result: result?.sonarr),
          const SizedBox(height: 6),
          _service(l, 'Radarr',
              key: const Key('arr-radarr'),
              configured: features.upcomingMovies,
              result: result?.radarr),
          const SizedBox(height: 12),
          AdminActionButton(
            key: const Key('arr-test'),
            label: l.adminSeerrTest,
            icon: LucideIcons.link,
            onPressed: _test,
          ),
        ],
      );
    }
    return AdminCard(
        title: l.adminArrTitle, icon: LucideIcons.calendarClock, child: child);
  }

  /// Prima della prova si sa solo se è configurato (decisione 13 del piano
  /// 19c); dopo, l'esito.
  Widget _service(AppLocalizations l, String name,
      {required Key key, required bool configured, ArrTestResult? result}) {
    final (text, color) = switch (result) {
      null => configured
          ? ('', WfColors.cream)
          : (l.adminArrNotConfigured, WfColors.creamMuted),
      final tested when tested.ok => (arrTestLabel(l, tested), WfColors.cream),
      final tested when !tested.configured =>
        (arrTestLabel(l, tested), WfColors.creamMuted),
      final tested => (arrTestLabel(l, tested), WfColors.error),
    };
    return Row(
      key: key,
      children: [
        SizedBox(
          width: 80,
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}
```

In `lib/features/admin/wonderflix_tab.dart`: import `home_admin_cards.dart`; i figli della `ListView` diventano:

```dart
          children: const [
            AnnouncementCard(),
            NewTitlesCard(),
            HomeForEveryoneCard(),
            ArrCard(),
            SeerrCard(),
            AccountRecoveryCard(),
          ],
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/admin`
Expected: PASS, anche i test che c'erano (con le funzioni predefinite le card nuove dicono "Serve il plugin 1.7.0" e non chiamano niente). Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/admin test/features/admin test/support/admin_fakes.dart
git commit -m "feat(app): admin cards for the Home of everyone and Sonarr and Radarr"
```

## Gruppo C — "Cosa guardo stasera?"

### Task 8: le regole e il controller

**Files:**
- Create: `lib/features/tonight/tonight_logic.dart`, `lib/features/tonight/tonight_controller.dart`
- Test: `test/features/tonight/tonight_logic_test.dart`, `test/features/tonight/tonight_controller_test.dart`

**Interfaces:**
- Consumes:
  - `LibraryApi.randomUnplayed`, `JellyfinItem.recursiveItemCount`, `testItem(recursiveCount:, unplayedCount:)`, `FakeLibraryApi.randomPages/randomCalls/randomGate/filtersByKind` (Task 2);
  - `catalogFiltersProvider`, `profilePreferencesProvider`, `libraryApiProvider`, `currentUserIdProvider`, `sessionControllerProvider`;
  - `formatRuntime`, `l.detailSeasons`.
- Produces:
  - `tonightBatch` (50), `tonightMaxBatches` (3), `tonightMetaGenres` (3);
  - `enum TonightType { movies, series, both }` con `wire`, `kinds`, `parse`;
  - `enum TonightDuration { any, under90, under120 }` con `wire`, `limit`, `parse`;
  - `class TonightFilters({type, duration, genre})` con `defaults`, `isDefault`, `copyWith`;
  - `bool neverStarted(JellyfinItem series)`, `bool tonightEligible(JellyfinItem item, TonightFilters filters)`, `String tonightMeta(AppLocalizations l, JellyfinItem item)`, `List<String> tonightGenreUnion(Iterable<List<String>> lists)`;
  - `tonightTypeKey`, `tonightDurationKey`, `tonightGenreKey`;
  - `tonightSeenProvider`, `tonightGenresProvider` (family per `TonightType`);
  - `class TonightState({required TonightFilters filters, required AsyncValue<JellyfinItem?> pick})`;
  - `TonightController` con `another()` e `setFilters(TonightFilters next)`, e `tonightControllerProvider`.

- [ ] **Step 1: i test che falliscono**

`test/features/tonight/tonight_logic_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

import '../../support/library_fakes.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  JellyfinItem series({int? episodes, int? unplayed, bool played = false}) =>
      testItem(
          id: 's',
          kind: ItemKind.series,
          recursiveCount: episodes,
          unplayedCount: unplayed,
          played: played);

  test('i valori salvati, e quelli sconosciuti valgono il predefinito', () {
    expect(TonightType.parse('series'), TonightType.series);
    expect(TonightType.parse(null), TonightType.both);
    expect(TonightType.parse('boh'), TonightType.both);
    expect(TonightDuration.parse('90'), TonightDuration.under90);
    expect(TonightDuration.parse('120'), TonightDuration.under120);
    expect(TonightDuration.parse(null), TonightDuration.any);
    expect(TonightType.both.kinds, {ItemKind.movie, ItemKind.series});
  });

  test('i filtri: predefiniti e copia', () {
    expect(TonightFilters.defaults.isDefault, isTrue);
    const drama = TonightFilters(genre: 'Dramma');
    expect(drama.isDefault, isFalse);
    expect(drama.copyWith(genre: null), TonightFilters.defaults);
    expect(drama.copyWith(type: TonightType.movies).genre, 'Dramma');
  });

  test('serie mai iniziata: tanti episodi da vedere quanti ne ha', () {
    expect(neverStarted(series(episodes: 40, unplayed: 40)), isTrue);
    expect(neverStarted(series(episodes: 8, unplayed: 5)), isFalse);
    expect(neverStarted(series(unplayed: 17)), isFalse,
        reason: 'senza RecursiveItemCount non si sa');
    expect(neverStarted(series(episodes: 0, unplayed: 0)), isFalse);
    expect(neverStarted(series(episodes: 4, unplayed: 4, played: true)),
        isFalse);
  });

  test('film: non visti e della durata scelta', () {
    const any = TonightFilters();
    const short = TonightFilters(duration: TonightDuration.under90);
    expect(tonightEligible(testItem(runtimeMinutes: 120), any), isTrue);
    expect(tonightEligible(testItem(runtimeMinutes: 120, played: true), any),
        isFalse);
    expect(tonightEligible(testItem(runtimeMinutes: 89), short), isTrue);
    expect(tonightEligible(testItem(runtimeMinutes: 90), short), isFalse);
    expect(tonightEligible(testItem(runtimeMinutes: null), short), isFalse,
        reason: 'durata sconosciuta');
    expect(
        tonightEligible(testItem(runtimeMinutes: 110),
            const TonightFilters(duration: TonightDuration.under120)),
        isTrue);
  });

  test('il tipo, e la durata che vale solo per i film', () {
    final movie = testItem(runtimeMinutes: 150);
    final fresh = series(episodes: 10, unplayed: 10);
    expect(
        tonightEligible(movie, const TonightFilters(type: TonightType.series)),
        isFalse);
    expect(
        tonightEligible(fresh, const TonightFilters(type: TonightType.movies)),
        isFalse);
    expect(
        tonightEligible(
            fresh, const TonightFilters(duration: TonightDuration.under90)),
        isTrue);
    expect(tonightEligible(testItem(kind: ItemKind.episode), const TonightFilters()),
        isFalse);
  });

  test('la riga dei dati', () {
    expect(
        tonightMeta(
            l,
            testItem(
                year: 2024,
                runtimeMinutes: 166,
                genres: ['Fantascienza', 'Avventura', 'Dramma', 'Azione'])),
        '2024 · 2h 46m · Fantascienza · Avventura · Dramma');
    expect(
        tonightMeta(
            l,
            testItem(
                kind: ItemKind.series,
                year: 2016,
                runtimeMinutes: 55,
                childCount: 3,
                genres: ['Dramma'])),
        '2016 · 3 stagioni · Dramma');
  });

  test('i generi: unione senza doppioni, in ordine', () {
    expect(
        tonightGenreUnion([
          ['Dramma', 'Azione'],
          ['Dramma', 'Anime'],
        ]),
        ['Anime', 'Azione', 'Dramma']);
  });
}
```

`test/features/tonight/tonight_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late SharedPreferences prefs;
  late FakeSessionController session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    library = FakeLibraryApi();
    session = FakeSessionController(const SessionSignedIn(testUser));
  });

  ProviderContainer container() {
    final c = ProviderContainer.test(
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(() => session),
      ],
      retry: (_, _) => null,
    );
    c.listen(tonightControllerProvider, (_, _) {});
    return c;
  }

  JellyfinItem movie(String id) =>
      testItem(id: id, name: id, runtimeMinutes: 100);
  JellyfinItem fresh(String id) => testItem(
      id: id,
      name: id,
      kind: ItemKind.series,
      recursiveCount: 8,
      unplayedCount: 8);
  JellyfinItem started(String id) => testItem(
      id: id,
      name: id,
      kind: ItemKind.series,
      recursiveCount: 8,
      unplayedCount: 3);

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  TonightState state(ProviderContainer c) => c.read(tonightControllerProvider);
  String? pickId(ProviderContainer c) => state(c).pick.value?.id;

  test('i filtri vengono dal profilo, e la prima pescata li usa', () async {
    await prefs.setString(tonightTypeKey, 'series');
    await prefs.setString(tonightDurationKey, '90');
    await prefs.setString(tonightGenreKey, 'Dramma');
    final c = container();
    await settle();
    expect(state(c).filters,
        const TonightFilters(
            type: TonightType.series,
            duration: TonightDuration.under90,
            genre: 'Dramma'));
    final call = library.randomCalls.single;
    expect(call.kinds, {ItemKind.series});
    expect(call.genre, 'Dramma');
    expect(call.limit, tonightBatch);
  });

  test('la prima pescata propone il primo titolo che va bene', () async {
    library.randomPages.add(pageOf([started('s1'), movie('m2'), fresh('s3')]));
    final c = container();
    expect(state(c).pick.isLoading, isTrue);
    await settle();
    expect(pickId(c), 'm2');
    expect(c.read(tonightSeenProvider), {'m2'});
  });

  test('Un altro prende il prossimo della pescata, senza chiamare', () async {
    library.randomPages.add(pageOf([movie('m1'), fresh('s2')]));
    final c = container();
    await settle();
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 's2');
    expect(library.randomCalls, hasLength(1));
  });

  test('finita la pescata se ne fa un\'altra, e i già proposti non tornano',
      () async {
    library.randomPages
      ..add(pageOf([movie('m1')], 200))
      ..add(pageOf([movie('m1'), movie('m2')], 200));
    final c = container();
    await settle();
    expect(pickId(c), 'm1');
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm2');
    expect(library.randomCalls, hasLength(2));
  });

  test('già proposti tutti: si ricomincia', () async {
    library.randomPages.add(pageOf([movie('m1')], 1));
    final c = container();
    await settle();
    expect(pickId(c), 'm1');
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm1', reason: 'invece di "Nessun titolo"');
    expect(library.randomCalls, hasLength(2),
        reason: 'la pescata era già tutto: una sola chiamata in più');
  });

  test('nessun titolo: al massimo tre pescate', () async {
    library.randomPages.add(pageOf([started('s1')], 500));
    final c = container();
    await settle();
    expect(state(c).pick, const AsyncData<JellyfinItem?>(null));
    expect(library.randomCalls, hasLength(tonightMaxBatches));

    library.randomCalls.clear();
    library.randomPages
      ..clear()
      ..add(pageOf([started('s1')], 1));
    await c.read(tonightControllerProvider.notifier).another();
    expect(state(c).pick.value, isNull);
    expect(library.randomCalls, hasLength(1),
        reason: 'il totale stava tutto in una pescata');
  });

  test('errore, poi Un altro riprova', () async {
    library.error = const ServerUnreachableException();
    final c = container();
    await settle();
    expect(state(c).pick.hasError, isTrue);
    library.error = null;
    library.randomPages.add(pageOf([movie('m1')]));
    await c.read(tonightControllerProvider.notifier).another();
    expect(pickId(c), 'm1');
  });

  test('cambiando i filtri si riparte da capo e si ricordano', () async {
    library.randomPages.add(pageOf([movie('m1'), movie('m2')]));
    final c = container();
    await settle();
    await c.read(tonightControllerProvider.notifier).setFilters(
        const TonightFilters(
            type: TonightType.movies,
            duration: TonightDuration.under90,
            genre: 'Azione'));
    await settle();
    expect(prefs.getString(tonightTypeKey), 'movies');
    expect(prefs.getString(tonightDurationKey), '90');
    expect(prefs.getString(tonightGenreKey), 'Azione');
    expect(library.randomCalls.last.genre, 'Azione');
    expect(library.randomCalls.last.kinds, {ItemKind.movie});
    expect(library.randomCalls, hasLength(2),
        reason: 'la coda della pescata di prima non vale più');

    await c
        .read(tonightControllerProvider.notifier)
        .setFilters(TonightFilters.defaults);
    await settle();
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  test('una risposta arrivata dopo un cambio di filtri si ignora', () async {
    final gate = library.randomGate = Completer<void>();
    library.randomPages
      ..add(pageOf([movie('vecchio')]))
      ..add(pageOf([movie('nuovo')]));
    final c = container();
    await settle();
    unawaited(c
        .read(tonightControllerProvider.notifier)
        .setFilters(const TonightFilters(type: TonightType.movies)));
    await settle();
    library.randomGate = null;
    gate.complete();
    await settle();
    expect(pickId(c), 'nuovo');
  });

  test('cambiando account i già proposti ripartono da zero', () async {
    library.randomPages.add(pageOf([movie('m1')]));
    final c = container();
    c.listen(tonightSeenProvider, (_, _) {});
    await settle();
    expect(c.read(tonightSeenProvider), {'m1'});
    session.set(
        const SessionSignedIn(JellyfinUser(id: 'u2', name: 'Luigi')));
    await settle();
    expect(c.read(tonightSeenProvider), isEmpty);
  });
}
```

`sharedPreferencesProvider` è in `lib/app/providers.dart`; se no, importalo da dove lo prende `test/features/settings/settings_test.dart`.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/tonight`
Expected: errori di compilazione (i file non esistono).

- [ ] **Step 3: il codice**

`lib/features/tonight/tonight_logic.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/item_labels.dart';

/// Quanti titoli si pescano per volta (spec M §8.4).
const tonightBatch = 50;

/// Quante pescate al massimo per trovare un titolo nuovo, prima di dire che
/// non ce ne sono (decisione 6 del piano 19c).
const tonightMaxBatches = 3;

/// Quanti generi nella riga dei dati del titolo proposto.
const tonightMetaGenres = 3;

/// Il filtro del tipo (spec M §8.4); [wire] si salva nel profilo.
enum TonightType {
  movies('movies', {ItemKind.movie}),
  series('series', {ItemKind.series}),
  both('both', {ItemKind.movie, ItemKind.series});

  const TonightType(this.wire, this.kinds);

  final String wire;
  final Set<ItemKind> kinds;

  /// Un valore sconosciuto vale [both], il predefinito.
  static TonightType parse(String? raw) =>
      values.firstWhere((type) => type.wire == raw, orElse: () => both);
}

/// Il filtro della durata, solo per i film (spec M §8.4).
enum TonightDuration {
  any('any', null),
  under90('90', Duration(minutes: 90)),
  under120('120', Duration(minutes: 120));

  const TonightDuration(this.wire, this.limit);

  final String wire;

  /// Più corti di così; `null`: qualsiasi durata.
  final Duration? limit;

  static TonightDuration parse(String? raw) => values
      .firstWhere((duration) => duration.wire == raw, orElse: () => any);
}

/// I filtri della finestra.
@immutable
class TonightFilters {
  const TonightFilters({
    this.type = TonightType.both,
    this.duration = TonightDuration.any,
    this.genre,
  });

  static const defaults = TonightFilters();

  final TonightType type;
  final TonightDuration duration;

  /// `null`: tutti i generi.
  final String? genre;

  bool get isDefault => this == defaults;

  static const _keep = Object();

  TonightFilters copyWith({
    TonightType? type,
    TonightDuration? duration,
    Object? genre = _keep,
  }) =>
      TonightFilters(
        type: type ?? this.type,
        duration: duration ?? this.duration,
        genre: identical(genre, _keep) ? this.genre : genre as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is TonightFilters &&
      other.type == type &&
      other.duration == duration &&
      other.genre == genre;

  @override
  int get hashCode => Object.hash(type, duration, genre);

  @override
  String toString() => 'TonightFilters($type, $duration, $genre)';
}

/// Una serie mai iniziata: nessun episodio visto (decisione 3 del piano
/// 19c). Serve `RecursiveItemCount`, che `LibraryApi.randomUnplayed` chiede.
bool neverStarted(JellyfinItem series) {
  final episodes = series.recursiveItemCount;
  return !series.userData.played &&
      episodes != null &&
      episodes > 0 &&
      series.userData.unplayedItemCount == episodes;
}

/// Un titolo da proporre con [filters]: un film non visto della durata
/// scelta, o una serie mai iniziata. La durata vale solo per i film; un
/// film senza durata nota non passa un filtro di durata (decisione 5).
bool tonightEligible(JellyfinItem item, TonightFilters filters) =>
    switch (item.kind) {
      ItemKind.movie => filters.type != TonightType.series &&
          !item.userData.played &&
          _fits(item.runtime, filters.duration.limit),
      ItemKind.series =>
        filters.type != TonightType.movies && neverStarted(item),
      _ => false,
    };

bool _fits(Duration? runtime, Duration? limit) =>
    limit == null || (runtime != null && runtime < limit);

/// "2024 · 2h 46m · Fantascienza · Avventura · Dramma"; per una serie le
/// stagioni al posto della durata.
String tonightMeta(AppLocalizations l, JellyfinItem item) {
  final runtime = item.runtime;
  final seasons = item.childCount;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
    if (item.kind == ItemKind.series && seasons != null)
      l.detailSeasons(seasons),
    ...item.genres.take(tonightMetaGenres),
  ].join(' · ');
}

/// I generi del menu: di uno o due tipi, senza doppioni, in ordine
/// alfabetico (decisione 8 del piano 19c).
List<String> tonightGenreUnion(Iterable<List<String>> lists) =>
    {for (final list in lists) ...list}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
```

`lib/features/tonight/tonight_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../auth/session_controller.dart';
import '../catalog/catalog_controller.dart';
import '../library/library_providers.dart';
import '../profiles/profile_preferences.dart';
import 'tonight_logic.dart';

/// Le preferenze del profilo con i filtri (spec M §8.4).
const tonightTypeKey = 'tonight.type';
const tonightDurationKey = 'tonight.duration';
const tonightGenreKey = 'tonight.genre';

/// I titoli già proposti in questa sessione per l'account collegato: non
/// tornano finché ce ne sono altri (decisione 6 del piano 19c).
class TonightSeen extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Cambiando account si riparte da zero.
    ref.watch(sessionControllerProvider.select((session) =>
        session is SessionSignedIn ? session.user.id : null));
    return const {};
  }

  void add(String id) => state = {...state, id};

  void clear() => state = const {};
}

final tonightSeenProvider =
    NotifierProvider<TonightSeen, Set<String>>(TonightSeen.new);

/// I generi del menu: con "Entrambi" quelli dei film e delle serie insieme
/// (decisione 8 del piano 19c).
final tonightGenresProvider = FutureProvider.autoDispose
    .family<List<String>, TonightType>((ref, type) async {
  final lists = [
    for (final kind in type.kinds) ref.watch(catalogFiltersProvider(kind).future),
  ];
  return tonightGenreUnion(
      [for (final filters in await Future.wait(lists)) filters.genres]);
});

/// La finestra: i filtri e il titolo proposto.
@immutable
class TonightState {
  const TonightState({required this.filters, required this.pick});

  final TonightFilters filters;

  /// Il titolo proposto; `AsyncData(null)`: nessun titolo con questi filtri.
  final AsyncValue<JellyfinItem?> pick;
}

/// Pesca i titoli a gruppi di [tonightBatch] e li propone uno alla volta,
/// senza ripetere quelli già proposti (spec M §8.4).
class TonightController extends Notifier<TonightState> {
  /// I titoli dell'ultima pescata non ancora proposti.
  final _queue = <JellyfinItem>[];

  /// Cresce a ogni pescata: la risposta di una pescata superata si ignora.
  var _generation = 0;

  @override
  TonightState build() {
    final prefs = ref.read(profilePreferencesProvider);
    final genre = prefs.getString(tonightGenreKey);
    // La prima pescata parte appena la finestra c'è.
    unawaited(Future.microtask(another));
    return TonightState(
      filters: TonightFilters(
        type: TonightType.parse(prefs.getString(tonightTypeKey)),
        duration: TonightDuration.parse(prefs.getString(tonightDurationKey)),
        // In un profilo "nessun valore" è una stringa vuota (`clearString`).
        genre: genre == null || genre.isEmpty ? null : genre,
      ),
      pick: const AsyncLoading(),
    );
  }

  /// Cambia i filtri: si ricordano per il profilo e si riparte da capo.
  Future<void> setFilters(TonightFilters next) async {
    if (next == state.filters) return;
    _queue.clear();
    state = TonightState(filters: next, pick: state.pick);
    unawaited(another());
    final prefs = ref.read(profilePreferencesProvider);
    final genre = next.genre;
    await Future.wait([
      prefs.setString(tonightTypeKey, next.type.wire),
      prefs.setString(tonightDurationKey, next.duration.wire),
      genre == null
          ? prefs.clearString(tonightGenreKey)
          : prefs.setString(tonightGenreKey, genre),
    ]);
  }

  /// "Un altro", e la prima pescata: il prossimo titolo non ancora proposto.
  Future<void> another() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    final filters = state.filters;
    state = TonightState(filters: filters, pick: const AsyncLoading());
    try {
      final item = await _next(filters, generation);
      if (!ref.mounted || generation != _generation) return;
      if (item != null) ref.read(tonightSeenProvider.notifier).add(item.id);
      state = TonightState(filters: filters, pick: AsyncData(item));
    } on Object catch (error, stack) {
      if (!ref.mounted || generation != _generation) return;
      state = TonightState(filters: filters, pick: AsyncError(error, stack));
    }
  }

  Future<JellyfinItem?> _next(TonightFilters filters, int generation) async {
    final seen = ref.read(tonightSeenProvider);
    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      if (!seen.contains(item.id)) return item;
    }
    final api = ref.read(libraryApiProvider);
    final userId = ref.read(currentUserIdProvider);
    final repeats = <String, JellyfinItem>{};
    for (var batch = 0; batch < tonightMaxBatches; batch++) {
      final page = await api.randomUnplayed(userId,
          kinds: filters.type.kinds, genre: filters.genre, limit: tonightBatch);
      if (!ref.mounted || generation != _generation) return null;
      final fresh = <String, JellyfinItem>{};
      for (final item in page.items) {
        if (!tonightEligible(item, filters)) continue;
        if (seen.contains(item.id)) {
          repeats[item.id] = item;
        } else {
          fresh[item.id] = item;
        }
      }
      if (fresh.isNotEmpty) {
        final items = fresh.values.toList();
        _queue.addAll(items.skip(1));
        return items.first;
      }
      // La pescata era già tutto: pescare ancora non serve.
      if (page.totalCount <= tonightBatch) break;
    }
    if (repeats.isEmpty) return null;
    // Già proposti tutti: si ricomincia con quelli (spec M §8.4, "finché ce
    // ne sono altri").
    ref.read(tonightSeenProvider.notifier).clear();
    final again = repeats.values.toList();
    _queue.addAll(again.skip(1));
    return again.first;
  }
}

final tonightControllerProvider =
    NotifierProvider.autoDispose<TonightController, TonightState>(
        TonightController.new);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/tonight`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/tonight test/features/tonight
git commit -m "feat(app): tonight picks, filters remembered per profile"
```

### Task 9: la finestra e il dado nella Home

**Files:**
- Create: `lib/features/tonight/tonight_dialog.dart`
- Modify: `lib/features/home/hero_carousel.dart`, `lib/features/home/home_screen.dart`
- Test: `test/features/tonight/tonight_dialog_test.dart`, `test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 8; `showWfDialog`, `WfButton`, `FilterPicker`, `BackdropImage`, `imageUrlsProvider`, `playItem`, `openItem`.
- Produces:
  - `sealed class TonightChoice` con `TonightPlay` e `TonightDetails` (`item`);
  - `Future<TonightChoice?> showTonightDialog(BuildContext context)`;
  - `Future<void> openTonight(BuildContext context, WidgetRef ref)`;
  - `TonightDialog`, `TonightButton`;
  - `HeroCarousel({required List<JellyfinItem> items, Widget? corner})`;
  - chiavi: `tonight-button`, `tonight-dice`, `tonight-type`, `tonight-duration`, `tonight-another`, `tonight-details`, `tonight-play`.

- [ ] **Step 1: i test che falliscono**

`test/features/tonight/tonight_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/features/tonight/tonight_dialog.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';

import '../../support/fake_session_controller.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeLibraryApi library;
  late SharedPreferences prefs;
  TonightChoice? choice;
  var closed = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    library = FakeLibraryApi()
      ..filtersByKind[ItemKind.movie] =
          const LibraryFilters(genres: ['Azione', 'Dramma'])
      ..filtersByKind[ItemKind.series] =
          const LibraryFilters(genres: ['Anime', 'Dramma']);
    choice = null;
    closed = false;
  });

  final dune = testItem(
      id: 'm1',
      name: 'Dune',
      year: 2021,
      runtimeMinutes: 155,
      genres: ['Fantascienza'],
      rating: 8.1,
      overview: 'Paul Atreides arriva su Arrakis.');
  final alien = testItem(id: 'm2', name: 'Alien', runtimeMinutes: 117);

  Future<void> openDialog(WidgetTester tester,
      {MotionLevel motion = MotionLevel.reduced}) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                choice = await showTonightDialog(context);
                closed = true;
              },
              child: const Text('apri'),
            ),
          ),
        ),
      ),
      motion: motion,
      overrides: [
        libraryApiProvider.overrideWithValue(library),
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('propone un titolo con i suoi dati', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    expect(find.text('Cosa guardo stasera?'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('2021 · 2h 35m · Fantascienza'), findsOneWidget);
    expect(find.text('8.1'), findsOneWidget);
    expect(find.text('Paul Atreides arriva su Arrakis.'), findsOneWidget);
    expect(find.text('Riproduci'), findsOneWidget);
    expect(find.text('Dettagli'), findsOneWidget);
    expect(find.text('Un altro'), findsOneWidget);
  });

  testWidgets('Un altro: il prossimo, e il dado gira', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester, motion: MotionLevel.full);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alien'), findsOneWidget);
    final dice =
        tester.widget<AnimatedRotation>(find.byKey(const Key('tonight-dice')));
    expect(dice.turns, 1);
    expect(dice.duration, WfMotion.slow);
  });

  testWidgets('con le animazioni ridotte il dado non gira', (tester) async {
    library.randomPages.add(pageOf([dune, alien]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-another')));
    await tester.pump();
    final dice =
        tester.widget<AnimatedRotation>(find.byKey(const Key('tonight-dice')));
    expect(dice.duration, Duration.zero);
  });

  testWidgets('la durata è ferma con Serie', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    await tester.tap(find.text('Serie'));
    await tester.pump();
    await tester.pump();
    final duration = tester.widget<SegmentedButton<TonightDuration>>(
        find.byKey(const Key('tonight-duration')));
    expect(duration.onSelectionChanged, isNull);
    expect(library.randomCalls.last.kinds, {ItemKind.series});
    expect(prefs.getString(tonightTypeKey), 'series');
  });

  testWidgets('con Entrambi i generi dei film e delle serie', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    final picker = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>));
    expect([for (final item in picker.items!) (item.child as Text).data],
        ['Tutti i generi', 'Anime', 'Azione', 'Dramma']);
  });

  testWidgets('nessun titolo: il messaggio e Togli i filtri', (tester) async {
    await prefs.setString(tonightGenreKey, 'Dramma');
    library.randomPages.add(pageOf([], 0));
    await openDialog(tester);
    expect(find.text('Nessun titolo con questi filtri'), findsOneWidget);
    await tester.tap(find.text('Togli i filtri'));
    await tester.pump();
    await tester.pump();
    expect(library.randomCalls.last.genre, isNull);
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  testWidgets('un genere salvato che non c\'è più torna a tutti i generi',
      (tester) async {
    await prefs.setString(tonightGenreKey, 'Western');
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    expect(library.randomCalls.last.genre, isNull);
    expect(prefs.getString(tonightGenreKey), isNull);
  });

  testWidgets('errore: il messaggio e Riprova', (tester) async {
    library.error = const ServerUnreachableException();
    await openDialog(tester);
    expect(find.text('Riprova'), findsOneWidget);
    library.error = null;
    library.randomPages.add(pageOf([dune]));
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('Dettagli e Riproduci chiudono con la scelta', (tester) async {
    library.randomPages.add(pageOf([dune]));
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('tonight-details')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
    expect(choice, isA<TonightDetails>());
    expect(choice!.item.id, 'm1');

    await tester.tap(find.text('apri'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('tonight-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choice, isA<TonightPlay>());
  });
}
```

La seconda apertura nello stesso test ripesca: `randomPages` ripete l'ultima pagina, e i già proposti ricominciano (decisione 6), quindi c'è ancora "Dune".

In `test/features/home/home_screen_test.dart`, in fondo a `main` (`FakeLibraryApi.randomPages` serve solo al test che apre la finestra):

```dart
  testWidgets('il dado sul carosello', (tester) async {
    someRows();
    await pumpHome(tester);
    expect(
        find.descendant(
            of: find.byType(HeroCarousel),
            matching: find.byKey(const Key('tonight-button'))),
        findsOneWidget);
  });

  testWidgets('senza carosello il dado è in cima alle righe, a destra',
      (tester) async {
    library.resumeItems = [
      testItem(id: 'r1', name: 'Oppenheimer', playedPercentage: 30)
    ];
    await pumpHome(tester);
    final button = find.byKey(const Key('tonight-button'));
    expect(button, findsOneWidget);
    expect(tester.getTopRight(button).dx, greaterThan(1440 - 100));
    expect(tester.getTopLeft(button).dy,
        lessThan(tester.getTopLeft(find.text('Continua a guardare')).dy));
  });

  testWidgets('il dado anche nella Home vuota', (tester) async {
    await pumpHome(tester);
    expect(find.text("Qui non c'è ancora niente."), findsOneWidget);
    expect(find.byKey(const Key('tonight-button')), findsOneWidget);
  });

  testWidgets('dal dado, Dettagli apre la scheda del titolo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final shared = await SharedPreferences.getInstance();
    library.randomPages.add(pageOf([testItem(id: 'm9', name: 'Heat')]));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: HomeScreen())),
      GoRoute(
          path: '/item/:id',
          builder: (context, state) =>
              Text('scheda ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router,
        surfaceSize: const Size(1440, 1600),
        overrides: [
          ...homeOverrides(library: library, home: home, prefs: prefs),
          sharedPreferencesProvider.overrideWithValue(shared),
        ]);
    await settle(tester);
    await tester.tap(find.byKey(const Key('tonight-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tonight-details')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('scheda m9'), findsOneWidget);
  });
```

Aggiungi gli import che mancano (`shared_preferences`, `package:wonderflix/app/providers.dart`, `hero_carousel.dart`, `go_router`). Se il numero 100 del secondo test non basta per il margine del pulsante, controlla che il bordo destro del pulsante sia oltre la metà della finestra: conta che stia a destra.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/tonight test/features/home/home_screen_test.dart`
Expected: errori di compilazione (`tonight_dialog.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/tonight/tonight_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../catalog/catalog_filters_bar.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// Larghezza della finestra.
const tonightDialogWidth = 720.0;

/// Altezza dello spazio del titolo proposto: resta la stessa mentre si
/// pesca, così la finestra non salta.
const tonightPickHeight = 360.0;

/// Altezza dello sfondo del titolo proposto.
const tonightBackdropHeight = 200.0;

/// Quello che si è scelto nella finestra.
sealed class TonightChoice {
  const TonightChoice(this.item);

  final JellyfinItem item;
}

class TonightPlay extends TonightChoice {
  const TonightPlay(super.item);
}

class TonightDetails extends TonightChoice {
  const TonightDetails(super.item);
}

Future<TonightChoice?> showTonightDialog(BuildContext context) =>
    showWfDialog<TonightChoice>(
      context,
      maxWidth: tonightDialogWidth,
      semanticLabel: AppLocalizations.of(context).tonightButton,
      builder: (_) => const TonightDialog(),
    );

/// Apre la finestra e fa quello che si è scelto con il [context] di chi l'ha
/// aperta: quello della finestra chiusa non può più navigare (decisione 7
/// del piano 19c).
Future<void> openTonight(BuildContext context, WidgetRef ref) async {
  final choice = await showTonightDialog(context);
  if (!context.mounted) return;
  switch (choice) {
    case TonightPlay(:final item):
      await playItem(context, ref, item);
    case TonightDetails(:final item):
      openItem(context, item);
    case null:
      break;
  }
}

/// "Cosa guardo stasera?" con il dado (spec M §8.4).
class TonightButton extends ConsumerWidget {
  const TonightButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => WfButton.secondary(
        key: const Key('tonight-button'),
        label: AppLocalizations.of(context).tonightButton,
        icon: LucideIcons.dices,
        onPressed: () => unawaited(openTonight(context, ref)),
      );
}

/// La finestra (spec M §8.4): filtri, il titolo proposto, Riproduci,
/// Dettagli e "Un altro".
class TonightDialog extends ConsumerStatefulWidget {
  const TonightDialog({super.key});

  @override
  ConsumerState<TonightDialog> createState() => _TonightDialogState();
}

class _TonightDialogState extends ConsumerState<TonightDialog> {
  /// Giri del dado: uno a ogni "Un altro".
  var _spins = 0;

  TonightController get _controller =>
      ref.read(tonightControllerProvider.notifier);

  void _another() {
    setState(() => _spins++);
    unawaited(_controller.another());
  }

  void _filters(TonightFilters next) =>
      unawaited(_controller.setFilters(next));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final state = ref.watch(tonightControllerProvider);
    final filters = state.filters;
    final genres = ref.watch(tonightGenresProvider(filters.type)).value ??
        const <String>[];
    // Un genere che non c'è più torna a "Tutti i generi" (decisione 8 del
    // piano 19c).
    ref.listen(tonightGenresProvider(filters.type), (_, next) {
      final current = ref.read(tonightControllerProvider).filters;
      final list = next.value;
      final genre = current.genre;
      if (genre != null && list != null && !list.contains(genre)) {
        _filters(current.copyWith(genre: null));
      }
    });
    final pick = state.pick.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AnimatedRotation(
              key: const Key('tonight-dice'),
              turns: _spins.toDouble(),
              duration: motion.isReduced ? Duration.zero : WfMotion.slow,
              curve: WfMotion.emphasized,
              child: const Icon(LucideIcons.dices,
                  size: 24, color: WfColors.gold),
            ),
            const SizedBox(width: 12),
            Text(l.tonightButton,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TonightType>(
              key: const Key('tonight-type'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: TonightType.movies,
                    label: Text(l.tonightTypeMovies)),
                ButtonSegment(
                    value: TonightType.series,
                    label: Text(l.tonightTypeSeries)),
                ButtonSegment(
                    value: TonightType.both, label: Text(l.tonightTypeBoth)),
              ],
              selected: {filters.type},
              onSelectionChanged: (selection) =>
                  _filters(filters.copyWith(type: selection.first)),
            ),
            SegmentedButton<TonightDuration>(
              key: const Key('tonight-duration'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: TonightDuration.any,
                    label: Text(l.tonightDurationAny)),
                ButtonSegment(
                    value: TonightDuration.under90,
                    label: Text(l.tonightDuration90)),
                ButtonSegment(
                    value: TonightDuration.under120,
                    label: Text(l.tonightDuration120)),
              ],
              selected: {filters.duration},
              // La durata vale solo per i film (spec M §8.4).
              onSelectionChanged: filters.type == TonightType.series
                  ? null
                  : (selection) =>
                      _filters(filters.copyWith(duration: selection.first)),
            ),
            FilterPicker<String?>(
              value: filters.genre,
              items: {
                null: l.catalogAllGenres,
                for (final genre in genres) genre: genre,
              },
              onChanged: (genre) => _filters(filters.copyWith(genre: genre)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: tonightPickHeight,
          child: switch (state.pick) {
            AsyncData(value: final item?) => _TonightPick(item: item),
            AsyncData() => _TonightMessage(
                text: l.tonightEmpty,
                action: filters.isDefault ? null : l.tonightClearFilters,
                onAction: () => _filters(TonightFilters.defaults),
              ),
            AsyncError(:final error) => _TonightMessage(
                text: describeError(l, error),
                action: l.retry,
                onAction: _another,
              ),
            _ => const SkeletonBox(height: tonightPickHeight),
          },
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            WfButton.secondary(
              key: const Key('tonight-another'),
              label: l.tonightAnother,
              icon: LucideIcons.dices,
              onPressed: state.pick.isLoading ? null : _another,
            ),
            WfButton.secondary(
              key: const Key('tonight-details'),
              label: l.actionDetails,
              icon: LucideIcons.info,
              onPressed: pick == null
                  ? null
                  : () => Navigator.of(context).pop(TonightDetails(pick)),
            ),
            WfButton.primary(
              key: const Key('tonight-play'),
              label: l.actionPlay,
              icon: LucideIcons.play,
              onPressed: pick == null
                  ? null
                  : () => Navigator.of(context).pop(TonightPlay(pick)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Il titolo proposto: sfondo, titolo, dati, voto e trama.
class _TonightPick extends ConsumerWidget {
  const _TonightPick({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final rating = item.communityRating;
    const muted = TextStyle(color: WfColors.creamMuted);
    return Column(
      key: ValueKey('tonight-pick-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: tonightBackdropHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BackdropImage(
                    backdrop: urls.backdrop(item), fallback: urls.poster(item)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [WfColors.bg, Colors.transparent],
                      stops: [0, 0.6],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WfText.display(32)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tonightMeta(l, item), style: muted),
            if (rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
                  const SizedBox(width: 4),
                  Text(rating.toStringAsFixed(1),
                      style: const TextStyle(
                          color: WfColors.gold, fontWeight: FontWeight.w600)),
                ],
              ),
          ],
        ),
        if (item.overview case final overview?) ...[
          const SizedBox(height: 8),
          Text(overview, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

/// Nessun titolo, o un errore: il messaggio e, se c'è, un'azione.
class _TonightMessage extends StatelessWidget {
  const _TonightMessage(
      {required this.text, required this.action, required this.onAction});

  final String text;
  final String? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WfColors.creamMuted)),
          if (label != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    );
  }
}
```

In `lib/features/home/hero_carousel.dart`:
- sotto le costanti:

```dart
/// Distanza dal basso del pulsante nell'angolo del carosello: sopra i
/// pallini (spec M §8.4).
const heroCornerBottom = 56.0;
```

- il costruttore diventa `const HeroCarousel({super.key, required this.items, this.corner});`, con il campo:

```dart
  /// In basso a destra, sopra i pallini: il pulsante "Cosa guardo
  /// stasera?" (spec M §8.4).
  final Widget? corner;
```

- nello `Stack`, dopo `Positioned(right: 32, bottom: 20, child: _dots(motion)),`:

```dart
              if (widget.corner case final corner?)
                Positioned(right: 32, bottom: heroCornerBottom, child: corner),
```

In `lib/features/home/home_screen.dart` (import di `../tonight/tonight_dialog.dart`):
- `HeroCarousel(items: featuredItems)` diventa `HeroCarousel(items: featuredItems, corner: const TonightButton())`;
- nella `ListView` dei dati, prima di `...shown,`: `if (featuredItems.isEmpty) const _TonightCorner(),`;
- nella "Home vuota", tra il testo e `_CustomizeLink`: `const Padding(padding: EdgeInsets.only(top: 16), child: TonightButton()),`;
- in fondo al file:

```dart
/// Senza carosello il dado sta in cima alle righe, a destra (spec M §8.4).
class _TonightCorner extends StatelessWidget {
  const _TonightCorner();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(32, 16, 32, 0),
        child: Align(alignment: Alignment.centerRight, child: TonightButton()),
      );
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/tonight test/features/home`
Expected: PASS. Poi `flutter analyze` e la suite intera.

- [ ] **Step 5: commit**

```powershell
git add lib/features/tonight lib/features/home test/features/tonight test/features/home
git commit -m "feat(app): tonight dialog and the dice button on the Home"
```

## Gruppo D — chiusura

### Task 10: STOP — review finale e prova con l'utente (lo fa l'orchestratore)

Il subagent si ferma qui.

1. **Review finale del branch** (modello più capace) con il pacchetto della review, poi un solo giro di correzioni e una nuova review mirata, come nel 19b.
2. **Build di prova:** copia `config/wonderflix.json` nel worktree, poi `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Senza il flag l'exe mostra "Configurazione mancante".
3. **Prova con l'utente sul server vero** (plugin 1.7.0 di prova, con Sonarr e Radarr configurati):
   - **Home per tutti** (Amministrazione → WonderFlix):
     - spegnere una riga e riaccenderla, cambiare l'ordine, "Salva": la Home dell'admin cambia subito;
     - controllare la Home di un altro account (`serveradmin`) dopo un riavvio dell'app, perché le righe dell'admin restano in memoria 5 minuti;
     - "Ripristina" con la conferma;
     - alla fine la Home dell'admin torna a `null`.
   - **Impostazioni → Home:**
     - spostare (trascinando, con le frecce, con Alt+↑/↓) e nascondere righe: la Home cambia;
     - il link "Personalizza la Home" in fondo alla Home porta alla sezione;
     - "Ripristina";
     - alla fine l'utente rimette i suoi ritocchi come preferisce.
   - **Sonarr e Radarr:**
     - "Prova collegamento", con tutti e due collegati e le versioni;
     - **Sonarr irraggiungibile, solo se l'utente lo vuole:**
       - l'orchestratore salva prima la configurazione del plugin, poi scrive un indirizzo sbagliato con l'API di configurazione;
       - la Home si apre lo stesso, senza "Serie in arrivo", e la card dice "Non raggiungibile: controlla l'indirizzo";
       - poi rimette l'indirizzo giusto e controlla che la configurazione sia uguale alla copia.
   - **Cosa guardo stasera?:**
     - tutti i filtri e "Un altro";
     - "Riproduci" su una serie mai iniziata parte dal primo episodio;
     - "Dettagli";
     - i filtri si ritrovano riaprendo la finestra.
   - **Lettura da un account non admin:** solo se l'utente crea un account di prova; altrimenti resta come in §14.2 della spec.
4. Aspetta l'esito dell'utente. Le modifiche chieste durante la prova si fanno con TDD nel worktree, prima del merge.

### Task 11: allineamento della spec e checklist

**Files:**
- Modify: `docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`, `docs/RELEASING.md`
- Modify: `docs/superpowers/plans/2026-10-11-wonderflix-19c-home-config-tonight.md` (solo una voce "Dalle review dei gruppi", se ci sono differenze)

- [ ] **Step 1: la spec**

Controllando ogni frase sul codice:
- **Stato:** piano 19c realizzato e provato, con la data; release (si completa nella sezione Release).
- **§8.4:** le decisioni 3, 4, 5, 6, 7, 8 e 15 del piano (serie mai iniziate con `RecursiveItemCount`, stagioni con `ChildCount`, durata solo per i film, pescate, scelta restituita dalla finestra, generi, posizione del dado).
- **§8.5:** le decisioni 9, 10, 11, 14 e 16; togli le "Note per il 19c" che sono diventate codice e scrivi cosa fa il codice.
- **§8.6:** le decisioni 12 e 13.
- **§10:** le chiavi che non ci sono (`tonightGenreAll`, `tonightSeasons`) e quella nuova (`homeRowsBecauseYouWatched`), decisioni 1 e 2.
- **§12.2:** i test del 19c, con il numero finale della suite.
- **§12.3 e §14:** le prove del Task 10, con l'esito.
- **§15:** 19c realizzato.
- Ogni altra differenza venuta fuori nei task, con il motivo.

- [ ] **Step 2: la checklist**

In `docs/RELEASING.md`, nella checklist dei test manuali, prima di "Aggiornamento da una versione precedente":

```markdown
- [ ] Home (plugin 1.7.0): Serie in arrivo e Film in arrivo con i clic (scheda della serie o pagina Seerr); Perché hai visto X, Le mie richieste, Continua la saga.
- [ ] Impostazioni → Home: sposta (trascinando, con le frecce, con Alt+↑/↓) e nascondi righe, la Home cambia; "Ripristina la Home predefinita"; il link "Personalizza la Home" in fondo alla Home.
- [ ] Amministrazione → WonderFlix → "Home per tutti": spegni e riaccendi una riga, cambia l'ordine, "Salva"; "Ripristina" con la conferma. "Sonarr e Radarr": "Prova collegamento".
- [ ] "Cosa guardo stasera?" (il dado sul carosello): filtri, "Un altro", "Riproduci" e "Dettagli"; i filtri restano riaprendo.
```

- [ ] **Step 3: commit**

```powershell
git add docs
git commit -m "docs: align the Home spec with plan 19c"
```

### Task 12: merge (lo fa l'orchestratore)

Dopo l'OK dell'utente sulla prova: merge fast-forward su `main`, push, rimozione del worktree (con `cmd /c rd /s /q "\\?\<percorso>"` se `build/` ha percorsi troppo lunghi) e del branch.

## Release (orchestratore, dopo il merge)

Ogni passo che pubblica (push dei tag, manifest, pubblicazione della release, installazione sul server) va fatto con l'OK dell'utente.

1. **Plugin 1.7.0** (vedi `docs/RELEASING.md`, sezione del plugin):
   - il csproj è già a `1.7.0` e `meta.template.json` ha già la Home e le uscite nella descrizione e nell'overview;
   - `git tag watch-party-plugin-v1.7.0` e push del tag. Il workflow pubblica una **pre-release** con `wonderflix-watch-party_1.7.0.zip` e `.zip.md5`; `releases/latest` resta l'app;
   - **controllo dei riferimenti** della dll della release contro Jellyfin 10.11.9 (progetto `refprobe` nella scratchpad, da ricreare come nel piano 18c). Atteso: 0 non risolti;
   - in `jellyfin-plugin-watch-party/manifest.json`, una voce in cima a `versions`:
     - `"version": "1.7.0.0"`, `"targetAbi": "10.11.0.0"`;
     - `sourceUrl` della pre-release, `checksum` uguale al contenuto del `.md5`, `timestamp` in UTC;
     - `changelog` in italiano: "Home su misura per WonderFlix 0.13.0: righe e ordine della Home scelti dall'admin, le uscite di Sonarr e Radarr (Serie in arrivo, Film in arrivo) e la prova del collegamento. Sonarr e Radarr si configurano nella pagina del plugin.";
   - aggiorna `description` e `overview` del manifest come in `meta.template.json`;
   - commit `chore: publish the watch party plugin 1.7.0`, push. Il Catalogo può mostrare la 1.6.0 ancora per qualche minuto (cache di `raw.githubusercontent.com`): si aspetta, senza rifare il push.
2. **Server:**
   - controlla che nessuno stia guardando;
   - `app-jellyfin stop`;
   - sposta la cartella di prova `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.7.0.0` in `~/wfwp-backup/1.7.0.0-prova`, e la configurazione in `~/wfwp-backup/config-1.7.0-prima-del-catalogo.xml`;
   - `app-jellyfin start`;
   - l'installazione dal Catalogo la fa l'utente (Dashboard → Plugin → Catalogo), oppure l'orchestratore con l'API come nel 18c, ma solo con l'OK esplicito dell'utente;
   - riavvio, poi:
     - nel log `Loaded plugin: "WonderFlix Watch Party" "1.7.0.0"`;
     - l'md5 della dll uguale a quello della dll nello zip;
     - nella configurazione Sonarr, Radarr, Seerr, bot e SMTP al loro posto e `HomeRows` com'era;
     - in `Info` le funzioni `home`, `upcomingSeries`, `upcomingMovies`.
3. **App 0.13.0, non obbligatoria** (vedi `docs/RELEASING.md`, sezione dell'app):
   - versione nel `pubspec.yaml`, commit `chore: release 0.13.0`, tag `v0.13.0`, push;
   - il workflow crea la bozza con `WonderFlix-Setup-0.13.0.exe` e `.sha256`;
   - le note in italiano le scrivo io nella bozza, senza `min-version`. Devono dire:
     - la Home su misura: l'admin sceglie righe e ordine per tutti, ognuno le sposta e le nasconde da Impostazioni → Home (anche dal link "Personalizza la Home"), per il suo account su tutti i PC;
     - le righe nuove: Perché hai visto X, Le mie richieste, Continua la saga, Serie in arrivo e Film in arrivo;
     - "Cosa guardo stasera?" con il dado nella Home;
     - per gli admin le card "Home per tutti" e "Sonarr e Radarr";
     - che la Home dell'admin e le righe "In arrivo" vogliono il plugin 1.7.0. Senza, valgono l'ordine predefinito e i ritocchi di ognuno;
   - la pubblica l'utente.
4. **Documenti:**
   - `docs/IDEE.md`: esce l'idea 15; fra le fatte entra "Spec M — Home su misura (plugin 1.7.0, app 0.13.0)";
   - spec: "Stato: realizzata; plugin 1.7.0 e app 0.13.0 pubblicati il …", e in §13/§15 la build di prova sostituita dal Catalogo;
   - commit `docs: Spec M done in the ideas list`, push.
5. **Fuori dal piano, da proporre all'utente:** Home Screen Sections su jellyfin-web ha ancora gli indirizzi vecchi di Sonarr e Radarr (`vapor`): si possono correggere a parte.
