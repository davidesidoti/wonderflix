# Revisione finale, fase 3: scheda del titolo — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La scheda di film e serie parla come la Home (riga oro, titolo grande, una riga di dati, azioni in ordine fisso), gli episodi si segnano come visti uno per uno e per stagione, il prossimo episodio è un biglietto, e il pannello del voto, la Persona, la Saga e la pagina TMDB si allineano.

**Architecture:** Quasi tutto sta in `features/detail/` (testata, episodi) e `features/ratings/` (riga dei voti, pannello). Pezzi nuovi piccoli: `ui/expandable_text.dart` (trama con "Altro"), un widget per i voti della stagione, un parametro `gold` su `WfButton.secondary`. La lista degli episodi passa da `Column` a sliver. Nessuna lettura nuova all'apertura: il campo `ChildCount` delle stagioni viaggia nella richiesta di oggi.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, intl, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` (§3.1, §5 tutta, §10–§12). Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/scheda.html`. Piano della fase 1 (già eseguito prima di questo): `docs/superpowers/plans/2026-11-16-revisione-finale-fase-1-comuni.md`.

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Prima di `analyze`/`test`: `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\`, `flutter pub get`, `flutter gen-l10n`.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`), anche con `withValues(alpha:)`. Titoli con `WfText.display(n)`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`, chiavi nuove raccolte vicino alle altre `detail*` / `rating*`. Niente etichette in maiuscolo. Episodi sempre con `episodeCode` ("S1:E4"); generi sempre con `genreLabel`, al massimo 2 nelle righe dei dati.
- Fuori dalla TV il comportamento TV non cambia, e viceversa. Il layout stretto della scheda è `detailCompact(context)` (= `compact && !tv`).
- Confini con le altre fasi: lo stile e i gruppi del menu ⋯ (`item_actions_menu.dart`) sono della fase 4: qui non si tocca quel file, si usano solo le `extra` di `ItemActionsButton`. Il pannello "Consiglia a…" è della fase 5. Dalla fase 1 ci sono già: `PanelHeader` nel pannello voto, il commento in `TvTextFieldFrame`, la Persona con `compact && !tv`, i generi nuovi in `genre_labels.dart`.
- Nessuna lettura in più all'apertura della scheda. Nessun cambio al plugin.
- `dart format` solo sulle righe toccate.
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).

## Review Focus

- **Film senza regista, serie senza anno:** la riga oro dice solo "Film" / "Serie", mai "Film di " vuoto o "Serie · ". Test in Task 1.
- **Trama lunghissima aperta con "Altro" sul desktop (testata alta 560, testo ancorato in basso):** il titolo resta dentro lo schermo; la trama aperta si ferma a 10 righe. Test in Task 2.
- **Anime da 170 episodi:** si costruiscono solo gli episodi vicini allo schermo, e scorrendo si arriva all'ultimo. Test in Task 5.
- **"Segna la stagione come vista" che fallisce:** la voce torna com'era, compare l'errore, gli episodi non cambiano. Test in Task 6.
- **TV con i voti della stagione:** Giù dalle schede delle stagioni va al primo episodio, non alla riga dei voti (che in TV non prende il focus). Test in Task 9.

---

### Task 1: Riga oro, titolo grande, una riga di dati

**Files:**
- Modify: `app/lib/features/detail/detail_header.dart` (`DetailHeader.build` `:284-299`, `HeaderTitle`, `MetaLine`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/movie_detail_test.dart`, `app/test/features/detail/series_detail_test.dart`

**Interfaces:**
- Produces:
  - `String? detailKicker(JellyfinItem item, AppLocalizations l)` in `detail_header.dart`: film → `l.detailKickerMovie(director)` ("Film di {director}", il primo `people` con `type == 'Director'`), senza regista `l.requestsKindMovie` ("Film"); serie → `l.detailKickerSeries('$year')` ("Serie · {year}", `productionYear`), senza anno `l.requestsKindSeries` ("Serie"); altro (episodio aperto da solo) → `null`.
  - `class DetailKicker extends StatelessWidget { const DetailKicker(this.text); }`: testo `WfColors.gold`, 12,5, w600, come la riga di `hero_carousel.dart:599-606`. La usano anche i Task 12 (TMDB).
  - `MetaLine({required JellyfinItem item, bool genres = false})`: con `genres: true` aggiunge alla parte di testo i generi `{...item.genres.map(genreLabel)}.take(2)` (come `heroMeta`), nello stesso `Text` "anno · durata/stagioni · generi". Il voto diventa `formatRatingAverage(rating, l.localeName)` ("7,5"). `card_preview.dart` resta senza generi (parametro di serie `false`).
  - `TextStyle headerTitleStyle(BuildContext context)`: `WfText.display(96)` sul desktop, `48` nello stretto, `72` in TV. `HeaderTitle` lo usa; il nome va in una `SizedBox(height: 80)` con `maxLines: 1` in TV, `maxLines: 2` altrove. Logo: alto 96 sul desktop, 72 nello stretto, 80 in TV (oggi 120 ovunque). La pagina della Saga usa `HeaderTitle` e prende le stesse misure.
- Chiavi nuove: `detailKickerMovie` "Film di {director}" / "Directed by {director}"; `detailKickerSeries` "Serie · {year}" / "Series · {year}".

In `DetailHeader.build`: la `DetailKicker` sopra `HeaderTitle` (dentro lo `StaggerItem` 0), `MetaLine(item: item, genres: true)`, e via la riga dei generi in inglese (`:290-299`). `detailEntranceCount` resta 9 (l'indice 2 lo prende la trama nel Task 2).

- [ ] **Step 1: Test che falliscono**

```dart
// movie_detail_test.dart (m1 ha il regista Denis Villeneuve)
testWidgets('riga oro col regista e una sola riga di dati', (tester) async {
  api.itemsById['m1'] = testItem(id: 'm1', name: 'Dune: Parte Due', rating: 7.5,
      genres: const ['Drama', 'Romance', 'Crime'],
      people: [{'Id': 'p8', 'Name': 'Denis Villeneuve', 'Type': 'Director'}]);
  await pumpDetail(tester);
  expect(find.text('Film di Denis Villeneuve'), findsOneWidget);
  expect(find.text('2024 · 2h · Dramma · Romantico'), findsOneWidget);
  expect(find.text('7,5'), findsOneWidget);
  expect(find.text('Drama · Romance · Crime'), findsNothing);
  final title = tester.widget<Text>(find.text('DUNE: PARTE DUE'));
  expect(title.style?.fontSize, 96);
});
testWidgets('film senza regista: la riga oro dice solo Film', (tester) async {
  api.itemsById['m1'] = testItem(id: 'm1', name: 'Dune: Parte Due');
  await pumpDetail(tester);
  expect(find.text('Film'), findsOneWidget);
  expect(find.textContaining('Film di'), findsNothing);
});
// series_detail_test.dart
testWidgets('serie: riga oro con l\'anno', (tester) async {
  await pumpSeries(tester);
  expect(find.text('Serie · 2024'), findsOneWidget);
});
testWidgets('serie senza anno: la riga oro dice solo Serie', (tester) async {
  api.itemsById['s1'] = testItem(id: 's1', name: 'The Last of Us',
      kind: ItemKind.series, year: null, childCount: 2);
  await pumpSeries(tester);
  expect(find.text('Serie'), findsOneWidget);
  expect(find.textContaining('Serie ·'), findsNothing);
});
```

- [ ] **Step 2:** `flutter test test/features/detail/movie_detail_test.dart test/features/detail/series_detail_test.dart` → FAIL.
- [ ] **Step 3:** implementa `detailKicker`, `DetailKicker`, `MetaLine(genres:)`, `headerTitleStyle` e le misure del logo; aggiungi le due chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS; poi `flutter test test/features/detail test/features/collections test/ui` (la saga e l'anteprima usano `HeaderTitle`/`MetaLine`; un test che cercava "8.4" passa a "8,4") → PASS.
- [ ] **Step 5: Commit** `feat(app): scheda con la riga oro, il titolo grande e i generi in italiano`

### Task 2: Trama di 3 righe con "Altro"

**Files:**
- Create: `app/lib/ui/expandable_text.dart`
- Modify: `app/lib/features/detail/detail_header.dart` (trama, `:300-314`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/ui/expandable_text_test.dart` (nuovo), `app/test/features/detail/movie_detail_test.dart`

**Interfaces:**
- Produces: `class ExpandableText extends StatefulWidget { const ExpandableText(this.text, {super.key, required int maxLines, int? expandedMaxLines, TextStyle? style, bool tvFocusable = false}); }`.
  - Chiuso: `maxLines` righe con ellissi e, solo se il testo non ci sta, sotto il link "Altro" (`l.detailShowMore`, oro 12,5 w600, nessuna sottolineatura). Il controllo: `LayoutBuilder` + `TextPainter(maxLines:, textScaler: MediaQuery.textScalerOf(context)).didExceedMaxLines`.
  - Aperto (tocco su "Altro"): `expandedMaxLines` righe (`null` = tutte), "Altro" sparisce. Non si richiude.
  - `tvFocusable: true` (solo in TV): tutto il testo sta in un `TvFocusable(onActivate: apri)`; "Altro" resta come scritta. La usa la Persona (Task 11).
- Chiave nuova: `detailShowMore` "Altro" / "More".

Nella testata: desktop e stretto `ExpandableText(overview, maxLines: 3, expandedMaxLines: detailCompact(context) ? null : 10, style: TextStyle(height: 1.45))` dentro lo `StaggerItem` 2 (prima 3); in TV un `Text` di 2 righe con ellissi, senza "Altro" (bozza).

- [ ] **Step 1: Test che falliscono**

```dart
// expandable_text_test.dart
testWidgets('testo lungo: tre righe e Altro, che lo apre', (t) async {
  final long = 'Una trama lunga che va su più righe. ' * 20;
  await pumpApp(t, Scaffold(body: SizedBox(width: 400,
      child: ExpandableText(long, maxLines: 3))));
  expect(t.widget<Text>(find.text(long)).maxLines, 3);
  await t.tap(find.text('Altro'));
  await t.pump();
  expect(t.widget<Text>(find.text(long)).maxLines, isNull);
  expect(find.text('Altro'), findsNothing);
});
testWidgets('testo corto: niente Altro', (t) async {
  await pumpApp(t, const Scaffold(body: ExpandableText('Breve.', maxLines: 3)));
  expect(find.text('Altro'), findsNothing);
});
// movie_detail_test.dart
testWidgets('trama lunghissima aperta: il titolo resta nello schermo', (tester) async {
  // m1 con overview: 'Una trama lunga che va su più righe. ' * 60, superficie 1280×800;
  // tap su 'Altro' → maxLines della trama == 10 e
  // tester.getTopLeft(find.text('DUNE: PARTE DUE')).dy >= 0
});
```

(`pumpDetail` del file accetta già `extra`; per la superficie 1280×800 aggiungi un parametro `surfaceSize` passato a `pumpApp`.)

- [ ] **Step 2:** `flutter test test/ui/expandable_text_test.dart test/features/detail/movie_detail_test.dart` → FAIL.
- [ ] **Step 3:** crea `ExpandableText`, aggiungi la chiave, usala nella testata.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/detail/detail_tv_test.dart` (la trama in TV resta di 2 righe nella prima schermata) → PASS.
- [ ] **Step 5: Commit** `feat(app): la trama della scheda si apre con Altro`

### Task 3: Azioni della testata in ordine fisso

**Files:**
- Modify: `app/lib/features/detail/detail_header.dart` (`build` `:217-466`, `_ActionIcon`), `app/lib/features/detail/primary_action.dart` (`primaryActionLabel`), `app/lib/features/library/item_labels.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/movie_detail_test.dart`, `app/test/features/detail/series_detail_test.dart`, `app/test/features/detail/detail_tv_test.dart`, `app/test/features/detail/detail_recommend_test.dart`, `app/test/features/detail/primary_action_test.dart`

**Interfaces:**
- Produces:
  - `String shortDuration(AppLocalizations l, Duration d)` in `item_labels.dart`: sotto l'ora `l.ticketMinutes(minuti arrotondati per eccesso)` ("18 min"), da un'ora in su `formatRuntime(d)` ("1h 15m"). La usano i Task 7 e 8.
  - `Future<void> runUserDataAction(BuildContext context, Future<void> Function() action)` in `detail_header.dart`: l'attuale `_toggle` reso pubblico (errore → SnackBar con `describeError`). Lo usano i Task 6 e 7.
  - `primaryActionLabel`: `ResumeAction` di un episodio → `l.actionResumeEpisode(code)` ("Riprendi S1:E4"), senza l'ora. Film invariato ("Riprendi da 23:14"). Vale anche nella barra in alto.
  - `_LabeledAction({required Widget button, required String label, bool selected = false})`: `Column(button, SizedBox(height: 4), Text(label))`, testo 11 (10,5 in TV), `creamMuted`, oro se `selected`. Il ⋯ con la parola è `_LabeledAction(button: ItemActionsButton(...), label: l.detailActionMore)`: `ItemActionsButton` non cambia.
- Chiavi nuove: `detailActionWatched` "Visto" / "Watched"; `detailActionTogether` "Insieme" / "Together"; `detailActionRecommend` "Consiglia" / "Recommend"; `detailActionMore` "Altro" / "More".

Ordine (spec §5.1), le azioni che non ci sono si saltano:
- **Desktop** (una `Wrap`): primario · ↺ (`_ActionIcon`, tooltip "Ricomincia", solo con `ResumeAction`) · "Guarda insieme" (`WfButton.secondary`) · "Trailer" (`WfButton.secondary`) · ♥ · ✓ · ★ Vota (solo film) · Consiglia a… (`_ActionIcon` `LucideIcons.send`, tooltip `l.recommendButton`) · ⋯ con `extra: [?resume, ?nextUp, ?richiediStagioni]` (`label: l.requestsMoreSeasons`). Spariscono i due `WfButton.secondary` dopo il ⋯ (`:447-460`) e il "Ricomincia" con la parola.
- **Vota sul desktop:** `ratingsOn` vale anche fuori dalla TV per i film (`target != null && (tv || (!compact && item.kind == ItemKind.movie))`); le serie fuori dalla TV votano dalla riga della stagione (Task 9).
- **Sotto il primario**, con `ResumeAction` e durata nota, fuori dalla TV: `Row(SizedBox(width: 120, height: 3, child: ProgressStrip(...)), SizedBox(width: 8), Text(l.detailRemaining(shortDuration(l, durata − posizione))))`, `creamMuted` 12; nello stretto centrata.
- **Stretto:** primario a tutta larghezza, la riga dei dati e sotto una `Row` di `Expanded(_LabeledAction)`: La mia lista (`l.navMyList`), Visto, Trailer, Insieme, Consiglia, Altro. Il ⋯ ha `extra: [?resume, ?nextUp, ?ricomincia (l.actionRestart), ?richiediStagioni]`; Consiglia a… non è più nel ⋯.
- **TV:** primario (autofocus, come oggi) · Trailer (`WfButton.secondary`) · poi `_LabeledAction` per Ricomincia, La mia lista, Visto, Vota, Consiglia a… (`l.recommendButton`), Altro. "Guarda insieme" e "Richiedi stagioni" restano fuori dalla TV come oggi.

- [ ] **Step 1: Test che falliscono**

```dart
// movie_detail_test.dart: m1 con punto di ripresa, trailer, regista;
// extra: watch party che può creare (come 'Guarda insieme: crea il gruppo…'),
// ...socialTestOverrides(social, features: SocialFeatures(friends: true, ratings: true, recommendations: true))
// con un amico (come detail_recommend_test.dart).
testWidgets('azioni in ordine fisso e ⋯ per ultimo', (tester) async {
  await pumpDetail(tester, extra: [...]);
  final xs = [
    find.text('Riprendi da 23:14'), find.byTooltip('Ricomincia'),
    find.text('Guarda insieme'), find.text('Trailer'),
    find.byTooltip('Aggiungi a La mia lista'), find.byTooltip('Segna come visto'),
    find.byTooltip('Vota'), find.byTooltip('Consiglia a…'), find.byTooltip('Altre azioni'),
  ].map((f) => tester.getCenter(f).dx).toList();
  for (var i = 1; i < xs.length; i++) { expect(xs[i], greaterThan(xs[i - 1])); }
  expect(find.text('Ricomincia'), findsNothing); // è un'icona
  expect(find.text('rimangono 1h 36m'), findsOneWidget); // 120 min − 23:14
});
// series_detail_test.dart
testWidgets('serie: il primario dice Riprendi S1:E4 e Richiedi stagioni è nel ⋯', (tester) async {
  // seasonsToRequestProvider sovrascritto a true per s1 con tmdbId;
  // find.text('Riprendi S1:E4') findsOneWidget; find.text('Richiedi stagioni') findsNothing;
  // tap byTooltip('Altre azioni') (il primo, quello della testata) → find.text('Richiedi stagioni') findsOneWidget
  // find.text('rimangono 22 min') findsOneWidget (45 min − 23:14 → 21m46s → 22)
});
testWidgets('stretto: sei azioni con la parola, Ricomincia nel ⋯', (tester) async {
  // surfaceSize 390×780: find.text('La mia lista'), 'Visto', 'Trailer', 'Insieme', 'Consiglia', 'Altro' findsOneWidget;
  // find.byTooltip('Ricomincia') findsNothing; tap sull'icona di Altro → find.text('Ricomincia') findsOneWidget
});
// detail_tv_test.dart
testWidgets('TV: le icone hanno il nome sotto', (tester) async {
  // pumpDetail(tester, 'm1', surfaceSize: Size(960, 540)): find.text('La mia lista'), 'Visto', 'Altro' findsOneWidget;
  // getTopLeft(find.text('Visto')).dy > getBottomLeft(find.byTooltip('Segna come visto')).dy
});
```

Aggiorna i test che cercano "Riprendi S1:E4 · 23:14" (`series_detail_test`, `detail_tv_test`, `primary_action_test`) a "Riprendi S1:E4", e `detail_recommend_test` a `find.byTooltip('Consiglia a…')`.

- [ ] **Step 2:** `flutter test test/features/detail` → FAIL sui casi nuovi.
- [ ] **Step 3:** implementa ordine, `_LabeledAction`, `shortDuration`, `runUserDataAction`, l'etichetta del primario; aggiungi le chiavi.
- [ ] **Step 4:** `flutter test test/features/detail test/features/collections test/features/home` → PASS (in TV: `'dati e pulsanti nella prima schermata'` deve restare verde a 960×540).
- [ ] **Step 5: Commit** `feat(app): azioni della scheda in ordine fisso, con il nome sul telefono e in TV`

### Task 4: Voti degli amici col pulsante del kit, "Fa parte di" come Simili

**Files:**
- Modify: `app/lib/ui/wf_buttons.dart` (`WfButton.secondary`), `app/lib/features/ratings/friend_ratings_row.dart` (`:67-77`), `app/lib/features/collections/collection_rows.dart` (`:61`, `:71`)
- Test: `app/test/ui/wf_buttons_test.dart` (aggiungi o crea), `app/test/features/ratings/friend_ratings_row_test.dart`, `app/test/features/collections/collection_rows_test.dart`

**Interfaces:**
- Produces: `WfButton.secondary({..., bool gold = false})`: con `gold` testo, icona e bordo `WfColors.gold`. Lo usa il Task 9.
- `FriendRatingsRow.trailing`: `WfButton.secondary(small: true, key: Key('friend-ratings-action'), label: mine == null ? l.ratingVote : l.ratingMine(mine.score), icon: mine == null ? LucideIcons.star : LucideIcons.pencil, gold: mine != null, onPressed: ...)`.
- `_SagaRow`: `height: rowPosterSize(context).rowHeight`, `width: rowPosterSize(context).width`.
- L'ordine Voti degli amici · Cast · Fa parte di · Simili c'è già (`movie_detail_view.dart:63-75`); il cast ha già foto, personaggio e sagoma (`detail_rows.dart`): niente da fare.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('il mio voto è un pulsante del kit in oro', (tester) async {
  // riga con mine: MyRating(score: 8)
  final b = find.byKey(const Key('friend-ratings-action'));
  expect(find.descendant(of: b, matching: find.byType(OutlinedButton)), findsOneWidget);
  expect(find.text('Il tuo voto: 8'), findsOneWidget);
  final style = tester.widget<OutlinedButton>(find.descendant(of: b, matching: find.byType(OutlinedButton))).style!;
  expect(style.foregroundColor!.resolve({}), WfColors.gold);
});
testWidgets('Fa parte di ha la misura di Simili', (tester) async {
  // collection_rows_test: la card della saga è larga rowPosterSize(context).width (160 a 1440, 112 a 390×780)
});
```

- [ ] **Step 2:** `flutter test test/ui test/features/ratings/friend_ratings_row_test.dart test/features/collections/collection_rows_test.dart` → FAIL.
- [ ] **Step 3:** aggiungi `gold`, cambia il pulsante e le misure della saga.
- [ ] **Step 4:** stessi test → PASS (un test che cercava `TextButton` nella riga si aggiorna).
- [ ] **Step 5: Commit** `fix(app): voti degli amici col pulsante del kit e saga della misura di Simili`

### Task 5: La serie a pezzi (sliver)

**Files:**
- Modify: `app/lib/features/detail/series_detail_view.dart` (`build` `:96-197`, `_EpisodeList` `:291-361`)
- Test: `app/test/features/detail/series_detail_test.dart`

**Interfaces:**
- Produces: la pagina della serie è una `CustomScrollView(controller: widget.controller)` dentro lo `StaggerGroup` di oggi:
  - `SliverToBoxAdapter` per testata, `ReportsBanner`, il blocco delle stagioni (scheletro / errore / riga delle schede);
  - `_EpisodeSliver({seriesId, seasonId, highlightId, animate})`: `SliverList.builder` di `EpisodeTile` con lo `StaggerGroup(key: ValueKey('episodes-$seasonId'), play: animate, count: min(n, 10))` di oggi intorno; caricamento, errore e vuoto come `SliverToBoxAdapter` (lo stesso `EpisodeListSkeleton`, `ErrorView`, `detailNoEpisodes`);
  - Cast e Simili in `SliverToBoxAdapter`, poi `SliverPadding(bottom: 40)`.
- La dissolvenza `WfSwitcher` al cambio di stagione sparisce (non vale per uno sliver); resta l'entrata scaglionata. `ShellHeaderPublisher`, `barTitleVisible` e lo sfondo che segue `controller` non cambiano.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('170 episodi: si costruiscono solo quelli vicini', (tester) async {
  api.episodesBySeason['se1'] = [for (var i = 1; i <= 170; i++) ep('x$i', 'se1', 1, i)];
  await pumpSeries(tester);
  expect(find.byType(EpisodeTile, skipOffstage: false).evaluate().length, lessThan(40));
  await tester.scrollUntilVisible(find.text('Episodio 170'), 600,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('Episodio 170'), findsOneWidget);
});
```

(Dal Task 7 il nome dell'episodio è senza "170. ": qui cerca `find.textContaining('Episodio 170')`, che regge prima e dopo.)

- [ ] **Step 2:** `flutter test test/features/detail/series_detail_test.dart` → FAIL.
- [ ] **Step 3:** passa a `CustomScrollView` e `_EpisodeSliver`.
- [ ] **Step 4:** `flutter test test/features/detail test/features/ratings` → PASS (`'gli episodi entrano scaglionati solo cambiando stagione'` e i test TV di Giù restano verdi).
- [ ] **Step 5: Commit** `fix(app): gli episodi della serie si costruiscono a pezzi`

### Task 6: Stagioni in una riga che scorre e ⋯ della stagione

**Files:**
- Modify: `app/lib/core/jellyfin/library_api.dart` (`seasons`, `:106-108`), `app/lib/features/detail/series_detail_view.dart` (`_SeasonTabs` `:224-285`, il ⋯ della stagione `:166-175`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/series_detail_test.dart`, `app/test/core/jellyfin/library_api_test.dart` (se c'è un test di `seasons`, aggiungi il campo)

**Interfaces:**
- Consumes: `runUserDataAction` (Task 3); `UserDataOverrides.togglePlayed` (`features/library/user_data.dart:114`, `POST`/`DELETE /UserPlayedItems/{id}`).
- Produces:
  - `seasons()` chiede anche `ChildCount`: `'fields': '${cardImageParams['fields']},ChildCount'` (stessa richiesta, nessuna lettura nuova).
  - Scheda della stagione: "Stagione 1" (w600, oro se scelta) e, con `childCount`, `' · ${l.detailEpisodes(n)}'` in `creamMuted` 12,5 ("Stagione 1 · 8 episodi"). Le schede stanno in un `SingleChildScrollView(scrollDirection: Axis.horizontal)` con dentro `SlidingUnderline` e una `Row` (non più `Wrap`).
  - ⋯ della stagione (solo fuori dalla TV, come oggi): `ItemActionsButton(item: season, extra: [segna, ?vota])`; `segna` = `watchUserData(ref, season).played ? l.detailSeasonMarkUnwatched : l.detailSeasonMarkWatched`, che chiama `runUserDataAction(context, () async { await overrides.togglePlayed(season); ref.invalidate(episodesProvider((seriesId:, seasonId:))); })`. "Vota la stagione" lo aggiunge il Task 9.
- Chiavi nuove: `detailEpisodes` "{count, plural, =1{1 episodio} other{{count} episodi}}" / "{count, plural, =1{1 episode} other{{count} episodes}}"; `detailSeasonMarkWatched` "Segna la stagione come vista" / "Mark season as watched"; `detailSeasonMarkUnwatched` "Segna la stagione come da vedere" / "Mark season as unwatched".

> **Nota per la prova a mano (spec §11):** si usa `POST /UserPlayedItems/{seasonId}`. Se dopo averla segnata gli episodi in `UserData` (`jellyfin.db`, sola lettura) non risultano visti, si passa a un `POST` per episodio. Non scrivere adesso le due strade.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('stagioni con il numero di episodi, in una riga che scorre', (tester) async {
  api.seasonsBySeries['s1'] = [
    testItem(id: 'se1', name: 'Stagione 1', kind: ItemKind.season, index: 1, childCount: 8),
    testItem(id: 'se2', name: 'Stagione 2', kind: ItemKind.season, index: 2, childCount: 1),
  ];
  await pumpSeries(tester);
  expect(find.textContaining('8 episodi'), findsOneWidget);
  expect(find.ancestor(of: find.text('Stagione 1'), matching: find.byType(Wrap)), findsNothing);
});
testWidgets('⋯ della stagione: Segna la stagione come vista', (tester) async {
  await pumpSeries(tester);
  await tester.tap(find.byTooltip('Altre azioni').at(1)); // testata, poi stagione
  await tester.pumpAndSettle();
  await tester.tap(find.text('Segna la stagione come vista'));
  await tester.pump(); await tester.pump();
  expect(api.playedCalls, contains(('se1', true)));
  await tester.tap(find.byTooltip('Altre azioni').at(1));
  await tester.pumpAndSettle();
  expect(find.text('Segna la stagione come da vedere'), findsOneWidget);
});
testWidgets('stagione che non si segna: torna com\'era e lo dice', (tester) async {
  // api.failSetPlayed = true (aggiungilo a FakeLibraryApi se non c'è: setPlayed lancia);
  // dopo il tap: una SnackBar; riaprendo il ⋯ c'è ancora 'Segna la stagione come vista'
});
```

- [ ] **Step 2:** `flutter test test/features/detail/series_detail_test.dart` → FAIL.
- [ ] **Step 3:** campo `ChildCount`, schede scorrevoli con il conteggio, voce della stagione; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/detail test/core/jellyfin` → PASS (`'la linea oro passa sotto la stagione scelta'` resta verde).
- [ ] **Step 5: Commit** `feat(app): stagioni con gli episodi e la stagione si segna come vista`

### Task 7: Episodio con data, durata e Visto

**Files:**
- Modify: `app/lib/features/detail/series_detail_view.dart` (`EpisodeTile` `:363-482`), `l10n/app_it.arb`, `l10n/app_en.arb` (solo se servono)
- Test: `app/test/features/detail/series_detail_test.dart`, `app/test/features/detail/detail_tv_test.dart`

**Interfaces:**
- Consumes: `shortDuration`, `runUserDataAction` (Task 3), `l.detailActionWatched` "Visto".
- Produces: `EpisodeTile` (firma invariata):
  - nome dell'episodio senza "4. " davanti, w600;
  - riga dati `[episodeCode(e), data, shortDuration(l, runtime)].join(' · ')` senza le parti che mancano ("S1:E4 · 27 lug 2025 · 52 min"); data `DateFormat('d MMM y', l.localeName).format(premiereDate)` sul valore UTC così com'è (è una data di calendario: `toLocal()` la sposterebbe di un giorno);
  - trama di 2 righe (desktop); nello stretto niente trama;
  - a destra (desktop) o sotto il testo (stretto): Visto e poi ⋯. Visto = `FilterChip(avatar: Icon(LucideIcons.check, size: 16), showCheckmark: false, label: Text(l.detailActionWatched), selected: userData.played, onSelected: (_) => runUserDataAction(context, () => overrides.togglePlayed(episode)))`: i colori li dà `chipTheme` della fase 1 (scelto = oro);
  - il `WatchedBadge` dopo il ⋯ sparisce fuori dalla TV; in TV la riga resta senza Visto né ⋯ (la riga intera riproduce), con il `WatchedBadge` di oggi;
  - via il "rimangono" nella riga dati (lo dice il biglietto, Task 8).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('episodio: codice, data, durata e Visto prima del ⋯', (tester) async {
  api.episodesBySeason['se1'] = [testItem(id: 'e3', name: 'La scatola', kind: ItemKind.episode,
      seriesId: 's1', seasonId: 'se1', seasonIndex: 1, index: 3, runtimeMinutes: 52,
      premiereDate: '2025-07-27T00:00:00.0000000Z')];
  await pumpSeries(tester);
  expect(find.text('La scatola'), findsOneWidget);
  expect(find.text('S1:E3 · 27 lug 2025 · 52 min'), findsOneWidget);
  final chip = find.widgetWithText(FilterChip, 'Visto');
  final more = find.byTooltip('Altre azioni').last;
  expect(tester.getCenter(chip).dx, lessThan(tester.getCenter(more).dx));
  await tester.tap(chip);
  await tester.pump(); await tester.pump();
  expect(api.playedCalls, contains(('e3', true)));
  expect(tester.widget<FilterChip>(chip).selected, isTrue);
});
testWidgets('episodio senza data né durata: nessun punto in più', (tester) async {
  // testItem(..., index: 3, runtimeMinutes: null) senza premiereDate → find.text('S1:E3') findsOneWidget
});
// detail_tv_test.dart
testWidgets('TV: gli episodi non hanno Visto', (tester) async {
  // pumpDetail(tester, 's1', surfaceSize: Size(960, 540)) → find.byType(FilterChip) findsNothing
});
```

Aggiorna i test che cercano "3. Episodio 3" / "1. Episodio 1" a "Episodio 3" / "Episodio 1" (`series_detail_test`, `detail_tv_test`).

- [ ] **Step 2:** `flutter test test/features/detail` → FAIL.
- [ ] **Step 3:** rifai `EpisodeTile` come sopra.
- [ ] **Step 4:** `flutter test test/features/detail` → PASS.
- [ ] **Step 5: Commit** `feat(app): ogni episodio ha data, durata e il pulsante Visto`

### Task 8: Il prossimo episodio come biglietto

**Files:**
- Modify: `app/lib/features/detail/series_detail_view.dart` (`EpisodeTile`, parametro `highlighted`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/detail/series_detail_test.dart`

**Interfaces:**
- Consumes: `TicketClipper.vertical`, `TicketTearPainter.vertical` (`ui/ticket_shape.dart`); `l.ticketNext` "Prossimo"; `shortDuration` (Task 3); `ProgressStrip`.
- Produces: `EpisodeTile(highlighted: true)` (oggi solo lo sfondo `surface`, `:396`) diventa il biglietto, con `Key('next-episode-ticket')`:
  - forma `ClipPath(clipper: TicketClipper.vertical(strappo))` con fondo `WfColors.surface`, sopra un bordo `WfColors.gold` 1,5 con angoli 8 e la `TicketTearPainter.vertical(strappo)`, come `ui/ticket_card.dart:94-173`; lo strappo cade subito dopo la still (`larghezza still + 12`);
  - sulla still un ▶ in un cerchio 40 (`bg` al 60%, bordo `cream` al 50%) e la barretta di avanzamento;
  - sopra il nome "Prossimo" (`l.ticketNext`, oro, 12, w600);
  - in fondo al testo: con un punto di ripresa `l.detailNextResume(shortDuration(l, durata − posizione))` ("Riprendi · rimangono 18 min") e sotto una barretta larga 160 (nello stretto a tutta larghezza); senza, `l.actionPlay` ("Riproduci");
  - stesse azioni (Visto, ⋯) e stesso tocco (riproduce) delle altre righe; in TV stesso biglietto, senza azioni.
- Chiave nuova: `detailNextResume` "Riprendi · rimangono {time}" / "Resume · {time} left".

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('il prossimo episodio è un biglietto con Prossimo e quanto manca', (tester) async {
  await pumpSeries(tester); // e4 iniziato a 23:14 di 45 min, è il nextUp
  final ticket = find.byKey(const Key('next-episode-ticket'));
  expect(ticket, findsOneWidget);
  expect(find.descendant(of: ticket, matching: find.text('Prossimo')), findsOneWidget);
  expect(find.descendant(of: ticket, matching: find.text('Riprendi · rimangono 22 min')), findsOneWidget);
  expect(find.descendant(of: ticket, matching: find.byType(ClipPath)), findsWidgets);
  expect(find.descendant(of: ticket, matching: find.text('Episodio 4')), findsOneWidget);
});
testWidgets('prossimo non iniziato: Riproduci', (tester) async {
  // api.nextUpItems = [ep('e21', 'se2', 2, 1)], seasonId 'se2' → nel biglietto find.text('Riproduci')
});
testWidgets('stretto: il biglietto c\'è anche lì', (tester) async {
  // surfaceSize 390×780 → find.byKey(Key('next-episode-ticket')) findsOneWidget, nessun overflow
});
```

- [ ] **Step 2:** `flutter test test/features/detail/series_detail_test.dart` → FAIL.
- [ ] **Step 3:** costruisci il biglietto dentro `EpisodeTile` quando `highlighted`; chiave; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/detail` → PASS.
- [ ] **Step 5: Commit** `feat(app): il prossimo episodio della serie è un biglietto`

### Task 9: Voti della stagione sotto le schede

**Files:**
- Modify: `app/lib/features/ratings/friend_ratings_row.dart` (nuovo widget `SeasonRatingsStrip`), `app/lib/features/detail/series_detail_view.dart` (togli `FriendRatingsRow` da `:116-133`; la riga va sotto le schede; voce "Vota la stagione" nel ⋯ della stagione), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/ratings/friend_ratings_row_test.dart` (gruppo `'nella scheda'`), `app/test/features/detail/detail_tv_test.dart`

**Interfaces:**
- Consumes: `itemRatingsProvider`, `openRatePanel`, `RateSubject`, `WfButton.secondary(gold:)` (Task 4), `UserAvatar.lookup`.
- Produces: `class SeasonRatingsStrip extends ConsumerWidget { const SeasonRatingsStrip({super.key, required JellyfinItem season, required String title, ValueChanged<ItemRatings>? onRate}); }`:
  - stesse regole di `FriendRatingsRow` per esserci (funzione `ratings`, dati arrivati, amici o `canRate`) e stesso `ref.listen` su Visto;
  - una riga bassa con margini 24 (16 nello stretto) e filo `surface` sotto: `title` (`l.ratingFriendsRowSeason(season.name)`, `creamMuted` 12,5), media `WfText.display(28, color: WfColors.gold)` con `formatRatingAverage`, `l.ratingFriendsCount(n)`, una pastiglia per amico (avatar 24, nome, voto Bebas 18 oro), e a destra `WfButton.secondary(small: true, gold: mine != null, label: mine == null ? l.ratingRateSeason : l.ratingMine(mine.score), icon: LucideIcons.star)`; nello stretto va a capo (`Wrap`);
  - senza voti degli amici, al posto della media `l.ratingNoFriendsYet`;
  - in TV niente pulsante e niente focus (si vota con Vota della testata): Giù dalle schede va al primo episodio.
- Il ⋯ della stagione (Task 6) aggiunge `(label: l.ratingRateSeason, onSelected: () => openRatePanel(..., RateSubject(item: season, title: '${series.name} · ${season.name}', mine: r.mine)))` quando i dati ci sono e `r.canRate || r.mine != null`.
- Chiave nuova: `ratingRateSeason` "Vota la stagione" / "Rate the season".

- [ ] **Step 1: Test che falliscono**

```dart
// friend_ratings_row_test.dart, gruppo 'nella scheda' (sostituisce
// 'serie: la riga della stagione scelta, prima delle schede')
testWidgets('serie: i voti della stagione stanno sotto le schede', (tester) async {
  // social.itemRatingsById['se1'] con due amici (7 e 8) e canRate
  final strip = find.byType(SeasonRatingsStrip);
  expect(strip, findsOneWidget);
  expect(tester.getTopLeft(strip).dy, greaterThan(tester.getBottomLeft(find.text('Stagione 1')).dy));
  expect(tester.getTopLeft(strip).dy, lessThan(tester.getTopLeft(find.text('Episodio 3')).dy));
  expect(find.text('7,5'), findsOneWidget);
  expect(find.text('Vota la stagione'), findsOneWidget);
  expect(find.byType(FriendRatingsRow), findsNothing);
});
testWidgets('serie: Vota la stagione apre il pannello sulla stagione scelta', (tester) async {
  // tap su 'Vota la stagione' → rateSubjectProvider.item.id == 'se1', title 'The Last of Us · Stagione 1'
});
testWidgets('serie: il ⋯ della stagione ha Vota la stagione', (tester) async { /* .at(1), voce presente */ });
testWidgets('senza la funzione dei voti: niente riga e niente voce nel ⋯', (tester) async { /* ratings: false */ });
// detail_tv_test.dart
testWidgets('TV: Giù dalle schede va al primo episodio, non ai voti', (tester) async {
  // social.itemRatingsById['se1'] con un amico; focus su 'Stagione 1' →
  // arrowDown → hasFocus(find.text('Episodio 3')) (il nome nella prima riga)
});
```

- [ ] **Step 2:** `flutter test test/features/ratings test/features/detail/detail_tv_test.dart` → FAIL.
- [ ] **Step 3:** crea `SeasonRatingsStrip`, spostala sotto la riga delle schede nel blocco delle stagioni (Task 5), aggiungi la voce del ⋯ e la chiave.
- [ ] **Step 4:** `flutter test test/features/ratings test/features/detail` → PASS (`'serie: Vota vota la stagione mostrata e segue le schede'` in TV resta verde).
- [ ] **Step 5: Commit** `feat(app): i voti della stagione stanno sotto le schede`

### Task 10: Il pannello "Il tuo voto"

**Files:**
- Modify: `app/lib/features/ratings/rate_panel.dart` (`build`), `app/lib/features/ratings/rating_widgets.dart` (`RatingScorePicker`, nuova `ratingWord`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/ratings/rate_panel_test.dart`, `app/test/features/ratings/rating_widgets_test.dart`

**Interfaces:**
- Consumes: `PanelHeader` (fase 1, già nel pannello), `RatingCommentField` in `TvTextFieldFrame` (fase 1).
- Produces:
  - `String ratingWord(AppLocalizations l, int score) => l.ratingWord(score);` con `ratingWord` ICU `plural` sul segnaposto `int` (un `select` con chiavi numeriche non è sicuro in gen-l10n): it "{score, plural, =1{Da evitare} =2{Da evitare} =3{Deludente} =4{Deludente} =5{Così così} =6{Così così} =7{Bello} =8{Molto bello} =9{Bellissimo} other{Imperdibile}}"; en "{score, plural, =1{Skip it} =2{Skip it} =3{Disappointing} =4{Disappointing} =5{So-so} =6{So-so} =7{Good} =8{Very good} =9{Great} other{Must-see}}".
  - `RatingScorePicker({..., bool large = false})`: con `large` due file da cinque (`Wrap` o due `Row`, spazio 8), caselle alte 56 (46 in TV), numeri `WfText.display(30)` (26 in TV), angoli 8; scelto `gold` con numero `bg`. Senza `large` com'è oggi (`rating_round_panel.dart` non cambia).
  - Pannello: in `PanelHeader.subtitle` la riga con locandina 46×69 (angoli 4), `subject.title` (w600 15) e sotto `creamMuted` 12,5: per un film `'${l.requestsKindMovie} · ${year}'`, per una stagione `l.detailEpisodes(childCount)` se c'è. La locandina 80×120 di oggi sparisce. Sotto la scala, col voto scelto, `Text('$score  ${ratingWord(l, score)}')` oro w600 (il numero `WfText.display(22)`).
  - **Un piede solo**, fisso in basso, sopra un filo `border`: a sinistra, solo con `subject.mine != null`, `TextButton` "Togli il mio voto" con testo `WfColors.error.withValues(alpha: 0.85)`; a destra `WfButton.primary(label: l.ratingSave)`. Il corpo sopra scorre.
  - `ratingSave` diventa "Salva voto" / "Save rating".

- [ ] **Step 1: Test che falliscono**

```dart
test('le parole del voto', () {
  final l = lookupAppLocalizations(const Locale('it'));
  expect([for (var n = 1; n <= 10; n++) ratingWord(l, n)], [
    'Da evitare', 'Da evitare', 'Deludente', 'Deludente', 'Così così',
    'Così così', 'Bello', 'Molto bello', 'Bellissimo', 'Imperdibile']);
});
testWidgets('scala grande in due file e parola del voto', (tester) async {
  await pump(tester, mine: const MyRating(score: 8));
  expect(tester.getTopLeft(find.byKey(const Key('rating-score-6'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('rating-score-5'))).dy));
  expect(tester.getSize(find.byKey(const Key('rating-score-1'))).height, 56);
  expect(find.textContaining('Molto bello'), findsOneWidget);
});
testWidgets('un piede solo: Togli a sinistra, Salva voto a destra', (tester) async {
  await pump(tester, mine: const MyRating(score: 5));
  final remove = tester.getCenter(find.text('Togli il mio voto'));
  final save = tester.getCenter(find.text('Salva voto'));
  expect(remove.dx, lessThan(save.dx));
  expect((remove.dy - save.dy).abs(), lessThan(4));
});
```

Aggiorna `button('Salva')` → `button('Salva voto')` negli altri casi del file; "Togli il mio voto" non è più un `ButtonStyleButton` con l'icona: `button()` lo trova ancora (`TextButton` è un `ButtonStyleButton`).

- [ ] **Step 2:** `flutter test test/features/ratings` → FAIL.
- [ ] **Step 3:** implementa `ratingWord`, `large`, la riga del titolo, il piede; cambia `ratingSave`; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/ratings test/features/detail/detail_tv_test.dart` → PASS (in TV a 960×540 il pannello non va in overflow).
- [ ] **Step 5: Commit** `feat(app): il pannello del voto con la scala grande, la parola e un piede solo`

### Task 11: Persona

**Files:**
- Modify: `app/lib/features/person/person_screen.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/person/person_screen_test.dart`

**Interfaces:**
- Consumes: `ExpandableText` (Task 2), `MediaRow` + `rowPosterSize` (`ui/media_row.dart`), `openRequests(context)` (`features/requests/requests_navigation.dart:44`).
- Produces:
  - margini `16` con `detailCompact(context)`, `32` altrove (oggi 32 ovunque, `:99`, `:131`, `:153`);
  - biografia `ExpandableText(bio, maxLines: 4, tvFocusable: tv, style: TextStyle(height: 1.5))` (oggi 10 righe senza "Altro");
  - "Su WonderFlix" e la griglia solo con almeno un titolo; con zero titoli una riga `l.personNoTitles` ("Nessun suo titolo è sul server.", `creamMuted`) e `WfButton.secondary(label: l.personSearchRequests, icon: LucideIcons.search, onPressed: () => openRequests(context))` ("Cerca in Richieste");
  - TV: foto a sinistra (lo fa già la fase 1), biografia col focus (OK la apre), titoli in una `MediaRow(title: l.personOnServer, ...)` di `PosterCard` larghe `rowPosterSize(context).width` al posto della griglia.
- Chiavi nuove: `personNoTitles` "Nessun suo titolo è sul server." / "None of their titles are on the server."; `personSearchRequests` "Cerca in Richieste" / "Search in Requests".

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('senza titoli: niente Su WonderFlix, l\'invito a Richieste', (tester) async {
  // onItems → pageOf([]) → find.text('Su WonderFlix') findsNothing;
  // find.text('Nessun suo titolo è sul server.') e find.text('Cerca in Richieste') findsOneWidget
});
testWidgets('biografia lunga: 4 righe e Altro', (tester) async { /* overview lungo → maxLines 4, 'Altro' */ });
testWidgets('stretto: margini 16', (tester) async {
  // 390×780 → tester.getTopLeft(find.text('ZENDAYA')).dx == 16
});
testWidgets('TV: biografia col focus e titoli in una fila', (tester) async {
  // tv: true, Size(960, 540): find.byType(MediaRow) findsOneWidget; find.byType(SliverGrid) findsNothing;
  // focus sulla biografia + LogicalKeyboardKey.select → maxLines della biografia null
});
```

- [ ] **Step 2:** `flutter test test/features/person` → FAIL.
- [ ] **Step 3:** implementa margini, biografia, stato vuoto, fila in TV; chiavi.
- [ ] **Step 4:** `flutter test test/features/person test/features/detail/detail_hero_test.dart` (volo Hero della foto) → PASS.
- [ ] **Step 5: Commit** `feat(app): la Persona con la biografia che si apre e il suo layout in TV`

### Task 12: Saga e pagina TMDB

**Files:**
- Modify: `app/lib/features/collections/collection_screen.dart` (`:175`, `CollectionHeader` `:270-279`), `app/lib/features/requests/tmdb_title_screen.dart` (`TmdbTitleHeader`, padding delle stagioni `:154`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/collections/collection_screen_test.dart`, `app/test/features/requests/tmdb_title_screen_test.dart`

**Interfaces:**
- Consumes: `DetailHeaderFrame`, `detailBackdropHeight`, `detailCompact`, `headerTitleStyle`, `DetailKicker` (Task 1), `ExpandableText` (Task 2).
- Produces:
  - **Saga:** griglia con margini `detailCompact(context) ? 16 : 32`; con zero titoli, al posto di "0 film · 0 visti", `l.collectionEmptyHint` ("Nessun film di questa saga è sul server. Puoi chiederli in Richieste.", `creamMuted`).
  - **TMDB:** `TmdbTitleHeader` diventa `Stack(children: [Positioned(top: 0, left: 0, right: 0, height: detailBackdropHeight(context), child: BackdropImage(...)), DetailHeaderFrame(controller: null, children: [...])])`, così nello stretto l'immagine è 16:9 sopra e i testi sotto, come la scheda. Figli: `DetailKicker(l.tmdbNotOnServer)` solo se il titolo non si può guardare (`!watchable`); il nome in maiuscolo con `headerTitleStyle(context)`; **una riga di dati** `[anno, Film/Serie, durata o stagioni, ...genres.map(genreLabel).take(2)].join(' · ')`; la trama con `ExpandableText(maxLines: 3)`; le azioni di oggi (Richiedi primario, stato, Guarda, Trailer). Margini delle stagioni `detailCompact ? 16 : 32`.
- Chiavi nuove: `collectionEmptyHint` (testo sopra) / "None of this saga's films are on the server. You can ask for them in Requests."; `tmdbNotOnServer` "Non ancora su WonderFlix" / "Not on WonderFlix yet".

- [ ] **Step 1: Test che falliscono**

```dart
// collection_screen_test.dart
testWidgets('saga vuota: dice cosa fare, non 0 film', (tester) async {
  // titoli della saga = [] → find.textContaining('0 film') findsNothing;
  // find.text('Nessun film di questa saga è sul server. Puoi chiederli in Richieste.') findsOneWidget
});
testWidgets('stretto: la griglia parte a 16', (tester) async {
  // 390×780 → getTopLeft(prima PosterCard).dx == 16
});
// tmdb_title_screen_test.dart (aggiorna 'film: dati, trailer e Richiedi con l'avviso')
expect(find.text('Non ancora su WonderFlix'), findsOneWidget);
expect(find.text('2024 · Film · 2h 46m · Fantascienza · Avventura'), findsOneWidget);
expect(find.text('Fantascienza · Avventura'), findsNothing);
testWidgets('stretto: immagine sopra e testi sotto, come la scheda', (tester) async {
  // 390×780 → find.byType(DetailHeaderFrame) findsOneWidget;
  // getTopLeft(find.text('DUNE - PARTE DUE')).dy >= 390 * 9 / 16 - 1
});
testWidgets('in parte nella libreria: niente Non ancora su WonderFlix', (tester) async { /* status partial */ });
```

- [ ] **Step 2:** `flutter test test/features/collections test/features/requests/tmdb_title_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS (`'lo sfondo scorre con la testata, con la rotella dolce'` resta verde: lo sfondo è ancora dentro la lista).
- [ ] **Step 5: Commit** `feat(app): saga vuota che spiega e pagina TMDB con la testata della scheda`

### Task 13: Checklist e verifica completa

**Files:**
- Modify: `docs/RELEASING.md` (checklist della 0.42.0, dopo la riga della fase 1 se c'è, altrimenti dopo "Stasera e Match nuovi")

- [ ] **Step 1:** aggiungi la riga: `- [ ] Revisione finale, fase 3: scheda (app 0.42.0): film con "Film di …", titolo grande, una riga di dati con due generi in italiano, trama con Altro, azioni in ordine (↺ accanto al primario, Consiglia icona, ⋯ ultimo con Richiedi stagioni), "rimangono …" sotto il primario; serie con le stagioni "Stagione 1 · 8 episodi" che scorrono, ⋯ della stagione (Segna la stagione come vista: controllare in UserData che siano visti anche gli episodi), voti della stagione sotto le schede, Visto su un episodio, biglietto del prossimo episodio, anime lungo che scorre liscio; pannello voto con scala grande, parola e un piede; Persona senza titoli; saga vuota; pagina TMDB nello stretto; telefono con sei azioni con la parola; TV: nomi sotto le icone, Giù alle stagioni e al primo episodio.`
- [ ] **Step 2: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta).
- [ ] **Step 3: Commit** `docs: checklist della scheda nuova`

## Prova a mano (dopo la review finale)

Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`):
- un film con punto di ripresa (riga oro col regista, "rimangono …", ordine delle azioni, Vota e Consiglia icone, ⋯ ultimo), "Altro" sulla trama; la riga "Voti degli amici" col pulsante oro;
- una serie con due stagioni: schede con il numero di episodi, Visto su un episodio, il biglietto del prossimo, "Segna la stagione come vista" e poi `UserData` degli episodi in `jellyfin.db` (sola lettura): se non risultano visti, la riserva di §11 (un `POST` per episodio); rimetterli "da vedere" alla fine. Usare un titolo che non sposta la ripresa di nessuno;
- un anime lungo (centinaia di episodi): la pagina si apre e scorre senza scatti;
- il pannello voto (scala, parola, Togli/Salva voto), una Persona senza titoli, una saga, una pagina TMDB; la finestra stretta sotto 1024 px.

APK sulla Fire Stick (comando in CLAUDE.md): scheda di "2012" e di una serie (nomi sotto le icone, focus sul primario, Giù alle stagioni e al primo episodio, voti della stagione che non prendono il focus), Vota col commento in cornice, una Persona (biografia con OK, titoli in fila).
