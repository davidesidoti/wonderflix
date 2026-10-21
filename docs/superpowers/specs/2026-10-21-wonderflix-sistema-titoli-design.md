# WonderFlix — Spec R: segnalazioni e strumenti per sistemare i titoli

- **Data:** 2026-10-21
- **Stato:** approvata il 2026-10-21; piano 24a realizzato (`docs/superpowers/plans/2026-10-21-wonderflix-24a-segnalazioni-plugin.md`), build di prova sul server; piani 24b e 24c da realizzare.
- **Ambito:** Spec R. Porta nell'app quello che oggi si fa solo dal menu "⋯" di jellyfin-web su un titolo: cercare e scaricare sottotitoli, modificare i metadati, identificare il titolo giusto, aggiornare i metadati, cambiare locandina e sfondo. Aggiunge le **segnalazioni**: chi trova un problema lo segnala e gli admin lo sistemano. Assorbe la parte "scaricare i sottotitoli mancanti" dell'idea 10 di `docs/IDEE.md`. Lo stile dei sottotitoli resta fuori.

## 1. Obiettivo

Oggi, quando un titolo ha un problema, l'admin deve aprire jellyfin-web. Due casi reali:

- un film arrivato con il titolo in arabo, da reidentificare;
- un episodio senza sottotitoli italiani, perché Bazarr non li ha trovati.

Gli amici se ne accorgono mentre guardano, ma non hanno un modo per dirlo dentro l'app.

Con lo spec R:

- **chiunque** può segnalare un problema su un film, una serie, una stagione o un episodio, con il tipo di problema e una nota facoltativa;
- **gli admin** ricevono la segnalazione nella cassetta, aprono il titolo e lo sistemano dall'app;
- quando l'admin chiude la segnalazione, **chi l'ha fatta riceve una notifica**: "sistemato" oppure "non sistemabile per ora", con la nota dell'admin se c'è;
- **chi ha la spunta sottotitoli** in Jellyfin può cercare, scaricare e caricare sottotitoli da solo. Non tocca i metadati e non riceve le segnalazioni.

**Nota sul modello:** le segnalazioni sono di WonderFlix, salvate dal plugin. **Non** sono le "Issues" di Seerr, che restano escluse come nello spec I. I permessi invece sono quelli di Jellyfin (`IsAdministrator`, `EnableSubtitleManagement`), letti dal server: l'app non ha impostazioni di permesso sue.

## 2. Situazione di partenza

App 0.17.0, plugin 1.11.0, Jellyfin 10.11.9 su Ultra.cc. Plugin **Open Subtitles v24** installato sul server; ci sono anche TMDb, TheTVDB, Fanart, AniDB e AniList.

### App

- Un solo client HTTP con il token dell'utente (`lib/core/jellyfin/jellyfin_http.dart`), usato sia per Jellyfin sia per il plugin.
- Le chiamate dirette agli item sono in `library_api.dart`, `playback_api.dart` e `admin_api.dart`. `POST /Items/{id}/Refresh` è usato solo per la scansione delle librerie.
- Nessuna chiamata a RemoteSearch, Subtitles, MetadataEditor o RemoteImages. Sono tutte in `docs/reference/jellyfin-openapi-10.11.9.json`.
- **Admin:** `Policy.IsAdministrator` da `/Users/Me` (`auth_models.dart`), esposto da `isAdminProvider` (`admin_providers.dart`). Nessun altro flag di policy viene letto, a parte `SyncPlayAccess`.
- **Dettaglio:**
  - `item_detail_screen.dart`, `movie_detail_view.dart`, `series_detail_view.dart`;
  - i bottoni sono in `detail_header.dart` (`Wrap`). Non c'è un menu "⋯";
  - gli episodi sono in `_EpisodeList` (`series_detail_view.dart`);
  - menu esistenti da riusare: `ui/wf_menus.dart`, `app_shell.dart`, `users_tab.dart`.
- **Finestre:** `showWfDialog` (`ui/wf_dialog.dart`), `wf_confirm_dialog.dart`. Selettore file: `file_selector` (già in `pubspec.yaml`).
- **Player:** `features/player/tracks_panel.dart` (tracce, ritardo, dimensione). I sottotitoli esterni si caricano da `deliveryUrl` (`playback_service.dart`).
- **Dashboard admin:** scheda WonderFlix (`wonderflix_tab.dart`) con card su `AdminCard`.
- **Cassetta:** l'avviso `InboxChanged` arriva via WebSocket e l'app ricarica `GET /WonderFlixWatchParty/Inbox`. Al tocco di una voce l'app apre una schermata (`inbox_panel.dart`).

### Plugin

- **Cassetta:** `InboxService`/`InboxBook`/`InboxStore`, con i tipi in `Protocol/InboxDtos.cs`. `RemoveAsync(userId, entryId)` toglie una voce.
- **Archivi:** `RecommendationStore` e `ratings.json` fanno da modello (caricamento pigro, scrittura atomica, `.bad`).
- **Admin:**
  - endpoint con `Policies.RequiresElevation`;
  - utenti da `IUserDirectory`, con `UserRef.IsAdmin` (`JellyfinUserDirectory.cs`).
- **Funzioni del plugin:** l'app sa cosa c'è da `Info`. `WatchPartyProtocol.FeaturesWith(...)` elenca funzioni come `ratings`.
- **Notifiche delle richieste Seerr:** vanno a chi ha `ManageRequests` **in Seerr**, non agli admin Jellyfin. Le segnalazioni hanno una regola loro (§6.3).

### Jellyfin: chi può fare cosa (10.11, uguale su 10.9 e 10.10 per queste chiamate)

| Azione | Endpoint | Permesso |
|---|---|---|
| Cerca sottotitoli | `GET /Items/{id}/RemoteSearch/Subtitles/{lang3}` | `EnableSubtitleManagement` (**l'admin non basta**) |
| Scarica sottotitolo | `POST /Items/{id}/RemoteSearch/Subtitles/{subtitleId}` | idem. Risponde 204 **anche se fallisce** |
| Carica sottotitolo | `POST /Videos/{id}/Subtitles` (base64) | idem |
| Elimina sottotitolo esterno | `DELETE /Videos/{id}/Subtitles/{index}` | solo admin |
| Identifica: cerca | `POST /Items/RemoteSearch/{Movie\|Series}` | qualunque utente |
| Identifica: applica | `POST /Items/RemoteSearch/Apply/{id}?replaceAllImages=` | solo admin. **Sincrono e lento** |
| Editor metadati | `GET /Items/{id}/MetadataEditor`, `POST /Items/{id}` (DTO intero) | solo admin |
| Aggiorna metadati | `POST /Items/{id}/Refresh?metadataRefreshMode=&imageRefreshMode=&replaceAllMetadata=&replaceAllImages=` | solo admin. In coda |
| Immagini remote | `GET /Items/{id}/RemoteImages`, `POST …/RemoteImages/Download?type=&imageUrl=` | lista: tutti; download: admin |
| Carica immagine | `POST /Items/{id}/Images/{type}` (base64) | admin |
| Ordine degli sfondi | `POST /Items/{id}/Images/Backdrop/{index}/Index?newIndex=` | admin |

## 3. Decisioni

Prese con l'utente nel brainstorming del 2026-10-21:

1. **Tre ruoli:**
   - l'**utente** segnala;
   - chi ha la **spunta sottotitoli** di Jellyfin sistema solo i sottotitoli;
   - l'**admin** sistema tutto.
2. **Le notifiche delle segnalazioni vanno solo agli admin.** Chi ha la spunta sottotitoli non le riceve.
3. **La segnalazione:** un tipo di problema (Sottotitoli, Titolo o informazioni, Audio o video, Altro) più una **nota facoltativa**.
4. **Si segnala a ogni livello:** film, serie intera, stagione o singolo episodio. Dall'episodio si può allargare alla stagione o alla serie.
5. **Chiusura:** l'admin preme "Sistemato" o "Non sistemabile", ognuno con una nota facoltativa. La segnalazione sparisce e chi l'ha fatta riceve una notifica con l'esito.
6. **Dove l'admin le trova:**
   - la notifica nella cassetta, che apre il dettaglio del titolo;
   - nel dettaglio, un riquadro con le segnalazioni aperte;
   - una card "Segnalazioni" nella scheda WonderFlix della dashboard.
7. **Perimetro:** segnalazioni (A), sottotitoli (B), metadati: modifica, identifica, aggiorna (C), **locandina e sfondo (D)**, info tecniche (E).
8. **Le bozze** viste nel browser il 2026-10-21 sono approvate (`.superpowers/brainstorm/…/spec-r-bozze.html`). Il menu "⋯" sta accanto a Preferito e Visto.

**Le mie scelte** (da confermare leggendo):

9. **L'admin può sempre gestire i sottotitoli**, anche senza la spunta. Per questo cercare, scaricare e caricare passano **dal plugin**, che lavora lato server (§6.4). Il plugin, inoltre, sa se il download è fallito, a differenza di Jellyfin che risponde 204 comunque.
10. **Anche "Sistemato" ha una nota facoltativa**, come "Non sistemabile".
11. **Il riquadro della segnalazione ha una scorciatoia** verso lo strumento giusto: "Cerca sottotitoli" per i sottotitoli, "Identifica" o "Modifica metadati" per le informazioni.
12. **Doppioni:** se lo stesso utente segnala di nuovo lo stesso titolo con lo stesso tipo mentre la prima è aperta, la nota nuova sostituisce la vecchia e gli admin non vengono riavvisati. Utenti diversi fanno segnalazioni diverse, e ognuno riceve la sua risposta.
13. **Massimo 20 segnalazioni aperte per utente.**
14. **Chiudendo una segnalazione, la sua notifica sparisce dalla cassetta di tutti gli admin.**
15. **I campi cambiati nell'editor metadati vengono bloccati** (`LockedFields`), così un aggiornamento successivo non li riscrive. Nell'editor ogni campo bloccato ha un lucchetto per sbloccarlo.
16. **"Usa come sfondo"** scarica l'immagine e la mette **prima** fra gli sfondi, perché il dettaglio mostra il primo. Gli sfondi vecchi restano.
17. **Il nome del file** nelle info tecniche lo vede solo l'admin. Il percorso sul server non lo vede nessuno.
18. **Nel player**, chi può gestire i sottotitoli trova "Cerca sottotitoli" nel pannello tracce. Segnalare dal player resta fuori.

Decise dopo la revisione del documento:

19. **Identifica e i campi bloccati.** Jellyfin non sovrascrive i campi bloccati, neanche con Identifica. Se l'item ha campi bloccati, la conferma di Identifica mostra la casella "Sblocca i campi modificati a mano", attiva di base. Con la casella attiva, l'app svuota `LockedFields` e `LockData` con `POST /Items/{id}` prima di `Apply`. Così il caso del titolo in arabo, prima corretto a mano e poi identificato, funziona.
20. **Scorciatoie del riquadro per livello:**
    - Sottotitoli su un film o un episodio: "Cerca sottotitoli";
    - Sottotitoli su una stagione o una serie: niente scorciatoia, l'admin sceglie l'episodio dalla lista;
    - Titolo o informazioni su un film o una serie: "Identifica";
    - Titolo o informazioni su una stagione o un episodio: "Modifica metadati";
    - Audio o video, Altro: nessuna scorciatoia.
21. **Sottotitolo nuovo nel player:**
    - l'app richiede `PlaybackInfo` (l'unica fonte di `DeliveryUrl`). Se la traccia nuova arriva con consegna esterna, il player la aggiunge senza fermarsi;
    - altrimenti, per esempio con una transcodifica che la incide nel video, compare "Il sottotitolo sarà disponibile dalla prossima riproduzione".
    Nessuna ricarica dello stream.
22. **Immagini per livello:**
    - film e serie: Locandina e Sfondo;
    - stagioni: solo Locandina;
    - episodi: solo "Immagine" (la miniatura 16:9, tipo `Primary`).
23. **Il "⋯" della stagione** sta a destra delle schede delle stagioni (`_SeasonTabs`) e vale per la stagione selezionata.

## 4. Perimetro

### Incluso

- **Plugin 1.12.0:**
  - archivio delle segnalazioni (`reports.json`) ed endpoint;
  - due tipi nuovi di voce nella cassetta: `ReportPending` e `ReportResolved`;
  - endpoint sottotitoli lato server;
  - funzione `reports` in `Info`.
- **App 0.18.0:**
  - menu "⋯" nel dettaglio (film, serie, stagione, episodio);
  - "Segnala un problema";
  - riquadro delle segnalazioni nel dettaglio e card nella dashboard;
  - notifiche;
  - finestra Sottotitoli, anche dal player;
  - Info tecniche;
  - Modifica metadati, Identifica, Aggiorna metadati, Locandina e sfondo;
  - testi it/en.

### Escluso

- Eliminare un titolo (cancella i file dal disco).
- Aggiungere a collezioni o saghe.
- Logo, miniature, banner e altre immagini oltre a locandina e sfondo; eliminare immagini.
- Identifica per stagioni ed episodi (Jellyfin non lo fa), per persone e saghe.
- Modifica di cast, studi, tag, id esterni, numeri di stagione ed episodio.
- Testi delle canzoni, rigenerazione delle anteprime della barra, scansione di una libreria.
- Stile dei sottotitoli (resto dell'idea 10).
- Segnalare dal player; storico delle segnalazioni chiuse; "le mie segnalazioni" per l'utente.
- Gestire la spunta sottotitoli dall'app (si mette in Jellyfin).
- Avvisi su Discord, email o push.

## 5. Architettura

```
Segnalazioni
  App ──POST Reports {ItemId, Type, Note}──▶ Plugin ──▶ reports.json
                                              └──▶ cassetta di ogni admin: ReportPending
  Admin ──GET Reports──▶ Plugin (aperte, con nomi e titolo da aprire)
  Admin ──POST Reports/{id}/Resolve {Outcome, Note}──▶ Plugin ──▶ toglie la segnalazione
                                              ├──▶ toglie ReportPending dagli admin
                                              └──▶ cassetta di chi ha segnalato: ReportResolved

Sottotitoli (admin o spunta sottotitoli)
  App ──GET/POST Subtitles/…──▶ Plugin ──ISubtitleManager──▶ file accanto al video + refresh in coda

Metadati, identifica, aggiorna, immagini (solo admin), elimina sottotitolo (solo admin)
  App ──▶ Jellyfin direttamente, con il token dell'utente

Info tecniche (tutti)
  App: dati già presenti nell'item (MediaSources / MediaStreams)
```

- **Il plugin decide:** chi riceve le notifiche, chi può gestire i sottotitoli e quali segnalazioni ci sono.
- **Jellyfin decide** tutto il resto dei permessi. L'app nasconde le voci che l'utente non può usare, ma la vera difesa resta del server.

## 6. Plugin 1.12.0

### 6.1 Archivio (`reports.json`)

- File in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, con le stesse regole di `RecommendationStore`: caricamento pigro sotto lock, scrittura atomica, `.bad` se illeggibile, un errore del disco non annulla la modifica in memoria.
- **Contenuto:** `{"Version": 1, "Reports": [{"Id", "UserId", "ItemId", "Type", "Note", "CreatedAt", "UpdatedAt"}]}`.
  - `Id`, `UserId`, `ItemId`: guid in formato `N`. `ItemId` è il film, la serie, la stagione o l'episodio segnalato;
  - `Type`: `Subtitles` | `Metadata` | `AudioVideo` | `Other`;
  - `Note`: manca se vuota. Testo semplice con le regole dei commenti dello spec N §6.2 (caratteri di controllo e a capo diventati spazi, spazi ai bordi tolti), al massimo **500** punti di codice (non unità UTF-16: 500 emoji valgono 500); oltre si risponde 400;
  - date ISO-8601 UTC;
  - le segnalazioni sono scritte dalla più recente.
- **File illeggibile:** finisce in `.bad` anche se un id non è in formato `N`, se un tipo è sconosciuto o se una voce o l'elenco sono `null`.
- **Ci sono solo le segnalazioni aperte.** Una chiusa si cancella (decisione 5).
- **Pulizia periodica** (ogni 5 minuti, un `HostedService` col suo `try/catch`): toglie le segnalazioni di utenti che non esistono più e di titoli che non esistono più, senza avvisare nessuno, e toglie anche le loro `ReportPending`. Come per i voti, non tocca i titoli durante una scansione (`ILibraryTitles.IsScanRunning`) né se la libreria lancia un errore.

### 6.2 Endpoint (sotto `/WonderFlixWatchParty`)

| Metodo e percorso | Chi | Cosa |
|---|---|---|
| `POST Reports {ItemId, Type, Note?}` | ogni utente | Crea la segnalazione. 400 se il tipo non è valido, se la nota supera 500 punti di codice, se il titolo non è un `Movie`, `Series`, `Season` o `Episode` (una stagione o un episodio senza serie non vale), se chi chiama non vede il titolo o se la libreria non risponde. 409 `LimitReached` oltre 20 aperte. Doppione (stesso utente, titolo e tipo): la `Note` nuova sostituisce la vecchia (una nota vuota la toglie), `UpdatedAt` si aggiorna, nessun nuovo avviso. Risponde **200** con la segnalazione (`ReportDto`), sia nuova sia doppione. |
| `GET Reports/Mine?itemId=` | ogni utente | Le proprie segnalazioni aperte su quel titolo, così il pannello mostra "Hai già segnalato questo problema" e precompila la nota. Risponde `{"Items":[ReportDto…]}`, dalla più recente. 400 se `itemId` non è valido. |
| `GET Reports` | admin | Tutte le aperte, dalla più recente: `{"Items":[ReportDto…]}`. |
| `POST Reports/{id}/Resolve {Outcome, Note?}` | admin | `Outcome`: `Fixed` \| `CannotFix`. `Note` con le stesse regole (500 punti di codice). Toglie la segnalazione e le sue `ReportPending`, e aggiunge `ReportResolved` a chi l'ha fatta, ma **non** se chi chiude è anche chi ha segnalato. Risponde 204. 400 per un id, un esito o una nota non validi. **409** `{"Reason":"Closed"}` se non c'è più, per esempio se un altro admin l'ha appena chiusa: di due admin insieme, solo il primo la chiude e chi ha segnalato riceve **una** sola `ReportResolved`. |

- **`ReportDto`** (stessa forma per `GET Reports`, `GET Reports/Mine` e la risposta di `POST Reports`; `?` = assente se vuoto):
  - `Id`, `Type`, `Note`?, `CreatedAt`, `UpdatedAt`;
  - `UserId`, `UserName`: chi ha segnalato;
  - `ItemId`, `ItemType` (`Movie` | `Series` | `Season` | `Episode`), `ItemName`: il titolo segnalato;
  - `TitleId`, `TitleName`: il film o la serie da aprire (per un film o una serie sono quelli dell'item), `SeasonNumber`? ed `EpisodeNumber`? per stagioni ed episodi.
  - `TitleType` e `SeriesName` della prima stesura non ci sono: `TitleType` è `Movie` se `ItemType` è `Movie`, altrimenti `Series`; `SeriesName` è `TitleName`, che vale anche per i film.
- I nomi si leggono dalla libreria senza utente **a ogni risposta**: dopo un'identifica si vede il nome nuovo. Un titolo che non si trova più (o se la libreria lancia un errore) resta in lista con `ItemName`, `TitleName` e `ItemType` vuoti e `TitleId` uguale a `ItemId`, finché la pulizia non lo toglie. `UserName` è vuoto per un utente che non c'è più.
- **Mai 404.** Gli id sono stringhe senza vincoli di rotta, quindi un id non valido è 400. I 409 hanno il corpo `{"Reason": "…"}` (`LimitReached`, `Closed`).
- Gli admin che ricevono `ReportPending` sono gli utenti di `IUserDirectory.GetUsers()` con `UserRef.IsAdmin` **e** abilitati, tranne chi segnala; non quelli di Seerr.
- **Chiave API** (non ha un utente): `POST Reports` e `GET Reports/Mine` rispondono 400; `GET Reports` e Resolve funzionano, e chi chiude risulta "chiave API" nel log.

### 6.3 Cassetta

Due nuovi tipi in `InboxEntryTypes`.

Le voci **riusano i campi che `InboxEntry` ha già** e ne aggiungono sei, tutti assenti se vuoti: `ReportId`, `ReportType`, `Outcome`, `ItemType`, `SeasonNumber`, `EpisodeNumber`.

| Campo | Cosa contiene |
|---|---|
| `ReportId` | la segnalazione (formato `N`) |
| `ReportType` | `Subtitles` \| `Metadata` \| `AudioVideo` \| `Other` |
| `FromName` | chi ha segnalato (solo `ReportPending`) |
| `Title` | il nome del film o della serie (`TitleName`) |
| `ImageItemId` | il film o la serie da aprire (`TitleId`); fa anche da locandina |
| `ItemId` | il titolo segnalato (film, serie, stagione o episodio) |
| `ItemType` | `Movie` \| `Series` \| `Season` \| `Episode` |
| `SeasonNumber`, `EpisodeNumber` | per stagioni ed episodi |
| `Text` | `ReportPending`: la nota di chi ha segnalato. `ReportResolved`: la nota dell'admin, già ripulita |
| `Outcome` | `Fixed` \| `CannotFix` (solo `ReportResolved`) |

- Il livello ("S2 E3", "Stagione 2", "Tutta la serie") lo compone l'app nella sua lingua: il plugin non scrive testi in italiano. Per questo `SeriesName`, `TitleType`, `ItemName` e `ResolutionNote` della prima stesura non ci sono.
- Se il titolo non c'è più (o la libreria non risponde), la voce ha `Title` vuoto, `ItemId` della segnalazione e niente `ImageItemId`, `ItemType`, `SeasonNumber`, `EpisodeNumber`.
- **`ReportPending`**, a ogni admin abilitato tranne chi ha segnalato.
  - Contiene anche la nota (`Text`): l'admin la vede comunque nel riquadro.
  - Si toglie da tutti gli admin quando la segnalazione viene chiusa o pulita. Un admin che segnala e poi chiude da solo non riceve né la propria `ReportPending` né una `ReportResolved`.
  - Un admin nuovo **non** riceve le segnalazioni già aperte: le trova nella card.
  - **Un doppione con una nota nuova non aggiorna la `Text` della `ReportPending` già nella cassetta** (nessun nuovo avviso, decisione 12). La nota in tempo reale la mostrano il riquadro e la card, che leggono `GET Reports`.
- **`ReportResolved`**, a chi ha segnalato. La pulizia non ne crea né ne toglie. Segue la regola di tutte le voci della cassetta (30 giorni).
- Entrambe passano da `InboxService`: lock, `InboxChanged`, i limiti di lunghezza della cassetta, come i tipi esistenti. Un errore nella cassetta non fa fallire la segnalazione né la chiusura: finisce in un `Warning`.
- Casi limite noti: se chi ha segnalato viene eliminato prima della chiusura, la `ReportResolved` resta nella sua cassetta finché la pulizia della cassetta non la toglie; una `ReportPending` può restare orfana se la segnalazione si chiude proprio fra la creazione e l'invio degli avvisi (resta fino ai 30 giorni della cassetta; l'app deve gestire una segnalazione che non trova più).

### 6.4 Sottotitoli lato server

Endpoint ammessi a chi è **admin oppure** ha `EnableSubtitleManagement` (`user.HasPermission(PermissionKind.EnableSubtitleManagement)`), ed è abilitato. Altrimenti 403.

- **Il permesso si legge a ogni chiamata** da `IUserDirectory`: `UserRef` ha un campo nuovo, facoltativo e in fondo, `bool CanManageSubtitles = false`, che `JellyfinUserDirectory` legge da `PermissionKind.EnableSubtitleManagement` (= 22). Un permesso tolto vale subito.
- Il 403 viene prima del 400. Con la **chiave API** (nessun utente) tutti e tre gli endpoint rispondono 403.
- Un `itemId` non valido, di un titolo che chi chiama non vede o che non è un `Movie` o un `Episode`: 400. Mai 404.
- Il risultato dei servizi è un enum a parte, `SubtitleStatus { Ok, Forbidden, Invalid, Failed }`; `HubStatus` resta com'è, perché altri `switch` lo usano.

| Metodo e percorso | Cosa |
|---|---|
| `GET Subtitles/{itemId}/Search?language={lang3}&perfectMatch=` | `ISubtitleManager.SearchSubtitles` per un `Movie` o un `Episode` che chi chiama vede. Risponde 200 con un array di `RemoteSubtitleDto`, **appiattito** (sotto). Lista vuota se non ci sono provider. Se la ricerca lancia un errore: **502 senza corpo**, con un `Warning`. |
| `POST Subtitles/{itemId}/Download {SubtitleId}` | `ISubtitleManager.DownloadSubtitles`, poi refresh dell'item in coda (come fa `SubtitleController`, solo dopo un download riuscito). Risponde 204. Se il download lancia un errore: **502** `{"Reason":"DownloadFailed"}`, con un `Warning` nel log. |
| `POST Subtitles/{itemId}/Upload {Language, Format, IsForced, IsHearingImpaired, Data}` | `ISubtitleManager.UploadSubtitle`, poi refresh in coda (solo dopo un salvataggio riuscito). Risponde 204. Un errore di Jellyfin durante il salvataggio: **502** `{"Reason":"UploadFailed"}`. 400 per i casi sotto. |

- **`RemoteSubtitleDto`** (la risposta di Search): `Id`, `ProviderName`, `Name`, `Language` (le tre lettere di Jellyfin), `Format`, `CommunityRating`?, `DownloadCount`?, `IsHashMatch`, `HearingImpaired`, `Forced`, `MachineTranslated`.
  - I booleani di Jellyfin, che possono essere `null`, diventano `false`; le stringhe `null` diventano vuote.
  - `AiTranslated || MachineTranslated` diventa `MachineTranslated`: non c'è più `AiTranslated`.
- **Lingue:** tre lettere ASCII (controllate **prima** di passare al minuscolo, perché il segno Kelvin diventerebbe una "k"); il plugin le porta in minuscolo (`ita`), sia per cercare sia per caricare. Altrimenti 400.
- **Download:** `SubtitleId` non vuoto né fatto di soli spazi e al massimo `SubtitleService.MaxSubtitleIdLength` (1024) caratteri, altrimenti 400 **prima** di chiamare Jellyfin.
- **Upload:**
  - `Data` in base64 standard, al massimo `SubtitleService.MaxUploadBytes` = 2 MiB (2 097 152 byte) **decodificati**, non vuoti; altrimenti 400;
  - `Format` fra `srt`, `ass`, `ssa`, `vtt`, `sub`, senza badare alle maiuscole (spazi ai bordi tolti); altrimenti 400.
- Si elimina direttamente da Jellyfin (`DELETE /Videos/{id}/Subtitles/{index}`, solo admin): non serve il plugin.
- **Log:** `Debug` per ricerche e download riusciti; `Warning` (con l'eccezione) per ricerche, download e upload falliti. Dentro ci sono l'id dell'item e, per il download, il provider; mai il contenuto del file.
  - L'id del sottotitolo è del client: del download fallito si scrive solo il provider (la parte prima di `_`), e solo se sono da 1 a 32 lettere o cifre ASCII; altrimenti "unknown". Così testo del client non arriva al log.
  - Limite noto: il testo dell'eccezione di Jellyfin o del provider può contenere un URL o un percorso.
- **Provider lenti:** un timeout del provider lancia un'eccezione di annullamento anche se la richiesta non è stata annullata: ricerca, download e upload lo trattano come un errore (502 con `Warning`) e lasciano passare l'annullamento solo quando il token della richiesta è davvero annullato.
- **Upload:** il corpo della richiesta è limitato a 4 MiB (`SubtitlesController.MaxUploadRequestBytes`: 2 MiB di base64 sono circa 2,8 MB, più l'involucro JSON), così Kestrel rifiuta i corpi enormi prima del controllo del permesso.
- **Refresh in coda:** se il salvataggio riesce ma `QueueRefresh` lancia un errore, la chiamata resta riuscita (204): l'errore finisce in un `Warning` con il solo id dell'item.
- Il token di annullamento della richiesta arriva a ricerca e download. `ISubtitleManager.UploadSubtitle` di Jellyfin non ne ha uno, quindi un upload già partito non si interrompe.

### 6.5 `Info`

- Nuova funzione `reports`, in fondo a `WatchPartyProtocol.Features` (dopo `ratings`): `FeaturesWith` la include sempre, come le altre. Copre sia le segnalazioni sia gli endpoint sottotitoli. `Version` è "1.12.0", `Protocol` resta 1.
- Con un plugin senza `reports`, l'app nasconde "Segnala", il riquadro, la card e la finestra Sottotitoli. Gli strumenti admin che parlano solo con Jellyfin (§7.6–7.9) restano.

## 7. App 0.18.0

### 7.1 Nucleo

- **Permessi:**
  - `auth_models.dart` legge anche `Policy.EnableSubtitleManagement`;
  - un provider `canManageSubtitlesProvider` vale `isAdmin || enableSubtitleManagement`, e insieme a `reports` in `Info` decide se mostrare gli strumenti dei sottotitoli.
- **API:**
  - `reports_api.dart` per le segnalazioni;
  - `subtitles_api.dart` per i sottotitoli via plugin, più il `DELETE` diretto;
  - `item_edit_api.dart` per MetadataEditor, `POST /Items/{id}`, RemoteSearch, Apply, Refresh, RemoteImages, upload e ordine delle immagini.
- **Timeout:** Identifica: applica ha un timeout lungo, 3 minuti, perché Jellyfin risponde solo a fine refresh. Il resto usa quello normale.

### 7.2 Menu "⋯"

Un bottone "⋯" in `detail_header.dart`, dopo Preferito e Visto. Uno uguale su ogni riga di `_EpisodeList` e uno a destra di `_SeasonTabs` per la stagione selezionata (decisione 23).

| Voce | Chi | Dove |
|---|---|---|
| Segnala un problema | tutti (con `reports`) | film, serie, stagione, episodio |
| Info tecniche | tutti | film, episodio |
| Sottotitoli… | `canManageSubtitles` | film, episodio |
| Modifica metadati | admin | tutti e quattro |
| Identifica | admin | film, serie |
| Aggiorna metadati | admin | tutti e quattro |
| Locandina e sfondo | admin | tutti e quattro |

Le voci che non si possono usare non compaiono; se non ne resta nessuna, il bottone non c'è. Le voci sono separate in tre gruppi (tutti / sottotitoli / admin), come nella bozza.

### 7.3 Segnala un problema

Finestra `showWfDialog`, come nella bozza 2:

- **titolo** del contenuto (per un episodio: serie · SxEy "nome");
- **livello**, solo se aperta da un episodio o da una stagione: "Questo episodio", "Stagione N", "Tutta la serie". Da una stagione: "Questa stagione", "Tutta la serie";
- **tipo**: quattro chip, uno obbligatorio;
- **nota** facoltativa, al massimo 500 caratteri, con il contatore vicino al limite;
- se `GET Reports/Mine` ha già una segnalazione con quel tipo: la scritta "Hai già segnalato questo problema: puoi aggiornare la nota" e la nota precompilata;
- **Invia**, poi la conferma "Segnalazione inviata agli admin" (lo snackbar dell'app). Gli errori stanno nella finestra, che resta aperta.

### 7.4 Segnalazioni lato admin

- **Riquadro nel dettaglio** (bozza 3), solo per gli admin, sopra il contenuto del dettaglio di un film o di una serie.
  - Mostra le segnalazioni di `GET Reports` con quel `TitleId`, quindi in una serie anche quelle di stagioni ed episodi, con il livello scritto ("S2 E3", "Stagione 2", "Tutta la serie").
  - Ognuna ha: avatar e nome, tipo, nota, "Sistemato", "Non sistemabile" e la scorciatoia della decisione 11, scelta per livello come nella decisione 20 (sull'episodio o sulla stagione giusta).
  - "Sistemato" e "Non sistemabile" aprono una piccola finestra con la nota facoltativa e il bottone di conferma.
  - Se non ci sono segnalazioni, il riquadro non c'è.
- **Card "Segnalazioni"** in `wonderflix_tab.dart`: tutte le aperte, con titolo, livello, tipo, chi e quando. "Apri" porta al dettaglio. Se è vuota: "Nessuna segnalazione aperta".
- **Aggiornamento:** riquadro e card si ricaricano quando arriva `InboxChanged` (una `ReportPending` arriva o sparisce), dopo una chiusura e all'apertura.

### 7.5 Notifiche

- **`ReportPending`**:
  - testo: "**Nome** ha segnalato un problema", sotto titolo · livello · tipo;
  - al tocco apre il dettaglio di `TitleId`, con la stagione dell'episodio selezionata se possibile.
- **`ReportResolved`**:
  - "Problema sistemato su **Titolo**" oppure "Non è stato possibile sistemare **Titolo**", sotto la nota dell'admin tra virgolette, se c'è;
  - al tocco apre il dettaglio.
- Icone e colori come nella bozza 4.

### 7.6 Sottotitoli

Finestra (bozza 5), da "⋯ → Sottotitoli…", dalla scorciatoia del riquadro e dal pannello tracce del player.

- **Lingua:** menu con le lingue più comuni. All'inizio vale la lingua preferita dei sottotitoli dell'utente (`SubtitleLanguagePreference` della configurazione Jellyfin), altrimenti italiano. I codici sono ISO 639-2 a tre lettere (`ita`, `eng`…).
- **Cerca:** lista dei risultati.
  - Ognuno ha nome, provider, formato, voto, numero di download e le etichette "Sincronizzato col file" (`IsHashMatch`), "Per non udenti", "Forzati", "Tradotto automaticamente" (`MachineTranslated`, che il plugin ricava da `AiTranslated` o `MachineTranslated` di Jellyfin).
  - L'ordine: prima i sincronizzati, poi per download.
  - Lista vuota: "Nessun sottotitolo trovato", e se non c'è nessun provider lo dice il plugin con una lista vuota (accettato: stesso messaggio).
- **Scarica:**
  - mentre scarica la riga mostra una rotella; 502 dà "Download non riuscito";
  - poi l'app rilegge l'item ogni 2 s, per al massimo 20 s, finché compare una traccia esterna nuova. Se non compare: "Scaricato: la traccia comparirà tra poco".
- **Carica file…:** `file_selector` con `.srt .ass .ssa .vtt .sub`, al massimo 2 MiB (2 097 152 byte; il plugin controlla i byte decodificati). Lingua presa dal menu; "Forzati" e "Per non udenti" come caselle. Poi la stessa attesa di "Scarica".
- **Tracce presenti:** lingua, formato, esterna o nel file. Solo per l'admin e solo sulle esterne c'è "Elimina", con conferma (`wf_confirm_dialog`).
- **Dal player:**
  - in `tracks_panel.dart`, sotto i sottotitoli, "Cerca sottotitoli" apre la stessa finestra sul titolo in riproduzione;
  - quando la traccia nuova compare, il player rilegge `PlaybackInfo`. Se la traccia ha consegna esterna, la aggiunge fra le tracce caricandola da `deliveryUrl`, senza fermare la riproduzione e senza attivarla da sola. Altrimenti mostra il messaggio della decisione 21.

### 7.7 Info tecniche

Finestra con una sezione per ogni versione (`MediaSources`):

- contenitore, dimensione, durata, bitrate;
- **video:** codec, risoluzione, HDR/SDR, fps;
- **audio:** una riga per traccia (lingua, codec, canali, predefinita);
- **sottotitoli:** una riga per traccia (lingua, formato, esterno/nel file, forzati).

Il nome del file lo vede solo l'admin (decisione 17). Se l'item non ha già `MediaSources`, l'app lo rilegge con quel campo.

### 7.8 Modifica metadati (admin)

- **Campi:**
  - titolo, titolo originale, titolo per l'ordinamento, tagline (non per gli episodi), trama;
  - anno e data di uscita;
  - generi (chip con aggiunta e rimozione);
  - classificazione per età (menu da `ParentalRatingOptions` di `MetadataEditor`).
- **Salvataggio:**
  - l'app parte dall'item completo di `GET /Items/{id}` (con l'utente admin), cambia solo quei campi e manda indietro il DTO intero con `POST /Items/{id}`, come jellyfin-web;
  - ogni campo cambiato si aggiunge a `LockedFields`;
  - il lucchetto accanto a un campo lo sblocca o lo blocca;
  - poi l'app ricarica il dettaglio.
- **Errori:** nella finestra, che resta aperta.

### 7.9 Identifica (admin, film e serie)

- **Ricerca:** campi precompilati dall'item (nome, anno, id TMDb e IMDb; per le serie anche TVDB) e "Cerca", con `POST /Items/RemoteSearch/Movie|Series` e `ItemId`.
- **Risultati:** locandina (`ImageUrl`), nome, anno, provider, trama accorciata.
- **Scelta:**
  - una conferma: "Sostituire metadati e immagini con quelli di *Nome (anno)*?", con la casella "Sostituisci anche le immagini" (attiva di base) e, se l'item ha campi bloccati, la casella "Sblocca i campi modificati a mano" (decisione 19);
  - poi `Apply`, con una rotella e il testo "Può volerci qualche minuto";
  - alla fine l'app ricarica il dettaglio. Se scade il timeout: "Jellyfin sta ancora lavorando: ricarica tra poco".

### 7.10 Aggiorna metadati (admin)

Sottomenu con due voci:

- **"Cerca dati mancanti"**: `FullRefresh`, senza sostituire;
- **"Sostituisci tutti i metadati"**: `FullRefresh` + `replaceAllMetadata`, con la conferma e la casella "anche le immagini" (`replaceAllImages`).

Jellyfin le mette in coda. L'app mostra "Aggiornamento avviato" e ricarica il dettaglio dopo 10 s.

### 7.11 Locandina e sfondo (admin)

- **Due schede, Locandina e Sfondo**, con l'immagine attuale in alto. Stagioni ed episodi hanno una scheda sola (decisione 22).
- **Griglia** da `GET /Items/{id}/RemoteImages?type=Primary|Backdrop`:
  - ogni immagine ha anteprima (`ThumbnailUrl`), provider, risoluzione, lingua, voto;
  - si vedono la lingua dell'item e quelle senza lingua; la casella "Tutte le lingue" mostra le altre;
  - si caricano 30 immagini alla volta.
- **Scelta:**
  - "Usa come locandina" → `RemoteImages/Download?type=Primary`;
  - "Usa come sfondo" → download con `type=Backdrop`, poi l'app rilegge l'item e sposta lo sfondo nuovo (l'ultimo) all'indice 0 (decisione 16).
- **"Carica dal PC…":** `file_selector` con jpg e png, al massimo 10 MB, poi `POST /Items/{id}/Images/{type}` in base64. Per lo sfondo poi si sposta all'indice 0, come sopra.
- **Dopo ogni cambio:** l'app ricarica il dettaglio. Le immagini cambiano tag, quindi la cache delle immagini non serve quella vecchia.

### 7.12 Versione

App `0.18.0`, plugin `1.12.0`.

## 8. Senza plugin ed errori

- **Plugin senza `reports`**, o plugin assente: niente "Segnala", riquadro, card e Sottotitoli. Restano Info tecniche e gli strumenti admin diretti.
- **403 da Jellyfin o dal plugin**, per esempio un permesso tolto mentre l'app era aperta: "Non hai il permesso per farlo". L'app rilegge `/Users/Me`, così le voci spariscono.
- **Errore di rete:** il messaggio generico dell'app, e la finestra resta aperta con i dati inseriti.
- **Segnalazione già chiusa da un altro admin** (409 `Closed` su Resolve): "Questa segnalazione è già stata chiusa", e il riquadro si ricarica.

## 9. Testi nuovi (ARB, it + en)

Tutte le etichette, i messaggi e le notifiche di §7 e §8, in italiano e in inglese, con le chiavi che seguono le convenzioni dei file ARB esistenti. Il builder scrive l'inglese.

## 10. Sicurezza e privacy

- **La vera difesa sono i permessi lato server.** Il plugin controlla `IsAdmin` e `EnableSubtitleManagement` a ogni chiamata; Jellyfin controlla i suoi. Le voci nascoste nell'app servono solo a pulire l'interfaccia.
- **Visibilità:**
  - un utente non vede le segnalazioni degli altri;
  - `GET Reports/Mine` risponde solo con le proprie;
  - chi riceve `ReportResolved` vede la nota dell'admin, ma non il suo nome.
- **Note:** testo semplice, ripulito lato server (§6.1), mai interpretato come markup nell'app.
- **Upload:** limiti di dimensione e formato controllati dal plugin (sottotitoli) e dall'app (immagini; Jellyfin le accetta solo dagli admin).
- **Log:** id degli item, delle segnalazioni e degli utenti. Mai note, contenuto dei sottotitoli o percorsi dei file.

## 11. Test

### 11.1 Plugin (xUnit)

- **Archivio:** caricamento, scrittura atomica, `.bad`, pulizia (utenti e titoli spariti, pausa durante la scansione).
- **Segnalazioni:**
  - creazione valida;
  - tipo non valido; titolo di tipo non ammesso o non visibile;
  - nota ripulita e troppo lunga;
  - doppione che aggiorna senza riavvisare;
  - limite di 20.
- **Notifiche:**
  - `ReportPending` solo agli admin `UserRef.IsAdmin` tranne chi segnala;
  - Resolve toglie la segnalazione e le `ReportPending` di tutti gli admin, e manda `ReportResolved`, ma non se chi chiude ha segnalato;
  - 409 `Closed` su una già chiusa, e una sola `ReportResolved` se due admin chiudono insieme;
  - nessun 404; la chiave API: 400 su `POST Reports` e `GET Reports/Mine`, 403 sui sottotitoli;
  - un non admin su `GET Reports` o Resolve riceve 403.
- **Sottotitoli:**
  - 403 senza permesso; ammesso con la sola spunta e con il solo admin;
  - un errore di download diventa 502;
  - upload: base64 non valido, troppo grande, formato non ammesso;
  - refresh in coda dopo download e upload.
- **`Info`** espone `reports`.

### 11.2 App

- **Menu "⋯":** le voci giuste per ruolo × livello (tabella §7.2); bottone assente senza voci.
- **Segnala:** livelli da episodio e stagione, tipo obbligatorio, nota precompilata dal doppione, errore che lascia la finestra aperta.
- **Riquadro e card:** filtro per `TitleId`, chiusura con nota, 409 `Closed` gestito, ricarica su `InboxChanged`.
- **Notifiche:** testo e navigazione delle due voci nuove.
- **Sottotitoli:** ordinamento dei risultati, attesa della traccia nuova (compare / non compare entro 20 s), 502, Elimina solo per l'admin e solo sulle esterne.
- **Editor metadati:** solo i campi cambiati finiscono in `LockedFields`; il DTO mandato è quello completo.
- **Sfondo:** dopo il download, lo spostamento all'indice 0 usa l'indice giusto.
- **Senza `reports`:** le voci sono nascoste.

### 11.3 Prova a mano

Sul server vero, con l'admin e due utenti di prova, uno con la spunta sottotitoli:

1. Un utente segnala un episodio. Gli admin ricevono la notifica, l'utente con la spunta no.
2. L'admin apre la notifica, usa "Cerca sottotitoli", scarica un sottotitolo italiano e la traccia compare. "Sistemato" con nota: la notifica arriva all'utente.
3. L'utente con la spunta cerca e scarica dal player senza fermarsi, e non vede le voci admin.
4. L'admin reidentifica un film; modifica un titolo, aggiorna i metadati e verifica che il titolo bloccato resti; cambia locandina e sfondo.
5. "Non sistemabile" con nota: arriva la notifica giusta.

## 12. Da verificare sul sorgente di Jellyfin 10.11.9

**Verificato per il piano 24a** (sorgente al tag `v10.11.9`; il plugin si compila contro la 10.11.0 e le firme sono le stesse):

- **Firme:** `SearchSubtitles(Video, string language, bool? isPerfectMatch, bool isAutomated, CancellationToken)`, `DownloadSubtitles(Video, string subtitleId, CancellationToken)` e `UploadSubtitle(Video, SubtitleResponse)`. L'ultima **non ha un `CancellationToken`**. `SearchSubtitles` risponde con un array vuoto per tipi diversi da `Movie` e `Episode`.
- **`DownloadSubtitles` rilancia l'errore** quando il provider fallisce (anche `RateLimitExceededException`). Il 204 sempre di Jellyfin viene da `SubtitleController`, che inghiotte l'eccezione. Quindi il 502 `DownloadFailed` si ricava dall'eccezione, senza contare le tracce.
- **`UploadSubtitle`** lancia `ArgumentException` per un formato che Jellyfin non ammette (non in `NamingOptions.SubtitleFileExtensions`): diventa 502 `UploadFailed`.
- **Refresh:** `SubtitleController` dopo download e upload fa `IProviderManager.QueueRefresh(item.Id, new MetadataRefreshOptions(new DirectoryService(fileSystem)), RefreshPriority.High)`. Il plugin lo copia identico.
- **`RemoteSubtitleInfo`:** `CommunityRating` (`float?`), `DownloadCount` (`int?`) e `IsHashMatch`, `AiTranslated`, `MachineTranslated`, `Forced`, `HearingImpaired` (`bool?`).
- **`PermissionKind.EnableSubtitleManagement`** esiste con questo nome, valore 22.

**Ancora aperto** (piani 24b e 24c):

- Che `RemoteImages/Download` di un `Backdrop` aggiunga lo sfondo in fondo, e che `Images/Backdrop/{index}/Index` sposti come previsto.
- Che `POST /Items/{id}` con il DTO letto da `GET /Items/{id}?userId=` non sporchi i dati utente, e quali campi servono perché `LockedFields` venga salvato.
- Che i dati di `MediaSources.Path` arrivino ai non admin: se sì, l'app non li mostra (decisione 17); se no, l'admin vede il nome del file.

## 13. Piani e release

- **24a, plugin 1.12.0 (realizzato):** archivio, endpoint, cassetta, sottotitoli, `Info`. Il plugin 1.12.0 resta **build di prova** sul server fino alla fine del 24b: la release arriva con l'app.
- **24b, app (segnalazioni e sottotitoli):** nucleo, menu "⋯", Segnala, riquadro e card, notifiche, Sottotitoli (anche dal player), Info tecniche.
- **24c, app (strumenti admin):** Modifica metadati, Identifica, Aggiorna, Locandina e sfondo.
- **Release:** plugin 1.12.0, poi app 0.18.0 dopo la prova a mano. Obbligatoria o no si decide al rilascio: l'app funziona anche con il plugin 1.11.0, solo senza segnalazioni e sottotitoli.
