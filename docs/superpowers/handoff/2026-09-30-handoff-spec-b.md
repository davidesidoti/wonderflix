# WonderFlix — passaggio di consegne verso lo Spec B (watch party)

Documento per cominciare lo Spec B in una nuova sessione. Tutto quello che segue è già su `main` ed è pushato su `origin`.

## Stato al 2026-09-30

Lo **Spec A (client core) è completo**, dai piani 1–3b al 4b. `main` è al commit `b75cc80`, lo stesso del tag `v0.1.2`, con **468 test verdi** e `flutter analyze` pulito.

| Documento | Stato |
|---|---|
| Spec A: `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` | approvato, realizzato |
| Piani 1, 2, 3a, 3b, 4a, 4b: `docs/superpowers/plans/2026-09-29-wonderflix-0*.md` | completati, provati dall'utente, su `main` |
| Procedura di release: `docs/RELEASING.md` | in uso |
| Passaggi di consegne precedenti: `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md`, `…-piano-4.md` | ancora utili per ambiente e lezioni |
| **Spec B: watch party** | **da scrivere** |

**Release pubblicate** su `github.com/davidesidoti/wonderflix/releases`: `v0.1.0`, `v0.1.1`, `v0.1.2`. La 0.1.2 ha nelle note `<!-- wonderflix:min-version=0.1.2 -->`. L'utente ha provato dal vivo installazione, aggiornamento facoltativo e aggiornamento obbligatorio.

**Il repository è PUBBLICO.** I Secrets `WONDERFLIX_SERVER_URL`, `WONDERFLIX_DISCORD_APP_ID`, `WONDERFLIX_SUPPORT_URL` e `WONDERFLIX_ACCESS_REQUEST_URL` sono configurati.

## Cosa fa oggi l'app

Oltre a quanto elencato nel passaggio di consegne del Piano 4:
- **login e navigazione:** password o Quick Connect; Home, catalogo, dettagli, attore, ricerca, La mia lista; aggiornamenti in tempo reale via WebSocket;
- **player (media_kit/libmpv):**
  - riproduzione diretta con ripiego sulla transcodifica;
  - tracce, sottotitoli e ritardo;
  - salta intro, prossimo episodio, trickplay, capitoli;
  - pannello media di Windows;
- **log e supporto (4a):**
  - log a rotazione in `%LocalAppData%\WonderFlix\logs`, senza segreti;
  - "Copia diagnostica" e "Apri la cartella dei log" nelle Impostazioni;
- **Discord Rich Presence (4a):**
  - attività *Watching* con titolo, episodio, tempi e locandina;
  - pulsante "Chiedi l'accesso" verso il profilo Discord dell'utente (`accessRequestUrl`);
  - tre impostazioni;
- **distribuzione (4b):**
  - installer Inno Setup per utente, con icona a secchiello di popcorn;
  - aggiornamenti automatici e obbligatori da GitHub, mai durante la visione;
  - pipeline `release.yml`, che parte dal tag e crea la bozza.

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, testi UI nei file ARB (it + en).
- **Commit:** con l'identità git dell'utente, **mai** `Co-Authored-By` o "Generated with…". Vale anche per i subagent.
- **Processo per ogni spec o piano:**
  1. **Spec nuovo:** `superpowers:brainstorming` con l'utente, poi il documento in `docs/superpowers/specs/`.
  2. **Piani:** `superpowers:writing-plans`, piano in `docs/superpowers/plans/`, commit su `main` senza push. **Se il piano è grande, proporre prima una divisione (come 3a/3b, 4a/4b) e aspettare la conferma.** Prima di scriverlo, proporre le decisioni aperte e la ricerca fatta.
  3. **Worktree:** in `.claude/worktrees/<nome>` sul branch `feat/<nome>`. Si crea con `git worktree add` da `main`, poi `EnterWorktree` con `path`; va copiato `config/wonderflix.json` nel worktree.
  4. **`superpowers:subagent-driven-development`:**
     - un subagent per gruppo di 2–4 task, che legge dal file del piano le sezioni indicate;
     - controllo dei risultati dopo ogni gruppo;
     - a fine piano, revisione del branch con un subagent reviewer.
  5. **A fine implementazione mi fermo.** Riporto i risultati della revisione con una proposta di correzioni e **aspetto il via dell'utente**. Solo con il via: subagent correttore, poi avvio dell'app o release per la prova.
  6. **Prova manuale** insieme all'utente, sul server reale.
  7. **Modifiche durante la prova:** quelle chieste dall'utente si fanno con TDD nello stesso worktree.
  8. **Chiusura:** solo dopo l'ok dell'utente, merge fast-forward su `main`, push, rimozione di worktree e branch.
- **Release:** a ogni release scrivo io le note nella bozza (`gh release edit vX.Y.Z --notes-file …`, in italiano, dai commit rispetto alla release precedente). Aggiungo il marcatore `min-version` solo se l'aggiornamento è obbligatorio. **La pubblicazione la fa l'utente**, e ogni push di tag solo col suo ok.
- **Marcatore obbligatorio:** vale solo nell'**ultima** release pubblicata. Oggi è `min-version=0.1.2`. Se la prossima release non lo riporta, il blocco sparisce, ma chi ha già la 0.1.2 non ne risente.
- **UI:** icone solo `LucideIcons`, nessuna emoji. Tema Noir & Oro (`lib/app/theme.dart`).

## Ambiente (particolarità importanti)

- **Flutter 3.47.5** con Visual Studio Build Tools 2026 e il componente ATL.
- **Rust** (serve a `smtc_windows`):
  - installato in `C:\Users\sidot\.cargo\bin`;
  - in Git Bash, prima di `flutter build` o `flutter run`: `export PATH="/c/Users/sidot/.cargo/bin:$PATH"`.
- **`flutter_rust_bridge` è fissato a 2.11.1** per `smtc_windows` 1.1.0: non aggiornarlo da solo.
- **`config/wonderflix.json`** esiste solo in locale (in `.gitignore`). Contiene `serverUrl`, `githubRepo` (`davidesidoti/wonderflix`), `discordAppId`, `supportUrl` e `accessRequestUrl`. In CI viene generato dai Secrets.
- **Dopo un pull o un merge nel checkout principale** esegui `flutter pub get` e `flutter gen-l10n`. `lib/l10n/gen` non è versionato: se è vecchio, `flutter test` resta fermo su "loading …" senza un errore chiaro.
- **File generati con modifiche false:** `flutter test`, `pub get` e `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff` non mostra cambi di contenuto, `git checkout -- windows/flutter/`.
- **App aperta:** una build fallisce con `LNK1168`. Si risolve con `taskkill //IM wonderflix.exe //F`.
- **App avviata da Claude:** l'app desktop di Claude è un pacchetto MSIX e virtualizza le scritture in `AppData` dei processi che lancia. Log, file e cartelle non si vedono in Esplora risorse, e "Apri la cartella" non funziona. Per queste prove, e **sempre** per installer e app installata, l'exe lo avvia l'utente da Esplora risorse.
- **Shell nei worktree:**
  - la sessione isolata rifiuta i comandi composti che mescolano git e variabili: usare comandi semplici e separati;
  - non lanciare `git worktree remove` dall'interno della cartella da rimuovere.
- **Fine riga:** molti file sono CRLF (ARB, `main.dart`, `.gitignore`…). Modificarli con Edit mirati. `installer/wonderflix.iss` ha un BOM UTF-8, da mantenere.
- **`gh`** è autenticato come l'utente: serve per release, Actions e Secrets (solo i nomi).

## Lezioni dai test (da dare ai subagent)

Oltre a quelle dei passaggi di consegne precedenti:
- **`pumpApp` e Scaffold:** `pumpApp` ha `surfaceSize`; non mette uno `Scaffold`, che serve per SnackBar, Switch e simili.
- **Stream dei fake:** i fake di motore e sessione media usano stream broadcast asincroni, quindi può servire un `await tester.pump()` in più.
- **Microtask:** `playerActiveProvider` pubblica lo stato in un microtask; dopo `enter()`/`leave()` servono due `pump()`.
- **Tempo nei test:** `fakeAsync` e il pacchetto `clock` vanno insieme. Il codice deve usare `clock.now()`, mai `DateTime.now()`, se si vuole il tempo finto. Nei test `fakeAsync` evitare l'I/O asincrono su disco, perché non si completa nel tempo finto.
- **`find.byType`:** non trova le sottoclassi (es. `FilledButton.icon`); usare `find.byWidgetPredicate((w) => w is FilledButton)`.
- **Log nei test:** nessuno ascolta `Logger.root`. Chi verifica i log si iscrive a `Logger.root.onRecord`.
- **Formattazione:** non eseguire `dart format` su file interi.

## Punti aperti (non bloccanti)

- Chiudendo il player mentre sta ancora caricando non parte il report di fine.
- La conversione senza ricodifica (remux) risulta "Transcode" nella Dashboard.
- **Non provati sul server:**
  - schermata d'errore con la rete staccata;
  - salvaschermo bloccato durante la visione;
  - trailer locali;
  - tasti multimediali fisici.
- `WriteFile` sulla pipe di Discord è sincrono sul thread UI: blocco molto improbabile, lasciato così.
- **Firma del codice:** spenta. Prima di accenderla vedi la nota in `docs/RELEASING.md`.
- **Icona sulla barra delle applicazioni:** dopo l'aggiornamento alla 0.1.1 era rimasta quella vecchia (cache di Windows). La 0.1.2 aggiunge `ChangesAssociations=yes`; l'effetto si vedrà con il prossimo aggiornamento.

## Spec B: cosa si sa già

Dalla spec A, §13:
- Jellyfin ha già **SyncPlay** lato server. Il comportamento lamentato dall'utente con i client attuali (il video che va avanti o indietro da solo) viene dalle correzioni di sincronizzazione del client (SkipToSync/SpeedToSync) e da come vengono propagati i salti.
- **Da definire nello Spec B:**
  - regole precise sui salti nel gruppo: chi può saltare, cosa vedono gli altri;
  - strategia di correzione: preferire piccoli aggiustamenti di velocità ai salti.

### Cosa offre già il codice

- **`VideoEngine`** (`lib/core/video/video_engine.dart`):
  - `open`, `play`, `pause`, `seek`, `setVolume`, tracce, sottotitoli;
  - stream di posizione, durata, buffer, riproduzione, buffering, fine ed errore.
  - **Attenzione:** manca il controllo della **velocità** (`setRate`), anche se la spec A §4 la cita. Va aggiunta (media_kit: `Player.setRate`) per la correzione con la velocità.
- **`ServerEvents`** (`lib/core/jellyfin/server_events.dart`):
  - WebSocket di sessione con keep-alive;
  - oggi gestisce `UserDataChanged`, `LibraryChanged`, `ForceKeepAlive`;
  - vanno aggiunti `SyncPlayCommand` e `SyncPlayGroupUpdate`.
- **`PlayerController`** / **`PlayerScreen`**:
  - player con overlay estendibile e comandi da tastiera;
  - report dell'avanzamento a Jellyfin;
  - passaggio all'episodio successivo con `pushReplacement`.
- **`MediaSession`** (`MirroredMediaSession`): SMTC più Discord. La Rich Presence potrebbe mostrare "Watch party con N persone".
- **`playerActiveProvider`**: sa se il player è aperto.
- **`UpdateGate`**: gli aggiornamenti non interrompono la visione.

### Ricerca da fare prima di scrivere lo Spec B

- **API SyncPlay di Jellyfin 10.11.9.** Riferimento: `docs/reference/jellyfin-openapi-10.11.9.json`.
  - **Endpoint (tutti `POST` tranne List e `{id}`):**
    - gruppi: `/SyncPlay/New`, `/Join`, `/Leave`, `/List`, `/{id}`;
    - riproduzione: `/Pause`, `/Unpause`, `/Seek`, `/Stop`, `/Buffering`, `/Ready`, `/Ping`, `/SetIgnoreWait`;
    - coda: `/SetNewQueue`, `/Queue`, `/SetPlaylistItem`, `/NextItem`, `/PreviousItem`, `/RemoveFromPlaylist`, `/MovePlaylistItem`, `/SetRepeatMode`, `/SetShuffleMode`.
  - **Messaggi WebSocket:** `SyncPlayCommand` (`SendCommandType`: `Unpause`, `Pause`, `Stop`, `Seek`, con `When` e `PositionTicks`) e `SyncPlayGroupUpdate` (`GroupUpdateType`: `UserJoined`, `UserLeft`, `GroupJoined`, `GroupLeft`, `StateUpdate`, `PlayQueue`, `NotInGroup`, `GroupDoesNotExist`, `LibraryAccessDenied`).
  - **Stati del gruppo:** `Idle`, `Waiting`, `Paused`, `Playing`.
  - **Sincronizzazione dell'orologio:** `GET /GetUtcTime` (`RequestReceptionTime` / `ResponseTransmissionTime`), per stimare lo scarto tra client e server come fa jellyfin-web.
  - **Permessi:** `SyncPlayUserAccessType` sull'utente (chi può creare o unirsi ai gruppi).
- **Implementazione di jellyfin-web** (`src/plugins/syncPlay/` nel repository `jellyfin/jellyfin-web`): come stima lo scarto dell'orologio, quando usa SpeedToSync e SkipToSync, con quali soglie. Serve per capire da dove vengono i salti lamentati.
- **Come trovare e unirsi a un gruppo** dall'interfaccia: lista dei gruppi, invito, e rapporto con Discord (il pulsante dell'attività oggi apre il profilo dell'utente).
- **Transcodifica e buffering:** con un membro in transcodifica i tempi di avvio e di buffering cambiano. Capire come SyncPlay gestisce `Buffering`/`Ready`.

### Da chiarire con l'utente durante il brainstorming

- Chi può mettere in pausa, saltare e cambiare episodio (tutti, o solo chi ha creato il gruppo).
- Cosa succede quando qualcuno va in buffering: aspettano tutti, o si prosegue.
- Tolleranza di sincronizzazione accettabile, e se preferire la correzione con la velocità ai salti anche per scarti grandi.
- Interfaccia: dove si crea e dove si entra in un gruppo; cosa si vede nel player (membri, stato).
- Compatibilità con jellyfin-web e altri client nello stesso gruppo: requisito, oppure solo WonderFlix.
- Come dividere lo Spec B in piani.
