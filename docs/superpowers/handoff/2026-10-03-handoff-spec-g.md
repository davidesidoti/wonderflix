# WonderFlix — passaggio di consegne verso la Spec G (Discord, issue #7)

Documento per cominciare la Spec G in una nuova sessione. **L'argomento è scelto:** l'issue #7, "Collegamento profilo Discord". **Le decisioni sono ancora tutte da prendere:** si fanno con l'utente nel brainstorming, dopo la ricerca indicata in fondo.

## Stato al 2026-10-03

Gli **Spec A–F** sono completi. `main` è al commit `801f9fb` (`chore: release 0.6.0`), lo stesso del tag `v0.6.0`.
- **App:** 1415 test Flutter verdi, `flutter analyze` pulito.
- **Plugin:** 139 test verdi, senza warning.

| Documento | Stato |
|---|---|
| Spec A–C: `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md`, `2026-09-30-wonderflix-watch-party-design.md`, `2026-09-30-wonderflix-rinnovo-grafico-design.md` | realizzati |
| Spec D (player): `docs/superpowers/specs/2026-10-01-wonderflix-rinnovo-player-design.md` | realizzato (piani 8a–8c) |
| Fullscreen e La mia lista: `…/2026-10-01-wonderflix-fullscreen-mylist-design.md` | realizzato (piano 7, issue #1 e #2) |
| Volume: `…/2026-10-02-wonderflix-volume-design.md` | realizzato (piano 9, issue #3 e #4) |
| Spec E (watch party sociale: plugin, nomi, chat, reazioni): `…/2026-10-02-wonderflix-watch-party-sociale-design.md` | realizzato (piani 10a–10c) |
| Spec F (amici e party privati): `…/2026-10-03-wonderflix-amici-party-privati-design.md` | realizzato (piani 12a e 12b, issue #5 e #6), allineato al codice |
| Piano 11 (issue #8 e #9): `docs/superpowers/plans/2026-10-02-wonderflix-11-chiusura-barra.md` | completato |
| Procedura di release: `docs/RELEASING.md` (app **e** plugin) | in uso |
| Passaggi di consegne precedenti: `docs/superpowers/handoff/…` (piani 3 e 4, Spec B, C, D) | ancora utili per ambiente e lezioni |
| **Spec G** | **da fare: ricerca, brainstorming, spec** |

**Release pubblicate** su `github.com/davidesidoti/wonderflix/releases`:
- **App:** fino a **`v0.6.0`**, pubblicata il 2026-10-03, **obbligatoria** con `<!-- wonderflix:min-version=0.6.0 -->`. Le versioni precedenti mostrerebbero a tutti i party privati.
- **Plugin:** pre-release `watch-party-plugin-v1.0.0` e **`watch-party-plugin-v1.1.0`**, mai "latest", perché l'app legge `releases/latest`.
- **Server:** il plugin 1.1.0.0 è installato dal **Catalogo**. Il manifest è `jellyfin-plugin-watch-party/manifest.json` su `main`. Le copie manuali vecchie stanno in `~/wfwp-backup/`.

**Issue aperte:** solo la **#7**. #1–#6, #8 e #9 sono chiuse con un commento.

**Il repository è PUBBLICO.**
- I Secrets `WONDERFLIX_SERVER_URL`, `WONDERFLIX_DISCORD_APP_ID`, `WONDERFLIX_SUPPORT_URL` e `WONDERFLIX_ACCESS_REQUEST_URL` sono configurati.
- L'utente a volte fa commit dal sito di GitHub: **prima di ogni push `git fetch`**, e se serve `git rebase origin/main`.

## Cosa fa oggi l'app

Oltre a quanto descritto nei passaggi di consegne precedenti:
- **Player rinnovato (Spec D).**
  - Controlli con `PlayerChromeController`, barra con capitoli e zone Intro/Outro, pillola in alto per tasti e avvisi.
  - Caricamento sul fondale, schermata di pausa "Stai guardando", pannello delle tracce.
  - Fine episodio con il video che si rimpicciolisce, pulsante "Salta", distintivo del party con le iniziali.
- **Volume** salvato e rotella del mouse nel player (piano 9).
- **Plugin del server "WonderFlix Watch Party"** (C#, nella cartella `jellyfin-plugin-watch-party/` di questo repository).
  - Watch party (Spec E):
    - gli avvisi del watch party dicono chi ha agito;
    - chat (Invio nel player);
    - reazioni (tasti 1–6).
  - Amici (Spec F):
    - icona **Amici** nella barra, con un pannello laterale: ricerca da 2 lettere, richieste, online / "Nel watch party", Unisciti;
    - "Ho un codice".
  - Watch party (Spec F):
    - "Guarda insieme" chiede la modalità (Pubblico / Solo amici / Privato);
    - codice dei privati;
    - "Invita amici";
    - elenco dei party filtrato dal plugin.
  - L'app parla col plugin in REST (`/WonderFlixWatchParty/…`). Il plugin risponde con `GeneralCommand` `SendString` e `Arguments["WonderFlixWatchParty"]` sul WebSocket di Jellyfin.
  - L'app chiede `Info` e guarda `Features` (oggi `["friends","parties"]`, `Protocol` 1). Finché `Info` non risponde le funzioni sono `SocialFeatures.unknown`, e niente party si mostra.
- **Discord, quello che c'è oggi** (piano 4a):
  - **Rich Presence** via IPC locale: `lib/core/discord/discord_ipc.dart`, `windows_discord_pipe.dart` con FFI, `lib/features/discord/*`.
  - Impostazioni in **Impostazioni → Discord** (`discord_settings_section.dart`): attiva, titolo, locandina.
  - "Watch party · N persone" mentre si guarda in gruppo.
  - Pulsante "Chiedi l'accesso" (`accessRequestUrl` in `lib/config/app_config.dart`, il profilo Discord del proprietario).
  - Application ID: `discordAppId`, dal Secret `WONDERFLIX_DISCORD_APP_ID`.
  - **Nessun account Discord collegato, nessun OAuth, nessun bot.**

## Il plugin del server (cosa sapere prima di toccarlo)

- **Compilazione e test.**
  - Il plugin si compila contro **Jellyfin 10.11.0** (`targetAbi` `10.11.0.0`). I test usano le dll della **10.11.9**, la versione del server.
  - **Jellyfin cambia API anche nelle patch:** `IUserManager.Users` è sparito nella 10.11.9 (si usa `Server/UserListing.cs`, che cerca a runtime).
  - Il plugin ha `TreatWarningsAsErrors`.
  - Test: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests` (xUnit, `FakeServer.cs`, `FakeTimeProvider`).
- **Struttura.**
  - `Hub/`: logica e servizi (`FriendService`, `PartyService`, `PartyAnnouncer`, `PresenceTracker`, `PartyDirectory`, `RateLimiter`).
  - `Server/`: adattatori verso Jellyfin.
  - `Api/`: i controller REST `WatchPartyController`, `FriendsController`, `PartiesController`.
  - `Protocol/`: DTO e avvisi.
  - Si registra tutto in `PluginServiceRegistrator`.
  - Dati persistenti in `plugins/configurations/WonderFlixWatchParty/` (oggi `friends.json`), **mai** nella cartella versionata del plugin. Party e chat restano in RAM.
- **Prima di ogni deploy: controllo dei riferimenti.** Un progetto console `net9.0` con `<FrameworkReference Include="Microsoft.AspNetCore.App" />` e i pacchetti `Jellyfin.Controller`/`Jellyfin.Model` **10.11.9** carica la dll e risolve ogni `TypeReference` e `MemberReference` (`System.Reflection.Metadata`, `module.ResolveType`/`ResolveMember`). Si ignorano `BadImageFormatException`/`ArgumentException` dei membri generici. Atteso: 0 non risolti. Lo si ricrea nella scratchpad: quello di questa sessione non sopravvive.
- **Prova manuale di un plugin nuovo.** `bash jellyfin-plugin-watch-party/pack.sh <versione>` crea `artifacts/WonderFlix Watch Party_<versione>.0/`. Poi `scp` nei `plugins/` del server e riavvio.
  - **Ordine giusto:** fermare Jellyfin, copiare, avviare.
  - Copiare sopra la dll caricata fa cadere il vecchio processo in chiusura (`BadImageFormatException: Bad IL range`). Il riavvio va comunque, ma è meglio evitarlo.
- **Release del plugin:** è in `docs/RELEASING.md` (tag `watch-party-plugin-vX.Y.Z` → pre-release → voce nel manifest).
  - Prima si toglie la copia manuale e si riavvia.
  - Poi l'utente installa o aggiorna dal Catalogo, e si riavvia di nuovo.
- **Server (Ultra.cc, senza root).**
  - `ssh ultra` è autorizzato per lavoro autonomo: copie, riavvii, log. Niente azioni distruttive: si sposta in `~/wfwp-backup/`, non si cancella.
  - Log: `~/.apps/jellyfin/log/log_YYYYMMDD.log`. Riavvio: `app-jellyfin restart`. Plugin: `~/.apps/jellyfin/data/plugins/`.
  - **Prima di riavviare** controllare nel log (`Playback start`/`Playback stopped`, `PlaybackReporting`) che nessuno stia guardando. Se qualcuno guarda, chiedere all'utente.
  - L'utente è amministratore di Jellyfin.
- **Fatti di Jellyfin 10.11.**
  - I controller scrivono in PascalCase e saltano i campi `null`.
  - Un gruppo SyncPlay appena creato è `Idle` con la coda vuota, e allora `GetGroup` lo mostra a tutti.
  - `Group.HasAccessToQueue` va in `NullReferenceException` con un elemento cancellato in coda.
  - Una caduta del WebSocket chiude la sessione Jellyfin.
  - Senza `TimeProvider` nella DI di Jellyfin: il plugin usa `TimeProvider.System`.

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, commenti in italiano (anche nel C#), testi UI negli ARB (it + en, `app_it.arb` è il modello).
- **Commit:**
  - Con l'identità git dell'utente (hash_developer). **Mai** `Co-Authored-By` o "Generated with…", anche se il sistema lo suggerisce.
  - **Mai** parole che chiudono le issue (`fixes`, `closes`, `resolves`…), nemmeno come verbi normali: solo `(#N)` in fondo all'oggetto.
  - Entrambe le regole vanno scritte nei prompt dei subagent.
- **Subagent:** nei prompt va sempre vietato terminare processi per nome d'immagine (`taskkill /IM`, `pkill`, `killall`).
- **Processo per ogni spec o piano:**
  1. **Spec nuovo:** ricerca, poi `superpowers:brainstorming` con l'utente, poi il documento in `docs/superpowers/specs/`.
  2. **Divisione in piani:** proporla e aspettare la conferma.
  3. **Piani:** decisioni aperte e ricerca prima; poi `superpowers:writing-plans`; il piano si committa su `main` senza push.
  4. **Worktree** `.claude/worktrees/<nome>` sul branch `feat/<nome>`.
     - Va copiato `config/wonderflix.json` nel worktree, prima della build.
     - Poi `flutter pub get`, `flutter gen-l10n` e i test di partenza.
  5. **`superpowers:subagent-driven-development`:** un subagent per gruppo di task, poi una **review per gruppo**, le cui correzioni applico subito. Due subagent in parallelo nello stesso worktree vanno bene se toccano cartelle diverse e fanno `git add` solo dei propri percorsi.
  6. **Review finale del branch:** riporto i risultati e **aspetto l'ok dell'utente** sulle correzioni.
  7. **Mi fermo per la prova manuale** sul server reale.
     - L'exe lo avvia **sempre** l'utente, perché le app lanciate da questa sessione hanno l'AppData virtualizzato (MSIX).
     - La seconda istanza si apre con `WONDERFLIX_PROFILE=b`.
  8. **Merge e push solo dopo l'ok** dell'utente ("fai il merge su main e pusha"):
     1. `git fetch`;
     2. fast-forward su `main`;
     3. push;
     4. rimozione di worktree e branch.
- **Release:**
  - Commit `chore: release X.Y.Z`; tag e push solo con l'ok dell'utente.
  - A pipeline finita **scrivo io** le note in italiano nella bozza (`gh release edit vX.Y.Z --notes-file …`). Il marcatore `min-version` va solo se la release è obbligatoria.
  - **Pubblica l'utente.**
  - Se serve un plugin nuovo: prima il plugin dal Catalogo, poi l'app.
- **Issue:** commento ("Fatto in [WonderFlix X.Y.Z](link)", cosa cambia) e chiusura come completata **solo con l'ok dell'utente**, dopo la pubblicazione.
- **Versioni:** si resta su 0.x. **v1.0.0 = prima release per gli amici.** Una funzione nuova alza la minore, una correzione la patch.
- **UI:** icone solo `LucideIcons`. Colori `WfColors`. Durate da `WfMotion` o costanti nominate e commentate. `clock.now()`, mai `DateTime.now()`. Le emoji a colori sono ammesse solo per le reazioni del watch party.
- **Escluso per scelta dell'utente:** entrare in un watch party da Discord o con un collegamento `wonderflix://`. L'issue #7 parla di "inviare gli inviti" su Discord: va chiesto all'utente nel brainstorming se vuole rivedere l'esclusione o limitarsi ad avvisi senza link.

## Ambiente

Valgono le particolarità dei passaggi di consegne precedenti:
- Flutter 3.47.5;
- Rust in `C:\Users\sidot\.cargo\bin`, `flutter_rust_bridge` 2.11.1;
- `git checkout -- windows/flutter/` per i falsi cambi di fine riga;
- `core.autocrlf=true`; edit mirati, mai `dart format` o `dotnet format` su file interi;
- `gh` autenticato.

In più:
- **Pacchetti:** flutter_riverpod **3.4.3**, go_router 18, dio con `JellyfinHttp` (`quietStatuses` per i 404/429 attesi dal plugin).
- **Build di release per le prove:**
  ```bash
  flutter build windows --release --dart-define-from-file=config/wonderflix.json
  ```
- **.NET 9 SDK:** serve per il plugin.

## Lezioni recenti (da dare ai subagent)

Oltre a quelle dei passaggi di consegne precedenti:
- **Riverpod 3.**
  - Un `Notifier` con una dipendenza cambiata si ricostruisce alla **lettura successiva**, non con `flushMicrotasks`.
  - Un controller costruito o ricostruito pigramente avvia il proprio `reload()` e scarta il nostro. Per una lista fresca si chiama l'API direttamente.
  - L'istanza del notifier resta la stessa tra le ricostruzioni: le letture vecchie si scartano con un contatore.
  - `WidgetRef.listen` non ha `fireImmediately`: si usa `ref.listenManual` in `initState`.
  - `select` usa `readSafe`, quindi un `ref.listen(provider.select(…), onError: …)` non lancia se il provider non si costruisce.
- **Menu e focus.**
  - `showMenu` **non apre mai il menu sopra** il pulsante: lo spinge in alto solo finché ci sta. `menuPositionBelow(…, estimatedHeight:)` in `lib/ui/wf_menus.dart` lo fa da sé.
  - `showMenu` limita la larghezza a 280 px (si cambia con `constraints:`).
  - Nel player un menu aperto copre la route: `PlayerChromeController.isCovered` tiene i controlli visibili. All'uscita dal player si chiudono prima le route sopra (`popUntil`).
  - `autofocus: true` non funziona dentro la shell di go_router: si chiede il focus esplicitamente dopo il fotogramma.
- **Plugin e privacy.**
  - Quello che il plugin manda a una sessione va filtrato con la vista di **quella** sessione (`GetGroup(sessionId, …)`), non con quella di chi agisce.
  - Un avviso non va mai mandato prima che il dato da proteggere esista: per esempio prima che il gruppo abbia la coda.
- **Disponibilità del plugin nell'app.**
  - Finché `Info` non ha risposto non si mostra nulla di filtrato.
  - Un errore di rete lascia lo stato "ignoto" e si riprova.
  - Solo 400/401/403/404 valgono come "plugin assente".
- **Commit in parallelo:** due subagent nello stesso worktree devono fare `git add` solo dei propri percorsi e riprovare se c'è `.git/index.lock`.

## Punti aperti (non bloccanti)

Dalla Spec F:
- **Party dimenticati per errore.** Un party registrato che la pulizia ha dimenticato per errore resta nascosto agli estranei per 24 h. I suoi partecipanti però lo vedono senza modalità, cioè come "Pubblico".
- **Menu delle modalità.** Con testo ingrandito il menu è più alto della stima e copre in parte il pulsante.
- **Attese senza indicatore.**
  - "Guarda insieme" può aspettare fino a 2 s che il plugin risponda.
  - "Invita amici" può aspettare fino a 2 s la lista degli amici.
- **Codice valido senza accesso alla libreria.** Chi ha un codice valido ma nessun accesso alla libreria del film legge "Codice non valido o party finito".

Ancora aperti dai passaggi di consegne precedenti:
- Il nome del gruppo del watch party non cambia se il gruppo passa a un altro titolo.
- La conversione senza ricodifica risulta "Transcode" nella Dashboard.
- **Mai provati sul server:** rete staccata, salvaschermo, trailer locali, tasti multimediali fisici.
- `WriteFile` sulla pipe di Discord è sincrono sul thread UI. **Da tenere presente nella Spec G.**
- Firma del codice spenta.

## Spec G: cosa chiede l'issue #7 e cosa si sa

**Issue #7** (dell'utente): collegare il proprio account Discord, magari dalle impostazioni. Gli scopi sono tre:
1. notifiche da parte del server;
2. una lista amici allineata con Discord;
3. inviare gli inviti.

**Primi risultati.** La ricerca fatta durante il brainstorming della Spec F va **riverificata**:
- **Lista amici da Discord:** serve lo scope `relationships.read`, che Discord concede solo dopo approvazione (Discord Social SDK). Per un'app privata quasi certamente non si può.
- **Collegamento dell'account (OAuth2):** si può fare in due modi.
  - Con il plugin come backend: il client secret resta sul server, e il plugin salva il collegamento utente Jellyfin ↔ id Discord in `plugins/configurations/…`.
  - Con l'app come client pubblico con PKCE e redirect su loopback (`http://127.0.0.1:<porta>`).
- **Avvisi e inviti su Discord:** servono un **bot** e un server Discord in comune per i messaggi diretti, oppure un webhook in un canale. Un invito "cliccabile" vorrebbe un link https, ma l'utente ha escluso l'ingresso nel party da Discord e da `wonderflix://`.
- Gli amici di WonderFlix (Spec F) già esistono nel plugin: Discord potrebbe solo **arricchirli** (nome e avatar Discord, suggerimenti tra utenti collegati) invece di sostituirli.

**Ricerca da fare prima del brainstorming:**
- **OAuth2 di Discord oggi.**
  - Scope `identify`, `email`, `guilds`, `guilds.members.read`, `relationships.read`, e quali richiedono approvazione.
  - PKCE per i client pubblici e redirect su loopback per le app desktop.
  - Durata dei token e refresh.
- **Discord Social SDK.**
  - Cosa offre: amici, presenza, inviti di gioco.
  - Requisiti e approvazione.
  - Se funziona con un'app non-gioco e con Flutter/Windows (FFI verso l'SDK C++?).
- **Bot.**
  - Messaggi diretti: regole, server in comune, limiti di frequenza.
  - Se un bot può stare **dentro il plugin** (solo REST per i DM, senza gateway) o richiede un processo sempre acceso.
  - Dove tenere il token del bot: configurazione del plugin nella Dashboard di Jellyfin?
- **Rich Presence esistente.**
  - Cosa aggiunge il collegamento rispetto alla presenza già attiva via IPC.
  - Il pulsante della Rich Presence come "invito": link https, vincoli di Discord sui pulsanti.
- **Privacy.**
  - Cosa vedono gli altri del proprio Discord.
  - Scollegare l'account.
  - Cancellare i dati dal plugin.
- **Configurazione pagina del plugin in Jellyfin** (`IHasWebPages`/`PluginConfiguration`): per client id e secret del backend.

**Da chiarire con l'utente nel brainstorming:**
- Quale dei tre scopi conta di più, e se la lista amici "allineata" può diventare "arricchita" con suggerimenti tra utenti collegati.
- Se l'esclusione dell'ingresso da Discord resta: avvisi solo informativi o link.
- Se un bot Discord e un server Discord comune sono accettabili.
- Se il collegamento passa dal plugin (consigliato per non mettere segreti nell'app pubblica) o dall'app.

## Primo passo della nuova sessione

1. Leggere questo documento, la Spec F (§5–6 plugin, §7–8 app e pannello Amici) e il piano 4a (Discord) per il codice esistente.
2. Fare la ricerca indicata sopra, con le fonti ufficiali di Discord.
3. `superpowers:brainstorming` con l'utente sulla Spec G, poi proporre la divisione in piani.
