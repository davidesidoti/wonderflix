# WonderFlix — Spec B: watch party (visione sincronizzata)

- **Data:** 2026-09-30
- **Stato:** approvato in brainstorming, in attesa di revisione finale
- **Ambito:** Spec B di 2. Si appoggia allo Spec A (`2026-09-29-wonderflix-client-core-design.md`), già realizzato (v0.1.2).

## 1. Obiettivo

Guardare film ed episodi insieme, ognuno dal proprio PC, restando sincronizzati, senza i difetti dei client Jellyfin attuali:

- il video non deve **mai** muoversi senza un motivo visibile: ogni pausa, ripresa, salto o cambio di episodio compare come avviso;
- durante la visione lo scarto si corregge con **piccole variazioni di velocità**, non con salti;
- creare un gruppo o entrarci deve richiedere un clic, con un avviso per gli inviti.

### Da dove vengono i difetti attuali

Dall'analisi di jellyfin-web (`src/plugins/syncPlay/`) e del server Jellyfin 10.11 (`MediaBrowser.Controller/SyncPlay/GroupStates/`):

| Comportamento lamentato | Causa |
|---|---|
| Il video "va avanti da solo" | SpeedToSync di jellyfin-web recupera tutto lo scarto in 1 s: velocità = 1 + scarto/1000, cioè fino a **3,9×** per 2,9 s di scarto. |
| Il video "torna indietro da solo" | Il comando `Pause` riporta tutti alla posizione del gruppo, quindi chi era più avanti torna indietro. SkipToSync salta sopra i 400 ms. Sui comandi `Seek` doppi, jellyfin-web aggiunge uno scarto casuale di ±50 ms e rifà il salto. |
| Pause e ripartenze frequenti | Ogni `Buffering` di un membro, frequente per chi è in transcodifica, porta il gruppo in `Waiting` e manda `Pause` a tutti. |

Il server resta quello: SyncPlay di Jellyfin. La differenza la fa il client, con la correzione dello scarto, la gestione dei comandi e i messaggi mostrati.

## 2. Decisioni

| Tema | Decisione |
|---|---|
| Client nel gruppo | Solo WonderFlix. Una futura versione web userà la stessa logica, quindi la parte di sincronizzazione è in **Dart puro**, senza `dart:io`. Gruppi misti con jellyfin-web: non supportati né provati. |
| Chi controlla | **Tutti**: pausa, ripresa, salto, episodio, salta intro. Ogni azione produce un avviso visibile a tutti. |
| Chi ha fatto l'azione | L'avviso è **anonimo** ("Salto a 32:10"). Il server non dice chi ha mandato un comando, e un utente non amministratore non vede le sessioni degli altri. Chi agisce vede "Hai saltato a 32:10". Il modello dell'avviso ha un campo "chi" facoltativo, per un futuro canale (plugin del server). |
| Buffering | **Si aspettano tutti** (comportamento del server). Il client segnala il buffering solo dopo **1 s** continuo. Chiunque può premere "Riprendi senza aspettare". |
| Correzione dello scarto | Da fermi: allineamento esatto. Durante la visione: zona morta ±150 ms, velocità 0,95×/1,05×, salto solo sopra i **3 s**. Dettagli in §4.4. |
| Creare | "Guarda insieme" nei dettagli (film, episodio, serie) e nei controlli del player. |
| Entrare | Pulsante "Watch party · N" nella barra in alto e avviso d'invito quando nasce un gruppo. |
| Player | Distintivo "Watch party · N" nei controlli, che apre il pannello dei membri. Con i controlli nascosti si vedono solo il video e gli avvisi. |
| Serie | La coda del gruppo contiene l'episodio e i successivi. Il prossimo episodio parte per tutti. Il salto automatico dell'intro è spento in gruppo. |
| Chiudere il player | Esce solo chi chiude (`Leave`), gli altri continuano. Il gruppo sparisce quando esce l'ultimo. |
| Impostazioni personali | Volume, tracce audio, sottotitoli e ritardo restano personali. Ognuno riceve lo stream adatto a lui (diretto o transcodifica). |

## 3. Perimetro

### Incluso

- Creare un gruppo, entrare, uscire; elenco dei gruppi; avviso d'invito.
- Pausa, ripresa, salto, prossimo episodio e salta intro sincronizzati.
- Stima dell'orologio del server e correzione dello scarto.
- Attesa comune durante il buffering, con "Riprendi senza aspettare".
- Rientro automatico dopo una caduta della connessione.
- Avvisi, pannello dei membri, schermata di attesa.
- Discord Rich Presence con lo stato "Watch party · N persone".
- Seconda istanza per le prove in sviluppo (§7.2).

### Escluso (idee future)

- Nome di chi ha fatto l'azione, chat, reazioni: servono un canale proprio (plugin del server).
- Unirsi da Discord (pulsante dell'attività o collegamento `wonderflix://`).
- Gestione avanzata della coda: aggiungere elementi, riordinare, ripetizione, ordine casuale.
- Gruppi misti con jellyfin-web o con le app mobili ufficiali.
- Un "host" con permessi speciali.

## 4. Protocollo, orologio e correzione (`lib/core/syncplay/`)

Dart puro. Nessuna dipendenza da Flutter, media_kit o `dart:io`. Il tempo si legge solo con `clock.now()`.

### 4.1 API (`SyncPlayApi`)

Sopra `JellyfinHttp`. Endpoint usati:

| Area | Endpoint |
|---|---|
| Gruppi | `POST /SyncPlay/New` (`GroupName`), `POST /SyncPlay/Join` (`GroupId`), `POST /SyncPlay/Leave`, `GET /SyncPlay/List` |
| Coda | `POST /SyncPlay/SetNewQueue` (`PlayingQueue`, `PlayingItemPosition`, `StartPositionTicks`), `POST /SyncPlay/NextItem` (`PlaylistItemId`), `POST /SyncPlay/SetPlaylistItem` (`PlaylistItemId`) |
| Riproduzione | `POST /SyncPlay/Pause`, `POST /SyncPlay/Unpause`, `POST /SyncPlay/Seek` (`PositionTicks`) |
| Stato del client | `POST /SyncPlay/Buffering` e `POST /SyncPlay/Ready` (`When`, `PositionTicks`, `IsPlaying`, `PlaylistItemId`), `POST /SyncPlay/SetIgnoreWait` (`IgnoreWait`), `POST /SyncPlay/Ping` (`Ping`) |
| Orologio | `GET /GetUtcTime` (`RequestReceptionTime`, `ResponseTransmissionTime`) |

`When` si invia sempre nell'orario del server (ISO 8601 UTC), calcolato con `ServerClock`.

### 4.2 Messaggi WebSocket

`ServerEventsClient` impara due nuovi tipi:

- **`SyncPlayCommand`** (`SendCommand`): `GroupId`, `PlaylistItemId`, `When`, `PositionTicks`, `Command` (`Unpause`, `Pause`, `Stop`, `Seek`) ed `EmittedAt`.
- **`SyncPlayGroupUpdate`**, diviso in base a `Type`:
  - `GroupJoined` (`GroupInfoDto`: `GroupId`, `GroupName`, `State`, `Participants`, `LastUpdatedAt`);
  - `UserJoined` e `UserLeft` (nome utente);
  - `GroupLeft` e `NotInGroup`;
  - `StateUpdate` (`State` e `Reason`, cioè il tipo di richiesta che ha cambiato lo stato);
  - `PlayQueue` (`Reason`, `LastUpdate`, `Playlist` con `ItemId` e `PlaylistItemId`, `PlayingItemIndex`, `StartPositionTicks`, `IsPlaying`);
  - `GroupDoesNotExist` e `LibraryAccessDenied`.

I valori sconosciuti degli enum non devono far fallire la lettura: il messaggio si registra nel log e si ignora. Gli aggiornamenti `PlayQueue` più vecchi dell'ultimo ricevuto (confronto su `LastUpdate`) si scartano.

### 4.3 Orologio (`ServerClock`)

Funziona come jellyfin-web (metodo di NTP):

- una misura: t0 = invio, t1 = `RequestReceptionTime`, t2 = `ResponseTransmissionTime`, t3 = ricezione;
- offset = ((t1 − t0) + (t2 − t3)) / 2;
- ritardo = (t3 − t0) − (t2 − t1);
- ping = ritardo / 2.

Regole:

- all'ingresso in un gruppo: 3 misure a 1 s di distanza, poi una ogni 60 s;
- si tengono le ultime 8 misure e si usa quella con il **ritardo più basso**;
- dopo ogni misura si manda `/SyncPlay/Ping` con il ping;
- una misura fallita si registra nel log, e si tiene l'ultima buona;
- finché non c'è la prima misura, i comandi ricevuti restano in attesa. Si applica solo l'ultimo.

Conversioni: `toServer(locale) = locale + offset` e `toLocal(server) = server − offset`.

### 4.4 Correzione durante la visione (`DriftCorrector`)

Funzione pura: dato lo stato (scarto recente, velocità attuale, tempo dall'ultimo `Unpause` e dall'ultimo salto) restituisce un'azione tra *nessuna*, *velocità x* e *salta a p*.

- **Posizione attesa** = `PositionTicks` dell'ultimo `Unpause` + (ora del server − `When`).
- **Scarto** = posizione attesa − posizione locale. Si calcola ogni ~500 ms come media delle ultime 3 letture.
- Si corregge solo se:
  - l'ultimo comando è `Unpause`;
  - il `PlaylistItemId` coincide con quello aperto;
  - il motore non è in buffering;
  - sono passati almeno **1,5 s** dall'`Unpause` applicato.

| Scarto assoluto | Azione |
|---|---|
| < 150 ms | Nessuna. Se era in corso una correzione, si torna a 1,0× solo quando lo scarto scende **sotto i 40 ms** (isteresi). |
| 150 ms – 3 s | Velocità **1,05×** se si è indietro, **0,95×** se si è avanti. |
| > 3 s | Salto alla posizione attesa, avviso "Riallineamento al gruppo", poi **5 s** senza correzioni. |

Tutte le soglie sono costanti in un unico punto, per poterle ritoccare dopo le prove.

`VideoEngine` riceve `setRate(double rate)`, implementato con `Player.setRate` di media_kit. L'audio mantiene il tono (scaletempo di mpv). All'uscita dal gruppo, a ogni nuovo comando e alla chiusura, la velocità torna a 1,0.

### 4.5 Applicazione dei comandi

Svolta dal `GroupPlaybackDriver` (§6.2). "Allineamento esatto" vuol dire `seek` alla posizione indicata, fatto solo a video fermo e solo se la posizione locale differisce di oltre 40 ms. Sotto questa soglia un salto non serve.

| Comando | Comportamento |
|---|---|
| `Unpause` con `When` futuro | Allineamento esatto a `PositionTicks`, poi `play()` all'istante `toLocal(When)`. |
| `Unpause` con `When` già passato | `seek` alla posizione stimata (`PositionTicks` + tempo trascorso), poi `play()`. Succede quando si entra in un gruppo che sta già guardando. |
| `Pause` | `pause()` all'istante `toLocal(When)` (subito se è già passato), poi allineamento esatto a `PositionTicks`. |
| `Seek` | `pause()` e `seek(PositionTicks)`. A buffer pieno si manda `Ready` (`IsPlaying: false`). |
| `Stop` | Pausa e avviso "Il watch party si è fermato". Il player resta aperto. WonderFlix non manda mai `Stop` (§5.6). |

Regole comuni:

- **Doppioni:** un comando uguale al precedente (stesso `Command`, `When`, `PositionTicks` e `PlaylistItemId`) non si riapplica. Se il suo istante è già passato, si controlla lo stato locale: se è coerente non si fa nulla, altrimenti si riapplica una volta. Mai scarti casuali.
- I comandi con `EmittedAt` precedente all'ingresso nel gruppo si ignorano.
- I comandi con un `PlaylistItemId` diverso da quello aperto si ignorano (tranne `Stop`). La coda porterà all'elemento giusto.
- Ogni nuovo comando annulla quello programmato e non ancora eseguito, e riporta la velocità a 1,0.

### 4.6 Buffering e pronto

- Il motore in buffering per oltre **1 s** continuo, con il gruppo in `Playing`, fa partire `Buffering`. I buffering più brevi non si segnalano.
- Quando il buffering finisce (anche dopo un `Seek` o un'apertura) parte `Ready`, con posizione attuale, `IsPlaying` e `PlaylistItemId`.
- All'apertura di un elemento del gruppo il player resta in pausa sulla posizione di partenza e, a file caricato, manda `Ready`.
- Il resto lo gestisce il server: il gruppo va in `Waiting`, gli altri ricevono `Pause`, e quando tutti sono pronti arriva un `Unpause` con un istante futuro.

## 5. Sessione di gruppo (`lib/features/watch_party/`)

### 5.1 `WatchPartySession`

Provider Riverpod mantenuto per tutta la sessione di login, sopra le route. Stato:

- `none`, `joining` o `inGroup`;
- nel gruppo:
  - `groupId`, `groupName`;
  - membri (nomi utente);
  - stato del gruppo (`Idle`, `Waiting`, `Paused`, `Playing`);
  - coda (elementi con `ItemId` e `PlaylistItemId`, indice in riproduzione, `StartPositionTicks`, `LastUpdate`);
  - ultimo comando;
- avvisi da mostrare (§5.7).

Al logout o alla scadenza della sessione si esce dal gruppo, e lo stato torna a `none`.

### 5.2 Creare

**Dai dettagli ("Guarda insieme"):**

1. `New`, con il nome del gruppo `"<utente> · <titolo>"`. Il titolo è quello del film, oppure il nome della serie per gli episodi.
2. Si attende `GroupJoined`.
3. `SetNewQueue`:
   - film: solo il film;
   - episodio: quell'episodio e tutti i successivi della serie, in ordine;
   - serie: il prossimo episodio da vedere e i successivi;
   - posizione di partenza: la stessa di "Riproduci/Riprendi" in quella pagina.
4. All'arrivo della coda (`PlayQueue`, `NewPlaylist`) si apre il player in modalità gruppo.

Il nome del gruppo contiene il titolo perché `/SyncPlay/List` **non dice cosa si sta guardando**. Per le serie il nome resta valido anche quando si cambia episodio.

**Dai dettagli, stando già in un gruppo:** niente `New`. Si manda solo `SetNewQueue` con la coda calcolata come sopra, e il gruppo passa al nuovo titolo. Tutti vedono l'avviso "Si guarda: <titolo>". Il pulsante resta "Guarda insieme".

**Dal player (solo, già in visione):** stessa sequenza. La coda parte dall'elemento aperto, alla posizione attuale. Il player **non si riapre**: si aggancia al gruppo, va in pausa e aspetta l'`Unpause` del server.

### 5.3 Entrare

1. `Join`, poi si attende `GroupJoined` e la coda.
2. Si apre il player sull'elemento in riproduzione.
3. Da lì in poi comandano i messaggi del gruppo.

Mentre il nuovo membro si prepara, il server mette in pausa gli altri. Gli avvisi "Marco sta entrando…" e poi "Marco è entrato" spiegano la pausa.

Se si entra in un gruppo mentre si guarda altro da soli, il player attuale viene sostituito.

### 5.4 Cambio episodio

- Un aggiornamento della coda con un nuovo elemento (`NextItem`, `PreviousItem`, `SetCurrentItem`) sostituisce il player (`pushReplacement`) con quello del nuovo episodio, in modalità gruppo.
- **A fine episodio** c'è il conto alla rovescia di oggi, e alla scadenza (o con "Prossimo episodio") parte `NextItem` con il `PlaylistItemId` corrente. Il server ignora le richieste doppie degli altri membri, perché contengono un id non più attuale.
- **A fine coda** (ultimo episodio o film) il gruppo resta aperto. Ognuno chiude il player quando vuole.

### 5.5 Rientro automatico

Quando `ServerEventsClient` si riconnette (`ServerConnected` dopo una caduta), se eravamo in un gruppo si rimanda `Join` sullo stesso `groupId`. Il server riconosce la sessione e la ripristina. Se arriva `GroupDoesNotExist`, si esce con l'avviso "Il watch party è terminato".

### 5.6 Uscire

- Chiudere il player, o premere "Esci dal watch party", manda `Leave`. Gli altri continuano e vedono "Marco è uscito".
- Alla chiusura dell'app si prova a mandare `Leave` (con un tempo massimo breve). Se non riesce, il server toglie la sessione quando scade.
- WonderFlix non manda mai `Stop`.

### 5.7 Avvisi

Nascono dagli aggiornamenti `StateUpdate` (motivo), dai comandi e dalle entrate e uscite:

| Evento | Avviso |
|---|---|
| Pausa / Ripresa | "Pausa" / "Ripresa" |
| Salto | "Salto a 32:10" |
| Cambio episodio | "Episodio successivo: S02E06 · Titolo" |
| Nuovo titolo nel gruppo | "Si guarda: <titolo>" |
| Entrata / uscita | "Marco è entrato" / "Marco è uscito" |
| Salto per scarto > 3 s | "Riallineamento al gruppo" |
| Attesa forzata | "Si riprende senza aspettare" |
| Gruppo chiuso | "Il watch party è terminato" |

Quando l'azione è mia, l'avviso compare **subito**, in seconda persona ("Hai saltato a 32:10"), e il primo aggiornamento del server corrispondente, entro 3 s, non produce un secondo avviso. Il modello dell'avviso ha un campo "chi" facoltativo, oggi sempre vuoto per le azioni altrui.

### 5.8 Elenco dei gruppi e inviti (`WatchPartyDirectory`)

- `GET /SyncPlay/List` ogni **30 s**, e subito alla navigazione tra le schermate principali. Solo con la sessione attiva e senza essere in un gruppo.
- Il risultato alimenta il pulsante della barra in alto e il suo pannello.
- Un gruppo che non c'era alla lettura precedente, e che non è mio, fa comparire l'**avviso d'invito**, ma solo se il player non è aperto (`playerActiveProvider`). Al primo avvio dell'app i gruppi già esistenti non producono inviti: compaiono solo nell'elenco.
- Gli errori di rete si registrano nel log, senza messaggi all'utente.

### 5.9 Permessi

Da `Policy.SyncPlayAccess` dell'utente (`/Users/Me`):

| Valore | Interfaccia |
|---|---|
| `CreateAndJoinGroups` | Tutto. |
| `JoinGroups` | Niente "Guarda insieme". Elenco, inviti e ingresso sì. |
| `None` | Nessun elemento del watch party. |

Con `LibraryAccessDenied` compare l'avviso "Non hai accesso a questo contenuto" e non si entra.

### 5.10 Integrazioni

- **Discord Rich Presence:** in gruppo, la riga di stato diventa "Watch party · N persone". Il resto dell'attività non cambia.
- **Aggiornamenti (`UpdateGate`):** un gruppo con il player aperto conta come visione in corso.
- **Log e "Copia diagnostica":** vanno nel log:
  - ingresso e uscita;
  - comandi ricevuti e applicati;
  - offset e ping dell'orologio;
  - scarto misurato, velocità, riallineamenti.

  "Copia diagnostica" aggiunge l'ultimo stato del gruppo: id, stato, numero di membri, offset, ultimo scarto. Niente token e niente URL con segreti.

## 6. Player

### 6.1 Autorità di riproduzione (`PlaybackAuthority`)

Le azioni dell'utente passano da un'interfaccia: pulsanti, tastiera, pannello media di Windows, "Salta intro", "Prossimo episodio" e conto alla rovescia.

- `play()`, `pause()`, `togglePlay()`, `seekTo(position)`, `nextEpisode()`.
- **`LocalAuthority`:** il comportamento di oggi, applicato direttamente al motore.
- **`GroupAuthority`:**
  - `pause()` manda `Pause` e **mette subito in pausa anche il motore**, così la risposta è immediata. Il comando del gruppo poi allinea la posizione.
  - `play()` manda `Unpause`; il motore riparte con il comando del gruppo.
  - `seekTo()` manda `Seek`. La barra mostra subito la posizione scelta, e il motore si sposta con il comando del gruppo.
  - `nextEpisode()` manda `NextItem`.
  - "Salta intro" è un `seekTo()`.
  - Se il gruppo è in `Waiting`, `play()` corrisponde a "Riprendi senza aspettare".

Volume, tracce, sottotitoli e ritardo non passano dall'autorità: restano locali.

### 6.2 `GroupPlaybackDriver`

Collega la sessione di gruppo al `VideoEngine` del player aperto:

- applica i comandi (§4.5);
- fa girare il `DriftCorrector` (§4.4);
- manda `Buffering` e `Ready` (§4.6).

Si crea quando il player si apre in modalità gruppo, o quando un player da solo diventa gruppo (§5.2). Si distrugge con il player o all'uscita dal gruppo; in quel caso il player torna a `LocalAuthority`, in pausa.

### 6.3 Modalità gruppo del player

- `PlayerArgs` riceve `partyPlaylistItemId` (assente = da solo).
- La posizione di partenza la decide il gruppo: non si usa la ripresa personale.
- Il salto automatico dell'intro è spento. Il pulsante "Salta intro" resta, e vale per tutti.
- Il report dell'avanzamento a Jellyfin resta attivo: ognuno ha il suo stato "visto" e il suo "continua a guardare".
- **Errore di apertura** (anche dopo il ripiego sulla transcodifica):
  - si manda `SetIgnoreWait(true)`, così il gruppo non resta bloccato ad aspettare;
  - si mostra l'errore con "Riprova" ed "Esci dal watch party";
  - "Riprova" riuscito manda `SetIgnoreWait(false)` e poi `Ready`.

## 7. Interfaccia

Icone solo `LucideIcons`, nessuna emoji, tema Noir & Oro. Tutti i testi nei file ARB (it, en).

### 7.1 Elementi

- **Barra in alto:**
  - pulsante "Watch party · N" (bordo oro, icona `users`), visibile solo se esiste almeno un gruppo;
  - apre un pannello con i gruppi: nome, membri (nomi), stato (in riproduzione / in pausa / in attesa), "Unisciti";
  - se sono in un gruppo, il pulsante dice "Nel watch party" e il pannello offre "Torna al player" ed "Esci dal watch party".
- **Dettagli di film, episodio e serie:** "Guarda insieme" (stile secondario, bordo oro) accanto a Riproduci, se i permessi lo consentono.
- **Avviso d'invito:**
  - scheda in alto a destra con "<utente> ha avviato un watch party", il titolo preso dal nome del gruppo, e "Unisciti";
  - resta 10 s e si può chiudere.
- **Player:**
  - distintivo "Watch party · N" nei controlli in alto, visibile insieme agli altri controlli;
  - il distintivo apre un pannello con il nome del gruppo, i membri (iniziali e nome) ed "Esci dal watch party";
  - "Guarda insieme" nei controlli quando si guarda da soli;
  - **avvisi a pillola** in alto al centro, visibili anche a controlli nascosti (3 s ciascuno, in coda se sono più di uno);
  - **schermata di attesa** con il gruppo in `Waiting`: indicatore, "In attesa degli altri membri…" e "Riprendi senza aspettare". Compare dopo 1 s, per non lampeggiare.

Il server non comunica lo stato dei singoli membri (chi è in buffering) né le loro foto. Il pannello mostra quindi solo nomi e iniziali, e l'attesa è generica.

### 7.2 Seconda istanza per le prove

Solo per lo sviluppo: la variabile d'ambiente `WONDERFLIX_PROFILE=<nome>` avvia un'istanza separata.

- **Mutex:** in `windows/runner/main.cpp` il nome del mutex diventa `Local\WonderFlix.SingleInstance.<nome>`.
- **Dati locali:** preferenze, credenziali e log hanno un prefisso o una cartella per profilo.
- **`DeviceId`:** diverso, perché il server tratta due istanze con lo stesso `DeviceId` come **una sola sessione**.

Senza la variabile il comportamento è identico a oggi. La variabile non si documenta nell'interfaccia.

## 8. Prove

### 8.1 Automatiche

- **`ServerClock`:** calcolo di offset e ritardo, scelta della misura migliore, ritmo delle misure, errori (con `fakeAsync` e `clock`).
- **`DriftCorrector`:** tabella di casi (zona morta, isteresi, velocità, salto, pausa dopo il salto, periodo iniziale).
- **Messaggi:** lettura di tutti i tipi, con valori sconosciuti e campi mancanti.
- **`SyncPlayApi`:** corpi e percorsi delle richieste, con l'HTTP finto.
- **`WatchPartySession`:** creazione (dai dettagli e dal player), ingresso, cambio di coda, rientro dopo la riconnessione, uscita, avvisi (con eco scartata), permessi. Usa un socket finto.
- **`WatchPartyDirectory`:** controllo periodico, inviti solo per gruppi nuovi e non miei, niente inviti con il player aperto.
- **`GroupPlaybackDriver`:** ogni comando (istante futuro e passato), doppioni, `PlaylistItemId` diverso, buffering sotto e sopra 1 s, `Ready` dopo salto e apertura, correzione, errore di apertura. Usa il motore finto con `setRate`.
- **Widget:** pulsante e pannello della barra, avviso d'invito, "Guarda insieme", distintivo e pannello del player, pillole, schermata di attesa.

### 8.2 Manuali (sul server reale)

Con due istanze sullo stesso PC (§7.2) e due utenti, poi dal vivo con un secondo PC:

- creare dai dettagli (film, episodio) e dal player; entrare dall'elenco e dall'invito;
- pausa, ripresa e salto da entrambi i lati, con gli avvisi giusti;
- passaggio all'episodio successivo (conto alla rovescia e pulsante), salta intro;
- buffering di un membro (rete limitata), attesa comune e "Riprendi senza aspettare";
- un membro in transcodifica forzata;
- scarto sotto controllo dopo 30 minuti di visione, senza salti visibili;
- chiusura del player di un membro, rientro dall'elenco;
- rete staccata e riattaccata: rientro automatico;
- Rich Presence in gruppo;
- utente con `SyncPlayAccess` = `JoinGroups` e `None`.

## 9. Rischi e punti aperti

- **Velocità in media_kit:** si presume che `setRate` a 0,95/1,05 mantenga il tono dell'audio e non provochi scatti del video. Va verificato all'inizio; se ci sono problemi, si regola l'opzione `audio-pitch-correction` di mpv.
- **Precisione della posizione:** la posizione di mpv arriva a intervalli. La media su 3 letture e la zona morta di 150 ms dovrebbero bastare; le soglie restano regolabili (§4.4).
- **Pausa all'ingresso di un membro:** è una regola del server e non si evita. Gli avvisi la rendono chiara.
- **Nome del gruppo con il titolo:** se il gruppo passa a un altro titolo (§5.2, "stando già in un gruppo"), il nome non si aggiorna, perché il server non lo permette. Accettato.
