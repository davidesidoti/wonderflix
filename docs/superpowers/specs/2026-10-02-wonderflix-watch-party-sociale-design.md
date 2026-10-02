# WonderFlix — Spec E: watch party sociale (nomi, chat, reazioni)

- **Data:** 2026-10-02
- **Stato:** approvato; piani 10a, 10b e 10c realizzati (`docs/superpowers/plans/2026-10-02-wonderflix-10a-watch-party-plugin-nomi.md`, `docs/superpowers/plans/2026-10-02-wonderflix-10b-watch-party-chat.md`, `docs/superpowers/plans/2026-10-02-wonderflix-10c-watch-party-reazioni.md`)
- **Ambito:** Spec E. Aggiunge al watch party il nome di chi agisce, una chat di testo e reazioni rapide, attraverso un plugin del server Jellyfin scritto per WonderFlix. Si appoggia allo Spec B (`2026-09-30-wonderflix-watch-party-design.md`: §5.7 avvisi, §7 interfaccia) e allo Spec D (`2026-10-01-wonderflix-rinnovo-player-design.md`: §5 `PlayerChromeController`, §9 pillola, §11 schermata di pausa, §14 pannello, §15 watch party nel player), tutti realizzati (v0.4.1).

## 1. Obiettivo

Nel watch party di oggi gli avvisi delle azioni altrui sono anonimi ("Pausa", "Salto a 1:02:15") perché il server SyncPlay non dice chi ha agito, e non c'è modo di parlarsi. Lo Spec E aggiunge:

- **il nome di chi agisce**: "Luca ha messo in pausa", "Giulia ha saltato a 1:02:15";
- **una chat di testo** leggera dentro il player;
- **reazioni rapide** (emoji) che salgono sopra il film.

Tutto passa da un **plugin del server Jellyfin**, "WonderFlix Watch Party", che vive nello stesso repository. **Senza il plugin l'app funziona esattamente come oggi.**

## 2. Situazione di partenza

- **WebSocket** (`lib/core/jellyfin/server_events.dart`): `parseServerMessage` gestisce `UserDataChanged`, `LibraryChanged`, `ForceKeepAlive`, `SyncPlayCommand`, `SyncPlayGroupUpdate`; tutti gli altri tipi (compreso `GeneralCommand`) sono scartati in silenzio. L'app invia solo `KeepAlive`. Riconnessione 2, 5, 15, poi 30 s; ogni connessione emette `ServerConnected(isReconnect)`.
- **Identità:** l'app conosce il proprio utente (`JellyfinUser{id, name}`) e il proprio `DeviceId`, **non** il proprio id di sessione. Degli altri membri conosce **solo i nomi** (`GroupInfo.participants`, eventi `UserJoined`/`UserLeft`).
- **SyncPlay:** `WatchPartySession` (fasi none/joining/inGroup, `rejoins` dopo una riconnessione), `GroupAuthority` trasforma pausa, ripresa e salti dell'utente in richieste al gruppo e chiama `onAction` per gli avvisi "Hai…". L'episodio successivo chiesto dall'utente passa da `_playNext` in `player_screen.dart`; quello a fine video da `_onFinished`; un nuovo titolo dentro un gruppo da `startWatchParty` → `WatchPartySession.setQueue`.
- **Avvisi** (`lib/features/watch_party/party_notices.dart`): `PartyNotice{kind, mine, position, name, title}`; `name` oggi vale solo per ingressi e uscite. `_onUpdate` traduce `StateUpdate` (`Pause`, `Unpause` → ripresa o ripresa forzata, `Seek`) e i cambi di coda (`NextItem` → episodio successivo, altrimenti "Si guarda"). Eliminazione dell'eco entro 3 s. La `PlayerPill` mostra prima il riscontro dei tasti, poi gli avvisi.
- **Player** (`player_screen.dart`): `Stack` di livelli con `ValueKey` e `ExcludeFocus`, nell'ordine video, attesa del gruppo, schermata di pausa, errore o controlli, caricamento, "Salta"/scheda, post-play, attesa sopra il post-play, pillola, pannello tracce. `PlayerChromeController` tiene un solo `_panelOpen`. Nessun elemento del player può ricevere il focus; i tasti passano da `_onKey` sul `Focus` radice (mappa in `player_commands.dart`: Spazio, frecce, F, M, G, H, N, Esc, tasti multimediali; **Invio e 1–6 sono liberi**).
- **Barra dei controlli, a destra:** episodio successivo, "Guarda insieme" (solo fuori da un gruppo), tracce, schermo intero.
- **Regola dello Spec B §7:** solo icone Lucide, niente emoji. Lo Spec E fa **un'eccezione per le reazioni e per il testo della chat**.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Perimetro | Nome di chi agisce, chat di testo, reazioni rapide. |
| Canale | **Plugin del server Jellyfin** (C#). Scartati: solo API di Jellyfin (serve il permesso "controllo remoto di altri utenti" per tutti, che su 10.11 coincide con una falla di sicurezza) e servizio separato su Ultra.cc (porta, `systemd --user`, nginx, secondo socket). |
| Repository | **Stesso repository**, cartella `jellyfin-plugin-watch-party/`. Release del plugin come **pre-release** con tag `watch-party-plugin-v*`. |
| Nome | **WonderFlix Watch Party**: assembly `Jellyfin.Plugin.WonderFlixWatchParty`, API `/WonderFlixWatchParty/…`. |
| Trasporto | **Andata via REST** al plugin; **ritorno sul WebSocket già aperto** dall'app, come `GeneralCommand` `SendString`. |
| Chi ha agito | **Lo annuncia l'app** che agisce; il plugin timbra il nome vero. Lo stato resta quello di SyncPlay. |
| Chat | **Leggera, in basso a sinistra**: bolle che svaniscono; Invio apre campo e storico. **Solo nel player.** |
| Storico | **Breve, in memoria nel plugin**: ultimi 50 messaggi per gruppo, finché il gruppo esiste. |
| Fuori dal player | Contatore oro sul pulsante "Nel watch party"; tornando al player, puntino sul pulsante chat. |
| Reazioni | **Emoji a colori di Windows** che **salgono in basso a destra**; 1 😂 · 2 😱 · 3 😢 · 4 😮 · 5 👏 · 6 🤦. |
| Comando delle reazioni | **Pulsante con barretta + tasti 1–6.** |
| Jellyfin 12 | Il plugin nasce per 10.11 (net9.0). La build per 12 (net10.0) si fa quando l'utente decide di aggiornare il server dal pannello di Ultra.cc. |
| Release | Plugin **1.0.0**; app **0.5.0**, non obbligatoria. |

## 4. Perimetro

### Incluso

- Plugin "WonderFlix Watch Party": endpoint, protocollo, registro, storico, limiti, inoltro, CI, manifest (§6).
- Canale lato app (§7), nomi negli avvisi (§8), chat (§9), reazioni (§10), tasti e livelli del player (§11).
- Comportamento senza plugin ed errori (§12), diagnostica (§13), testi (§14), test (§15).

### Escluso

- Chat e reazioni fuori dal player; notifiche di sistema per i messaggi.
- Storico su disco, modifica o cancellazione dei messaggi, menzioni, risposte, moderazione.
- Messaggi privati; chat fuori da un gruppo SyncPlay.
- Set di reazioni personalizzabile; reazioni con testo o immagini.
- Pagina di configurazione del plugin nella Dashboard.
- Gruppi misti con jellyfin-web o con le app ufficiali (già escluso dallo Spec B).
- Nome di chi agisce per azioni che l'app non fa partire dall'utente (avanzamento automatico a fine episodio, riallineamenti).
- Build per Jellyfin 12.

## 5. Architettura

```
WonderFlix (chi agisce)                 Jellyfin 10.11.9                         WonderFlix (gli altri)
  GroupAuthority ── POST /SyncPlay/… ──▶ SyncPlay (invariato) ── SyncPlayGroupUpdate (anonimo) ──▶ PartyNotices
  PartyChannel ─── POST /WonderFlixWatchParty/Groups/{id}/Events ──▶ Plugin ── GeneralCommand SendString ──▶ PartyChannel
                                          (verifica, timbra, storico,            (stesso /socket di oggi)
                                           limiti, inoltro)
```

- SyncPlay resta la fonte di verità per lo stato del gruppo. Il plugin è un canale accanto, che non tocca SyncPlay.
- Il plugin inoltra ogni evento alle **sole sessioni WonderFlix registrate nel gruppo**, tranne quella che l'ha mandato (che lo mostra già da sé).
- L'app mette insieme l'avviso anonimo di SyncPlay e l'annuncio con il nome (§8).

## 6. Plugin "WonderFlix Watch Party"

### 6.1 Progetto

```
jellyfin-plugin-watch-party/
  Jellyfin.Plugin.WonderFlixWatchParty/          plugin (net9.0)
  Jellyfin.Plugin.WonderFlixWatchParty.Tests/    test xUnit
  meta.template.json                             meta.json del pacchetto (versione e data le mette pack.sh)
  pack.sh                                        build di release e cartella da installare
  manifest.json                                  repository di plugin per la Dashboard
  README.md                                      installazione e prova (in italiano)
```

- **Dati:** nome `WonderFlix Watch Party`, GUID `882eb47e-668a-4935-ba55-c2858eb4ed90`, `targetAbi` `10.11.0.0`, categoria `General`, proprietario `davidesidoti`.
- **Dipendenze:** `Jellyfin.Controller` e `Jellyfin.Model` 10.11.x con `ExcludeAssets=runtime` (come il modello ufficiale `jellyfin-plugin-template`). Nessuna altra libreria nel plugin. Il progetto di test riferisce di nuovo gli stessi pacchetti senza `ExcludeAssets`, altrimenti non carica le dll di Jellyfin.
- **Registrazione:** `IPluginServiceRegistrator` registra registro, storico, limiti e il servizio di pulizia (`IHostedService`). Il controller viene trovato da Jellyfin nell'assembly del plugin.
- **Configurazione:** nessuna pagina; il plugin non ha impostazioni.

### 6.2 Endpoint

Tutti richiedono un utente collegato con accesso a SyncPlay (policy `SyncPlayHasAccess` di `MediaBrowser.Common.Api.Policies`; se nel pacchetto NuGet non fosse disponibile, `[Authorize]` più il controllo di `SyncPlayAccess` dell'utente). Le risposte usano le stesse convenzioni JSON di Jellyfin (proprietà in PascalCase).

| Chiamata | Risposta | Cosa fa |
|---|---|---|
| `GET /WonderFlixWatchParty/Info` | `{"Version":"1.0.0","Protocol":1}` | Dice all'app che il plugin c'è e quale protocollo parla. |
| `POST /WonderFlixWatchParty/Groups/{groupId}/Join` | `{"Messages":[…]}` | Registra la sessione di chi chiama nel gruppo; restituisce lo storico della chat (dal più vecchio al più nuovo). |
| `POST /WonderFlixWatchParty/Groups/{groupId}/Leave` | 204 | Toglie la sessione dal gruppo. |
| `POST /WonderFlixWatchParty/Groups/{groupId}/Events` | l'evento timbrato (§6.3) | Valida, timbra, conserva (solo chat) e inoltra un evento. Registra anche la sessione, se non lo era (es. dopo un riavvio del plugin). |

Errori: **400** evento non valido, **403** gruppo inesistente o utente non nel gruppo, **409** sessione di chi chiama non trovata, **429** limite di frequenza superato. Il plugin non risponde mai 404: per l'app un 404 vuol dire che la rotta non esiste, cioè plugin assente. Un `groupId` che non è un GUID riceve 404 dal vincolo della rotta (`{groupId:guid}`); l'app manda sempre GUID. Senza autenticazione la risposta è 400, come per gli endpoint SyncPlay di Jellyfin (la policy `SyncPlayHasAccess` va in errore su un utente anonimo); l'app manda sempre l'autenticazione.

### 6.3 Protocollo (versione 1)

**Eventi inviati dall'app** (corpo di `Events`):

```json
{"Type":"Action","Action":"Pause"}
{"Type":"Action","Action":"Seek","PositionTicks":37350000000}
{"Type":"Chat","Text":"che scena"}
{"Type":"Reaction","Reaction":"joy"}
```

- `Action`: `Pause`, `Unpause`, `Seek` (con `PositionTicks` ≥ 0), `NextItem`, `NewQueue`. Sono i nomi delle richieste SyncPlay corrispondenti.
- `Text`: spazi esterni tolti, a capo sostituiti da spazi, **da 1 a 200 caratteri** (punti di codice Unicode: `runes` in Dart, `EnumerateRunes` in C#).
- `Reaction`: un identificativo `^[a-z]{1,20}$`. Il plugin **non** controlla l'elenco: le app ignorano quelli che non conoscono, così il set si può cambiare senza aggiornare il plugin. Oggi: `joy`, `scream`, `cry`, `wow`, `clap`, `facepalm`.

**Evento timbrato** (risposta di `Events`, voce dello storico, contenuto inoltrato):

```json
{"Protocol":1,"Id":"5f0c…","GroupId":"9a1e…","Type":"Chat","UserId":"2b7d…","UserName":"Luca",
 "SentAt":"2026-10-02T21:14:03.512Z","Text":"che scena"}
```

- `Id`: GUID nuovo; serve all'app per togliere i doppioni.
- `UserId`, `UserName`: presi dalla sessione autenticata, **mai** dal corpo della richiesta.
- `SentAt`: ora UTC del server.
- I campi `Action`, `PositionTicks`, `Text`, `Reaction` come nell'evento inviato.

**Inoltro sul WebSocket:**

```json
{"MessageType":"GeneralCommand","MessageId":"…","Data":{"Name":"SendString",
 "Arguments":{"WonderFlixWatchParty":"<evento timbrato come stringa JSON>"}}}
```

La chiave `WonderFlixWatchParty` evita `String`, che jellyfin-web scriverebbe nel campo con il focus.

### 6.4 Identità e appartenenza

- **Chi chiama:** `IAuthorizationContext.GetAuthorizationInfo(HttpContext)` dà `UserId`, `DeviceId` e `Client`; la sessione è quella di `ISessionManager.Sessions` con gli stessi `DeviceId`, `Client` e `UserId`. Se non c'è: 409.
- **Appartenenza:** `ISyncPlayManager.GetGroup(session, groupId)` deve restituire il gruppo e il nome dell'utente deve essere tra i `Participants` (confronto senza distinzione di maiuscole); altrimenti 403. I partecipanti sono solo nomi: il controllo è per utente, non per sessione.

### 6.5 Registro, storico e pulizia

- **Registro:** gruppo → insieme di id di sessione WonderFlix. Ci si entra con `Join` o con il primo `Events`; si esce con `Leave`, con l'evento `ISessionManager.SessionEnded`, o quando all'inoltro la sessione non esiste più o il suo utente non è più tra i partecipanti.
- **Storico:** per gruppo, gli ultimi **50** eventi `Chat` (non reazioni, non annunci). Solo in RAM: si perde al riavvio del server, accettato.
- **Pulizia:** ogni 5 minuti un servizio elimina registro e storico dei gruppi che non esistono più (`GetGroup` con una delle sessioni registrate restituisce null, o nessuna sessione registrata è ancora viva).
- Tutte le strutture sono sicure tra thread (le richieste arrivano in parallelo).

### 6.6 Limiti, validazione e log

| Tipo | Limite per sessione |
|---|---|
| `Chat` | 5 ogni 10 s |
| `Reaction` | 8 ogni 5 s |
| `Action` | 20 ogni 10 s |

- Finestra scorrevole per sessione e tipo; oltre il limite: 429, l'evento non viene né conservato né inoltrato.
- **Log:** avvio del plugin con la versione; per ogni evento a livello Debug solo tipo, gruppo e id utente. **Mai il testo dei messaggi.**

### 6.7 Inoltro

- Destinatari: le sessioni registrate nel gruppo, **tranne quella che ha inviato**, ancora presenti in `ISessionManager.Sessions` e con l'utente ancora tra i partecipanti.
- Invio con `ISessionManager.SendGeneralCommand(null, sessionId, command, ct)`. Con `controllingSessionId` nullo il server non controlla i permessi di controllo remoto (verificato sul codice 10.11.9: `SessionManager.cs`, `SendGeneralCommand`), e il messaggio va sul WebSocket aperto più di recente della sessione (`WebSocketController.SendMessage`). Una sessione senza WebSocket aperto non riceve nulla.
- Gli invii partono in parallelo; l'errore su una sessione si registra nel log e non ferma gli altri. La risposta a chi ha inviato arriva dopo gli inoltri.
- L'inoltro non usa l'annullamento della richiesta di chi invia (`CancellationToken.None`): una richiesta interrotta non deve interrompere i WebSocket dei destinatari.

### 6.8 Distribuzione

- **Workflow** `.github/workflows/watch-party-plugin.yml`:
  - su push e pull request che toccano `jellyfin-plugin-watch-party/**`: `dotnet test` con .NET 9;
  - su tag `watch-party-plugin-vX.Y.Z`: `pack.sh` (build di release e cartella con la dll e `meta.json`), zip `wonderflix-watch-party_X.Y.Z.zip`, MD5, **pre-release** su GitHub con zip e `.md5` (`gh release create … --prerelease --latest=false`).
- **Perché pre-release:** l'aggiornamento dell'app legge `releases/latest`, che esclude le pre-release; una release del plugin non deve mai diventarlo. Il tag non fa partire `release.yml` (che ascolta solo `v*.*.*`).
- **Manifest:** `jellyfin-plugin-watch-party/manifest.json`, servito da `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`. A pipeline finita aggiungo io la voce della versione (`version` `X.Y.Z.0`, `targetAbi`, `sourceUrl` dello zip, `checksum` MD5, `timestamp`, `changelog`) e la committo, con l'ok dell'utente, come per le note dell'app.
- **Installazione:** Dashboard → Plugin → Repository → aggiungi l'URL del manifest; Catalogo → WonderFlix Watch Party → Installa; riavvio di Jellyfin dal pannello di Ultra.cc.
- **Prova prima della release:** via SFTP si copia la cartella del plugin (dll + `meta.json`) nella cartella dei plugin di Jellyfin su Ultra.cc e si riavvia Jellyfin. Prima di installare dal Catalogo quella cartella va tolta, per non avere due copie.

### 6.9 Jellyfin 12

Jellyfin 12 (net10.0) richiede di ricompilare i plugin. Quando l'utente decide di aggiornare, si aggiunge una build `targetAbi` `12.0.0.0` al manifest. Fino ad allora, con il server su 12 il plugin non si carica e l'app torna al comportamento di oggi (§12).

## 7. App: il canale

### 7.1 Ricezione

`parseServerMessage` riconosce `MessageType: "GeneralCommand"` con `Data.Name == "SendString"` e `Data.Arguments.WonderFlixWatchParty` stringa, ed emette un nuovo `ServerEvent`: `PartyChannelReceived(String payload)`. Gli altri `GeneralCommand` restano ignorati.

### 7.2 Nucleo (`lib/core/party_channel/`, Dart puro)

- `party_channel_models.dart`:
  - `PartyPluginInfo{version, protocol}`;
  - `sealed class PartyEvent{id, groupId, userId, userName, sentAt}` con `PartyActionEvent{action, position?}`, `PartyChatEvent{text}`, `PartyReactionEvent{reaction}`;
  - `PartyAction` (`pause`, `unpause`, `seek`, `nextItem`, `newQueue`);
  - `PartyReaction` (enum `joy`, `scream`, `cry`, `wow`, `clap`, `facepalm`, con emoji e tasto 1–6; `fromId` restituisce null per gli sconosciuti);
  - `parsePartyEvent(String)` → `PartyEvent?`: null (e una riga di log) per JSON malformato, `Protocol` diverso, tipo sconosciuto o reazione sconosciuta;
  - eventi in uscita con `toJson`.
- `party_channel_api.dart` (`PartyChannelApi` sopra `JellyfinHttp`): `info()`, `join(groupId)` → storico, `leave(groupId)`, `send(groupId, evento)` → evento timbrato. Errori come `PartyChannelException` con il tipo: `unavailable` (404: rotta inesistente, plugin assente), `rateLimited` (429), `rejected` (400, 403), `sessionUnknown` (409), `network`.

### 7.3 `PartyChannel` (`lib/features/watch_party/party_channel.dart`)

Notifier Riverpod che segue `WatchPartySession`.

- **Stato:** disponibilità (`unknown`, `available`, `unavailable`), versione del plugin, canale attivo per il gruppo corrente, messaggi della chat (al massimo 50, ognuno con stato `pending`/`sent`), messaggi non letti, contatori di eventi inviati e ricevuti.
- **Flussi:** `reactions` (anche le proprie, subito), `chatArrivals` (messaggi nuovi, anche i propri `pending`). Gli annunci degli altri non hanno un flusso: vanno agli avvisi (sotto).
- **Ingresso:** quando la sessione entra in un gruppo e a ogni nuovo ingresso dopo una riconnessione (`rejoins`): `info()` (se il plugin non risulta già disponibile), poi `join(groupId)`. Lo storico ricevuto si unisce a quello presente per `Id`, in ordine di `SentAt`.
- **Uscita:** quando la sessione esce dal gruppo: `leave(groupId)` (senza attendere l'esito) se per quel gruppo è partito un `Join`, anche se la risposta non è ancora arrivata (il server ci ha forse già registrati); messaggi e contatori azzerati, canale spento.
- **Ricezione:** `PartyChannelReceived` → `parsePartyEvent`; scartati gli eventi di un altro gruppo e i doppioni (stesso `Id`). Con il `Join` in corso si accettano già gli eventi del gruppo in cui si entra: il server può inoltrarli prima della risposta. Nella chat e nelle reazioni un evento con il proprio `UserId` (stesso utente da un altro PC) si mostra come "Tu"; gli id utente si confrontano come quelli dei gruppi (senza trattini, in minuscolo). Negli avvisi il proprio utente da un altro PC resta con il nome: l'azione viene da un altro dispositivo.
- **Invio:**
  - `sendChat(text)`: aggiunge subito il messaggio come `pending`, poi lo sostituisce con quello timbrato; se fallisce lo toglie e restituisce l'esito (`sent`, `rateLimited`, `failed`).
  - `sendReaction(reaction)`: emette subito la reazione propria sul flusso, poi invia; un errore va solo nel log.
  - `announce(action, {position})`: invia senza attendere; un errore va solo nel log.
  - Con il canale spento i metodi non fanno nulla.
- **Non letti:** un messaggio arrivato mentre nessun livello chat è montato (cioè fuori dal player) incrementa i non letti; `markRead()` li azzera quando la chat si apre. Il livello chat del player (10b) chiama `attachChatLayer`/`detachChatLayer`.
- **Avvisi:** gli annunci ricevuti vanno a `PartyNotices.attribute`; quando il canale si accende o si spegne lo dice a `PartyNotices.setAttribution`. Gli avvisi non leggono il canale.
- **Vita:** il canale lo tiene vivo `watchPartyRoutingProvider` (in `WonderflixApp`), così segue il gruppo anche fuori dal player. Se nasce a gruppo già in corso entra subito dopo la build.
- **Diagnostica:** `refreshInfo()` chiede `Info` se il plugin non è già noto (al massimo 5 s).

### 7.4 Annunci

| Azione dell'utente | Punto | Annuncio |
|---|---|---|
| Pausa | `GroupAuthority.pause` → `onAction(paused)` | `Pause` |
| Ripresa (anche senza aspettare) | `GroupAuthority.play` → `onAction(resumed)` | `Unpause` |
| Salto (dopo il debounce di 400 ms) | `GroupAuthority._flushSeek` → `onAction(seeked, position)` | `Seek` + `PositionTicks` |
| Episodio successivo (pulsante, tasto N, "Riproduci ora" del post-play) | `_playNext` nel gruppo, se `nextItem` restituisce `true` (richiesta arrivata al server) | `NextItem` |
| Nuovo titolo ("Guarda insieme" dentro un gruppo) | `startWatchParty` dopo `setQueue` riuscita | `NewQueue` |

L'avanzamento a fine video (`_onFinished`) **non** si annuncia: lo chiedono tutti i membri e il nome non avrebbe senso.

## 8. Nomi negli avvisi

- `PartyNotice.name` vale per tutti gli avvisi, non più solo per ingressi e uscite (spec B §5.7 da aggiornare).
- **Buffer degli annunci:** ogni `PartyActionEvent` ricevuto resta disponibile per **2 s**.
- **Abbinamento:** quando `_onUpdate` produce un avviso di un altro membro, si cerca nel buffer l'annuncio corrispondente più recente e lo si consuma:

| Avviso | Annuncio |
|---|---|
| pausa | `Pause` |
| ripresa, ripresa forzata | `Unpause` |
| salto | `Seek` |
| episodio successivo | `NextItem` |
| "si guarda" (nuovo titolo) | `NewQueue` |

- **Attesa:** se l'avviso arriva prima del nome, resta in sospeso **al massimo 300 ms**: esce appena arriva l'annuncio, oppure allo scadere senza nome (come oggi). Un avviso che aspetta il nome può essere superato da uno successivo (entro 300 ms): accettato. Anche i nostri avvisi di episodio successivo e di nuovo titolo, che non passano da `PartyNotices.mine`, possono aspettare fino a 300 ms.
- Un annuncio senza un avviso corrispondente non mostra niente: lo stato lo dice SyncPlay.
- Restano come oggi: avvisi propri ("Hai…"), eliminazione dell'eco, ingressi e uscite (che hanno già il nome), riallineamenti, fine e rimozione.
- Con il canale spento non si attende nulla: gli avvisi escono subito, anonimi.

## 9. Chat

### 9.1 Posizione e aspetto

- Livello `PartyChatLayer` in basso a sinistra, margine sinistro come i controlli, a un'**altezza fissa** subito sopra la zona dei controlli (non si sposta quando i controlli compaiono o spariscono): `left: 24`, `bottom: 150` (`PartyChatLayer.left`/`bottom`, come "Salta intro" a destra). Larghezza massima 360 px.
- Bolla: nome in oro (semibold), testo in crema, fondo `WfColors.bg` al 72%, angoli 10. I propri messaggi hanno il nome "Tu".
- Il testo usa il font dell'app con `fontFamilyFallback: ['Segoe UI Emoji']` (`partyChatTextStyle` in `party_chat_bubble.dart`), così le emoji scritte nella chat sono a colori (verificato nel piano 10b).

### 9.2 Chat chiusa

- Ogni messaggio in arrivo compare come bolla, anche i nostri scritti da un altro PC (con "Tu"); quelli mandati da qui, a chat aperta, sono nello storico. Al massimo **3** bolle; la più nuova in basso, le altre salgono.
- Ogni bolla resta **8 s**, poi sfuma (`fast`). Testo lungo: massimo 4 righe con ellissi.
- Entrata: dissolvenza + 8 px verso l'alto (`medium`, curva enfatizzata); con le animazioni ridotte, solo dissolvenza.

### 9.3 Chat aperta

- Si apre con **Invio** o con il **pulsante chat**. Invio apre la chat solo se il focus è al player: su un pulsante a fuoco (per esempio "Riprova") lo preme. Il campo (360 px, segnaposto "Scrivi un messaggio…") prende il focus; sopra, lo **storico** scorrevole (fino a 50 messaggi, altezza massima 40% della finestra), che non sfuma.
- Lo storico è **ancorato in fondo**: i messaggi più nuovi in basso, subito sopra il campo (con pochi messaggi resta stretto). All'apertura si è in fondo; chi è in fondo ci resta quando arriva un messaggio; un messaggio inviato riporta in fondo anche chi stava leggendo più su.
- **Invio** invia il testo; **Invio a campo vuoto** chiude la chat. Invio tenuto premuto non invia e non chiude di nuovo: la ripetizione del tasto si ignora.
- **Tab** e **Maiusc+Tab** non escono dal campo. Se il campo perde il focus con la chat aperta, il tasto successivo glielo ridà (quel tasto non scrive nulla).
- I tasti multimediali (play/pausa e gli altri) funzionano anche mentre si scrive.
- **Esc** chiude la chat, senza uscire dal player.
- **Clic sul film** con la chat aperta: chiude solo la chat (non mette in pausa). Un clic sui controlli agisce e lascia il focus nel campo (`onTapOutside` vuoto).
- Contatore dei caratteri visibile da 180/200; a 200 il campo non accetta altro (`ChatLengthFormatter`: conta i punti di codice come il plugin, non i grafemi). Un tasto al limite non entra; un incolla troppo lungo si taglia nel punto in cui entra. Il testo già scritto, anche quello dopo il cursore, non cambia.
- Chiusura automatica: campo vuoto e **20 s** senza attività (tasti, mouse sulla chat, messaggi inviati).
- La rotella sopra la chat aperta non regola il volume: scorre lo storico, se può. Sulle bolle e altrove regola il volume.
- Alla chiusura il focus torna al player.
- Il focus si prende (il campo all'apertura, il player alla chiusura) solo se il player è la pagina in primo piano. Con un menu o un dialogo sopra il player il focus resta a loro; chiusi, torna al player, e a chat aperta il primo tasto lo riporta al campo.

### 9.4 Invio e errori

- Il messaggio inviato compare subito nello storico, al 60% di opacità, e diventa pieno alla conferma. Tiene la stessa identità (`PartyChatEntry.key`) da "in attesa" a confermato.
- Se l'invio fallisce il messaggio sparisce, il testo torna nel campo (con la chat riaperta se nel frattempo era stata chiusa) e sotto il campo compare una riga rossa: "Non inviato, riprova" (errore) o "Troppi messaggi, aspetta un attimo" (429). La riga sparisce al tasto successivo.

### 9.5 Pulsante e non letti

- Pulsante **chat** (`LucideIcons.messageCircle`, tooltip "Chat (Invio)") nella barra dei controlli, a destra, dove fuori dal gruppo c'è "Guarda insieme". Compare solo nel gruppo con il canale attivo.
- **Fuori dal player:** i messaggi arrivati diventano un contatore oro (fino a "9+": `CountBadge` con `max: 9`, dentro `PartyChip`) sul pulsante "Nel watch party" della barra in alto.
- **Tornando al player:** niente bolle per quei messaggi; un puntino oro sul pulsante chat finché la chat non si apre (`markRead`).

### 9.6 Rapporto con il resto del player

- Chat, barretta delle reazioni e pannello "Audio e sottotitoli" si escludono: aprirne uno chiude gli altri.
- La chat aperta **non** tiene visibili i controlli (si nascondono come sempre); conta però come attività: con la chat aperta la schermata "Stai guardando" non parte.
- Le bolle compaiono anche sopra la schermata di pausa, il post-play, l'attesa del gruppo, il caricamento e l'errore; non li chiudono.

## 10. Reazioni

### 10.1 Set

| Tasto | Emoji | Id |
|---|---|---|
| 1 | 😂 | `joy` |
| 2 | 😱 | `scream` |
| 3 | 😢 | `cry` |
| 4 | 😮 | `wow` |
| 5 | 👏 | `clap` |
| 6 | 🤦 | `facepalm` |

Le emoji usano `fontFamily: 'Segoe UI Emoji'` (glifi a colori di Windows). Sono l'unica eccezione alla regola "solo icone Lucide", insieme al testo scritto in chat.

### 10.2 Barretta

- Pulsante **reazioni** (`LucideIcons.smilePlus`, tooltip "Reazioni (1–6)") accanto al pulsante chat, alle stesse condizioni.
- La barretta si apre sopra il pulsante, allineata a destra: fondo `WfColors.surface` al 94%, bordo `WfColors.border`, forma a pillola, ombra.
- È un livello a sé agganciato al pulsante (`CompositedTransformTarget` sul pulsante, `CompositedTransformFollower` nel livello `player-party-reactions-tray`): un widget che sporge fuori dai bordi del suo genitore non riceve i clic. È sempre montata: chiusa è invisibile e non prende i clic. Entrata con dissolvenza e scala 0,9 → 1 dal pulsante (`WfMotion.medium`, curva enfatizzata), uscita con `WfMotion.fast`; con le animazioni ridotte solo la dissolvenza.
- Le 6 emoji a 24 px con il tasto sotto (testo piccolo, crema al 50%); al passaggio del mouse fondo crema al 12%.
- **Clic** = invio; la barretta resta aperta per mandarne altre.
- Si chiude con un clic sul film (che non fa altro), Esc, di nuovo il pulsante, o dopo **5 s** senza il mouse sopra (`PartyReactionsTray.idleClose`; il conto riparte a ogni clic su una reazione e quando il mouse esce).
- Finché è aperta i controlli restano visibili (come con il pannello).

### 10.3 Tasti

- **1–6** e tastierino numerico 1–6 inviano subito la reazione, solo con il focus al player (`_focusNode.hasPrimaryFocus`: a chat aperta i numeri vanno nel campo), anche a controlli nascosti.
- Non mostrano i controlli né la pillola: il riscontro è l'emoji in volo con "Tu".
- La ripetizione automatica del tasto tenuto premuto è ignorata; al massimo una reazione ogni **200 ms**, anche contando i clic sulla barretta (`PlayerScreen.reactionInterval`).
- Spenti mentre si scrive in chat e con il canale spento.

### 10.4 Volo

- Livello `PartyReactionsLayer` (`right: 24`, `bottom: 150`, la stessa altezza fissa della chat): nasce in basso a destra, con uno scostamento orizzontale da 0 a 80 px calcolato dall'`Id` dell'evento (`reactionJitter`, stabile nei test).
- Emoji a **40 px** con sotto il nome in un'etichetta piccola (fondo `WfColors.bg` al 65%); "Tu" per le proprie.
- **Animazioni complete:** 0–200 ms scala 0,6 → 1 (curva enfatizzata); 0–2,4 s salita di **140 px** in decelerazione; dissolvenza negli ultimi 600 ms. Il fotogramma a un dato istante lo calcola la funzione pura `reactionFrame`.
- **Animazioni ridotte:** niente scala né salita; compare in 150 ms, resta 1,6 s, sfuma in 300 ms.
- Al massimo **12** reazioni in volo; le nuove oltre il limite si scartano.
- Un solo livello disegna tutte le reazioni con un unico ticker, dentro un `RepaintBoundary`, e non intercetta il puntatore (`IgnorePointer`).
- Le durate sono costanti nominate e commentate in `party_reactions_layer.dart`, derivate dai token di `WfMotion` dove esistono.
- Fuori dal player le reazioni si ignorano (non contano come non letti).

## 11. Tasti, Esc e livelli nel player

- **Tasti nuovi:** Invio (e Invio del tastierino) apre la chat, solo con il focus al player (`_focusNode.hasPrimaryFocus`); 1–6 reazioni. Solo nel gruppo con il canale attivo.
- **Mentre si scrive** `_onKey` lascia passare tutti i tasti al campo (Spazio scrive uno spazio) tranne Esc, che chiude la chat, e i tasti multimediali, che fanno il loro comando. Tab e Maiusc+Tab si fermano lì (non portano il focus fuori dal campo); la ripetizione di Invio si ignora. Se il focus non è al campo, il tasto glielo ridà e si consuma.
- **Esc:** chat → barretta → pannello → post-play o scheda → schermo intero → uscita.
- **`PlayerChromeController`:** `_panelOpen` diventa un `popup` (`PlayerPopup`, al massimo uno): `tracks`, `chat` e `reactions`. I controlli restano visibili con `tracks` (e `reactions`), non con `chat`. Con la chat aperta il controller stesso non fa partire la schermata di pausa e la chiude all'apertura. Il player ha un `FocusNode` suo, a cui torna il focus quando la chat si chiude.
- **Focus della chat:** anche il `FocusNode` del campo è di `PlayerScreen`, che lo crea, lo passa a `PartyChatLayer` (`focusNode`) e lo distrugge: così può ridare il focus al campo. Il focus si prende (campo all'apertura, player alla chiusura) solo se il player è la route corrente (`ModalRoute.isCurrentOf`): un menu o un dialogo sopra il player tiene il suo.
- **Livelli** (dal basso): video, attesa del gruppo, schermata di pausa, errore o controlli, caricamento, "Salta"/scheda, post-play, attesa sopra il post-play, **reazioni** (`player-party-reactions`), **chat**, **barretta** (`player-party-reactions-tray`), pillola, pannello tracce. Il livello chat non è dentro `ExcludeFocus`.
- La barretta non vive nel livello dei controlli: è un livello a sé, ancorato al pulsante, sopra chat, "Salta intro" e scheda e sotto pillola e pannello. Il suo `CompositedTransformFollower` sta in un `Positioned(left: 0, top: 0)` dello `Stack` del player e riceve i clic dove è disegnato; senza il pulsante (strato d'errore al posto dei controlli) non si vede né prende clic.

## 12. Senza plugin ed errori

| Caso | Comportamento |
|---|---|
| Plugin assente (404) o protocollo diverso | Canale spento: niente pulsanti chat e reazioni, tasti Invio e 1–6 inattivi, avvisi anonimi come oggi. Si riprova a ogni ingresso nel gruppo. |
| `Info` o `Join` falliti per la rete | Canale spento per quel gruppo; si riprova alla riconnessione o al prossimo ingresso. |
| Plugin tolto mentre si è nel gruppo (404 dalle rotte del plugin) | Canale spento: la chat e la barretta si chiudono, i pulsanti spariscono, gli avvisi tornano anonimi. |
| `Events` 409 (sessione non trovata) | Un nuovo `join`, poi un solo nuovo tentativo. |
| Annuncio o reazione non inviati | Solo nel log. |
| Messaggio non inviato | §9.4. |
| Evento ricevuto malformato, di un altro gruppo o doppio | Ignorato. |
| Membro con un'app senza il canale | Le sue azioni restano anonime per gli altri; lui non vede chat e reazioni. |
| Server aggiornato a Jellyfin 12 senza la nuova build | Il plugin non si carica: come "plugin assente". |

I 404 e i 429 del plugin sono esiti previsti: nel log vanno a livello info, non tra gli "Ultimi errori" (§13).

## 13. Diagnostica e log

- La diagnostica (Impostazioni → copia della diagnostica) aggiunge una riga `Plugin watch party: …`, per esempio `Plugin watch party: 1.0.0 (protocollo 1), canale=attivo, inviati=3, ricevuti=5`, oppure `assente, canale=spento, …`, `2.0.0 (protocollo diverso), …`, `sconosciuto, …` (`describePartyChannel`). Come il resto della diagnostica non è tradotta. **Mai testi né nomi.** Se il plugin non è già noto, la diagnostica chiede `Info` (al massimo 5 s).
- Log dell'app (`Logger('watchparty')`): tipi di evento, esiti delle chiamate, motivi di scarto. Mai il testo dei messaggi, neanche negli errori di lettura (solo il tipo dell'errore).
- Le chiamate al plugin con risposta 404 (plugin assente) o 429 (troppi eventi) vanno nel log `http` a livello info: non finiscono tra gli "Ultimi errori" della diagnostica.
- Discord: invariato.

## 14. Testi nuovi (ARB, it + en)

| Chiave | it | en |
|---|---|---|
| `watchPartyNoticePausedBy` | {name} ha messo in pausa | {name} paused |
| `watchPartyNoticeResumedBy` | {name} ha ripreso | {name} resumed |
| `watchPartyNoticeForcedResumeBy` | {name} ha fatto ripartire senza aspettare | {name} resumed without waiting |
| `watchPartyNoticeSeekBy` | {name} ha saltato a {time} | {name} jumped to {time} |
| `watchPartyNoticeNextEpisodeBy` | {name} ha avviato: {title} | {name} started: {title} |
| `watchPartyNoticeNowWatchingBy` | {name} ha scelto: {title} | {name} picked: {title} |
| `partyChatYou` | Tu | You |
| `partyChatOpen` | Chat (Invio) | Chat (Enter) |
| `partyChatHint` | Scrivi un messaggio… | Write a message… |
| `partyChatNotSent` | Non inviato, riprova | Not sent, try again |
| `partyChatTooMany` | Troppi messaggi, aspetta un attimo | Too many messages, wait a moment |
| `partyReactionsOpen` | Reazioni (1–6) | Reactions (1–6) |
| `partyReactionJoy` | Risata | Laughing |
| `partyReactionScream` | Spavento | Scared |
| `partyReactionCry` | Triste | Sad |
| `partyReactionWow` | Stupore | Amazed |
| `partyReactionClap` | Applauso | Applause |
| `partyReactionFacepalm` | Facepalm | Facepalm |

Le etichette delle reazioni servono da tooltip nella barretta e da etichetta accessibile.

## 15. Test

**Plugin (xUnit):**
- registro (ingresso, uscita, `SessionEnded`, potatura all'inoltro), storico (50, ordine, cancellazione del gruppo), limiti (finestre per tipo), validazione (testo, azioni, reazioni), timbratura (nome dalla sessione, mai dal corpo);
- controller con finti `ISessionManager`, `ISyncPlayManager`, `IAuthorizationContext`: codici 400/403/409/429 (mai 404), destinatari dell'inoltro (escluso il mittente, sessioni morte, utenti usciti).

**App, logica:**
- `parseServerMessage` con `GeneralCommand` (nostro, altrui, malformato); `parsePartyEvent`;
- `PartyChannelApi` con `FakeAdapter` (codici e corpi);
- `PartyChannel` con eventi del server e API finti: ingresso, riconnessione con unione dello storico, uscita, plugin assente, plugin tolto, 409, doppioni, "Tu" da un altro PC, non letti;
- `PartyNotices` con `fakeAsync`: attesa di 300 ms, buffer di 2 s, ripresa forzata, consumo dell'annuncio, canale spento.

**App, interfaccia** (`pumpApp`, banco `pumpPartyPlayer`):
- chat: Invio apre e invia, Invio a campo vuoto chiude, Esc, clic sul film, Spazio nel campo non mette in pausa, durata e numero delle bolle, chiusura dopo 20 s, errori e testo rimesso, contatore 180/200, puntino e contatore fuori dal player;
- reazioni: tasti 1–6 e tastierino, ripetizione ignorata, 200 ms, barretta (clic, chiusure, 5 s), limite di 12, animazioni ridotte, propria reazione subito;
- player: esclusione chat/barretta/pannello, ordine di Esc, livelli, schermata di pausa con la chat aperta, pulsanti assenti senza canale.

**Prova manuale:** plugin copiato via SFTP sul server; due istanze (`WONDERFLIX_PROFILE=b`); nomi negli avvisi, chat, reazioni, riconnessione, plugin rimosso.

## 16. Piani e release

- **10a · Plugin, canale e nomi:**
  - prima una **sonda**: plugin minimo con `Info` e un `Events` che inoltra alla propria sessione, copiato via SFTP; verifica sul server vero che il `GeneralCommand` arrivi all'app;
  - poi il plugin completo (§6) con test, workflow, `manifest.json` (vuoto di versioni) e README;
  - lato app: §7, §8, §13.
  - Prova: "Luca ha messo in pausa".
- **10b · Chat:**
  - prima la verifica che Flutter su Windows disegni a colori le emoji di Segoe UI Emoji;
  - poi §9 e la parte di §11 che riguarda la chat.
- **10c · Reazioni e chiusura:**
  - §10 e il resto di §11;
  - spec allineato all'implementazione; aggiornamenti a Spec B §5.7, Spec D (livelli, Esc, tasti) e `docs/RELEASING.md` (procedura del plugin);
  - release del **plugin 1.0.0** (pre-release, voce nel manifest) e di **WonderFlix 0.5.0**, non obbligatoria.

Ogni piano segue il flusso concordato (worktree, subagent, revisione, prova manuale sul server reale).

## 17. Rischi e punti da verificare

- **Inoltro sul WebSocket:** verificato sul server vero con la sonda del piano 10a (2026-10-02).
- **Policy `SyncPlayHasAccess`** e `IAuthorizationContext` dal pacchetto NuGet: verificati con la sonda (2026-10-02).
- **Emoji a colori** in Flutter su Windows: verificato nel piano 10b. Flutter disegna a colori le emoji di Segoe UI Emoji.
- **Sovrapposizioni:** bolle e reazioni possono coprire righe lunghe di sottotitoli o testi del post-play; da guardare nella prova manuale.
- **Più sessioni dello stesso utente** nel gruppo: l'appartenenza è per nome utente; entrambe ricevono gli eventi, e i propri si mostrano come "Tu".
- **Jellyfin 12:** il plugin va ricompilato prima che l'utente aggiorni il server; senza, l'app degrada da sola (§12).
- **Sicurezza del server:** Jellyfin 10.11.9 è esposto all'avviso GHSA-4vx8-xhc9-qg6x (controllo remoto delle sessioni altrui), corretto solo in 12.0. Non dipende dallo Spec E, che non usa quel permesso.
- **Prestazioni:** reazioni e bolle sopra il video; un solo ticker e `RepaintBoundary`; da misurare con `--profile` se la prova mostra scatti.
