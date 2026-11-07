# WonderFlix TV — Piano 2: interfaccia da telecomando

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sul Fire Stick WonderFlix si usa solo col telecomando: barra laterale, focus visibile su card e pulsanti, pagine e player navigabili con le frecce, OK e Indietro, e senza le funzioni escluse dal design.

**Architecture:** Un flag `tv` in `FormFactor` (passato da `app.dart` con `isAndroidTv`) accende le differenze; Windows e web restano identici perché ogni ramo nuovo è dietro `FormFactor.of(context).tv`. `compact` resta com'è (su 960×540 dp la TV usa i layout stretti esistenti, dialoghi e pannelli a pagina intera compresi); cambia solo la cornice: `TvShell` con `TvSidebar` al posto di barra in alto e barra in basso. Un widget `TvFocusable` dà focus, bordo oro, attivazione con OK e scorrimento automatico agli elementi che oggi sono solo `GestureDetector`. Il player sulla TV legge i tasti del telecomando e rende focalizzabili i suoi controlli.

**Tech Stack:** Flutter 3.47.5 (widget `Focus`, `FocusableActionDetector`, `Shortcuts`, `PopScope`), Riverpod 3, go_router; Kotlin solo per il nome del dispositivo.

**Spec:** `docs/superpowers/specs/2026-11-07-wonderflix-tv-design.md` (sezioni "Cosa c'è sulla TV", "Navigazione e aspetto", "Accesso e account", "Controlli col telecomando"). Prerequisito: piano 1 (`docs/superpowers/plans/2026-11-07-wonderflix-tv-1-motore-android.md`), unito a `main`, con la lista "Da riprendere".

## Global Constraints

- Windows e web non cambiano: ogni differenza passa da `FormFactor.of(context).tv` (falso fuori dalla TV). `flutter analyze` pulito, `flutter test` tutto verde, `flutter build windows --debug` e build web ok.
- `FormFactor.tv` vero ⇒ `touch` falso e `phone` falso; `compact` invariato (larghezza < 1024).
- Sulla TV si guarda e basta. Dentro: Home, Film, Serie (catalogo, saghe), pagina titolo e persona, Cerca, La mia lista, player, Vota, Consiglia, Stasera, Richieste (da Cerca + scheda con lo stato). Fuori: admin, Spazio, download, modifica metadati, Discord, watch party, amici e chat, notifiche (cassetta), calendario, Match, aggiornamento dell'app (arriva col piano di distribuzione).
- Barra laterale, dall'alto: Cerca, Home, Film, Serie, Stasera, La mia lista, Richieste; in fondo l'avatar. Chiusa mostra solo le icone; si allarga coi nomi quando ha il focus.
- Pagina titolo: il pulsante principale (Riproduci / Riprendi SxEy · posizione) ha il focus all'apertura; accanto La mia lista, Vota, Consiglia, Segna come visto, Altro (solo "Info tecniche" e "Segnala un problema").
- Player: OK = pausa/play e mostra i controlli; Sinistra/Destra = ±10 s con anteprima; Su/Giù = mostrano i controlli e ci si sposta tra i pulsanti (pausa, ±10 s, Audio e sottotitoli, Episodio successivo); Indietro = prima chiude controlli e pannelli, poi esce; tasti media del telecomando fanno ciò che dicono; "Salta intro" prende il focus finché è visibile.
- Indietro dalla radice (`/home`) non esce subito: decisione del builder fissata qui, doppio Indietro entro 2 s con l'avviso "Premi di nuovo Indietro per uscire". Indietro da un'altra voce della barra porta a `/home`.
- Docs, commenti, stringhe e commit in italiano; codice in inglese. Stringhe nuove nei file `app/l10n` (come le altre), `flutter gen-l10n`.
- Commit solo a nome dell'utente, senza `Co-Authored-By`, senza `closes`/`fixes`/`resolves`. Subagenti: mai `taskkill /IM` o `pkill`. Build Windows completa, se serve: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- Prove sul Fire Stick: `C:/Users/sidot/dev/android-sdk/platform-tools/adb.exe connect 192.168.1.171:5555`; build `flutter build apk --release --split-per-abi --dart-define-from-file=config/wonderflix.json`, installa `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`. Tasti del telecomando via adb: `input keyevent KEYCODE_DPAD_UP|DOWN|LEFT|RIGHT|DPAD_CENTER|BACK|MEDIA_PLAY_PAUSE|MEDIA_FAST_FORWARD|MEDIA_REWIND`. L'utente è entrato; le password non le scrive l'agente. Ogni riproduzione sposta i punti di ripresa dell'account dell'utente: usare "2012" per le prove del player.
- Worktree `.claude/worktrees/tv`, branch `feat/tv-ui` (da `main`). `app/config/wonderflix.json` già presente.

## Review Focus

1. **Focus perso** (dopo un cambio pagina, un dialogo chiuso, un pannello chiuso): nessun elemento ha il focus e il telecomando non fa niente. Ci si aspetta che il focus torni su un elemento visibile. → test in Task 3 (cambio voce della barra) e Task 4 (apertura pagina titolo); verifica in Task 9.
2. **Elemento col focus fuori schermo** in una riga o lista lunga: deve scorrere fino a renderlo visibile. → test in Task 1 (`TvFocusable` in una lista che scorre).
3. **Indietro in ogni stato**: barra aperta, dialogo aperto, pagina profonda, radice, player con pannello aperto. Nessuno stato deve far uscire dall'app per sbaglio né restare bloccato. → test in Task 3 (radice e voce non-Home) e Task 6 (player); verifica in Task 9.
4. **Tasto OK** (`select` / `DPAD_CENTER`, che Flutter riceve come `LogicalKeyboardKey.select`) non attiva gli elementi che oggi rispondono solo a Invio/Spazio. → test in Task 1 (scorciatoia globale) e Task 6 (player).
5. **Funzioni escluse ancora raggiungibili** (menu "Altro" con modifica metadati, Match, calendario, watch party): sulla TV non devono comparire. → test in Task 4 e Task 5.

---

### Task 1: Modo TV in `FormFactor`, `TvFocusable` e tasto OK

**Files:**
- Modify: `app/lib/ui/form_factor.dart`
- Modify: `app/lib/app/app.dart` (riga ~62, dove si monta `FormFactorScope`)
- Create: `app/lib/ui/tv_focusable.dart`
- Test: `app/test/ui/form_factor_test.dart` (esistente o nuovo), `app/test/ui/tv_focusable_test.dart`

**Interfaces:**
- Produces: `FormFactor.tv` (bool); `FormFactorScope({required Widget child, bool? touchOverride, bool tv = false})`; `class TvFocusable extends StatefulWidget { const TvFocusable({super.key, required this.child, required this.onActivate, this.autofocus = false, this.focusNode, this.borderRadius = const BorderRadius.all(Radius.circular(6)), this.onFocusChange}); }` con `onActivate` di tipo `VoidCallback?`; `const tvFocusColor = WfColors.gold`; `const tvFocusScale = 1.05`.

- [ ] **Step 1: Test di `FormFactor`**: con `FormFactorScope(tv: true, child: …)` e `MediaQuery` 960×540: `tv == true`, `touch == false`, `phone == false`, `compact == true`; con `tv: false` tutto come oggi; senza scope `tv == false`.
- [ ] **Step 2: Test di `TvFocusable`** (dentro `FormFactorScope(tv: true)`):
  - con `autofocus: true` il figlio è circondato da un bordo `tvFocusColor` largo 2 e scalato a `tvFocusScale`;
  - `LogicalKeyboardKey.select`, `enter` e `space` chiamano `onActivate` una volta;
  - in un `ListView` orizzontale di 20 elementi larghi 200 dentro uno spazio di 600, spostare il focus sul 15° (`focusNode.requestFocus()`) lo rende visibile (`tester.getRect` dentro il viewport) dopo `pumpAndSettle`;
  - con `FormFactorScope(tv: false)` `TvFocusable` non aggiunge nessun `Focus` (il widget figlio è restituito così com'è: `find.byType(Focus)` invariato rispetto al solo figlio).
- [ ] **Step 3: Esegui e verifica che falliscano** — `flutter test test/ui/form_factor_test.dart test/ui/tv_focusable_test.dart` → FAIL.
- [ ] **Step 4: Implementa**: `FormFactor` riceve `tv` dall'`InheritedWidget` dello scope (lo stesso che porta `touch`); con `tv` lo scope pubblica `touch: false` e ignora i puntatori. `app.dart` passa `tv: isAndroidTv`. `TvFocusable` usa `FocusableActionDetector` con `ActivateIntent` → `onActivate`, e al guadagno del focus chiama `Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200))`. In `app.dart`, solo con `tv`, un `Shortcuts` sopra il router mappa `SingleActivator(LogicalKeyboardKey.select)` → `ActivateIntent()`. Aggiorna il commento di `FormFactor` ("mai da `Platform`") spiegando che `tv` arriva da `app.dart`.
- [ ] **Step 5: Test della scorciatoia OK**: in un'app di prova con `FormFactorScope(tv: true)` e lo stesso `Shortcuts`, un `ElevatedButton` con focus riceve `onPressed` premendo `select`.
- [ ] **Step 6: Esegui** — test nuovi verdi; `flutter test` tutto verde; `flutter analyze` pulito.
- [ ] **Step 7: Commit** — `feat(tv): modo TV, focus da telecomando e tasto OK`

### Task 2: Card e righe col focus

**Files:**
- Modify: `app/lib/ui/poster_card.dart`, `app/lib/ui/landscape_card.dart`, `app/lib/ui/remote_image_card.dart`, `app/lib/features/collections/collection_card.dart`, `app/lib/features/requests/requestable_poster_card.dart`, `app/lib/features/search/search_screen.dart` (riquadri delle persone, ~riga 192), `app/lib/ui/media_row.dart`, `app/lib/ui/card_preview_host.dart`, `app/lib/features/home/hero_carousel.dart`
- Test: `app/test/ui/tv_cards_test.dart`

**Interfaces:**
- Consumes: `TvFocusable`, `FormFactor.tv` (Task 1).

- [ ] **Step 1: Test** (con `FormFactorScope(tv: true)`): una `MediaRow` di 8 `PosterCard` con `onTap` finti: `autofocus` sulla prima (parametro nuovo `autofocus` della card, default `false`), `DPAD_RIGHT` ×3 (`LogicalKeyboardKey.arrowRight`) sposta il focus sulla quarta, `select` chiama il suo `onTap`; le frecce `row-previous`/`row-next` non ci sono sulla TV; nessuna anteprima `CardPreviewHost` si apre dopo 2 s di focus. Stesso test breve per `LandscapeCard` e `RemoteImageCard`. Con `tv: false` le frecce della riga ci sono come oggi.
- [ ] **Step 2: Esegui e verifica che falliscano**.
- [ ] **Step 3: Implementa**: ogni card avvolge il contenuto in `TvFocusable(onActivate: <stessa azione del tap>, autofocus: autofocus)`; il bordo del focus sostituisce quello dell'hover sulla TV. `MediaRow` nasconde i pulsanti precedente/successivo con `tv`. `CardPreviewHost` non apre anteprime con `tv`. `HeroCarousel`: con `tv` niente scorrimento a gesti; i pulsanti delle slide restano (già focalizzabili).
- [ ] **Step 4: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(tv): card e righe navigabili col telecomando`

### Task 3: `TvShell`, barra laterale, menu dell'account e Indietro dalla radice

**Files:**
- Create: `app/lib/app/tv_shell.dart`, `app/lib/app/tv_sidebar.dart`, `app/lib/app/tv_account_menu.dart`
- Modify: `app/lib/app/app_shell.dart` (`appShellBuilder` sceglie `TvShell` con `tv`; `_runMenuAction` diventa pubblica `runUserMenuAction(BuildContext, WidgetRef, String)`)
- Modify: `app/l10n/*.arb` (etichette nuove)
- Test: `app/test/app/tv_shell_test.dart`

**Interfaces:**
- Consumes: `FormFactor.tv`, `TvFocusable` (Task 1); `openTonight(BuildContext, WidgetRef)` (`features/tonight/tonight_dialog.dart:62`); `requestsAvailableProvider`; `runUserMenuAction`; `changeProfile` (`features/profiles/profile_switch.dart:27`).
- Produces: `class TvShell extends ConsumerWidget { const TvShell({required this.child}); }`; `TvSidebar`; `Future<void> showTvAccountMenu(BuildContext, WidgetRef)`; costanti `tvSidebarCollapsedWidth = 72.0`, `tvSidebarExpandedWidth = 220.0`, `tvExitWindow = Duration(seconds: 2)`.

- [ ] **Step 1: Test** (router di prova con le route `/home`, `/movies`, `/series`, `/mylist`, `/requests`, `/search`, `/settings`, shell `TvShell`, `FormFactorScope(tv: true)`):
  - la barra mostra, in quest'ordine, Cerca, Home, Film, Serie, Stasera, La mia lista, Richieste e l'avatar; Richieste manca con `requestsAvailableProvider` falso;
  - chiusa è larga `tvSidebarCollapsedWidth` e senza testi; col focus su una voce è larga `tvSidebarExpandedWidth` e mostra i nomi;
  - focus su "Film" + `select` → la route è `/movies` e il focus passa al contenuto (un `TvFocusable` con `autofocus` della pagina di prova riceve il focus);
  - "Stasera" + `select` chiama `openTonight` (sostituito da un provider/callback finto: aggiungi a `TvShell` un parametro `@visibleForTesting VoidCallback? onTonight`);
  - avatar + `select` apre il menu con, in ordine, "Cambia account", "Aggiungi account", "Impostazioni", "Esci"; "Impostazioni" porta a `/settings`;
  - nessun `WatchPartyButton`, `FriendsButton`, `InboxButton`, `ShellBottomBar` né barra in alto;
  - Indietro (`tester.binding.handlePopRoute()`) su `/movies` → `/home`; su `/home` il primo Indietro mostra "Premi di nuovo Indietro per uscire" e non esce, un secondo entro `tvExitWindow` chiama l'uscita (callback `@visibleForTesting VoidCallback? onExit`, di default `SystemNavigator.pop`), un secondo dopo `tvExitWindow` mostra di nuovo l'avviso;
  - su una pagina profonda (`/item/x` spinta con `push`) Indietro torna indietro normalmente.
- [ ] **Step 2: Esegui e verifica che falliscano**.
- [ ] **Step 3: Implementa** `TvShell`: `Row(TvSidebar, Expanded(BackNavigationHandler(child)))` dentro un `PopScope(canPop: false)` attivo solo quando il router non può tornare indietro (`!GoRouter.of(context).canPop()`), che fa la logica radice/voce. `TvSidebar`: `FocusTraversalGroup` verticale di `TvFocusable` con icone Lucide (le stesse di `shell_bottom_bar.dart`: house, search, bookmark, messageSquarePlus; film, tv per Film e Serie; per Stasera l'icona di `TonightButton`); si allarga con `AnimatedContainer` (180 ms) quando un suo discendente ha il focus; la voce della route corrente è evidenziata in oro. Al cambio voce il focus va al primo elemento con `autofocus` della pagina, o al primo focalizzabile del contenuto (`FocusTraversalGroup` del contenuto + `FocusScope.of(context).nextFocus()` se nessuno lo prende). `showTvAccountMenu`: dialogo con quattro `WfButton` impilati che chiamano `runUserMenuAction` con `switch`, `add`, `settings`, `logout`. "Aggiungi account" solo se lo è anche nel menu PC (stessa condizione di `_UserMenu`).
- [ ] **Step 4: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(tv): barra laterale, menu account e uscita con doppio Indietro`

### Task 4: Home e pagina titolo sulla TV

**Files:**
- Modify: `app/lib/features/home/home_screen.dart` (`_EntryButtons`, ~riga 371), `app/lib/features/home/hero_carousel.dart`
- Modify: `app/lib/features/detail/detail_header.dart` (righe ~107-279), `app/lib/features/detail/item_actions_menu.dart`, `app/lib/features/detail/series_detail_view.dart` (`_SeasonTabs` ~197, `EpisodeTile` ~320)
- Test: `app/test/features/home/home_tv_test.dart`, `app/test/features/detail/detail_tv_test.dart`

**Interfaces:**
- Consumes: Task 1–2; `openRatePanel(context, ref, RateSubject(item: item, title: item.name, mine: …))` (`features/ratings/rate_panel.dart:48`), `openRecommendPanel`.

- [ ] **Step 1: Test home** (`tv: true`): il primo pulsante del carosello ("Riproduci") ha il focus all'apertura; `MatchButton` non c'è, `TonightButton` sì.
- [ ] **Step 2: Test pagina titolo** (`tv: true`, film e serie dalle fake esistenti dei test di `features/detail`):
  - il pulsante principale ha il focus all'apertura;
  - la riga delle azioni contiene, in ordine, La mia lista (`favorite`), Vota, Consiglia, Segna come visto (`played`), Altro; "Vota" apre il pannello del voto con `RateSubject(item: item, title: item.name, …)`; non ci sono "Guarda insieme", "Trailer", "Ricomincia" resta;
  - il menu Altro contiene solo "Info tecniche" e "Segnala un problema";
  - serie: `DPAD_DOWN` dal pulsante principale raggiunge le schede delle stagioni; `select` su "Stagione 2" la seleziona; gli episodi sono focalizzabili e `select` su un episodio chiama `playItem` (finto);
  - con `tv: false` la riga è identica a oggi (stesso test esistente invariato).
- [ ] **Step 3: Esegui e verifica che falliscano**.
- [ ] **Step 4: Implementa**: con `tv` il carosello mette `autofocus` sul primo pulsante della slide visibile e `_EntryButtons` nasconde Match. In `DetailHeader` con `tv`: `WfButton.primary(autofocus: true)`; riga azioni = favorite, Vota (`WfIconToggle`/`IconButton` con icona stella, apre `openRatePanel` con il voto attuale se disponibile dallo stesso provider usato da `FriendRatingsRow`), Consiglia (icona, `openRecommendPanel`), played, `ItemActionsButton(tvOnly: true)`; nascondi Guarda insieme, Trailer, Richiedi stagioni. `ItemActionsButton` con `tvOnly` (parametro nuovo, default `false`) mostra solo Report e MediaInfo. `_SeasonTabs` e `EpisodeTile` sulla TV: `InkWell(canRequestFocus: false)` dentro `TvFocusable` con la stessa azione; il menu episodio "⋯" nascosto sulla TV.
- [ ] **Step 5: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 6: Commit** — `feat(tv): home e pagina titolo col telecomando`

### Task 5: Cerca, Richieste, login, impostazioni e funzioni escluse

**Files:**
- Modify: `app/lib/features/search/search_screen.dart` (riga 75), `app/lib/features/requests/request_row.dart`, `app/lib/features/auth/login_screen.dart`, `app/lib/features/auth/password_login_form.dart` (riga 75), `app/lib/features/settings/settings_screen.dart`, `app/lib/features/update/update_banner.dart` (o il punto che lo monta), `app/lib/app/router.dart` (redirect di `/calendar`, `/admin`, `/friends`, `/inbox`, `/match/:id` a `/home` sulla TV)
- Test: `app/test/features/tv_pages_test.dart`

**Interfaces:**
- Consumes: Task 1–3.

- [ ] **Step 1: Test** (`tv: true`):
  - Cerca: il campo di testo NON ha il focus all'apertura (sulla TV aprirebbe subito la tastiera); `DPAD_DOWN`/`select` lo raggiunge e lo attiva; i risultati e la sezione "da richiedere" sono `TvFocusable`;
  - Richieste: una `RequestRow` è focalizzabile e `select` chiama `openRequest`;
  - login: con Quick Connect attivo la scheda iniziale è Quick Connect; il campo nome utente non ha `autofocus`;
  - impostazioni: compaiono solo le sezioni lingua dell'app, player, lingue di audio e sottotitoli; mancano account, notifiche, aspetto, home, Discord;
  - il banner di aggiornamento non compare sulla TV;
  - le route `/calendar`, `/admin`, `/friends`, `/inbox`, `/match/x` portano a `/home`.
- [ ] **Step 2: Esegui e verifica che falliscano**.
- [ ] **Step 3: Implementa** con controlli `FormFactor.of(context).tv` (nel router: `isAndroidTv` nel `redirect`, perché lì non c'è un `BuildContext` con lo scope; documentalo in un commento). `RequestRow`: `TvFocusable` intorno alla riga (o `InkWell` già focalizzabile con bordo di focus `tvFocusColor`).
- [ ] **Step 4: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(tv): cerca, richieste, login e impostazioni per la TV`

### Task 6: Tasti del telecomando e Indietro nel player

**Files:**
- Modify: `app/lib/features/player/player_screen.dart` (`_onKey` ~1235, `_escape` ~1055, `_exit` ~748, `Focus` ~1650), `app/lib/features/player/player_commands.dart` (~35), `app/lib/features/player/player_chrome.dart`
- Test: `app/test/features/player/player_tv_keys_test.dart` (con il motore finto `FakeVideoEngine` di `test/support/playback_fakes.dart` e l'impalcatura di `player_screen_test.dart`)

**Interfaces:**
- Consumes: `FormFactor.tv` (Task 1).
- Produces: `PlayerChromeController.showForKey()` (mostra i controlli e riparte il timer di 3 s).

- [ ] **Step 1: Test** (`tv: true`, video in riproduzione):
  - `select` → pausa e controlli visibili; di nuovo `select` → riprende;
  - `arrowRight` → `seek` a posizione +10 s e controlli visibili con l'anteprima trickplay sulla barra (se il titolo ha trickplay nelle fake; altrimenti almeno la barra visibile); `arrowLeft` → −10 s;
  - `arrowUp`/`arrowDown` NON cambiano il volume e mostrano i controlli;
  - `mediaFastForward` / `mediaRewind` → ±10 s; `mediaPlayPause` → pausa/play;
  - Indietro (`handlePopRoute`) con il pannello tracce aperto lo chiude; con i controlli visibili li nasconde; senza niente aperto esce dal player passando da `_exit()` (il controller viene chiuso: `FakeVideoEngine.disposed == true` o equivalente) e torna alla pagina precedente;
  - con `tv: false` Su/Giù cambiano ancora il volume (test esistenti invariati).
- [ ] **Step 2: Esegui e verifica che falliscano**.
- [ ] **Step 3: Implementa**: in `_onKey` con `tv` gestisci prima `select`/`enter` (togglePlay + `showForKey`), frecce (seek o mostra controlli; quando i controlli sono visibili e un controllo ha il focus, Su/Giù/Sinistra/Destra spostano il focus invece di cercare — lascia gestire l'evento al traversal restituendo `KeyEventResult.ignored`), `mediaFastForward`/`mediaRewind`. Avvolgi la schermata in `PopScope(canPop: false, onPopInvokedWithResult: (didPop, _) { if (!didPop) _escape(); })` così il Back di sistema passa dalla stessa logica di Esc e da `_exit()`.
- [ ] **Step 4: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(tv): telecomando e Indietro nel player`

### Task 7: Controlli del player focalizzabili sulla TV

**Files:**
- Modify: `app/lib/features/player/player_overlay.dart`, `app/lib/features/player/player_screen.dart` (gli `ExcludeFocus` intorno a overlay, `SkipSegmentButton` ~1870, prossimo episodio, post-play, pannello laterale), `app/lib/features/player/tracks_panel.dart` (`_TrackTile` ~195, `_ScaleChip` ~299, riga del ritardo), `app/lib/features/player/skip_button.dart`
- Test: `app/test/features/player/player_tv_controls_test.dart`

**Interfaces:**
- Consumes: Task 1, Task 6 (`showForKey`).

- [ ] **Step 1: Test** (`tv: true`):
  - con i controlli visibili, `arrowDown` porta il focus sulla fila dei pulsanti: pausa, −10 s, +10 s, "Audio e sottotitoli", "Episodio successivo" (quest'ultimo solo per un episodio con successivo); `select` su "Audio e sottotitoli" apre il pannello e il focus va alla traccia selezionata; `select` su un'altra traccia la sceglie;
  - nel pannello non c'è la riga "Ritardo sottotitoli" (sulla TV non funziona, piano 1);
  - non ci sono i pulsanti schermo intero, volume, guarda insieme;
  - quando compare "Salta intro" ha il focus; `select` salta;
  - post-play e "Episodio successivo" (card): il pulsante principale ha il focus;
  - con `tv: false` gli `ExcludeFocus` restano (test esistenti invariati).
- [ ] **Step 2: Esegui e verifica che falliscano**.
- [ ] **Step 3: Implementa**: con `tv` togli gli `ExcludeFocus` e dai `autofocus` dove indicato; bordo di focus `tvFocusColor` sui pulsanti dell'overlay (`TvFocusable` per quelli che non sono già pulsanti Material); nascondi schermo intero, volume, watch party e la riga del ritardo.
- [ ] **Step 4: Esegui** — verdi; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Commit** — `feat(tv): controlli del player col telecomando`

### Task 8: Nome del dispositivo in Jellyfin

**Files:**
- Modify: `app/android/app/src/main/kotlin/it/wonderflix/tv/MainActivity.kt` (canale `wonderflix/device`, metodo `name`)
- Modify: `app/lib/app/platform_startup_io.dart` (legge il nome all'avvio su Android), `app/lib/app/platform_startup_web.dart` (stesso simbolo, `null`), `app/lib/main.dart` (passa il nome a `DeviceIdentity.load(prefs, profile: …, hostName: …)`)
- Test: `app/test/app/device_name_test.dart`

**Interfaces:**
- Produces: `String? get tvDeviceName` in `platform_startup_io.dart`/`_web.dart`; `String tvDeviceNameFrom(String? settingsName, String model)` (funzione pura).

- [ ] **Step 1: Test di `tvDeviceNameFrom`**: `('Fire TV Stick di davide', 'AFTMA08C15')` → `'Fire TV Stick di davide'`; `(null, 'AFTMA08C15')` → `'AFTMA08C15'`; `('  ', 'X')` → `'X'`.
- [ ] **Step 2: Esegui e verifica che fallisca**.
- [ ] **Step 3: Implementa**: Kotlin restituisce `{settingsName: Settings.Global.getString(contentResolver, "device_name"), model: Build.MODEL}`; Dart lo legge in `initPlatform` su Android (errore → `null`, si resta su `hostName()`), e `main.dart` usa `tvDeviceName` come `hostName` di `DeviceIdentity.load` se non è `null`.
- [ ] **Step 4: Esegui** — verde; `flutter test` verde; `flutter analyze` pulito.
- [ ] **Step 5: Verifica sul Fire Stick** — dopo l'installazione e un avvio, sul server (`ssh ultra`, tabella `Devices` di `jellyfin.db` in sola lettura, come nel piano 1) l'app WonderFlix più recente ha `DeviceName = 'Fire TV Stick di davide'` (o il nome del dispositivo in Impostazioni → Il mio Fire TV) invece di `localhost`.
- [ ] **Step 6: Commit** — `feat(tv): nome del dispositivo in Jellyfin`

### Task 9: Giro di prova col telecomando (con l'utente)

**Files:**
- Modify: questo piano (sezione "Esito della prova")

- [ ] **Step 1: Build e installazione** sul Fire Stick (comandi nelle Global Constraints).
- [ ] **Step 2: Giro guidato**, prima via `adb input keyevent`, poi chiedendo all'utente di ripeterlo col telecomando vero:
  - avvio → home con il focus sul carosello; Sinistra apre la barra; scorrere tutte le voci; Stasera apre il pannello e Indietro lo chiude;
  - Cerca: OK sul campo apre la tastiera, si cerca "2012", si apre il titolo, il focus è su Riproduci;
  - player: OK pausa/play con controlli, Destra/Sinistra ±10 s, Giù sui pulsanti, "Audio e sottotitoli", Indietro chiude e poi esce;
  - una serie con episodio successivo (scegliere con l'utente un titolo che non gli rovini i progressi, o accettarne lo spostamento): il passaggio automatico all'episodio successivo funziona (punto aperto del piano 1: due player sui decoder del Fire Stick);
  - Richieste, La mia lista, Film/Serie e una saga; avatar → menu account → Impostazioni;
  - Indietro dalla radice: un Indietro mostra l'avviso, due escono.
- [ ] **Step 3: Rimetti a posto l'account** come nel piano 1 (sola lettura su `jellyfin.db` per controllare; correzioni dall'app).
- [ ] **Step 4: Scrivi l'esito** (passato/non passato per ogni punto, cosa ha notato l'utente) e commit — `docs(tv): esito del giro col telecomando`.

## Esito della prova

_Da compilare in Task 9._
