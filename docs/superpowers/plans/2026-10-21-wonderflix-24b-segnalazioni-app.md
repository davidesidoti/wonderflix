# WonderFlix — Piano 24b: segnalazioni e sottotitoli, app 0.18.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec R per tutti gli utenti e per chi gestisce i sottotitoli:
- **nucleo:** modelli e chiamate di segnalazioni, sottotitoli e info tecniche; il permesso sottotitoli; la funzione `reports`; i testi;
- **cassetta:** le voci `ReportPending` e `ReportResolved`;
- **dettaglio:** il menu "⋯" su film, serie, stagione ed episodio, con "Segnala un problema", "Info tecniche" e "Sottotitoli…";
- **sottotitoli:** la finestra per cercare, scaricare, caricare ed eliminare, anche dal pannello tracce del player, con la traccia nuova aggiunta senza fermare il video quando si può;
- **admin:** il riquadro delle segnalazioni nel dettaglio e la card nella dashboard;
- **versione:** app 0.18.0, build per la prova a mano, poi release insieme al plugin 1.12.0.

Gli strumenti solo admin per i metadati (modifica, identifica, aggiorna, locandina e sfondo) sono il piano 24c.

**Architecture:**
- **Nucleo in `lib/core/`:**
  - `reports/` (`report_models.dart`, `reports_api.dart`);
  - `subtitles/` (`subtitle_models.dart`, `subtitles_api.dart`);
  - `jellyfin/media_info_models.dart`, con la lettura in `LibraryApi.mediaInfo`.
  Le API seguono `MatchApi`: un'eccezione tipata, con il motivo del 409 letto da `{Reason}`.
- **Funzioni:** in `lib/features/reports/`, `lib/features/subtitles/` e `lib/features/detail/item_actions_menu.dart`. I pannelli sono finestre `showWfDialog`, come nella bozza approvata.
- **Player:** chiama `PlayerController.refreshSubtitleStreams()`, che rilegge `PlaybackInfo` e aggiunge le tracce esterne nuove senza ripartire.

**Tech Stack:** Flutter 3.47.5 (Windows), Dart, Riverpod 3, go_router, dio (`JellyfinHttp`), `file_selector`, lucide_icons_flutter, `flutter_test`, `fake_async`. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md` (§3, §6.2–6.5 per i JSON, §7.1–7.7, §8, §9, §10, §11.2, §11.3, §13). Il plugin 1.12.0 è già su `main` (piano 24a) e gira sul server come build di prova. Se il codice del plugin diverge da questo piano, vale il plugin: correggi il parsing e segnalalo.

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 8):
1. **Versioni:** questo piano chiude con l'app **0.18.0**, rilasciata con il plugin 1.12.0 (spec §13). Il piano 24c sarà la 0.19.0. La spec §4 e §7.12 mettono tutto nella 0.18.0: si corregge nel Task 8.
2. **Release non obbligatoria:** l'app 0.17 continua a funzionare con il plugin 1.12.0. La riga `min-version` resta quella di prima, salvo diversa indicazione dell'utente al rilascio.
3. **La funzione `reports` non dipende dall'accesso ai watch party** (a differenza di `ratings`): vale per tutti quelli che hanno il plugin.
4. **Notifica di un episodio:** apre la scheda della serie (`/item/{TitleId}`) senza stagione selezionata, perché la voce ha i numeri ma non l'id della stagione. Una segnalazione sulla **stagione** apre invece `/item/{TitleId}?season={ItemId}`.
5. **`showSubtitlesDialog` prende id e titolo, non un `JellyfinItem`**, così la aprono allo stesso modo il menu, il riquadro admin (che ha solo i dati della segnalazione) e il player.
6. **Info tecniche e tracce presenti** si leggono da `GET /Items/{id}?userId=&fields=MediaSources` con un modello proprio (`ItemMediaInfo`). `JellyfinItem` resta com'è.
7. **Attesa della traccia nuova:** prima della chiamata si fotografano gli indici delle tracce esterne; dopo, ogni 2 s per al massimo 20 s, si rilegge `ItemMediaInfo` finché compare un indice esterno nuovo. Vale per download e caricamento.
8. **Traccia nuova nel player** (spec, decisione 21). `refreshSubtitleStreams()` rilegge `PlaybackInfo` con la stessa versione e le stesse tracce:
   - **aggiunta senza fermarsi** solo se tutte le tracce di prima ci sono ancora con lo stesso indice e lo stesso tipo, e tutte le tracce sottotitoli nuove hanno consegna esterna (`deliveredExternally`);
   - **altrimenti** "Il sottotitolo sarà disponibile dalla prossima riproduzione".
   La traccia nuova non si attiva da sola.
9. **Riquadro admin** nella `ListView` del dettaglio, subito dopo `DetailHeader`, **fuori** dalle `StaggerItem`: `detailEntranceCount` resta 9.
10. **Scorciatoie del riquadro in questo piano** (spec, decisione 20): solo "Cerca sottotitoli", su segnalazioni `Subtitles` di un film o di un episodio. "Identifica" e "Modifica metadati" arrivano con il 24c, che le aggiunge allo stesso punto (`reportShortcut`).
11. **Menu "⋯" estendibile:** l'elenco delle voci è una funzione pura (`itemActionGroups`) con un gruppo admin vuoto in questo piano; il 24c aggiunge le sue voci lì.
12. **Lingue dei sottotitoli:** le voci del menu sono quelle di `playbackLanguages` (`user_config_api.dart`, già nell'app). All'inizio vale `LanguagePreferences.subtitleLanguage` se è fra quelle, altrimenti `ita`.
13. **Testi:** in italiano nel piano (Task 1); l'inglese lo scrive chi esegue, nello stesso tono degli altri testi inglesi.

## Global Constraints

- App **0.18.0** (`pubspec.yaml`). Nessuna dipendenza nuova.
- **Endpoint del plugin 1.12.0** sotto `/WonderFlixWatchParty` (spec §6.2, §6.4):
  - `POST Reports` `{ItemId, Type, Note?}` → 200 `ReportDto`;
  - `GET Reports/Mine?itemId=` → `{Items:[ReportDto]}`;
  - `GET Reports` (admin) → `{Items:[…]}`;
  - `POST Reports/{id}/Resolve` `{Outcome, Note?}` → 204;
  - `GET Subtitles/{itemId}/Search?language=&perfectMatch=` → `[RemoteSubtitleDto]`;
  - `POST Subtitles/{itemId}/Download` `{SubtitleId}` → 204;
  - `POST Subtitles/{itemId}/Upload` `{Language, Format, IsForced, IsHearingImpaired, Data}` → 204.
  Errori:
  - 400 = richiesta non valida;
  - 403 = permesso;
  - 409 `{"Reason":"LimitReached"|"Closed"}`;
  - 502 = fallito (`{"Reason":"DownloadFailed"|"UploadFailed"}`, la ricerca senza corpo).
  Il plugin non risponde mai 404: un 404 è un plugin vecchio.
- **Jellyfin diretto:**
  - `DELETE /Videos/{itemId}/Subtitles/{index}` (solo admin) → 204;
  - `GET /Items/{id}?userId=&fields=MediaSources`;
  - `POST /Items/{id}/PlaybackInfo` (già in `PlaybackApi`).
- **JSON** PascalCase.
  - `ReportDto`: `Id`, `Type`, `Note?`, `CreatedAt`, `UpdatedAt`, `UserId`, `UserName`, `ItemId`, `ItemType` (`Movie`/`Series`/`Season`/`Episode`, vuoto se il titolo non c'è più), `ItemName`, `TitleId`, `TitleName`, `SeasonNumber?`, `EpisodeNumber?`.
  - `RemoteSubtitleDto`: `Id`, `ProviderName`, `Name`, `Language`, `Format`, `CommunityRating?`, `DownloadCount?`, `IsHashMatch`, `HearingImpaired`, `Forced`, `MachineTranslated`.
  - Voci della cassetta (spec §6.3): `ReportId`, `ReportType`, `FromName` (pending), `Outcome` (resolved: `Fixed`/`CannotFix`), `Text`, `ItemId`, `ItemType?`, `SeasonNumber?`, `EpisodeNumber?`, `Title`, `ImageItemId?` (= `TitleId`).
  - Gli id sono in formato "N": si confrontano con `jellyfinIdKey`.
- **Funzione del plugin:** `"reports"`.
- **Permesso sottotitoli:** `Policy.EnableSubtitleManagement`; gli strumenti si vedono con `(isAdmin || enableSubtitleManagement) && features.reports`.
- **Valori:**
  - nota della segnalazione e di chiusura: al massimo **500 punti di codice** (`capRunes(500)`), contatore visibile da 450;
  - file di sottotitoli: al massimo **2 097 152 byte**, estensioni `srt ass ssa vtt sub`;
  - attesa della traccia: ogni **2 s** per al massimo **20 s** (`subtitlePollInterval`, `subtitlePollTimeout`).
- **Testi** it/en: le chiavi e i testi italiani sono nel Task 1. Nessun testo fisso nel codice.
- **Stile:**
  - icone solo `LucideIcons`, colori `WfColors`, `clock.now()` (mai `DateTime.now()`), durate con `WfMotion`, animazioni ridotte rispettate;
  - note, nomi e titoli mostrati sempre come testo semplice;
  - **nei log mai note, nomi, titoli, nomi di file o contenuto dei sottotitoli**: solo id, numeri e il nome del fallimento.
- **Flutter** è in `C:\Users\sidot\dev\flutter`. I test si lanciano con `flutter test`.
- **Build per la prova a mano**, esattamente:
  `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
  `config/wonderflix.json` è ignorato da git: va copiato nel worktree dal checkout principale prima della build e non si committa.
- **Commit:** con l'identità git del repository (hash_developer). **Mai** il trailer `Co-Authored-By` né righe "Generated with…"; mai `closes`, `fixes`, `resolves` (né simili) nei messaggi. Niente push.
- **Processi:** **mai** terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.

## Review Focus

1. **Permesso tolto mentre l'app è aperta:** un 403 dal plugin o da Jellyfin mostra "Non hai il permesso per farlo" e chiama `refreshUser()`, così le voci spariscono. Test: Task 5 (`un 403 nella ricerca rilegge l'utente`).
2. **Due admin sulla stessa segnalazione:** il secondo "Sistemato" riceve 409 `Closed`, vede "Questa segnalazione è già stata chiusa" e il riquadro si ricarica senza quella voce. Test: Task 7 (`chiusa da un altro admin: messaggio e ricarica`).
3. **Download riuscito ma traccia che non arriva entro 20 s:** niente rotella infinita; resta "Scaricato: la traccia comparirà tra poco" e la finestra si può chiudere. Test: Task 5 (`la traccia non compare entro 20 s`).
4. **Finestra chiusa durante l'attesa della traccia:** nessun errore e nessuna chiamata dopo la chiusura, perché il controller `autoDispose` ferma il timer. Test: Task 5 (`chiudere durante l'attesa ferma le riletture`).
5. **Sottotitolo nuovo durante una transcodifica che lo incide:** il video non riparte; compare il messaggio "dalla prossima riproduzione". Test: Task 6 (`traccia non esterna: messaggio e niente ripartenza`).

---

## Regole per chi esegue

- **Worktree** `.claude/worktrees/piano-24b` (branch `piano-24b` da `main`). Tutti i comandi partono dalla sua root: fai prima `Set-Location` lì e non toccare mai il checkout principale.
- **Shell:** PowerShell. In ogni comando con `flutter`, `dart` o `git`, prima rinfresca il PATH:
  `$env:Path = 'C:\Users\sidot\dev\flutter\bin;' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
- **Commit:** vedi le Global Constraints. Su una riga sola, `git commit -m "feat(app): …"`. Comandi git semplici: niente `git -C`, e mai `git checkout -- <file>` su un file che hai modificato.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera tutta verde con **`flutter test --concurrency=4`** (con i 16 processi predefiniti il PC si è riavviato);
  - prima del Task 1 misura la base (numero di test verdi su `main`) e scrivila nel primo resoconto.
- **File generati:**
  - dopo ogni modifica agli ARB `flutter gen-l10n` (`lib/l10n/gen/` non si committa; in un worktree nuovo va generato prima di tutto);
  - se `windows/flutter/generated_plugin*` cambia solo nei fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** niente `dart format` su file interi, solo modifiche mirate. Ogni file tiene i suoi fine riga. Scrivi in UTF-8 con gli strumenti di modifica dei file, mai con `Set-Content` o `Out-File`.
- **Codice:** commenti in italiano, codice in inglese; durate, misure e limiti come costanti nominate e commentate.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container hanno `retry: (_, _) => null`;
  - in un provider tutti i `ref.watch` stanno prima del primo `await`;
  - cattura `final ref = this.ref` prima delle attese e controlla `ref.mounted` dopo.
- **Se il codice del piano ha un errore** (analyzer, firma diversa, `switch` esaustivo da completare in un file non elencato, icona Lucide con un altro nome): correggilo in modo minimo e segnalalo. Meglio correggere il codice che indebolire un test.

## Note tecniche verificate

Sul codice di `main` `839179a` (2026-10-21):
- **HTTP:**
  - `JellyfinHttp` (`lib/core/jellyfin/jellyfin_http.dart`): `get(path, {query, cancelToken, quietStatuses})`, `post(path, {body, query, contentType, quietStatuses})`, `put(path, {body, quietStatuses})`, `delete(path, {query, quietStatuses})`. Il corpo `Map` va in JSON; `asJsonMap`, `parseJson`, `restartGatewayStatuses`.
  - Errori in `lib/core/jellyfin/api_exception.dart` (`sealed ApiException`): `UnauthorizedException`, `ForbiddenException([body])`, `NotFoundException`, `ServerUnreachableException`, `ServerErrorException(statusCode, [body])` (409 e 502 arrivano qui con `body` già decodificato).
  - Modello di API con il motivo del 409: `lib/core/social/match_api.dart` (`MatchFailure`, `MatchException`, `_call`, `_reason(body)`), provider in `lib/features/match/match_providers.dart`. Test: `FakeAdapter`/`FakeResponse(status, [body])` (`test/support/fake_adapter.dart`), `testServerUrl`, `testClientInfo` (`test/support/test_data.dart`), come `test/core/social/rating_api_test.dart`.
- **Funzioni:** `PluginFeatures` (`lib/core/social/social_models.dart:13`, `ratings` alla riga 51). `SocialFeatures` (`lib/features/social/social_providers.dart:19–140`) va toccata in costruttore, campo, `==`, `hashCode`, `toString` e nel blocco di `refresh` (righe 230–247), più `describePluginFeatures` (`lib/features/settings/diagnostics.dart:53`). `features.known` è falso finché `Info` non risponde. Nei test `FakeSocialAvailability`, `socialTestOverrides(api, features:)` (`test/support/social_fakes.dart`).
- **Utente:**
  - `JellyfinUser` (`lib/core/jellyfin/auth_models.dart:29–69`) con `_isAdministrator(policy)` alla riga 26; `==` e `hashCode` vanno aggiornati;
  - `isAdminProvider` (`lib/features/admin/admin_providers.dart:17`);
  - `sessionControllerProvider` → `SessionSignedIn(user)`; `refreshUser()` (`session_controller.dart:271`).
  - Nei test `testUser`, `testAdmin`, `FakeSessionController`.
- **Cassetta:**
  - `sealed class InboxEntry` e `inboxEntryFromJson` (`lib/core/social/inbox_models.dart:274`, tipi sconosciuti → `null`); modello `RecommendationEntry` (riga 234);
  - `inbox_panel.dart`: switch dell'icona (righe 319–333) e del contenuto (righe 336–380), `_ItemPoster(itemId:)`, `_RecommendationContent` (chiude il pannello con `shellPanelProvider.notifier.close()` e poi `openItemById`), `InboxRequestIcon(icon:, size: InboxPanel.leadingSize)`;
  - `InboxController` ricarica su `InboxChangedEvent` (`inbox_controller.dart`).
- **Navigazione:** `openItemById(context, id)` (`lib/app/navigation.dart:58`); la scheda accetta `?season=<seasonId>` (`item_detail_screen.dart:104`, `initialSeasonId`).
- **Dettaglio:**
  - `DetailHeader({item, primary, controller})`: `Wrap` dei bottoni alle righe 125–209, Preferito alla 174, Visto alla 183;
  - `JellyfinItem` (`lib/core/jellyfin/item_models.dart:207`): `id`, `name`, `kind` (`ItemKind.movie|series|season|episode|…`), `seriesId`, `seriesName`, `seasonId`, `indexNumber`, `parentIndexNumber`. Non ha `MediaSources`;
  - `MovieDetailView` (righe 45–64) e `SeriesDetailView` (`ListView` alla riga 81): `_SeasonTabs(seasons, selectedId, onSelect)` alla 168, `_EpisodeList` alla 227, `EpisodeTile({episode, highlighted})` pubblico alla 291;
  - `detailEntranceCount = 9` (`detail_header.dart:38`, controllato da `detail_entrance_test.dart`);
  - provider: `itemProvider`, `seasonsProvider`, `episodesProvider` (`detail_providers.dart`), tutti legati a `libraryRevisionProvider`;
  - `LibraryApi.item(userId, itemId)` (`library_api.dart:91`). Nei test `FakeLibraryApi`, `testItem(...)` (`test/support/library_fakes.dart`).
- **Menu e finestre:**
  - menu Material: `PopupMenuButton(popUpAnimationStyle: wfPopUpAnimation(context), …)` con `PopupMenuDivider` (`users_tab.dart:273`, `party_badge.dart:251`);
  - `showWfDialog(context, builder:, maxWidth:, semanticLabel:)`, `showWfConfirmDialog(context, title:, message:, confirmLabel:, cancelLabel:)`, `showAdminConfirmDialog`;
  - bottoni `WfButton.primary/secondary(label:, icon:, onPressed:)`, `WfIconToggle`;
  - snackbar con `ScaffoldMessenger.of(context).showSnackBar(...)`, testo d'errore con `describeError(l, error)` (`lib/app/error_text.dart`);
  - `capRunes(int max)` (`lib/ui/rune_limit.dart`).
- **Admin:**
  - `WonderflixTab` (`wonderflix_tab.dart:46–58`, `ListView` di card);
  - `AdminCard(title:, icon:, child:)`, `AdminCardError`, `AdminEmptyText`, `AdminActionButton`, `adminTimeLabel(at, now, l)`;
  - card modello: `rating_comments_card.dart` (`AsyncNotifierProvider.autoDispose`, `features.known` → `SkeletonBox`). Nei test `adminTestOverrides(...)`.
- **Player:**
  - `TracksPanel(...)` (`tracks_panel.dart`; sezione sottotitoli alle righe 103–114), costruito in `player_screen.dart:1992`;
  - `PlayerController` (`player_controller.dart`): `PlayerArgs = ({itemId, start, party})`, `PlayerViewState.plan` (`PlaybackPlan?`), `selectSubtitle`, `_start(...)` rilegge `PlaybackInfo` e riparte, `_showSubtitle` carica le esterne con `_engine.addSubtitle(_service.subtitleUrl(stream), …)` e le tiene in `_externalSubtitles`;
  - `PlaybackPlan` (`playback_service.dart:8`): `itemId`, `method`, `mediaSource`, `playSessionId`, `source`, `audioIndex`, `subtitleIndex`, `isTranscode`, `burnsIn`. `PlaybackService.prepare(...)`;
  - `MediaStreamInfo.fromJson` e `MediaSourceInfo.fromJson` (`playback_models.dart:38`, `:98`), `deliveredExternally`;
  - `PlaybackApi.playbackInfo(itemId, {userId, start, maxBitrate, allowDirect, mediaSourceId, audioStreamIndex, subtitleStreamIndex})`.
- **Lingue:** `playbackLanguages` (`lib/core/jellyfin/user_config_api.dart`, codici a tre lettere); `languagePreferencesProvider` → `LanguagePreferences.subtitleLanguage` (`lib/features/settings/language_preferences.dart:54`).
- **File:** `avatarFilePickerProvider` (`lib/features/profiles/avatar_dialog.dart:73–82`, `openFile` + `XTypeGroup`, `PickedAvatarFile{length, read}`) è il modello da copiare.
- **Testi:**
  - `l10n/app_it.arb` (modello, con i blocchi `@chiave`) e `l10n/app_en.arb`; `AppLocalizations.of(context)`;
  - plurali come `ratingFriendsCount`;
  - test dei testi come `test/app/l10n_plan23b_test.dart` (`lookupAppLocalizations`).
- **Release:** `docs/RELEASING.md`.

**Jellyfin 10.11.9:**
- `MediaSources` di `GET /Items/{id}`: ogni versione ha `Id`, `Name`, `Container`, `Size`, `RunTimeTicks`, `Bitrate`, `Path`, `MediaStreams`.
- Ogni stream ha `Index`, `Type` (`Video`/`Audio`/`Subtitle`), `Codec`, `Language`, `DisplayTitle`, `Title`, `Width`, `Height`, `RealFrameRate`, `VideoRange` (`SDR`/`HDR`), `VideoRangeType`, `Channels`, `IsDefault`, `IsForced`, `IsExternal`, `IsHearingImpaired`.
- Le tracce esterne nuove compaiono dopo il refresh che il plugin mette in coda: per questo l'app aspetta (decisione 7).

## File

| File | Responsabilità |
|---|---|
| `lib/core/reports/report_models.dart`, `reports_api.dart` | tipi, esiti, `ItemReport`, chiamate e `ReportsException` |
| `lib/core/subtitles/subtitle_models.dart`, `subtitles_api.dart` | `RemoteSubtitle`, ordine, chiamate e `SubtitlesException` |
| `lib/core/jellyfin/media_info_models.dart` (+ `library_api.dart`) | `ItemMediaInfo`: versioni, video, audio, sottotitoli |
| `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `lib/core/jellyfin/auth_models.dart` (modifiche) | funzione `reports`, permesso sottotitoli |
| `lib/features/reports/reports_providers.dart` | `reportsApiProvider`, `itemMediaInfoProvider`, `canManageSubtitlesProvider` |
| `lib/features/reports/report_labels.dart` | livello, tipo e riga del titolo nella lingua dell'app |
| `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart` (modifiche) | voci della cassetta |
| `lib/features/detail/item_actions_menu.dart`, `media_info_dialog.dart` (+ `detail_header.dart`, `series_detail_view.dart`) | menu "⋯" e info tecniche |
| `lib/features/reports/report_dialog.dart` | "Segnala un problema" |
| `lib/features/subtitles/subtitles_controller.dart`, `subtitles_dialog.dart`, `subtitle_file_picker.dart` | finestra dei sottotitoli |
| `lib/features/player/tracks_panel.dart`, `player_screen.dart`, `player_controller.dart`, `playback_service.dart` (modifiche) | "Cerca sottotitoli" e traccia nuova |
| `lib/features/reports/admin_reports_controller.dart`, `reports_banner.dart`, `resolve_report_dialog.dart`, `lib/features/admin/reports_card.dart` (+ `wonderflix_tab.dart`, `*_detail_view.dart`) | riquadro, chiusura, card |
| `l10n/app_it.arb`, `l10n/app_en.arb` | testi |
| `test/support/report_fakes.dart` | `FakeReportsApi`, `FakeSubtitlesApi`, dati di prova |

---

## Gruppo A — nucleo

### Task 1: modelli, chiamate, funzione, permesso e testi

**Files:**
- Create: `lib/core/reports/report_models.dart`, `lib/core/reports/reports_api.dart`, `lib/core/subtitles/subtitle_models.dart`, `lib/core/subtitles/subtitles_api.dart`, `lib/core/jellyfin/media_info_models.dart`, `lib/features/reports/reports_providers.dart`, `test/support/report_fakes.dart`
- Modify: `lib/core/jellyfin/library_api.dart`, `lib/core/jellyfin/auth_models.dart`, `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`, `test/support/library_fakes.dart` (`mediaInfo`)
- Test: `test/core/reports/reports_api_test.dart`, `test/core/subtitles/subtitles_api_test.dart`, `test/core/jellyfin/media_info_models_test.dart`, `test/core/jellyfin/auth_models_test.dart` (un test), `test/features/social/social_providers_test.dart` (un test), `test/features/reports/reports_providers_test.dart`, `test/app/l10n_plan24b_test.dart`

**Interfaces:**
- Produces:
  - **`report_models.dart`:**
    - `enum ReportType { subtitles('Subtitles'), metadata('Metadata'), audioVideo('AudioVideo'), other('Other') }`, con `wire` e `static ReportType? fromWire(Object?)`;
    - `enum ReportOutcome { fixed('Fixed'), cannotFix('CannotFix') }`, con `fromWire`;
    - `enum ReportItemType { movie('Movie'), series('Series'), season('Season'), episode('Episode') }`, con `fromWire` (vuoto o sconosciuto → `null`);
    - `class ItemReport { String id; ReportType type; String? note; DateTime createdAt, updatedAt; String userId, userName, itemId; ReportItemType? itemType; String itemName, titleId, titleName; int? seasonNumber, episodeNumber; }`, con `static ItemReport? fromJson(Map)` (`null` se `Type` è sconosciuto) e `static List<ItemReport> listFromJson(Object?)` (legge `Items` e salta le voci non valide).
  - **`reports_api.dart`:**
    - `enum ReportsFailure { unavailable, invalid, forbidden, limitReached, closed, network }`;
    - `class ReportsException implements Exception { const ReportsException(this.failure); final ReportsFailure failure; }`;
    - `class ReportsApi(JellyfinHttp)`:
      - `Future<ItemReport> create({required String itemId, required ReportType type, String? note})`;
      - `Future<List<ItemReport>> mine(String itemId)`;
      - `Future<List<ItemReport>> all()`;
      - `Future<void> resolve(String reportId, ReportOutcome outcome, {String? note})`.
      Mappa: 404 → `unavailable`, 400 → `invalid`, 401/403 → `forbidden`, 409 con `Reason` `LimitReached` → `limitReached` e `Closed` → `closed` (altro 409 → `invalid`), tutto il resto → `network`. `quietStatuses = {400, 403, 404, 409}`. Una nota vuota non si manda.
  - **`subtitle_models.dart`:**
    - `class RemoteSubtitle { String id, providerName, name, language, format; double? communityRating; int? downloadCount; bool isHashMatch, hearingImpaired, forced, machineTranslated; }`, con `fromJson`;
    - `List<RemoteSubtitle> sortSubtitles(Iterable<RemoteSubtitle>)`: prima `isHashMatch`, poi `downloadCount` decrescente (null in fondo), a parità per nome;
    - `class SubtitleUpload { String language, format; bool isForced, isHearingImpaired; Uint8List bytes; }`.
  - **`subtitles_api.dart`:**
    - `enum SubtitlesFailure { unavailable, forbidden, invalid, failed, network }`;
    - `class SubtitlesException implements Exception { const SubtitlesException(this.failure); final SubtitlesFailure failure; }`;
    - `class SubtitlesApi(JellyfinHttp)`:
      - `Future<List<RemoteSubtitle>> search(String itemId, String language, {bool? perfectMatch})`;
      - `Future<void> download(String itemId, String subtitleId)`;
      - `Future<void> upload(String itemId, SubtitleUpload upload)`: `Data` = `base64Encode(bytes)`;
      - `Future<void> delete(String itemId, int streamIndex)`: Jellyfin, `DELETE /Videos/{itemId}/Subtitles/{index}`.
      Mappa: 404 → `unavailable`, 400 → `invalid`, 401/403 → `forbidden`, 502 → `failed`, il resto → `network`. `quietStatuses = {400, 403, 404, 502}`.
  - **`media_info_models.dart`:**
    - `class ItemMediaInfo { List<MediaVersion> versions; }`, con `factory ItemMediaInfo.fromItemJson(Map)`, che legge `MediaSources`;
    - `class MediaVersion { String id; String? name, container, fileName; int? size, bitrate; Duration? duration; VideoTrack? video; List<AudioTrack> audio; List<SubtitleTrack> subtitles; }`. `fileName` è **solo il nome** dell'ultimo componente di `Path`, con `/` o `\`, mai il percorso;
    - `class VideoTrack { String? codec, range; int? width, height; double? fps; }`;
    - `class AudioTrack { int index; String? language, codec, title; int? channels; bool isDefault; }`;
    - `class SubtitleTrack { int index; String? language, codec, title; bool isExternal, isForced, isHearingImpaired; }`;
    - `Set<int> externalSubtitleIndexes(ItemMediaInfo)`: gli indici delle tracce esterne di tutte le versioni.
  - **`LibraryApi`:** `Future<ItemMediaInfo> mediaInfo(String userId, String itemId)` → `GET /Items/{id}` con `query: {'userId': userId, 'fields': 'MediaSources'}`. Nel finto: `Map<String, ItemMediaInfo> mediaInfoById` e `List<String> mediaInfoCalls`.
  - **`JellyfinUser.enableSubtitleManagement`** (`bool`, da `Policy.EnableSubtitleManagement`, predefinito `false`), in costruttore, `fromJson`, `==`, `hashCode`.
  - **`PluginFeatures.reports = 'reports'`**; **`SocialFeatures.reports`**, che vale `info.features.contains(PluginFeatures.reports)` **senza** `_canJoin` (decisione 3); `describePluginFeatures` la elenca.
  - **`reports_providers.dart`:**
    - `final reportsApiProvider = Provider<ReportsApi>(…jellyfinHttpProvider…)`;
    - `final subtitlesApiProvider = Provider<SubtitlesApi>(…)`;
    - `final itemMediaInfoProvider = FutureProvider.autoDispose.family<ItemMediaInfo, String>((ref, itemId) …)`, con l'utente da `currentUserIdProvider`;
    - `final canManageSubtitlesProvider = Provider<bool>`: vero con una sessione, `features.reports` e `user.isAdministrator || user.enableSubtitleManagement`.
  - **`test/support/report_fakes.dart`:**
    - `class FakeReportsApi implements ReportsApi` (`reports`, `mine`, `calls`, `nextFailure` una volta sola, `gate` `Completer?`);
    - `class FakeSubtitlesApi implements SubtitlesApi` (`results`, `calls`, `nextFailure`, `gate`);
    - `ItemReport testReport({…})`, `RemoteSubtitle testSubtitle({…})`, `ItemMediaInfo testMediaInfo({List<SubtitleTrack> subtitles = const []})`;
    - `List<Override> reportTestOverrides({FakeReportsApi?, FakeSubtitlesApi?})`.

**Testi** (italiano; chiavi esatte; l'inglese lo scrive chi esegue):

| Chiave | Italiano |
|---|---|
| `itemActionsMenu` | Altre azioni |
| `itemActionReport` | Segnala un problema |
| `itemActionMediaInfo` | Info tecniche |
| `itemActionSubtitles` | Sottotitoli… |
| `reportDialogTitle` | Segnala un problema |
| `reportLevelThisEpisode` | Questo episodio |
| `reportLevelThisSeason` | Questa stagione |
| `reportLevelWholeSeries` | Tutta la serie |
| `reportLevelSeries` | Tutta la serie |
| `reportLevelSeason` (`{number}` int) | Stagione {number} |
| `reportLevelSpecials` | Speciali |
| `reportLevelEpisode` (`{season}`, `{episode}` int) | S{season} E{episode} |
| `reportTypeSubtitles` | Sottotitoli |
| `reportTypeMetadata` | Titolo o informazioni |
| `reportTypeAudioVideo` | Audio o video |
| `reportTypeOther` | Altro |
| `reportNoteHint` | Aggiungi dettagli (facoltativo) |
| `reportAlreadySent` | Hai già segnalato questo problema: puoi aggiornare la nota |
| `reportSend` | Invia segnalazione |
| `reportSent` | Segnalazione inviata agli admin |
| `reportLimitReached` | Hai già 20 segnalazioni aperte: aspetta che gli admin ne chiudano qualcuna |
| `reportNoPermission` | Non hai il permesso per farlo |
| `inboxReportPending` (`{name}`) | {name} ha segnalato un problema |
| `inboxReportFixed` (`{title}`) | Problema sistemato su {title} |
| `inboxReportCannotFix` (`{title}`) | Non è stato possibile sistemare {title} |
| `inboxReportUnknownTitle` | un titolo |
| `reportsBannerTitle` (`{count}` int, plurale) | =1: Segnalazione aperta · 1 / other: Segnalazioni aperte · {count} |
| `reportFixed` | Sistemato |
| `reportCannotFix` | Non sistemabile |
| `reportNoNote` | Nessuna nota |
| `reportResolveFixedTitle` | Segna come sistemato |
| `reportResolveCannotFixTitle` | Segna come non sistemabile |
| `reportResolveNoteHint` | Nota per chi ha segnalato (facoltativa) |
| `reportResolveConfirm` | Conferma |
| `reportAlreadyClosed` | Questa segnalazione è già stata chiusa |
| `reportShortcutSubtitles` | Cerca sottotitoli |
| `adminReportsTitle` | Segnalazioni |
| `adminReportsEmpty` | Nessuna segnalazione aperta |
| `adminReportsNeedPlugin` | Serve il plugin 1.12.0 |
| `adminReportsOpen` | Apri |
| `subtitlesDialogTitle` | Sottotitoli |
| `subtitlesLanguage` | Lingua |
| `subtitlesSearch` | Cerca |
| `subtitlesUpload` | Carica file… |
| `subtitlesNoResults` | Nessun sottotitolo trovato |
| `subtitlesDownload` | Scarica |
| `subtitlesHashMatch` | Sincronizzato col file |
| `subtitlesHearingImpaired` | Per non udenti |
| `subtitlesForced` | Forzati |
| `subtitlesMachineTranslated` | Tradotto automaticamente |
| `subtitlesDownloads` (`{count}` int, plurale) | =1: 1 download / other: {count} download |
| `subtitlesDownloadFailed` | Download non riuscito |
| `subtitlesUploadFailed` | Caricamento non riuscito |
| `subtitlesFileTooLarge` | Il file supera 2 MB |
| `subtitlesWaiting` | Aspetto che Jellyfin aggiunga la traccia… |
| `subtitlesTrackAdded` | Sottotitolo aggiunto |
| `subtitlesTrackSoon` | Scaricato: la traccia comparirà tra poco |
| `subtitlesExisting` | Tracce presenti |
| `subtitlesNone` | Nessuna traccia |
| `subtitlesExternal` | esterno |
| `subtitlesEmbedded` | nel file |
| `subtitlesDelete` | Elimina |
| `subtitlesDeleteTitle` | Eliminare il sottotitolo? |
| `subtitlesDeleteMessage` | Il file del sottotitolo verrà cancellato dal server. |
| `subtitlesFileTypes` | Sottotitoli |
| `subtitlesNextPlayback` | Il sottotitolo sarà disponibile dalla prossima riproduzione |
| `playerSearchSubtitles` | Cerca sottotitoli |
| `mediaInfoTitle` | Info tecniche |
| `mediaInfoVersion` (`{name}`) | Versione: {name} |
| `mediaInfoContainer` | Contenitore |
| `mediaInfoSize` | Dimensione |
| `mediaInfoDuration` | Durata |
| `mediaInfoBitrate` | Bitrate |
| `mediaInfoFile` | File |
| `mediaInfoVideo` | Video |
| `mediaInfoAudio` | Audio |
| `mediaInfoSubtitles` | Sottotitoli |
| `mediaInfoChannels` (`{count}` int) | {count} canali |
| `mediaInfoDefault` | predefinita |
| `mediaInfoUnavailable` | Informazioni non disponibili |

- [ ] **Step 1: test che falliscono**

`test/core/reports/reports_api_test.dart` (con `FakeAdapter`, come `rating_api_test.dart`):

```dart
test('create manda ItemId, Type e la nota, e legge il ReportDto', () async {
  adapter.handler = (_) => FakeResponse(200, reportJson(id: 'r1'));
  final report = await api.create(itemId: 'e1', type: ReportType.subtitles, note: 'Mancano');
  final request = adapter.requests.single;
  expect((request.method, request.path), ('POST', '/WonderFlixWatchParty/Reports'));
  expect(request.data, {'ItemId': 'e1', 'Type': 'Subtitles', 'Note': 'Mancano'});
  expect(report.id, 'r1');
});

test('i 409 diventano limitReached e closed', () async {
  adapter.handler = (_) => FakeResponse(409, {'Reason': 'LimitReached'});
  await expectLater(api.create(itemId: 'e1', type: ReportType.other),
      throwsA(isA<ReportsException>().having((e) => e.failure, 'failure', ReportsFailure.limitReached)));
  adapter.handler = (_) => FakeResponse(409, {'Reason': 'Closed'});
  await expectLater(api.resolve('r1', ReportOutcome.fixed),
      throwsA(isA<ReportsException>().having((e) => e.failure, 'failure', ReportsFailure.closed)));
});
```

E inoltre:
- `404 è un plugin vecchio, 403 è il permesso, 400 non valido`.
- `mine e all leggono Items e saltano un tipo sconosciuto`.
- `resolve manda Outcome e Note, senza Note se vuota`.

`test/core/subtitles/subtitles_api_test.dart`:
- `search chiama la rotta con lingua e perfectMatch e legge i risultati`.
- `upload manda Data in base64`.
- `delete chiama Jellyfin` (`DELETE /Videos/e1/Subtitles/3`).
- `502 è failed`.
- `sortSubtitles mette prima i sincronizzati poi per download`, con un test puro.

`test/core/jellyfin/media_info_models_test.dart`:
- `versioni, video, audio e sottotitoli dal JSON di Jellyfin`.
- `fileName è solo il nome, con / e con \`.
- `externalSubtitleIndexes`.
- `senza MediaSources: nessuna versione`.

Gli altri:
- `auth_models_test`: `EnableSubtitleManagement nella Policy`.
- `social_providers_test`: `reports vale anche senza accesso ai watch party`.
- `reports_providers_test`: `canManageSubtitles: admin sì, spunta sì, nessuno dei due no, senza reports no`.
- `l10n_plan24b_test`: tutte le chiavi della tabella in it ed en, non vuote; il plurale di `reportsBannerTitle` e `subtitlesDownloads` per 1 e 3.

- [ ] **Step 2: i test falliscono** (`flutter test test/core/reports test/core/subtitles test/core/jellyfin/media_info_models_test.dart test/features/reports test/app/l10n_plan24b_test.dart`).

- [ ] **Step 3: il codice** con le firme sopra. Le API copiano la forma di `MatchApi._call`. I testi vanno negli ARB, i blocchi `@chiave` con i segnaposto solo in `app_it.arb`, poi `flutter gen-l10n`.

- [ ] **Step 4: i test passano** (stesso comando, poi `flutter analyze` e la suite intera).

- [ ] **Step 5: commit**

```powershell
git add -A lib l10n test
git commit -m "feat(app): reports and subtitles core"
```

### Task 2: voci della cassetta e testi del livello

**Files:**
- Create: `lib/features/reports/report_labels.dart`
- Modify: `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart`
- Test: `test/core/social/inbox_models_test.dart` (test nuovi), `test/features/inbox/inbox_reports_test.dart`, `test/features/reports/report_labels_test.dart`

**Interfaces:**
- Consumes: `ReportType`, `ReportOutcome`, `ReportItemType` (Task 1).
- Produces:
  - **`report_labels.dart`:**
    - `String reportLevelLabel(AppLocalizations l, ReportItemType? type, {int? season, int? episode})`:
      - `series` → `reportLevelSeries`;
      - `season` → `reportLevelSpecials` per 0, altrimenti `reportLevelSeason(n)`, vuoto senza numero;
      - `episode` → `reportLevelEpisode(s, e)`, vuoto se manca uno dei due;
      - `movie` e `null` → `''`;
    - `String reportTypeLabel(AppLocalizations l, ReportType? type)` (null → `reportTypeOther`);
    - `String reportTitleLine(AppLocalizations l, {required String title, ReportItemType? itemType, int? season, int? episode, ReportType? type})`: le parti non vuote unite da `' · '`.
  - **`inbox_models.dart`:**
    - `final class ReportPendingEntry extends InboxEntry { String reportId; ReportType? reportType; String fromName; String itemId; ReportItemType? itemType; String? titleId; String title; int? seasonNumber, episodeNumber; String? text; }`;
    - `final class ReportResolvedEntry extends InboxEntry { String reportId; ReportType? reportType; ReportOutcome outcome; String itemId; ReportItemType? itemType; String? titleId; String title; int? seasonNumber, episodeNumber; String? text; }`;
    - in `inboxEntryFromJson`, `'ReportPending'` e `'ReportResolved'`: `titleId` da `ImageItemId`. Senza `ReportId`, senza `ItemId`, o (resolved) con un `Outcome` sconosciuto → `null`.
  - **`inbox_panel.dart`:**
    - icona: `_ItemPoster(itemId: titleId)` se c'è; altrimenti `InboxRequestIcon` con `LucideIcons.flag` (pending), `LucideIcons.circleCheck` (fixed) o `LucideIcons.circleAlert` (cannotFix);
    - contenuto: un widget nuovo come `_RecommendationContent`, con la prima riga e una seconda riga in `WfColors.creamMuted`:
      - pending: `inboxReportPending(fromName)` / `reportTitleLine(title, livello, tipo)`;
      - resolved: `inboxReportFixed(title)` o `inboxReportCannotFix(title)`, con `inboxReportUnknownTitle` se il titolo è vuoto / la nota tra virgolette `“…”`, se c'è;
      - entrambe con l'ora come le altre voci;
    - tocco: chiude il pannello, poi:
      - con `titleId` e `itemType == season` → `context.push('/item/$titleId?season=$itemId')`;
      - con `titleId` → `openItemById(context, titleId)`;
      - senza `titleId` → nessuna navigazione, solo la chiusura (decisione 4).

- [ ] **Step 1: test che falliscono**
- `inbox_models_test`: `ReportPending con tutti i campi`; `ReportResolved Fixed con la nota`; `titolo sparito: niente ImageItemId e ItemType`; `senza ReportId o con Outcome sconosciuto si salta`.
- `report_labels_test`: `episodio S2 E3`; `stagione 0 è Speciali`; `serie intera`; `film senza livello`; `riga con titolo, livello e tipo`; `episodio senza numeri: solo titolo e tipo`.
- `inbox_reports_test` (widget, come `inbox_recommendation_test.dart`):
  - `la voce pending mostra chi, titolo, livello e tipo, e apre la serie`;
  - `la voce di una stagione apre la serie su quella stagione` (rotta `/item/s1?season=se2`);
  - `la voce resolved mostra l'esito e la nota tra virgolette`;
  - `titolo sparito: testo con "un titolo" e nessuna navigazione`.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.** Gli `switch` esaustivi sul tipo sigillato fuori da `inbox_panel.dart`, se ce ne sono, vanno completati.
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): report entries in the inbox"`

## Gruppo B — dettaglio per tutti

### Task 3: menu "⋯" e info tecniche

**Files:**
- Create: `lib/features/detail/item_actions_menu.dart`, `lib/features/detail/media_info_dialog.dart`
- Modify: `lib/features/detail/detail_header.dart`, `lib/features/detail/series_detail_view.dart`
- Test: `test/features/detail/item_actions_menu_test.dart`, `test/features/detail/media_info_dialog_test.dart`

**Interfaces:**
- Consumes: `canManageSubtitlesProvider`, `itemMediaInfoProvider`, `SocialFeatures.reports`, `isAdminProvider` (Task 1).
- Produces:
  - `enum ItemAction { report, mediaInfo, subtitles }` (il 24c aggiunge le sue).
  - `List<List<ItemAction>> itemActionGroups({required ItemKind kind, required bool reports, required bool canManageSubtitles, required bool isAdmin})`, funzione pura. Gruppi nell'ordine tutti / sottotitoli / admin, senza i gruppi vuoti:
    - `report` con `reports` e kind in {movie, series, season, episode};
    - `mediaInfo` per {movie, episode};
    - `subtitles` con `canManageSubtitles` e kind in {movie, episode};
    - gruppo admin vuoto in questo piano (decisione 11).
  - `class ItemActionsButton extends ConsumerWidget { const ItemActionsButton({super.key, required this.item}); final JellyfinItem item; }`:
    - icona `LucideIcons.ellipsis`, tooltip `itemActionsMenu`, la stessa misura di `WfIconToggle` (44);
    - `PopupMenuButton` con `wfPopUpAnimation` e `PopupMenuDivider` fra i gruppi;
    - `SizedBox.shrink()` senza voci;
    - azioni: `report` → `showReportDialog(context, item)` (Task 4; fino ad allora la voce c'è ma l'azione è vuota, e il Task 4 la collega); `mediaInfo` → `showMediaInfoDialog(context, item)`; `subtitles` → `showSubtitlesDialog(context, itemId: item.id, title: …)` (Task 5; lo stesso schema).
  - `Future<void> showMediaInfoDialog(BuildContext context, JellyfinItem item)` (`showWfDialog`, `maxWidth: 560`):
    - titolo `mediaInfoTitle` e sotto il nome;
    - una sezione per versione, con `mediaInfoVersion(name)` solo se le versioni sono più di una;
    - righe: contenitore, dimensione (in GB o MB con un decimale, `NumberFormat` della lingua), durata, bitrate (Mbps);
    - video: codec, `width×height`, range, fps;
    - una riga per audio: lingua, codec, `mediaInfoChannels`, `mediaInfoDefault`;
    - una riga per sottotitolo: lingua, codec, `subtitlesExternal`/`subtitlesEmbedded`, `subtitlesForced`;
    - `mediaInfoFile` con `fileName` **solo se `isAdminProvider`**;
    - errore o nessuna versione → `mediaInfoUnavailable`.
  - **Posti:**
    - in `DetailHeader`, dopo Visto (riga 183): `ItemActionsButton(item: item)`;
    - in `EpisodeTile`, in fondo alla riga prima del `WatchedBadge`;
    - in `SeriesDetailView`, a destra di `_SeasonTabs`, `ItemActionsButton(item: <la stagione selezionata dalla lista di seasonsProvider>)`.
    Il tocco sul bottone non deve far partire l'episodio: il bottone sta fuori dall'`InkWell` o ferma il tocco.

- [ ] **Step 1: test che falliscono**

```dart
test('voci per ruolo e livello (spec §7.2)', () {
  expect(itemActionGroups(kind: ItemKind.movie, reports: true, canManageSubtitles: true, isAdmin: false),
      [[ItemAction.report, ItemAction.mediaInfo], [ItemAction.subtitles]]);
  expect(itemActionGroups(kind: ItemKind.season, reports: true, canManageSubtitles: true, isAdmin: true),
      [[ItemAction.report]]);
  expect(itemActionGroups(kind: ItemKind.series, reports: false, canManageSubtitles: false, isAdmin: false), isEmpty);
  expect(itemActionGroups(kind: ItemKind.episode, reports: false, canManageSubtitles: false, isAdmin: false),
      [[ItemAction.mediaInfo]]);
});
```

E inoltre:
- `il bottone non c'è senza voci` (una serie senza `reports`);
- `il menu di un film mostra le voci e il separatore`;
- `il bottone su un episodio non fa partire la riproduzione`.
- `media_info_dialog_test`:
  - `due versioni, video, audio e sottotitoli`;
  - `il nome del file solo per l'admin`;
  - `errore: informazioni non disponibili`.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera; `detail_entrance_test` resta verde).
- [ ] **Step 5: commit** — `git commit -m "feat(app): item actions menu and media info"`

### Task 4: "Segnala un problema"

**Files:**
- Create: `lib/features/reports/report_dialog.dart`
- Modify: `lib/features/detail/item_actions_menu.dart` (collega `report`)
- Test: `test/features/reports/report_dialog_test.dart`

**Interfaces:**
- Consumes: `reportsApiProvider`, `ReportsException`, `report_labels.dart`, `capRunes`.
- Produces:
  - `Future<void> showReportDialog(BuildContext context, JellyfinItem item)`;
  - `List<ReportTarget> reportTargets(AppLocalizations l, JellyfinItem item)`, funzione pura, con `class ReportTarget { String itemId; String label; }`:
    - episodio → [`reportLevelThisEpisode` (id dell'episodio), `reportLevelSeason`/`reportLevelSpecials` (`seasonId`, numero `parentIndexNumber`), `reportLevelWholeSeries` (`seriesId`)], togliendo le voci senza id;
    - stagione → [`reportLevelThisSeason`, `reportLevelWholeSeries`];
    - film e serie → un solo bersaglio, e la riga dei livelli non si mostra.

**Finestra** (bozza 2, `showWfDialog`, `maxWidth: 480`):
- **titolo:** `reportDialogTitle`; sotto, la riga del contenuto:
  - episodio: `seriesName · S{s} E{e} “name”`;
  - stagione: `seriesName · <livello>`;
  - altrimenti `name`;
- **livelli:** chip `ChoiceChip` (solo con più bersagli); il primo è scelto;
- **tipo:** quattro chip, nessuno scelto all'inizio; **Invia** resta spento finché non se ne sceglie uno;
- **nota:** `TextField` multilinea, `capRunes(500)`, hint `reportNoteHint`, contatore `n/500` visibile da 450 punti di codice;
- **doppione:** a ogni cambio di bersaglio l'app chiama `mine(itemId)`. Se c'è una segnalazione con il tipo scelto, mostra `reportAlreadySent` e, **se la nota è vuota**, la precompila. Un errore di `mine` si ignora (nessun avviso);
- **Invia:** `create`, con una sola chiamata in volo (bottone spento durante l'invio). Se riesce: chiude la finestra e mostra lo snackbar `reportSent`. Gli errori restano nella finestra:
  - `limitReached` → `reportLimitReached`;
  - `forbidden` → `reportNoPermission` e `refreshUser()`;
  - il resto → `describeError`.

- [ ] **Step 1: test che falliscono**
- `bersagli da un episodio: episodio, stagione, serie`; `da una stagione: stagione e serie`; `stagione 0: Speciali`; `episodio senza seasonId: senza la voce della stagione`.
- `Invia spento finché non si sceglie il tipo`.
- `invia al bersaglio scelto con tipo e nota`: si sceglie "Tutta la serie" → `create(itemId: seriesId, …)`; poi la finestra si chiude e appare lo snackbar.
- `doppione: avviso e nota precompilata` (`mine` restituisce una segnalazione `Subtitles` con nota "vecchia").
- `limite raggiunto: messaggio nella finestra che resta aperta`.
- `doppio clic su Invia: una sola chiamata` (con il `gate` del finto).

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): report a problem dialog"`

## Gruppo C — sottotitoli

### Task 5: finestra dei sottotitoli

**Files:**
- Create: `lib/features/subtitles/subtitles_controller.dart`, `lib/features/subtitles/subtitles_dialog.dart`, `lib/features/subtitles/subtitle_file_picker.dart`
- Modify: `lib/features/detail/item_actions_menu.dart` (collega `subtitles`)
- Test: `test/features/subtitles/subtitles_controller_test.dart`, `test/features/subtitles/subtitles_dialog_test.dart`

**Interfaces:**
- Consumes: `subtitlesApiProvider`, `libraryApiProvider` (`mediaInfo`), `itemMediaInfoProvider`, `externalSubtitleIndexes`, `sortSubtitles`, `playbackLanguages`, `languagePreferencesProvider`, `isAdminProvider`.
- Produces:
  - **`subtitle_file_picker.dart`:**
    - `class PickedSubtitleFile { String name; int length; Future<Uint8List> Function() read; }`;
    - `typedef SubtitleFilePicker = Future<PickedSubtitleFile?> Function(String label)`;
    - `final subtitleFilePickerProvider = Provider<SubtitleFilePicker>(…)`, come `avatarFilePickerProvider`, con `subtitleFileExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub']` e `maxSubtitleFileBytes = 2097152`.
  - **`subtitles_controller.dart`:**
    - `const subtitlePollInterval = Duration(seconds: 2)`, `const subtitlePollTimeout = Duration(seconds: 20)`;
    - `enum SubtitlesNotice { none, downloadFailed, uploadFailed, fileTooLarge, noPermission, error, waiting, trackAdded, trackSoon }`;
    - `class SubtitlesState { String language; bool searching; List<RemoteSubtitle>? results; String? busyId; bool uploading; SubtitlesNotice notice; Object? error; }`, con `copyWith`;
    - `class SubtitlesController extends Notifier<SubtitlesState>`, con `final subtitlesControllerProvider = NotifierProvider.autoDispose.family<SubtitlesController, SubtitlesState, String>` (per id dell'item). Metodi:
      - `void setLanguage(String code)`;
      - `Future<void> search()`;
      - `Future<bool> download(RemoteSubtitle subtitle)`;
      - `Future<bool> upload(PickedSubtitleFile file, {required bool forced, required bool hearingImpaired})`;
      - `Future<void> delete(SubtitleTrack track)`.
      `download` e `upload` restituiscono vero quando la traccia nuova è comparsa.

**Regole:**
- **lingua iniziale:** decisione 12;
- **una sola operazione alla volta:** con `searching`, `busyId` o `uploading` le altre si ignorano;
- **download e upload:**
  - prima si fotografa `externalSubtitleIndexes(await libraryApi.mediaInfo(...))`;
  - poi la chiamata. Un fallimento → la notice giusta, e `forbidden` → `noPermission` + `refreshUser()`;
  - poi `waiting`. Ogni `subtitlePollInterval`, fino a `subtitlePollTimeout`, si rilegge `mediaInfo`: con un indice esterno nuovo → `trackAdded`, `ref.invalidate(itemMediaInfoProvider(itemId))` e risultato vero; alla scadenza → `trackSoon` e falso;
  - i timer si fermano in `ref.onDispose` (Review Focus 4);
- **upload:**
  - oltre `maxSubtitleFileBytes` → `fileTooLarge`, senza chiamare il plugin;
  - il formato è l'estensione del nome in minuscolo;
  - lingua dal menu;
- **delete:** solo per l'admin e su `isExternal`. La conferma la chiede la finestra; dopo, `ref.invalidate(itemMediaInfoProvider(itemId))`;
- **log:** solo l'id dell'item e il nome del fallimento.

**Finestra:**
- `Future<void> showSubtitlesDialog(BuildContext context, {required String itemId, required String title, VoidCallback? onTrackAdded})` (bozza 5, `showWfDialog`, `maxWidth: 640`);
- **in alto:** titolo `subtitlesDialogTitle`, sotto `title`. Una riga con il menu della lingua (`DropdownButton` sui `playbackLanguages`), **Cerca** e, a destra, **Carica file…**, con le caselle `subtitlesForced` e `subtitlesHearingImpaired` usate dal caricamento;
- **risultati:**
  - una riga per sottotitolo: nome (va a capo); sotto `provider · formato · ★ voto · subtitlesDownloads(n)`, con solo le parti presenti; le etichette `subtitlesHashMatch` (in `WfColors.online`), `subtitlesHearingImpaired`, `subtitlesForced`, `subtitlesMachineTranslated`; **Scarica** (`WfButton.primary` per i sincronizzati, `secondary` per gli altri);
  - durante il download la riga ha una rotella al posto del bottone;
  - con la lista vuota: `subtitlesNoResults`;
- **avviso:** una riga di stato sopra le tracce: `waiting` con la rotella, `trackAdded`, `trackSoon`, oppure i messaggi d'errore;
- **tracce presenti:** da `itemMediaInfoProvider(itemId)`, titolo `subtitlesExisting`:
  - una riga per traccia (lingua, codec, esterno / nel file);
  - **Elimina** solo per l'admin e solo sulle esterne, con `showWfConfirmDialog(subtitlesDeleteTitle, subtitlesDeleteMessage)`;
  - nessuna traccia: `subtitlesNone`;
- `onTrackAdded` si chiama quando `download` o `upload` restituiscono vero, se la finestra è ancora aperta.

- [ ] **Step 1: test che falliscono**

`subtitles_controller_test.dart` (con `fake_async`):
- `la lingua iniziale è quella preferita, altrimenti ita`.
- `search ordina i risultati`.
- `download: rilegge ogni 2 s e si ferma alla traccia nuova` (alla terza rilettura compare l'indice 5 esterno → vero, `trackAdded`, 3 chiamate a `mediaInfo` dopo la foto).
- `la traccia non compare entro 20 s` → falso, `trackSoon`, nessuna rilettura dopo i 20 s.
- `download fallito (502): downloadFailed e nessuna rilettura`.
- `un 403 nella ricerca rilegge l'utente`.
- `upload: file troppo grande senza chiamata; formato dall'estensione; Data della lunghezza giusta`.
- `una seconda operazione mentre la prima è in volo si ignora`.
- `chiudere durante l'attesa ferma le riletture` (dispose del container a metà: nessuna chiamata a `mediaInfo` dopo).

`subtitles_dialog_test.dart` (widget):
- `etichette e ordine dei risultati`.
- `Elimina solo per l'admin e solo sulle esterne` (tre casi: utente con la spunta, admin su una traccia esterna, admin su una nel file).
- `Elimina chiede conferma e chiama delete`.
- `lista vuota: nessun sottotitolo trovato`.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): subtitles dialog"`

### Task 6: sottotitoli dal player

**Files:**
- Modify: `lib/features/player/tracks_panel.dart`, `lib/features/player/player_screen.dart`, `lib/features/player/player_controller.dart`, `lib/features/player/playback_service.dart`
- Test: `test/features/player/tracks_panel_test.dart` (test nuovi), `test/features/player/player_subtitle_refresh_test.dart`

**Interfaces:**
- Consumes: `showSubtitlesDialog` (Task 5), `canManageSubtitlesProvider` (Task 1), `PlaybackApi.playbackInfo`.
- Produces:
  - `TracksPanel(..., VoidCallback? onSearchSubtitles)`: con il callback, sotto le tracce dei sottotitoli c'è un bottone `playerSearchSubtitles` (`LucideIcons.search`); senza, niente;
  - `PlaybackService.reloadSource(PlaybackPlan plan, {required String userId, required Duration position, required int maxBitrate}) → Future<MediaSourceInfo?>`: chiama `playbackInfo` con `mediaSourceId: plan.mediaSource.id`, `allowDirect: !plan.isTranscode` e le tracce del piano; restituisce la versione con lo stesso id, o null;
  - `enum SubtitleRefresh { added, nextPlayback, unchanged }`;
  - `PlayerController.refreshSubtitleStreams() → Future<SubtitleRefresh>`: decisione 8.
    - Con `added`, il piano nuovo ha la `MediaSourceInfo` di prima con le tracce nuove (stessi `id`, `transcodingUrl`, indici predefiniti; aggiungi `copyWith` o un costruttore con le tracce se manca), e `PlayerViewState.plan` si aggiorna, così il `TracksPanel` le mostra.
    - Non chiama `_start`, non cambia la traccia scelta, non ricrea la sorgente del video.
    - Una traccia esterna nuova si carica nell'engine solo quando l'utente la sceglie, con il percorso esistente di `selectSubtitle`.
    - Errori di rete → `unchanged`, con un log con il solo tipo dell'errore.
  - **In `player_screen.dart`:** con `canManageSubtitlesProvider`, `onSearchSubtitles` chiude il pannello tracce e apre `showSubtitlesDialog(context, itemId: widget.args.itemId, title: <nome del titolo in riproduzione>, onTrackAdded: …)`. `onTrackAdded` chiama `refreshSubtitleStreams()`; con `nextPlayback` mostra lo snackbar `subtitlesNextPlayback`. Mentre la finestra è aperta, i tasti del player non agiscono: la finestra è una rotta sopra il player. Controllalo con un test.

- [ ] **Step 1: test che falliscono**
- `tracks_panel_test`: `Cerca sottotitoli solo con il callback`.
- `player_subtitle_refresh_test`, con i finti di `playback_fakes.dart`:
  - `traccia esterna nuova: added e la lista la mostra senza ripartire`: nessuna nuova `prepare`, la sorgente dell'engine è la stessa, `subtitleIndex` è invariato;
  - `traccia non esterna: messaggio e niente ripartenza` → `nextPlayback`;
  - `indici di prima spostati → nextPlayback`;
  - `nessuna traccia nuova → unchanged`;
  - `errore di rete → unchanged`.
- Un test di widget: `dal pannello tracce si apre la finestra dei sottotitoli e i tasti del player non agiscono` (spazio con la finestra aperta: nessuna pausa).

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera).
- [ ] **Step 5: commit** — `git commit -m "feat(app): search subtitles from the player"`

## Gruppo D — admin

### Task 7: riquadro, chiusura e card

**Files:**
- Create: `lib/features/reports/admin_reports_controller.dart`, `lib/features/reports/reports_banner.dart`, `lib/features/reports/resolve_report_dialog.dart`, `lib/features/admin/reports_card.dart`
- Modify: `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/admin/wonderflix_tab.dart`
- Test: `test/features/reports/admin_reports_controller_test.dart`, `test/features/reports/reports_banner_test.dart`, `test/features/admin/reports_card_test.dart`

**Interfaces:**
- Consumes: `reportsApiProvider`, `ItemReport`, `report_labels.dart`, `showSubtitlesDialog` (Task 5), `socialEventsProvider` (`InboxChangedEvent`), `watchPartyEventsProvider` (`ServerConnected`), `isAdminProvider`, `SocialFeatures.reports`.
- Produces:
  - **`AdminReportsController extends AsyncNotifier<List<ItemReport>>`**, `final adminReportsProvider = AsyncNotifierProvider.autoDispose<…>`:
    - `build` guarda `isAdminProvider` e `features.reports`: senza uno dei due → `[]`, senza chiamate. Ascolta `InboxChangedEvent` e la riconnessione → `reload()`;
    - `Future<void> reload()`;
    - `Future<void> resolve(ItemReport report, ReportOutcome outcome, {String? note})`: chiama l'API, poi `reload()`. Con `closed` fa `reload()` e rilancia la `ReportsException`.
  - **`ReportShortcut? reportShortcut(ItemReport report)`**, con `enum ReportShortcut { subtitles }` (il 24c ne aggiunge): `subtitles` per `ReportType.subtitles` su `movie` o `episode`; altrimenti null (decisione 10).
  - **`ReportsBanner({required String titleId})`** (bozza 3):
    - le segnalazioni con `jellyfinIdKey(titleId)`; niente se è vuoto, se non si è admin o durante il caricamento;
    - bordo `WfColors.gold`, titolo `reportsBannerTitle(n)`;
    - una riga per segnalazione: `UserAvatar.lookup(userId:, name:)`, nome, tipo e livello (`reportTitleLine` senza il titolo), nota o `reportNoNote`;
    - bottoni `reportFixed` (`WfButton.primary`), `reportCannotFix`, e la scorciatoia `reportShortcutSubtitles` → `showSubtitlesDialog(itemId: report.itemId, title: <titolo e livello>)`.
  - **`Future<void> showResolveReportDialog(BuildContext context, WidgetRef ref, ItemReport report, ReportOutcome outcome)`:**
    - finestra con titolo `reportResolveFixedTitle`/`reportResolveCannotFixTitle`, nota facoltativa (`capRunes(500)`, `reportResolveNoteHint`) e **Conferma** (una sola chiamata in volo);
    - con `closed` chiude la finestra e mostra lo snackbar `reportAlreadyClosed`;
    - gli altri errori restano nella finestra.
  - **Posti:**
    - `MovieDetailView`: `ReportsBanner(titleId: item.id)` subito dopo `DetailHeader`, fuori dalle `StaggerItem` (decisione 9), solo per i film (non per un episodio aperto da solo);
    - `SeriesDetailView`: `ReportsBanner(titleId: series.id)` nello stesso posto.
  - **`ReportsCard`** in `wonderflix_tab.dart`, dopo `RatingCommentsCard`:
    - `features.known` falso → `SkeletonBox`; senza `reports` → `adminReportsNeedPlugin`;
    - altrimenti la lista, con `ConstrainedBox(maxHeight: 480)` come i commenti. Ogni riga ha `UserAvatar`, `reportTitleLine(title: titleName, …)`, sotto `userName · adminTimeLabel(createdAt)`, e **Apri** → `openItemById(context, titleId)`;
    - vuota → `adminReportsEmpty`; errore → `AdminCardError`.

- [ ] **Step 1: test che falliscono**
- `admin_reports_controller_test`:
  - `un non admin non chiama l'API`;
  - `InboxChanged ricarica`;
  - `resolve chiama e ricarica`;
  - `chiusa da un altro admin: messaggio e ricarica` (`closed` → ricarica e rilancia).
- `reports_banner_test`:
  - `solo le segnalazioni di quel titolo, con livello e nota`;
  - `niente per chi non è admin`;
  - `Sistemato con la nota chiama resolve(fixed, nota)`;
  - `chiusa da un altro admin: snackbar e riquadro senza quella voce`;
  - `scorciatoia solo per i sottotitoli di un film o di un episodio`.
- `reports_card_test`:
  - `elenco con titolo, livello, tipo, chi e quando`;
  - `vuota`;
  - `serve il plugin`;
  - `Apri porta al titolo`.

- [ ] **Step 2: i test falliscono.**
- [ ] **Step 3: il codice.**
- [ ] **Step 4: i test passano** (poi `flutter analyze` e la suite intera; `detail_entrance_test` resta verde).
- [ ] **Step 5: commit** — `git commit -m "feat(app): admin reports banner and card"`

## Gruppo E — chiusura

### Task 8: versione 0.18.0, spec e build

**Files:**
- Modify: `pubspec.yaml`, `docs/RELEASING.md`, `docs/superpowers/specs/2026-10-21-wonderflix-sistema-titoli-design.md`

- [ ] **Step 1:** `pubspec.yaml` → `version: 0.18.0`. In `docs/RELEASING.md`, nella lista delle prove a mano, una voce "Segnalazioni e sottotitoli (plugin 1.12.0)" con i passi 1, 2, 3 e 5 della spec §11.3.
- [ ] **Step 2: la spec**, controllando ogni frase sul codice:
  - **Stato:** "piano 24b realizzato (`docs/superpowers/plans/2026-10-21-wonderflix-24b-segnalazioni-app.md`); piano 24c da realizzare";
  - **§4, §7.12, §13:** app 0.18.0 = 24b, 24c = 0.19.0 (decisione 1); release non obbligatoria (decisione 2);
  - **§7.1:** `reports` senza l'accesso ai watch party (decisione 3); i nomi reali dei file;
  - **§7.4:** riquadro fuori dall'animazione (decisione 9); scorciatoia solo sottotitoli fino al 24c (decisione 10);
  - **§7.5:** navigazione di stagioni ed episodi (decisione 4);
  - **§7.6:** finestra con id e titolo (decisione 5); attesa (decisione 7); regola del player (decisione 8);
  - **§7.7:** `ItemMediaInfo` (decisione 6);
  - **§12:** il risultato della verifica su `MediaSources.Path` per i non admin, se emerso durante i task;
  - ogni altra differenza venuta fuori, con il motivo.
- [ ] **Step 3:** `flutter analyze` e la suite intera verdi, poi la build esatta delle Global Constraints (dopo aver copiato `config/wonderflix.json`). Annota il percorso dell'exe.
- [ ] **Step 4: commit** — `git add -A pubspec.yaml docs` e `git commit -m "chore: app 0.18.0 and spec aligned with plan 24b"`

### Task 9: STOP — prova a mano con l'utente

Il subagent si ferma dopo il Task 8. L'orchestratore fa la review finale del branch e i ritocchi, poi **aspetta l'utente** prima di lanciare l'app (memoria `wonderflix-workflow`).

Prova sul server vero (plugin 1.12.0 già installato), con l'admin e due utenti di prova, uno con la spunta "gestione sottotitoli" (la mette l'utente in Jellyfin): spec §11.3, passi 1, 2, 3 e 5.

Da guardare in particolare:
- il download vero da OpenSubtitles e la traccia che compare;
- nel player la traccia aggiunta senza fermarsi, in riproduzione diretta, e il messaggio in transcodifica;
- le notifiche nelle due direzioni;
- "Non sistemabile".

Le richieste di ritocco dell'utente durante la prova si fanno con TDD nello stesso worktree prima del merge.

Con l'ok dell'utente:
1. merge su `main` e push;
2. release del plugin 1.12.0 (tag `watch-party-plugin-v1.12.0`, manifest);
3. release dell'app 0.18.0 (tag `v0.18.0`, con le note scritte nella bozza della release su GitHub; memoria `release-notes`);
4. obbligatoria o no la decide l'utente (decisione 2).
