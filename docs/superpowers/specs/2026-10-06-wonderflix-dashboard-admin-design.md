# WonderFlix — Spec J: dashboard admin

- **Data:** 2026-10-06
- **Stato:** approvato; piano 16a realizzato (docs/superpowers/plans/2026-10-06-wonderflix-16a-admin-sessioni.md), piano 16b realizzato (docs/superpowers/plans/2026-10-06-wonderflix-16b-manutenzione-registro-wonderflix-release.md)
- **Ambito:** Spec J. Realizza l'idea 1 di `docs/IDEE.md` ("Dashboard e azioni da admin dentro WonderFlix"). Usa gli endpoint admin del plugin delle Spec G (`2026-10-03-wonderflix-notifiche-design.md`) e I (`2026-10-05-wonderflix-seerr-design.md`).

## 1. Obiettivo

Oggi l'admin apre la Dashboard di Jellyfin nel browser per vedere chi sta guardando, scansionare le librerie, avviare le attività, leggere il registro e riavviare il server. Le funzioni admin del plugin (annuncio, "Invia ora" delle novità, prova di Seerr) stanno nella sua pagina web. Con la Spec J queste cose si fanno da WonderFlix, in una pagina **Amministrazione** visibile solo agli admin:

- **striscia del server**: nome, versione, "Riavvio necessario" e **Riavvia** con conferma;
- **Sessioni**: chi guarda cosa, come (diretta, remux, transcodifica e perché), chi è collegato, i watch party in corso;
- **Manutenzione**: scansione delle librerie e attività pianificate;
- **Registro**: il registro attività di Jellyfin;
- **WonderFlix**: annuncio, novità, stato di Seerr.

La Spec J non tocca il plugin: tutto passa dalle API di Jellyfin e dagli endpoint admin che il plugin ha già.

## 2. Situazione di partenza

- **App 0.9.0:**
  - `JellyfinUser` (`lib/core/jellyfin/auth_models.dart`) legge da `Policy` solo `SyncPlayAccess`. **`Policy.IsAdministrator` arriva** con `/Users/Me` e con l'accesso, **ma si scarta**. L'app non sa chi è admin.
  - La sessione è in `sessionControllerProvider` (`SessionSignedIn(user)`). `/Users/Me` si rilegge al ripristino della sessione. Un provider derivato come `syncPlayAccessProvider` (`lib/features/watch_party/watch_party_providers.dart`) è il modello per `isAdminProvider`.
  - `JellyfinHttp` ha `get`, `post` e `delete`. Gli errori diventano `ApiException` (Unauthorized, Forbidden, NotFound, ServerUnreachable, ServerError…). Un 401 chiama `onUnauthorized` e si esce dall'account.
  - **Nessuna chiamata admin di Jellyfin:** niente `/Sessions` (elenco), `/ScheduledTasks`, `/System/ActivityLog`, `/System/Info` (con accesso), `/System/Restart`, `/Library/Refresh`, `/Library/VirtualFolders`, `/Plugins`. `SystemApi` legge solo `/System/Info/Public`.
  - **Nessuna chiamata agli endpoint admin del plugin** (§3).
  - La barra in alto: Home, Film, Serie, La mia lista, [Richieste], Cerca. A destra watch party, amici, cassetta e il **menu dell'avatar** (`_UserMenu` in `lib/app/app_shell.dart`) con Impostazioni ed Esci.
  - Le rotte della shell sono in `lib/app/router.dart`. `/requests` non è protetta dal router: la pagina guarda `requestsGoneProvider` e torna a `/home`.
  - Il WebSocket (`ServerEventsClient`) manda solo `KeepAlive` e si ricollega da solo.
  - `inboxTimeLabel` (`lib/features/inbox/inbox_time.dart`) fa le ore relative ("5 min fa", "2 h fa", "ieri"…).
  - WonderFlix non dichiara a Jellyfin le capacità di controllo remoto (`/Sessions/Capabilities`).
- **Plugin 1.4.0**, endpoint con `RequiresElevation` (solo admin di Jellyfin):

  | Endpoint | Risposta |
  |---|---|
  | `POST WonderFlixWatchParty/Inbox/Announcements` `{Text}` (1–500 caratteri) | `{Recipients}`, 400 se il testo non va |
  | `GET WonderFlixWatchParty/Inbox/NewTitles` | `{Enabled, Pending}` (`Pending` è un numero) |
  | `POST WonderFlixWatchParty/Inbox/NewTitles/Send` | `{Titles, Recipients}` |
  | `POST WonderFlixWatchParty/Requests/Test` | sempre 200: `{Ok, Version, Error}` con `Error` tra `NotConfigured`, `SeerrAuth`, `SeerrUnavailable` |
  | `GET WonderFlixWatchParty/Requests/Admin` | `{Configured, LastEventAt, LastEventType}` |

  - La configurazione (`NotifyNewTitles`, `SeerrUrl`, `SeerrApiKey`, `SeerrWebhookSecret`) passa da `GET/POST /Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration` di Jellyfin, come fa la pagina web del plugin.
  - `Inbox/*` esiste dal plugin 1.2.0 (funzione `inbox`), `Requests/*` dal 1.4.0.

## 3. Il server

Fatti raccolti il 2026-10-06, in sola lettura.

- **Jellyfin 10.11.9** in un container Ultra.cc, sotto `s6-supervise`. **Il riavvio da API funziona:** il processo esce e s6 lo rilancia. Il 2026-10-05 alle 22:22 UTC, dopo l'installazione del plugin 1.4.0, Jellyfin si è fermato ed è ripartito da solo.
- **Librerie:** Anime, Collezioni2, Movies, Shows.
- **Plugin installati:** circa 20 (AniDB, AniList, Auto Collections, Chapter Creator, Intro Skipper, Playback Reporting, Trakt, TMDb Box Sets, InfuseSync…). Molti aggiungono attività pianificate, quindi l'elenco delle attività è lungo.
- **Registro attività:** 12.134 voci dal 2026-04-14, circa 150 al giorno. Nell'ultima settimana erano quasi tutte `SessionStarted`/`SessionEnded` e `VideoPlayback`/`VideoPlaybackStopped`, più accessi, utenti e plugin. Il server scrive già i testi in italiano ("viviroby è online su FireTV Soggiorno").
- **Client:**
  - gli amici usano soprattutto Jellyfin Android TV (FireTV), Jellyfin Web, Jellyfin Desktop e le app iOS;
  - WonderFlix è uno dei tanti client;
  - Seerr e jfa-go aprono sessioni con una chiave API.
- **Spazio disco:** Jellyfin vede il disco condiviso del server (26 TB, 13 TB liberi). La quota vera dell'account Ultra è di 11,2 TB, con 9,9 TB usati, cioè circa 1,2 TB liberi. Il dato di Jellyfin (`/System/Info/Storage`) trarrebbe in inganno.
- **Utenti:** 22.

## 4. Decisioni

| Tema | Decisione |
|---|---|
| Funzioni | sessioni e server, manutenzione, registro, plugin WonderFlix; **niente** utenti e permessi |
| Posizione | voce **"Amministrazione" nel menu dell'avatar** → pagina `/admin` con schede; la barra in alto non cambia |
| Sessioni | **solo vedere**: niente messaggi né stop (WonderFlix non accetta comandi remoti) |
| Plugin | **azioni e stato**: annuncio, interruttore e "Invia ora" delle novità, stato e prova di Seerr; la configurazione di Seerr resta nella pagina web del plugin |
| Architettura | **solo app**: API admin di Jellyfin con il token dell'admin, più gli endpoint admin del plugin che esistono già; l'interruttore delle novità riscrive la configurazione del plugin intera |
| Aggiornamento | **rilettura periodica** mentre la scheda è visibile (il Registro no: si ricarica con "Aggiorna", §9.5); niente sottoscrizioni sul WebSocket |
| Spazio disco | **escluso** (§3) |
| Release | app **0.10.0 non obbligatoria**; nessuna release del plugin |

## 5. Perimetro

### Incluso

- `JellyfinUser.isAdministrator`, `isAdminProvider` e la voce "Amministrazione" nel menu dell'avatar.
- La pagina `/admin` con la striscia del server e quattro schede: Sessioni, Manutenzione, Registro, WonderFlix.
- Riavvio del server con conferma e attesa del ritorno.
- `AdminApi`, `PluginAdminApi` e i loro modelli.
- Un helper comune per la rilettura periodica.

### Escluso

- **Utenti e permessi** (creare, disattivare, eliminare utenti, policy, password).
- **Messaggio e stop sulle sessioni**: servirebbe che WonderFlix dichiarasse le capacità di controllo remoto e obbedisse ai comandi.
- **Spazio disco** (§3).
- **Pianificazioni delle attività** (trigger): si vedono e si cambiano dalla Dashboard web.
- **File di log** (`/System/Logs`).
- **Configurazione di Seerr** (indirizzo, chiave, segreto, modello del webhook): resta nella pagina web del plugin.
- **Plugin, catalogo, dispositivi, chiavi API, impostazioni del server, librerie** (aggiungere, togliere, cambiare cartelle o opzioni).
- **Spegnimento** del server.
- **Filtro per gravità** del registro: le API non lo hanno.
- **Aggiornamento in diretta** con le sottoscrizioni del WebSocket (`SessionsStart`, `ScheduledTasksInfoStart`, `ActivityLogEntryStart`).
- **Il metodo di riproduzione che WonderFlix dichiara** (il punto aperto "remux che risulta Transcode" dell'idea 5): resta nell'idea 5. La scheda Sessioni mostra comunque "Remux" anche in quel caso (§9.3).

## 6. Architettura

```
lib/core/jellyfin/
  auth_models.dart          JellyfinUser.isAdministrator (Policy.IsAdministrator)
  admin_api.dart            AdminApi: Sessions, SyncPlay/List, System/Info, System/Info/Public, System/Restart,
                            Library/VirtualFolders, Items/{id}/Refresh, ScheduledTasks,
                            ScheduledTasks/Running/{id}, System/ActivityLog/Entries
  json_fields.dart          le letture tolleranti dei JSON (§8.2), usate da tutti i modelli
  admin_models.dart         SessionEntry, NowPlaying, NowPlayingKind, PlayMethod, TranscodeInfo, PartyGroup,
                            PartyState, ServerInfo
  maintenance_models.dart   LibraryFolder, LibraryKind, ScheduledTask, TaskState, TaskResult, TaskStatus
  activity_models.dart      ActivityEntry, ActivitySeverity, ActivityPage
lib/core/social/
  plugin_admin_api.dart     PluginAdminApi: Inbox/Announcements, Inbox/NewTitles (+Send),
                            Requests/Admin, Requests/Test, /Plugins/{id}/Configuration
  plugin_admin_models.dart  NewTitlesStatus, NewTitlesSent, SeerrAdminStatus, SeerrTestResult
lib/features/auth/
  auth_service.dart         currentUser(): rilegge /Users/Me
  session_controller.dart   refreshUser(): rilegge l'utente della sessione (§12)
lib/features/admin/
  admin_providers.dart      isAdminProvider, adminApiProvider, pluginAdminApiProvider,
                            adminForegroundProvider, adminEpochProvider
  admin_navigation.dart     AdminTab (sessions, maintenance, activity, wonderflix), adminTabs (WonderFlix solo
                            con `inbox`) e l'indirizzo
  admin_poller.dart         rilettura periodica (§10)
  admin_tab_controller.dart AdminData e AdminTabController: la base dei controller delle schede e della striscia (§10)
  admin_time.dart           ore relative e assolute (§9.5), durate (§9.4), ora dell'ultimo aggiornamento
  admin_widgets.dart        titolo di sezione, testo vuoto, riga utente con l'iniziale, "Dati non aggiornati",
                            AdminCard e AdminCardError (le card della scheda WonderFlix)
  admin_action_button.dart  AdminActionButton: il pulsante di un'azione (§9.4)
  admin_confirm_dialog.dart showAdminConfirmDialog: conferma con titolo, messaggio e pulsante
  admin_screen.dart         pagina, schede, rinvio dei non admin
  server_info_controller.dart  ServerInfoController: le informazioni del server, e l'utente (§9.2, §12)
  server_strip.dart         striscia del server, RestartArea
  restart_controller.dart   riavvio: POST, attesa del ritorno
  restart_dialog.dart       finestra di conferma
  sessions_controller.dart  sessioni + watch party
  sessions_tab.dart         card "In riproduzione", righe "Collegati", watch party
  session_labels.dart       metodo, titolo, dispositivo, motivi, accelerazione, stato dei party
  maintenance_controller.dart  librerie + attività, scansioni, Avvia e Ferma
  maintenance_tab.dart
  task_labels.dart          stato di un'attività ferma, percentuale
  activity_controller.dart  pagine del registro, filtro (non rilegge da solo)
  activity_tab.dart
  wonderflix_controllers.dart  InboxAdminController (novità, annuncio, interruttore, "Invia ora") e
                            SeerrAdminController (stato, prova)
  wonderflix_labels.dart    testi del tipo di evento e della prova di Seerr, delle novità
  wonderflix_tab.dart       le card Annuncio, Novità e Seerr
lib/ui/wf_tab_button.dart   pulsante delle schede, spostato dalla pagina Richieste (§9.1)
lib/app/router.dart         + /admin?tab=
lib/app/app_shell.dart      + voce "Amministrazione" nel menu dell'avatar
l10n/app_it.arb, app_en.arb + testi (§11)
```

Le API stanno con le altre: `AdminApi` in `lib/core/jellyfin/` (endpoint di Jellyfin), `PluginAdminApi` in `lib/core/social/` (endpoint del plugin). Hanno la forma di `RequestsApi`: classe sottile su `JellyfinHttp`, modelli con `fromJson` scritti a mano, niente codegen. I controller sono `Notifier` con stato immutabile e `NotifierProvider.autoDispose`, come in `lib/features/requests/`. Quelli delle schede e della striscia estendono `AdminTabController` (§10); quello del Registro no, perché non rilegge da solo (§9.5). Le due API si prendono da `adminApiProvider` e `pluginAdminApiProvider` (`admin_providers.dart`).

## 7. Accesso e navigazione

- **`JellyfinUser.isAdministrator`:** viene da `Policy.IsAdministrator` e vale `false` se manca. Si legge all'accesso e a ogni `/Users/Me`.
- **`isAdminProvider`:** vero solo con `SessionSignedIn` e `user.isAdministrator`.
- **Menu dell'avatar:** per gli admin c'è "Amministrazione" (icona `LucideIcons.shieldCheck`) tra Impostazioni ed Esci, e apre `context.go('/admin')`. Per gli altri il menu resta com'è.
- **Rotta:** `/admin?tab=sessions|maintenance|activity|wonderflix` nella shell (`shellPage`). Senza `tab`, o con un valore sconosciuto, si apre `sessions`. La scheda scelta finisce nell'indirizzo con `context.go` (`openAdmin`), come nella pagina Richieste. La rotta non mette una chiave alla pagina: cambiando scheda la pagina resta la stessa, e con lei la striscia e un riavvio in corso.
- **Protezione:** la rotta non è protetta dal router. Se `isAdminProvider` è falso, la pagina fa `context.go('/home')` dopo il primo frame, come `RequestsScreen`. Vale anche quando l'utente smette di essere admin mentre guarda la pagina (§12).
- **Scheda WonderFlix:** c'è solo con la funzione `inbox` del plugin (`socialAvailabilityProvider`).
  - Senza la funzione, `?tab=wonderflix` mostra Sessioni. Lo stesso se la funzione sparisce mentre la scheda è aperta. L'indirizzo non cambia: resta `?tab=wonderflix`.
  - Subito dopo l'accesso non si sa ancora se il plugin c'è (finché `Info` non risponde). Con `?tab=wonderflix` e le funzioni non ancora note la pagina mostra l'indicatore di caricamento, con le altre tre schede nella fila e nessuna scelta. Non si passa da Sessioni: si leggerebbero dati per niente e per un attimo comparirebbe il contenuto sbagliato. Appena le funzioni sono note, la pagina mostra WonderFlix, oppure Sessioni se manca `inbox`.
  - Le altre schede si vedono subito, anche con le funzioni non note.
- **Titolo:** nessun titolo nella barra. La pagina ha il titolo grande "AMMINISTRAZIONE", come la pagina Richieste, senza `ShellPageFrame`.

## 8. Dati: API e modelli

### 8.1 `AdminApi` (Jellyfin)

| Metodo | Chiamata | Note |
|---|---|---|
| `sessions()` | `GET /Sessions?activeWithinSeconds=960` | Restano fuori le sessioni senza `UserId`, o con un `UserId` di soli zeri (chiavi API di Seerr, jfa-go…). |
| `partyGroups()` | `GET /SyncPlay/List` | Con l'admin l'elenco è completo. |
| `serverInfo()` | `GET /System/Info` | `ServerName`, `Version`, `OperatingSystemDisplayName` (sul server è vuoto), `HasPendingRestart`. |
| `isServerUp()` | `GET /System/Info/Public` | Per l'attesa del riavvio: `true` solo con 200 e `StartupWizardCompleted` a `true`; `false` con qualunque `ApiException` (rete, 5xx…) e con ogni altra risposta (campo `false` o mancante, corpo che non è un oggetto). |
| `restart()` | `POST /System/Restart` | I 502/503/504 di nginx vanno nel registro come informazioni. |
| `libraries()` | `GET /Library/VirtualFolders` | `Name`, `CollectionType`, `ItemId`, `RefreshStatus`, `RefreshProgress`. |
| `scanLibrary(itemId)` | `POST /Items/{itemId}/Refresh?Recursive=true&ImageRefreshMode=Default&MetadataRefreshMode=Default&ReplaceAllImages=false&RegenerateTrickplay=false&ReplaceAllMetadata=false` | I parametri di "Scansiona libreria" della Dashboard web 10.11.9 (`refreshdialog.js`, modo "scan"), copiati uguali per avere lo stesso comportamento: metadati e immagini solo dove mancano. `Recursive` non è nell'OpenAPI 10.11.9 e Jellyfin lo ignora: la scansione di una libreria comprende comunque le sotto-cartelle. |
| `tasks()` | `GET /ScheduledTasks?isHidden=false` | |
| `startTask(id)` | `POST /ScheduledTasks/Running/{id}` | |
| `stopTask(id)` | `DELETE /ScheduledTasks/Running/{id}` | |
| `activity({startIndex, hasUserId})` | `GET /System/ActivityLog/Entries` | `limit` sempre 50 (`activityPageSize`). `hasUserId` assente per "Tutto". Risposta `{Items, TotalRecordCount, StartIndex}`. |

- **"Scansiona tutte" non ha una chiamata sua.** `POST /Library/Refresh` in Jellyfin 10.11 risponde solo quando la scansione di tutte le librerie è finita, e non mostra l'avanzamento. Come la Dashboard web, "Scansiona tutte" avvia con `startTask` l'attività pianificata "Scansione della libreria" (`Key == "RefreshLibrary"`), e se ne vede lo stato accanto al pulsante (§9.4).
- **Chi è admin:** le letture della pagina (`/Sessions`, `/SyncPlay/List`, `/System/Info`) non chiedono di essere admin. Solo `/System/Restart` lo chiede. Un 403 dice con certezza "non sei admin" solo per il riavvio. Per le letture è un segnale in più, non quello su cui ci si affida (§12). Anche per le azioni e le letture delle altre schede (Manutenzione, Registro, WonderFlix) un 403 fa rileggere l'utente, e basta.
- **Riavvio di Jellyfin:**
  - le risposte 502/503/504 di nginx alle letture, a `isServerUp()`, al `POST /System/Restart` e alla rilettura dell'utente (`/Users/Me`, quella che fa la pagina) sono attese. Vanno nel registro dell'app come informazioni, non come avvisi (un 500 resta un avviso);
  - il ripristino della sessione all'avvio dell'app e l'accesso non cambiano;
  - **il server di setup:** Jellyfin 10.11 avvia prima un piccolo server di setup, 6-18 s prima di quello vero, e lo stesso `GET /System/Info/Public` può rispondere 200 mentre l'app vera non c'è ancora (non verificato: si vede solo durante un riavvio). Per questo `isServerUp()` guarda `StartupWizardCompleted`: il server vero risponde `true`, quello di setup no.

### 8.2 Modelli

- **`SessionEntry`:**
  - `id`, `userId`, `userName`, `client`, `deviceName`, `lastActivity`;
  - `nowPlaying` (facoltativo): `itemId`, `name`, `kind` (`NowPlayingKind`: film, episodio, altro; da `Type`), `year` (`ProductionYear`), `seriesName`, `seriesId`, `seasonNumber` (`ParentIndexNumber`), `episodeNumber` (`IndexNumber`), `runtime` (da `RunTimeTicks`). La locandina è quella dell'elemento, o della serie per gli episodi;
  - da `PlayState`: `position` (da `PositionTicks`), `isPaused`, `playMethod`;
  - `transcode` (facoltativo, da `TranscodingInfo`): `videoCodec`, `audioCodec`, `isVideoDirect`, `isAudioDirect`, `bitrate` (bit al secondo), `width`, `height`, `hardwareAcceleration`, `reasons` (stringhe).
- **`PlayMethod`:** `directPlay`, `directStream`, `transcode`, `unknown`.
- **`PartyGroup`:** `id`, `name`, `state` (Idle, Waiting, Paused, Playing; altro → `unknown`), `participants` (nomi).
- **`ServerInfo`:** `name`, `version`, `operatingSystem`, `hasPendingRestart`.
- **`LibraryFolder`:** `itemId`, `name`, `kind`, `refreshing`, `refreshProgress` (0–100, facoltativo).
  - `kind` (`LibraryKind`: film, serie, altro) viene da `CollectionType` e serve per l'icona.
  - `refreshing` è vero per ogni `RefreshStatus` diverso da "Idle", quindi anche per "Queued": una libreria in coda dietro un'altra, che non ha ancora un avanzamento. Senza `RefreshStatus` è falso.
  - Una libreria senza `ItemId` si scarta: non si potrebbe scansionare.
- **`ScheduledTask`:**
  - `id`, `key`, `name`, `description`, `category`;
  - `state`: `idle`, `running`, `cancelling`; uno stato sconosciuto vale come `idle` (ferma);
  - `progress` (facoltativo);
  - `lastResult` (facoltativo, `TaskResult`): `start`, `end`, `status` (`TaskStatus`: Completed, Failed, Cancelled, Aborted; altro è `unknown`), `errorMessage`, e la durata (fine meno inizio, se ci sono tutte e due).
  - Un'attività senza `Id` si scarta: non si potrebbe avviare.
- **`ActivityEntry`:** `id`, `name`, `shortOverview`, `overview`, `type`, `itemId`, `date`, `userId`, `severity` (`info`, `warning`, `error`: Trace, Debug e Information sono `info`; Critical è `error`).
  - Un `userId` o un `itemId` di soli zeri (le voci di sistema) vale `null`.
  - Non c'è `userImageTag`: Jellyfin dà solo l'id dell'utente, e l'app non ha un indirizzo per l'immagine (§9.5).
- **`ActivityPage`:** `items` e `total` (`TotalRecordCount`; se manca, il numero delle voci lette).
- Le date arrivano in UTC e si mostrano in ora locale. I campi mancanti o di tipo sbagliato non fanno fallire la lettura dell'elenco: una voce senza `Id` si scarta, gli altri campi diventano `null`. Le letture tolleranti sono in `json_fields.dart` e le usano tutti i modelli. Un corpo che non è quello atteso (un elenco, un oggetto) è un errore del server. Le risposte del plugin hanno invece dei campi obbligatori (§8.3).

### 8.3 `PluginAdminApi` (plugin)

| Metodo | Chiamata |
|---|---|
| `announce(text)` | `POST /WonderFlixWatchParty/Inbox/Announcements` `{Text}` → `recipients` |
| `newTitles()` | `GET /WonderFlixWatchParty/Inbox/NewTitles` → `NewTitlesStatus(enabled, pending)` |
| `sendNewTitles()` | `POST /WonderFlixWatchParty/Inbox/NewTitles/Send` → `NewTitlesSent(titles, recipients)` |
| `seerrStatus()` | `GET /WonderFlixWatchParty/Requests/Admin` → `SeerrAdminStatus(configured, lastEventAt, lastEventType)`, oppure `null` con 404 (plugin più vecchio della 1.4.0) |
| `testSeerr()` | `POST /WonderFlixWatchParty/Requests/Test` → `SeerrTestResult(ok, version, error)` |
| `setNotifyNewTitles(bool)` | `GET /Plugins/882eb47e-668a-4935-ba55-c2858eb4ed90/Configuration` come mappa JSON, cambio della sola chiave `NotifyNewTitles`, `POST` della mappa intera allo stesso indirizzo |

- **Campi obbligatori:** una risposta senza i suoi campi, o con un campo di un altro tipo, è un errore (`ServerErrorException`): meglio un errore di un "0 titoli" o di uno "spento" inventati. Zero e `false` sono valori veri.
  - l'annuncio: `Recipients` (intero);
  - le novità: `Enabled` (booleano) e `Pending` (intero);
  - "Invia ora": `Titles` e `Recipients` (interi);
  - lo stato di Seerr: `Configured` (booleano);
  - la prova di Seerr: `Ok` (booleano).

  Gli altri campi (`LastEventAt`, `LastEventType`, `Version`, `Error`) sono facoltativi.
- **`setNotifyNewTitles`:**
  - le altre chiavi della mappa (anche quelle che l'app non conosce) passano intatte;
  - la chiave `NotifyNewTitles` (PascalCase) è stata verificata sulla risposta vera del server;
  - **non scrive** se la configurazione letta non ha `NotifyNewTitles` booleano o non ha `SeerrApiKey` (si dà un errore): una `POST` con una mappa parziale riporterebbe ai valori di partenza le chiavi che mancano, cioè indirizzo, chiave e segreto di Seerr. Vale anche per un corpo che non è un oggetto e per una lettura fallita.
- `PluginAdminApi` non tiene nulla della configurazione dopo la chiamata: chiave e segreto di Seerr attraversano la memoria dell'app solo durante la riscrittura e non finiscono nel registro dell'app, nemmeno se la scrittura fallisce.
- Gli esiti attesi (400 dell'annuncio, 404 del plugin più vecchio, 502/503/504 di nginx durante un riavvio) vanno nel registro dell'app come informazioni.

## 9. Interfaccia

### 9.1 Pagina

- In cima il titolo grande (§7), poi la **striscia del server** (§9.2), sotto la fila delle schede, poi il contenuto della scheda.
- Le schede hanno lo stesso aspetto di quelle della pagina Richieste. Il pulsante privato `_TabButton` di `lib/features/requests/requests_screen.dart` diventa `WfTabButton` in `lib/ui/wf_tab_button.dart`, usato da tutte e due le pagine.
- Ogni scheda ha i suoi stati: caricamento, errore con "Riprova", vuoto, dati. In caricamento la scheda mostra `LoadingView`, come la pagina Richieste, e la striscia uno `SkeletonBox`.

### 9.2 Striscia del server e riavvio

- **Striscia:** nome del server, "Jellyfin 10.11.9 · <sistema>" e il pulsante **Riavvia**.
  - Il sistema compare solo se Jellyfin lo dice. Sul server `OperatingSystemDisplayName` è vuoto, quindi si vede solo "Jellyfin 10.11.9".
  - Con `HasPendingRestart` compare l'avviso "Riavvio necessario: Jellyfin va riavviato per finire un'installazione o un aggiornamento".
  - Si rilegge all'apertura della pagina, ogni 60 s e dopo un riavvio. A ogni lettura si rilegge anche l'utente (§12).
  - Senza dati e con la lettura fallita, la striscia mostra l'errore con "Riprova".
- **Conferma:**
  - Riavvia apre una finestra (`wf_dialog.dart`). All'apertura l'app rilegge le sessioni, quindi i dati sono freschi; mentre legge mostra un indicatore.
  - Con qualcuno che guarda: "{n} persone stanno guardando:", l'elenco "nome — titolo", e "Il riavvio interrompe la visione e i watch party." Una sola persona ha il testo al singolare.
  - Senza nessuno: "Nessuno sta guardando."
  - Se la lettura fallisce: "Non so chi sta guardando."
  - Con tanti spettatori l'elenco scorre e i pulsanti restano in vista.
  - Pulsanti: "Annulla" e **"Riavvia"** in rosso.
- **Riavvio** (`RestartController`):
  1. `POST /System/Restart`:
     - un errore di rete, un timeout o un 502/503/504 di nginx contano come **riavvio partito**: Jellyfin può fermarsi prima di rispondere;
     - un **401**: nessun avviso, l'app esce dall'account da sola (§12);
     - un **403**: l'utente si rilegge (§12) e compare "Riavvio non riuscito";
     - **qualsiasi altro errore** mostra "Riavvio non riuscito" e la striscia torna normale. Un errore inatteso, che non viene dall'API, va anche nel registro dell'app (mai il corpo di una risposta); quelli dell'API ci sono già, con metodo, percorso ed esito.
  2. Al posto di Riavvia la striscia mostra l'indicatore e "Riavvio in corso…". Un secondo Riavvia mentre si aspetta non fa niente: nessun altro `POST`.
  3. Ogni 3 s `isServerUp()`. Jellyfin conta come **tornato** quando risponde dopo essere stato giù almeno una volta, oppure se in 60 s non è mai caduto. "Risponde" vuol dire che `/System/Info/Public` dà 200 con `StartupWizardCompleted` a `true` (§8.1): il server di setup che Jellyfin avvia per primo non conta.
  4. Al ritorno: l'avviso "Jellyfin è tornato", e la striscia e la scheda aperta si ricaricano.
  5. Dopo 3 minuti senza ritorno: "Jellyfin non risponde ancora" con "Ricontrolla", che fa ripartire l'attesa.
- Il resto dell'app non cambia comportamento: il WebSocket si ricollega da solo come oggi. Un'eventuale riproduzione dell'admin si interrompe come per tutti.
- Il riavvio vive nel controller della pagina: se l'admin esce dalla pagina, l'attesa si ferma senza avvisi.

### 9.3 Sessioni

Si rilegge ogni 5 s.

- **"In riproduzione"**: una card per ogni sessione con `nowPlaying`, ordinate per nome dell'utente (senza badare alle maiuscole). A parità, per nome del dispositivo e poi per id della sessione: lo stesso utente su due dispositivi non cambia posto a ogni lettura. Ogni card mostra:
  - l'**avatar**, cioè l'iniziale del nome in un cerchio (l'app non ha un indirizzo per le immagini degli utenti), e il nome;
  - client e dispositivo ("Jellyfin Android TV · FireTV Soggiorno");
  - il **titolo**:
    - film: "Titolo (anno)";
    - episodio: "Serie · S1:E3 · Titolo";
    - altro: il nome;
  - l'**immagine**: la locandina; per gli episodi quella della serie;
  - l'**avanzamento**: barra, "12:34 / 1:45:20", e l'icona di pausa se è in pausa. Se Jellyfin non dà la durata, o la dà a zero, la durata è sconosciuta: la barra resta vuota e si vede solo la posizione ("12:34");
  - il **metodo**:
    - **"Diretta"**: `DirectPlay`;
    - con `TranscodingInfo` decidono i suoi dati: video e audio entrambi diretti sono **"Remux"** (anche se il client dichiara `Transcode`), tutti gli altri casi sono **"Transcodifica"**;
    - senza `TranscodingInfo` decide il metodo dichiarato: `DirectStream` è "Remux", `Transcode` è "Transcodifica", ogni altro valore non ha etichetta.
  - **Solo con "Transcodifica"**, sotto, ci sono la riga "→ H264 1080p · AAC · 8,2 Mbps · Software" e i **motivi**. Il Remux non ha né la riga né i motivi. La riga dice:
    - codec e altezza del video, se il video si transcodifica;
    - codec dell'audio, se l'audio si transcodifica;
    - il bitrate, se c'è;
    - l'accelerazione hardware, se il video si transcodifica (nome, oppure "Software" se manca).

    Se non c'è niente da dire, la riga non compare.
  - **Motivi tradotti**:
    - contenitore, codec video, codec audio, codec dei sottotitoli, profilo, livello, risoluzione, profondità di colore, gamma dinamica (`VideoRangeTypeNotSupported`), canali audio, bitrate oltre il limite (`ContainerBitrateExceedsLimit`, `VideoBitrateNotSupported`, `AudioBitrateNotSupported`), audio esterno;
    - frequenza dei fotogrammi (`VideoFramerateNotSupported`), frequenza di campionamento (`AudioSampleRateNotSupported`), profondità audio (`AudioBitDepthNotSupported`), traccia audio secondaria (`SecondaryAudioNotSupported`), video interlacciato (`InterlacedVideoNotSupported`), fotogrammi di riferimento (`RefFramesNotSupported`), video anamorfico (`AnamorphicVideoNotSupported`), troppe tracce (`StreamCountExceedsLimit`), errore della riproduzione diretta (`DirectPlayError`);
    - "traccia sconosciuta" per `UnknownVideoStreamInfo` e `UnknownAudioStreamInfo`.

    Un motivo senza traduzione appare con il nome originale. I motivi stanno su una riga, senza doppioni (le due tracce sconosciute fanno un motivo solo).
- **"Collegati"**: una riga compatta per ogni sessione senza `nowPlaying`, ordinata per attività recente (a parità, per dispositivo e poi per id). Mostra utente, client e dispositivo, e "attivo {ora}" (§9.5).
- **"Watch party"**: una riga per gruppo con nome, stato ("In riproduzione", "In pausa", "In attesa", "Fermo") e partecipanti. Senza accesso ai watch party (`SyncPlayAccess.none`) l'elenco non si chiede e resta vuoto: Jellyfin lo rifiuterebbe.
  - Sessioni e watch party si leggono insieme. Se fallisce solo l'elenco dei watch party, la scheda non va in errore: restano le sessioni nuove e i party dell'ultima lettura riuscita (nessuno, se non c'è stata). Se falliscono le sessioni, fallisce la lettura (§10), e un 403 fa rileggere l'utente (§12).
- **Vuoti:** "Nessuno sta guardando", "Nessuno collegato", "Nessun watch party in corso".
- Le sessioni dell'admin stesso compaiono come le altre, anche in "Collegati": per questo il vuoto è "Nessuno collegato" e non "Nessun altro collegato".
- Le sessioni senza un utente vero si scartano: senza `UserId`, o con un `UserId` di soli zeri (§8.1).

### 9.4 Manutenzione

**Librerie:**
- Il pulsante **"Scansiona tutte"** avvia l'attività con `Key == "RefreshLibrary"` (`startTask`, §8.1). Sta sul bordo destro dell'intestazione, e accanto mostra lo stato di quell'attività:
  - la percentuale se è in corso;
  - "Arresto…" se si sta fermando;
  - altrimenti "Ultima: {ora}" (niente, se non è mai stata eseguita).

  Il pulsante è attivo **solo se l'attività c'è ed è ferma**: senza l'attività, o con la scansione in corso o in arresto, è disattivato.
- Per ogni libreria: un'icona secondo `kind` (film, serie, altro), il nome e **"Scansiona"** (`scanLibrary`). Durante la scansione (anche se è solo in coda) c'è la barra con `refreshProgress` (vuota se Jellyfin non lo dice) e il pulsante è disattivato.
- Dopo un clic la scheda si rilegge subito (§10).

**Pulsanti delle azioni** (Scansiona tutte, Scansiona, Avvia, Ferma; anche quelli della scheda WonderFlix, §9.6):
- Mentre la loro azione è in corso sono disattivati, e una pressione in più prima del ridisegno non la fa ripartire.
- Se l'azione fallisce compare un avviso con l'errore, e la scheda mostra lo stato vero, riletto subito (§12).
- Se nel frattempo il pulsante non c'è più (scheda o pagina cambiata) non compare niente.

**Attività pianificate:**
- Sono raggruppate per `category`. Le categorie, e dentro ognuna le attività, vanno in ordine alfabetico: categoria e poi nome, senza badare alle maiuscole, come nella Dashboard web. Il server le dà ordinate solo per nome, quindi seguire il suo ordine mescolerebbe le categorie. Ogni gruppo ha come titolo il nome della categoria, così come arriva.
- Ogni riga mostra il nome, la descrizione (una riga, intera al passaggio del mouse) e lo stato:
  - **ferma**:
    - "Ultima: {ora} · Completata in {durata}";
    - oppure "Ultima: {ora} · Annullata" o "Ultima: {ora} · Interrotta";
    - oppure "Ultima: {ora}" e, accanto, **"Non riuscita"** in rosso: un clic apre `errorMessage`, se c'è;
    - oppure "Mai eseguita".
    
    Pulsante **Avvia**.
  - **in corso**: barra con `progress` e la percentuale, e pulsante **Ferma**.
  - **in arresto**: "Arresto…", senza pulsanti.
- La durata si scrive "45 s", "3 min", "1 h 5 min". Una durata negativa (l'orologio del server era indietro) vale zero.
- Dopo Avvia o Ferma la scheda si rilegge subito.

**Ritmo:** ogni 2 s se un'attività è in corso o in arresto, o se una libreria si sta scansionando; altrimenti ogni 15 s.

### 9.5 Registro

- Pagine da 50, dalla voce più recente. La pagina successiva si carica quando si arriva in fondo (o subito, se la prima non riempie la finestra); in fondo all'elenco c'è "Non ci sono altre voci".
- **Voci arrivate in cima tra una pagina e l'altra:** spostano gli indici. Le pagine si leggono con un cursore del server e si tengono solo le voci più vecchie dell'ultima mostrata: niente doppioni e niente voci nuove in fondo. Se una pagina non ne ha, si legge la successiva, fino a 5 pagine in più per volta. La fine dell'elenco la dà il totale del server, o una pagina vuota.
- **Filtri:** "Tutto", "Utenti" (`hasUserId=true`), "Sistema" (`hasUserId=false`). Cambiare filtro ricomincia dalla prima pagina; la risposta di un caricamento con il filtro di prima si scarta.
- **Riga:**
  - l'icona della gravità: informazione grigia, avviso ambra, errore rosso;
  - `name`, e `shortOverview` sotto in piccolo;
  - l'**ora**.
  
  Un clic apre `overview`, se c'è. Se la voce ha un `itemId`, il link "Apri il titolo" apre `/item/{itemId}`.
- **Niente avatar:** Jellyfin dà solo l'id dell'utente, e il nome sta già nel testo della voce ("viviroby è online su …").
- **Ora** (`admin_time.dart`): "adesso", "{n} min fa", "{n} h fa" nello stesso giorno; dal giorno prima la data con l'ora ("5 ott, 22:53") nella lingua dell'app. Il passaggio del mouse mostra data e ora complete, con i secondi ("6 ott 2026, 08:10:03").
- **Nessuna rilettura automatica:** le righe nuove in cima farebbero saltare lo scorrimento. Il registro si ricarica all'apertura della scheda e con **"Aggiorna"**.
  - "Aggiorna" riparte dalla prima pagina, e la vista torna in cima.
  - Lo stesso quando Jellyfin torna da un riavvio (`adminEpochProvider`, §10): l'elenco di prima può non essere più quello del server.
  - Le ore relative ("5 min fa") non si aggiornano da sole (§14).
- **Un caricamento fallito:**
  - senza voci in elenco, la scheda mostra l'errore con "Riprova";
  - con voci già mostrate, restano e in fondo c'è l'errore accanto a "Riprova". La pagina dopo non si chiede da sola finché c'è l'errore;
  - "Riprova" ripete lo stesso tipo di caricamento: la pagina dopo, se era quella a fallire; la prima pagina, se era "Aggiorna", il cambio di filtro o l'apertura. Un "Aggiorna" fallito non aggiunge niente in coda alle voci mostrate.
  - Un 403 fa rileggere l'utente (§12).
- Vuoto: "Nessuna voce".

### 9.6 WonderFlix

Tre card, nell'ordine Annuncio, Novità, Seerr. I dati stanno in due controller (`wonderflix_controllers.dart`), che estendono `AdminTabController`:
- **`InboxAdminController`:** lo stato delle novità (`newTitles()`) e le azioni annuncio, interruttore e "Invia ora";
- **`SeerrAdminController`:** lo stato di Seerr (`seerrStatus()`) e "Prova collegamento".

Ognuno si rilegge all'apertura, dopo ogni sua azione e ogni 30 s. Ogni card ha il suo stato e il suo errore: se una non carica, le altre funzionano. Una card senza dati mostra una barra di attesa (`SkeletonBox`), e con la lettura fallita l'errore con "Riprova". Se la lettura fallisce ma ci sono i dati di prima, le card Novità e Seerr mostrano la riga "Dati non aggiornati · ultimo aggiornamento {ora}" (§10). La card Annuncio non legge niente: manda l'annuncio con il controller delle novità, e finché c'è lo tiene vivo.

- **Annuncio:**
  - campo di testo su più righe, da 1 a 500 caratteri, con il contatore (§14). Il testo si accorcia ai lati prima dell'invio, come fa il plugin;
  - **"Invia a tutti"**, attivo solo con del testo (non fatto di soli spazi), chiede conferma: "L'annuncio arriva nella cassetta di tutti gli utenti attivi." Pulsanti "Annulla" e "Invia";
  - esito: "Annuncio inviato a {n} persone" ("a 1 persona" se una sola), e il campo si svuota; con 400: "Testo non valido", e il testo resta. Un altro errore diventa un avviso (§12).
- **Novità:**
  - interruttore **"Avvisa delle novità"** (`setNotifyNewTitles`). Durante la scrittura è disattivato, e resta sul valore scelto finché la rilettura non è finita: non torna indietro per un attimo. Se la scrittura fallisce torna com'era e compare l'errore;
  - testo "{n} titoli in attesa del prossimo riepilogo", oppure "Nessun titolo in attesa", oppure, con l'interruttore spento, "Le novità non vengono raccolte";
  - **"Invia ora"**, attivo solo con l'interruttore acceso e almeno un titolo in attesa. Non chiede conferma (§14). Esito: "Inviati {titles} titoli a {recipients} persone". Sono due testi, uno per ogni plurale ("Inviati 3 titoli" e "a 12 persone"): con un titolo e una persona si legge "Inviato 1 titolo a 1 persona".
- **Seerr** (solo se `seerrStatus()` non è `null`: con un plugin più vecchio la card non c'è):
  - **configurato**:
    - "Ultimo evento dal webhook: {ora} · {tipo}", oppure "Nessun evento ricevuto". Il tipo è "Richiesta in attesa" (`MEDIA_PENDING`), "Richiesta disponibile" (`MEDIA_AVAILABLE`) o "Messaggio di prova" (`TEST_NOTIFICATION`, quello del pulsante di prova di Seerr); un altro tipo si scrive com'è, e un evento senza tipo "—";
    - **"Prova collegamento"**: accanto al pulsante compare "Collegato a Seerr {versione}" ("Collegato a Seerr", se la versione manca), oppure l'errore in rosso: "Seerr non è configurato", "Seerr ha rifiutato la chiave", "Seerr non risponde" (anche per un errore sconosciuto);
  - **non configurato**: "Non configurato: si imposta dalla pagina del plugin nella Dashboard web."

## 10. Rilettura periodica

`AdminPoller` è un piccolo helper. Lo usano i controller delle schede e della striscia, che estendono `AdminTabController` (Sessioni, Manutenzione, i due di WonderFlix, la striscia). Il Registro no: non rilegge da solo (§9.5), ma ricomincia dalla prima pagina dopo un riavvio.

- prende una funzione di lettura e l'intervallo; l'intervallo può cambiare (Manutenzione: 2 s o 15 s). Un intervallo nuovo vale da subito, ma non rimanda la prima lettura;
- **mai due letture insieme:** l'intervallo parte dalla **fine** della lettura precedente. Una lettura chiesta mentre un'altra è in corso (dopo un'azione, "Riprova", dopo il riavvio) ne fa partire una sola, appena la prima finisce;
- si **ferma** nei casi qui sotto, e quando riparte legge subito:
  - quando la finestra è nascosta, per esempio ridotta a icona. `adminForegroundProvider` ascolta un `AppLifecycleListener` (`onHide`/`onShow`) e parte dallo stato vero della finestra, anche se la pagina si apre quando è già nascosta;
  - quando la pagina è coperta da un'altra rotta (per esempio una pagina titolo o il player): Riverpod mette in pausa gli ascoltatori del controller, e `AdminTabController` ferma la rilettura (`onCancel`/`onResume`);
  - quando il controller si chiude (`autoDispose`);
- **dopo un riavvio** tutti i controller rileggono subito, tramite `adminEpochProvider`: un contatore che il riavvio fa crescere al ritorno di Jellyfin;
- **lettura fallita:** restano i dati di prima e lo stato segna l'ora dell'ultima lettura riuscita. La scheda mostra la riga "Dati non aggiornati · ultimo aggiornamento {ora}", e i tentativi continuano al ritmo normale. Un 403 fa anche rileggere l'utente (§12);
- **azioni:** `act()` di `AdminTabController` esegue l'azione di una scheda (Avvia, Scansiona, Invia…) e rilegge la scheda:
  - se l'azione riesce, `act()` finisce **dopo** la rilettura: i pulsanti che aspettano l'azione non si riattivano, e l'interruttore delle novità non torna indietro, su dati vecchi;
  - se fallisce, l'errore arriva subito a chi chiama, che lo mostra (§12), e la scheda si rilegge senza farlo aspettare. Un 403 fa anche rileggere l'utente;
  - con la pagina chiusa nel frattempo non si rilegge niente;
- i timer e l'ora (`clock`) si prestano al tempo finto delle prove (`fake_async`).

## 11. Testi nuovi (ARB, it + en)

`app_it.arb` è il modello, poi `app_en.arb`. I testi principali, in italiano:

| Dove | Testi |
|---|---|
| Menu e pagina | "Amministrazione", "Sessioni", "Manutenzione", "Registro", "WonderFlix" |
| Striscia | "Jellyfin {version}", "Jellyfin {version} · {os}", "Riavvia", "Riavvio necessario", "Jellyfin va riavviato per finire un'installazione o un aggiornamento", "Riavvio in corso…", "Jellyfin è tornato", "Jellyfin non risponde ancora", "Ricontrolla", "Riavvio non riuscito" |
| Conferma | "Riavviare Jellyfin?", "{n} persone stanno guardando:" (plurale), "Il riavvio interrompe la visione e i watch party.", "Nessuno sta guardando.", "Non so chi sta guardando.", "Annulla", "Riavvia" |
| Sessioni | "In riproduzione", "Collegati", "Watch party", "Diretta", "Remux", "Transcodifica", "Software", i motivi (l'elenco è in §9.3, fino a "traccia sconosciuta"), "attivo {time}", gli stati dei party ("In riproduzione", "In pausa", "In attesa", "Fermo"), i tre vuoti ("Nessuno sta guardando", "Nessuno collegato", "Nessun watch party in corso") |
| Manutenzione | "Librerie", "Scansiona tutte", "Scansiona", "Attività pianificate", "Avvia", "Ferma", "Arresto…", "Ultima: {time}", "Completata in {duration}", "Non riuscita", "Annullata", "Interrotta", "Mai eseguita", le durate ("{count} s", "{count} min", "{hours} h {minutes} min") |
| Registro | "Tutto", "Utenti", "Sistema", "Aggiorna", "Apri il titolo", "Nessuna voce", "Non ci sono altre voci" |
| WonderFlix | "Annuncio", "Invia a tutti", "L'annuncio arriva nella cassetta di tutti gli utenti attivi.", "Invia" (il pulsante della conferma), "Annuncio inviato a {n} persone" (plurale), "Testo non valido", "Novità", "Avvisa delle novità", "{n} titoli in attesa del prossimo riepilogo" (plurale), "Nessun titolo in attesa", "Le novità non vengono raccolte", "Invia ora", i due pezzi di "Inviati {titles} titoli a {recipients} persone" (due testi con un plurale ciascuno: "Inviati {n} titoli" e "a {n} persone"), "Seerr", "Ultimo evento dal webhook: {time} · {type}", "Nessun evento ricevuto", i tipi dell'evento ("Richiesta in attesa", "Richiesta disponibile", "Messaggio di prova"), "Prova collegamento", "Collegato a Seerr {version}", "Collegato a Seerr", gli errori di Seerr ("Seerr non è configurato", "Seerr ha rifiutato la chiave", "Seerr non risponde"), "Non configurato: si imposta dalla pagina del plugin nella Dashboard web." |
| Comuni | "Dati non aggiornati · ultimo aggiornamento {time}", "Non sei più amministratore" |

Il test dei testi di ogni piano (`test/app/l10n_plan16a_test.dart` per il 16a, `test/app/l10n_plan16b_test.dart` per il 16b) controlla che le chiavi ci siano in entrambe le lingue.

## 12. Errori e casi limite

- **401:** il flusso di oggi (`onUnauthorized`, uscita dall'account).
- **Uscita dall'account, o 401, con la pagina aperta:** nessun avviso "Non sei più amministratore" e nessun rinvio a `/home`. Senza sessione non si sono persi dei permessi: il flusso normale porta al Login.
- **Non più admin:**
  - un 403 **non** è un segnale sicuro. Le letture della pagina (`/Sessions`, `/SyncPlay/List`, `/System/Info`) non chiedono di essere admin, e non lo danno a chi ha perso i permessi. Solo `/System/Restart` lo chiede;
  - quindi l'app rilegge `/Users/Me` e aggiorna la sessione: all'apertura della pagina, ogni 60 s insieme alla striscia (§9.2), e dopo un 403 di una lettura, di un'azione o del riavvio. Più richieste insieme fanno una sola lettura, e la sessione cambia solo se l'utente è cambiato;
  - se l'utente non è più admin, compare l'avviso "Non sei più amministratore", la voce del menu sparisce e la pagina torna a `/home`;
  - se lo è ancora, l'errore resta nella scheda (per il riavvio, "Riavvio non riuscito").
- **Primo caricamento fallito:** stato d'errore della scheda con "Riprova".
- **Rilettura fallita:** §10.
- **Azione fallita** (Avvia, Ferma, Scansiona, Invia, interruttore): un avviso con l'errore, e lo stato torna com'era. La scheda si rilegge subito, e un 403 fa anche rileggere l'utente (§10).
- **Attività già avviata o già ferma da un altro admin, o dalla Dashboard web:** Jellyfin risponde comunque o con un errore. Si legge di nuovo l'elenco, che mostra lo stato vero.
- **Due admin che cambiano l'interruttore delle novità, oppure l'app e la pagina web insieme:** vince l'ultima scrittura. Va bene così.
- **Configurazione del plugin che non sembra quella vera** (senza `NotifyNewTitles` booleano o senza `SeerrApiKey`, o un corpo che non è un oggetto): l'interruttore non scrive niente e dà un errore. Una scrittura parziale cancellerebbe indirizzo, chiave e segreto di Seerr (§8.3).
- **Risposte del plugin senza i loro campi** (novità, "Invia ora", annuncio, stato e prova di Seerr): sono errori, non zeri o "spento" inventati (§8.3).
- **Libreria in coda dietro un'altra** (`RefreshStatus` "Queued"): vale come in scansione, con la barra vuota e senza "Scansiona" (§8.2).
- **Senza l'attività "Scansione della libreria":** "Scansiona tutte" è disattivato (§9.4).
- **Plugin assente o senza `inbox`:** la scheda WonderFlix non c'è, e `?tab=wonderflix` mostra Sessioni (§7).
- **Plugin dalla 1.2.0 alla 1.3.x:** la card Seerr non c'è (§9.6).
- **Riavvio con l'admin dentro un watch party:** il party cade come per tutti. Al ritorno il WebSocket si ricollega da solo.
- **Server lento a tornare** (scansioni all'avvio): l'attesa arriva fino a 3 minuti, poi "Ricontrolla" (§9.2).
- **Sessione senza `NowPlayingItem` ma con `TranscodingInfo`:** finisce in "Collegati".
- **Valori sconosciuti** (nuovi tipi, stati, motivi, metodi): si mostrano con il valore originale, oppure come "sconosciuto" dove serve un'icona. Un'attività con uno stato sconosciuto vale come ferma. Non fanno fallire la lettura.
- **Elenco attività molto lungo:** un solo elenco a scorrimento con i gruppi, senza cartelle chiuse.
- **App aperta da un utente che diventa admin durante l'uso:** la voce compare alla prossima lettura di `/Users/Me` (al riavvio dell'app o dopo un nuovo accesso).

## 13. Test

- **Modelli:** si leggono i JSON di `/Sessions` (con e senza riproduzione, con transcodifica), `/SyncPlay/List`, `/System/Info`, `/Library/VirtualFolders`, `/ScheduledTasks`, `/System/ActivityLog/Entries` e della configurazione del plugin.
  - `/System/Info` viene dal server vero. Le sessioni e i watch party seguono invece lo schema OpenAPI 10.11.9 (`docs/reference/jellyfin-openapi-10.11.9.json`): quando si sono presi i campioni nessuno stava guardando, e `/SyncPlay/List` con una chiave API risponde 400.
  - Gli altri JSON vanno presi dal server all'inizio del piano, senza token né indirizzi IP.
  - Si provano anche campi mancanti e valori sconosciuti: una libreria in coda ("Queued"), un'attività con uno stato sconosciuto, un `userId` di soli zeri.
  - Le letture tolleranti (`json_fields.dart`) hanno le loro prove.
- **`JellyfinUser.isAdministrator`:** vero, falso, mancante.
- **`AdminApi` e `PluginAdminApi`** con `FakeAdapter`:
  - percorsi, query e corpi;
  - `isServerUp()`: su solo con `StartupWizardCompleted` a `true`; giù con il campo `false` o mancante, con un corpo che non è un oggetto e con ogni errore;
  - il livello del registro per 502/503/504 (info) e per un 500 (avviso), sulle letture, sul `POST` del riavvio e sulla rilettura dell'utente;
  - lettura delle risposte e mappatura degli errori;
  - `seerrStatus()` con 404 → `null`;
  - le risposte del plugin senza i loro campi obbligatori sono errori, e zero è un valore vero;
  - `setNotifyNewTitles`: le chiavi sconosciute passano intatte e cambia solo `NotifyNewTitles`; con una configurazione senza `NotifyNewTitles` booleano o senza `SeerrApiKey`, con un corpo che non è un oggetto o con una lettura fallita non si scrive niente; se la scrittura fallisce, chiave e segreto non vanno nel registro dell'app;
  - `scanLibrary` con i parametri della Dashboard web, `activity` con indice e filtro.
- **`AdminPoller`** con tempo finto: intervallo dalla fine della lettura, cambio di intervallo, una lettura chiesta durante un'altra, pausa e ripresa, dati vecchi tenuti dopo un errore.
- **`AdminTabController`:** pausa con la finestra nascosta (anche all'apertura) e con la pagina coperta, rilettura dopo il riavvio, rilettura dell'utente dopo un 403.
  - **`act()`:** esegue l'azione e poi rilegge, e il risultato arriva solo dopo la rilettura; con un errore, questo arriva subito a chi chiama, la scheda si rilegge e un 403 fa rileggere l'utente; con la pagina chiusa durante l'azione non si rilegge niente.
- **`RestartController`** con tempo finto:
  - giù → su;
  - nessuna caduta in 60 s;
  - timeout di 3 minuti e "Ricontrolla";
  - errore di rete e 502/503/504 sul `POST` contati come riavvio partito;
  - 401 (nessun avviso) e 403 (l'utente si rilegge);
  - un secondo riavvio durante l'attesa;
  - un errore inatteso, che va nel registro, e un errore dell'API, che non ci va.
- **`SessionsController`:** ordine stabile (stesso utente su due dispositivi, in qualunque ordine arrivino), watch party che non si leggono (sessioni nuove e party di prima, senza errore) e sessioni che non si leggono (errore della scheda).
- **Controller delle schede:**
  - Manutenzione: ritmo (2 s con qualcosa in corso, 15 s da fermo), attività per categoria e nome, "Scansiona tutte" che avvia l'attività della scansione e non `/Library/Refresh` (senza l'attività dà un errore), lettura subito dopo un'azione, 403 su un'azione, un errore di una delle due letture è un errore della scheda;
  - Registro: pagine da 50 fino alla fine, filtri (anche cambiati mentre arriva una pagina), "Aggiorna" e il ritorno di Jellyfin dalla prima pagina, voci arrivate in cima senza doppioni, "Riprova" che ripete lo stesso caricamento (anche dopo un "Aggiorna" fallito), 403;
  - WonderFlix: le azioni chiamano il plugin e rileggono, le due card hanno errori separati, un plugin vecchio non ha la card Seerr, 403 su un'azione.
- **Widget:**
  - voce del menu solo per gli admin, e rinvio dei non admin a `/home`, con l'avviso solo se si perdono i permessi (non con l'uscita dall'account);
  - striscia: l'utente si rilegge all'apertura e a ogni lettura;
  - scheda dall'indirizzo;
  - scheda WonderFlix solo con `inbox`: senza, `?tab=wonderflix` mostra Sessioni; con le funzioni non ancora note la pagina aspetta, senza passare da Sessioni, e poi mostra WonderFlix o Sessioni; le altre schede si vedono subito;
  - testi della conferma di riavvio con zero, una e più persone, e con la lettura fallita;
  - etichette Diretta, Remux (anche il caso `Transcode` con video e audio diretti) e Transcodifica, con i motivi;
  - librerie (barra durante la scansione, "Scansiona" spento) e "Scansiona tutte" (attivo con l'attività ferma; spento senza l'attività, in corso e in arresto; lo stato accanto, e il pulsante sul bordo destro);
  - stati delle attività (ferma, in corso, in arresto, non riuscita con il messaggio d'errore, mai eseguita), Avvia e Ferma, un avviso se l'azione è rifiutata;
  - pulsanti delle azioni: disattivati mentre l'azione va, un solo avvio con due pressioni di fila, un errore in un avviso, niente errori se il pulsante sparisce durante l'azione;
  - righe del registro (gravità, apertura di `overview`, link al titolo), filtri e "Aggiorna", la vista che torna in cima con "Aggiorna" e dopo un riavvio, la pagina dopo allo scorrimento, l'errore con "Riprova" (della prima pagina e in fondo all'elenco);
  - card WonderFlix (annuncio con conferma, "Annulla", testo rifiutato, solo spazi; contatore; interruttore e scrittura fallita; Invia ora attivo e no; Seerr configurato, non configurato, senza eventi o assente; una card che non carica non ferma le altre; la card dell'annuncio che tiene vivo il suo controller);
  - riga "Dati non aggiornati" (anche nella card Seerr).
- Il test dei testi del piano (§11).
- **A mano, sul server vero e con l'utente:**
  - una riproduzione vera vista da Sessioni, possibilmente transcodificata, e un watch party;
  - scansione di una libreria e, se l'utente vuole, "Scansiona tutte" (scansiona tutte le librerie);
  - avvio e arresto di un'attività;
  - registro con i filtri;
  - "Prova collegamento" di Seerr;
  - interruttore delle novità, controllato poi nella pagina web del plugin;
  - riavvio **con nessuno che guarda**;
  - annuncio e "Invia ora": arrivano davvero a tutti, quindi si fanno solo se l'utente vuole.

## 14. Rischi e punti da verificare

- **Il riavvio da API su Ultra.cc:** si prova a mano con nessuno che guarda. Se s6 non rilancia Jellyfin, la conferma deve dirlo e la funzione si toglie.
- **`/SyncPlay/List` per l'admin:** si verifica che mostri anche i party privati degli altri (il plugin non filtra quell'elenco).
- **Sessioni senza utente:** si verifica che Seerr e jfa-go spariscano davvero con il filtro su `UserId`.
- **Ciclo di vita della finestra su Windows:** si verifica che la riduzione a icona dia `hidden`/`paused` a `AppLifecycleListener`. Altrimenti il controllo usa `window_manager`.

**Limiti noti** (si accettano così):
- **Il contatore dell'annuncio conta i caratteri** (i grafemi, come il campo di testo di Flutter), mentre il plugin conta i punti di codice. Un testo pieno di emoji, sotto i 500 caratteri, può superare i 500 punti di codice e avere "Testo non valido".
- **Le ore relative del Registro** ("5 min fa") non si aggiornano da sole: il registro non rilegge (§9.5). Si aggiornano con "Aggiorna".
- **"Invia ora" non chiede conferma:** arriva davvero a tutti, ma il pulsante è attivo solo con titoli in attesa.
- **Una scheda WonderFlix aperta mentre le funzioni del plugin restano non note** continua a caricare finché `Info` non risponde. Si riprova ogni 30 s (§7).

## 15. Piano e release

- **Due piani**, perché uno solo risultava troppo lungo:
  - **16a (fatto)**, `docs/superpowers/plans/2026-10-06-wonderflix-16a-admin-sessioni.md`: accesso, API (`AdminApi` con `sessions`, `partyGroups`, `serverInfo`, `isServerUp`, `restart`), striscia, riavvio, Sessioni, allineamento della spec. La pagina ha una sola scheda;
  - **16b (fatto)**, `docs/superpowers/plans/2026-10-06-wonderflix-16b-manutenzione-registro-wonderflix-release.md`: Manutenzione, Registro, WonderFlix, allineamento della spec. Resta la release.
- **Release:** app **0.10.0 non obbligatoria**, con le note in italiano nella bozza. Il plugin non cambia. **Ancora da fare**, dopo la prova a mano con l'utente.
- **Alla fine:** in `docs/IDEE.md` l'idea 1 passa tra le fatte.
