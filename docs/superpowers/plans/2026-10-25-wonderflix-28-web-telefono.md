# WonderFlix 28 — Web dal telefono (progetto 1c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tutta l'app WonderFlix si usa dal browser del telefono (iPhone e Android), col tocco e su schermi stretti, senza tagliare funzioni e senza cambiare il PC e l'app Windows.

**Architecture:** Un solo punto, `FormFactor` (`lib/ui/form_factor.dart`), dice a ogni widget se il layout è stretto (larghezza < 1024), se si usa il dito (ultimo puntatore) e se è un telefono (dito e lato corto < 600). Shell, finestre, schermate e player leggono `FormFactor.of(context)` e cambiano layout o input. Tutto sta nel codice Flutter comune. Nel codice web restano solo tre cose: lo schermo intero assente su iPhone, il blocco dell'orientamento e l'avvio rifiutato da iOS. Passano da `PlayerWindow` e `VideoEngine`.

**Tech Stack:** Flutter 3.47.5 (web wasm/JS e Windows), Riverpod, go_router, `package:web`, test con `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-25-wonderflix-web-telefono-design.md` (leggerla prima di ogni task). L'inventario del codice con le misure fisse è nella nota `C:\Users\sidot\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\side-session-notes\local_c1fabdd4-5bf9-48b0-a49f-e49412a76ade\1c-inventario-desktop.md`.

I percorsi `lib/…`, `test/…`, `web/…`, `deploy/…` sono dentro `app/`. Tutti i comandi `flutter` si lanciano da `app/`.

## Global Constraints

- Layout stretto: larghezza della finestra `< 1024` punti logici (`compactLayoutWidth = 1024.0`). Sopra, tutto identico a oggi.
- Modo tocco: ultimo puntatore `PointerDeviceKind.touch` o `stylus`. All'avvio vale `true` se `defaultTargetPlatform` è `android` o `iOS`, altrimenti `false`.
- Telefono: modo tocco e `MediaQuery.sizeOf(context).shortestSide < 600` (`phoneShortestSide = 600.0`).
- Nel layout stretto e nel modo tocco ogni elemento toccabile misura almeno 44×44 (`minTouchTarget = 44.0`).
- La decisione stretto/tocco viene solo da `MediaQuery` e dal tipo di puntatore, mai da `kIsWeb`, dallo user agent o da `Platform`.
- Con mouse e finestra ≥ 1024: sito sul PC e app Windows identici a oggi, scorciatoie comprese. `app/window_setup.dart` tiene `minWindowSize = Size(1024, 640)`.
- Nessuna funzione persa sul telefono: ogni azione raggiungibile sul PC è raggiungibile col dito nel layout stretto.
- Niente overflow (strisce gialle e nere) a 390×844, 844×390 e 768×1024.
- Testi dell'interfaccia in italiano e inglese nei file `l10n/app_it.arb` e `l10n/app_en.arb`. Commenti e documenti in italiano, codice in inglese, come il resto della repo.
- Nessuna modifica al plugin, al profilo video, ai token o alla build web della 1b.
- Commit solo a nome dell'utente (la configurazione git della worktree), **senza** la riga `Co-Authored-By`. Nei messaggi di commit niente parole `closes`/`fixes`.
- Mai `taskkill /IM` per nome dell'immagine: si chiude solo il processo avviato, per PID.
- Build Windows: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Build web: `flutter build web --release --wasm --base-href <percorso> --pwa-strategy=none --dart-define-from-file=config/wonderflix.json`. Il file `config/wonderflix.json` va copiato nella worktree da quella principale (`C:\Users\sidot\Documents\Github\wonderflix\app\config\wonderflix.json`) e non va mai committato.
- Ogni task finisce con `flutter analyze` pulito e `flutter test` tutto verde.

## Review Focus

1. **Tastiera virtuale sopra i campi.** Su telefono un campo in fondo alla pagina (finestre come pagina, chat del party, commento del voto, pannelli Consiglia e Vota) deve restare visibile con la tastiera aperta. → Test in Task 3 e Task 9 con `MediaQuery.viewInsets.bottom = 300`.
2. **Indietro del browser o del telefono con Amici e Notifiche aperti come pagina.** Deve chiudere la pagina e tornare dove si era, non uscire dalla sezione. → Sono rotte vere (Task 2), con un test di pop.
3. **Rotazione del telefono mentre una cosa è aperta.** Passando da 390×844 a 844×390 restano aperti il player, una finestra come pagina e il foglio "Altro", senza overflow. → Test in Task 2 e Task 9 che cambiano `setSurfaceSize` a metà.
4. **Finestra che passa sopra o sotto 1024 mentre un pannello laterale è aperto** (sito sul PC ridimensionato). Il pannello aperto come pannello resta usabile e non si apre due volte. → Test in Task 2.
5. **Avvio rifiutato da iOS a metà di un watch party.** "Tocca per riprodurre" compare, il tocco fa partire e il party si riallinea; senza tocco nessun ciclo di tentativi. → Test in Task 10.

Limite accettato, da non correggere: le finestre come pagina (Task 3) sono rotte senza URL, come oggi `showDialog`. Il gesto indietro di iOS con una finestra aperta può quindi chiudere anche la pagina sotto. La finestra ha la sua freccia indietro.

---

### Task 1: `FormFactor` e cablaggio

**Files:**
- Create: `lib/ui/form_factor.dart`
- Modify: `lib/app/app.dart` (il `builder:` di `MaterialApp.router`, riga ~59: avvolgere in `FormFactorScope`)
- Modify: `test/support/pump_app.dart` (parametro `formFactor`)
- Test: `test/ui/form_factor_test.dart`

**Interfaces:**
- Produces:
  - `const compactLayoutWidth = 1024.0; const phoneShortestSide = 600.0; const minTouchTarget = 44.0;`
  - `@immutable class FormFactor { const FormFactor({required this.compact, required this.touch, required this.phone}); final bool compact; final bool touch; final bool phone; static FormFactor of(BuildContext context); }`. `of` dipende da `MediaQuery.sizeOf` e dallo scope. Senza scope, `touch` è `false` e `compact` e `phone` si calcolano dalla misura.
  - `class FormFactorScope extends StatefulWidget { const FormFactorScope({super.key, required this.child, this.touchOverride}); final Widget child; final bool? touchOverride; }`. Ha un `Listener` (`onPointerDown`, `onPointerHover`) che aggiorna il tipo dell'ultimo puntatore e lo pubblica con un `InheritedWidget`. Con `touchOverride != null` il modo tocco è fisso.
  - `pumpApp(..., bool touch = false)` e `pumpAppRouter(..., bool touch = false)` / `pumpAppRouterOf(...)`: avvolgono il figlio in `FormFactorScope(touchOverride: touch)`. Così i `tester.tap` (che sono tocchi) non cambiano i test esistenti.

- [ ] **Step 1: Write the failing tests** in `test/ui/form_factor_test.dart`:
  - `'stretto sotto 1024, largo da 1024'`: a 1023×800 `compact == true`, a 1024×800 `compact == false`.
  - `'telefono: tocco e lato corto sotto 600'`: con `touchOverride: true`, 390×844 e 844×390 danno `phone == true`, 768×1024 dà `phone == false`, e con `touchOverride: false` 390×844 dà `phone == false`.
  - `'il tocco segue l ultimo puntatore'`: scope senza override; `tester.tap` (tocco) → `touch == true`; poi un `TestGesture` con `kind: PointerDeviceKind.mouse` che fa `addPointer` + `moveTo` → `touch == false`.
  - `'senza scope: niente tocco, misura dalla MediaQuery'`.
- [ ] **Step 2: Run** `flutter test test/ui/form_factor_test.dart`. Expected: FAIL, `form_factor.dart` non esiste.
- [ ] **Step 3: Implement** `lib/ui/form_factor.dart` come sopra, poi avvolgi il `builder:` di `lib/app/app.dart` (fuori dal `WfMotionScope`) e i tre helper di `test/support/pump_app.dart`.
- [ ] **Step 4: Run** `flutter test test/ui/form_factor_test.dart`, poi `flutter test` e `flutter analyze`. Expected: PASS.
  - I test esistenti che usano una superficie larga meno di 1024 ora vedono il layout stretto. Se uno si rompe, per esempio i test di `_barTitleCompactWidth = 420` o della griglia compatta del calendario, portalo a una larghezza ≥ 1024 dove il layout di oggi resta.
  - Se misurano davvero la larghezza della barra o della cella, avvolgi il widget sotto prova in un `MediaQuery` largo. Cambiane solo la misura, non le attese.
- [ ] **Step 5: Commit** `feat(ui): FormFactor per layout stretto e tocco`.

### Task 2: Shell stretta — barra in basso, "Altro", barra in alto, pannelli come pagine

**Files:**
- Modify: `lib/app/app_shell.dart` (layout stretto della barra in alto, barra in basso, avvisi a tutta larghezza)
- Create: `lib/app/shell_bottom_bar.dart` (barra in basso e foglio "Altro")
- Modify: `lib/app/router.dart` (rotte `/friends`, `/inbox`, `/recommend`, `/rate` nella ShellRoute)
- Modify: `lib/app/shell_panels.dart` (helper `openShellPanel`)
- Modify: `lib/features/friends/friends_button.dart`, `lib/features/inbox/inbox_button.dart`, i chiamanti di `openRecommendPanel` / `openRatePanel` (cercali con grep)
- Modify: `lib/features/friends/friends_panel.dart`, `lib/features/inbox/inbox_button.dart` (o il file del pannello), `lib/features/recommendations/recommend_panel.dart`, `lib/features/ratings/rate_panel.dart`: gli host non disegnano il pannello laterale nel layout stretto, e ognuno ha una pagina che riusa il contenuto
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/app_shell_compact_test.dart`, `test/app/l10n_plan28_test.dart`

**Interfaces:**
- Consumes: `FormFactor.of`, `minTouchTarget` (Task 1).
- Produces:
  - `void openShellPanel(BuildContext context, WidgetRef ref, ShellPanel panel)`. Nel layout stretto fa `context.push(shellPanelRoute(panel))`, altrimenti `ref.read(shellPanelProvider.notifier).toggle(panel)`. Lo usano tutti i pulsanti che oggi chiamano `toggle`/`open` per i quattro pannelli. `openRecommendPanel`/`openRatePanel` impostano il soggetto come oggi e poi lo chiamano.
  - `String shellPanelRoute(ShellPanel panel)` → `/friends`, `/inbox`, `/recommend`, `/rate`.
  - Ogni pagina-pannello chiama `open(panel)` in `initState` e `close()` in `dispose`, così letture delle notifiche e ricarica degli amici funzionano come oggi. Ha una barra con la freccia indietro (`navBack`). Se manca il soggetto (Consiglia e Vota dopo un ricaricamento) torna alla Home, come le altre rotte con `extra`.
  - Chiavi l10n nuove: `navMore` = "Altro" / "More".
- [ ] **Step 1: Write the failing tests** in `test/app/app_shell_compact_test.dart`, con `pumpAppRouter` a 390×844 e `touch: true`, e gli stessi override di `test/app/app_shell_test.dart`:
  - `'stretto: barra in basso con Home, Cerca, La mia lista, Altro'`: ci sono `Key('bottom-nav-/home')`, `-/search`, `-/mylist`, `-/more`; manca `-/requests` senza le richieste; `find.byKey(Key('nav-/movies'))` non c'è.
  - `'stretto: Richieste in basso quando ci sono'` (`SocialFeatures(requests: true)`).
  - `'Altro apre Film, Serie, Impostazioni, Cambia profilo, Esci; Admin solo per gli admin'`. Tocca "Film": va su `/movies` e il foglio si chiude.
  - `'stretto: Amici apre /friends come pagina e indietro torna alla pagina di prima'` (Review Focus 2).
  - `'largo (1440×900): barra in alto di oggi, niente barra in basso, Amici apre il pannello laterale'`.
  - `'da stretto a largo con Altro aperto: niente eccezioni'` (Review Focus 3/4): `setSurfaceSize` da 390×844 a 844×390 e poi a 1440×900.
  - `'stretto: niente overflow a 390×844 e 844×390'`: `tester.takeException()` è `null`.
  - `test/app/l10n_plan28_test.dart` sul modello di `l10n_plan25b_test.dart`, con lista `_keys` che i task successivi estendono. Per ora contiene `navMore`, con valori `Altro`/`More`.
- [ ] **Step 2: Run** `flutter test test/app/app_shell_compact_test.dart test/app/l10n_plan28_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Barra in alto stretta, alta 56:
    - a sinistra `_BackButton` e logo alto 28;
    - `_BarTitle` al centro;
    - a destra `WatchPartyButton`, `InboxButton`, `FriendsButton` e l'avatar senza nome, che apre lo stesso `_UserMenu`.
  - Barra in basso `ShellBottomBar(location:)`, alta 56 più `SafeArea`, con icone Lucide ed etichetta. "Altro" apre `showModalBottomSheet` con le voci della spec §4.2. Le voci condizionali seguono gli stessi provider di oggi: `requestsAvailableProvider`, `calendarAvailableProvider`, `user.isAdministrator`, `profilesProvider…isFull`.
  - Le pagine sotto la barra in basso lasciano il margine in fondo come `ShellPageFrame` fa per la barra in alto.
  - Avvisi (`top: 72, right: 24`) nel layout stretto: `left: 8, right: 8`, larghezza piena.
  - Le pagine-pannello sono `shellPage` nella ShellRoute.
- [ ] **Step 4: Run** i test del passo 1, poi `flutter test` e `flutter analyze`. Expected: PASS. I test esistenti della shell (a 1440×900) restano verdi senza cambiare le attese.
- [ ] **Step 5: Commit** `feat(shell): barra in basso, Altro e pannelli come pagine nel layout stretto`.

### Task 3: Finestre come pagine

**Files:**
- Modify: `lib/ui/wf_dialog.dart`, `lib/ui/wf_confirm_dialog.dart`
- Modify (fanno scorrere il proprio contenuto): `lib/features/account/change_password_dialog.dart`, `lib/features/account/link_contact_dialog.dart`, `lib/features/account/unlink_contact_dialog.dart`, `lib/features/admin/set_password_dialog.dart`, `lib/features/requests/approve_dialog.dart`, `lib/features/profiles/avatar_dialog.dart`
- Modify (misure fisse più larghe dello schermo): `lib/features/item_edit/images_dialog.dart`, `lib/features/item_edit/identify_dialog.dart`, `lib/features/tonight/tonight_dialog.dart`, `lib/features/detail/media_info_dialog.dart`
- Test: `test/ui/wf_dialog_test.dart` (crealo o estendilo se c'è già)

**Interfaces:**
- Consumes: `FormFactor` (Task 1).
- Produces: `showWfDialog<T>(context, {required builder, maxWidth = 480, semanticLabel, bool fullPageWhenCompact = true})`.
  - Nel layout stretto, con `fullPageWhenCompact`, apre una `MaterialPageRoute<T>(fullscreenDialog: true)` sul navigatore radice. La pagina ha fondo `WfColors.surface`, `SafeArea`, una riga in alto con la freccia indietro (`navBack`, che fa `Navigator.pop` con `null`) e sotto il `builder` con padding 16. L'altezza è limitata come in un `Dialog`, cioè lo spazio della pagina meno la tastiera (`viewInsets.bottom`).
  - Altrimenti apre il `Dialog` di oggi.
  - Il valore restituito resta lo stesso: `pop(value)` dentro il builder funziona in tutti e due i casi.
  - `showWfConfirmDialog` passa `fullPageWhenCompact: false`: le conferme brevi restano al centro e il loro contenuto scorre.
- [ ] **Step 1: Write the failing tests** in `test/ui/wf_dialog_test.dart`:
  - `'stretto: la finestra è una pagina con la freccia indietro e restituisce il valore'`: a 390×844 c'è un `Scaffold` della pagina e un `IconButton` con tooltip "Indietro". `pop('ok')` restituisce `'ok'`; la freccia restituisce `null`.
  - `'largo: la finestra è un Dialog come oggi'` a 1440×900.
  - `'conferma breve: resta Dialog anche nello stretto'`.
  - `'tastiera aperta: il campo attivo resta visibile'` (Review Focus 1): `ChangePasswordDialog` a 390×844 con `MediaQuery(viewInsets: EdgeInsets.only(bottom: 300))`. Tocca l'ultimo campo: il suo rettangolo (`tester.getRect`) sta sopra `844 - 300`, e non ci sono eccezioni.
  - Un test per ogni finestra dell'elenco "Modify" sopra, a 390×844 e 844×390, che la apre con i fake esistenti (`test/support/*_fakes.dart`). Expected: `tester.takeException()` `null`.
- [ ] **Step 2: Run** `flutter test test/ui/wf_dialog_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** il ramo pagina di `showWfDialog`.
  - Le sei finestre che non scorrono avvolgono la loro `Column` in un `SingleChildScrollView`, senza `Flexible` dentro.
  - Le misure fisse (immagini 900, identifica con campi 240/90/130, stasera h360, griglia avatar 6×56, colonna etichette 120) diventano: `Wrap` per i campi, griglie a `maxCrossAxisExtent`, altezze massime e non fisse.
  - Sopra 1024 l'aspetto non cambia.
- [ ] **Step 4: Run** `flutter test test/ui/wf_dialog_test.dart`, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): finestre come pagine nel layout stretto`.

### Task 4: Login, profili, persona, intestazioni delle pagine

**Files:**
- Modify: `lib/features/auth/login_screen.dart` (Row 716 px, TabBarView h300), `lib/features/profiles/profiles_screen.dart` (solo controllo), `lib/features/person/person_screen.dart`
- Modify: le intestazioni con titolo `display(40)` in `Row` senza `Flexible`. Trovale con grep su `requests_screen.dart`, `calendar_screen.dart`, `admin_screen.dart` e sulle schermate di catalogo e lista (`lib/features/catalog/`, `lib/features/mylist/`). Se esiste un'intestazione condivisa, cambia solo quella.
- Test: `test/features/compact_screens_test.dart` (nuovo; i task 5 e 6 lo estendono)

**Interfaces:**
- Consumes: `FormFactor` (Task 1).
- Produces: in `test/features/compact_screens_test.dart` l'helper `Future<void> expectNoOverflow(WidgetTester tester, Widget screen, {List<Override> overrides})`. Monta `screen` con `pumpApp(touch: true)` a 390×844, poi a 844×390, poi a 768×1024, con `pumpAndSettle` dopo ogni misura, e verifica `tester.takeException() == null`. I task 5 e 6 lo riusano.
- [ ] **Step 1: Write the failing tests:** `expectNoOverflow` per login, profili, persona, catalogo film, La mia lista, ricerca e impostazioni, con i fake esistenti.
  - Login stretto: il logo sta sopra il pannello, cioè `getRect(logo).bottom <= getRect(pannello).top`.
- [ ] **Step 2: Run** `flutter test test/features/compact_screens_test.dart`. Expected: FAIL (overflow nel login e nella persona).
- [ ] **Step 3: Implement.**
  - Login stretto: colonna che scorre, logo largo al massimo 200, pannello a tutta larghezza, schede senza altezza fissa.
  - Persona stretta: foto 140×210 sopra, nome `headlineMedium`.
  - Intestazioni: il titolo usa `Flexible`, si rimpicciolisce a `headlineMedium` nello stretto e va a capo.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): login, persona e intestazioni nel layout stretto`.

### Task 5: Home e scheda di film e serie

**Files:**
- Modify: `lib/features/home/hero_carousel.dart` (h460, testo 560, logo 420×110, `_EntryButtons` sovrapposti, swipe, puntini)
- Modify: `lib/features/home/home_row_view.dart` (poster 160, landscape 300, padding 32)
- Modify: `lib/features/detail/detail_header.dart` (altezza 560 fissa, Wrap fino a ~10 azioni), `lib/features/detail/series_detail_view.dart` (miniatura episodio 200), cast
- Test: `test/features/compact_screens_test.dart`, `test/features/home/hero_carousel_test.dart` (estendi se esiste)

**Interfaces:**
- Consumes: `FormFactor`, `expectNoOverflow` (Task 1, 4).
- [ ] **Step 1: Write the failing tests:**
  - `expectNoOverflow` per la Home (con `home_fakes.dart`), la scheda di un film e quella di una serie con episodi (`library_fakes.dart`).
  - `'carosello: trascinare a sinistra passa al titolo dopo'`: `tester.drag` di -300 in orizzontale → il titolo mostrato cambia.
  - `'scheda stretta: tutte le azioni raggiungibili'`: per un film con trailer e consigli, ogni azione che sul PC è un pulsante della testata (Riproduci, Ricomincia, Guarda insieme, Trailer, Preferito, Visto, Consiglia, Vota, ⋯) si trova come pulsante visibile o come voce del menu ⋯ dopo averlo aperto.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement.**
  - Carosello stretto: alto `min(460, larghezza × 1.1)`, testo a tutta larghezza meno 16 per lato, logo largo al massimo 240. I pulsanti Stasera e Match vanno sotto il testo invece che nell'angolo. Swipe con `PageView` o `GestureDetector.onHorizontalDragEnd` sullo stesso indice di oggi. Puntini con area di tocco 44.
  - Righe strette: poster 112, landscape 220, padding 16.
  - Testata stretta: altezza dal contenuto (immagine 16:9 sopra, testo e azioni sotto). Riproduci a tutta larghezza, poi una riga di icone, e il resto nel menu ⋯ che esiste già (`item_actions_menu.dart`).
  - Episodi stretti: miniatura 120 di larghezza.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(home,detail): Home e scheda nel layout stretto`.

### Task 6: Admin, richieste, calendario, match, menu e avvisi

**Files:**
- Modify: `lib/features/admin/admin_screen.dart` (5 tab in `Row`, `ServerStrip` fisso), `lib/features/admin/server_strip.dart`, `lib/features/admin/users_tab.dart`, `sessions_tab.dart`, `activity_tab.dart`, `maintenance_tab.dart`, `wonderflix_tab.dart`, `home_admin_cards.dart`
- Modify: `lib/features/requests/requests_screen.dart` (tab), `lib/features/requests/request_row.dart` (azioni ~230 px)
- Modify: `lib/features/calendar/calendar_screen.dart` (titolo 220 fisso), `lib/features/calendar/calendar_month_grid.dart` (altezza minima delle celle, scroll)
- Modify: `lib/features/match/match_screen.dart` (Row mazzo + colonna)
- Modify: `lib/features/watch_party/party_mode_menu.dart` (380), `lib/features/watch_party/watch_party_button.dart` (tile 320), `lib/features/watch_party/invite_card_frame.dart` e `lib/features/friends/friend_request_card.dart` (340)
- Test: `test/features/compact_screens_test.dart`

**Interfaces:**
- Consumes: `FormFactor`, `expectNoOverflow`.
- [ ] **Step 1: Write the failing tests:**
  - `expectNoOverflow` per l'Admin, una volta per scheda (con `admin_fakes.dart`), le richieste con una richiesta in attesa (`requests_fakes.dart`), il calendario (mese con uscite), il match (`match_fakes.dart`), il menu della modalità del party aperto e un invito al party mostrato.
  - `'admin stretto: le schede scorrono e si raggiungono tutte'`: si può toccare "WonderFlix" (l'ultima scheda) dopo `ensureVisible`.
  - `'richiesta stretta: Approva e Rifiuta sotto il titolo e toccabili'`: la `Size` di ciascuno è ≥ 44×44 e il titolo è largo almeno metà dello schermo.
  - `'calendario a 844×390: celle alte almeno 44, la griglia scorre'`.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement.**
  - Tab dell'Admin e delle richieste in uno `SingleChildScrollView` orizzontale (solo nello stretto, o sempre se l'aspetto largo non cambia).
  - `ServerStrip` dentro lo scroll della scheda nello stretto.
  - Righe di utenti, sessioni e task: azioni sotto il testo o nel menu della riga, già `PopupMenuButton` in `users_tab.dart`.
  - Calendario: titolo `Flexible` al posto di 220 fisso, celle con altezza minima `minTouchTarget` e griglia in uno scroll verticale quando non ci stanno.
  - Match: colonna (mazzo sopra, membri e coppie sotto) nello stretto.
  - Menu e avvisi: larghezza `min(misura di oggi, schermo - 16)`.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(admin,requests,calendar,match): layout stretto`.

### Task 7: Tocco al posto dell'hover fuori dal player

**Files:**
- Modify: `lib/ui/card_preview_host.dart` (pressione lunga col tocco → foglio dal basso), `lib/ui/card_preview.dart` (il contenuto si riusa nel foglio)
- Modify: `lib/features/player/queue_panel/queue_rows.dart` (`hoverOnly()`), `lib/features/inbox/inbox_panel.dart:416` (la ×)
- Modify: `lib/features/watch_party/party_chat_layer.dart` (timer di 20 s), `lib/features/watch_party/party_reactions_tray.dart` (5 s)
- Modify: le card con il bordo oro dell'hover: `lib/ui/poster_card.dart`, `landscape_card.dart`, `remote_image_card.dart`, `lib/features/collections/collection_card.dart`, `lib/features/requests/requestable_poster_card.dart`
- Test: `test/ui/card_preview_touch_test.dart`, più test in quelli esistenti della coda, delle notifiche, della chat e delle reazioni

**Interfaces:**
- Consumes: `FormFactor` (Task 1).
- Produces: `Future<void> showCardPreviewSheet(BuildContext context, JellyfinItem item, {CardPreviewExtra? extra, String? heroSource})`. È un `showModalBottomSheet` con lo stesso contenuto e le stesse azioni dell'anteprima di oggi, compresa la × dei consigli quando `extra` la prevede. Le azioni chiudono il foglio.
- [ ] **Step 1: Write the failing tests:**
  - `'tocco: pressione lunga su una card apre l anteprima dal basso con la × dei consigli'`, con `pumpApp(touch: true)` e una card di "Consigliati per te". Toccando la × parte la stessa chiamata di oggi (il fake la registra).
  - `'tocco: un tocco apre la scheda e nessuna anteprima'`.
  - `'mouse: l anteprima con l hover resta com è'`: il test esistente resta verde.
  - `'tocco: nella coda del party maniglia e × sono visibili e funzionano'`: rimuove una voce e la sposta trascinando la maniglia.
  - `'tocco: la × delle notifiche è visibile'`.
  - `'tocco: scorrere la chat rinnova la chiusura dopo 20 s'`: con `fakeAsync`, scorre a 15 s e a 30 s la chat è ancora aperta.
  - `'tocco: toccare il vassoio delle reazioni lo tiene aperto'`.
  - `'tocco: niente bordo oro rimasto acceso dopo un tocco su una card'`.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement.**
  - In `CardPreviewHost`, `onLongPress` solo con `FormFactor.touch`, attraverso `showCardPreviewSheet`.
  - `hoverOnly()` e la × delle notifiche sono sempre visibili quando `touch`.
  - I timer si rinnovano con `onPointerDown` e con le `ScrollNotification`.
  - Le card ignorano lo stato hover quando `touch`.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ui): tocco al posto dell'hover`.

### Task 8: Player — input col tocco

**Files:**
- Modify: `lib/features/player/player_screen.dart` (il `GestureDetector` del video, circa riga 1620; `Listener`/`MouseRegion`, circa riga 1590)
- Modify: `lib/features/player/player_chrome.dart` (`toggleControls()`)
- Modify: `lib/features/player/player_overlay.dart` (niente cursore del volume col tocco)
- Test: `test/features/player/player_touch_test.dart`

**Interfaces:**
- Consumes: `FormFactor` (Task 1).
- Produces: `PlayerChromeController.toggleControls()`. Mostra i controlli se sono nascosti e fa ripartire il timer di 3 s. Li nasconde se sono visibili, a meno che ci sia un riquadro aperto o che siano in pausa.
- [ ] **Step 1: Write the failing tests** in `test/features/player/player_touch_test.dart`, con il motore finto di `test/support/playback_fakes.dart` e `pumpApp(touch: true)` a 844×390:
  - `'tocco: un tocco sul video mostra i controlli e non mette in pausa'`: dopo 3 s i controlli sono nascosti; `tester.tap` sul video li fa tornare e `engine.playing` resta `true`.
  - `'tocco: un tocco con i controlli visibili li nasconde'`.
  - `'tocco: doppio tocco sulla metà destra va avanti di 10 s, sulla sinistra indietro di 10 s'`: confronta la posizione del motore prima e dopo.
  - `'tocco: niente cursore del volume'`.
  - `'mouse: tap = play/pausa, doppio clic = schermo intero'`: `pumpApp(touch: false)`, i test esistenti del player restano verdi.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement.**
  - Con `touch`, il `GestureDetector` del video fa così:
    - `onTap` chiude un riquadro aperto, oppure esce dal post-play, oppure chiama `_chrome.toggleControls()`;
    - `onDoubleTapDown` registra la x del tocco, e `onDoubleTap` chiama `controller.seekBy(±10 s)` in base alla metà;
    - c'è la pillola del salto (`SeekFeedback`) come per i tasti.
  - Senza `touch` resta il codice di oggi.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(player): controlli col tocco`.

### Task 9: Player — layout stretto

**Files:**
- Modify: `lib/features/player/player_overlay.dart` (riga dei controlli in basso, ~800 px)
- Modify: `lib/features/player/player_side_panel_host.dart` (`widthFor` 0.35w → foglio dal basso nello stretto)
- Modify: `lib/features/player/post_play.dart` (`postPlaySideRect`), `lib/features/player/pause_screen.dart`, `lib/features/player/player_extras.dart` (card dell'episodio successivo 380, salta intro), `lib/features/watch_party/party_chat_layer.dart` (chat 360 a sinistra, campo sopra la tastiera)
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`, `test/app/l10n_plan28_test.dart`
- Test: `test/features/player/player_compact_test.dart`

**Interfaces:**
- Consumes: `FormFactor`, `toggleControls` (Task 1, 8).
- Produces: chiave l10n `playerMoreControls` = "Altri controlli" / "More controls" (tooltip del menu ⋯).
- [ ] **Step 1: Write the failing tests** in `test/features/player/player_compact_test.dart`, a 390×844 e a 844×390 con `touch: true`:
  - `'stretto: controlli senza overflow, con play al centro'`.
  - `'stretto: ogni comando del player è raggiungibile'`: in un party con episodio successivo, ogni pulsante del layout largo si trova (per tooltip) come pulsante visibile o come voce del menu ⋯ (`playerMoreControls`). Sono tracce, coda, chat, reazioni, guarda insieme, precedente, successivo e schermo intero.
  - `'stretto: il pannello tracce si apre dal basso a tutta larghezza'`: la larghezza è uguale a quella dello schermo.
  - `'stretto: post-play con video sopra e informazioni sotto, senza overflow'`.
  - `'stretto: chat del party con la tastiera aperta, campo visibile'` (Review Focus 1), con `viewInsets.bottom = 300`.
  - `'rotazione col player aperto: niente eccezioni'` (Review Focus 3).
  - `'largo (1440×900): layout dei controlli di oggi'`: i test esistenti restano verdi.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement** la disposizione della spec §4.5.
  - In alto: indietro, titolo `titleLarge` su una riga e badge.
  - Al centro: −10, play 64, +10.
  - In basso: `SeekBar`, i tempi e una riga di icone 44×44. Quelle che non stanno vanno nel `PopupMenuButton` ⋯.
  - Pannelli in `PlayerSidePanelHost`: nello stretto si ancorano in basso, a tutta larghezza, alti al massimo il 70% e con `SafeArea`.
  - Chat stretta: a tutta larghezza in basso, sopra `viewInsets.bottom`.
  - Post-play stretto: colonna.
  - Card dell'episodio successivo e salta intro: `right: 16` e larghezza `min(380, schermo - 32)`.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(player): layout stretto`.

### Task 10: Schermo intero, orientamento e "Tocca per riprodurre"

**Files:**
- Modify: `lib/features/player/player_window.dart` (interfaccia e implementazione Windows), `lib/features/player/default_player_window_web.dart`
- Modify: `lib/core/video/video_engine.dart`, `lib/core/video/web_video_engine.dart` (`play()`, riga ~241), `lib/core/video/media_kit_engine.dart`
- Modify: `lib/features/player/player_screen.dart` (schermo intero all'apertura sul telefono, pulsante nascosto, strato "Tocca per riprodurre"), `lib/features/player/player_overlay.dart`
- Modify: `test/support/playback_fakes.dart` (fake del motore e della finestra)
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`, `test/app/l10n_plan28_test.dart`
- Test: `test/features/player/player_fullscreen_touch_test.dart`, `test/features/player/player_play_blocked_test.dart`

**Interfaces:**
- Consumes: `FormFactor.phone` (Task 1).
- Produces:
  - `PlayerWindow.supportsFullScreen` (`bool`): sul web è `document.fullscreenEnabled`, su Windows `true`.
  - `PlayerWindow.lockLandscape()` e `PlayerWindow.unlockOrientation()` (`Future<void>`):
    - sul web `screen.orientation.lock('landscape')` e `unlock()`, con gli errori inghiottiti e un log `fine`;
    - su Windows non fanno niente.
  - `VideoEngine.playBlockedStream` (`Stream<void>`): emette quando il browser rifiuta `play()` con `NotAllowedError`.
    - Sul web, `play()` cattura l'errore e, se il nome è `NotAllowedError`, emette e ritorna senza rilanciare.
    - media_kit restituisce `const Stream.empty()`.
    - Il fake ha `void blockNextPlay()`.
  - Chiave l10n `playerTapToPlay` = "Tocca per riprodurre" / "Tap to play".
- [ ] **Step 1: Write the failing tests:**
  - `'telefono: all apertura il player va a schermo intero e blocca l orizzontale, alla chiusura esce'`: con `touch: true` a 390×844, il fake della finestra registra `setFullScreen(true)` e `lockLandscape()`. All'uscita registra `setFullScreen(false)` e `unlockOrientation()`.
  - `'tablet (768×1024) e mouse: nessuno schermo intero automatico'`.
  - `'senza Fullscreen API (supportsFullScreen false): nessun pulsante schermo intero e il doppio clic non fa niente'`.
  - `'avvio rifiutato: compare Tocca per riprodurre, il tocco chiama play e lo strato sparisce'`: `engine.blockNextPlay()` prima dell'avvio.
  - `'avvio rifiutato nel party: dopo il tocco il driver riprende senza nuovi tentativi da solo'` (Review Focus 5): con i fake del watch party (`watch_party_fakes.dart`), conta le chiamate a `play()` senza tocco, e devono essere 1. Dopo il tocco la posizione si riallinea con il `DriftCorrector` come oggi.
- [ ] **Step 2: Run** e verifica il FAIL.
- [ ] **Step 3: Implement** le tre interfacce e lo strato.
  - Lo strato "Tocca per riprodurre" è un velo scuro a tutto schermo con un'icona play grande e il testo. Il tocco chiama `controller.togglePlay()`, o il percorso del party che oggi parte con Spazio.
  - Lo strato sparisce al primo `playingStream` `true`.
  - Lo schermo intero automatico parte una volta all'apertura, solo se `FormFactor.phone && supportsFullScreen`.
- [ ] **Step 4: Run** i test, poi `flutter test` e `flutter analyze`. Expected: PASS. Poi `flutter build web --release --wasm --base-href /wonderflix-prova/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json`. Expected: build riuscita (il codice `package:web` compila).
- [ ] **Step 5: Commit** `feat(player): schermo intero sul telefono e avvio bloccato da iOS`.

### Task 11: Aree sicure, sito di prova e documenti

**Files:**
- Modify: `lib/app/app_shell.dart`, `lib/app/shell_bottom_bar.dart`, `lib/features/player/player_overlay.dart` (`SafeArea` dove mancano ancora)
- Create: `deploy/wonderflix-prova.conf`
- Modify: `docs/RELEASING.md` (sito di prova e checklist del telefono)
- Test: `test/app/safe_area_test.dart`

**Interfaces:**
- Consumes: tutto quello che c'è sopra.
- [ ] **Step 1: Write the failing test** `'aree sicure: barra in basso e controlli del player stanno dentro il padding'`: a 390×844 con `MediaQuery(padding: EdgeInsets.only(top: 47, bottom: 34))`. Il rettangolo della barra in basso finisce a ≤ 844 - 34, e il pulsante indietro del player inizia a ≥ 47.
- [ ] **Step 2: Run** e verifica il FAIL, poi aggiungi i `SafeArea` mancanti. Run di nuovo. Expected: PASS. Poi `flutter test` e `flutter analyze`.
- [ ] **Step 3: Write `deploy/wonderflix-prova.conf`**: copia di `deploy/wonderflix.conf` con `/wonderflix-prova` e `/home/hashvps/wonderflix-web-prova/` al posto dei percorsi. La prima riga di commento dice che va in `~/.apps/nginx/proxy.d/wonderflix-prova.conf`.
- [ ] **Step 4: Update `docs/RELEASING.md`**:
  - una sezione "Sito di prova" con:
    - build con `--base-href /wonderflix-prova/`;
    - `rsync -a --delete build/web/ ultra:~/wonderflix-web-prova/` (prima tutto tranne `index.html`, poi `index.html`);
    - la conf e `app-nginx restart` solo la prima volta;
  - nella checklist dei test manuali, le prove dal telefono della spec §5 (barra in basso e Altro, anteprima tenendo premuto, episodio con tocco, salti e tracce, sottotitolo, richiesta, ogni scheda dell'Admin, Amici e Notifiche, watch party con il PC, tastiera sui campi, rotazione).
- [ ] **Step 5: Commit** `feat: aree sicure, conf del sito di prova e RELEASING` (con `deploy/wonderflix-prova.conf` e `docs/RELEASING.md`).

### Task 12: Sito di prova sul server e prova di Claude (lo fa il controllore, non un subagente)

- [ ] **Step 1:** Copia `config/wonderflix.json` nella worktree se non c'è. Da `app/`: `flutter build web --release --wasm --base-href /wonderflix-prova/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json`.
- [ ] **Step 2:** Con `ssh ultra`:
  - `mkdir -p ~/wonderflix-web-prova`;
  - copia `deploy/wonderflix-prova.conf` in `~/.apps/nginx/proxy.d/`;
  - `app-nginx restart`;
  - rsync in due passate.
  - Controlla con `curl -sI https://hashvps.proton.usbx.me/wonderflix-prova/` (200 e header COOP/COEP) e `curl -sI https://hashvps.proton.usbx.me/wonderflix/` (ancora 200: il sito di tutti non è toccato).
- [ ] **Step 3:** Browser integrato con `resize_window` preset `mobile` (390×812, tocco simulato), sul sito di prova. Il login lo fa l'utente con gli account di prova, mai Claude.
  - Esegui le prove della spec §5 in verticale e in orizzontale (844×390).
  - Rispetta i vincoli della spec: ClaudeNormal chiede un titolo piccolo e ClaudeAdmin lo approva; per i sottotitoli si cerca soltanto.
  - Fai un watch party fra il browser in modalità telefono e il sito sul PC in un'altra scheda.
- [ ] **Step 4:** Riporta `resize_window` a `desktop`. Fai un giro veloce sul sito di prova a 1440×900 col mouse: deve essere come prima.
  - Build Windows (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`), avvio, giro su Home, scheda e player, chiusura per PID.
- [ ] **Step 5:** Annota i problemi trovati, correggili con TDD nella worktree, ripubblica il sito di prova. Poi passa all'utente l'indirizzo `https://hashvps.proton.usbx.me/wonderflix-prova/` per la prova dal suo iPhone.
- [ ] **Step 6 (dopo l'ok dell'utente):**
  - merge su `main` e push;
  - `version: 0.22.0` in `app/pubspec.yaml` su `main` e tag `v0.22.0` come in `docs/RELEASING.md`;
  - note nella bozza della release;
  - spec a "realizzata", 1c tra le fatte in `docs/IDEE.md`.
