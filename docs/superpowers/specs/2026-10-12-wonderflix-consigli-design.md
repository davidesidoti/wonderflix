# WonderFlix — Spec N: consigli tra amici

- **Data:** 2026-10-12
- **Stato:** approvata il 2026-10-12; piano 20a realizzato (`docs/superpowers/plans/2026-10-12-wonderflix-20a-consigli-plugin.md`), build di prova installata sul server il 2026-10-12 alle 21:06 UTC; piano 20b da scrivere.
- **Ambito:** Spec N. Realizza l'idea 6 di `docs/IDEE.md` ("Consigli tra amici"): dal dettaglio di un film o di una serie si consiglia il titolo a uno o più amici, con un messaggio breve; il consiglio arriva nella loro cassetta delle notifiche e nella riga "Consigliati per te" della Home.

## 1. Obiettivo

- **Consiglia a…** Nel dettaglio di un film o di una serie un pulsante apre un pannello: si scelgono uno o più amici, si scrive un messaggio facoltativo e si invia.
- **Nella cassetta.** Chi riceve trova la voce "Luca ti consiglia *Dune*" con il messaggio; un clic apre il dettaglio.
- **Nella Home.** La riga "Consigliati per te" raccoglie i titoli consigliati, con chi li ha consigliati. Un titolo esce dalla riga quando lo si guarda, quando si sceglie "Non mi interessa" o dopo 60 giorni.

Nota sul modello: non è un sistema di consigli automatici (Jellyfin non ne ha). Sono consigli scritti da una persona a un'altra, solo tra amici di WonderFlix (Spec F).

## 2. Situazione di partenza

App 0.13.0, plugin 1.7.0, Jellyfin 10.11.9 su Ultra.cc.

- **Amici** (Spec F): `FriendGraph`/`FriendService` nel plugin, `friends.json`; pannello Amici nell'app.
- **Cassetta** (Spec G e successive): `inbox.json`, voci per tipo (`Invite`, `Announcement`, `NewTitles`, `RequestAvailable`, `RequestPending`, `ContactReminder`), avviso `InboxChanged`, pannello laterale 360 px nell'app (`ShellSidePanel`). L'app 0.13.0 scarta le voci di tipo sconosciuto (`inboxEntryFromJson` → `null`) e conta le non lette solo tra quelle che mostra.
- **Permessi:** `ILibraryAccess.CanSee(userId, itemId)` controlla librerie e limiti d'età del profilo, anche per chi è offline.
- **Serie seguite:** `ILibraryTitles.FollowsSeries` (Spec G §6.6) sa già se un utente ha episodi visti o iniziati di una serie.
- **Home** (Spec M): righe con id stabili (`HomeRowIds.Known` nel plugin, `HomeRowKind` nell'app), Home dell'admin in `PluginConfiguration.HomeRows`, ritocchi dell'utente nelle `DisplayPreferences`, motivi delle righe non disponibili (`HomeRowGate`).
- **Niente dialog** nell'app: le scelte stanno in menu e pannelli laterali.

## 3. Decisioni

Prese con l'utente nel brainstorming del 2026-10-12:

1. **Cassetta e riga Home**, tutte e due in questo spec.
2. **Uscita dalla riga:** il titolo è stato visto dopo il consiglio, oppure "Non mi interessa", oppure sono passati 60 giorni.
3. **Più mittenti, una card:** due amici che consigliano lo stesso titolo danno una card sola ("Da Luca e Marta"), con i messaggi di tutti. Lo stesso amico che riconsiglia aggiorna il suo messaggio e la data. Nella cassetta una voce per mittente.
4. **Amico che non può vedere il titolo** (libreria o limite d'età): nel pannello compare spento con "Non può vederlo".
5. **Nessun extra:** solo film e serie, solo dal dettaglio; niente consigli dall'anteprima delle card, niente avviso al mittente quando l'amico guarda, niente consigli dagli episodi.
6. **Archivio proprio nel plugin** (`recommendations.json`, approccio A): la riga non dipende dalla cassetta, che si svuota e tiene le voci solo 30 giorni.

## 4. Perimetro

### Incluso

- Plugin 1.8.0: archivio, endpoint, voce `Recommendation` nella cassetta, limite di frequenza, funzione `recommendations` in `Info`, id di riga `recommended`.
- App 0.14.0: pulsante e pannello "Consiglia a…", riga "Consigliati per te", messaggi e "Non mi interessa" nell'anteprima delle card della riga, voce nella cassetta, testi it/en.

### Escluso

- Consigli di episodi, stagioni, saghe, persone.
- Consigli a chi non è amico.
- Elenco dei consigli inviati, avviso al mittente.
- Risposte o reazioni a un consiglio.
- Moderazione dei messaggi dalla dashboard admin.

## 5. Architettura

```
App (dettaglio) ──POST Recommendations──▶ Plugin ──▶ recommendations.json
                                            ├──▶ inbox.json (voce Recommendation) ──InboxChanged──▶ app dell'amico
App (Home) ──GET Recommendations──▶ Plugin (filtra: 60 gg, CanSee, amicizia, visto)
App (card) ──DELETE Recommendations/{itemId}──▶ Plugin
```

- Il plugin tiene i consigli per destinatario e decide cosa è ancora valido (§6.3): ha i dati utente di tutti, i permessi e il grafo degli amici.
- L'app legge gli elementi da Jellyfin (`/Items?Ids=…`) per le card, come per le altre righe: Jellyfin applica di nuovo i permessi.

## 6. Plugin 1.8.0

### 6.1 Archivio

- File `recommendations.json` in `<PluginConfigurationsPath>/WonderFlixWatchParty/`, accanto a `inbox.json`.
- Contenuto: `{"Version": 1, "Users": {"<toUserId>": [{"ItemId": "…", "From": [{"UserId": "…", "Message": "…", "CreatedAt": "…"}]}]}}`. Id in formato `N`, date ISO-8601 UTC, `Message` assente se vuoto.
- Stesse regole di `InboxStore`: caricato all'avvio, ogni modifica riscrive il file in modo atomico sotto un lock, file illeggibile rinominato in `recommendations.json.bad` (riga `Warning`) e si riparte vuoti; se la rinomina fallisce si riparte vuoti lo stesso. La lettura all'avvio ha il suo `try/catch`, separato dagli altri archivi.
- **Riconsiglio:** se il destinatario ha già il titolo con lo stesso mittente, si aggiornano `Message` (anche togliendolo) e `CreatedAt`; altrimenti il mittente si aggiunge.
- **Tetto:** al massimo 50 titoli per destinatario; oltre si toglie quello con l'ultimo `CreatedAt` più vecchio.
- **"Data" di un titolo:** il `CreatedAt` più recente tra i suoi mittenti. Serve all'ordine (più recente prima), al tetto e ai 60 giorni.

### 6.2 Endpoint (sotto `/WonderFlixWatchParty`)

`RecommendationsController` con la stessa policy di `FriendsController` (accesso a SyncPlay, come gli amici). Chi chiama si ricava dal token. Il plugin **non risponde mai 404**; l'id in `DELETE` è una stringa senza vincoli di rotta.

| Metodo e percorso | Corpo / risposta |
|---|---|
| `GET Recommendations/Targets?itemId=` | `{Friends: [{UserId, Name, Online, CanSee}]}`: gli amici attivi (non disabilitati) di chi chiama, per nome; l'app li riordina (online prima); 400 se l'elemento non c'è, non è un film o una serie, o chi chiama non lo vede |
| `POST Recommendations` `{ItemId, To: [...], Message}` | `{Sent}`; vedi sotto |
| `GET Recommendations` | `{Items: [{ItemId, From: [{UserId, Name, Message, CreatedAt}]}]}`: i consigli validi di chi chiama (§6.3), titolo più recente prima, mittenti più recente prima |
| `DELETE Recommendations/{itemId}` | 204, anche se il titolo non c'è ("Non mi interessa") |

**`POST Recommendations`:**
- 400 se: l'elemento non esiste, non è un film o una serie, chi chiama non lo vede; il messaggio, senza spazi ai bordi, supera 200 punti di codice; `To` è vuoto o ha più di 50 id.
- Il messaggio è testo semplice: gli a capo, ogni altro carattere di controllo (tab, ...) e U+2028/U+2029 diventano spazi, le righe vuote spariscono, gli spazi ai bordi si tolgono. Vuoto dopo la pulizia vale come nessun messaggio.
- La lunghezza si conta in punti di codice, come gli annunci: 200 emoji passano.
- Si saltano **in silenzio** gli id che non sono amici di chi chiama, gli utenti disabilitati o inesistenti, chi non può vedere l'elemento (`CanSee`), chi chiama stesso, i doppioni. `Sent` è il numero dei destinatari a cui il consiglio è arrivato.
- **Limite:** `LimitTypes.Recommendations`, 30 destinatari all'ora per mittente (come `Invites`, ogni destinatario valido conta). Tutto o niente: se i destinatari validi superano quanto resta, 429 e niente viene salvato.
- **`To` e limite:** `To` accetta fino a 50 id, ma i destinatari sono al massimo 30 all'ora: più di 30 destinatari validi in una richiesta danno sempre 429. L'app (piano 20b) limita la scelta nel pannello a quanto resta della quota, al massimo 30.
- **Errori della libreria:** se Jellyfin lancia in `Targets` o in `POST` la risposta è 500; solo `GET` tiene i titoli (§6.3).
- Per ogni destinatario: archivio (§6.1), voce nella cassetta (§6.4), `InboxChanged` alle sue sessioni. Un errore nella cassetta o nell'avviso va nel log (`Warning`) e non cambia la risposta.

### 6.3 Cosa è valido (filtro a lettura)

A ogni `GET Recommendations` e alla pulizia periodica, per il destinatario:

1. **Mittenti:** si toglie un mittente che non esiste più o non è più amico. Un titolo senza mittenti esce.
2. **60 giorni:** esce il titolo la cui data (§6.1) ha più di 60 giorni.
3. **Permessi:** esce il titolo che il destinatario non può più vedere (`CanSee` falso, anche se l'elemento non esiste più).
4. **Visto dopo il consiglio:** esce il titolo che il destinatario ha guardato **dopo** la data del titolo:
   - **film:** `LastPlayedDate` dei suoi dati utente successiva alla data (visto o iniziato);
   - **serie:** almeno un episodio con `LastPlayedDate` successiva alla data (nuovo metodo su `ILibraryTitles`, una domanda per serie: episodi della serie ordinati per data di visione, il primo).
   Così un titolo già visto prima del consiglio resta nella riga finché non lo si riguarda, e un nuovo consiglio dopo una visione rimette il titolo nella riga.

Quello che esce si toglie dall'archivio (salvataggio solo se qualcosa è cambiato). Come si toglie:
- **Fuori dal lock:** `GET` legge i titoli sotto lock, fa le domande alla libreria fuori dal lock e poi toglie un titolo solo se il suo consiglio più recente è ancora quello controllato. Un amico che riconsiglia nel frattempo non perde il consiglio.
- **Mittenti persi:** si tolgono solo se il loro `CreatedAt` è ancora quello controllato (un mittente che torna amico e riconsiglia nel frattempo resta).
- **Errore della libreria in `GET`:** se `CanSee` o la domanda sulle visioni lanciano per un titolo, il titolo resta (`Warning`) e la risposta arriva lo stesso.
- **Pulizia periodica:** sta in `RecommendationsHostedService` (non in `WatchPartyHostedService`), ogni 5 minuti con il suo `try/catch`. Controlla solo mittenti (non esistono più o non sono più amici), i 60 giorni e i destinatari che non esistono più. Permessi (`CanSee`) e "visto" li controlla solo `GET`: sono domande alla libreria per ogni titolo di ogni utente, e conta solo quello che l'utente vede.
- **"Visto":** `LastPlayedDate` come sopra. Verificato sul sorgente di Jellyfin 10.11.9: `ItemSortBy.DatePlayed` ordina per `LastPlayedDate` dell'utente della query; `MarkPlayed` senza data tiene la data che c'era, altrimenti mette adesso. Quindi "segna come visto" di un titolo mai visto lo toglie dalla riga; di un titolo già visto prima del consiglio no (accettato).

### 6.4 Voce nella cassetta

Nuovo tipo `InboxEntryTypes.Recommendation`, campi propri: `ItemId` (film o serie, anche per la locandina), `FromName`, `Title` (nome dell'elemento, con l'anno se c'è: "Dune (2021)"), `Text` (il messaggio; assente se vuoto).

- **Una voce per mittente e titolo:** se il destinatario ha già una voce `Recommendation` con lo stesso mittente e lo stesso `ItemId`, si aggiorna (`FromName`, `Title`, `Text`, `CreatedAt`, `Read = false`, nuovo `Seq`). Per riconoscere il mittente la voce tiene anche `FromUserId`.
- La voce segue le regole della cassetta (30 giorni, 100 voci, Svuota) e non dipende dall'archivio: "Non mi interessa" non la toglie, e svuotare la cassetta non tocca la riga.

### 6.5 Limiti e log

- `LimitTypes.Recommendations`: 30 destinatari all'ora per mittente (§6.2).
- Log come il resto del plugin: **mai titoli, messaggi o nomi**, solo id e numeri. `Debug` per consiglio salvato (n destinatari) e per ogni lettura che toglie qualcosa: mittenti e titoli tolti, più quanti titoli erano da togliere per ogni motivo (oltre 60 giorni, non visibili, visti); `Warning` per file illeggibile, errori di scrittura, errori della cassetta.

### 6.6 `Info`

`Features` aggiunge `"recommendations"`. `Protocol` resta 1. `Version` "1.8.0".

### 6.7 Riga della Home

- `HomeRowIds.Known` aggiunge `"recommended"`, subito dopo `"nextUp"` (ordine predefinito, §7.3). `HomeRowIds.AddedLater` elenca le righe nate dopo la 1.7.0 (per ora solo `recommended`).
- **Home dell'admin già salvata:** `HomeRows` contiene solo le righe accese, quindi una riga nuova risulterebbe spenta per tutti. All'avvio (`RecommendationsHostedService`) con il plugin 1.8.0, se `HomeRowsSeen` non contiene `recommended`, il plugin accende `recommended` (se `HomeRows` non è `null`) e la scrive in `HomeRowsSeen`:
  - posizione: subito dopo l'ultima riga accesa che la precede nell'ordine predefinito (`resume`, `nextUp`); se nessuna delle due è accesa, in testa (la stessa regola di Spec M §6.4);
  - una volta sola: se poi l'admin la spegne, resta spenta;
  - con `HomeRows` `null` non serve accenderla (vale l'ordine predefinito, che la contiene già): si segna solo vista. Se poi l'admin salva la sua Home con l'app 0.14.0 e la spegne, al riavvio dopo non torna accesa.
  - `HomeRowsSeen` è una stringa di id separati da virgole: le righe nuove delle versioni future useranno lo stesso meccanismo.

## 7. App 0.14.0

### 7.1 Nucleo

- `lib/core/social/`: modelli `Recommendation` (`itemId`, `from: [RecommendationSender{userId, name, message?, createdAt}]`), `RecommendationTarget` (`userId`, `name`, `online`, `canSee`); voce `RecommendationEntry` in `inbox_models.dart`.
- `SocialApi`: `recommendationTargets(itemId)`, `recommend(itemId, to, message)`, `recommendations()`, `dismissRecommendation(itemId)`; stessi in `FakeSocialApi`.
- `SocialFeatures.recommendations` (funzione `recommendations` del plugin).

### 7.2 Pulsante e pannello "Consiglia a…"

- **Pulsante** "Consiglia a…" (icona Lucide `send`) nella fila dei pulsanti del dettaglio di film e serie, dopo La mia lista. Compare solo con la funzione `recommendations` e almeno un amico. Non c'è nel dettaglio degli episodi.
- Apre un **pannello laterale** a destra, 360 px, nello stesso `ShellSidePanel` di Amici e Cassetta (uno alla volta; Esc e clic fuori chiudono, come gli altri):
  - in alto locandina piccola e titolo dell'elemento;
  - elenco degli amici (`GET Recommendations/Targets`) con una casella ciascuno, online prima, poi per nome; quelli con `CanSee` falso sono spenti con "Non può vederlo";
  - campo del messaggio, facoltativo, al massimo 200 caratteri con contatore; Invio non va a capo (il plugin toglie comunque gli a capo), il testo lungo va a capo da solo nel campo;
  - **Invia** (spento finché nessun amico è scelto e durante l'invio).
- **Esito:** il pannello si chiude e un avviso dice "Consiglio inviato" (o "Consiglio inviato a N amici"). Con 429 l'avviso è "Troppi consigli: riprova più tardi" e il pannello resta aperto; con un altro errore "Consiglio non inviato" e il pannello resta aperto. Se `Sent` è 0 (tutti saltati dal plugin) l'avviso è "Consiglio non inviato".
- Elenco che non si carica: messaggio d'errore e "Riprova" nel pannello.

### 7.3 Riga "Consigliati per te"

- `HomeRowKind.recommended('recommended')`, dopo `nextUp`; non viene da Jellyfin (`fromJellyfin` falso, come `requests`).
- `homeRowGate`: senza la funzione `recommendations` → nuovo motivo `HomeRowGate.recommendationsOff` ("Serve il plugin WonderFlix 1.8.0 o più recente").
- Caricamento: `GET Recommendations`, poi gli elementi da Jellyfin per id (con dati utente e immagini, come le altre righe di locandine), nell'ordine del plugin. Gli id che Jellyfin non restituisce si saltano. Riga vuota → non si vede.
- **Card:** locandina come "La mia lista"; sotto il titolo la riga "Da Luca", "Da Luca e Marta", "Da Luca e altri 2" (nomi in ordine di consiglio più recente).

### 7.4 Anteprima delle card della riga

Solo per le card di questa riga, nell'anteprima che si apre al passaggio del mouse (Spec C §7):

- sotto la trama, fino a 3 messaggi "Luca: «da vedere stasera»" (un mittente senza messaggio non compare qui); testo su una riga con ellissi;
- pulsante **"Non mi interessa"** (icona `x`): `DELETE Recommendations/{itemId}`, l'anteprima si chiude e la card esce dalla riga con l'animazione delle righe. Se la chiamata fallisce la card resta e un avviso dice "Non riuscito: riprova".

### 7.5 Voce nella cassetta

- Locandina dell'elemento, "**Luca** ti consiglia *Dune (2021)*", sotto il messaggio se c'è, la data relativa come le altre voci.
- Clic → dettaglio dell'elemento (il pannello si chiude).
- Elemento che Jellyfin non restituisce più all'utente: voce grigia con "Non disponibile", senza clic.

### 7.6 Dal vivo

- La cassetta si rilegge con `InboxChanged`, come oggi.
- La riga si rilegge a ogni apertura della Home e dopo "Non mi interessa"; nessun avviso dedicato.

## 8. Senza plugin ed errori

- **Plugin senza `recommendations`** (< 1.8.0): niente pulsante, riga non disponibile con il motivo, nessuna chiamata.
- **`GET Recommendations` fallisce:** la riga non si vede, riga di log `warning` (solo il tipo dell'errore); le altre righe non ne risentono.
- **Permessi cambiati fra apertura del pannello e invio:** il plugin salta il destinatario (§6.2); se chi consiglia non vede più l'elemento, 400 → "Consiglio non inviato".
- **Amico rimosso:** sparisce dalla card e dai messaggi alla lettura successiva; se era l'unico mittente la card esce.
- **App 0.13.0 con plugin 1.8.0:** le voci `Recommendation` sono scartate e non contano tra le non lette; la riga `recommended` è un id sconosciuto e si ignora (Spec M §6.3). Quasi nessun effetto, quindi l'app 0.14.0 può essere **non obbligatoria**. Due differenze:
  - le voci `Recommendation` nascoste contano comunque nel tetto di 100 voci della cassetta;
  - se l'admin modifica la Home con l'app 0.13.0, l'id `recommended` sconosciuto cade; poiché `HomeRowsSeen` c'è già, la riga resta spenta finché non si riaccende con la 0.14.0.

## 9. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `recommendButton` | Consiglia a… | Recommend to… |
| `recommendPanelTitle` | Consiglia a… | Recommend to… |
| `recommendCannotSee` | Non può vederlo | Can't watch it |
| `recommendMessageHint` | Aggiungi un messaggio (facoltativo) | Add a message (optional) |
| `recommendSend` | Invia | Send |
| `recommendSent` | Consiglio inviato | Recommendation sent |
| `recommendSentMany` | Consiglio inviato a {count} amici | Recommendation sent to {count} friends |
| `recommendNotSent` | Consiglio non inviato | Recommendation not sent |
| `recommendRateLimited` | Troppi consigli: riprova più tardi | Too many recommendations: try again later |
| `recommendTargetsError` | Impossibile caricare gli amici | Couldn't load your friends |
| `homeRowRecommended` | Consigliati per te | Recommended for you |
| `recommendedFromOne` | Da {name} | From {name} |
| `recommendedFromTwo` | Da {first} e {second} | From {first} and {second} |
| `recommendedFromMany` | Da {name} e altri {count} | From {name} and {count} others |
| `recommendDismiss` | Non mi interessa | Not interested |
| `recommendDismissFailed` | Non riuscito: riprova | Didn't work: try again |
| `inboxRecommendation` | {name} ti consiglia {title} | {name} recommends {title} |
| `homeGateRecommendationsOff` | Serve il plugin WonderFlix 1.8.0 o più recente | Needs WonderFlix plugin 1.8.0 or newer |

"Riprova" e "Non disponibile" ci sono già. I testi non danno per scontato il genere di nessuno.

## 10. Sicurezza e privacy

- Si consiglia solo agli amici; il plugin ricontrolla l'amicizia a ogni invio e a ogni lettura.
- Un consiglio non svela a chi lo riceve niente che non possa già vedere (`CanSee` all'invio e a ogni lettura).
- A chi consiglia, "Non può vederlo" rivela solo che quel titolo non è accessibile a quell'amico (scelta dell'utente, §3.4). Nessun dato sulle visioni dell'amico arriva al mittente.
- I messaggi sono testo semplice, mai interpretati come markdown o link; non vanno nei log.
- Il `Title` della voce nella cassetta è fissato all'invio: dopo un cambio di permessi può restare fino a 30 giorni (come le voci `RequestAvailable`).

## 11. Test

### 11.1 Plugin (xUnit)

- Archivio: riconsiglio (aggiorna, non duplica), più mittenti, tetto 50, file illeggibile → `.bad`, rinomina non riuscita.
- Filtro (§6.3): 60 giorni sulla data più recente, `CanSee` falso, mittente non più amico (solo lui / l'unico), film visto prima e dopo il consiglio, serie con episodio iniziato prima e dopo.
- `POST`: 400 (elemento mancante, episodio, non visibile a chi chiama, messaggio lungo, `To` vuoto o > 50), destinatari saltati in silenzio, `Sent`, 429 senza salvataggi, voce della cassetta creata e aggiornata, errore della cassetta che non cambia la risposta.
- `Targets`, `DELETE` (anche di un titolo assente), mai 404.
- `HomeRowIds` con `recommended`; inserimento una volta sola nella Home dell'admin (`HomeRowsSeen`), anche con `nextUp` spenta, e niente con `HomeRows` null.
- Controllo dei riferimenti della dll contro Jellyfin 10.11.9 (come per le versioni passate).

### 11.2 App

- Modelli e lettura del JSON, voce `Recommendation` della cassetta, voce sconosciuta ancora scartata.
- Pannello: elenco, spenti, contatore, Invia spento, esiti (inviato, 429, errore, `Sent` 0), errore dell'elenco e Riprova, Esc.
- Riga: gate, ordine, elementi mancanti saltati, riga vuota nascosta, testi "Da …".
- Anteprima: messaggi (max 3, senza messaggio esclusi), "Non mi interessa" riuscito e non riuscito.
- Pulsante nel dettaglio: solo film e serie, solo con la funzione e con amici.

### 11.3 Prova a mano

Due istanze (`WONDERFLIX_PROFILE=b`) con due utenti amici; un terzo utente con un limite d'età per provare "Non può vederlo". Consiglio con e senza messaggio, riconsiglio, due mittenti, visione e uscita dalla riga, "Non mi interessa", cassetta.

## 12. Rischi e punti da verificare

- **"Visto dopo il consiglio" per le serie:** verificato sul sorgente di Jellyfin 10.11.9 (piano 20a): `InternalItemsQuery` con `AncestorIds` = la serie, `OrderBy` `DatePlayed` decrescente e `Limit` 1 dà l'episodio visto più di recente, senza leggerli tutti.
- **`LastPlayedDate` con "segna come visto":** verificato sul sorgente (piano 20a): `MarkPlayed` senza data tiene la data che c'era, altrimenti mette adesso. Un titolo già visto prima del consiglio e segnato visto a mano dopo resta nella riga finché non si sceglie "Non mi interessa" (accettato).
- **App 0.13.0 e voce nuova:** verificato nel codice (`inboxEntryFromJson` restituisce `null`); da riprovare sul server con la build di prova.

## 13. Piani e release

- **20a — plugin 1.8.0 (realizzato):** verifiche di §12, archivio, filtro, endpoint, voce della cassetta, limite, `Info`, riga `recommended` e inserimento nella Home dell'admin; build di prova installata a mano sul server il 2026-10-12 (stop → copia → start quando nessuno guardava; la 1.7.0 del Catalogo in `~/wfwp-backup/1.7.0.0-catalogo`, la configurazione in `~/wfwp-backup/config-1.7.0-prima-20a.xml`): `Info` 1.8.0 con `recommendations`, `HomeRowsSeen` = `recommended` con `HomeRows` non impostata. Resta fino alla fine del 20b. Nessuna release.
- **20b — app 0.14.0:** nucleo, pannello, riga, anteprima, cassetta, testi; prova con l'utente.
- **Release** (con l'OK dell'utente a ogni passo): plugin **1.8.0** dal Catalogo (tag `watch-party-plugin-v1.8.0`, voce nel manifest, la build di prova spostata in `~/wfwp-backup/`), poi app **0.14.0 non obbligatoria** con le note in italiano nella bozza.
- **Alla fine**, in `docs/IDEE.md`: l'idea 6 esce dalla lista e tra le fatte c'è "Spec N — consigli tra amici (plugin 1.8.0, app 0.14.0)".
