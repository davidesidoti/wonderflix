# Revisione finale, fase 1: pezzi comuni e correzioni — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** I pezzi comuni (testa e piede delle finestre, testa dei pannelli, controlli a tema) e le correzioni trasversali (TV, generi, testi) su cui poggiano le fasi 2–7.

**Architecture:** Due file nuovi in `ui/` (`wf_dialog_parts.dart`, `panel_header.dart`), `showWfDialog` che sa mettere un piede fisso e una barra nello stretto, temi in `theme.dart`. Il resto sono correzioni puntuali nei file che le hanno.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` (§3, §4.5–§4.6 per i punti TV del player, §10). Bozze: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/` (`strumenti.html` §guscio, `social.html` §guscio).

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Il worktree ha bisogno di `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\` e di `flutter pub get` e `flutter gen-l10n` prima di `analyze`/`test`.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`. Niente etichette in maiuscolo.
- Fuori dalla TV il comportamento TV non cambia, e viceversa: ogni layout TV è `compact && !tv`.
- `dart format` solo sulle righe toccate (un file vecchio riformattato riscrive centinaia di righe).
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).
- Nessun cambio al plugin.

## Review Focus

- **Finestra con testo ingrandito (textScaler 1,5) nello stretto:** il piede fisso resta visibile e il corpo scorre, nessun overflow. Test in Task 3.
- **Esc o clic fuori su una finestra con modifiche non salvate** chiedono conferma; senza modifiche chiudono al primo colpo (una seconda conferma sarebbe un fastidio). Test in Task 3.
- **TV, D-pad Giù su un campo in cornice:** il focus passa oltre senza aprire la tastiera (il campo non ottiene il focus). Test in Task 5 per ognuno dei quattro campi.
- **Errore del player in TV:** "Riprova" ha il focus appena compare l'errore, anche se prima il focus era sul nodo del player. Test in Task 6.
- **Pannello nello stretto e in TV:** nessuna ✕ (una sola chiusura, la ←); sul desktop la ✕ c'è ancora. Test in Task 4.

---

### Task 1: Generi che mancano

**Files:**
- Modify: `app/lib/core/jellyfin/genre_labels.dart`, `app/lib/ui/card_preview.dart`, `app/lib/features/player/pause_screen.dart`
- Test: `app/test/core/jellyfin/genre_labels_test.dart` (crealo se non c'è; se c'è, aggiungi i casi), `app/test/ui/card_preview_content_test.dart`, il test della pausa in `app/test/features/player/`

**Interfaces:**
- Produces: `genreLabel(String) -> String` con le voci nuove (firma invariata).

- [ ] **Step 1: Test che falliscono**

```dart
test('i generi del server senza traduzione diventano italiani', () {
  expect(genreLabel('Crime'), 'Poliziesco');
  expect(genreLabel('Romance'), 'Romantico');
  expect(genreLabel('Psychological'), 'Psicologico');
  expect(genreLabel('Martial Arts'), 'Arti marziali');
  expect(genreLabel('Medical'), 'Medico');
  expect(genreLabel('Food'), 'Cucina');
  expect(genreLabel('televisione film'), 'Film TV');
  expect(genreLabel('Fantasy'), 'Fantasy');
});
test('Poliziesco manda al server anche Crime', () {
  expect(genreServerNames('Poliziesco'), ['Poliziesco', 'Crime']);
});
```

E due test di widget, nei test già esistenti di `card_preview` (`test/ui/card_preview_content_test.dart`) e della pausa (`test/features/player/…pause…`): un titolo con generi `['Drama', 'Dramma', 'Crime', 'Thriller']` mostra "Dramma · Poliziesco" (tradotti, senza doppioni, al massimo 2).

- [ ] **Step 2:** `flutter test test/core/jellyfin/genre_labels_test.dart test/ui/card_preview_content_test.dart` più il test della pausa → FAIL.
- [ ] **Step 3:** aggiungi le sette voci a `_labels`. In `ui/card_preview.dart:369` (oggi `item.genres.take(3).join(' · ')`) e `features/player/pause_screen.dart:21` (`item.genres.take(2)`) usa i generi passati da `genreLabel`, senza doppioni, al massimo 2, come `heroMeta` in `features/home/hero_labels.dart` (riusa la stessa funzione se è pubblica, sennò estraila lì). `detail_header.dart` lo fa la fase 3; `tmdb_title_screen.dart` ha già i generi italiani di TMDB.
- [ ] **Step 4:** stessi comandi → PASS. Poi `flutter test test/features/catalog test/features/home` → PASS.
- [ ] **Step 5: Commit** `fix(app): traduzioni dei generi che restavano in inglese`

### Task 2: Controlli a tema

**Files:**
- Modify: `app/lib/app/theme.dart` (`buildWonderflixTheme`)
- Test: `app/test/app/theme_test.dart` (crealo se non c'è)

**Interfaces:**
- Produces: `ThemeData` con `chipTheme`, `checkboxTheme`, `radioTheme`, `switchTheme`, `dropdownMenuTheme` valorizzati.

Valori (spec §3.4):
- **Chip:** fondo `surfaceHigh`, bordo `border`, testo `cream` 12,5 w500, forma `StadiumBorder`, altezza 32; scelto → fondo `gold` al 14%, bordo `gold`, testo `gold`; spunta (`checkmarkColor`) `gold`.
- **Checkbox:** scelto → riempimento `gold`, spunta `bg`; vuoto → bordo `creamMuted` 1,5.
- **Radio:** scelto `gold`, vuoto `creamMuted`.
- **Switch:** acceso → traccia `gold`, pallino `bg`; spento → traccia `surfaceHigh`, bordo `border`, pallino `creamMuted`.
- **Dropdown menu:** `inputDecorationTheme` come quello dei campi, menu `surface` con bordo `border`.
- Sulla TV restano i `tvButtonSide`/velo del tema di oggi (nessun cambio TV).

- [ ] **Step 1: Test che falliscono**

```dart
test('le scelte sono oro', () {
  final t = buildWonderflixTheme();
  const selected = {WidgetState.selected};
  expect(t.chipTheme.side?.color, isNotNull);
  expect(t.checkboxTheme.fillColor!.resolve(selected), WfColors.gold);
  expect(t.radioTheme.fillColor!.resolve(selected), WfColors.gold);
  expect(t.switchTheme.trackColor!.resolve(selected), WfColors.gold);
  expect(t.chipTheme.selectedColor, WfColors.gold.withValues(alpha: 0.14));
});
```

- [ ] **Step 2:** `flutter test test/app/theme_test.dart` → FAIL.
- [ ] **Step 3:** aggiungi i temi in `base.copyWith(...)`.
- [ ] **Step 4:** stesso comando → PASS; poi `flutter test test/features/item_edit test/features/subtitles test/features/reports` (usano chip, checkbox, switch) → PASS. Un test che cercava un colore Material di serie si aggiorna al colore nuovo.
- [ ] **Step 5: Commit** `feat(app): chip, caselle, radio e interruttori nei colori dell'app`

### Task 3: Testa e piede delle finestre

**Files:**
- Create: `app/lib/ui/wf_dialog_parts.dart`
- Modify: `app/lib/ui/wf_dialog.dart`, `app/lib/ui/wf_confirm_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/ui/wf_dialog_test.dart` (aggiungi), `app/test/ui/wf_dialog_parts_test.dart` (nuovo)

**Interfaces:**
- Produces (le usano le fasi 2–7):
  - `class WfDialogHeader extends StatelessWidget { const WfDialogHeader({super.key, required String title, String? subtitle, Widget? leading}); }`: `leading` (di solito la locandina 36×54 con angoli 4) a sinistra, titolo `WfText.display(32)`, `subtitle` in `creamMuted` 12,5 sotto (una riga, ellissi).
  - `class WfDialogFooter extends StatelessWidget { const WfDialogFooter({super.key, String? note, required String cancelLabel, required VoidCallback? onCancel, required Widget primary}); }`: sopra un filo `border`; a sinistra `note` in `creamMuted` 12,5 (`Expanded`, va a capo); a destra `WfButton.secondary` con `cancelLabel` (icona `LucideIcons.x`) e `primary`. Le azioni vanno a capo (`Wrap`) se non ci stanno.
  - `class WfDiscardGuard extends StatelessWidget { const WfDiscardGuard({super.key, required int changes, required Widget child}); }`: con `changes > 0` intercetta il pop (`PopScope(canPop: false)`) e chiede `showWfConfirmDialog` con titolo `l.discardChangesTitle(changes)` ("Buttare le {n} modifiche?" / "Buttare la modifica?"), messaggio `l.discardChangesBody` ("Quello che hai cambiato non è ancora salvato."), conferma `l.discardChangesConfirm` ("Butta"), annulla `l.discardChangesKeep` ("Continua a modificare"); su conferma fa il pop. Con `changes == 0` non fa niente.
  - `showWfDialog<T>(... , String? compactTitle, WidgetBuilder? footer)`: due parametri nuovi, facoltativi (le chiamate di oggi non cambiano).
    - Desktop: `footer` sotto il corpo, a tutta larghezza fuori dal padding; il corpo scorre se non c'è spazio.
    - Stretto (pagina intera): barra in alto alta 56 con `compactTitle` (Bebas 26, ellissi) e una ✕ a destra (tooltip `MaterialLocalizations.closeButtonTooltip`) al posto della freccia di oggi; corpo che scorre; `footer` fisso in fondo, sopra la tastiera (`MediaQuery.viewInsets`).
    - TV: invariato (chi chiama passa `fullPageWhenCompact: !tv`).
- Consumes: `WfButton.secondary` (`ui/wf_buttons.dart`).

- [ ] **Step 1: Test che falliscono** (`wf_dialog_parts_test.dart` e `wf_dialog_test.dart`)

```dart
testWidgets('il piede ha la nota a sinistra, Annulla e il primario', (t) async {
  await pumpApp(t, Scaffold(body: WfDialogFooter(
    note: '3 modifiche', cancelLabel: 'Annulla', onCancel: () {},
    primary: WfButton.primary(label: 'Salva', icon: LucideIcons.check, onPressed: () {}))));
  expect(find.text('3 modifiche'), findsOneWidget);
  expect(t.getTopLeft(find.text('3 modifiche')).dx,
      lessThan(t.getTopLeft(find.text('Annulla')).dx));
  expect(t.getTopLeft(find.text('Annulla')).dx,
      lessThan(t.getTopLeft(find.text('Salva')).dx));
});
testWidgets('nello stretto il piede resta in fondo anche col testo grande', (t) async {
  // surfaceSize 390×780, MediaQuery textScaler 1.5, corpo alto 2000:
  // showWfDialog(compactTitle: 'Modifica metadati', footer: ...) →
  // il piede è dentro lo schermo (getBottomLeft.dy <= 780), nessuna eccezione di overflow,
  // e la barra mostra 'Modifica metadati' e la ✕.
});
testWidgets('con modifiche, Esc chiede prima di chiudere', (t) async {
  // finestra con WfDiscardGuard(changes: 2): Esc → compare 'Buttare le 2 modifiche?';
  // 'Continua a modificare' → la finestra resta; Esc + 'Butta' → si chiude.
});
testWidgets('senza modifiche Esc chiude subito', (t) async {
  // WfDiscardGuard(changes: 0): Esc → finestra chiusa, nessuna conferma.
});
testWidgets('la conferma usa testa e piede comuni', (t) async {
  // showWfConfirmDialog(...): il titolo ha lo stile WfText.display(32);
  // il pulsante di conferma è un WfButton.primary (non un FilledButton nudo).
});
```

(Scrivi i corpi completi seguendo lo stile dei test già in `wf_dialog_test.dart`.)

- [ ] **Step 2:** `flutter test test/ui/wf_dialog_test.dart test/ui/wf_dialog_parts_test.dart` → FAIL.
- [ ] **Step 3:** crea `wf_dialog_parts.dart`, estendi `showWfDialog`, rifai `showWfConfirmDialog` con `WfDialogHeader` + `WfDialogFooter` (icona del primario `LucideIcons.check`); aggiungi le quattro chiavi `discardChanges*` (con plurale ICU) in it/en; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS; poi `flutter test test/ui test/features/admin test/features/space` (usano la conferma) → PASS.
- [ ] **Step 5: Commit** `feat(app): testa, piede e conferma comuni per le finestre`

### Task 4: Testa dei pannelli, larghezza, ordine dei pulsanti

**Files:**
- Create: `app/lib/ui/panel_header.dart`
- Modify: `app/lib/ui/shell_side_panel.dart` (`width = 380.0`), `app/lib/app/app_shell.dart` (`_compactBar`: `FriendsButton` prima di `InboxButton`), `app/lib/features/friends/friends_panel.dart`, `app/lib/features/inbox/inbox_panel.dart`, `app/lib/features/recommendations/recommend_panel.dart`, `app/lib/features/ratings/rate_panel.dart`, `app/lib/ui/skeletons.dart`
- Test: `app/test/ui/panel_header_test.dart` (nuovo), aggiornamenti in `test/features/{friends,inbox,recommendations,ratings}` e `test/ui/shell_side_panel_test.dart`

**Interfaces:**
- Produces:
  - `class PanelHeader extends StatelessWidget { const PanelHeader({super.key, required String title, Widget? subtitle, List<Widget> actions = const [], required String closeTooltip, required VoidCallback onClose}); }`: titolo `WfText.display(30)`, `subtitle` sotto (riga `creamMuted` 13 o un widget come locandina+titolo), `actions` a destra prima della ✕. La ✕ c'è solo se `!FormFactor.of(context).compact && !FormFactor.of(context).tv` (nello stretto e in TV il pannello è una pagina con la sua ←). Padding `fromLTRB(20, 18, 12, 12)`.
  - `class PanelRowsSkeleton extends StatelessWidget { const PanelRowsSkeleton({super.key, int rows = 3}); }` in `skeletons.dart`: righe grigie con un cerchio 32 e due barre, con lo shimmer di `ui/shimmer.dart`.
- Consumes: niente da task precedenti.

Nei quattro pannelli: sostituisci la testa fatta a mano (`friends_panel.dart:107-124`, `inbox_panel.dart:143-162`, `recommend_panel.dart:158-175`, `rate_panel.dart:126-145`) con `PanelHeader`, senza cambiare il resto del contenuto (lo rifanno le fasi 3 e 5). Le azioni che oggi stanno nella testa (es. "Svuota" delle notifiche) passano in `actions`. Mentre carica, `PanelRowsSkeleton` al posto del vuoto in Amici, Notifiche e Consiglia (`friends_panel.dart:399`, `inbox_panel.dart:230`, `recommend_panel.dart:203`).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('sul desktop la testa ha la ✕', (t) async {
  await pumpApp(t, Scaffold(body: PanelHeader(title: 'Amici', closeTooltip: 'Chiudi', onClose: () {})));
  expect(find.byTooltip('Chiudi'), findsOneWidget);
});
testWidgets('nello stretto la testa non ha la ✕', (t) async {
  await pumpApp(t, Scaffold(body: PanelHeader(title: 'Amici', closeTooltip: 'Chiudi', onClose: () {})),
      surfaceSize: const Size(390, 780));
  expect(find.byTooltip('Chiudi'), findsNothing);
  expect(find.text('Amici'), findsOneWidget);
});
testWidgets('in TV la testa non ha la ✕', (t) async { /* tv: true, Size(960, 540) */ });
testWidgets('pannello largo 380', (t) async { expect(ShellSidePanel.width, 380); });
testWidgets('nello stretto Amici viene prima di Notifiche nella barra', (t) async {
  // monta la shell a 390×780 (come i test di app_shell esistenti):
  // getTopLeft(FriendsButton).dx < getTopLeft(InboxButton).dx
});
testWidgets('Amici mentre carica mostra le righe grigie', (t) async {
  // friendsController in caricamento → find.byType(PanelRowsSkeleton) findsOneWidget
});
```

- [ ] **Step 2:** `flutter test test/ui/panel_header_test.dart` → FAIL.
- [ ] **Step 3:** implementa `PanelHeader`, `PanelRowsSkeleton`, larghezza, ordine, e sostituisci le teste.
- [ ] **Step 4:** `flutter test test/ui test/app test/features/friends test/features/inbox test/features/recommendations test/features/ratings` → PASS. I test che cercavano la ✕ nelle pagine dello stretto (o lo stile Inter 20 del titolo) si aggiornano.
- [ ] **Step 5: Commit** `feat(app): testa comune dei pannelli e una sola chiusura nello stretto`

### Task 5: Campi di testo in cornice sulla TV

**Files:**
- Modify: `app/lib/features/reports/report_dialog.dart` (campo nota, ~`:286`; e `fullPageWhenCompact: !tv` dove si apre la finestra), `app/lib/features/detail/media_info_dialog.dart` (solo `fullPageWhenCompact: !tv` dove si apre), `app/lib/features/ratings/rating_widgets.dart` (~`:87`), `app/lib/features/recommendations/recommend_panel.dart` (~`:228`), `app/lib/features/auth/recovery_panel.dart` (`:301-368`: togli `autofocus: true` in TV e metti ogni campo in cornice)
- Test: `test/features/reports/report_dialog_test.dart`, `test/features/ratings/…`, `test/features/recommendations/…`, `test/features/auth/recovery_panel_test.dart` (aggiungi un caso TV a ciascuno)

**Interfaces:**
- Consumes: `TvTextFieldFrame({required FocusNode focusNode, required Widget child})` (`ui/tv_text_field_frame.dart`, già esistente; fuori dalla TV restituisce `child`). Ogni campo ha il suo `FocusNode` (crealo nello `State` e chiudilo in `dispose`).

- [ ] **Step 1: Test che falliscono**, uno per campo, a `Size(960, 540)` con `tv: true`:

```dart
testWidgets('TV: Giù passa sopra la nota senza aprire la tastiera', (t) async {
  // apri la finestra Segnala; dai il focus all'ultima pastiglia del tipo;
  // sendKeyEvent(LogicalKeyboardKey.arrowDown) → il focus è sulla cornice
  // (find.byType(TvTextFieldFrame)), il TextField NON ha il focus;
  // un altro Giù → il focus è sul pulsante del piede.
});
testWidgets('TV: Segnala è una finestra, non una pagina', (t) async {
  // find.byType(Dialog) findsOneWidget; nessun MaterialPageRoute a pagina intera
});
```

Stesso schema per il commento del voto, il messaggio di Consiglia e i campi del recupero password (in più: all'apertura nessun `TextField` ha il focus). Per Info tecniche solo il test "è una finestra".

- [ ] **Step 2:** `flutter test` sui quattro file → FAIL.
- [ ] **Step 3:** avvolgi i campi in `TvTextFieldFrame`, togli l'autofocus in TV, passa `fullPageWhenCompact: !FormFactor.of(context).tv` alle due finestre.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/tv_pages_test.dart test/features/tv_focus_borders_test.dart` → PASS.
- [ ] **Step 5: Commit** `fix(app): sulla TV i campi di testo non aprono più la tastiera da soli`

### Task 6: Player e Persona in TV

**Files:**
- Modify: `app/lib/features/player/player_side_panel_host.dart` (~`:447`), `app/lib/features/player/pause_screen.dart` (~`:242`), `app/lib/features/player/post_play.dart` (`:105`, `:196`), `app/lib/features/player/player_screen.dart` (`:1736` posizioni; `:1872-1881` errore), `app/lib/features/player/player_loading.dart` (`PlayerErrorLayer`), `app/lib/features/person/person_screen.dart` (`:81`)
- Test: `test/features/player/…` (pannelli, pausa, post-play, errore in TV), `test/features/person/person_screen_test.dart`

**Interfaces:**
- Consumes: `FormFactor.of(context)` (`compact`, `tv`); il `focusLayer(...)` già usato da `player_screen.dart` per i livelli del player.

Regole:
- In ognuno dei sei punti, dove oggi c'è `compact` per scegliere il layout del telefono, usa `compact && !tv`. In TV il pannello delle tracce e la coda tornano laterali (380 a destra, come sul desktop), la pausa usa le misure del desktop, il post-play ha l'immagine e niente trama (la trama si toglie solo in TV per stare in 540, spec §4.7), le posizioni di "Salta intro", carta e chat sono quelle del desktop.
- Errore: `PlayerErrorLayer` sta dentro un livello di focus proprio (`focusLayer` o un `FocusScope` con `autofocus`) e "Riprova" ha `autofocus: true`; `_onTvKey` (`player_screen.dart:1159`) non consuma frecce e OK quando lo stato è `PlayerStatus.error`.
- Persona: `compact && !tv` per il layout con la foto sopra il nome.

- [ ] **Step 1: Test che falliscono** (tutti a `Size(960, 540)`, `tv: true`)

```dart
testWidgets('TV: il pannello Audio e sottotitoli è laterale', (t) async {
  // apri il pannello: è ancorato a destra (getTopRight.dx == 960), largo 380, alto quanto lo schermo
});
testWidgets('TV: il post-play mostra l\'immagine dell\'episodio', (t) async { /* find.byKey dell'immagine */ });
testWidgets('TV: Riprova ha il focus quando il video fallisce', (t) async {
  // controller in errore → Focus del pulsante 'Riprova' hasFocus;
  // sendKeyEvent(LogicalKeyboardKey.select) → controller.retry chiamato
});
testWidgets('TV: la Persona ha la foto accanto al nome', (t) async {
  // getTopLeft(nome).dx > getTopRight(foto).dx
});
```

E un test di controllo per lo stretto non-TV (390×780): il pannello è ancora un foglio dal basso.

- [ ] **Step 2:** `flutter test test/features/player test/features/person` → FAIL sui casi nuovi.
- [ ] **Step 3:** applica le regole.
- [ ] **Step 4:** stessi test → PASS.
- [ ] **Step 5: Commit** `fix(app): in TV il player e la Persona non usano più il layout del telefono`

### Task 7: Testi, checklist

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`, `app/lib/features/player/pause_screen.dart:176`, `app/lib/features/friends/friends_panel.dart:743`, `app/lib/features/watch_party/watch_party_button.dart:58`, `app/lib/features/friends/activity_labels.dart:14`, `docs/RELEASING.md`
- Test: aggiorna i test che cercano i testi vecchi (`grep -rn` nelle cartelle `test/`)

Cambi:
- `loginSubmit`: "ACCEDI" → "Accedi" (en: "Sign in").
- `pause_screen.dart:176`, `friends_panel.dart:743`, `watch_party_button.dart:58`: togli `.toUpperCase()` e il `letterSpacing` delle etichette in Inter (i titoli in Bebas non si toccano: il Bebas è già maiuscolo).
- `friendsWatchingEpisode`: "Sta guardando {series} · {code}", con `code` String; `activity_labels.dart` passa `episodeCode(...)` o lo stesso formato "S{season}:E{episode}" (`features/library/item_labels.dart`).
- Le chiavi di "Tagline" in `edit_metadata_dialog` → "Frase di lancio"; "Carica dal PC…" in `images_dialog` → "Carica un file…" (cerca i valori nell'arb).
- `docs/RELEASING.md`: nella checklist della 0.42.0 una riga "Revisione finale, fase 1: finestre e pannelli con titolo Bebas e piede comune, una sola chiusura nello stretto, campi in TV che non aprono la tastiera, player e Persona in TV col loro layout, generi tradotti".

- [ ] **Step 1:** aggiorna i test che verificano questi testi ai valori nuovi (es. `find.text('Accedi')`, `find.textContaining('S2:E3')`) → FAIL.
- [ ] **Step 2:** cambia arb e codice; `flutter gen-l10n`.
- [ ] **Step 3:** `flutter test` sui file toccati → PASS.
- [ ] **Step 4: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta).
- [ ] **Step 5: Commit** `fix(app): etichette in frase normale e episodi nel formato S1:E2`

## Prova a mano (dopo la review finale)

Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`): una conferma (es. rimuovere un profilo), i quattro pannelli sul desktop e in una finestra stretta, i generi di una serie. APK sulla Fire Stick (comando in CLAUDE.md): Segnala dalla scheda, un video che fallisce (Riprova col telecomando), Audio e sottotitoli laterale.
