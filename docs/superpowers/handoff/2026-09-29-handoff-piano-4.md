# WonderFlix — passaggio di consegne verso il Piano 4

Documento per riprendere il lavoro in una nuova sessione. Tutto quello che segue è già su `main` ed è pushato su `origin`.

## Stato al 2026-09-29

| Piano | Stato | Documento |
|---|---|---|
| Spec A (client core) | approvato | `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` |
| 1 — fondamenta e login | completato, provato sul server, su `main` | `docs/superpowers/plans/2026-09-29-wonderflix-01-fondamenta-login.md` |
| 2 — Home e catalogo | completato, provato sul server, su `main` | `docs/superpowers/plans/2026-09-29-wonderflix-02-home-catalogo.md` |
| 3a — player di base | completato, provato sul server, su `main` | `docs/superpowers/plans/2026-09-29-wonderflix-03a-player-base.md` |
| 3b — funzioni extra del player | completato, provato sul server, su `main` (ultimo commit `bfda026`) | `docs/superpowers/plans/2026-09-29-wonderflix-03b-player-extra.md` |
| **4 — aggiornamenti, installer, Discord, log** | **da scrivere** | — |
| Spec B — watch party | dopo lo Spec A | — |

Passaggio di consegne precedente (ancora utile per l'ambiente e la ricerca sulle API): `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md`.

**Cosa fa oggi l'app** (verificato dall'utente sul server reale):
- **accesso e navigazione:**
  - login con password o Quick Connect, sessione ricordata, schermata "server irraggiungibile";
  - Home, catalogo, schede di film e serie, attore, ricerca, La mia lista;
  - aggiornamenti in tempo reale via WebSocket;
- **player (media_kit/libmpv):**
  - riproduzione diretta, e se non parte un solo ripiego sulla conversione sul server;
  - tracce audio e sottotitoli (interni, esterni, grafici), ritardo dei sottotitoli ±0,1 s;
  - tastiera, schermo intero, controlli che si nascondono;
  - minutaggio inviato a Jellyfin e aggiornato subito in tutta l'app;
  - salta intro e riassunto, anche in automatico;
  - scheda "Prossimo episodio" con conto alla rovescia e passaggio automatico, anche a schermo intero;
  - anteprime trickplay e tacche dei capitoli sulla barra;
  - trailer locali nel player, remoti nel browser;
  - pannello media di Windows (SMTC);
- **Impostazioni:**
  - lingua dell'interfaccia;
  - sezione Player (qualità "Massima/Alta/Media/Bassa", dimensione dei sottotitoli, decodifica hardware, salto automatico, riproduzione automatica);
  - lingue di audio e sottotitoli salvate sul server;
- **finestra:** una sola istanza (mutex in `windows/runner/main.cpp`); dimensione e posizione ricordate.

**Test:** 333 verdi, `flutter analyze` pulito. La CI (`.github/workflows/ci.yml`) esegue analyze, test e la build Windows, e da ora installa anche Rust.

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, testi UI nei file ARB (it + en).
- **Commit:** con l'identità git dell'utente, **mai** `Co-Authored-By` o "Generated with…". Vale anche per i subagent.
- **Processo per ogni piano:**
  1. `superpowers:writing-plans` → piano in `docs/superpowers/plans/`, commit su `main` (senza push).
  2. Worktree dedicato in `.claude/worktrees/<nome>` sul branch `feat/<nome>`: `git worktree add` da `main`, poi `EnterWorktree` con `path`; copiare `config/wonderflix.json` nel worktree.
  3. `superpowers:subagent-driven-development`:
     - un subagent per gruppo di 2–4 task; il subagent legge dal file del piano le sezioni indicate;
     - controllo dei risultati dopo ogni gruppo;
     - a fine piano, revisione finale del branch con un subagent reviewer e un subagent che corregge i problemi trovati.
  4. Prova manuale insieme all'utente sul server reale, seguendo la checklist dell'ultimo task del piano.
  5. Le modifiche chieste dall'utente durante la prova si fanno con TDD nello stesso worktree.
  6. Solo dopo l'ok dell'utente: merge fast-forward su `main`, push, rimozione del worktree e del branch.
- **UI:** icone solo `LucideIcons`, nessuna emoji. Tema Noir & Oro (`lib/app/theme.dart`).
- L'utente vuole che, quando un piano è grande, gli si proponga prima una divisione (come 3a/3b) e si aspetti la sua conferma.

## Ambiente (particolarità importanti)

- **Flutter 3.47.5** con Visual Studio Build Tools 2026 e il componente ATL.
- **Rust** (serve a `smtc_windows`):
  - installato con rustup (rustc 1.98.1) in `C:\Users\sidot\.cargo\bin`;
  - in una sessione aperta prima dell'installazione non è nel PATH: in Git Bash usare `export PATH="/c/Users/sidot/.cargo/bin:$PATH"` prima di `flutter build` o `flutter run`;
  - la prima build compila Rust e scarica libmpv: servono internet e qualche minuto.
- **`flutter_rust_bridge` è fissato a 2.11.1** in `pubspec.yaml`: è la versione con cui è stato generato `smtc_windows` 1.1.0, e il crate Rust è fissato a `=2.11.1`. Con un'altra versione SMTC non si inizializza (l'app funziona lo stesso, senza pannello). **Non aggiornarlo** senza aggiornare `smtc_windows`.
- **`config/wonderflix.json`** esiste solo in locale (è in `.gitignore`):
  - `serverUrl`, `discordAppId` e `supportUrl` sono valorizzati;
  - `githubRepo` è ancora il valore d'esempio (`davidesidoti/wonderflix`): da decidere col Piano 4, vedi sotto.
- **File generati con modifiche false:** `flutter pub get` / `flutter test` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga. Se `git diff` non mostra cambi di contenuto, eseguire `git checkout -- windows/flutter/`. I cambi veri (nuovi plugin nativi) vanno committati.
- **App aperta:** una build successiva fallisce con `LNK1168`. Soluzione: `taskkill //IM wonderflix.exe //F`.
- **Shell nei worktree:**
  - i comandi git vanno eseguiti dal worktree;
  - la sessione isolata nel worktree rifiuta i comandi composti che mescolano git e variabili: usare comandi semplici e separati;
  - non lanciare `git worktree remove` stando dentro la cartella da rimuovere.
- **Il repository GitHub `davidesidoti/wonderflix` è PRIVATO** (vedi le decisioni per il Piano 4).

## Lezioni dai test (da dare ai subagent)

Oltre a quelle del passaggio di consegne del Piano 3:
- **Dimensione della superficie:** `pumpApp` ha il parametro `surfaceSize`. Chiamare `setSurfaceSize` prima di `pumpApp` non serve, perché `pumpApp` la reimposta.
- **Fake del motore e della sessione media:** usano stream broadcast asincroni. Dopo `emit*` o `press` può servire un `await tester.pump()` in più.
- **Test della schermata del player:** finiscono con l'helper `unmount`, che smonta e fa scadere i timer (report di fine, nascondi controlli, timeline).
- **Log innocuo nei test:** `[player] dati utente non aggiornati: Cannot use the Ref … after it has been disposed` compare quando si smonta tutta la `ProviderScope` mentre il player si sta chiudendo. È previsto e intercettato.
- **Formattazione:** non eseguire `dart format` su file interi. Il progetto non è nello stile "tall" attuale e il comando riscriverebbe tutto.
- **Import:** `debugPrint` arriva già da `material.dart`. Gli import superflui fanno fallire `flutter analyze` (`unnecessary_import`).
- **`flutter test` e i file generati:** `flutter test` riscrive `windows/flutter/generated_plugin*`. Va eseguito `git checkout -- windows/flutter/` prima di ogni commit.

## Punti aperti (non bloccanti)

- **Dalla revisione del 3a, lasciati apposta:**
  - chiudendo il player mentre sta ancora caricando non parte il report di fine;
  - la conversione senza ricodifica (remux) risulta "Transcode" nella Dashboard.
- **Non provati sul server:**
  - schermata d'errore con rete staccata;
  - salvaschermo bloccato durante la visione;
  - trailer locali (l'utente non ne ha);
  - tasti multimediali fisici (la tastiera dell'utente non li ha).
- **Log:** oggi ci sono solo `debugPrint` (circa 18). Il Piano 4 introduce i log su file.

## Piano 4 — cosa copre (dalla spec)

- **§9 Aggiornamenti e distribuzione:**
  - `UpdateService`:
    - `GET https://api.github.com/repos/{githubRepo}/releases/latest` all'avvio e ogni 6 h;
    - confronto semver, download dell'installer in `%TEMP%`, verifica SHA-256;
    - barra "Aggiornamento pronto: Riavvia ora" con le note di rilascio in markdown;
    - mai durante la riproduzione;
    - errori solo nel log.
  - **Aggiornamenti obbligatori:** marcatore `<!-- wonderflix:min-version=X.Y.Z -->` nelle note dell'ultima release; schermata bloccante con avanzamento e *Aggiorna ora*; dopo il video se si stava guardando.
  - **Installer Inno Setup:**
    - installazione per utente in `%LocalAppData%\Programs\WonderFlix`, senza UAC;
    - collegamenti su Start e Desktop, programma di disinstallazione;
    - installazione silenziosa (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`) che riapre l'app.
  - **`release.yml`** (parte con il tag `vX.Y.Z`):
    - config generata dai Secrets;
    - build release, Inno Setup, file `.sha256`;
    - passaggio di firma presente ma spento;
    - GitHub Release creata come bozza.
  - **`docs/RELEASING.md`** con la procedura della §10.
- **§8 Discord Rich Presence:**
  - IPC sulla named pipe `\\.\pipe\discord-ipc-N`;
  - attività *Watching* con titolo, "S1:E4 · titolo" o anno, timestamp, poster o logo, pulsante verso `supportUrl`;
  - "In pausa" senza timestamp; attività cancellata fuori dal player; nuovo tentativo ogni 30 s se Discord non è aperto;
  - impostazioni *mostra attività*, *mostra titolo*, *mostra poster*;
  - prerequisito: app Discord con l'asset `logo`.
- **§11 Log e supporto:**
  - log a rotazione in `%LocalAppData%\WonderFlix\logs` (5 file da 2 MB), senza token, password né header `Authorization`;
  - pulsante "Copia diagnostica" nelle Impostazioni: versioni, impostazioni del player, ultimi 50 errori.
- **§12:** checklist dei test manuali prima di ogni release.
- **Già fatto:** una sola istanza, finestra ricordata.

## Da decidere con l'utente prima di scrivere il piano

1. **Repository privato:** la spec vuole release leggibili senza token, quindi pubbliche. Opzioni:
   - (a) rendere pubblico `davidesidoti/wonderflix`;
   - (b) un repository pubblico solo per le release (es. `davidesidoti/wonderflix-releases`), dove `release.yml` pubblica con un token (Secret); `githubRepo` nella config punta a quello;
   - (c) altro, per esempio un token nell'app (sconsigliato).

   Da questa scelta dipendono `githubRepo` e `release.yml`.
2. **Divisione del piano:** probabile proposta 4a (log + aggiornamenti + installer + release) e 4b (Discord). Proporla e aspettare la conferma, come per il 3.
3. **Discord:** verificare che l'app sul Developer Portal abbia l'asset `logo`.
4. **Versione di partenza:** `pubspec.yaml` è a `0.1.0`. Decidere la prima release (es. `v0.1.0` o `v1.0.0`).

## Ricerca da fare prima di scrivere il piano (non ancora fatta)

- **Pacchetti** (verificare versioni e compatibilità con Flutter 3.47.5):
  - log su file: `logging` più un sink a rotazione scritto a mano, oppure un pacchetto;
  - `crypto` (SHA-256) e `pub_semver`;
  - rendering markdown per le note di rilascio (`flutter_markdown` risulta dismesso: cercare il sostituto attuale).
- **Discord IPC da Dart:**
  - aprire e leggere/scrivere la named pipe con `dart:io` su Windows, oppure un pacchetto esistente;
  - formato dei frame: opcode + lunghezza + JSON, handshake con `client_id`;
  - verificare nella pub cache prima di scegliere.
- **Inno Setup:**
  - se `windows-latest` di GitHub Actions lo include o va installato;
  - come riaprire l'app dopo l'installazione silenziosa (`[Run]` con i flag giusti);
  - disinstallazione pulita.
- **Aggiornamento dall'app:** avviare l'installer con `Process.start` staccato dall'app e poi chiuderla (attenzione: il mutex della singola istanza va rilasciato prima che l'installer riapra l'app).
- **GitHub API:**
  - `releases/latest` esclude bozze e pre-release;
  - limiti delle chiamate senza token (60 all'ora per IP: sufficienti con un controllo ogni 6 h);
  - asset `.exe` e `.sha256` nella risposta.
