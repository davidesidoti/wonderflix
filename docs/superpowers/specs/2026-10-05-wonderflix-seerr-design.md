# WonderFlix — Spec I: richieste con Seerr

- **Data:** 2026-10-05
- **Stato:** approvato; piano 15a realizzato (`docs/superpowers/plans/2026-10-05-wonderflix-15a-richieste-seerr.md`), piano 15b realizzato (`docs/superpowers/plans/2026-10-05-wonderflix-15b-richieste-approvazioni-release.md`)
- **Ambito:** Spec I. Realizza l'idea 2 di `docs/IDEE.md` ("Integrazione di Seerr"). Si appoggia alla Spec F (disponibilità del plugin, `Features`: `2026-10-03-wonderflix-amici-party-privati-design.md`) e alla Spec G (cassetta delle notifiche: `2026-10-03-wonderflix-notifiche-design.md`).

## 1. Obiettivo

Oggi gli amici chiedono i titoli che mancano dal sito di Seerr, e l'admin li approva da lì. Con la Spec I si fa tutto dentro WonderFlix:

- nella **ricerca**, i film e le serie che non ci sono compaiono in una sezione "Da richiedere";
- una **scheda** del titolo da richiedere, con **Richiedi** e, per le serie, la scelta delle **stagioni**;
- **"Richiedi stagioni"** sulle serie della libreria a cui mancano delle stagioni;
- una pagina **"Richieste"** con lo stato di ogni richiesta;
- per l'admin, **approvare** (con la scelta di server, profilo e cartella) e **rifiutare** dall'app;
- nella **cassetta delle notifiche**: "Ora disponibile" a chi ha chiesto il titolo, "Nuova richiesta" all'admin.

Gli amici non fanno nessun nuovo accesso: entra il plugin per loro.

## 2. Situazione di partenza

- **App 0.8.1:**
  - La ricerca (`lib/features/search/`) cerca film, serie e persone nella libreria, con 300 ms di attesa e almeno 2 lettere. I risultati sono sezioni di `PosterCard`, che vuole un `JellyfinItem`.
  - La scheda (`lib/features/detail/`) ha la fila dei pulsanti in `detail_header.dart`: Riproduci, Ricomincia, Guarda insieme, Trailer, cuore e visto. I trailer remoti (YouTube) si aprono nel browser.
  - `JellyfinItem` **non** legge `ProviderIds`: l'app non conosce l'id TMDB dei titoli.
  - La barra in alto ha Home, Film, Serie, La mia lista e Cerca; a destra watch party, amici e cassetta.
  - L'app conserva solo `userId` e `accessToken`, **non la password** (`lib/core/storage/session_store.dart`).
  - `SocialApi` chiama il plugin con lo stesso `JellyfinHttp`. `SocialAvailability` legge `Info.Features`.
  - La cassetta (`lib/features/inbox/`) ignora i tipi che non conosce e ricalcola da sola i non letti.
- **Plugin 1.3.0:**
  - Controller sotto `/WonderFlixWatchParty`. Non risponde mai 404, perché l'app leggerebbe "plugin assente".
  - Salva su file JSON (`friends.json`, `inbox.json`). La configurazione ha solo `NotifyNewTitles`.
  - **Non fa nessuna chiamata HTTP verso l'esterno** e non ha endpoint senza accesso.
  - La cassetta ha i tipi `Invite`, `Announcement` e `NewTitles`. Avvisa le app con `InboxChanged` sul WebSocket di Jellyfin, poi l'app rilegge `GET Inbox`.
  - `Features`: `["friends", "parties", "inbox", "queue"]`.

## 3. Il server

Fatti raccolti sul server il 2026-10-05, in sola lettura.

- **Seerr 3.4.1**, in un container Docker gestito da Ultra.cc. Configurazione in `~/.apps/seerr/settings.json`, database in `~/.apps/seerr/db/db.sqlite3`.
  - Indirizzo pubblico: `https://hashvps.proton.usbx.me/seerr`, tramite nginx.
  - **Jellyfin gira in un altro container:** da lì `127.0.0.1` non porta a Seerr. Il plugin userà l'indirizzo pubblico, come già fa Seerr verso Jellyfin (da verificare con "Prova collegamento", §7.1).
- **Impostazioni:**
  - Accesso con le credenziali Jellyfin acceso, e gli utenti nuovi si creano al primo accesso.
  - Permessi predefiniti: solo richiedere (`REQUEST`), quindi ogni richiesta va approvata. Le quote sono illimitate.
  - Due Radarr ("Radarr", predefinito, e "Radarr Anime") e un Sonarr con profilo e cartella per gli anime.
  - Il webhook è spento. Gli avvisi di oggi arrivano su Telegram.
- **Utenti:** 28, tutti di tipo Jellyfin, con 413 richieste in totale e nessuna in attesa.
  - Il n.3 "davide.sidoti" (admin) è quello che approva.
  - Il n.1, il proprietario, punta a un id Jellyfin che non esiste più. Altri 7 utenti sono legati a utenti Jellyfin cancellati.
  - Due utenti Jellyfin non hanno ancora un account Seerr.
- **Approvazioni:** solo 4 richieste su 413 hanno server, profilo o cartella cambiati a mano (sulla cartella degli anime).
- **API** (`/api/v1`):
  - **Chiave e utente.** Con la chiave API (`X-API-Key`) si agisce come l'utente n.1, o come l'utente indicato in `X-API-User`, senza altri controlli. Seerr applica poi i permessi di quell'utente.
  - **Abbinamento e import.**
    - `GET /user` dà `jellyfinUserId` per ogni utente.
    - `POST /user/import-from-jellyfin` crea gli account (serve `MANAGE_USERS`).
    - `POST /auth/jellyfin` vuole la password: non serve, perché il plugin agisce con la chiave.
  - **Ricerca e schede.**
    - `GET /search?query=&page=&language=` dà film, serie e persone mescolati, 20 per pagina, con `mediaInfo` facoltativo: `status`, `jellyfinMediaId`, `seasons[]`, `requests[]`, `downloadStatus[]`.
    - `GET /movie/{tmdbId}` e `GET /tv/{tmdbId}` danno i dettagli TMDB e `mediaInfo`.
  - **Richieste.**
    - `POST /request` vuole `{mediaType, mediaId, seasons}`. Risponde 201, oppure 403 (niente permesso, quota, titolo bloccato), 409 (già chiesto) o 202 (nessuna stagione da chiedere).
    - `GET /request?take=&skip=&filter=&sort=&requestedBy=` dà l'elenco. **Le richieste non contengono il titolo**, solo `media.tmdbId`.
  - **Approvazione** (servono `MANAGE_REQUESTS`).
    - `PUT /request/{id}` cambia server, profilo e cartella.
    - `POST /request/{id}/approve` e `/decline` approvano e rifiutano. **Il rifiuto non ha un motivo.**
    - `GET /service/radarr|sonarr` e `/service/radarr|sonarr/{id}` danno server, profili e cartelle.
  - **Codici di stato.**
    - Richiesta: 1 in attesa, 2 approvata, 3 rifiutata, 4 non riuscita, 5 completata.
    - Titolo: 1 sconosciuto, 2 in attesa, 3 in lavorazione, 4 in parte disponibile, 5 disponibile, 6 bloccato, 7 eliminato.
  - **Permessi** (bit): `ADMIN` 2, `MANAGE_USERS` 8, `MANAGE_REQUESTS` 16, `REQUEST` 32.
- **Webhook di Seerr:**
  - È **uno solo per tutto il server**: un indirizzo, una maschera di tipi (`MEDIA_PENDING` 2, `MEDIA_AVAILABLE` 8, …) e un modello JSON con variabili `{{…}}`. Tra le variabili ci sono `notification_type`, `subject`, `request_id`, `media_type`, `media_tmdbid`, `media_jellyfinMediaId`, `requestedBy_jellyfinUserId`, `requestedBy_username` ed `extra`.
  - Come autenticazione può mandare solo un header `Authorization`, che Jellyfin interpreta per sé: il segreto va quindi **nel corpo**.
- **Problemi trovati, fuori da questa spec:**
  - La sincronizzazione "aggiunti di recente" di Seerr fallisce ogni 5 minuti, perché usa l'id Jellyfin dell'utente n.1. Un titolo risulta disponibile solo dopo la scansione completa della notte, e così anche l'avviso "Ora disponibile" (§11).
  - La porta 42511 di Seerr risponde in HTTP sull'IP pubblico.
  - `preventSearch` è acceso sul Radarr e sul Sonarr predefiniti.

## 4. Decisioni

| Tema | Decisione |
|---|---|
| Funzioni | ricerca e richiesta, pagina Richieste, approvare dall'app; **niente** sezioni "Scopri" |
| Architettura | il **plugin fa da tramite** verso Seerr con chiave API e `X-API-User`; l'app non vede mai la chiave |
| Avvisi | webhook di Seerr → plugin → cassetta: "Ora disponibile" (a chi ha chiesto il titolo) e "Nuova richiesta" (a chi può approvare); **niente** avvisi per approvata e rifiutata |
| Account | chi non ha un account Seerr viene **importato da Jellyfin alla prima richiesta**, con i permessi predefiniti |
| Serie | **stagioni a scelta**, con "Tutte"; vale anche per le serie della libreria che ci sono solo in parte |
| Ricerca | sezione **"Da richiedere" in fondo**, sotto i risultati di oggi |
| Scheda | una **pagina** come le schede di oggi |
| Pagina Richieste | voce **"Richieste" nella barra in alto**; schede "Le mie" e, per chi può approvare, "Da approvare" e "Tutte" |
| Approva | finestra con **server, profilo e cartella**; "Predefinito" lascia decidere Seerr |
| Rifiuta | con conferma, senza motivo |
| Release | plugin **1.4.0**, poi app **0.9.0 non obbligatoria** |

## 5. Perimetro

### Incluso

- **Plugin 1.4.0:** configurazione di Seerr, client Seerr, endpoint delle richieste, webhook, due tipi nuovi nella cassetta, `requests` in `Features`.
- **App 0.9.0:** modelli e API, sezione "Da richiedere", scheda da richiedere, scelta delle stagioni, "Richiedi stagioni" nella scheda delle serie, pagina Richieste, finestra Approva, righe nuove nella cassetta.

### Escluso

- **Sezioni "Scopri"** (di tendenza, popolari, in arrivo).
- **Richieste in 4K**: sul server non c'è un Radarr o Sonarr 4K.
- **Annullare o modificare** le proprie richieste: si fa dal sito di Seerr.
- **Motivo del rifiuto**: Seerr non lo ha.
- **Avvisi "Approvata" e "Rifiutata"**: lo stato si vede nella pagina Richieste.
- **Pagine successive** della ricerca di Seerr: si mostra solo la prima (fino a 20 titoli).
- **Persone** nei risultati di Seerr.
- **Segnalazioni** (issues) e **watchlist** di Seerr.
- **Gestire permessi, quote e utenti di Seerr** dall'app: rientra nell'idea della dashboard admin.
- **Ricollegare l'utente Seerr n.1** e gli altri problemi del server (§3): sono un compito a parte, con backup e l'ok dell'utente.

## 6. Architettura

```
Plugin 1.4.0
  Configuration/PluginConfiguration.cs  + SeerrUrl, SeerrApiKey, SeerrWebhookSecret
  Configuration/configPage.html         + sezione "Seerr" (campi, segreto, modello del webhook, Prova collegamento)
  Seerr/ISeerrClient.cs, SeerrClient.cs HTTP verso Seerr (IHttpClientFactory, 10 s)
  Seerr/SeerrJson.cs                    forme JSON di Seerr usate dal client
  Seerr/SeerrUserMap.cs                 utente Jellyfin → utente Seerr, cache, import
  Seerr/SeerrTitleCache.cs              titoli e locandine per tmdbId e lingua (1 h)
  Hub/RequestsService.cs                ricerca, schede, richieste, elenchi, approvazioni, stati
  Hub/RequestWebhookHandler.cs          webhook → avvisi nella cassetta
  Hub/InboxService.cs                   + AddRequestAvailableAsync, AddRequestPendingAsync
  Api/RequestsController.cs             /WonderFlixWatchParty/Requests/...
  Api/RequestsWebhookController.cs      /WonderFlixWatchParty/Requests/Webhook (senza accesso)
  Protocol/RequestsDtos.cs              oggetti per l'app
  Protocol/InboxDtos.cs                 + RequestAvailable, RequestPending
  Protocol/WatchPartyProtocol.cs        Features + "requests" (solo con Seerr configurato)

App 0.9.0
  lib/core/jellyfin/item_models.dart    JellyfinItem.tmdbId (ProviderIds.Tmdb)
  lib/core/requests/
    requests_api.dart                   RequestsApi sul plugin
    requests_models.dart                RequestsMe, RequestableTitle, TitleDetails, SeasonInfo, MediaRequest, ApproveOptions
    tmdb_images.dart                    URL delle immagini TMDB
  lib/core/social/inbox_models.dart     + RequestAvailableEntry, RequestPendingEntry
  lib/features/requests/
    requests_providers.dart             disponibilità, Me, RequestsApi
    requestables_controller.dart        sezione "Da richiedere" della ricerca
    requestable_poster_card.dart        card con immagine TMDB ed etichetta
    tmdb_title_screen.dart              scheda da richiedere
    season_picker.dart                  elenco delle stagioni con le caselle
    request_seasons.dart                "Richiedi stagioni" per le serie della libreria (finestra e pulsante)
    requests_list_controller.dart       elenchi della pagina Richieste (pagine, aggiornamento, ricarica, Approva e Rifiuta), conteggio "Da approvare"
    requests_screen.dart                pagina Richieste, schede, pagine
    request_row.dart                    riga di una richiesta
    pending_request_actions.dart        Rifiuta (a due tempi) e Approva nella riga
    approve_dialog.dart                 finestra Approva
    requests_navigation.dart            schede dell'indirizzo, openRequest e openRequests
    request_labels.dart                 etichette e colori degli stati
  lib/features/search/search_screen.dart     + sezione "Da richiedere"
  lib/features/detail/detail_header.dart     + "Richiedi stagioni"
  lib/features/inbox/inbox_panel.dart        + due righe
  lib/features/inbox/inbox_request_rows.dart testi e icone delle due righe
  lib/ui/wf_dialog.dart                      aspetto comune delle finestre (§9.5)
  lib/app/router.dart, app_shell.dart        + /requests, /tmdb/:type/:tmdbId, voce "Richieste"
```

L'app parla solo con il plugin; il plugin parla con Seerr. La chiave API e l'id Seerr degli utenti restano nel plugin.

## 7. Plugin 1.4.0

### 7.1 Configurazione

- `PluginConfiguration` riceve `SeerrUrl`, `SeerrApiKey` e `SeerrWebhookSecret`. L'XML è leggibile solo dagli admin, come oggi.
- Nella pagina del plugin c'è una nuova sezione **"Seerr"**:
  - campi per indirizzo e chiave API (la chiave è mascherata);
  - **"Prova collegamento"** (`POST Requests/Test`, solo admin) chiama `GET /status` e `GET /auth/me` con la chiave, e mostra "Collegato a Seerr 3.4.1" oppure l'errore: indirizzo irraggiungibile, chiave rifiutata o risposta inattesa;
  - il **segreto del webhook**, generato dal plugin al primo salvataggio, con "Rigenera";
  - le **istruzioni per il webhook**: l'indirizzo da incollare (`<indirizzo pubblico di Jellyfin>/WonderFlixWatchParty/Requests/Webhook`), i tipi da attivare ("Richiesta in attesa" e "Richiesta disponibile") e il modello JSON già completo del segreto, con un pulsante "Copia";
  - "Ultimo evento ricevuto" con data e tipo, per capire se il webhook arriva. La pagina lo legge da `GET Requests/Admin` (solo admin), che dice anche se Seerr è configurato (§7.3).
- **Modello JSON del webhook:**

  ```json
  {
    "secret": "<segreto>",
    "notification_type": "{{notification_type}}",
    "subject": "{{subject}}",
    "request_id": "{{request_id}}",
    "media_type": "{{media_type}}",
    "media_tmdbid": "{{media_tmdbid}}",
    "media_jellyfinMediaId": "{{media_jellyfinMediaId}}",
    "requestedBy_jellyfinUserId": "{{requestedBy_jellyfinUserId}}",
    "requestedBy_username": "{{requestedBy_username}}",
    "{{extra}}": []
  }
  ```

  `{{extra}}` non è una variabile di testo: con la chiave speciale `"{{extra}}": []` Seerr scrive nel corpo `"extra": [{name, value}]`, da cui il plugin legge le stagioni (§7.5).

- `Info.Features` aggiunge `requests` solo quando indirizzo e chiave ci sono. Lo stato del collegamento non conta: se Seerr è giù, l'app mostra l'errore (§11).

### 7.2 Client e abbinamento degli utenti

- `SeerrClient` usa `IHttpClientFactory`, con un'attesa massima di 10 s e `X-API-Key` su ogni chiamata.
  - **Chiamate di servizio** (elenco utenti, import, impostazioni, server Radarr/Sonarr) senza `X-API-User`: agiscono come l'utente n.1 (admin).
  - **Chiamate per conto di un utente** (richieste, elenchi, approvazioni) con `X-API-User`.
  - **Chiave al sicuro:** il client non segue i redirect (la chiave andrebbe a un altro indirizzo) e l'header `X-API-Key` non compare nei log del client HTTP.
  - **Risposte inattese:** un `null` esplicito dove Seerr dovrebbe mandare una lista conta come "Seerr non risponde" (`SeerrUnavailable`).
- **`SeerrUserMap`:**
  - Legge `GET /user?take=1000` e abbina per `jellyfinUserId`, senza badare a maiuscole e trattini. La cache dura 10 minuti e si svuota dopo un import. Uno svuotamento (`Invalidate`) non viene annullato da un caricamento già in corso: quel caricamento non rimette in cache i dati letti prima.
  - Più utenti con lo stesso id Jellyfin: vince l'id Seerr più basso.
  - **L'id dell'utente viene solo dall'accesso Jellyfin della chiamata** (`IAuthorizationContext`), mai da un campo mandato dall'app.
  - **Import:** se l'utente non ha un account, **alla prima `POST Requests`** il plugin chiama `POST /user/import-from-jellyfin` con il suo id, svuota la cache e riprova l'abbinamento. Se fallisce, risponde con il codice `AccountUnavailable`. Con due prime richieste insieme dello stesso utente l'import parte una volta sola (lo protegge un blocco a parte).
- **`SeerrTitleCache`:** titolo, anno e locandina per (`mediaType`, `tmdbId`, lingua), per un'ora, al massimo 2000 voci. Serve a completare gli elenchi delle richieste, che non hanno il titolo (§3).
  - Le ricerche dei titoli fanno al massimo 6 chiamate a Seerr alla volta.
  - Si ricorda per 5 minuti solo il titolo che Seerr non conosce (404), così non lo si richiede a ogni elenco. Gli altri errori (Seerr giù, chiave rifiutata) non si ricordano: alla riga successiva si riprova.

### 7.3 Endpoint

Tutti sotto `/WonderFlixWatchParty/Requests` e con `[Authorize]`, tranne il webhook. `language` è `it` o `en`, dalla lingua dell'app.

| Metodo e percorso | Cosa fa |
|---|---|
| `GET Me` | `{CanRequest, CanManage, HasAccount}`. Senza account, `CanRequest` viene dai permessi predefiniti di Seerr (`GET /settings/main`, in cache 10 min). `CanManage` = `ADMIN` o `MANAGE_REQUESTS`. |
| `GET Search?query=&language=` | prima pagina di `GET /search`, **solo film e serie**, senza i titoli bloccati: `[{MediaType, TmdbId, Title, Year, PosterPath, Status, JellyfinItemId}]` |
| `GET Movie/{tmdbId}?language=` | `{TmdbId, Title, Year, Overview, Genres, RuntimeMinutes, PosterPath, BackdropPath, TrailerUrl, Status, JellyfinItemId, RequestedByMe, Requested}` |
| `GET Tv/{tmdbId}?language=` | come sopra, più `Seasons: [{SeasonNumber, EpisodeCount, Status}]`, senza la stagione 0 |
| `POST Requests` | `{MediaType, TmdbId, Seasons?}` → la richiesta creata `{Id, Status}`; per conto dell'utente, con l'import se serve. Per le serie `Seasons` ha al massimo 100 stagioni |
| `GET Requests?filter=mine\|pending\|all&skip=&take=&language=` | `{Items: [MediaRequest], HasMore}`, ordinate dalla più recente; `take` al massimo 50 |
| `GET Services/{movie\|tv}` | solo con `CanManage`: `[{Id, Name, IsDefault, Profiles: [{Id, Name}], RootFolders: [Path], DefaultProfileId, DefaultRootFolder}]`, senza i server 4K. Un server di cui non si leggono i dettagli si salta |
| `POST Requests/{id}/Approve` | solo con `CanManage`: `{ServerId?, ProfileId?, RootFolder?}`. Senza campi approva e basta; con i campi prima `PUT /request/{id}` (per le serie con le stagioni della richiesta), poi l'approvazione |
| `POST Requests/{id}/Decline` | solo con `CanManage` |
| `GET Admin` | solo admin Jellyfin: se Seerr è configurato e data e tipo dell'ultimo evento del webhook ("Ultimo evento ricevuto", §7.1) |
| `POST Test` | solo admin Jellyfin (§7.1) |
| `POST Webhook` | `[AllowAnonymous]` (§7.5) |

- **`MediaRequest`:** `{Id, MediaType, TmdbId, Title, Year, PosterPath, Seasons: [int], RequestedBy: {Name, IsMe}, CreatedAt, Status, Progress?, JellyfinItemId?}`.
- Una riga con un `MediaType` che l'app non conosce non la fa fallire: l'app la salta (§8.1).
- **Filtri:**
  - `mine` usa `requestedBy` con l'id Seerr dell'utente;
  - `pending` e `all` richiedono `CanManage`;
  - senza account, `mine` dà un elenco vuoto.
- **Stato di un titolo** (`Status` in ricerca e schede, anche per stagione):
  - `None`: nessun `mediaInfo`, oppure stato sconosciuto o eliminato;
  - `Pending`: in attesa;
  - `Processing`: in lavorazione;
  - `Partial`: in parte disponibile;
  - `Available`: disponibile.
  - Per una stagione senza stato proprio, `Pending` o `Processing` si ricavano dalle richieste in corso che la contengono.
- **Stato di una richiesta** (`Status` in `MediaRequest`), nell'ordine:
  1. rifiutata → `Declined`;
  2. non riuscita → `Failed`;
  3. in attesa → `Pending`;
  4. completata → `Available`;
  5. approvata, con il titolo disponibile → `Available`;
  6. approvata, con un download in corso → `Downloading`, con `Progress` = 1 − `sizeLeft`/`size` del primo `downloadStatus`;
  7. approvata, con almeno una delle stagioni chieste già arrivata (nella richiesta la stagione è completata) → `Partial`;
  8. altrimenti approvata → `Approved`.

  Lo stato "in parte disponibile" della serie intera non conta: non dice se quello che è stato chiesto è arrivato. Per questo una serie con tutte le stagioni chieste arrivate è `Available` anche se la serie, nel suo insieme, è in parte.
- **Errori**, con il corpo `{Code}`. Mai 404.

  | Caso | Risposta |
  |---|---|
  | Seerr non configurato | 503 `NotConfigured` |
  | Seerr irraggiungibile, lento o con risposta inattesa | 502 `SeerrUnavailable` |
  | Chiave rifiutata | 502 `SeerrAuth` |
  | Permesso mancante, o chiamata senza utente Jellyfin (per esempio con una chiave API) | 403 `NoPermission` |
  | Quota | 403 `QuotaExceeded` |
  | Titolo bloccato | 403 `Blocklisted` |
  | Già chiesto | 409 `AlreadyRequested` |
  | Nessuna stagione da chiedere | 409 `NothingToRequest` (dal 202 di Seerr) |
  | Account non creato | 409 `AccountUnavailable` |
  | Parametri sbagliati | 400 |
  | Richiesta inesistente | 400 `UnknownRequest` |

### 7.4 Sicurezza

- Il plugin inoltra solo le operazioni della tabella, con percorsi costruiti da lui: niente passaggio libero di percorsi o query verso Seerr.
- `X-API-User` viene solo dall'abbinamento (§7.2). Le operazioni da admin le controlla due volte: il plugin con `CanManage`, poi Seerr con i permessi dell'utente.
- Nessuna risposta all'app contiene la chiave API, l'id Seerr o le email.

### 7.5 Webhook

- `POST Requests/Webhook`, senza accesso, corpo al massimo 64 KB.
- Se il corpo è malformato, troppo grande o non è JSON, risponde ASP.NET stesso (400, 413 o 415): il plugin risponde solo 401 o 200.
- **Segreto:** confrontato in tempo costante con `SeerrWebhookSecret`. Se manca o è sbagliato risponde 401 e scrive nel registro (al massimo una riga al minuto).
- **Tipi:**
  - `MEDIA_AVAILABLE` → `RequestAvailable` all'utente Jellyfin `requestedBy_jellyfinUserId`, solo se esiste ed è abilitato;
  - `MEDIA_PENDING` → `RequestPending` agli utenti Jellyfin il cui account Seerr ha `ADMIN` o `MANAGE_REQUESTS`, **escluso chi ha chiesto**;
  - `TEST_NOTIFICATION` → aggiorna solo "Ultimo evento ricevuto";
  - tutti gli altri → 200 senza effetti.
- Un evento senza `request_id` o con dati mancanti si scarta con una riga nel registro e risponde 200, così Seerr non riprova.
- **Titolo dell'avviso:** `subject` (per esempio "Dune (2021)"), tagliato a 200 caratteri. Il nome di chi ha chiesto si taglia a 100. Le stagioni, se ci sono, vengono da `extra` ("Requested Seasons").

### 7.6 Cassetta delle notifiche

- **Nuovi tipi in `InboxDtos`:**
  - `RequestAvailable` `{RequestId, MediaType, TmdbId, Title, Seasons?, ItemId?}`;
  - `RequestPending` `{RequestId, MediaType, TmdbId, Title, Seasons?, RequesterName}`.
- **Doppioni:** una voce dello stesso tipo e con lo stesso `RequestId` sostituisce quella di prima, e torna non letta.
- `NotifyAsync` manda `InboxChanged` come per gli altri tipi. Valgono le regole di oggi: 100 voci e pulizia dopo 30 giorni.
- Le app vecchie ignorano i due tipi (§2).

## 8. App: dati e comandi

### 8.1 Modelli e API

- `JellyfinItem.tmdbId`: si legge `ProviderIds.Tmdb`, se c'è, e va aggiunto ai `Fields` delle chiamate della scheda e della ricerca nella libreria (§8.3).
- `RequestsApi` (`lib/core/requests/requests_api.dart`) ha un metodo per ogni endpoint di §7.3, tranne `Test` e `Webhook`. Mappa i `{Code}` in `RequestsFailure` (enum), sul modello di `SocialFailure`. Per leggere il `{Code}` anche nelle risposte 403 e 5xx, `ForbiddenException` e `ServerErrorException` (`lib/core/jellyfin/api_exception.dart`) portano il `body` della risposta.
- Le righe con un `MediaType` sconosciuto (per esempio una persona) si saltano, nella ricerca e negli elenchi delle richieste: il resto della risposta si legge lo stesso.
- **Modelli:**
  - `RequestsMe`;
  - `RequestableTitle` (risultato della ricerca);
  - `TitleDetails` (film o serie, con `seasons`);
  - `SeasonInfo`;
  - `MediaRequest`;
  - `ServiceOption`, `ApproveChoice`.
- Gli stati sono enum: `TitleStatus { none, pending, processing, partial, available }` e `RequestStatus { pending, approved, downloading, partial, available, declined, failed }`.
- `tmdb_images.dart` costruisce gli indirizzi delle immagini: `https://image.tmdb.org/t/p/w342{posterPath}` per le locandine, `w1280` per gli sfondi.

### 8.2 Disponibilità

- `requestsAvailableProvider` è vero se `Info.Features` contiene `requests`.
- `requestsMeProvider` (`GET Me`) è `autoDispose`: si carica quando una pagina lo usa e la funzione è disponibile, e si rilegge ogni volta che una pagina lo usa di nuovo, non a ogni connessione al server.
- Senza `requests`, nell'app non cambia nulla: niente voce nella barra, niente sezione, niente pulsanti.
- Con `CanRequest` falso si vedono le sezioni e le schede, ma senza i pulsanti per chiedere.

### 8.3 Sezione "Da richiedere"

- `requestablesControllerProvider` segue il termine della ricerca di oggi, con la stessa attesa e lo stesso minimo di lettere, ma **è indipendente**: la ricerca nella libreria non aspetta Seerr.
- **Doppioni:** si tolgono i titoli con `JellyfinItemId` uguale all'id di un risultato della libreria (film o serie), e anche quelli con lo stesso id TMDB e lo stesso tipo (film con film, serie con serie) di un risultato. La ricerca nella libreria chiede i `ProviderIds`, perché Seerr può non conoscere l'id Jellyfin dei titoli recenti (§3).
- Restano in elenco:
  - i titoli `None`, `Pending`, `Processing` e `Partial`;
  - gli `Available` che la libreria non ha trovato (per esempio un titolo in un'altra lingua), con l'etichetta "Su WonderFlix": aprono la scheda della libreria.
- Le risposte vecchie, quelle di un termine nel frattempo cambiato, si scartano.
- La schermata della ricerca tiene vivo il controller anche quando la sezione è fuori dallo schermo (la lista la costruisce solo quando è vicina): senza, il controller perderebbe attesa, richiesta e titoli.
- Se la funzione diventa disponibile quando un termine è già scritto, la ricerca parte da sola, senza aspettare un altro tasto.

### 8.4 Richieste e approvazioni

- **`RequestTitleController`** (per scheda):
  - carica `Movie` o `Tv`;
  - tiene le stagioni scelte. All'apertura sono scelte tutte le stagioni `None`; `resetSelection` riporta la scelta a tutte le stagioni ancora da chiedere;
  - manda la richiesta e blocca il pulsante finché non arriva la risposta;
  - dopo la risposta, positiva o `AlreadyRequested`, ricarica la scheda, e il pulsante resta bloccato fino alla fine della ricarica;
  - lo usa anche "Richiedi stagioni" (§9.3), con la stessa chiave della scheda da richiedere: stagioni scelte, invio, blocco e avvisi sono gli stessi.
- **`RequestsListController`** (per filtro e lingua dell'app):
  - carica a pagine di 20;
  - carica all'apertura della pagina e, a **ogni** `InboxChanged`, **aggiorna le righe mostrate**, non solo per le voci `RequestAvailable` o `RequestPending`: l'evento non dice il tipo della voce, e un aggiornamento in più non costa niente. Ne arrivano anche quando si apre il pannello delle notifiche (le voci si segnano lette), quindi l'elenco non deve accorciarsi;
  - **aggiornare e ricaricare:**
    - l'aggiornamento rilegge in una sola chiamata le righe mostrate, fino a 50 (il massimo del plugin), e le mette al posto delle prime; le righe oltre restano, tolte quelle già nella pagina nuova e quelle appena approvate o rifiutate. "Ce ne sono altre" vale quello della pagina nuova se non resta nessuna riga oltre, altrimenti resta com'era;
    - se non riesce, l'elenco non cambia e non compare un errore: le righe si aggiornano al prossimo avviso (lo scorrimento carica solo le pagine dopo);
    - limite noto: con più di 50 righe caricate, ogni richiesta nuova in cima fa sparire la riga che era intorno alla cinquantesima, finché la pagina non si riapre;
    - senza righe (elenco vuoto o primo caricamento) è un ricaricamento;
    - il **ricaricamento** (primo caricamento, "Riprova" della pagina d'errore) riparte dalla prima pagina, di 20 righe;
  - **ricarica e pagine:**
    - le righe di prima restano finché non arrivano le nuove;
    - un caricamento già in corso non rimette una riga appena approvata o rifiutata;
    - i doppioni per id si scartano;
    - la pagina dopo parte dalle righe mostrate, senza contare quelle con un'azione in corso;
    - se le righe non riempiono la finestra, o dopo le azioni scendono sotto una pagina e sul server ce ne sono altre, la pagina dopo si carica da sola;
    - "Riprova" in fondo all'elenco ripete il tipo di caricamento fallito: da capo se era un ricaricamento, la pagina dopo se era una pagina;
  - **Approva e Rifiuta** chiamano gli endpoint e bloccano la riga (`busy`) finché la risposta non arriva, poi la tolgono dall'elenco. Se la chiamata non riesce la riga resta, e l'avviso è "Non riuscito, riprova". L'elenco resta vivo finché la risposta non arriva, anche se nel frattempo si cambia scheda: il conteggio si ricarica e "Tutte", se c'è, si aggiorna lo stesso, al suo posto (senza svuotarsi né perdere lo scroll).
- **Conteggio "Da approvare (n)":** `GET Requests?filter=pending&take=50`, cioè la prima pagina; se oltre ce ne sono altre, si mostra "50+". Si ricarica dopo Approva e Rifiuta e a ogni `InboxChanged`.

## 9. App: interfaccia

### 9.1 Ricerca

- Sotto i risultati di oggi (Film, Serie, Persone) c'è la sezione **"Da richiedere"**, con il sottotitolo "Non sono ancora su WonderFlix".
- Film e serie sono insieme, nell'ordine di Seerr, in un `Wrap` di `RequestablePosterCard` larghe 150 come le card di oggi.
- **Card:**
  - immagine TMDB, oppure il segnaposto di oggi;
  - titolo e anno sotto;
  - etichetta in alto a sinistra: "Film" o "Serie" per i titoli `None`, "Richiesto" (`Pending`), "In arrivo" (`Processing`), "In parte" (`Partial`), "Su WonderFlix" (`Available`).
  - Il clic apre la scheda da richiedere, o quella della libreria per "Su WonderFlix". Non c'è l'anteprima al passaggio del mouse delle card di oggi.
- **Stati della sezione:**
  - in caricamento: uno scheletro di una riga. Vale anche quando il termine cambia: mentre Seerr cerca, non restano mai i titoli del termine di prima;
  - errore: "Seerr non risponde" con Riprova;
  - nessun titolo: la sezione non compare;
  - se anche la libreria non trova nulla, il messaggio "Nessun risultato" resta sopra la sezione.

### 9.2 Scheda da richiedere (`/tmdb/:type/:tmdbId`)

- **Impaginazione** di `detail_header.dart`: sfondo TMDB sfumato, titolo in Bebas Neue, riga con anno · Film/Serie · generi · durata o numero di stagioni, trama. Lo sfondo scorre insieme all'intestazione.
- **Permessi:** la pagina aspetta `Me` (o il suo errore) prima di mostrare i dati, così Richiedi e le caselle delle stagioni non cambiano dopo il primo fotogramma.
- **Pulsanti:**
  - **Richiedi** (oro), se `CanRequest` e se c'è qualcosa da chiedere. Per le serie l'etichetta è "Richiedi" con tutte le stagioni scelte, e "Richiedi {n} stagioni" quando sono solo alcune.
  - Al suo posto, se il titolo è già chiesto o arrivato, un'etichetta di stato: "Richiesto da te", "Richiesto", "In arrivo", "In parte disponibile".
  - **Guarda**, se il titolo è `Available` o `Partial` e ha `JellyfinItemId`: apre la scheda della libreria.
  - **Trailer**, se c'è `TrailerUrl` (YouTube): si apre nel browser, come i trailer remoti di oggi.
- **Stagioni** (solo serie), con `SeasonPicker`:
  - righe "Stagione {n} · {count} episodi" con la casella e lo stato a destra ("Da richiedere", "In attesa", "In arrivo", "In parte", "Disponibile"), e "Tutte" in cima;
  - ogni riga è un solo punto di focus per la tastiera;
  - le stagioni non `None` sono segnate e non si possono scegliere;
  - Richiedi è spento se non è scelta nessuna stagione.
- **Dopo l'invio:**
  - Richiedi resta bloccato finché la scheda non si è ricaricata;
  - avviso flottante "Richiesta inviata" oppure, se Seerr l'ha approvata da sola, "Richiesta approvata";
  - per `AlreadyRequested`: "Qualcuno l'ha già chiesto";
  - per `QuotaExceeded`: "Hai raggiunto il limite di richieste";
  - per `AccountUnavailable`: "Non è stato possibile creare il tuo account Seerr";
  - per gli altri errori: "Non riuscito, riprova".
- **Errore di caricamento:** `ErrorView` con Riprova. Si torna indietro con la freccia o con Esc, come le altre schede.

### 9.3 Serie della libreria

- Se la funzione è disponibile, `CanRequest` è vero e la serie ha `tmdbId`, la scheda carica in silenzio `Tv/{tmdbId}`, con lo stesso `RequestTitleController` della scheda da richiedere (§8.4).
- Se almeno una stagione è `None`, nella fila dei pulsanti compare **"Richiedi stagioni"** (secondario), **dopo** i pulsanti del cuore e del visto: la scheda di Seerr arriva dopo le altre richieste, e prima di loro li farebbe saltare.
- Il pulsante apre `RequestSeasonsDialog` (con l'aspetto di §9.5): il `SeasonPicker` con Annulla e Richiedi, e gli stessi avvisi di §9.2.
  - Si apre sempre con **tutte** le stagioni ancora da chiedere scelte: la scelta sta nel controller, che resta vivo con la scheda della libreria, e un Annulla precedente non deve lasciare caselle tolte.
  - Richiedi ha il fuoco: Invio richiede.
  - Con la richiesta in viaggio la finestra non si chiude: né con Esc, né con il clic fuori, né con Annulla. L'avviso dell'esito arriva solo se la finestra è ancora lì a riceverlo.
- Gli errori del caricamento non si mostrano: il pulsante semplicemente non compare.

### 9.4 Pagina Richieste (`/requests`)

- **Voce "Richieste"** nella barra in alto, tra "La mia lista" e "Cerca", solo se la funzione è disponibile.
- Titolo "Richieste". Le schede sono "Le mie" e, con `CanManage`, **"Da approvare ({n})"** e **"Tutte"**.
- **La scheda sta nell'indirizzo:** `/requests?tab=mine|pending|all`.
  - I pulsanti delle schede cambiano l'indirizzo, e la pagina si rifà a ogni indirizzo nuovo. Senza `CanManage` vale sempre "Le mie".
  - Senza `?tab=`, la scheda si sceglie **una volta**, quando la pagina si apre: "Da approvare" se ce n'è almeno una, altrimenti "Le mie". Per sceglierla la pagina aspetta i permessi e il conteggio. La scelta non cambia più: approvare l'ultima richiesta, o riceverne una nuova, non sposta la pagina.
- **Riga:**
  - locandina piccola;
  - titolo e anno;
  - sotto: "Film" oppure "Stagioni 1–2", "chiesto da {name}" nelle schede da admin, e la data;
  - a destra l'etichetta di stato.

  | Stato | Etichetta | Colore |
  |---|---|---|
  | `pending` | "In attesa" | oro |
  | `approved` | "Approvata" | crema |
  | `downloading` | "In arrivo · {p}%" ("In arrivo" senza percentuale) | oro |
  | `partial` | "In parte disponibile" | verde |
  | `available` | "Disponibile" | verde (`online`) |
  | `declined` | "Rifiutata" | rosso (`error`) |
  | `failed` | "Non riuscita" | rosso |

- **Clic sulla riga:** la scheda della libreria se c'è `JellyfinItemId`, altrimenti la scheda da richiedere.
- **"Da approvare"**: ogni riga ha **Rifiuta** (secondario) e **Approva** (oro), al posto dell'etichetta di stato.
  - **Rifiuta è a due tempi, senza finestra**, come "Svuota" della cassetta: "Rifiuta" diventa "Conferma" (rosso) per 4 secondi, e il secondo clic rifiuta. Gli screen reader leggono "Conferma il rifiuto".
  - **Approva** apre la finestra (§9.5).
  - **Riga in lavorazione:** mentre la chiamata è in viaggio la riga **non cambia misura**. I pulsanti restano al loro posto ma nascosti e non si toccano, con l'indicatore sopra (letto come "Operazione in corso"), e la riga non si apre (né dalla locandina né dal titolo). "Conferma" si disarma quando parte un'azione: se la chiamata non riesce, Rifiuta riparte da capo.
  - **Dopo l'azione** la riga esce subito dall'elenco, senza animazione, e compare l'avviso "Approvata" o "Rifiutata" ("Non riuscito, riprova" se la chiamata non è riuscita).
- **Pagine:** altre 20 righe quando si arriva in fondo, o da sole se le righe non riempiono la finestra (§8.4).
- **Pagina vuota:** "Non hai ancora chiesto niente. Cerca un titolo che manca e premi Richiedi." per "Le mie", "Niente da approvare" e "Nessuna richiesta" per le altre due.
- **Errore:** `ErrorView` con Riprova. Se l'errore viene dopo le prime righe, resta l'elenco e in fondo compare "Riprova" (§8.4).
- **Funzione tolta:** se `requests` sparisce da `Features` mentre la pagina è aperta, o la pagina si apre senza, torna alla Home (`/home`) senza mostrare l'errore. Finché le funzioni non sono note (dopo un nuovo accesso) la pagina resta.

### 9.5 Finestra Approva

- **Aspetto:** le finestre dell'app hanno un aspetto comune (`showWfDialog`, `lib/ui/wf_dialog.dart`): fondo `surface`, bordo, angoli arrotondati, larghezza massima 480; Esc e il clic fuori le chiudono. Approva e "Richiedi stagioni" (§9.3) sono le prime finestre dell'app. Ogni finestra ha un nome (il titolo, per esempio "Approva: {title}"), che gli screen reader annunciano quando si apre.
- Titolo "Approva: {title}".
- **Server**, in un menu: "Predefinito ({name del server predefinito})" sempre per primo, e poi **tutti** i server dello stesso tipo, senza i 4K. Anche il server predefinito compare, per sceglierne profilo e cartella. I nomi lunghi si tagliano con i puntini.
- Con "Predefinito" profilo e cartella non compaiono, e Seerr decide da solo: per le serie riconosce anche gli anime.
- Con un altro server compaiono i menu **Profilo** e **Cartella**, impostati sui valori predefiniti di quel server.
- **Nessun server segnato come predefinito:** con "Predefinito" Seerr approverebbe senza mandare niente a Radarr o Sonarr. Quindi, quando i server arrivano, si parte dal **primo server** (con il suo profilo e la sua cartella). La voce "Predefinito" resta tra le altre.
- I server si caricano all'apertura (`GET Services/{type}`), con uno scheletro. Finché non arrivano Approva è spento, così Invio non approva alla cieca. Se il caricamento non riesce, resta solo "Predefinito" con una nota.
- Pulsanti Annulla e **Approva**. Approva ha il fuoco: con i server arrivati Invio approva.
- **La finestra restituisce la scelta** (server, profilo e cartella, oppure "Predefinito") e si chiude: la chiamata parte dalla pagina, e la riga resta bloccata finché non arriva la risposta (§9.4).

### 9.6 Cassetta delle notifiche

- **`RequestAvailable`:**
  - icona `clapperboard`, testo "Ora disponibile: {title}" ("Ora disponibile: {title}, stagioni {list}" con le stagioni);
  - il clic apre la scheda della libreria (`openItemById`) se c'è `ItemId`, altrimenti la pagina Richieste sulla scheda "Le mie" (`/requests?tab=mine`): senza la scheda, un admin con richieste in attesa troverebbe "Da approvare".
- **`RequestPending`:**
  - icona `inbox`, testo "{name} ha chiesto {title}" ("…, stagioni {list}");
  - se il nome di chi ha chiesto manca (Seerr può mandarlo vuoto) la frase non regge, e il testo è "Nuova richiesta: {title}";
  - il clic apre Richieste sulla scheda "Da approvare" (`/requests?tab=pending`).
- Il testo di una voce sta in al massimo 3 righe, con i puntini: il titolo di Seerr arriva a 200 caratteri.

## 10. Testi nuovi (ARB, it + en)

`app_it.arb` è il modello, poi `app_en.arb`. I testi principali, in italiano:

| Dove | Testi |
|---|---|
| Barra | "Richieste" |
| Ricerca | "Da richiedere", "Non sono ancora su WonderFlix", "Seerr non risponde" |
| Etichette | "Film", "Serie", "Richiesto", "Richiesto da te", "In arrivo", "In parte", "In parte disponibile", "Su WonderFlix" |
| Scheda | "Richiedi", "Richiedi {n} stagioni", "Guarda", "Richiedi stagioni", "Stagioni", "Tutte", "Stagione {n} · {count} episodi", "Da richiedere", "In attesa", "Disponibile" |
| Avvisi | "Richiesta inviata", "Richiesta approvata", "Qualcuno l'ha già chiesto", "Hai raggiunto il limite di richieste", "Non è stato possibile creare il tuo account Seerr", "Non riuscito, riprova", "Approvata", "Rifiutata" |
| Pagina | "Le mie", "Da approvare ({n})", "Tutte", "chiesto da {name}", "Stagioni {list}", "Approvata", "In arrivo · {p}%", "Rifiutata", "Non riuscita", "Approva", "Rifiuta", "Conferma", "Conferma il rifiuto" (per gli screen reader), "Operazione in corso" (indicatore della riga), i tre messaggi di pagina vuota |
| Finestre | "Approva: {title}", "Server", "Predefinito ({name})", "Profilo", "Cartella", "Annulla" |
| Cassetta | "Ora disponibile: {title}", "{name} ha chiesto {title}", "Nuova richiesta: {title}" (senza il nome), ", stagioni {list}" |

Due test dei testi (`test/app/l10n_plan15a_test.dart` e `test/app/l10n_plan15b_test.dart`) controllano che le chiavi ci siano in entrambe le lingue.

## 11. Casi limite

- **Seerr spento o lento (oltre 10 s):**
  - la sezione "Da richiedere" mostra "Seerr non risponde", e la ricerca nella libreria funziona come sempre;
  - schede e pagina Richieste mostrano `ErrorView`;
  - "Richiedi stagioni" non compare.
- **Seerr risponde con `null` dove ci si aspetta una lista:** vale come una risposta inattesa. Il plugin risponde 502 `SeerrUnavailable` e l'app mostra "Seerr non risponde", come per Seerr spento.
- **Seerr non configurato o tolto:** `requests` sparisce da `Features` e l'app torna quella di oggi. Una chiamata in volo riceve 503 (`NotConfigured`) e l'app mostra "Seerr non risponde", come per Seerr spento. Se si sta guardando la pagina Richieste, l'app torna alla Home (§9.4).
- **Due persone chiedono lo stesso titolo insieme:** la seconda riceve "Qualcuno l'ha già chiesto" e la scheda si ricarica.
- **Stagioni chieste da altri nel frattempo:** Seerr toglie i doppioni. Se non resta nulla da chiedere arriva `NothingToRequest`, la scheda si ricarica e mostra lo stato.
- **Serie con solo alcune delle stagioni chieste arrivate:** la richiesta è "In parte disponibile", a meno che non ci sia un download in corso, che ha la precedenza ("In arrivo"). Lo stato della serie intera non conta (§7.3).
- **Richieste dell'admin:** Seerr le approva da sola. L'avviso è "Richiesta approvata", e non parte nessun `RequestPending`.
- **Utente senza account Seerr:** "Le mie" è vuota e `HasAccount` è falso. L'account nasce alla prima richiesta (§7.2).
- **Due prime richieste insieme dello stesso utente:** l'import parte una volta sola, e tutte e due le richieste usano l'account creato (§7.2).
- **Utente Jellyfin cancellato o rinominato:** l'abbinamento usa l'id, quindi un cambio di nome non conta. Gli utenti Seerr legati a utenti cancellati non vengono mai usati.
- **"Ora disponibile" in ritardo:** finché la sincronizzazione di Seerr è rotta (§3), l'avviso arriva dopo la scansione della notte. Il riepilogo delle novità della Spec G, invece, arriva come oggi.
- **Doppio avviso:** un titolo chiesto e arrivato compare sia in "Ora disponibile" sia nel riepilogo delle novità. Va bene così, perché hanno scopi diversi.
- **Webhook ripetuto o tardivo:** la voce con lo stesso `RequestId` sostituisce quella di prima (§7.6).
- **Webhook con un `requestedBy_jellyfinUserId` che non esiste più o è disabilitato:** l'evento si scarta con una riga nel registro.
- **Titolo disponibile senza `jellyfinMediaId`:** la riga apre la scheda da richiedere, e l'avviso la pagina Richieste su "Le mie" (`/requests?tab=mine`). Dalla scheda da richiedere manca "Guarda".
- **Approvazione di una richiesta già approvata o rifiutata da un altro admin, o dal sito di Seerr:** Seerr risponde comunque. Il plugin restituisce la richiesta aggiornata, e la riga esce da "Da approvare".
- **Lingua:** con `language=it` Seerr dà titoli e trame in italiano quando TMDB li ha, altrimenti in originale.
- **Versione di Seerr diversa:** le risposte all'app sono oggetti del plugin, quindi un cambio dell'API di Seerr si sistema nel solo plugin. "Prova collegamento" mostra la versione.
- **App vecchie (0.8.x) con il plugin 1.4.0:** non vedono nulla di nuovo. **App 0.9.0 con il plugin vecchio:** senza `requests`, nulla di nuovo.

## 12. Test

- **Plugin (xunit):**
  - `SeerrClient` con un `HttpMessageHandler` finto: header `X-API-Key` sempre presente, `X-API-User` solo dove serve, attesa massima, mappatura degli errori (403 con quota o permesso, 409, 202, 401 della chiave, errori di rete);
  - `SeerrUserMap`: abbinamento senza badare a maiuscole e trattini, doppioni, cache, import alla prima richiesta e import non riuscito;
  - `RequestsService`: stati dei titoli e delle stagioni, stato delle richieste negli otto casi, `Progress`, filtri, completamento dei titoli con `SeerrTitleCache`, approvazione con e senza `PUT`, persone e titoli bloccati tolti dalla ricerca;
  - `RequestsController`: accesso, `CanManage` per le operazioni da admin, mai 404, `{Code}`;
  - webhook: segreto (giusto, sbagliato, mancante), i tipi, chi riceve `RequestPending`, eventi incompleti, doppioni nella cassetta;
  - `Info.Features` con e senza Seerr configurato.
- **App:**
  - `RequestsApi` con `FakeAdapter`: percorsi, query, corpi, lettura delle risposte, `RequestsFailure`;
  - `JellyfinItem.tmdbId`;
  - controller con un `FakeRequestsApi`: doppioni con la libreria (per id Jellyfin, e per id TMDB dello stesso tipo), risposte vecchie, stagioni scelte all'apertura, invio bloccato, ricarica dopo `AlreadyRequested`, pagine, aggiornamento su `InboxChanged` (anche oltre la prima pagina), righe approvate o rifiutate che non tornano da una lettura partita prima;
  - widget:
    - sezione "Da richiedere" (etichette, stati, errore, nessun titolo);
    - scheda da richiedere (pulsanti nei vari stati, stagioni, avvisi);
    - "Richiedi stagioni" (presente e assente);
    - pagina Richieste con e senza `CanManage` (schede nell'indirizzo, righe, conferma di Rifiuta, riga in lavorazione, pagina vuota, funzione tolta);
    - finestra Approva (Predefinito, altro server, errore dei server);
    - righe nuove della cassetta;
    - voce nella barra solo con `requests`;
  - test dei testi.
- **A mano, sul server vero e con l'utente:**
  - "Prova collegamento";
  - una richiesta da un account normale e una dall'admin;
  - l'import di un utente senza account;
  - approvazione con "Predefinito" e con "Radarr Anime";
  - rifiuto;
  - webhook "Nuova richiesta" e "Ora disponibile".

## 13. Rischi e punti da verificare

- **Indirizzo di Seerr dal container di Jellyfin:** si prova con "Prova collegamento" all'inizio del piano 15a. Se l'indirizzo pubblico non funziona, si cerca un indirizzo interno, per esempio la rete Docker o l'IP del server.
- **Webhook attraverso nginx:** Seerr chiamerà l'indirizzo pubblico di Jellyfin. Va verificato che un `POST` senza accesso arrivi al plugin.
- **Avvisi "Ora disponibile" lenti** finché la sincronizzazione di Seerr è rotta (§3, §11): si sistema con il compito a parte sul server.
- **Seerr segnala un aggiornamento disponibile:** prima della release si riprova contro la versione installata in quel momento.

## 14. Divisione in piani

1. **Piano 15a — chiedere:**
   - plugin 1.4.0 completo (configurazione, client, abbinamento e import, endpoint, webhook, tipi nuovi della cassetta), installato a mano sul server per le prove;
   - nell'app: `JellyfinItem.tmdbId`, `RequestsApi` e modelli, disponibilità, sezione "Da richiedere", scheda da richiedere con stagioni e Richiedi.
2. **Piano 15b — seguire e approvare:**
   - pagina Richieste e voce nella barra;
   - finestra Approva e Rifiuta;
   - "Richiedi stagioni" sulle serie della libreria;
   - righe nuove della cassetta;
   - configurazione del webhook in Seerr, con l'ok dell'utente;
   - allineamento di questa spec.

   Poi la release: plugin 1.4.0 dal Catalogo, quindi app **0.9.0 non obbligatoria**.
