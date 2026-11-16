# "Cosa guardo stasera?" e Match, nuova UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La spec: filtri come frase, finestra "Cosa guardo stasera?" col titolo al centro e i già proposti, sala Match con posti, regole, voto con comandi grandi e match come biglietti.

**Architecture:** Un modello puro della frase (`askParts`) e un widget `AskSentence` sostituiscono `TonightFiltersBar` in finestra e sala. La forma del biglietto si estrae da `ticket_card.dart` in `ui/ticket_shape.dart` e serve ai biglietti dei match e a "È un match!". La sala usa `MatchSeats` al posto di `MatchMembersBar`. Nessun cambio al plugin né ai controller, salvo `TonightController.restore`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter.

**Spec:** `docs/superpowers/specs/2026-11-16-stasera-match-ui-design.md` (bozza `docs/superpowers/specs/2026-11-16-stasera-match-bozze/stasera-match.html`). Leggila prima di ogni task: i § qui sotto sono i suoi.

## Global Constraints

- Worktree `C:\Users\sidot\Documents\Github\wonderflix\.claude\worktrees\home-ui` (branch `worktree-home-ui`, contiene la Home nuova non ancora unita), comandi Flutter da `app/`. Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Dopo ogni modifica agli `.arb`: `flutter gen-l10n`.
- Controlli di ogni task: `flutter analyze` (nessun problema), `flutter test test/features/tonight test/features/match test/features/home test/ui` più i test del task. L'ultimo task fa girare `flutter test` intero.
- Stile invariato: `WfColors`, `WfText.display` (Bebas Neue), Inter; nessun colore nuovo (sì = `WfColors.online`, no = `WfColors.error`).
- Fuori dalla TV il comportamento TV non cambia, e viceversa (`FormFactor.of(context).tv`). Match resta fuori dalla TV.
- Testi nuovi in `app/l10n/app_it.arb` e `app/l10n/app_en.arb`.
- Codice in inglese, commenti e commit in italiano. Commit senza `Co-Authored-By` né "Generated with"; mai `closes`, `fixes`, `resolves`. Messaggio in un file senza BOM, `git commit -F <file>`. `git checkout -- app/windows/flutter/` prima di committare.
- `dart format` solo sulle righe che cambi.
- Mai fermare processi per nome d'immagine; solo per PID, solo i tuoi.
- riverpod 3.x. Widget test larghi: anche `tester.view.physicalSize`. Niente `pumpAndSettle` con animazioni infinite.

## Review Focus

1. **Frase grammaticalmente sbagliata** in qualche combinazione (genere femminile con le serie, plurale nella sala, durata assente con "serie", "un film o una serie" + voto). Task 1 testa tutte le combinazioni tipo × voto × voce.
2. **"Già proposti" fuori sincrono** dopo un errore o un "nessun titolo": un titolo che non c'è non deve finire nella fila. Task 3.
3. **TV**: il focus nella finestra deve partire da "Un altro" e raggiungere ogni parola della frase; un menu aperto da una parola si chiude con Back senza chiudere la finestra. Task 2 e 3.
4. **Overflow** nella finestra (nomi lunghi, trama lunga, frase lunga con un genere lungo) e nella sala (8 posti, nomi lunghi) a 1280×800 e 390×780. Test in task 3, 5, 6.
5. **Biglietti dei match senza titolo** (id che il server non dà: `titles[id] == null`): biglietto con nome vuoto e senza eccezioni. Task 6.

---

### Task 1: Generi tradotti e modello della frase

Spec §3.1, §6.

**Files:**
- Modify: `app/lib/features/tonight/tonight_logic.dart` (`tonightMeta`)
- Create: `app/lib/features/tonight/ask_parts.dart`
- Modify: `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/tonight/tonight_logic_test.dart`, `app/test/features/tonight/ask_parts_test.dart` (nuovo)

**Interfaces:**
- Produces:
  ```dart
  enum AskVoice { tonight, match }
  enum AskSlot { type, duration, genre, rating }
  class AskPart { const AskPart(this.text, {this.slot}); final String text; final AskSlot? slot; }
  List<AskPart> askParts(TonightFilters filters, AskVoice voice, AppLocalizations l);
  String askMenuLabel(AskSlot slot, Object value, AppLocalizations l); // voci del menu (§3.2)
  ```
  I pezzi senza `slot` sono testo fisso ("Stasera ", ", ", "."); quelli con `slot` sono le parole che si cambiano.
- Chiavi l10n con prefisso `ask` (nomi a scelta, testi della spec §3.1 e §3.2; inglese: "Tonight " / "Voting on ", "a movie" / "a series" / "a movie or a series", "movies" / "series" / "movies and series", "of any length" / "under 90 minutes" / "under 2 hours", "of any genre" / "{genre}", "with any rating" / "rated well" / "rated badly"; menu "Movies", "Series", "Movies and series", "Any length", "Under 90 minutes", "Under 2 hours", "All genres", "Any rating", "Good (7+)", "Bad (5 or less)").

- [ ] **Step 1: Test che falliscono.**
  - `tonight_logic_test`: `tonightMeta` di una serie 2021, 1 stagione, generi `['Science Fiction', 'Drama', 'Thriller']` → "2021 · 1 stagione · Fantascienza · Dramma · Thriller"; generi `['Drama', 'Dramma', 'Horror', 'Comedy']` → tre generi tradotti senza doppioni ("Dramma · Horror · Commedia").
  - `ask_parts_test` (it), unendo i testi:
    - tonight, film, qualsiasi, tutti, brutti → "Stasera un film di qualsiasi durata, di ogni genere, brutto."
    - tonight, serie, (durata ignorata), genere "Horror", belli → "Stasera una serie, di genere Horror, bella."
    - tonight, entrambi, sotto 2 ore, tutti, qualsiasi → "Stasera un film o una serie sotto le 2 ore, di ogni genere, con qualsiasi voto."
    - match, serie, tutti, brutti → "Si vota tra serie, di ogni genere, brutte."
    - match, film, sotto 90, tutti, belli → "Si vota tra film sotto i 90 minuti, di ogni genere, belli."
    - con "serie" nessun pezzo ha `slot: AskSlot.duration`; negli altri tipi c'è; i pezzi con slot sono 3 o 4 nell'ordine type, duration, genre, rating.
    - `askMenuLabel(AskSlot.rating, TonightRating.bad, l)` → "Brutti (5 o meno)".
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa.** `tonightMeta`: generi via `genreLabel`, `toSet`, `take(tonightMetaGenres)`. `askParts` costruisce i pezzi secondo §3.1 (spazi e virgole come negli esempi).
- [ ] **Step 4:** PASS + `flutter analyze`.
- [ ] **Step 5: Commit** `feat(app): frase dei filtri e generi tradotti in Stasera`.

### Task 2: Widget `AskSentence` al posto di `TonightFiltersBar`

Spec §3.1, §3.2.

**Files:**
- Create: `app/lib/features/tonight/ask_sentence.dart`
- Modify: `app/lib/features/tonight/tonight_dialog.dart`, `app/lib/features/match/match_screen.dart` (solo lo scambio del widget)
- Delete: `app/lib/features/tonight/tonight_filters_bar.dart` (e i suoi test; sposta il comportamento "genere che non c'è più → tutti" in `AskSentence`)
- Modify: `.arb` (togli le chiavi dei segmenti non più usate, se `grep` non trova altri usi)
- Test: `app/test/features/tonight/ask_sentence_test.dart` (nuovo), test esistenti di finestra e sala che cercavano i segmenti

**Interfaces:**
- Consumes: Task 1 (`askParts`, `askMenuLabel`, `AskVoice`, `AskSlot`).
- Produces: `AskSentence({required TonightFilters filters, required AskVoice voice, ValueChanged<TonightFilters>? onChanged, double fontSize = 21})`. `onChanged == null` = sola lettura. Chiavi dei pulsanti: `Key('ask-type')`, `Key('ask-duration')`, `Key('ask-genre')`, `Key('ask-rating')`.

- [ ] **Step 1: Test che falliscono** (`ask_sentence_test`):
  - mostra il testo della frase (`RichText`/`Text.rich` o `Wrap`: verifica col testo visibile) e i 4 pulsanti; con tipo serie 3 pulsanti, senza `ask-duration`;
  - tap su `ask-rating` → menu con "Qualsiasi voto", "Belli (7 o più)", "Brutti (5 o meno)"; scelta "Belli" → `onChanged` con `rating: good`;
  - tap su `ask-genre` → "Tutti i generi" e i generi di `tonightGenresProvider` (override); un genere salvato che non è nella lista → `onChanged` con `genre: null`;
  - sola lettura: nessun pulsante, testo presente;
  - TV (`FormFactorScope(tv: true)`): il primo pulsante prende il focus con `requestFocus`, Destra passa al successivo, OK (`LogicalKeyboardKey.select`) apre il menu, Back lo chiude e il focus torna sulla parola;
  - a 390 di larghezza la frase va a capo senza overflow.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa.** Testo Inter `fontSize`, `creamMuted`; parole crema w600 con sottolineatura oro 2 px e freccia oro (`LucideIcons.chevronDown` 14) in `PopupMenuButton` (`popUpAnimationStyle: wfPopUpAnimation(context)`); voce scelta in oro. Layout `Wrap` con i pezzi di testo spezzati in parole, così la frase va a capo come testo. Nella finestra e nella sala, per ora, lo scambio 1:1 al posto della barra (`AskVoice.tonight` nella finestra, `AskVoice.match` nella sala, `fontSize: 19`); il layout nuovo arriva nei task 3 e 5.
- [ ] **Step 4:** PASS (anche `test/features/match`, `test/features/home`).
- [ ] **Step 5: Commit** `feat(app): i filtri di Stasera e Match diventano una frase`.

### Task 3: La finestra "Cosa guardo stasera?"

Spec §4.

**Files:**
- Modify: `app/lib/features/tonight/tonight_dialog.dart`, `app/lib/features/tonight/tonight_controller.dart`, `.arb`
- Test: `app/test/features/tonight/tonight_dialog_test.dart` (e il controller test se c'è)

**Interfaces:**
- Consumes: Task 2 (`AskSentence`).
- Produces: `TonightController.restore(JellyfinItem item)` (mette `pick = AsyncData(item)` senza leggere; segna l'id come visto come fa la pesca). Costanti: `tonightDialogWidth = 760`, `tonightPickHeight = 258`, `tonightPosterWidth = 172` (TV 140), `tonightHistoryMax = 3`.
- Chiavi l10n: `tonightWhyMovie` "Un film che non hai mai visto" / "A movie you haven't seen", `tonightWhySeries` "Una serie che non hai mai iniziato" / "A series you haven't started", `tonightHistory` "Già proposti" / "Already suggested".

- [ ] **Step 1: Test che falliscono:**
  - layout desktop: locandina (larga 172) a sinistra del nome; perché "Un film che non hai mai visto" per un film, "Una serie che non hai mai iniziato" per una serie; nome in `WfText.display(46)`; riga dei dati con generi tradotti; la frase sopra; niente `SegmentedButton`;
  - "Un altro": il titolo di prima compare in "Già proposti" (una locandina con `Key('tonight-history-<id>')`); dopo 4 pescate ce ne sono 3, le più recenti; un tap su una locandina la rimette come titolo e il titolo di prima va in fondo;
  - cambiare un filtro svuota "Già proposti";
  - un "Un altro" che finisce in "nessun titolo" o errore non mette nulla in "Già proposti" oltre al titolo che c'era;
  - con le animazioni ridotte (`MediaQuery(disableAnimations: true)`) nessuna animazione di entrata (il titolo è subito a opacità 1);
  - stretto (390×780): pagina, locandina a tutta larghezza (alta al massimo 330), "Un altro" e "Riproduci" nella stessa riga e "Dettagli" sotto; nessun overflow con nome e trama lunghi;
  - TV: all'apertura il focus è su "Un altro" (`Key('tonight-another')`); Su porta a una parola della frase; finestra larga 680.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa** secondo §4.1–§4.4: intestazione (dado oro + titolo Inter 15 w600 `creamMuted`, il dado non gira più), frase, spazio del titolo alto almeno `tonightPickHeight` con locandina (`urls.poster`), perché, nome, dati con voto, trama 4 righe; fondale in cima alla finestra (`urls.backdrop`, opacità 0,35, `ShaderMask` verso il basso, alto 300, cambia con dissolvenza); piede con linea, "Già proposti" (stato della finestra: lista di `JellyfinItem`, max 3) e i tre pulsanti; il dado nel pulsante "Un altro" fa un giro a ogni pescata; il titolo nuovo entra salendo di 14 px in dissolvenza in 450 ms (`WfMotion.emphasized`), niente con le animazioni ridotte.
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(app): finestra Cosa guardo stasera col titolo al centro e i già proposti`.

### Task 4: Forma del biglietto e posti della sala

Spec §5.2, §5.5 (forma), §5.7 (forma).

**Files:**
- Create: `app/lib/ui/ticket_shape.dart`
- Modify: `app/lib/ui/ticket_card.dart` (usa `ticket_shape.dart`, comportamento identico)
- Create: `app/lib/features/match/match_seats.dart`
- Modify: `.arb`
- Test: `app/test/ui/ticket_card_test.dart` (resta verde), `app/test/features/match/match_seats_test.dart` (nuovo)

**Interfaces:**
- Produces:
  ```dart
  // ui/ticket_shape.dart
  const ticketNotchRadius = 7.0;
  class TicketClipper extends CustomClipper<Path> { const TicketClipper.vertical(this.at, {this.radius = 8}); const TicketClipper.horizontal(this.at, {this.radius = 8}); ... }
  class TicketTearPainter extends CustomPainter { const TicketTearPainter.vertical(this.at); const TicketTearPainter.horizontal(this.at); ... } // tratteggio #333
  // features/match/match_seats.dart
  const matchMaxMembers = 8;
  class MatchSeats extends StatelessWidget { const MatchSeats({super.key, required this.state, this.me}); final MatchState state; final String? me; }
  ```
- Chiavi l10n: `matchSeatsCount` "In sala, {n} su {max}" / "In the room, {n} of {max}", `matchSeatFree` "libero" / "free", `matchVotedOf` "{n} su {total}" / "{n} of {total}", `matchDone` "finito" / "done".

- [ ] **Step 1: Test che falliscono:**
  - `ticket_card_test` esistenti verdi dopo il refactor (nessun cambio di misure o chiavi);
  - `match_seats_test`: in attesa con 1 membro → 8 posti, 7 "libero", "In sala, 1 su 8"; in votazione con 2 membri (voti 12 e 30, pila 30) → solo 2 posti, "12 su 30" e "finito", barra del primo al 40%; nomi lunghi senza overflow a 390 di larghezza (i posti vanno a capo).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa.** Sposta clipper e pittore del biglietto in `ticket_shape.dart` con le varianti orizzontali. `MatchSeats` secondo §5.2 (posto largo 68, poltrona 56×62 angoli 14/6 con barretta sotto, avatar `UserAvatar.lookup` 36, bordo oro se occupato e tratteggiato `border` se libero, nome 11,5, barra 3 px e testo sotto in votazione; spazio 8 tra i posti, `Wrap`).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(app): forma del biglietto in comune e posti della sala Match`.

### Task 5: La sala in attesa

Spec §5.1, §5.3.

**Files:**
- Modify: `app/lib/features/match/match_screen.dart`, `.arb`
- Delete: `app/lib/features/match/match_members_bar.dart` se non lo usa più nessuno (e il suo test)
- Test: `app/test/features/match/match_screen_test.dart` (o dove sono i test della sala)

**Interfaces:**
- Consumes: Task 2 (`AskSentence`, `AskVoice.match`), Task 4 (`MatchSeats`), `WfButton.secondary(small: true)`.
- Chiavi l10n: `matchPageTitle` "Match" / "Match", `matchLead` (testo §5.1; en "Vote on the same titles, each on your own: the ones everybody likes become a match. Whoever opened the room picks where to start."), `matchVoteAmong` "Si vota tra" / "Voting on", `matchNoLateJoin` "Dopo l'inizio non entra più nessuno" / "Nobody can join after the start". `matchTitle` resta per il pannello Amici.

- [ ] **Step 1: Test che falliscono:**
  - titolo "MATCH" (o "Match" in Bebas) e la riga delle regole;
  - chi ha aperto: posti con "In sala, 1 su 8"; amico online con "Invita" a meno di 24 px dal bordo destro del nome-blocco (cioè subito dopo il nome, non sul bordo della pagina: verifica che `dx` di "Invita" sia minore della metà della larghezza a 1280); "Inizia" spento con "Serve almeno un amico nella sala"; con 2 membri acceso con "Dopo l'inizio non entra più nessuno"; la frase con `AskVoice.match`;
  - chi è entrato: niente frase, "In attesa che {nome} inizi…" nel riquadro;
  - 1280: due colonne (posti a sinistra del riquadro); 390: una sotto l'altra; nessun overflow con 8 membri dai nomi lunghi.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa** secondo §5.1 e §5.3 (titolo Bebas 56 / 40 nello stretto, riga regole `creamMuted` 14 larga al massimo 560, colonne 1,25/1 distanza 48, riquadro `surface` bordo `border` angoli 10 padding 20/22, riga amico: avatar 32, nome con larghezza minima 160, poi "Invita"/"Invitato").
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(app): sala Match con posti, regole e Invita accanto al nome`.

### Task 6: La votazione, i biglietti dei match ed "È un match!"

Spec §5.4–§5.7.

**Files:**
- Modify: `app/lib/features/match/match_screen.dart`, `match_swipe_deck.dart`, `match_card.dart`, `match_column.dart`, `match_celebration.dart`, `.arb`
- Create: `app/lib/features/match/match_ticket.dart`
- Test: test esistenti di mazzo, colonna, festa e sala; `app/test/features/match/match_ticket_test.dart` (nuovo)

**Interfaces:**
- Consumes: Task 4 (`TicketClipper`, `TicketTearPainter`, `MatchSeats`).
- Produces: `MatchTicket({required String id, required JellyfinItem? item, required bool chosen, String? note, VoidCallback? onTap, double width = 360})`: alto 84, fondale 150 (104 se `width < 300`), riga "Film · 1h 49m" / "Serie · 1 stagione" (o `note`, o "Parte per primo" in oro se `chosen`), bordo oro se `chosen`.
- Chiavi l10n: `matchLikedByAll` "Piaciuti a tutti" / "Liked by everyone", `matchCount` "{n} match" / "{n} matches" (plurale en), `matchNearOf` "{yes} sì su {of}" / "{yes} yes of {of}", `matchStartPartyWith` plurale "Avvia il party con {n} titoli" / "=1: Avvia il party con 1 titolo" (en "Start the party with {n} titles" / "1 title"), `matchLeft` "Ne restano {n}" / "{n} left", `matchNoKey` "No · ←", `matchYesKey` "Sì · →", `matchLikedByEveryone` "Piace a tutti" / "Everybody likes it", `matchYou` "Tu {n} su {total}" / "You {n} of {total}", `matchFriendDone` "{name} ha finito" / "{name} is done", `matchFriendVoted` "{name} {n} su {total}". Togli le chiavi che non servono più (`matchMatches`, `matchYesOf`, `matchStartParty`...) se `grep` non trova altri usi.

- [ ] **Step 1: Test che falliscono:**
  - carta: rapporto 2:3, larga 270 a 1280 (250 nello stretto), nome Bebas 34, dati con generi tradotti;
  - pulsanti tondi 64×64 con "No · ←" e "Sì · →" sotto (desktop), senza scritte nello stretto; "Ne restano 18" con pila 30 e 12 votati;
  - durante il trascinamento compare il timbro "SÌ"/"NO" (testo presente, colore `WfColors.online`/`error`);
  - colonna: "Piaciuti a tutti" e "2 match"; il primo biglietto scelto ha "Parte per primo"; tap su un altro (chi ha aperto) lo sceglie; quasi match con "1 sì su 2"; pulsante "Avvia il party con 2 titoli" (con un quasi match scelto come primo: 3 titoli; con un solo match: "con 1 titolo"); senza match "Ancora nessun match";
  - `match_ticket_test`: `item == null` → nessuna eccezione, nome vuoto; film → "Film · 1h 49m"; serie → "Serie · 1 stagione";
  - posti in alto a destra del titolo in votazione (desktop); nello stretto avatar 30 e la riga "Tu 12 su 30 · sara.lippolis ha finito";
  - "È un match!": biglietto con la locandina, il nome e "Piace a tutti"; con animazioni ridotte nessuna scala;
  - nessun overflow a 1280×800 e 390×780.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: Implementa** secondo §5.4–§5.7: carta verticale (locandina `urls.poster`, sfumatura, nome, dati, trama 3 righe), carte sotto ruotate ±4° scala 0,95 più scure; timbri; pulsanti tondi (bordo 2 del colore al 60%, fondo `surface`, distanza 44, 56 nello stretto); "Ne restano"; colonna larga 360 distanza 40 con intestazione Bebas 26, biglietti `MatchTicket` (stretto: fila orizzontale da 250), "Piaciuti a quasi tutti" Inter 12,5 w600, quasi match al 75%, pulsante a tutta larghezza alto 44; "È un match!" con biglietto (`TicketClipper.horizontal`, locandina 2:3 larga 260, bordo oro, entrata da scala 0,8 con −4° in 500 ms).
- [ ] **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(app): voto del Match con carta grande, biglietti dei match ed È un match nuovo`.

### Task 7: Checklist e controllo finale

Spec §9.

**Files:**
- Modify: `docs/RELEASING.md`

- [ ] **Step 1:** in `docs/RELEASING.md`, tra le righe della 0.42.0, una riga nel formato delle vicine: "Stasera e Match nuovi (app 0.42.0): filtri come frase (con \"serie\" niente durata, generi in italiano), titolo con locandina e perché, Un altro con i già proposti (clic per riprenderli); sala Match con regole, posti, Invita accanto al nome; voto con carta verticale, pulsanti grandi e ← →, match come biglietti, \"Avvia il party con N titoli\", È un match nuovo; telefono; TV: focus su Un altro e parole della frase raggiungibili."
- [ ] **Step 2:** `flutter gen-l10n`, `flutter analyze`, `flutter test` (tutto) → PASS. Se un test fuori da Stasera/Match si rompe, correggilo secondo la spec.
- [ ] **Step 3: Commit** `docs: checklist di Stasera e Match nuovi`.
