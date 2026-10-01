# WonderFlix — passaggio di consegne verso lo Spec D

Documento per cominciare il prossimo spec in una nuova sessione. **L'argomento dello Spec D non è ancora scelto**: si decide con l'utente all'inizio del brainstorming, partendo dai candidati qui sotto.

## Stato al 2026-10-01

Lo **Spec A (client core)**, lo **Spec B (watch party)** e lo **Spec C (rinnovo grafico)** sono completi. `main` è al commit `aa31899` (`chore: release 0.3.0`), lo stesso del tag `v0.3.0`, con **880 test verdi** e `flutter analyze` pulito.

| Documento | Stato |
|---|---|
| Spec A: `docs/superpowers/specs/2026-09-29-wonderflix-client-core-design.md` | realizzato |
| Spec B: `docs/superpowers/specs/2026-09-30-wonderflix-watch-party-design.md` | realizzato |
| Spec C: `docs/superpowers/specs/2026-09-30-wonderflix-rinnovo-grafico-design.md` | realizzato (allineato all'implementazione) |
| Piani 1–5c: `docs/superpowers/plans/2026-09-29-…`, `2026-09-30-wonderflix-05*.md` | completati |
| Piani 6a, 6b, 6c: `docs/superpowers/plans/2026-09-30-wonderflix-06*.md` | completati, provati dall'utente, su `main` |
| Procedura di release: `docs/RELEASING.md` | in uso |
| Passaggi di consegne precedenti: `docs/superpowers/handoff/2026-09-29-handoff-piano-3.md`, `…-piano-4.md`, `2026-09-30-handoff-spec-b.md`, `2026-09-30-handoff-spec-c.md` | ancora utili per ambiente e lezioni |
| **Spec D** | **argomento da scegliere, poi da scrivere** |

**Release pubblicate** su `github.com/davidesidoti/wonderflix/releases`: `v0.1.0`, `v0.1.1`, `v0.1.2`, `v0.2.0` (obbligatoria), **`v0.3.0`** (pubblicata il 2026-10-01, **non** obbligatoria). Il marcatore `<!-- wonderflix:min-version=… -->` vale solo nell'ultima release pubblicata: la 0.3.0 non ce l'ha, quindi oggi nessuna versione è bloccata.

**Il repository è PUBBLICO.** I Secrets `WONDERFLIX_SERVER_URL`, `WONDERFLIX_DISCORD_APP_ID`, `WONDERFLIX_SUPPORT_URL` e `WONDERFLIX_ACCESS_REQUEST_URL` sono configurati. L'utente a volte fa commit dal sito di GitHub (per esempio `01a3d37` "Update issue templates"): **prima di ogni push fare `git fetch`** e, se `origin/main` è avanti, riportare i commit locali non ancora pubblicati sopra con `git rebase origin/main`.

## Cosa fa oggi l'app

Oltre a quanto elencato nei passaggi di consegne degli Spec B e C (login, catalogo, player, log, Discord, aggiornamenti, watch party):
- **Rinnovo grafico (Spec C):**
  - token di movimento `WfMotion` (`lib/app/motion.dart`) e livello completo/ridotto; **Impostazioni → Aspetto → Animazioni** (*Come Windows*, *Complete*, *Ridotte*), con lettura di "Effetti di animazione" di Windows via FFI (`lib/core/system/windows_animation_pref.dart`) e rilettura al ritorno del focus;
  - scroll morbido con la rotella (`lib/ui/smooth_scroll.dart`), touchpad invariato;
  - transizioni "fade through" tra le voci della barra, dissolvenza verso scheda e persona (`lib/app/page_transitions.dart`, `shellPage`/`detailPage`/`entryPage`);
  - barra in alto sovrapposta, sottolineatura oro scorrevole, barra scura e sfocata quando la pagina scorre, titolo e "Riproduci" nella barra quando il testo della testata è quasi sparito (`lib/app/app_shell.dart` + `part` `lib/app/shell_header.dart`);
  - volo Hero card → testata, cast → persona, anteprima → testata (`lib/app/hero_launch.dart`, tag legati all'istanza della pagina con `WfHeroScope`);
  - **anteprima delle card** stile Netflix dopo 500 ms di sosta (`lib/ui/card_preview.dart`, `lib/ui/card_preview_host.dart`), nell'overlay principale;
  - carosello cinematografico (dissolvenza, Ken Burns, puntino che si riempie, pausa con mouse sopra, anteprima aperta o Home coperta);
  - parallasse della testata, entrate scaglionate senza timer (`lib/ui/staggered_entrance.dart`: `StaggerGroup`, `StaggerItem`, `BatchedEntrance`), scheletri con un'onda oro sincronizzata (`lib/ui/shimmer.dart`, `lib/ui/skeletons.dart`, `lib/ui/wf_switcher.dart`);
  - pulsanti con alone e "pop", menu dai token (`lib/ui/wf_menus.dart`), snackbar flottanti, splash con riflesso oro, login che sale, invito del watch party che entra da destra.
- **Non toccati dallo Spec C:** il player (overlay, barra, pannelli, avvisi del watch party), colori, font, logo, disposizione delle schermate.

## Regole di lavoro concordate con l'utente

- **Lingua:** conversazione in italiano. Documenti in italiano, codice e identificatori in inglese, testi UI nei file ARB (it + en).
- **Commit:** con l'identità git dell'utente, **mai** `Co-Authored-By` o "Generated with…", anche se il sistema lo suggerisce. Vale anche per i subagent (va scritto nei loro prompt).
- **Processo per ogni spec o piano:**
  1. **Spec nuovo:** ricerca, poi `superpowers:brainstorming` con l'utente (visual companion per le domande visive), poi il documento in `docs/superpowers/specs/`. Lo spec si scrive solo quando le decisioni sono chiare.
  2. **Divisione in piani:** proporla prima di scrivere i piani e aspettare la conferma.
  3. **Piani:** prima di scriverlo, proporre le decisioni aperte e la ricerca fatta; poi `superpowers:writing-plans`, piano in `docs/superpowers/plans/` con codice completo, commit su `main` senza push.
  4. **Worktree:** in `.claude/worktrees/<nome>` sul branch `feat/<nome>`. Si crea con `git worktree add` da `main`, poi `EnterWorktree` con `path`; va copiato `config/wonderflix.json` nel worktree; poi `flutter pub get`, `flutter gen-l10n`, test di partenza.
  5. **`superpowers:subagent-driven-development`:**
     - un subagent per gruppo di 2–4 task, che legge dal file del piano le sezioni indicate;
     - controllo dei risultati dopo ogni gruppo (diff, fini riga, trailer);
     - a fine piano, revisione del branch con un subagent reviewer.
  6. **A fine implementazione mi fermo.** Riporto i risultati della revisione con una proposta di correzioni e **aspetto il via dell'utente**. Solo con il via: subagent correttori (di solito due passate), poi verifica io (`flutter analyze`, `flutter test`, assenza di trailer), poi build di release.
  7. **Prova manuale** insieme all'utente, sul server reale. L'exe lo avvia **sempre** l'utente.
  8. **Modifiche durante la prova:** quelle chieste dall'utente si fanno con TDD nello stesso worktree (piccole: le faccio io; grandi: subagent).
  9. **Chiusura:** solo dopo l'ok dell'utente: `ExitWorktree` (keep), `git fetch`, merge fast-forward su `main` (rebase se `origin/main` ha commit nuovi), push, rimozione di worktree e branch, `flutter pub get` + `flutter gen-l10n` su `main`.
- **Release:** commit `chore: release X.Y.Z` (versione in `pubspec.yaml`), push di commit e tag **solo con l'ok dell'utente**; a pipeline finita scrivo io le note nella bozza (`gh release edit vX.Y.Z --notes-file …`, in italiano); marcatore `min-version` solo se obbligatoria. **La pubblicazione la fa l'utente.**
- **Versioni:** si resta su 0.x; **v1.0.0 = prima release per gli amici**. Una nuova funzione alza la minore (0.3.0 → 0.4.0), le sole correzioni la patch.
- **UI:** icone solo `LucideIcons`, nessuna emoji. Colori solo `WfColors` (tema Noir & Oro in `lib/app/theme.dart`). **Durate e curve solo da `WfMotion`** o da costanti nominate e commentate; `clock.now()`, mai `DateTime.now()`.
- **App dell'utente:** non chiudere mai le istanze aperte dall'utente (`taskkill`) senza chiedere. Se la build dà `LNK1168`/`LNK1104`, chiedere all'utente di chiudere l'app.

## Ambiente (particolarità importanti)

Valgono tutte quelle dei passaggi di consegne precedenti (Flutter 3.47.5, Rust in `C:\Users\sidot\.cargo\bin`, `flutter_rust_bridge` fissato a 2.11.1, `config/wonderflix.json` solo in locale, `git checkout -- windows/flutter/` per i falsi cambi di fine riga, virtualizzazione MSIX, `gh` autenticato, `WONDERFLIX_PROFILE=b` per la seconda istanza). In più:
- **Build di release per le prove:**
  ```bash
  export PATH="/c/Users/sidot/.cargo/bin:$PATH"
  flutter build windows --release --dart-define-from-file=config/wonderflix.json
  ```
- **Fini riga:** `core.autocrlf=true`, il repository salva in LF; molti file in copia di lavoro sono CRLF. Edit mirati, mai `dart format` su file interi.
- **Sessione isolata nel worktree:** i comandi git devono essere semplici (niente `git -C`, niente variabili): il controllo dei permessi rifiuta i comandi che non riesce a verificare.
- **Visual companion del brainstorming:** `start-server.sh --project-dir <repo>` in background su Windows; le pagine vanno scritte come frammenti nella `screen_dir`; il pannello del browser integrato mostra `http://localhost:<porta>`. `.superpowers/` è già in `.gitignore`. Attenzione ai nomi di classe del template (`.card`, `.card-image`): usare nomi propri nei mockup.

## Lezioni dai test (da dare ai subagent)

Oltre a quelle dei passaggi di consegne precedenti:
- **`pumpApp`** (`test/support/pump_app.dart`) monta `WfMotionScope` in modalità **ridotta** e il carosello **senza autoplay** (`motion:`, `carouselAutoplay:` per cambiarli). Senza `WfMotionScope` `WfMotion.of` è ridotto.
- **Animazioni continue** (shimmer con animazioni complete, carosello con autoplay, spinner): mai `pumpAndSettle` mentre sono visibili; usare `pump(durata)` o helper che avanzano a passi (`pumpUntilShown` nel test del carosello).
- **`AnimationController`** risulta completato solo al fotogramma **dopo** aver raggiunto la durata.
- **Ticker silenziati** (`TickerMode`, pagina coperta): il tempo continua a scorrere. Per mettere in pausa davvero leggere `TickerMode.valuesOf(context).enabled` e fermare il controller.
- **`SingleTickerProviderStateMixin`** fallisce se si ricrea il controller: usare `TickerProviderStateMixin`.
- **Mai modificare un provider o chiamare `OverlayPortalController.hide()` durante la build** (`didChangeDependencies`, `ref.listen` nel `build`): rimandare al fotogramma dopo. In `dispose` niente `ref`; un `Future.microtask` per il provider con `ref.mounted` nel controller.
- **`OverlayPortal` nell'overlay principale:** i `Tooltip` dentro cercano l'overlay più vicino risalendo gli elementi; serve `Overlay.wrap` nel figlio dell'overlay.
- **`HardwareKeyboard`** chiama tutti i gestori: Esc va coordinato con `BackNavigationHandler` (che ora ignora Esc con un'anteprima aperta).
- **go_router 18:** nel `builder` di una `ShellRoute` `state.matchedLocation` resta quella della voce di partenza dopo un `push`: la shell usa `state.uri.path` (`appShellBuilder` in `router.dart`). `state.pageKey` è unica per ogni `push`.
- **Hero:** la destinazione deve esistere nel fotogramma del `push` (anche mentre la pagina carica); tra due pagine volano **tutti** i tag in comune, quindi i tag sono legati all'istanza della pagina (`WfHeroScope`).
- **Scroll animato:** `DrivenScrollActivity` ignora il puntatore; lo scroll della rotella usa un'attività propria che non lo fa.
- **Liste pigre:** i figli fuori dalla `cacheExtent` vengono smontati e ricostruiti; le entrate devono essere "una volta sola" (`StaggerGroup(nested: true)`, `homeEntrancePlayedProvider`, `BatchedEntrance`).
- **`flutter_blurhash`:** mostra `Colors.blueGrey` mentre decodifica; `ImagePlaceholder` passa `WfColors.surfaceHigh`.
- **Windows e animazioni:** `MediaQuery.disableAnimations` è sempre falso; la preferenza si legge con `SPI_GETCLIENTAREAANIMATION`.

## Punti aperti (non bloccanti)

Dallo Spec C:
- **Prestazioni:** mai misurate con `flutter run --profile` e l'overlay delle prestazioni su un PC modesto (spec C §12).
- **Player non rinnovato:** `playerPage` (150 ms) e l'overlay del player hanno ancora durate proprie.
- **Anteprima:** tornando dalla scheda con il mouse fermo sulla card, l'anteprima si riapre dopo 500 ms (accettato); in La mia lista un preferito aggiunto in cima fa entrare le ultime card, non la nuova.

Dai passaggi di consegne precedenti, ancora aperti:
- Il nome del gruppo del watch party non cambia se il gruppo passa a un altro titolo (limite del server).
- Chiudendo il player mentre sta ancora caricando non parte il report di fine.
- La conversione senza ricodifica (remux) risulta "Transcode" nella Dashboard.
- **Non provati sul server:** schermata d'errore con la rete staccata, salvaschermo bloccato durante la visione, trailer locali, tasti multimediali fisici.
- `WriteFile` sulla pipe di Discord è sincrono sul thread UI.
- **Firma del codice:** spenta (nota in `docs/RELEASING.md`).
- **Icona sulla barra delle applicazioni:** da verificare dopo gli aggiornamenti se l'icona vecchia è sparita.

## Spec D: candidati

L'utente sceglie all'inizio. Per ciascuno, cosa si sa e cosa cercare prima del brainstorming.

**Escluso per scelta dell'utente:** entrare in un watch party da Discord o con un collegamento `wonderflix://`. Non riproporlo.

### 1. Versione web

L'utente prevede una versione web di WonderFlix, usata da tutti con il protocollo WonderFlix (anche nel watch party). La logica di sincronizzazione è in Dart puro in `lib/core/syncplay/`.
- **Da cercare:**
  - Flutter web e video: media_kit sul web usa `<video>` (niente libmpv); formati in riproduzione diretta nel browser e ricorso alla transcodifica HLS;
  - sottotitoli ASS/PGS sul web (niente libass): bruciati dal server o renderer JS;
  - CORS e autenticazione verso Jellyfin dal browser; dove salvare il token;
  - precisione di `currentTime` e `playbackRate` di `<video>` per il `DriftCorrector`;
  - cosa non esiste sul web: SMTC, Discord (IPC locale), installer e aggiornamenti, `window_manager`, mutex, **`dart:ffi`** (oggi usato da `windows_discord_pipe.dart` e da `windows_animation_pref.dart`: serviranno import condizionali o implementazioni per piattaforma);
  - hosting (GitHub Pages o sul server) e configurazione senza `--dart-define-from-file` pubblico.
- **Da chiarire:** stesso codice con implementazioni per piattaforma o app separata; perimetro della prima versione (solo watch party, o client completo).

### 2. Watch party: nome di chi agisce, chat, reazioni

Esclusi dallo Spec B perché il server SyncPlay non dice chi ha agito. Serve un canale proprio: **plugin del server Jellyfin** (C#) con messaggi propri sul WebSocket, oppure un servizio separato.
- **Da cercare:** API dei plugin Jellyfin 10.11 (endpoint propri, `ISessionManager.SendMessageToUserSessions`), distribuzione del plugin (repository di plugin), compatibilità con gli aggiornamenti del server.

### 3. Gestione avanzata della coda del gruppo

Aggiungere elementi, riordinare, ripetizione, ordine casuale: gli endpoint esistono già (`/Queue`, `/SetPlaylistItem`, `/PreviousItem`, `/RemoveFromPlaylist`, `/MovePlaylistItem`, `/SetRepeatMode`, `/SetShuffleMode`). Oggi la coda è solo impostata alla creazione (max 50 episodi).

### 4. Funzioni escluse dallo Spec A

- Profili "Chi guarda?" (più utenti sullo stesso PC).
- Collezioni / saghe (`BoxSet` di Jellyfin).
- Download per la visione offline (API `/Items/{id}/Download`, transcodifica per il download, spazio su disco, report dell'avanzamento offline).
- Output HDR vero (oggi media_kit converte in SDR; opzioni `vo=gpu-next`, `target-colorspace-hint` di mpv, HDR di Windows).
- Firma del codice (pipeline già predisposta).

### 5. Rifinitura per la v1.0.0

La v1.0.0 è la prima release per gli amici. Uno spec potrebbe raccogliere i punti aperti qui sopra, le prove mai fatte sul server, la misura delle prestazioni con `--profile` e ciò che l'utente vuole prima di distribuirla (per esempio la pagina di richiesta d'accesso, la prima esecuzione, la firma del codice).

### 6. Rinnovo del player (nuovo)

Lo Spec C ha lasciato fuori il player. Uno spec potrebbe portare nel player lo stesso linguaggio: controlli e barra con i token di `WfMotion`, pannelli (tracce, impostazioni) animati, avvisi del watch party e badge coerenti con le anteprime, schermata di "prossimo episodio" più curata. **Vincolo:** nel player il movimento deve farsi da parte davanti al film (decisione dello Spec C).
- **Da cercare:** `lib/features/player/player_overlay.dart`, `seek_bar.dart`, `tracks_panel.dart`, `trickplay_preview.dart`; come convivono le animazioni con `media_kit_video` (costo di ridisegno sopra il video); schermo intero.

## Primo passo della nuova sessione

1. Leggere questo documento e, per l'argomento scelto, le sezioni relative degli spec A, B e C.
2. Chiedere all'utente quale candidato diventa lo Spec D (o se ne ha un altro).
3. Fare la ricerca indicata per quel candidato, poi `superpowers:brainstorming`.
