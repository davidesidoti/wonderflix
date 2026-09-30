# WonderFlix — passaggio di consegne verso lo Spec C

Documento per cominciare il prossimo spec in una nuova sessione. **L'argomento dello Spec C non è ancora scelto**: si decide con l'utente all'inizio del brainstorming, partendo dai candidati qui sotto.

## Stato al 2026-09-30

Lo **Spec A (client core)** e lo **Spec B (watch party)** sono completi. `main` è al commit `1c1745c` (`chore: release 0.2.0`), lo stesso del tag `v0.2.0`, con **709 test verdi** e `flutter analyze` pulito.

| Documento | Stato |
|---|---|
| Spec A: `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` | realizzato |
| Spec B: `docs/superpowers/specs/2026-09-30-wonderflix-watch-party-design.md` | realizzato |
| Piani 1–4b: `docs/superpowers/plans/2026-09-29-wonderflix-0*.md` | completati, su `main` |
| Piani 5a, 5b, 5c: `docs/superpowers/plans/2026-09-30-wonderflix-05*.md` | completati, provati dall'utente, su `main` |
| Procedura di release: `docs/RELEASING.md` | in uso |
| Passaggi di consegne precedenti: `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md`, `…-piano-4.md`, `2026-09-30-handoff-spec-b.md` | ancora utili per ambiente e lezioni |
| **Spec C** | **argomento da scegliere, poi da scrivere** |

**Release pubblicate** su `github.com/davidesidoti/wonderflix/releases`: `v0.1.0`, `v0.1.1`, `v0.1.2`, **`v0.2.0`**. La 0.2.0 contiene il watch party ed è **obbligatoria** (`<!-- wonderflix:min-version=0.2.0 -->` nelle note).

**Il repository è PUBBLICO.** I Secrets `WONDERFLIX_SERVER_URL`, `WONDERFLIX_DISCORD_APP_ID`, `WONDERFLIX_SUPPORT_URL` e `WONDERFLIX_ACCESS_REQUEST_URL` sono configurati.

## Cosa fa oggi l'app

Oltre a quanto elencato nel passaggio di consegne dello Spec B (login, catalogo, player, log, Discord, aggiornamenti):
- **Watch party (Spec B):**
  - film e serie insieme, su SyncPlay di Jellyfin 10.11, solo tra client WonderFlix;
  - tutti comandano: pausa, ripresa, salto (con attesa di 400 ms per i salti da tastiera), prossimo episodio;
  - orologio del server stimato in stile NTP (`ServerClock`), correzione dello scarto con la velocità 0,95/1,05 e salto solo oltre 3 s (`DriftCorrector`), compensazione del ritardo di ripartenza di mpv (`StartLag`);
  - tutti aspettano chi è in buffering, con "Riprendi senza aspettare"; se il video non si apre per qualcuno, il gruppo va avanti;
  - avvisi anonimi nel player (il server non dice chi ha agito), badge del gruppo, schermata d'attesa;
  - elenco dei gruppi e inviti nella barra in alto (solo nell'app);
  - "Guarda insieme" dalla scheda e dal player (riapre il player sullo stesso punto, lo schermo intero resta com'è);
  - rientro automatico nel gruppo a ogni riconnessione del WebSocket;
  - permessi SyncPlay dell'utente (`SyncPlayAccess`): le azioni non consentite non compaiono;
  - Discord "Watch party · N persone" e riga del watch party nella diagnostica.

### Mappa del codice del watch party

- `lib/core/syncplay/`: modelli e parsing (`syncplay_models.dart`), client API (`syncplay_api.dart`), `server_clock.dart`, `drift_corrector.dart`, `start_lag.dart`. Logica in Dart puro, senza Flutter.
- `lib/features/watch_party/`: `WatchPartySession` (stato del gruppo, rientro), `GroupPlaybackDriver` (comandi → player, Ready/Buffering, correzione), `GroupAuthority` (azioni del player → server), routing, elenco e inviti, avvisi, pulsanti e badge.
- `lib/features/player/`: `PlayerArgs` con `party`, `PlaybackAuthority`, passaggio di consegne tra player (`player_handover.dart`).

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, testi UI nei file ARB (it + en).
- **Commit:** con l'identità git dell'utente, **mai** `Co-Authored-By` o "Generated with…". Vale anche per i subagent.
- **Processo per ogni spec o piano:**
  1. **Spec nuovo:** ricerca, poi `superpowers:brainstorming` con l'utente, poi il documento in `docs/superpowers/specs/`. Lo spec si scrive solo quando le decisioni sono chiare.
  2. **Divisione in piani:** proporla prima di scrivere i piani (come 5a/5b/5c) e aspettare la conferma.
  3. **Piani:** `superpowers:writing-plans`, piano in `docs/superpowers/plans/`, commit su `main` senza push. Prima di scriverlo, proporre le decisioni aperte e la ricerca fatta.
  4. **Worktree:** in `.claude/worktrees/<nome>` sul branch `feat/<nome>`. Si crea con `git worktree add` da `main`, poi `EnterWorktree` con `path`; va copiato `config/wonderflix.json` nel worktree.
  5. **`superpowers:subagent-driven-development`:**
     - un subagent per gruppo di 2–4 task, che legge dal file del piano le sezioni indicate;
     - controllo dei risultati dopo ogni gruppo;
     - a fine piano, revisione del branch con un subagent reviewer.
  6. **A fine implementazione mi fermo.** Riporto i risultati della revisione con una proposta di correzioni e **aspetto il via dell'utente**. Solo con il via: subagent correttore, poi build di release e test.
  7. **Prova manuale** insieme all'utente, sul server reale. L'exe lo avvia **sempre** l'utente.
  8. **Modifiche durante la prova:** quelle chieste dall'utente si fanno con TDD nello stesso worktree.
  9. **Chiusura:** solo dopo l'ok dell'utente, merge fast-forward su `main`, push, rimozione di worktree e branch.
- **Release:** a ogni release scrivo io le note nella bozza (`gh release edit vX.Y.Z --notes-file …`, in italiano, dai commit rispetto alla release precedente). Aggiungo il marcatore `min-version` solo se l'aggiornamento è obbligatorio. **La pubblicazione la fa l'utente**, e ogni push di tag solo col suo ok.
- **Versioni:** si resta su 0.x; **v1.0.0 = prima release per gli amici**. Una nuova funzione alza la minore (0.2.0 → 0.3.0), le sole correzioni la patch.
- **Marcatore obbligatorio:** vale solo nell'**ultima** release pubblicata. Oggi è `min-version=0.2.0`.
- **UI:** icone solo `LucideIcons`, nessuna emoji. Tema Noir & Oro (`lib/app/theme.dart`).
- **App dell'utente:** non chiudere mai le istanze aperte dall'utente (`taskkill`) senza chiedere.

## Ambiente (particolarità importanti)

Valgono tutte quelle del passaggio di consegne dello Spec B (Flutter 3.47.5, Rust in `C:\Users\sidot\.cargo\bin`, `flutter_rust_bridge` fissato a 2.11.1, `config/wonderflix.json` solo in locale, `flutter pub get` + `flutter gen-l10n` dopo un merge, `git checkout -- windows/flutter/` per i falsi cambi di fine riga, `LNK1168` con l'app aperta, virtualizzazione MSIX, file CRLF, `gh` autenticato). In più:
- **Build di release per le prove:**
  ```bash
  export PATH="/c/Users/sidot/.cargo/bin:$PATH"
  flutter build windows --release --dart-define-from-file=config/wonderflix.json
  ```
  Senza `--dart-define-from-file` l'app mostra "Configurazione mancante".
- **Seconda istanza** (per tutto ciò che coinvolge due utenti): variabile d'ambiente `WONDERFLIX_PROFILE=b`. Ha mutex, preferenze, credenziali, log e `DeviceId` propri. La avvia l'utente, per esempio da PowerShell: `$env:WONDERFLIX_PROFILE='b'; & .\build\windows\x64\runner\Release\wonderflix.exe`.
- **Log delle istanze avviate dall'utente:** da questa sessione si vede una copia vecchia (virtualizzazione MSIX, anche via Windows-MCP). Per leggerli, l'utente allega il file `%LocalAppData%\WonderFlix\logs\wonderflix.log`.
- **Worktree con l'app aperta:** se l'utente ha avviato l'exe dal worktree, la cartella resta bloccata dopo `git worktree remove`. Si cancella più tardi, quando l'app è chiusa.
- **Comandi `gh` in modalità automatica:** possono essere bloccati dal classificatore dei permessi. In quel caso fermarsi e chiedere il permesso all'utente.

## Lezioni dai test (da dare ai subagent)

Oltre a quelle dei passaggi di consegne precedenti:
- **Riverpod 3:** l'istanza del `Notifier` resta tra un rebuild e l'altro, ma `ref.onDispose` scatta a **ogni** rebuild. I listener partono nell'ordine di registrazione.
- **go_router 18:** dopo `push`, `routeInformationProvider.value.uri` è la pagina di **base**. La pagina in cima è `GoRouter.of(context).state.uri` (o `router.state.uri`).
- **`fakeAsync` e stream:** gli eventi arrivano nella zona in cui il listener si è iscritto. Chi si iscrive va creato (`mount()`) **dentro** `fakeAsync`.
- **Timer nei widget test:** alla fine del test non devono restare timer pendenti; usare un helper di chiusura che smonta l'albero e avanza il tempo.
- **Fake con liste:** restituire la **stessa** lista non notifica nulla ai provider; il fake deve creare una lista nuova a ogni modifica.
- **`PopupMenuItem` nei test:** con la superficie stretta le etichette vanno avvolte in `Flexible`, altrimenti overflow.
- **media_kit:** `setRate` mantiene il tono dell'audio (verificato).

## Punti aperti (non bloccanti)

Dallo Spec B:
- Il nome del gruppo non cambia se il gruppo passa a un altro titolo (il server non lo permette).
- All'ingresso di un membro il server mette in pausa tutti: regola del server, spiegata dagli avvisi.

Dai passaggi di consegne precedenti, ancora aperti:
- Chiudendo il player mentre sta ancora caricando non parte il report di fine.
- La conversione senza ricodifica (remux) risulta "Transcode" nella Dashboard.
- **Non provati sul server:** schermata d'errore con la rete staccata, salvaschermo bloccato durante la visione, trailer locali, tasti multimediali fisici.
- `WriteFile` sulla pipe di Discord è sincrono sul thread UI: blocco molto improbabile.
- **Firma del codice:** spenta (nota in `docs/RELEASING.md`).
- **Icona sulla barra delle applicazioni:** con la 0.1.2 è arrivato `ChangesAssociations=yes`; va verificato con l'aggiornamento alla 0.2.0 se l'icona vecchia è sparita.

## Spec C: candidati

L'utente sceglie all'inizio. Per ciascuno, cosa si sa e cosa cercare prima del brainstorming.

**Escluso per scelta dell'utente:** entrare in un watch party da Discord o con un collegamento `wonderflix://`. Non riproporlo.

### 1. Versione web

L'utente prevede una versione web di WonderFlix, usata da tutti gli utenti con il protocollo WonderFlix (anche nel watch party). Per questo la logica di sincronizzazione è in Dart puro in `lib/core/syncplay/`.
- **Da cercare:**
  - Flutter web e riproduzione video: media_kit sul web usa `<video>` (niente libmpv); quali formati passano in riproduzione diretta nel browser e quanto si ricade sulla transcodifica HLS;
  - sottotitoli ASS/PGS sul web (niente libass): bruciati dal server o renderer JS;
  - CORS e autenticazione verso Jellyfin dal browser; dove salvare il token;
  - precisione di `currentTime` e `playbackRate` di `<video>` per il `DriftCorrector`;
  - cosa non esiste sul web: SMTC, Discord Rich Presence (IPC locale), installer e aggiornamenti, `window_manager`, mutex;
  - hosting (GitHub Pages o sul server) e configurazione senza `--dart-define-from-file` pubblico.
- **Da chiarire:** stesso codice con implementazioni per piattaforma o app separata; perimetro della prima versione (solo watch party, o client completo).

### 2. Watch party: nome di chi agisce, chat, reazioni

Esclusi dallo Spec B perché il server SyncPlay non dice chi ha agito. Servono un canale proprio: **plugin del server Jellyfin** (C#) con messaggi propri sul WebSocket, oppure un servizio separato.
- **Da cercare:** API dei plugin Jellyfin 10.11 (endpoint propri, `ISessionManager.SendMessageToUserSessions`), distribuzione del plugin (repository di plugin), compatibilità con aggiornamenti del server.

### 3. Gestione avanzata della coda del gruppo

Aggiungere elementi, riordinare, ripetizione, ordine casuale: gli endpoint esistono già (`/Queue`, `/SetPlaylistItem`, `/PreviousItem`, `/RemoveFromPlaylist`, `/MovePlaylistItem`, `/SetRepeatMode`, `/SetShuffleMode`). Oggi la coda è solo impostata alla creazione (max 50 episodi).

### 4. Funzioni escluse dallo Spec A

- Profili "Chi guarda?" (più utenti sullo stesso PC).
- Collezioni / saghe (`BoxSet` di Jellyfin).
- Download per la visione offline (API `/Items/{id}/Download`, transcodifica per il download, spazio su disco, report dell'avanzamento offline).
- Output HDR vero (oggi media_kit converte in SDR; opzioni `vo=gpu-next`, `target-colorspace-hint` di mpv, HDR di Windows).
- Firma del codice (pipeline già predisposta).

### 5. Rifinitura per la v1.0.0

La v1.0.0 è la prima release per gli amici. Uno spec potrebbe raccogliere i punti aperti qui sopra, le prove mai fatte sul server e ciò che l'utente vuole prima di distribuirla (per esempio la pagina di richiesta d'accesso, la prima esecuzione, la firma del codice).

### 6. Rinnovo grafico

L'utente vuole un'app più "viva" e più bella da vedere. **I colori Noir & Oro restano** (`lib/app/theme.dart`); cambiano movimento e cura dei dettagli.
- **Cosa c'è oggi:**
  - transizione tra le pagine: una sola, di 150 ms (`CustomTransitionPage` in `lib/app/router.dart`);
  - nessun `Hero`, `AnimatedSwitcher` o `AnimationController` fuori dal player;
  - immagini con segnaposto blurhash (`lib/ui/wf_image.dart`, `flutter_blurhash`);
  - scroll di Flutter standard: su Windows la rotella del mouse avanza a scatti, senza inerzia.
- **Da cercare:**
  - **scroll morbido con la rotella:** `ScrollBehavior` e `ScrollPhysics` personalizzati, o intercettare `PointerScrollEvent` e animare verso la destinazione; pacchetti esistenti e compatibilità con le righe orizzontali (Home, catalogo) e con il touchpad (che è già fluido e non va toccato);
  - **transizioni tra le pagine:** `Hero` della locandina da scheda a dettaglio, dissolvenze e scorrimenti con go_router (`CustomTransitionPage`), il pacchetto `animations` (shared axis, fade through, container transform);
  - **micro-animazioni:** hover e focus delle schede (scala, ombra, bordo oro), comparsa scaglionata delle righe e delle griglie, `AnimatedSwitcher` per caricamento → contenuto, skeleton/shimmer al posto degli spinner;
  - **pagina di dettaglio:** sfondo con parallasse, testata che si restringe allo scroll, titolo che compare nella barra;
  - **prestazioni:** 60 fps anche su PC modesti, `RepaintBoundary`, costo delle immagini grandi, `MediaQuery.disableAnimations` / preferenza di Windows "Effetti di animazione" da rispettare;
  - **coerenza:** durate e curve in un unico posto (token del tema), in stile con il player (che ha già il suo overlay animato).
- **Da chiarire:** quanto spingere (sobrio o spettacolare), quali schermate per prime (Home e dettaglio?), se serve un'impostazione per ridurre le animazioni, riferimenti visivi che piacciono all'utente (Netflix, Apple TV, Disney+…). Il visual companion del brainstorming aiuta a confrontare le proposte.
- **Prove:** i widget test con animazioni lunghe o ripetute richiedono `pumpAndSettle` con attenzione (animazioni infinite = test bloccato) e nessun timer pendente a fine test.

## Primo passo della nuova sessione

1. Leggere questo documento e, per l'argomento scelto, le sezioni relative degli spec A e B.
2. Chiedere all'utente quale candidato diventa lo Spec C (o se ne ha un altro).
3. Fare la ricerca indicata per quel candidato, poi `superpowers:brainstorming`.
