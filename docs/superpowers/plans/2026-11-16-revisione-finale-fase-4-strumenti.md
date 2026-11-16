# Revisione finale, fase 4: menu ⋯ e strumenti — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il menu ⋯ a gruppi con icone e le sette finestre che apre (Segnala, Info tecniche, Sottotitoli, Modifica metadati, Identifica, Aggiorna metadati, Locandina e sfondo), più il lato admin delle segnalazioni, nel guscio comune della fase 1.

**Architecture:** Ogni finestra passa a `WfDialogHeader` + `showWfDialog(compactTitle:, footer:)`. Il piede vive fuori dal corpo (fisso nello stretto), quindi lo stato gli arriva da un mixin piccolo (`WfFooterHost`, Task 1). Le scelte "a riquadro" sono un widget solo (`WfChoiceTile`). Le etichette dei codec e delle lingue stanno in un file di funzioni pure (`media_labels.dart`). Nessuna lettura nuova all'apertura, salvo la ricerca dei sottotitoli (§6.8).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, intl, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` (§3, §6 tutta, §10, §12 "Strumenti"). Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/strumenti.html`. Interfacce della fase 1: `docs/superpowers/plans/2026-11-16-revisione-finale-fase-1-comuni.md` (Task 3: `WfDialogHeader`, `WfDialogFooter`, `WfDiscardGuard`, `showWfDialog(compactTitle:, footer:)`; Task 2: temi dei controlli; Task 5: nota di Segnala in `TvTextFieldFrame`, Segnala e Info come finestra in TV; Task 7: "Frase di lancio", "Carica un file…").

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`, sopra le fasi 1–3 già fatte. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Prima di `analyze`/`test`: `flutter pub get` e `flutter gen-l10n`.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`. Icone Lucide (`LucideIcons.*`); se un nome citato non esiste nel pacchetto, l'equivalente più vicino.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`, raccolti per area, plurali con ICU. Niente etichette in maiuscolo. Le chiavi che restano senza uso si tolgono (`grep -rn "l\.<chiave>" lib`).
- Un solo `WfButton.primary` per vista, col verbo dell'azione, mai "Conferma". "Annulla" è `MaterialLocalizations.cancelButtonLabel`, "Chiudi" `closeButtonLabel`, "Riprova" `l.retry`.
- Episodi con `episodeCode` ("S1:E4"). Testo dell'utente e dei provider sempre come testo semplice.
- TV: Segnala e Info tecniche sono le sole finestre raggiungibili; restano finestre (`fullPageWhenCompact: !tv`, già fatto in fase 1). Fuori dalla TV il comportamento TV non cambia, e viceversa: ogni layout TV è `compact && !tv`.
- Nessun cambio al plugin. Nessuna lettura in più all'apertura delle finestre, salvo la ricerca dei sottotitoli.
- `dart format` solo sulle righe toccate.
- Commit: messaggio in italiano (`feat(app): …` / `fix(app): …`), nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).

## Review Focus

- **Data di uscita impossibile o nel formato vecchio** ("31/02/2024", "17/13/2008", "2008-12-17"): errore sotto il campo, "Salva" porta il focus lì, nessuna chiamata a `updateItem`. Test in Task 5.
- **Chiudere Segnala con la nota precompilata dal doppione e non toccata:** nessuna domanda (non è una modifica tua); con la nota scritta, Esc chiede "Buttare la modifica?". Test in Task 3.
- **Identifica su un titolo con `LockData` vero e nessun `LockedFields`:** la riga di sblocco c'è, dice "Sblocca il titolo bloccato" ed è spenta; spenta non chiama `updateItem`. Test in Task 6.
- **Locandina: toccare due candidate di fila, o Esc con una candidata segnata:** nessuna chiamata a Jellyfin; vale l'ultima toccata; Esc chiude senza cambiare. Test in Task 8.
- **Sottotitoli con la preferenza di lingua che arriva dopo l'apertura:** la prima ricerca è nella lingua della preferenza, non in quella di riserva, ed è una sola. Test in Task 10.

---

### Task 1: Pezzi della fase (riga del titolo, locandina piccola, riquadro di scelta, piede con stato, etichette dei codec)

**Files:**
- Modify: `app/lib/features/library/item_labels.dart`, `app/lib/ui/wf_dialog_parts.dart` (della fase 1), `l10n/app_it.arb`, `l10n/app_en.arb`
- Create: `app/lib/ui/dialog_item_poster.dart`, `app/lib/ui/wf_choice_tile.dart`
- Modify: `app/lib/core/jellyfin/media_labels.dart` (della fase 2: aggiungi `languageName` e `resolutionLabel`)
- Test: `app/test/features/library/item_labels_test.dart` (aggiungi), `app/test/ui/wf_dialog_parts_test.dart` (aggiungi), `app/test/ui/wf_choice_tile_test.dart` (nuovo), `app/test/core/jellyfin/media_labels_test.dart` (aggiungi)

**Interfaces:**
- Consumes: `WfDialogFooter`, `showWfDialog(footer:)` (fase 1), `imageUrlsProvider.primaryOf(id)`, `WfImage`, `TvFocusable`, `playbackLanguages` (`core/jellyfin/user_config_api.dart`).
- Produces:
  - `String itemContextLine(AppLocalizations l, JellyfinItem item)`: episodio "{serie} · {episodeCode} {nome}" ("L'Istituto · S1:E4 La scatola"); stagione "{serie} · {nome}"; film "{nome} · Film · {anno}"; serie "{nome} · Serie · {anno}"; altro il nome. Parti vuote saltate. Chiavi nuove `dialogKindMovie` "Film", `dialogKindSeries` "Serie".
  - `class DialogItemPoster extends ConsumerWidget { const DialogItemPoster({super.key, required String itemId}); }`: 36×54, angoli 4, `WfImage(image: primaryOf(itemId))`. È il `leading` di `WfDialogHeader` in tutte le finestre della fase.
  - `class WfChoiceTile extends StatelessWidget { const WfChoiceTile({super.key, required String title, String? description, IconData? icon, required bool selected, required VoidCallback? onTap, bool autofocus = false}); }`: riquadro `surfaceHigh`, bordo `border`, raggio 8, padding 12×14; scelto → bordo `gold`, fondo oro al 10%, icona e titolo `gold`. Titolo 13,5 w600, descrizione `creamMuted` 12 (una o due righe). `Semantics(selected:, button: true)`. Fuori dalla TV `InkWell`; in TV `TvFocusable(onActivate: onTap)` e l'`InkWell` con `canRequestFocus: false`.
  - In `wf_dialog_parts.dart`:
    - `WfDialogFooter`: `cancelLabel` e `onCancel` diventano facoltativi; senza `cancelLabel` niente "Annulla" (finestre col solo "Chiudi").
    - `mixin WfFooterHost<W extends StatefulWidget> on State<W> { final footerTick = ValueNotifier<int>(0); Widget buildFooter(BuildContext context); }`: sovrascrive `setState` (chiama `super.setState`, poi `footerTick.value++`) e `dispose`. Uno stato che cambia per `ref.watch` fa `footerTick.value++` in un `ref.listen`.
    - `class WfHostFooter extends StatelessWidget { const WfHostFooter({super.key, required GlobalKey host}); }`: `ListenableBuilder` su `footerTick` dello stato di `host` che disegna `buildFooter`; se lo stato non c'è ancora, `SizedBox.shrink()` e un nuovo giro al frame dopo. Uso: `final key = GlobalKey(); showWfDialog(..., builder: (_) => _Body(key: key), footer: (_) => WfHostFooter(host: key))`.
    - Il "Annulla" del piede chiama `Navigator.maybePop`, così `WfDiscardGuard` e i `PopScope(canPop: !busy)` valgono anche per lui.
  - Da `app/lib/core/jellyfin/media_labels.dart` (creato dalla fase 2, Task 7) si usano `codecLabel`, `channelsLabel` e `trackLanguageName(code, l.localeName)`; qui la lingua è `languageName(String? code, String localeName) => trackLanguageName(code, localeName) ?? (code ?? '').toUpperCase()`. Nello stesso file si aggiunge (lo usano i Task 8, 9 e 10):
    - `String? resolutionLabel(int? width)`: ≥3800 "4K", ≥1900 "1080p", ≥1260 "720p", sotto null.

- [ ] **Step 1: Test che falliscono**

```dart
test('riga del titolo', () {
  final l = lookupAppLocalizations(const Locale('it'));
  expect(itemContextLine(l, testItem(kind: ItemKind.episode, name: 'La scatola',
      seriesName: "L'Istituto", seasonIndex: 1, index: 4)), "L'Istituto · S1:E4 La scatola");
  expect(itemContextLine(l, testItem(name: 'The Wrestler', year: 2008)), 'The Wrestler · Film · 2008');
  expect(itemContextLine(l, testItem(kind: ItemKind.series, name: "L'Istituto", year: 2025)),
      "L'Istituto · Serie · 2025");
  expect(itemContextLine(l, testItem(name: 'Senza anno', year: null)), 'Senza anno · Film');
});
test('codec, canali, lingue, risoluzione', () {
  expect(codecLabel('eac3'), 'E-AC-3');
  expect(codecLabel('subrip'), 'SRT');
  expect(codecLabel('pgssub'), 'PGS');
  expect(codecLabel('xyz'), 'XYZ');
  expect(channelsLabel(6), '5.1');
  expect(languageName('ita', 'it'), 'Italiano');
  expect(languageName('eng', 'it'), 'Inglese');
  expect(languageName('swe', 'it'), 'SWE');
  expect(resolutionLabel(3840), '4K');
});
testWidgets('il piede segue lo stato del corpo', (t) async {
  // corpo con WfFooterHost: un contatore e un pulsante che fa setState(n++);
  // buildFooter → WfDialogFooter(note: '$n modifiche', primary: ...).
  // aperto con showWfDialog(footer: (_) => WfHostFooter(host: key)):
  // '0 modifiche' → tap → '1 modifiche'; anche a 390×780 (piede fisso).
});
testWidgets('piede senza Annulla', (t) async {
  // WfDialogFooter(primary: WfButton.secondary(label: 'Chiudi', ...)) → find.text('Annulla') findsNothing
});
testWidgets('il riquadro scelto è oro e si annuncia scelto', (t) async {
  // WfChoiceTile(title: 'Sottotitoli', description: 'Mancano…', selected: true, onTap: …)
  // → il testo del titolo ha color WfColors.gold; tester.getSemantics(...) ha isSelected;
  // tap → onTap chiamato; selected: false → titolo cream.
});
testWidgets('TV: OK sul riquadro col focus lo sceglie', (t) async {
  // tv: true, Size(960, 540): focus sul riquadro, sendKeyEvent(LogicalKeyboardKey.select) → onTap
});
```

- [ ] **Step 2:** `flutter test test/features/library/item_labels_test.dart test/core/jellyfin/media_labels_test.dart test/ui/wf_dialog_parts_test.dart test/ui/wf_choice_tile_test.dart` → FAIL.
- [ ] **Step 3:** implementa; aggiungi le due chiavi, `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/ui` → PASS.
- [ ] **Step 5: Commit** `feat(app): riga del titolo, riquadri di scelta, piede con stato ed etichette dei codec`

### Task 2: Menu ⋯ a gruppi, con icone e puntini

**Files:**
- Modify: `app/lib/features/detail/item_actions_menu.dart`, `app/lib/features/detail/detail_header.dart` (voci `extra`), `app/lib/features/detail/series_detail_view.dart` (solo se la fase 3 ha messo voci `extra` sul ⋯ della stagione), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/item_actions_menu_test.dart`, più i test che cercano le etichette vecchie (`grep -rln "'Segnala un problema'\|'Info tecniche'\|'Modifica metadati'\|'Identifica'\|'Locandina e sfondo'\|'Richiedi stagioni'" test/`, compresi i test della fase 3 sul ⋯ della testata)

**Interfaces:**
- Consumes: `menuPositionBelow(anchor, estimatedHeight:)`, `wfPopUpAnimation` (`ui/wf_menus.dart`), `TvFocusBorder`.
- Produces:
  - `typedef ExtraItemAction = ({String label, IconData icon, VoidCallback onSelected});` (campo `icon` nuovo: il compilatore trova ogni chiamata da aggiornare).
  - `List<List<ItemAction>> itemActionGroups(...)` (firma invariata): ora al massimo due gruppi, "Controlla e segnala" `[report, mediaInfo, subtitles]` e "Admin" `[editMetadata, identify, refresh, images]`; vuoti saltati.
  - `double itemActionsMenuHeight({required int groups, required int rows, required bool tv})`: altezza prevista per aprire il menu sopra il ⋯.

Regole (spec §6.1):
- Il bottone apre il menu con `showMenu(useRootNavigator: true, position: menuPositionBelow(context, estimatedHeight: itemActionsMenuHeight(...)))` al posto di `PopupMenuButton`: sotto se c'è posto, sopra se no (desktop e TV). Tooltip "Altre azioni" invariato, 44×44.
- Gruppi nell'ordine: "La tua visione" (le voci `extra`, nell'ordine in cui arrivano), "Controlla e segnala", "Admin". Ogni gruppo ha in testa il suo nome: `PopupMenuItem(enabled: false, height: 32)`, Inter 12 w600 `creamMuted`; fra un gruppo e l'altro `PopupMenuDivider`. Nome del gruppo admin dal primo elemento (`ItemAction.editMetadata`/`refresh`/`images`); chiavi `itemActionsGroupMine` "La tua visione", `itemActionsGroupCheck` "Controlla e segnala", `itemActionsGroupAdmin` "Admin".
- Ogni voce: `Row(Icon 18 creamMuted, 12, Text)`. Icone: report `flag`, mediaInfo `info`, subtitles `captions`, editMetadata `pencil`, identify `scanSearch`, refresh `refreshCw`, images `image`.
- Puntini su tutte le voci che aprono una finestra, mai su quelle che agiscono subito: `itemActionReport` "Segnala un problema…", `itemActionMediaInfo` "Info tecniche…", `itemActionEditMetadata` "Modifica metadati…", `itemActionIdentify` "Identifica…", `itemActionImages` "Locandina e sfondo…" (`itemActionSubtitles`, `itemActionRefresh` li hanno già). Inglese uguale ("Report a problem…", …).
- `detail_header.dart`: icone delle `extra`: Togli da Continua a guardare `history`, Togli da / Rimetti in Prossimi episodi `skipForward`, Consiglia a… `send`, Richiedi stagioni `plus` con etichetta nuova `requestsMoreSeasonsMenu` "Richiedi stagioni…" (la voce l'ha spostata la fase 3: qui cambia solo etichetta e icona). Voci del ⋯ della stagione della fase 3 (`series_detail_view.dart`): `l.detailSeasonMarkWatched` / `l.detailSeasonMarkUnwatched` con `circleCheck` / `circle` (senza puntini), `l.ratingRateSeason` con `star`, etichetta nuova `ratingRateSeasonMenu` "Vota la stagione…" (apre il pannello). Il pulsante "Vota la stagione" della riga dei voti tiene `ratingRateSeason`.
- TV (`tvOnly`): stesse voci di oggi, stessi nomi; `PopupMenuItem.height` 44; ogni voce in `TvFocusBorder` (il focus della TV, §3.5); il primo elemento selezionabile prende il focus all'apertura.

- [ ] **Step 1: Test che falliscono**

```dart
test('gruppi per ruolo e livello', () {
  expect(itemActionGroups(kind: ItemKind.movie, reports: true, canManageSubtitles: true, isAdmin: false),
      [[ItemAction.report, ItemAction.mediaInfo, ItemAction.subtitles]]);
  expect(itemActionGroups(kind: ItemKind.season, reports: true, canManageSubtitles: true, isAdmin: true),
      [[ItemAction.report], [ItemAction.editMetadata, ItemAction.refresh, ItemAction.images]]);
});
testWidgets('menu di un admin: gruppi con nome, icone e puntini', (t) async {
  // pumpDetail('m1', admin) con una voce extra 'Togli da Continua a guardare':
  // nomi 'La tua visione', 'Controlla e segnala', 'Admin' in quest'ordine (dy crescente);
  // find.text('Segnala un problema…'), 'Info tecniche…', 'Modifica metadati…', 'Identifica…',
  // 'Locandina e sfondo…' findsOneWidget; find.text('Togli da Continua a guardare') (senza puntini);
  // find.byType(PopupMenuDivider) findsNWidgets(2);
  // find.descendant(of: <voce Identifica…>, matching: find.byIcon(LucideIcons.scanSearch)) findsOneWidget.
});
testWidgets('i nomi dei gruppi non si scelgono', (t) async {
  // tap su 'Controlla e segnala' → il menu resta aperto, nessuna finestra
});
testWidgets('TV: voci di oggi, righe alte 44, menu sopra il ⋯ in fondo allo schermo', (t) async {
  // tv: true, Size(960, 540), ItemActionsButton(tvOnly: true, item: film, extra: [resume]) allineato in basso:
  // voci 'Togli da Continua a guardare', 'Segnala un problema…', 'Info tecniche…'; niente 'Sottotitoli…' né 'Admin';
  // tester.widget<PopupMenuItem<Object>>(<voce Info tecniche…>).height == 44;
  // getBottomLeft(<menu>).dy <= getTopLeft(find.byType(ItemActionsButton)).dy.
});
```

Aggiorna i test esistenti del file: le etichette coi puntini, "il menu di un film mostra le voci" con zero separatori, e le `extra` del primo test con `icon:`.

- [ ] **Step 2:** `flutter test test/features/detail/item_actions_menu_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi in it/en; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/detail test/features/tv_pages_test.dart` → PASS (aggiorna i test che cercavano le etichette senza puntini).
- [ ] **Step 5: Commit** `feat(app): menu ⋯ a gruppi con icone, puntini e apertura sopra in fondo allo schermo`

### Task 3: Segnala un problema

**Files:**
- Modify: `app/lib/features/reports/report_dialog.dart`, `app/lib/features/reports/report_labels.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/reports/report_dialog_test.dart`, `app/test/features/reports/report_labels_test.dart`

**Interfaces:**
- Consumes: Task 1 (`itemContextLine`, `DialogItemPoster`, `WfChoiceTile`, `WfFooterHost`, `WfHostFooter`), fase 1 (`WfDialogHeader`, `WfDialogFooter`, `WfDiscardGuard`, la nota già in `TvTextFieldFrame`).
- Produces: `IconData reportTypeIcon(ReportType)`, `String reportTypeExample(AppLocalizations, ReportType)` in `report_labels.dart`; `reportLevelEpisode` diventa "S{season}:E{episode}" (vale anche per le righe admin).

Regole (spec §6.2):
- `showWfDialog(compactTitle: l.reportDialogTitle, footer: …)`; testa `WfDialogHeader(title: 'Segnala un problema', subtitle: itemContextLine(l, item), leading: DialogItemPoster(itemId: item.id))`. Via `_contentLine`.
- Due domande con etichetta Inter 13 w600: `reportAskTarget` "Su cosa?" (pastiglie dei bersagli, solo se più di uno) e `reportAskType` "Che problema c'è?" (quattro `WfChoiceTile`, due colonne; una colonna se `compact && !tv`).
- Icone ed esempi (testo della spec con l'iniziale maiuscola, come nella bozza): Sottotitoli `captions` "Mancano, sono fuori sincrono, lingua sbagliata"; Titolo o informazioni `fileText` "Nome, trama o locandina sbagliati"; Audio o video `monitorPlay` "Si blocca, niente audio, lingua sbagliata"; Altro `messageSquare` "Qualcos'altro: scrivilo nella nota".
- Doppione: riquadro (bordo oro al 35%, fondo oro all'8%, icona `info`) con `reportAlreadySent` = "Hai già segnalato questo problema il {date}. Puoi cambiare la nota: gli admin vedono quella nuova." (`date` = `DateFormat('d MMMM', locale)` di `createdAt`, es. "14 novembre").
- Piede: nota `reportPickType` "Scegli che problema c'è" finché `_type == null`; primario `reportUpdate` "Aggiorna la segnalazione" con un doppione, sennò "Invia segnalazione" (icona `send`), spento senza tipo o durante l'invio.
- `WfDiscardGuard(changes: …)`: 1 se la nota (trim) non è vuota e diversa dalla nota precompilata, sennò 0. Contatore della nota come oggi (da 450).

- [ ] **Step 1: Test che falliscono**

```dart
test('episodio nel formato S1:E2', () {
  expect(reportLevelLabel(l, ReportItemType.episode, season: 1, episode: 2), 'S1:E2');
});
testWidgets('testa con la riga dell\'episodio e le due domande', (t) async {
  // episodio 'La scatola' S1:E4 di "L'Istituto" → find.text("L'Istituto · S1:E4 La scatola"),
  // 'Su cosa?', 'Che problema c\'è?', 'Mancano, sono fuori sincrono, lingua sbagliata'
});
testWidgets('senza tipo il piede lo dice e Invia è spento', (t) async {
  // find.text('Scegli che problema c\'è') findsOneWidget; WfButton 'Invia segnalazione' onPressed null;
  // tap 'Sottotitoli' → suggerimento sparito, Invia acceso
});
testWidgets('doppione: il riquadro spiega e il pulsante dice Aggiorna la segnalazione', (t) async {
  // mine = [testReport(type: subtitles, createdAt: 2026-11-14)] → tap 'Sottotitoli' →
  // find.textContaining('il 14 novembre') findsOneWidget; find.text('Aggiorna la segnalazione') findsOneWidget;
  // find.text('Invia segnalazione') findsNothing
});
testWidgets('nota scritta: Esc chiede; nota precompilata intatta: Esc chiude', (t) async {
  // scrivi 'x' → Esc → 'Buttare la modifica?'; altra finestra con doppione e nota precompilata → Esc → chiusa
});
testWidgets('telefono: i riquadri in colonna', (t) async {
  // Size(390, 780): getTopLeft('Titolo o informazioni').dy > getTopLeft('Sottotitoli').dy e stessa dx
});
```

Aggiorna i test esistenti: "Aggiungi dettagli (facoltativo)" resta l'hint; "S1 E2" diventa "S1:E2"; il test TV della fase 1 ("Giù passa sopra la nota") parte dall'ultimo riquadro invece che dall'ultima pastiglia.

- [ ] **Step 2:** `flutter test test/features/reports/report_dialog_test.dart test/features/reports/report_labels_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi nuove `reportAskTarget`, `reportAskType`, `reportPickType`, `reportUpdate`, `reportTypeExample*`, `reportAlreadySent` cambiata; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/reports test/features/admin` → PASS.
- [ ] **Step 5: Commit** `feat(app): Segnala con due domande, riquadri spiegati e Aggiorna la segnalazione`

### Task 4: Segnalazioni, lato admin

**Files:**
- Modify: `app/lib/features/reports/reports_banner.dart`, `app/lib/features/reports/resolve_report_dialog.dart`, `app/lib/features/reports/report_labels.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/reports/reports_banner_test.dart`, `app/test/features/reports/report_labels_test.dart`

**Interfaces:**
- Consumes: `AdminSectionTitle`, `AdminList`, `WfLamp`, `LampState` (`features/admin/admin_kit.dart`), `adminTimeLabel` (`admin_time.dart`), Task 1.
- Produces: `String reportSubjectLine(AppLocalizations l, ItemReport r)`: episodio "S1:E4 La scatola · Sottotitoli" (`itemName` dopo il codice), stagione "Stagione 1 · …", serie "Tutta la serie · …", film solo il tipo.

Regole (spec §6.3):
- Riquadro → `AdminSectionTitle(title: l.reportsOpenTitle "Segnalazioni aperte", count: n)` + `AdminList` (margini 32 come oggi, 16 se `compact`). Via `reportsBannerTitle`.
- Riga: `WfLamp(state: LampState.attention, label: l.reportOpen "Aperta")`, avatar 32, "{utente} · {adminTimeLabel}" (w600), `reportSubjectLine`, la nota tra “ ” in `creamMuted` 12,5 (una riga, ellissi) o "Nessuna nota". A destra (va a capo nello stretto): la scorciatoia come `TextButton.icon` (Cerca sottotitoli / Identifica / Modifica metadati, `reportShortcut` invariato), `WfButton.secondary` "Segna come sistemato…" (`reportFixedAction`), un ⋯ (`PopupMenuButton`, tooltip "Altre azioni") con "Segna come non sistemabile…" (`reportCannotFixAction`). Via `reportFixed`, `reportCannotFix`.
- La lampada verde (chiusa) e "Chiuse di recente" restano fuori: `ReportsApi.all()` dà solo le aperte (vedi Domande aperte).
- Finestra di chiusura: `WfDialogHeader(title: 'Segna come sistemato' | 'Segna come non sistemabile', subtitle: '{titleName} · {reportSubjectLine senza il tipo}', leading: DialogItemPoster(itemId: report.itemId))`; un riquadro `surfaceHigh` con avatar, nome, pastiglia del tipo, data `d MMMM` e la nota tra virgolette; il campo nota (hint di oggi); piede `WfHostFooter` con Annulla e il primario che ripete il titolo (icona `check` / `x`). Via la chiave `reportResolveConfirm`.
- Esito: la finestra si chiude con un enum privato (`closed`, `alreadyClosed`); `closed` → snackbar `reportClosed` "Segnalazione chiusa"; `alreadyClosed` → `reportAlreadyClosed` come oggi.

- [ ] **Step 1: Test che falliscono**

```dart
test('riga del soggetto', () {
  expect(reportSubjectLine(l, testReport(itemType: ReportItemType.episode, seasonNumber: 1,
      episodeNumber: 4, itemName: 'La scatola', type: ReportType.subtitles)), 'S1:E4 La scatola · Sottotitoli');
  expect(reportSubjectLine(l, testReport(itemType: ReportItemType.series, type: ReportType.metadata)),
      'Tutta la serie · Titolo o informazioni');
});
testWidgets('elenco della Cabina con una sola azione in evidenza', (t) async {
  // 2 segnalazioni → find.text('Segnalazioni aperte'), find.byType(AdminList), find.byType(WfLamp) findsNWidgets(2);
  // find.widgetWithText(WfButton, 'Segna come sistemato…') findsNWidgets(2);
  // nessun WfButton.primary nell'elenco; 'Segna come non sistemabile…' solo dopo il tap sul ⋯ della riga
});
testWidgets('la finestra mostra la segnalazione e il pulsante ripete il titolo', (t) async {
  // tap 'Segna come sistemato…' → nota “Dal minuto 12…” visibile, find.text('Conferma') findsNothing,
  // tap sul primario 'Segna come sistemato' → resolve(fixed) e snackbar 'Segnalazione chiusa'
});
```

Aggiorna i test esistenti ("Conferma" → il titolo ripetuto, "Sistemato"/"Non sistemabile" → le voci coi puntini, il ⋯ per non sistemabile; "Conferma chiama resolve una volta" diventa col primario).

- [ ] **Step 2:** `flutter test test/features/reports/reports_banner_test.dart test/features/reports/report_labels_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/reports test/features/admin test/features/detail` → PASS.
- [ ] **Step 5: Commit** `feat(app): segnalazioni dell'admin con l'elenco della Cabina e Segnalazione chiusa`

### Task 5: Modifica metadati

**Files:**
- Modify: `app/lib/features/item_edit/edit_metadata_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/item_edit/edit_metadata_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1, fase 1 (`WfDialogHeader`, `WfDiscardGuard`), `JellyfinItem.fromJson(raw)` per la testa (la `Map` è già letta: nessuna lettura nuova).
- Produces: `DateTime? parseItalianDate(String text)` (solo "gg/mm/aaaa", date impossibili → null), `String formatItalianDate(DateTime d)` ("17/12/2008"), nello stesso file. `applyMetadataEdits` invariato.

Regole (spec §6.4):
- Larga 880; due colonne (sinistra: Titoli, Trama e frase di lancio; destra: Date, Generi, Classificazione, Blocca tutto), una sola se `compact`. Titoli dei gruppi `WfText.display(20)`: "Titoli", "Trama e frase di lancio", "Date", "Generi", "Classificazione", "Blocca tutto".
- In cima `editLockExplain` "I campi che modifichi restano tuoi: Jellyfin non li sovrascrive più. Il lucchetto li libera."
- Campi bloccabili (`lockableFields`): sopra il campo, a destra, un'etichetta toccabile con icona: "Bloccato" (`lock`, oro) / "Si aggiorna da solo" (`lockOpen`, `creamMuted`); tooltip di oggi. Gli altri campi senza lo spazio vuoto (via `_row` con `SizedBox(width: 40)`). Il campo tiene il suo `labelText`.
- Data: hint "gg/mm/aaaa", icona calendario in fondo al campo che apre `showDatePicker` e scrive `formatItalianDate`; la data letta si mostra con `formatItalianDate`. Errori con `errorText` sotto il campo, solo dopo "Salva": titolo vuoto `editErrorName` "Il titolo non può essere vuoto"; anno non di 4 cifre `editErrorYear` "Scrivi l'anno con quattro cifre"; data `editErrorDate` "Scrivi la data come gg/mm/aaaa, per esempio 17/12/2008." "Salva" con un errore dà il focus al primo campo sbagliato (`FocusNode` per titolo, anno, data) e non chiama Jellyfin.
- Generi: `WfButton.secondary` "Aggiungi" (`plus`) accanto al campo; al salvataggio un genere scritto e non aggiunto entra (come `_addGenre`); `editGenrePendingHint` "Un genere scritto e non ancora aggiunto entra quando salvi."
- Conteggio: campi di testo diversi dal letto + generi (o un genere scritto) + classificazione + "Blocca tutto" + lucchetti girati a mano diversi da quelli letti. Piede: nota `editChanges(n)` "{n, plural, =1{1 modifica} other{{n} modifiche}}" (niente nota a 0); "Salva" spento solo a 0 modifiche o durante il salvataggio.
- `WfDiscardGuard(changes: n)`; `compactTitle` "Modifica metadati"; testa con `itemContextLine` dopo il caricamento.
- Caricamento fallito: l'errore e `WfButton.secondary` "Riprova" che rilegge.
- `editLockAll` diventa "Blocca tutto il titolo".

- [ ] **Step 1: Test che falliscono**

```dart
test('date italiane', () {
  expect(parseItalianDate('17/12/2008'), DateTime(2008, 12, 17));
  expect(parseItalianDate('31/02/2024'), isNull);
  expect(parseItalianDate('17/13/2008'), isNull);
  expect(parseItalianDate('2008-12-17'), isNull);
  expect(formatItalianDate(DateTime(2008, 12, 7)), '07/12/2008');
});
testWidgets('il lucchetto dice lo stato a parole', (t) async {
  // lockedFields: ['Name'] → 'Bloccato' vicino al Titolo; 'Si aggiorna da solo' su Trama, Generi, Classificazione;
  // Titolo originale senza etichetta; modificare la Trama → diventa 'Bloccato'
});
testWidgets('data sbagliata: errore sotto il campo, focus lì, nessun salvataggio', (t) async {
  // scrivi '17/13/2008' → tap Salva → find.text('Scrivi la data come gg/mm/aaaa, per esempio 17/12/2008.');
  // il TextField della data hasFocus; editApi.calls non contiene 'updateItem'
});
testWidgets('il piede conta le modifiche e Salva è spento senza', (t) async {
  // all'apertura Salva onPressed null e nessuna nota; cambia Titolo e Trama → '2 modifiche', Salva acceso
});
testWidgets('un genere scritto e non aggiunto entra al salvataggio', (t) async {
  // scrivi 'Western' nel campo genere senza Invio → Salva → Genres contiene 'Western'
});
testWidgets('caricamento fallito: Riprova rilegge', (t) async {
  // rawItem lancia una volta → tap 'Riprova' → campi precompilati
});
```

Aggiorna i test esistenti: "Salva spento con titolo vuoto o data impossibile" diventa il test degli errori; la data letta è "gg/mm/aaaa".

- [ ] **Step 2:** `flutter test test/features/item_edit/edit_metadata_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando e `flutter test test/features/detail/item_actions_menu_test.dart test/features/reports` → PASS.
- [ ] **Step 5: Commit** `feat(app): Modifica metadati a gruppi, lucchetti a parole, data italiana e conteggio`

### Task 6: Identifica

**Files:**
- Modify: `app/lib/features/item_edit/identify_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/item_edit/identify_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1, `TicketClipper.vertical`/`TicketTearPainter.vertical` (`ui/ticket_shape.dart`), `RemoteSearchResult.raw['ProviderIds']`.
- Produces: `bool isCurrentMatch(Map<String, dynamic> item, RemoteSearchResult r)`: vero se un id `Tmdb`, `Imdb` o `Tvdb` non vuoto è uguale (senza distinguere maiuscole). `List<String> lockedFieldLabels(AppLocalizations l, Map<String, dynamic> item)`: i nomi dei `LockedFields` ("Titolo", "Trama", "Generi", "Classificazione per età").

Regole (spec §6.5):
- Campi: Nome, Anno, ID TheMovieDb (`identifyTmdb` "ID TheMovieDb"), ID IMDb con hint "tt…", ID TVDB solo per le serie (già così). "Cerca" è `WfButton.secondary` (il primario è "Applica").
- Risultati in riquadri (3 colonne, 1 nello stretto): locandina 48×72 o sagoma (`noimg`: icona `image` su `surfaceHigh`, bordo tratteggiato non serve: bordo `border`), nome, "{anno} · {fonte}"; scelto → bordo oro e spunta (`check` su cerchio oro); `isCurrentMatch` → targhetta "Attuale". Regista e durata dei risultati restano fuori: la ricerca di Jellyfin non li dà.
- Sotto i risultati, appena ce n'è uno scelto, due biglietti affiancati con una freccia oro in mezzo: "Ora" (spento, opacità 0,72): nome, "{anno} · Film|Serie" dalla `Map`, "Locandina e sfondo" o `identifyNoImages` "Nessuna locandina" se `ImageTags.Primary` manca; "Dopo" (bordo oro): nome, anno, `identifyNewImages` "Locandina e sfondo nuovi" se "Sostituisci anche le immagini" è acceso e il risultato ha `imageUrl`. In oro ciò che differisce da "Ora" (nome, anno, immagini).
- Opzioni (`SwitchListTile`, tema della fase 1): "Sostituisci anche le immagini" acceso, hint `identifyReplaceImagesHint` "Locandina e sfondo arrivano dal risultato scelto."; se ci sono blocchi, sblocco **spento di serie**: `identifyUnlockFields(n, fields)` "Sblocca i {n} campi modificati a mano ({fields})" (n=1: "Sblocca il campo modificato a mano ({fields})"), oppure `identifyUnlockAll` "Sblocca il titolo bloccato" con `LockData` vero e nessun campo; hint `identifyUnlockHint` "Spento, restano come li hai scritti tu. Acceso, Jellyfin li riscrive."
- Piede: nota "Può volerci qualche minuto…" (durante il lavoro, con la rotella), "Annulla" chiude sempre, primario `identifyApply` "Applica questo risultato" spento senza scelta. Via `identifyConfirm*` e il "Annulla che torna ai risultati".
- Stretto (`compact && !tv`): scelto un risultato, la vista passa ai biglietti in colonna con le opzioni; il piede ha `navBack` "Indietro" (torna ai risultati) e "Applica".
- Restano i messaggi "Titolo identificato" e "Jellyfin sta ancora lavorando: ricarica tra poco" e tutta la logica di `_apply`.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('sblocco spento di serie, coi campi nominati', (t) async {
  // lockedFields ['Name', 'Overview'] → cerca, scegli → find.text('Sblocca i 2 campi modificati a mano (Titolo, Trama)');
  // lo switch è spento; Applica → editApi.calls non contiene 'updateItem'
});
testWidgets('LockData senza campi: Sblocca il titolo bloccato, spento', (t) async { /* … */ });
testWidgets('il risultato attuale è segnato', (t) async {
  // ProviderIds Tmdb '70523' e un risultato con raw ProviderIds {'Tmdb': '70523'} → find.text('Attuale') findsOneWidget
});
testWidgets('Ora e Dopo nella stessa vista, nessun Annulla che torna indietro', (t) async {
  // scegli → find.text('Ora'), find.text('Dopo'), find.text('Locandina e sfondo nuovi');
  // tap 'Annulla' → finestra chiusa (non i risultati)
});
testWidgets('telefono: i biglietti in una seconda pagina con Indietro', (t) async {
  // Size(390, 780): scegli → 'Dopo' visibile, risultati no; 'Indietro' → risultati
});
```

Togli "Annulla nella conferma torna ai risultati"; i test di sblocco esistenti accendono lo switch prima di Applica.

- [ ] **Step 2:** `flutter test test/features/item_edit/identify_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): Identifica con i biglietti Ora e Dopo e lo sblocco spento di serie`

### Task 7: Aggiorna metadati

**Files:**
- Modify: `app/lib/features/item_edit/refresh_metadata_dialog.dart`, `app/lib/features/detail/item_actions_menu.dart` (chiamata), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/item_edit/refresh_metadata_dialog_test.dart`, `app/test/features/detail/item_actions_menu_test.dart`

**Interfaces:**
- Consumes: Task 1 (`WfChoiceTile`, `WfFooterHost`).
- Produces: `Future<void> showRefreshMetadataDialog(BuildContext context, {required JellyfinItem item})` (prima `itemId`: l'unico chiamante è il menu, che ha già l'item con `childCount` e `recursiveItemCount`).

Regole (spec §6.6):
- Testa con `itemContextLine`; domanda "Cosa aggiorno?"; due `WfChoiceTile`: `refreshMissing` "Completa i dati" / "Cerca solo ciò che manca."; `refreshReplaceAll` "Riscrivi tutto" / "Sostituisce tutto tranne i campi bloccati."
- `refreshAlsoImages` "Anche le immagini" (switch) con hint "Locandina, sfondo e logo tornano quelli scelti da Jellyfin.", attivo solo con "Riscrivi tutto".
- Su una serie: `refreshSeriesNote(seasons, episodes)` "Vale anche per le sue {seasons} stagioni e {episodes} episodi" (plurali: "la sua stagione", "1 episodio"); senza i numeri `refreshSeriesNoteUnknown` "Vale anche per le sue stagioni e i suoi episodi".
- Il primario ripete la scelta ("Completa i dati" / "Riscrivi tutto", icona `refreshCw`). Via `refreshStart`.
- Dopo l'avvio come oggi: "Aggiornamento avviato", bump dopo `refreshReloadDelay`, finestra chiusa. Niente "In corso… / Fatto" (Jellyfin non manda `DateLastRefreshed`).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('il pulsante ripete la scelta', (t) async {
  // aperta → primario 'Completa i dati'; tap riquadro 'Riscrivi tutto' → primario 'Riscrivi tutto'
});
testWidgets('serie: avviso con stagioni ed episodi', (t) async {
  // testItem(kind: series, childCount: 2, recursiveCount: 16) → 'Vale anche per le sue 2 stagioni e 16 episodi';
  // un film → nessun avviso
});
testWidgets('Anche le immagini solo con Riscrivi tutto', (t) async { /* switch onChanged null con Completa i dati */ });
```

Gli altri test del file passano a `item:`, e i tap su "Aggiorna" / "Sostituisci tutti i metadati" diventano "Completa i dati" / "Riscrivi tutto".

- [ ] **Step 2:** `flutter test test/features/item_edit/refresh_metadata_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando e `flutter test test/features/detail/item_actions_menu_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): Aggiorna metadati con due riquadri e il pulsante che ripete la scelta`

### Task 8: Locandina e sfondo

**Files:**
- Modify: `app/lib/features/item_edit/images_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/item_edit/images_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 (anche `languageName`).
- Produces: `String imageCandidateLine(AppLocalizations l, RemoteImage image, String locale)`: "★ 5,3 · Italiano · 2000×3000" (voto `NumberFormat('0.0', locale)`, lingua `languageName` o `imagesNoText` "Senza testo" se vuota, parti mancanti saltate).

Regole (spec §6.7):
- Testa `imagesTitle` "Locandina e sfondo" (episodio: `imagesTitleEpisode` "Immagine dell'episodio", senza pastiglie), `itemContextLine` dall'`itemProvider` che la finestra legge già.
- Desktop: "Attuale" fissa a sinistra (210), a destra la riga degli strumenti (pastiglie, "Tutte le lingue", "Carica un file…") e la griglia che scorre da sola (altezza della finestra fissa, es. `min(560, altezza schermo − 200)`). Durante il caricamento, segnaposto `SkeletonBox` della forma giusta (2:3 o 16:9). Stretto: tutto in colonna.
- Toccare una candidata la segna (bordo oro 2 e spunta) **senza chiamare Jellyfin**; via il pulsante "Usa questa" sotto ogni candidata. Il piede diventa: nota `imagesConfirm(kind)` "Usare questa locandina?" / "Usare questo sfondo?" / "Usare questa immagine?" (ICU `select`), Annulla (toglie la scelta, non chiude) e primario `imagesUseThis(kind)` "Usa questa locandina" / "Usa questo sfondo" / "Usa questa immagine" che fa quello che faceva `_use`. Senza scelta il piede ha solo "Chiudi". Dopo, la griglia non si rilegge: le candidate restano (quella di prima compresa, se veniva dal provider).
- Cambiare scheda o lingue toglie la scelta. Via `imagesUse`.

- [ ] **Step 1: Test che falliscono**

```dart
test('riga della candidata', () {
  expect(imageCandidateLine(l, RemoteImage(url: 'u', provider: 'TheMovieDb', rating: 5.3, language: 'it', width: 2000, height: 3000), 'it'),
      '★ 5,3 · Italiano · 2000×3000');
  expect(imageCandidateLine(l, RemoteImage(url: 'u', provider: 'TheMovieDb'), 'it'), 'Senza testo');
});
testWidgets('niente cambia prima della conferma', (t) async {
  // tap candidata A, poi B → editApi.calls senza 'downloadImage'; find.text('Usare questa locandina?');
  // tap 'Usa questa locandina' → una sola downloadImage con l'url di B, snackbar 'Immagine aggiornata'
});
testWidgets('Esc con una candidata segnata chiude senza cambiare', (t) async { /* nessuna downloadImage */ });
testWidgets('episodio: Immagine dell\'episodio e niente pastiglie', (t) async { /* … */ });
```

I test "Usa come locandina/sfondo" e "doppio clic" passano da tap su candidata + primario. (`RemoteImage` vuole anche `provider:`.)

- [ ] **Step 2:** `flutter test test/features/item_edit/images_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando e `flutter test test/features/detail/item_actions_menu_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): Locandina e sfondo con l'attuale fissa e la conferma prima di cambiare`

### Task 9: Info tecniche

**Files:**
- Modify: `app/lib/features/detail/media_info_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/media_info_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 (`codecLabel`, `channelsLabel`, `languageName`, `resolutionLabel`).

Regole (spec §6.9):
- Testa `WfDialogHeader(title: 'Info tecniche', subtitle: itemContextLine, leading: DialogItemPoster)`; `compactTitle`.
- Più versioni: una pastiglia per versione (`ChoiceChip`, nome o id) e si mostra quella scelta; una sola: niente pastiglie.
- Quattro gruppi con icona oro e titolo Inter 12,5 w600 `creamMuted`: File (`file`), Video (`monitor`), `mediaInfoAudioCount(n)` "Audio · {n}" (`audioLines`), `mediaInfoSubtitlesCount(n)` "Sottotitoli · {n}" (`captions`); gruppi vuoti saltati.
  - File: per l'admin e non in TV il nome del file con "Copia" (`Clipboard.setData`, snackbar `mediaInfoCopied` "Nome del file copiato"); poi riquadri Formato (contenitore in maiuscolo), Dimensione, Durata, Bitrate (decimali con `NumberFormat` della lingua: "2,4 GB", "6,2 Mbps").
  - Video: "HEVC · 4K (3840×2160) · HDR10 · 23,976 fps" (`fps` con `NumberFormat('0.###', locale)`).
  - Audio: "{lingua} · {codec} {canali}" ("Italiano · E-AC-3 5.1") e la targhetta "Predefinita".
  - Sottotitoli: "{lingua} · {codec}" e la targhetta `mediaInfoExternal` "File esterno" / `mediaInfoEmbedded` "Dentro il video" (+ "Forzati").
- Errore della lettura (`info.hasError`): `mediaInfoError` "Non riesco a leggere le info del file" e `WfButton.secondary` "Riprova" (`ref.invalidate(itemMediaInfoProvider(item.id))`). Nessuna versione: `mediaInfoUnavailable` come oggi.
- Piede: solo "Chiudi" (`WfDialogFooter` senza Annulla). TV: "Chiudi" con `autofocus`; Su/Giù scorrono il corpo di 80 px (`Shortcuts`/`CallbackShortcuts` sul corpo, controller dello scroll); niente nome del file.
- Via `mediaInfoContainer` "Contenitore" → `mediaInfoFormat` "Formato"; le etichette `mediaInfoVideo/Audio/Subtitles/File` restano solo se usate.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('quattro gruppi con i valori leggibili', (t) async {
  // versione con hevc 3840×2160 HDR10 23.976, audio ita eac3 6 canali predefinita, sub ita subrip esterno:
  // find.text('Audio · 1'), find.text('Sottotitoli · 1'), find.textContaining('HEVC · 4K (3840×2160)'),
  // find.textContaining('23,976 fps'), find.text('Italiano · E-AC-3 5.1'), find.text('File esterno')
});
testWidgets('errore: frase e Riprova che rilegge', (t) async {
  // mediaInfo lancia → 'Non riesco a leggere le info del file'; tap 'Riprova' → api chiamata due volte
});
testWidgets('due versioni: una pastiglia per versione', (t) async { /* tap sulla seconda → i suoi valori */ });
testWidgets('TV: niente nome del file, focus su Chiudi, Giù scorre', (t) async {
  // tv: true, Size(960, 540), admin: find.text(<nome file>) findsNothing; Chiudi hasFocus;
  // sendKeyEvent(arrowDown) → ScrollController.offset > 0 (con contenuto più alto della finestra)
});
```

Aggiorna i test esistenti (etichette ripetute → gruppi; "errore: informazioni non disponibili" → la frase nuova con Riprova).

- [ ] **Step 2:** `flutter test test/features/detail/media_info_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test e `flutter test test/features/detail` → PASS.
- [ ] **Step 5: Commit** `feat(app): Info tecniche a gruppi, codec leggibili e Riprova`

### Task 10: Sottotitoli

**Files:**
- Modify: `app/lib/features/subtitles/subtitles_dialog.dart`, `app/lib/features/subtitles/subtitles_controller.dart`, `app/lib/features/detail/item_actions_menu.dart`, `app/lib/features/player/player_screen.dart` (~`:1320`), `app/lib/features/reports/reports_banner.dart` (scorciatoia), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/subtitles/subtitles_dialog_test.dart`, `app/test/features/subtitles/subtitles_controller_test.dart`

**Interfaces:**
- Consumes: Task 1 (`itemContextLine`, `codecLabel`, `languageName`).
- Produces:
  - `showSubtitlesDialog(context, {required String itemId, required String title, VoidCallback? onTrackAdded})`: firma invariata, ma `title` è la riga sotto il titolo: il menu passa `itemContextLine(l, item)`, il player `itemContextLine(l, view.item!)` (o `''` senza item), il riquadro admin `reportTitleLine(...)` come oggi.
  - `SubtitlesController.searchOnOpen() -> Future<void>`: aspetta `languagePreferencesProvider.future` (al massimo 2 s, un errore vale "nessuna preferenza"), imposta la lingua iniziale e cerca una volta. `setLanguage(code)` dopo aver cambiato lingua rilancia `search()`.

Regole (spec §6.8):
- Testa `WfDialogHeader(title: 'Sottotitoli', subtitle: title, leading: DialogItemPoster(itemId:))`; `compactTitle`; piede solo "Chiudi"; `PopScope(canPop: !busy)` mentre cerca, scarica o carica.
- In cima "Tracce presenti" con il numero (`WfText.display(20)` + conteggio): riga "{lingua}" (w600) e sotto "{codec} · file esterno" / "{codec} · dentro il video" (`subtitlesExternal` → "file esterno", `subtitlesEmbedded` → "dentro il video"). Per l'admin: le esterne hanno "Elimina…", quelle nel video `subtitlesCannotDelete` "Non si può eliminare" in `creamMuted`. Conferma `subtitlesDeleteTrackTitle(language, codec)` "Eliminare i sottotitoli {language} ({codec}, file esterno)?" (via `subtitlesDeleteTitle`).
- Ricerca: il dialogo chiama `searchOnOpen()` in `initState`; la lingua è un `DropdownButtonFormField` con `labelText` "Lingua" (tema della fase 1); titolo "Cerca" con il conteggio dei risultati. Righe: nome della release, "{fonte} · {codecLabel} · ★ 7,0 · 120 download" (voto con `NumberFormat('0.0', locale)`), "Sincronizzato col file" in verde; "Scarica" `WfButton.primary` solo sul sincronizzato, gli altri `secondary` (come oggi). Via il pulsante "Cerca" (la ricerca parte da sola).
- "Carica un file": riquadro proprio (`surfaceHigh`, bordo, raggio 8; a destra largo 270 sul desktop, sotto nello stretto) con titolo, `subtitlesUploadHint(language)` "Hai già un .srt o un .ass? Lo aggiungo in {language}.", le caselle "Forzati" (`subtitlesForcedHint` "Solo cartelli e battute in altre lingue") e "Per non udenti" (`subtitlesHearingImpairedHint` "Con rumori e nomi di chi parla") e `WfButton.secondary` `subtitlesUpload` "Scegli il file…" (`upload`).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('la ricerca parte all\'apertura e riparte se cambi lingua', (t) async {
  // FakeSubtitlesApi.calls: dopo l'apertura una sola 'search m1 ita -'; scegli 'English' → poi 'search m1 eng -'
});
testWidgets('la preferenza che arriva dopo vale per la prima ricerca', (t) async {
  // languagePreferencesProvider risolto dopo 300 ms con subtitleLanguage 'eng' → una sola ricerca, con 'eng'
});
testWidgets('le tracce si leggono e la conferma nomina la traccia', (t) async {
  // admin, sub ita subrip esterno + eng pgssub nel file → 'Italiano', 'SRT · file esterno',
  // 'PGS · dentro il video', 'Non si può eliminare'; tap 'Elimina…' →
  // find.text('Eliminare i sottotitoli Italiano (SRT, file esterno)?')
});
testWidgets('Forzati e Per non udenti stanno nel riquadro del caricamento', (t) async {
  // find.descendant(of: <riquadro 'Carica un file'>, matching: find.text('Forzati')) findsOneWidget
});
testWidgets('dal menu la testa ha serie ed episodio', (t) async {
  // item_actions_menu_test: episodio di "L'Istituto" → "Sottotitoli…" → find.text("L'Istituto · S1:E4 La scatola")
});
```

Aggiorna i test esistenti: niente tap su "Cerca" (parte da sola), "Carica file…" → "Scegli il file…", "esterno"/"nel file" → i testi nuovi; il test della rotella durante la ricerca usa la ricerca dell'apertura.

- [ ] **Step 2:** `flutter test test/features/subtitles` → FAIL.
- [ ] **Step 3:** implementa; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/subtitles test/features/detail test/features/player test/features/reports` → PASS.
- [ ] **Step 5: Commit** `feat(app): Sottotitoli con la ricerca all'apertura, tracce leggibili e caricamento a parte`

### Task 11: Checklist e verifica completa

**Files:**
- Modify: `docs/RELEASING.md`, `l10n/app_it.arb`, `l10n/app_en.arb` (pulizia)

- [ ] **Step 1:** chiavi rimaste senza uso (fra `reportsBannerTitle`, `reportFixed`, `reportCannotFix`, `reportResolveConfirm`, `identifyConfirm`, `identifyConfirmNoImages`, `identifyUnlock`, `imagesUse`, `refreshStart`, `subtitlesSearch`, `subtitlesDeleteTitle`, `subtitlesDeleteMessage`, `mediaInfoContainer`, `itemActionsMenu` resta): `grep -rn "l\.<chiave>\b" lib` e togli quelle a zero da it ed en.
- [ ] **Step 2:** in `docs/RELEASING.md`, checklist della 0.42.0, una riga: "Revisione finale, fase 4 (app 0.42.0, da admin su PC, poi finestra sotto 1024 px; TV Segnala e Info): menu ⋯ con i gruppi La tua visione / Controlla e segnala / Admin, icone e puntini, in fondo allo schermo si apre sopra; Segnala con Su cosa? e Che problema c'è?, 'Scegli che problema c'è' e 'Aggiorna la segnalazione' su un doppione; elenco delle segnalazioni come la Cabina e 'Segnalazione chiusa'; Modifica metadati con 'Bloccato', data gg/mm/aaaa sbagliata che porta al campo, 'N modifiche' e 'Buttare le modifiche?'; Identifica coi biglietti Ora e Dopo, 'Attuale' e lo sblocco spento; Aggiorna metadati col pulsante che ripete la scelta; Locandina che non cambia finché non premi 'Usa questa locandina'; Sottotitoli che cercano da soli; Info tecniche a gruppi con Riprova; TV: Segnala e Info tecniche come finestra, menu con righe alte."
- [ ] **Step 3: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta).
- [ ] **Step 4: Commit** `docs: checklist della fase 4 della revisione finale`

## Domande aperte e cose lasciate fuori

- **Lampada verde e "Chiuse di recente" (§6.3):** `ReportsApi.all()` (`core/reports/reports_api.dart:75`) dà solo le aperte; senza plugin non ci sono chiuse da mostrare. Tutte le righe hanno la lampada oro.
- **Regista e durata nei risultati e nel biglietto "Dopo" (§6.5):** la ricerca remota di Jellyfin (`RemoteSearchResult`) non li dà; "Dopo" mostra nome, anno e immagini.
- **"Attuale" tra le candidate della Locandina:** Jellyfin non dice quale candidata remota è l'immagine attuale; resta solo l'"Attuale" fissa a sinistra.
- **Lingue nelle righe:** `languageName` dà i nomi nella lingua dell'app ("Inglese"), dalla stessa tabella del pannello tracce del player (fase 2).
- **Focus in TV:** §3.5 dice bordo crema 2 e scala 1,06; oggi `tvFocusColor` è oro e `tvFocusScale` 1,05 e la fase 1 non li cambia. Il menu usa `TvFocusBorder`, quindi segue quello che c'è.
- **Lingua iniziale dei sottotitoli:** "nella lingua dell'app" è letta come oggi: la preferenza dei sottotitoli dell'utente, sennò quella di riserva del controller.

## Prova a mano (dopo la review finale)

Plugin invariato. Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`), da admin: il ⋯ di un film, di una serie e di un episodio (gruppi, icone, puntini; il ⋯ di un episodio in fondo alla pagina si apre sopra); Segnala un episodio di "L'Istituto" (senza tipo, poi un doppione); su una scheda con segnalazioni, "Segna come sistemato…" e l'avviso; Modifica metadati di "The Wrestler" (data "17/13/2008", conteggio, Esc con modifiche); Identifica (Ora/Dopo, sblocco spento: non applicare su un titolo vero se non serve); Aggiorna metadati "Completa i dati" su una serie; Locandina: scegli e poi Annulla; Sottotitoli di un episodio (ricerca all'apertura; non eliminare tracce vere); Info tecniche ("Copia"). Poi la finestra sotto 1024 px (piede fisso in basso). APK sulla Fire Stick (comando in CLAUDE.md): ⋯ sulla scheda di "2012" (righe alte, focus), Segnala con il D-pad fino al piede senza tastiera, Info tecniche (focus su Chiudi, Giù scorre).
