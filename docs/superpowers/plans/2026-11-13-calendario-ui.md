# Calendario, nuova UI: piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** rifare la pagina Calendario dell'app come nella bozza approvata: passato spento, oggi in evidenza, barrette film/serie, cerchio "non ancora arrivato", elenco del giorno in ordine di ora, vista "Prossimi 7 giorni" e, nello stretto, elenco del giorno sotto la griglia.

**Architecture:** solo app Flutter, nessun cambio al plugin. La logica pura (stato di una voce, ordine, righe, "TBA", periodo dei 7 giorni) sta in `calendar_logic.dart`; una riga d'uscita condivisa tra finestra del giorno, 7 giorni e telefono; un provider nuovo per i 7 giorni; la vista sta nell'indirizzo (`?view=week`).

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, go_router, intl, `clock` per l'ora nei test.

**Spec:** `docs/superpowers/specs/2026-11-13-calendario-ui-design.md` (bozza: `docs/superpowers/specs/2026-11-13-calendario-bozze/calendario.html`). Dove la spec tace vale `docs/superpowers/specs/2026-10-22-wonderflix-calendario-uscite-design.md` §7.

## Global Constraints

- Lavoro nel worktree `C:\Users\sidot\Documents\Github\wonderflix\.claude\worktrees\calendario-ui`, comandi da `app/`. In Git Bash prima: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`.
- Controlli come in CI: `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- Release build (se serve): `flutter build windows --release --dart-define-from-file=config/wonderflix.json` (copiare prima `config/wonderflix.json` dal checkout principale `C:\Users\sidot\Documents\Github\wonderflix\app\config\`).
- Mai chiudere processi per nome dell'immagine (`taskkill /IM`, `pkill`): solo per PID e solo i propri.
- Commit in italiano, autore l'utente, **senza** `Co-Authored-By` né "Generated with Claude Code"; mai le parole `closes`, `fixes`, `resolves`. Messaggi multi-riga con `git commit -F <file>` (file senza BOM).
- Dopo comandi Flutter, se `app/windows/flutter/generated_plugin*` cambiano solo nei fine riga: `git checkout -- app/windows/flutter/`.
- `dart format` solo sulle righe toccate (non riformattare file interi).
- Stile invariato: `WfColors` (bg `#0A0A0A`, surface `#121212`, surfaceHigh `#1B1B1B`, border `#262626`, gold `#D4A64A`, cream `#F2EAD3`, creamMuted, online `#5BBF6A`), titoli `WfText.display` (Bebas Neue), testo Inter. Unico colore nuovo: `WfColors.calendarSeriesMark = Color(0xFF7E9CBD)`.
- TV fuori: `/calendar` resta in `_tvExcluded`. Il titolo "CALENDARIO" resta.
- Esce con l'app **0.42.0**: `pubspec.yaml` non cambia.
- Riverpod 3: niente nomi di Riverpod 2.
- Test di widget con indicatori indeterminati: niente `pumpAndSettle` infinito.

## Review Focus

1. **I 7 giorni a cavallo di due mesi** (oggi 28 novembre): la richiesta è `calendar(28/11, 05/12)` e i giorni di dicembre hanno le loro uscite. Test in Task 4 (`WeekProviderAsksTodayPlusSeven`).
2. **Film del giorno non ancora sul server**: un film con uscita digitale oggi e `onServer: false` è `missing` già oggi (spec §4.2: un film vale da tutto il suo giorno), domani è `upcoming`. Test in Task 1 (`AMovieCountsFromItsWholeDay`).
3. **Serie ×n con episodi in parte usciti**: alle 18:20, Percy Jackson 18:00 sul server + 18:40 non uscito = `upcoming` (niente cerchio); 18:00 non sul server = `missing`. Test in Task 1 (`AGroupIsMissingIfAnAiredEpisodeIsMissing`).
4. **Un servizio in errore con settimana vuota**: non si dice "Nessuna uscita nei prossimi 7 giorni" (come per il mese). Test in Task 4 (`AFailingServiceDoesNotSayTheWeekIsEmpty`).
5. **"TBA" scritto in altri modi** (`tba`, ` TBA `, `TBD`): mai mostrato come titolo. Test in Task 1 (`TbaIsNoTitle`).

---

## File

| File | Responsabilità |
|---|---|
| `lib/features/calendar/calendar_logic.dart` (mod.) | stato di voce ed episodio, ordine, righe di un giorno, "TBA", giorni e periodo dei 7 giorni |
| `lib/features/calendar/calendar_release_row.dart` (nuovo) | `CalendarReleaseRow` (una riga: locandina, titolo, sottotitolo, ora, stato) e `CalendarDayList` (intestazione del giorno + righe) |
| `lib/features/calendar/calendar_day_dialog.dart` (mod.) | finestra del giorno con riassunto e pillola, usa `CalendarReleaseRow` |
| `lib/features/calendar/calendar_month_grid.dart` (mod.) | caselle, voci, puntini, "+n altre", passaggio del mouse, modo selezione |
| `lib/features/calendar/calendar_week_view.dart` (nuovo) | la vista 7 giorni |
| `lib/features/calendar/calendar_providers.dart` (mod.) | `calendarWeekProvider` |
| `lib/features/calendar/calendar_navigation.dart` (mod.) | `CalendarView`, lettura della vista, rotta dei 7 giorni |
| `lib/features/calendar/calendar_screen.dart` (mod.) | intestazione, pulsante della vista, legenda, scelta della vista, telefono |
| `lib/app/router.dart` (mod.) | passa la vista allo schermo |
| `lib/app/theme.dart` (mod.) | `calendarSeriesMark`, via `calendarSeries` |
| `l10n/app_it.arb`, `l10n/app_en.arb` (mod.) | testi nuovi |
| `docs/RELEASING.md` (mod.) | riga della prova a mano |

---

### Task 1: Logica (stato, ordine, righe, "TBA", 7 giorni)

**Files:**
- Modify: `app/lib/features/calendar/calendar_logic.dart`
- Test: `app/test/features/calendar/calendar_logic_test.dart`

**Interfaces:**
- Produces:
  - `enum CalendarEntryState { arrived, missing, upcoming }`
  - `CalendarEntryState episodeState(UpcomingEpisode e, DateTime now)`: `airDate <= now` → `onServer ? arrived : missing`, altrimenti `upcoming`.
  - `CalendarEntryState calendarEntryState(CalendarEntry entry, {required DateTime day, required DateTime now})`: film → uscito se `day <= dayKey(now)` (`day` = chiave del giorno della casella); serie → `missing` se un episodio uscito non è sul server, altrimenti `arrived` se tutti usciti, altrimenti `upcoming`. Una serie senza `episodes` (dati di test) usa `day` come un film.
  - `class CalendarRow { const CalendarRow(this.entry, [this.episode]); final CalendarEntry entry; final UpcomingEpisode? episode; }` (una riga per film, una per episodio o blocco).
  - `List<CalendarRow> calendarRows(List<CalendarEntry> entries)`: ordine §4.6 (film per nome; poi episodi per `airDate`, nome serie senza maiuscole, stagione, episodio).
  - `String? episodeTitleOrNull(String? title)`: `null` per null, vuoto, `TBA`, `TBD` (trim, senza maiuscole).
  - `List<DateTime> calendarWeekDays(DateTime today)`: i 7 giorni da `dayKey(today)`, con `DateTime(y, m, d + i)`.
  - `({DateTime start, DateTime end}) calendarWeekPeriod(DateTime today)`: `start` = `dayKey(today)`, `end` = start + 7 giorni (escluso).
  - `entriesByDay` cambia ordine: film per nome, poi serie per `airDate` del primo episodio, poi per nome; gli `episodes` di una voce in ordine di `airDate`, stagione, episodio.

- [ ] **Step 1: Scrivere i test che falliscono** (stessi helper `testEpisode`/`testUpcomingMovie` del file)

```dart
test('EpisodeStateFollowsAirTimeAndServer', () {
  final now = DateTime(2026, 11, 13, 22, 26);
  expect(episodeState(testEpisode(airDate: DateTime(2026, 11, 13, 15, 30), onServer: false), now), CalendarEntryState.missing);
  expect(episodeState(testEpisode(airDate: DateTime(2026, 11, 13, 9), onServer: true), now), CalendarEntryState.arrived);
  expect(episodeState(testEpisode(airDate: DateTime(2026, 11, 13, 23), onServer: false), now), CalendarEntryState.upcoming);
});

test('AMovieCountsFromItsWholeDay', () {
  const odissea = CalendarEntry(kind: CalendarEntryKind.movie, title: 'Odissea');
  final now = DateTime(2026, 11, 13, 0, 5);
  expect(calendarEntryState(odissea, day: DateTime(2026, 11, 13), now: now), CalendarEntryState.missing);
  expect(calendarEntryState(odissea, day: DateTime(2026, 11, 14), now: now), CalendarEntryState.upcoming);
  expect(calendarEntryState(const CalendarEntry(kind: CalendarEntryKind.movie, title: 'X', onServer: true), day: DateTime(2026, 11, 12), now: now), CalendarEntryState.arrived);
});

test('AGroupIsMissingIfAnAiredEpisodeIsMissing', () {
  final now = DateTime(2026, 11, 20, 18, 20);
  CalendarEntry percy({required bool firstOnServer}) => CalendarEntry(
        kind: CalendarEntryKind.series, title: 'Percy Jackson', count: 2,
        episodes: [
          testEpisode(episode: 1, airDate: DateTime(2026, 11, 20, 18), onServer: firstOnServer),
          testEpisode(episode: 2, airDate: DateTime(2026, 11, 20, 18, 40)),
        ]);
  final day = DateTime(2026, 11, 20);
  expect(calendarEntryState(percy(firstOnServer: true), day: day, now: now), CalendarEntryState.upcoming);
  expect(calendarEntryState(percy(firstOnServer: false), day: day, now: now), CalendarEntryState.missing);
});

test('RowsAreMoviesThenEpisodesByTime', () {
  // Grey's 03:00, WAR 03:00, MobLand 09:00, Tulsa King 09:00, Overgeared 15:30, Odissea (film)
  // in ingresso in ordine sparso -> titoli delle righe:
  // ['Odissea', "Grey's Anatomy", 'WAR (2026)', 'MobLand', 'Tulsa King', 'Overgeared']
});

test('EntriesByDayPutsSeriesInTimeOrder', () { /* stessi dati via entriesByDay: stesso ordine delle voci */ });

test('TbaIsNoTitle', () {
  for (final t in [null, '', 'TBA', 'tba', ' TBA ', 'TBD']) {
    expect(episodeTitleOrNull(t), isNull, reason: '$t');
  }
  expect(episodeTitleOrNull('Till I Collapse'), 'Till I Collapse');
});

test('WeekDaysAndPeriodCrossTheMonth', () {
  final today = DateTime(2026, 11, 28, 21);
  expect(calendarWeekDays(today).first, DateTime(2026, 11, 28));
  expect(calendarWeekDays(today).last, DateTime(2026, 12, 4));
  expect(calendarWeekPeriod(today), (start: DateTime(2026, 11, 28), end: DateTime(2026, 12, 5)));
});
```

Il test esistente `MoviesComeFirstThenSeriesByTitle` diventa `MoviesComeFirstThenSeriesByTime` (serie con ore diverse: vince l'ora, a parità d'ora il nome).

- [ ] **Step 2: Lanciare i test e vederli fallire**

Run: `flutter test test/features/calendar/calendar_logic_test.dart`
Expected: FAIL (simboli non definiti).

- [ ] **Step 3: Implementare in `calendar_logic.dart` le firme dell'Interfaces block**

- [ ] **Step 4: Lanciare i test**

Run: `flutter test test/features/calendar/`
Expected: PASS (anche griglia, finestra e schermo: l'ordine nuovo non deve rompere altro; se un test esistente dipende dall'ordine per nome, aggiornarlo all'ordine §4.6).

- [ ] **Step 5: Commit** — `feat(app): il calendario sa se un'uscita è arrivata e ordina per ora`

---

### Task 2: Riga d'uscita condivisa e finestra del giorno

**Files:**
- Create: `app/lib/features/calendar/calendar_release_row.dart`
- Modify: `app/lib/features/calendar/calendar_day_dialog.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/calendar/calendar_day_dialog_test.dart`

**Interfaces:**
- Consumes: `CalendarRow`, `calendarRows`, `episodeState`, `calendarEntryState`, `episodeTitleOrNull`, `CalendarEntryState` (Task 1).
- Produces:
  - `class CalendarReleaseRow extends StatelessWidget { const CalendarReleaseRow({super.key, required CalendarRow row, required DateTime day, required DateTime now, required VoidCallback? onTap, bool large = false, bool compactStatus = false}); }` — locandina 34×51 (`large`: 40×60); titolo w600; sottotitolo `calendarMovieDigital` per i film, `episodeCode(...)` + ` · ` + titolo pulito per gli episodi; ora `HH:mm` locale per gli episodi (cifre tabellari); stato: `arrived` → ✓ + `calendarOnServer` in `WfColors.online`, `missing` → cerchio oro 9 px (bordo 1,5) + `calendarNotArrived` in oro, `upcoming` → niente. `compactStatus`: solo il segno, il testo resta nella semantica. `onTap == null`: niente clic, cursore né azione di semantica (come oggi).
  - `class CalendarDayList extends StatelessWidget { const CalendarDayList({super.key, required DateTime day, required DateTime today, required DateTime now, required List<CalendarEntry> entries, required void Function(CalendarEntry) onOpenEntry, required bool Function(CalendarEntry) canOpen, bool large = false, bool compactStatus = false, bool showEmpty = true}); }` — intestazione §4.8 (oggi: "Oggi" Bebas 24 oro + data `creamMuted` 13 minuscola; domani: "Domani" + data; altri: data capitalizzata Bebas 24 crema) e le righe; senza voci e con `showEmpty` → `calendarNoReleases` in `creamMuted`. Key dell'intestazione: `Key('calendar-heading-yyyy-MM-dd')`.
- Testi nuovi (ARB it/en, da spec §4.10): `calendarNotArrived` ("Non ancora arrivato" / "Not here yet"), `calendarTomorrow` ("Domani" / "Tomorrow"), `calendarNoReleases` ("Nessuna uscita" / "No releases"), `calendarDaySummary` (plurale: "1 uscita"/"{count} uscite"; en "1 release"/"{count} releases"), `calendarDayOnServer` ("{count} già sul server" / "{count} already on the server").

- [ ] **Step 1: Scrivere i test che falliscono** (in `calendar_day_dialog_test.dart`; `showCalendarDay` prende ora anche `now: DateTime`, e `today: DateTime`)

```dart
testWidgets('RowsAreInTimeOrder', (tester) async {
  // voci: Tulsa King 09:00, Grey's Anatomy 03:00, Overgeared 15:30, un film
  // ordine verticale delle righe: film, Grey's, Tulsa King, Overgeared
  // (confronta tester.getTopLeft(find.text(...)).dy)
});
testWidgets('TbaIsHidden', (tester) async {
  // episodio con episodeTitle 'TBA' (costruito con UpcomingEpisode(...) come _bridge: testEpisode non ha episodeTitle)
  // -> find.text('S01E08') trovato, find.textContaining('TBA') nessuno
});
testWidgets('TheDialogSaysHowManyAndHowManyAreHere', (tester) async {
  // 5 righe, 4 sul server -> find.text('5 uscite · 4 già sul server')
  // nessuna sul server -> find.text('5 uscite')
});
testWidgets('TodayAndTomorrowHaveAPill', (tester) async {
  // day == today -> find.text('Oggi'); day == today+1 -> find.text('Domani'); altro giorno -> nessuna delle due
});
testWidgets('EachRowShowsItsState', (tester) async {
  // now dopo l'uscita: sul server -> 'Sul server'; non sul server -> 'Non ancora arrivato'; non uscito -> nessuno dei due
});
```

I test esistenti restano (`TheDayListShowsEveryEpisodeAndTime`, `TappingARowClosesAndOpens`, `ADoubleTapPopsOnlyTheDialog`, `ARowThatCannotOpenIsNotClickable`), con `now`/`today` aggiunti.

- [ ] **Step 2: `flutter gen-l10n` e lanciare i test** — Expected: FAIL.
- [ ] **Step 3: Implementare** `calendar_release_row.dart` (sposta qui `_DayRow`) e la finestra: firma `Future<void> showCalendarDay(BuildContext context, {required DateTime day, required DateTime today, required DateTime now, required List<CalendarEntry> entries, required void Function(CalendarEntry) onOpenEntry, required bool Function(CalendarEntry) canOpen})`. Titolo `calendarDayTitle` + pillola oro (`calendarToday`/`calendarTomorrow`, testo `bg`, 12 px, raggio 10); riga di riassunto `calendarDaySummary(n)` + (`k > 0`) ` · ` + `calendarDayOnServer(k)`, dove n = righe e k = righe `arrived`. Aggiornare la chiamata in `calendar_screen.dart` (passa `today` e `clock.now()`).
- [ ] **Step 4: Lanciare** `flutter test test/features/calendar/` — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(app): l'elenco del giorno va in ordine di ora e dice cosa è arrivato`

---

### Task 3: Griglia del mese

**Files:**
- Modify: `app/lib/features/calendar/calendar_month_grid.dart`, `app/lib/app/theme.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/calendar/calendar_month_grid_test.dart`

**Interfaces:**
- Consumes: `calendarEntryState`, `CalendarEntryState`, `entriesByDay` già ordinato (Task 1).
- Produces: `CalendarMonthGrid` con parametri nuovi
  - `required DateTime now` (stato e ore di oggi);
  - `DateTime? selectedDay` e `void Function(DateTime day)? onSelectDay`: con `onSelectDay != null` (**modo selezione**, usato nello stretto dal Task 5) il tocco e Invio selezionano invece di chiamare `onOpenDay`, le caselle sono sempre a puntini, alte 48, e la griglia ha altezza fissa (`_headerHeight + 6 * 48 + 5 * _gap`) senza scorrere da sola. Ogni giorno si può selezionare, anche vuoto o di un mese vicino. Il giorno selezionato ha fondo `Color(0xFF2A2418)`.
  - Key nuove: `Key('calendar-entry-$id-$i-missing')` sul cerchio di una voce, `Key('calendar-entry-$id-$i-arrived')` sul ✓ (solo oggi), `Key('calendar-dot-$id-$i')` resta sui puntini.
- `theme.dart`: `static const calendarSeriesMark = Color(0xFF7E9CBD);` al posto di `calendarSeries` (che sparisce); `calendarMovie` resta.
- ARB: `calendarMore` diventa "+{count} altre" / "+{count} more".

Valori dalla spec §4.4 (da usare tali e quali): passato del mese fondo `surface` e opacità 0,42 su numero e voci **tranne** le `missing`; mesi vicini fondo trasparente, bordo `surface`, opacità 0,30; oggi bordo oro 2 px, numero in pillola oro (testo `bg`) + "Oggi" (`calendarToday`) in oro 12; voce alta 20, barretta 3 px (oro film, `calendarSeriesMark` serie), testo 12,5 `cream`, `×n` in `creamMuted` dopo il nome; a destra cerchio oro per `missing` ovunque, e solo nella casella di oggi ✓ verde per `arrived` e `HH:mm` per `upcoming` con ora; nessuna icona film/serie; "+n altre" 12,5 in `cream` al 75%; intestazioni dei giorni a sinistra (padding 8), sab/dom al 45%; mouse: casella con voci bordo `Color(0xFF3A3A3A)`, voce apribile fondo `WfColors.border`; `Tooltip(waitDuration: 500 ms)` con "Film: {titolo}" / "Serie: {etichetta}" (`requestsKindMovie`/`requestsKindSeries` + ": "); il bordo crema del fuoco vince su quello di oggi. Puntini: oro film, `calendarSeriesMark` serie, `missing` = cerchio vuoto oro; al massimo 4. Semantica della voce: tipo, etichetta e `calendarNotArrived` / `calendarAlreadyOnServer` secondo lo stato.

- [ ] **Step 1: Aggiornare e scrivere i test** (helper `_pump` con `now` predefinito `DateTime(2026, 10, 22, 12)`)

```dart
testWidgets('PastDaysAreDimmedExceptMissingEntries', (tester) async {
  // voce sul server il 20/10 e voce non sul server il 20/10:
  // Opacity sopra la prima = 0.42, nessuna Opacity < 1 sopra la seconda (cerchio 'calendar-entry-2026-10-20-1-missing' trovato)
});
testWidgets('TodayShowsTimesAndChecks', (tester) async {
  // oggi 22/10 ore 12: episodio delle 09:00 sul server -> key '...-arrived'; episodio delle 21:00 -> find.text('21:00')
});
testWidgets('FutureEntriesHaveNoMarks', (tester) async { /* 25/10: né missing né arrived */ });
testWidgets('TooManyEntriesBecomePlusNOthers', (tester) async { /* era TooManyEntriesBecomePlusN: ora '+2 altre' */ });
testWidgets('EntriesHaveATooltip', (tester) async { /* find.byTooltip('Film: Weapons') */ });
testWidgets('SelectionModeSelectsInsteadOfOpening', (tester) async {
  // onSelectDay dato: tap su un giorno vuoto -> onSelectDay(giorno), onOpenDay mai chiamato; Invio idem; puntini anche a 1440 px
});
```

`EntriesShowLabelsAndTheOnServerDot` diventa `EntriesShowLabelsAndMarks`; `NarrowCellsShowDots` controlla i colori nuovi (`WfColors.gold` film, `WfColors.calendarSeriesMark` serie).

- [ ] **Step 2: `flutter gen-l10n`, lanciare** `flutter test test/features/calendar/calendar_month_grid_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implementare** nella griglia; passare `now: clock.now()` da `calendar_screen.dart`.
- [ ] **Step 4: Lanciare** `flutter test test/features/calendar/` e `flutter analyze` — Expected: PASS, nessun problema (nessun riferimento rimasto a `calendarSeries`).
- [ ] **Step 5: Commit** — `feat(app): griglia del calendario con passato spento, oggi in evidenza e barrette`

---

### Task 4: Vista "Prossimi 7 giorni" e il suo provider

**Files:**
- Create: `app/lib/features/calendar/calendar_week_view.dart`
- Modify: `app/lib/features/calendar/calendar_providers.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/calendar/calendar_week_view_test.dart` (nuovo), `app/test/features/calendar/calendar_providers_test.dart` (nuovo)

**Interfaces:**
- Consumes: `calendarWeekDays`, `calendarWeekPeriod`, `entriesByDay` (Task 1); `CalendarDayList` (Task 2).
- Produces:
  - `final calendarWeekProvider = FutureProvider.autoDispose<CalendarPage>(...)`: stessi cancelli di `calendarPageProvider` (prima `calendarAvailableProvider`, poi `currentUserIdProvider`, tutti i watch prima dell'attesa), poi `homeApi.calendar(p.start, p.end)` con `p = calendarWeekPeriod(clock.now())`; stessi log d'errore.
  - `class CalendarWeekView extends StatelessWidget { const CalendarWeekView({super.key, required DateTime today, required DateTime now, required Map<DateTime, List<CalendarEntry>> entries, required bool knownEmpty, required void Function(CalendarEntry) onOpenEntry, required bool Function(CalendarEntry) canOpen, bool compact = false}); }` — una `CalendarDayList` per giorno di `calendarWeekDays(today)` (`large: !compact`, `compactStatus: compact`), in una colonna che scorre, larghezza massima 720 fuori dallo stretto, allineata a sinistra. Con `knownEmpty` (nessuna voce nei 7 giorni e nessun servizio in errore) le intestazioni restano ma senza "Nessuna uscita" (`showEmpty: false`) e in fondo un solo `calendarWeekEmpty`.
- ARB: `calendarWeekEmpty` ("Nessuna uscita nei prossimi 7 giorni" / "No releases in the next 7 days").

- [ ] **Step 1: Scrivere i test che falliscono**

```dart
// calendar_providers_test.dart
test('WeekProviderAsksTodayPlusSeven', () async {
  // withClock(Clock.fixed(DateTime(2026, 11, 28, 21))), container con FakeHomeApi e calendario disponibile:
  // await container.read(calendarWeekProvider.future);
  // expect(api.calendarCalls, [(DateTime(2026, 11, 28), DateTime(2026, 12, 5))]);
});
test('WeekProviderAsksNothingWithoutTheFeature', () async { /* calendar: false -> nessuna chiamata, CalendarPage vuota */ });

// calendar_week_view_test.dart (oggi 13/11/2026 22:26)
testWidgets('SevenHeadingsFromToday', (tester) async {
  // find.text('Oggi'), find.text('Domani'), key 'calendar-heading-2026-11-19' trovata, 'calendar-heading-2026-11-20' no
});
testWidgets('AnEmptyDaySaysSo', (tester) async { /* giorno senza voci -> 'Nessuna uscita' */ });
testWidgets('AnEmptyWeekSaysItOnce', (tester) async { /* knownEmpty -> 'Nessuna uscita nei prossimi 7 giorni' una volta, 'Nessuna uscita' nessuna */ });
testWidgets('TappingARowOpensIt', (tester) async { /* onOpenEntry ricevuto con la voce giusta */ });
testWidgets('CompactRowsShowOnlyTheMark', (tester) async { /* compact: find.text('Sul server') nessuno, semantica con 'Sul server' */ });
```

- [ ] **Step 2: `flutter gen-l10n`, lanciare i due file** — Expected: FAIL.
- [ ] **Step 3: Implementare** provider e vista.
- [ ] **Step 4: Lanciare** `flutter test test/features/calendar/` — Expected: PASS.
- [ ] **Step 5: Commit** — `feat(app): vista "Prossimi 7 giorni" del calendario`

---

### Task 5: Schermata, indirizzo e telefono

**Files:**
- Modify: `app/lib/features/calendar/calendar_navigation.dart`, `app/lib/features/calendar/calendar_screen.dart`, `app/lib/app/router.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`, `docs/RELEASING.md`
- Test: `app/test/features/calendar/calendar_navigation_test.dart`, `app/test/features/calendar/calendar_screen_test.dart`

**Interfaces:**
- Consumes: `CalendarWeekView`, `calendarWeekProvider` (Task 4); `CalendarMonthGrid` modo selezione (Task 3); `CalendarDayList`, `showCalendarDay` (Task 2).
- Produces:
  - `enum CalendarView { month, week }`
  - `CalendarView? parseCalendarView(Map<String, String> query)`: `view == 'week'` → `week`; altrimenti `parseCalendarMonth(query['month']) != null` → `month`; altrimenti `null` (= vista di partenza secondo lo schermo).
  - `const calendarWeekRoute = '/calendar?view=week';` e `void openCalendarWeek(BuildContext context) => context.go(calendarWeekRoute);`
  - `CalendarScreen({super.key, this.month, this.view})` con `final CalendarView? view;` — vista effettiva `view ?? (FormFactor.of(context).compact ? CalendarView.week : CalendarView.month)`.
  - `router.dart`: `view: parseCalendarView(state.uri.queryParameters)`.
- ARB: `calendarViewMonth` ("Mese" / "Month"), `calendarViewWeek` ("Prossimi 7 giorni" / "Next 7 days").

Comportamento (spec §4.3, §4.7–4.9):
- Intestazione fuori dallo stretto: titolo "CALENDARIO" com'è; sotto, in una riga: (solo Mese) titolo del mese, frecce, "Oggi"; poi a destra la legenda (`▍Film ▍Serie ○ Non ancora arrivato`, 12 px `creamMuted`, barrette 3×12) e il `SegmentedButton<CalendarView>` (come in `catalog_filters_bar.dart`), Key `calendar-view-month` / `calendar-view-week`. "Mese" → `openCalendarMonth(context, mese di oggi)`, "Prossimi 7 giorni" → `openCalendarWeek(context)`.
- Nello stretto: niente legenda; il pulsante a tutta larghezza sotto il titolo; mese e frecce sotto, solo nella vista Mese.
- Vista 7 giorni: `calendarWeekProvider`, stessi errori della vista Mese (righe per servizio, `ErrorView` se tutti i servizi accesi falliscono, motivo all'admin), poi `CalendarWeekView` con `knownEmpty` = nessuna voce e nessun servizio in errore.
- Vista Mese fuori dallo stretto: com'è, con la finestra del giorno.
- Vista Mese nello stretto: una sola colonna che scorre con `CalendarMonthGrid` in modo selezione e sotto `CalendarDayList(day: selezionato, compactStatus: true)`. Selezione iniziale: oggi se nella griglia, altrimenti il primo del mese; stato in un widget `StatefulWidget` privato dello schermo. Il wrapper resta sempre lo stesso (gotcha: cambiare i widget sopra una lista ne azzera lo scorrimento).
- `docs/RELEASING.md`, in coda alla checklist (dopo la riga del tappabuchi 720p): `- [ ] Calendario nuovo (app 0.42.0): mese di oggi con passato spento, oggi in pillola oro con ✓ e ore, barrette oro/azzurre, cerchio oro su un'uscita passata non sul server, "+n altre", tooltip; elenco del giorno in ordine di ora, senza "TBA", con "n uscite · k già sul server"; "Prossimi 7 giorni" e ritorno al mese; sul web da iPhone si apre sui 7 giorni, nel Mese un tocco su un giorno ne mostra le uscite sotto la griglia.`

- [ ] **Step 1: Scrivere i test che falliscono**

```dart
// calendar_navigation_test.dart
test('parseCalendarView', () {
  expect(parseCalendarView({'view': 'week'}), CalendarView.week);
  expect(parseCalendarView({'view': 'week', 'month': '2026-11'}), CalendarView.week);
  expect(parseCalendarView({'month': '2026-11'}), CalendarView.month);
  expect(parseCalendarView({'month': '2026-13'}), isNull);
  expect(parseCalendarView({'view': 'boh'}), isNull);
  expect(parseCalendarView({}), isNull);
});

// calendar_screen_test.dart (pumpScreen passa view: parseCalendarView(state.uri.queryParameters) e accetta surfaceSize)
testWidgets('WideStartsOnTheMonthPhoneOnTheWeek', ...);      // 1440×900 -> griglia; 390×844 -> 'Oggi' come intestazione dei 7 giorni, chiamata (oggi, oggi+7)
testWidgets('TheViewButtonChangesTheAddress', ...);          // tap 'calendar-view-week' -> '/calendar?view=week'; tap 'calendar-view-month' -> '/calendar?month=2026-10'
testWidgets('TheWeekHidesMonthArrowsKeepsTheTitle', ...);    // view=week: 'CALENDARIO' sì, Key('calendar-previous') no
testWidgets('TheLegendIsOnlyOnWideScreens', ...);            // 'Non ancora arrivato' nella legenda a 1440, assente a 390 (senza voci)
testWidgets('OnPhonesADayShowsItsReleasesUnderTheGrid', ...);// 390×844, ?month=2026-10: tap su un giorno con voci -> intestazione di quel giorno sotto, nessuna finestra
testWidgets('AFailingServiceDoesNotSayTheWeekIsEmpty', ...); // view=week, seriesError unreachable e film vuoti -> riga d'errore, nessun 'Nessuna uscita nei prossimi 7 giorni'
```

`ShowsTheMonthOfTodayAndAsksItsPeriod` e `TodayButtonIsAFingerTargetOnPhones` restano (il secondo con `?month=` nell'indirizzo, perché sul telefono senza `month` si apre la settimana).

- [ ] **Step 2: `flutter gen-l10n`, lanciare** `flutter test test/features/calendar/` — Expected: FAIL.
- [ ] **Step 3: Implementare** navigazione, router e schermata.
- [ ] **Step 4: Controlli completi**

Run: `flutter gen-l10n && flutter analyze && flutter test`
Expected: nessun problema, tutti i test verdi.

- [ ] **Step 5: Commit** — `feat(app): calendario con vista "Prossimi 7 giorni" e, sul telefono, l'elenco del giorno sotto la griglia`

---

## Dopo i task

- Revisione finale dell'intero ramo.
- Release build nel worktree e avvio dell'exe (`Start-Process` su `build\windows\x64\runner\Release\wonderflix.exe`) per la prova a mano dell'utente; per il telefono, build web sul sito di prova `/wonderflix-prova/` (vedi `docs/RELEASING.md`).
- Merge su `main` e push solo dopo l'ok dell'utente.
