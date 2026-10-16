# WonderFlix — Piano 22c: match del film, votazione e party

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'ultima parte app della Spec P:
- la votazione: carta da trascinare, pulsanti e tasti, voto ottimista;
- la colonna dei match e dei quasi match, "È un match!", i conteggi dei membri;
- la fine della pila con "Altri 30";
- l'avvio del party con la coda dei match e gli altri membri che entrano da soli;
- la versione 0.16.0, poi la prova a mano e la release (plugin 1.10.0 dal Catalogo, app 0.16.0 obbligatoria).

**Architecture:**
- Il controller della sala (`MatchRoomController`, piano 22b) riceve `vote`, `more` e `party`. Tiene la posizione ottimista (`MatchRoomView.sent`) e non perde più gli stati arrivati durante l'ingresso.
- I titoli della pila li carica un notifier a parte (`MatchTitles`) da `LibraryApi.itemsByIds`.
- La coda del party la costruiscono due funzioni pure-ish in `match_queue.dart`; `startWatchParty` riceve la coda già pronta e un `onRegistered`.
- L'interfaccia sta in `lib/features/match/`: carta (`MatchCard`), mazzo con il gesto (`MatchSwipeDeck`), colonna (`MatchColumn`), festa del match (`MatchCelebration`), più la fase di votazione nella pagina.

**Tech Stack:** Flutter (Windows), Dart, Riverpod 3, go_router, `flutter_test`. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md` (§7.3 "Votazione", "Fine della pila", "Avvia il party", "Rimandato al 22c"; §7.4; §9; §11.2; §11.3; §13). Piani prima: 22a (plugin), 22b (`docs/superpowers/plans/2026-10-16-wonderflix-22b-match-sala-app.md`, sala nell'app).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 6):
1. **Posizione ottimista nel controller.** `MatchRoomView.sent` conta i miei voti mandati; la mia posizione è il massimo tra `sent` e il mio `Voted` nello stato. `vote` controlla che il titolo sia quello della posizione, alza `sent`, poi chiama il plugin. Con `NotNext` si torna ai conteggi del plugin e si rilegge; con un altro errore si torna alla posizione di prima (la carta torna) e la pagina dice "Voto non inviato".
2. **Stati durante l'ingresso** (rimandato dal 22b): mentre `entering`, l'ultimo `MatchUpdatedEvent` arrivato si tiene da parte e si applica appena la sala c'è, se è della stessa sala e più recente.
3. **Le prossime 2 carte** si caricano disegnandole sotto quella in cima (un mazzo di 3, le due sotto un po' più piccole): così le immagini sono già pronte, senza un helper di precaricamento.
4. **`itemsByIds` chiede anche `ChildCount`**, così la riga dei dati di una serie dice le stagioni (`tonightMeta`).
5. **Titoli che il server non restituisce**: `MatchTitles` li segna `null`; quando uno è in cima, la pagina lo vota "no" da sola.
6. **`startWatchParty`** riceve `List<String>? queue` (sostituisce `buildPartyQueue`) e `void Function(String groupId)? onRegistered` (chiamato appena il party è registrato, dentro la registrazione, senza attendere). `matchParty` parte da lì.
7. **Ingresso automatico degli altri membri** dalla pagina della sala (ha il contesto per l'avviso d'errore): stato `Closed` con `PartyGroupId`, se non sono chi ha aperto, `joinWatchParty(groupId)` e poi la pagina si chiude. Per chi ha aperto la pagina resta sotto il player e si chiude all'uscita (piano 22b), come detto nella spec.
8. **Invito riuscito in parte** (rimandato dal 22b): la pagina invita un amico per clic, quindi un 429 vuol dire che quell'amico non è stato invitato: "Non riuscito" è giusto. Nessun cambio.
9. **Carta d'invito al match dentro un watch party** (rimandato dal 22b): `MatchInvites` non la mostra se `watchPartySessionProvider.phase` non è `none`.
10. **"È un match!" solo per i match nuovi**: alla prima vista della votazione i match già usciti contano come visti (aprendo la pagina a votazione iniziata non si festeggiano quelli vecchi).

## Global Constraints

- App **0.16.0** (`pubspec.yaml`), release **obbligatoria**: `<!-- wonderflix:min-version=0.16.0 -->` nelle note. Nessuna dipendenza nuova.
- Gesto: oltre il **30%** della larghezza della carta o con velocità oltre **800 px/s** la carta vola via dal lato del gesto ruotando fino a **±12°**; "SÌ" (verde) / "NO" (rosso) compaiono in proporzione alla distanza; sotto la soglia torna al centro. Animazioni ridotte: niente volo né rotazione, dissolvenza breve (`WfMotion.of(context).duration(...)`, mai durate scritte a mano).
- ✗ e ✓ sotto la carta; ← e → con il focus sulla pagina fanno lo stesso (Alt+← resta "indietro").
- "È un match!": **2 s** per ogni id nuovo in `Matches`, uno dopo l'altro; un tasto o un clic lo chiudono prima.
- Coda del party: primo titolo come "Guarda insieme" (film; serie dal primo episodio con stagione ≥ 1, altrimenti il primo, con i successivi fino a `maxPartyQueue` = 50); poi gli altri match nell'ordine di uscita (film interi, serie con il solo primo episodio); i quasi match solo se scelti come primo; tetto `partyQueueLimit` = 100. `PartyMode.private`, senza menu delle modalità.
- Testi (it/en) della spec §9 per le chiavi di questo piano: `matchYes`, `matchNo`, `matchItsAMatch`, `matchMatches`, `matchNoMatches`, `matchNearMatches`, `matchYesOf(yes, of)`, `matchAllVoted`, `matchMore`, `matchEmpty`, `matchPlaysFirst`, `matchStartParty`, `matchVoteNotSent`.
- Icone `LucideIcons`, colori `WfColors` (il verde e il rosso del gesto come costanti nominate se `WfColors` non li ha), `clock.now()`; nei log mai titoli o nomi.

## Review Focus

1. **Doppio clic o tasto tenuto premuto** su ✓/→ mentre la carta vola: un voto solo per titolo, mai due voti per la stessa carta. Test: Task 3 (`aHeldKeyVotesOncePerCard`).
2. **Voto che non parte (rete o 429)**: la carta torna, si vede "Voto non inviato", e il voto successivo riparte dallo stesso titolo. Test: Task 1 (`aFailedVoteGoesBack`), Task 3 (`aFailedVoteBringsTheCardBack`).
3. **Titolo sparito dalla libreria** in cima alla pila: si salta da solo con un "no", la votazione non si blocca. Test: Task 3 (`aMissingTitleIsVotedNo`).
4. **Serie senza episodi veri o titolo non più disponibile** al momento del party: niente party vuoto; l'avviso e la sala resta aperta. Test: Task 2 (`aSeriesWithoutEpisodesIsSkipped`, `startMatchPartyWithoutTitlesFails`).
5. **Membro che non riesce a entrare nel party** (permessi della libreria): l'avviso di `joinWatchParty` e la pagina si chiude comunque. Test: Task 5 (`aMemberWhoCannotJoinStillLeavesThePage`).

---

## Regole per chi esegue

Come nel piano 22b ("Regole per chi esegue"), con il worktree `.claude/worktrees/piano-22c`:
- commit con l'identità del repository, su una riga, **mai** `Co-Authored-By`, niente push, niente parole che chiudono le issue;
- mai terminare processi per nome d'immagine;
- PowerShell con il PATH rinfrescato; `flutter gen-l10n` dopo ogni ARB (`lib/l10n/gen/` non si committa; in un worktree nuovo va generato prima di tutto);
- prima di ogni commit `flutter analyze` pulito e **`flutter test --concurrency=4`** tutto verde (mai senza `--concurrency=4`); se `windows/flutter/generated_plugin*` cambia solo per i fine riga, `git checkout -- windows/flutter/`;
- base di partenza: **2982** test verdi (`main` `0761beb`, 2026-10-16);
- niente `dart format` su file interi; commenti in italiano, codice in inglese; durate e soglie come costanti nominate;
- se il codice del piano ha un errore (analyzer, firma diversa, icona Lucide con un altro nome), correggilo in modo minimo e segnalalo; meglio correggere il codice che indebolire un test.

## Note tecniche verificate

Sul codice di `main` `0761beb` (2026-10-16):
- `MatchRoomController` (`lib/features/match/match_room_controller.dart`): `open()`, `join(roomId)`, `reload()`, `leave([roomId])`, `invite(userIds)`, `start(TonightFilters)`; `_apply(MatchState)` scarta altre sale e `rev` non più alti; `_enter` cattura `ref` prima delle attese e dà `MatchFailure.conflict` a un secondo ingresso. `start` è il modello per `more`.
- `MatchApi.vote(roomId, itemId, {required bool yes})`, `more(roomId)`, `party(roomId, groupId)` esistono già. `FakeMatchApi` registra `vote r1 m1 yes|no`, `more r1`, `party r1 g1`; `vote` e `party` non cambiano `rooms`; `failures` vale una volta.
- `MatchScreen` (`match_screen.dart`) disegna solo l'attesa; `_onRoom`/`_close` chiudono la pagina solo quando è la rotta in cima. `MatchMembersBar(state:)` mostra avatar e nome.
- `startWatchParty(context, ref, item, {start, mode, invite})` (`watch_party_actions.dart`): chiama `buildPartyQueue` (riga 48), registra il party nel callback `register:` (solo con `mode`), mostra da sé l'avviso d'errore e restituisce `bool`. `joinWatchParty(context, ref, groupId)` uguale. Il player si apre da solo (`watchPartyRoutingProvider`, con `push`).
- `buildPartyQueue(library, userId, item)` e `maxPartyQueue = 50` in `party_queue.dart`; `partyQueueLimit = 100` in `party_queue_rules.dart`.
- `LibraryApi.itemsByIds(userId, ids)`: ordine del server (va rimesso nell'ordine degli id), id mancanti assenti, `fields: 'PrimaryImageAspectRatio,Genres,Overview'` (niente `ChildCount`). `allEpisodes(userId, seriesId)`: episodi veri in ordine stagione/episodio. `FakeLibraryApi`: `itemsById`, `seriesEpisodes`, `itemsByIdsCalls`; `testItem(id:, name:, kind:, seasonIndex:, childCount:, ...)`.
- Immagini: `imageUrlsProvider` → `backdrop(item)`, `poster(item)`; `BackdropImage(backdrop:, fallback:)`; `WfImage(image:)`. Modello di carta: la finestra di "Cosa guardo stasera?" (`tonight_dialog.dart`, circa righe 205–275: sfondo, sfumatura, titolo `WfText.display(32)`, `tonightMeta`, trama).
- Tasti: unico esempio `Focus(onKeyEvent:)` nel player (`player_screen.dart`, handler `_onKey`); `BackNavigationHandler` reagisce solo a Esc, tasto indietro, Alt+← e tasto indietro del mouse: ← e → semplici arrivano alla pagina.
- `WfMotion`: `fast` 150 ms, `medium` 300 ms, `slow` 450 ms, `emphasized`, `isReduced`, `duration(full)`; nei test il movimento è ridotto.
- Release: `docs/RELEASING.md` (app: versione, tag `v0.16.0`, bozza dal workflow, note, riga `min-version`, pubblicazione; plugin: tag `watch-party-plugin-v1.10.0`, voce in `manifest.json`, Catalogo sul server). Il csproj è già 1.10.0; il server ha la build di prova 1.10.0 (backup della 1.9.0 in `~/wfwp-backup/1.9.0.0-catalogo`).

## File

| File | Responsabilità |
|---|---|
| `lib/features/match/match_room_controller.dart` (modifica) | `vote`, `more`, `party`, `sent`, stati durante l'ingresso |
| `lib/core/jellyfin/library_api.dart` (modifica) | `ChildCount` in `itemsByIds` |
| `lib/features/match/match_queue.dart` | ordine dei titoli del party, coda |
| `lib/features/watch_party/watch_party_actions.dart` (modifica) | `queue`, `onRegistered` |
| `lib/features/match/match_actions.dart` (modifica) | `startMatchParty` |
| `lib/features/match/match_titles.dart` | `MatchTitles`, `matchTitlesProvider` |
| `lib/features/match/match_card.dart`, `match_swipe_deck.dart` | carta e mazzo con il gesto |
| `lib/features/match/match_column.dart`, `match_celebration.dart` | colonna, "È un match!" |
| `lib/features/match/match_members_bar.dart`, `match_screen.dart`, `match_invites.dart` (modifiche) | conteggi, votazione, fine pila, party, ingresso automatico, carta d'invito nel party |
| `l10n/app_it.arb`, `l10n/app_en.arb` | testi |
| `pubspec.yaml`, `docs/RELEASING.md`, spec, `docs/IDEE.md` | versione, prova a mano, documenti |

---

## Gruppo A — dati

### Task 1: voto, "Altri 30" e party nel controller

**Files:** Modify `lib/features/match/match_room_controller.dart`; Test `test/features/match/match_room_controller_test.dart` (test nuovi).

**Interfaces:**
- Consumes: `MatchApi.vote/more/party`, `currentUserIdProvider`.
- Produces:
  - `MatchRoomView.sent` (`int`, default 0; `copyWith(sent:)`) e `int position(String userId)` = il massimo tra `sent` e il `voted` del membro `userId` (0 se non c'è);
  - `Future<MatchFailure?> vote(String itemId, {required bool yes})`;
  - `Future<MatchFailure?> more()`;
  - `Future<MatchFailure?> party(String groupId)`.

- [ ] **Step 1: test che falliscono** (con il montaggio del file; `testUser` è `u1`):
  - `votingMovesThePositionAtOnce`: sala in votazione con `stack: ['m1', 'm2']`; `vote('m1', yes: true)` → `null`, `api.calls.last == 'vote r1 m1 yes'`, `room()!.position('u1') == 1` anche prima che arrivi uno stato nuovo.
  - `aVoteForAnotherTitleIsRefused`: `vote('m2', yes: true)` con posizione 0 → `MatchFailure.notNext`, nessuna chiamata `vote`.
  - `aFailedVoteGoesBack`: `api.failures['vote r1 m1 yes'] = MatchException(MatchFailure.network)` → `vote` dà `network` e `position('u1') == 0`; poi `vote('m1', yes: true)` riesce.
  - `notNextRealignsFromThePlugin`: `failures['vote r1 m1 yes'] = notNext`, `rooms['r1']` con `members: [Mario voted 1]` → `vote` dà `notNext`, `api.calls` contiene `state r1`, `position('u1') == 1` (dal plugin), `sent` tornato a 0.
  - `moreAppliesTheNewStack`: `rooms['r1']` con `rev` più alto e `stack` di 3 → `more()` → `null`, `calls.last == 'more r1'`, lo stato ha 3 titoli.
  - `partyCallsThePlugin`: `party('g1')` → `null`, `calls.last == 'party r1 g1'`; fuori da una sala → `MatchFailure.closed`, nessuna chiamata.
  - `aStateArrivingWhileEnteringIsKept`: `api.enterGate` in attesa, `open()` partito, arriva `matchUpdatedReceived(testMatchState(rev: 5, members: [mario, luigi]))`, poi il gate si completa → `room()!.state!.rev == 5`. Uno stato di un'altra sala arrivato intanto non conta.

- [ ] **Step 2:** `flutter test test/features/match/match_room_controller_test.dart` → errori di compilazione (`position`, `vote`, `more`, `party`).

- [ ] **Step 3: il codice.**
  - `vote`: sala aperta in votazione (altrimenti `closed`/`notStarted`); `pos = position(me)`; se `pos >= stack.length` o `stack[pos] != itemId` → `notNext` senza chiamata; `state = copyWith(sent: pos + 1)`, poi `_api.vote(...)`. Con `notNext`: `sent: 0` e `reload()`. Con un altro errore, se la vista è ancora della stessa sala: `sent: pos`. Il `ref` si cattura prima dell'attesa, come in `start`.
  - `more`: come `start` (applica la risposta con `_apply`).
  - `party`: chiama `_api.party`, niente stato.
  - Stati durante l'ingresso: un campo `MatchState? _pendingUpdate`; nel listener di `MatchUpdatedEvent`, mentre `_entering` e senza sala, si tiene il più recente; in `_enter`, appena impostata la sala, si applica con `_apply` se è della stessa sala; si azzera alla fine di `_enter`.

- [ ] **Step 4:** stesso comando → PASS; `flutter analyze`; suite intera.
- [ ] **Step 5:** `git commit -m "feat(app): match votes, more titles and party in the room controller"`

### Task 2: coda del party e `startMatchParty`

**Files:** Create `lib/features/match/match_queue.dart`; Modify `lib/features/watch_party/watch_party_actions.dart`, `lib/features/match/match_actions.dart`; Test `test/features/match/match_queue_test.dart`, `test/features/match/match_party_test.dart`, `test/features/watch_party/watch_party_actions_test.dart` (se c'è; altrimenti nel test del party).

**Interfaces:**
- Consumes: `MatchRoomController.party` (Task 1), `LibraryApi.itemsByIds/allEpisodes`, `maxPartyQueue`, `partyQueueLimit`.
- Produces:
  - `List<String> matchPartyOrder(MatchState state, {String? first})`: `first` (se è un match o un quasi match), altrimenti il primo match, altrimenti il primo quasi match; poi gli altri match nell'ordine di uscita; i quasi match non scelti restano fuori; vuota senza match né quasi match.
  - `Future<List<String>> buildMatchQueue(LibraryApi library, String userId, List<JellyfinItem> titles)`: regole delle Global Constraints; una serie senza episodi si salta; tagliata a `partyQueueLimit`.
  - `startWatchParty(..., {List<String>? queue, void Function(String groupId)? onRegistered})`.
  - `Future<bool> startMatchParty(BuildContext context, WidgetRef ref, {String? first})` (in `match_actions.dart`).

- [ ] **Step 1: test che falliscono.**
  - `match_queue_test.dart`:
    - `theChosenTitleGoesFirst`: `matches: ['a', 'b']`, `nearMatches: [n]` → `matchPartyOrder(state)` = `['a', 'b']`; `first: 'b'` → `['b', 'a']`; `first: 'n'` → `['n', 'a', 'b']`; `first: 'x'` (sconosciuto) → `['a', 'b']`; senza match ma con `n` → `['n']`; vuoto → `[]`.
    - `aSeriesFirstStartsFromItsFirstEpisodeWithTheFollowing`: serie `s1` con episodi `[e0 (stagione 0), e1, e2, e3]` (stagioni 1) → `['e1', 'e2', 'e3', ...]` poi gli altri; con 60 episodi il primo titolo ne mette 50.
    - `laterTitlesAddOneItemEach`: `[film f1, serie s2]` dopo il primo → `f1`, `e1 di s2`.
    - `aSeriesWithoutEpisodesIsSkipped`: serie senza episodi in `seriesEpisodes` → non c'è nella coda (e se è l'unico titolo la coda è vuota).
    - `theQueueStopsAtTheLimit`: primo titolo serie con 50 episodi + 60 film → lunghezza 100.
  - `match_party_test.dart` (con `pumpApp`, `FakeSyncPlayApi` con `onCall` che conferma `create` come nei test del pannello Amici, `socialTestOverrides(... SocialFeatures(friends: true, parties: true, match: true))`, `matchApiProvider`, `libraryApiProvider`):
    - `startMatchPartyStartsAPrivatePartyWithTheMatchesAndTellsThePlugin`: sala in votazione con `matches: ['m1', 'm2']`, `itemsById` con due film → `startMatchParty` → `true`; `syncPlay.queues.single.itemIds` è `['m1', 'm2']`; `social.calls` contiene `register g1 Private`; `match.calls` contiene `party r1 g1`.
    - `aFailingMatchPartyCallKeepsTheParty`: `match.failures['party r1 g1'] = network` → `startMatchParty` → `true`, il party resta (`watchPartySessionProvider.inGroup`).
    - `startMatchPartyWithoutTitlesFails`: i titoli non tornano da `itemsByIds` → `false`, avviso "Non riuscito, riprova", nessun `create`.
  - `startWatchParty` con `queue` e `onRegistered`: la coda data arriva a SyncPlay al posto di quella di `buildPartyQueue`; `onRegistered` riceve il `groupId` dopo `register`.

- [ ] **Step 2:** i test falliscono per compilazione.
- [ ] **Step 3: il codice.** `startWatchParty`: con `queue` non si chiama `buildPartyQueue`; `onRegistered?.call(groupId)` dopo `currentPartyProvider.registered(...)` (con `mode` nullo non c'è registrazione e `onRegistered` non si chiama). `startMatchParty`: prende prima delle attese messenger, container, `l`; stato della sala dal provider; `matchPartyOrder`; `itemsByIds` e riordino per id (titoli mancanti saltati); `buildMatchQueue`; coda vuota → avviso `matchFailed` e `false`; poi `startWatchParty(context, ref, titles.first, mode: PartyMode.private, queue: queue, onRegistered: (g) => unawaited(controller.party(g)))` (un errore di `party` va solo nel log).
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): match party queue and start"`

## Gruppo B — interfaccia

### Task 3: titoli, carta, mazzo e votazione nella pagina

**Files:** Create `lib/features/match/match_titles.dart`, `match_card.dart`, `match_swipe_deck.dart`; Modify `lib/core/jellyfin/library_api.dart`, `lib/features/match/match_screen.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`; Test `test/features/match/match_titles_test.dart`, `match_swipe_deck_test.dart`, `match_screen_test.dart` (test nuovi), `test/core/jellyfin/library_api_test.dart` (riga di `ChildCount`).

**Interfaces:**
- Consumes: `matchRoomProvider`, `MatchRoomController.vote` e `position` (Task 1); `imageUrlsProvider`, `BackdropImage`, `tonightMeta`.
- Produces:
  - `matchTitlesProvider = NotifierProvider<MatchTitles, Map<String, JellyfinItem?>>`: carica (con `itemsByIds`, solo gli id nuovi della pila della sala) e tiene i titoli; `null` = non restituito dal server; si svuota cambiando sala;
  - `MatchCard({required JellyfinItem item})`;
  - `MatchSwipeDeck({required List<JellyfinItem> cards, required ValueChanged<bool> onVote, bool enabled = true})` — `cards[0]` in cima, fino a 3; costanti `matchSwipeThreshold = 0.3`, `matchSwipeVelocity = 800.0`, `matchSwipeMaxAngle` = 12° (in radianti); chiavi `match-yes`, `match-no`, `match-label-yes`, `match-label-no`;
  - testi: le 13 chiavi delle Global Constraints (it/en dalla spec §9).

- [ ] **Step 1: test che falliscono.**
  - `match_titles_test.dart`: `titlesFollowTheStack` (stack `['m1','m2','m3']`, `itemsById` con `m1`, `m3` → mappa `{m1: item, m2: null, m3: item}`; un secondo stato con `m4` in più chiede solo `['m4']` in `itemsByIdsCalls`); `aNewRoomStartsEmpty`.
  - `match_swipe_deck_test.dart` (con `pumpApp`, movimento ridotto e pieno dove indicato):
    - `dragPastTheThresholdVotes`: trascinare la carta di +35% della larghezza → `onVote(true)`; di -35% → `onVote(false)`.
    - `aShortDragGoesBack`: +10% lento → nessun voto, la carta torna al centro.
    - `aFlingVotes`: `fling` verso destra con velocità > 800 → `onVote(true)`.
    - `labelsShowWhileDragging`: a +15% l'opacità di `match-label-yes` è > 0 e < 1, quella di `match-label-no` è 0.
    - `buttonsAndArrowKeysVote`: tap su `match-no` → `false`; tasto → → `true`; tasto ← → `false`.
    - `aHeldKeyVotesOncePerCard`: due → di fila prima che l'animazione finisca (movimento pieno) → un solo `onVote`.
    - `reducedMotionStillVotes`: con movimento ridotto il tap su `match-yes` vota.
  - `match_screen_test.dart`:
    - `theVotingPageShowsTheTopCard`: sala in votazione `stack: ['m1','m2']` con i titoli → si vede il titolo di `m1`; tap su `match-yes` → `match.calls` contiene `vote r1 m1 yes` e si vede `m2`.
    - `aFailedVoteBringsTheCardBack`: `failures['vote r1 m1 yes'] = network` → dopo il tap si vede di nuovo `m1` e "Voto non inviato".
    - `aMissingTitleIsVotedNo`: `m1` non in `itemsById` → `vote r1 m1 no` parte da solo e si vede `m2`.
  - `library_api_test.dart`: la query di `itemsByIds` ha `ChildCount` tra i `fields`.

- [ ] **Step 2:** falliscono per compilazione.
- [ ] **Step 3: il codice.**
  - `MatchCard`: come la carta di "Cosa guardo stasera?" (sfondo `BackdropImage`, sfumatura, titolo, `tonightMeta`, trama su 3 righe).
  - `MatchSwipeDeck`: `GestureDetector` orizzontale sulla carta in cima; `Transform` con traslazione e rotazione proporzionali (fino a ±12° alla soglia); etichette con opacità = distanza / soglia (limitata a 1); a voto deciso la carta vola via con un'animazione (`WfMotion.medium`, `emphasized`) e solo alla fine chiama `onVote`; mentre vola i voti nuovi si ignorano (un voto per carta); con `isReduced` niente volo né rotazione, dissolvenza `fast`. `Focus(autofocus: true, onKeyEvent:)`: solo `KeyDownEvent` senza Alt; ← no, → sì. Le carte 2 e 3 stanno sotto, scalate (0.96, 0.92).
  - Pagina, fase `voting`: righe a sinistra il mazzo, a destra la colonna (Task 4 la riempie; qui uno spazio vuoto). Le carte = i titoli della pila dalla mia posizione; se in cima c'è un `null` → `vote(id, yes: false)` dopo il frame. `onVote` → `vote(...)`; un errore diverso da `notNext` → avviso `matchVoteNotSent`.
- [ ] **Step 4:** PASS (i test della pagina dell'attesa restano verdi); analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): match voting card with swipe, buttons and keys"`

### Task 4: colonna dei match, "È un match!" e conteggi

**Files:** Create `lib/features/match/match_column.dart`, `match_celebration.dart`; Modify `match_members_bar.dart`, `match_screen.dart`; Test `match_column_test.dart`, `match_celebration_test.dart`, `match_screen_test.dart`, `match_members_bar_test.dart`.

**Interfaces:**
- Consumes: `matchTitlesProvider` (Task 3).
- Produces:
  - `MatchColumn({required MatchState state, required Map<String, JellyfinItem?> titles, String? chosen, ValueChanged<String>? onChoose})`: "Match" con locandina e titolo nell'ordine di `matches`; vuota → `matchNoMatches`; sotto, se ci sono, `matchNearMatches` con `matchYesOf(yes, of)`; la voce `chosen` dice `matchPlaysFirst`; `onChoose` nullo = voci non cliccabili. Chiavi `match-column-<id>`.
  - `MatchCelebration({required JellyfinItem? item, required VoidCallback onDone})`: strato con la locandina e `matchItsAMatch` in oro; dopo `matchCelebrationDuration` (2 s) o a un tasto/clic chiama `onDone`.
  - `MatchMembersBar`: in votazione, accanto al nome `"{voted}/{stack.length}"` e ✓ (`LucideIcons.check`) quando `voted >= stack.length` con pila non vuota.

- [ ] **Step 1: test che falliscono.**
  - `match_column_test.dart`: `matchesInOrderAndNearMatchesWithCounts` (due match, un quasi match "1 su 2"); `emptySaysNoMatches`; `chooseMarksPlaysFirst` (tap su un quasi match con `onChoose` → callback con l'id; con `chosen` si vede "Parte per primo"); `withoutOnChooseNothingIsClickable`.
  - `match_celebration_test.dart`: `itGoesAwayAfterTwoSeconds` (`pump(matchCelebrationDuration)` → `onDone` una volta); `aTapOrKeyClosesItEarlier`.
  - `match_members_bar_test.dart`: `countsAndCheckWhileVoting` (`voted: 1` su una pila di 2 → "1/2"; `voted: 2` → ✓); in attesa nessun conteggio.
  - `match_screen_test.dart`:
    - `aNewMatchIsCelebratedOnce`: in votazione, arriva lo stato con `matches: ['m1']` → si vede "È un match!"; dopo 2 s sparisce; un altro stato con lo stesso match non lo rimostra.
    - `twoNewMatchesOneAfterTheOther`: arrivano insieme `m1`, `m2` → prima l'uno, poi l'altro.
    - `oldMatchesAreNotCelebratedWhenOpeningThePage`: la sala ha già `matches: ['m1']` quando la pagina si apre → niente strato.
- [ ] **Step 2:** falliscono per compilazione.
- [ ] **Step 3: il codice.** La pagina tiene gli id già visti (inizializzati alla prima vista della votazione, decisione 10) e una coda di quelli nuovi; mostra `MatchCelebration` sopra il mazzo per il primo della coda.
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): match column, celebration and vote counts"`

### Task 5: fine della pila, avvio del party, ingresso automatico

**Files:** Modify `lib/features/match/match_screen.dart`, `lib/features/match/match_invites.dart`; Test `match_screen_test.dart`, `match_invites_test.dart`.

**Interfaces:**
- Consumes: `MatchRoomController.more`, `position` (Task 1); `startMatchParty` (Task 2); `MatchColumn` (Task 4); `joinWatchParty`.

- [ ] **Step 1: test che falliscono** (`match_screen_test.dart`, con `FakeSyncPlayApi` e i fake del party dove serve):
  - `allVotedWaitsForTheOthers`: posizione = lunghezza pila, un altro membro non ha finito → "Hai votato tutto, aspetta gli altri", nessun "Altri 30 titoli".
  - `whenEveryoneHasFinishedTheCreatorGetsMore`: tutti `voted == stack.length` → chi ha aperto vede "Altri 30 titoli" → tap → `more r1`; un membro non lo vede.
  - `anEmptyStackSaysNoTitles`: votazione con pila vuota → "Nessun titolo con questi filtri" (e "Altri 30 titoli" per chi ha aperto).
  - `startPartyNeedsAMatchAndUsesTheChosenFirst`: senza match né quasi match nessun "Avvia il party"; con `matches: ['m1','m2']`, tap su `match-column-m2` → "Parte per primo", tap su "Avvia il party" → la coda parte con `m2`; il pulsante è spento mentre parte.
  - `membersJoinThePartyByThemselves`: sono Luigi (sala aperta da Mario), arriva lo stato `Closed` con `PartyGroupId: 'g1'` e `closedReason: partyStarted` → `syncPlay.calls` contiene `join g1`, la pagina si chiude senza "Sala chiusa".
  - `aMemberWhoCannotJoinStillLeavesThePage`: `syncPlay.error` sul `join` → l'avviso di `joinWatchParty` e la pagina si chiude.
  - `match_invites_test.dart`: `noMatchInviteInsideAWatchParty` (con la sessione del party in `inGroup` o `joining`, un `MatchInvite` non si mostra).
- [ ] **Step 2:** falliscono.
- [ ] **Step 3: il codice.**
  - Fine della pila nella colonna di sinistra al posto del mazzo, con i testi della spec; "Altri 30 titoli" (`WfButton.secondary`) solo per chi ha aperto quando tutti hanno finito; errori → `matchFailureText`.
  - "Avvia il party" (`WfButton.primary`, chiave `match-start-party`) sotto la colonna, per chi ha aperto, con almeno un match o un quasi match; la scelta del primo è uno stato della pagina passato alla colonna (`onChoose`); durante `startMatchParty` spento.
  - `_onRoom`: stato `Closed` con `partyGroupId` e io non sono chi ha aperto → `unawaited(joinWatchParty(context, ref, groupId))` prima di chiudere la pagina (niente avviso "Sala chiusa", come oggi).
  - `MatchInvites._show`: esce anche se `watchPartySessionProvider.phase != WatchPartyPhase.none`.
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): match end of stack, party start and members auto-join"`

## Gruppo C — chiusura

### Task 6: versione 0.16.0, documenti e build

- [ ] `pubspec.yaml`: `version: 0.16.0`.
- [ ] `docs/RELEASING.md`: nella lista della prova a mano, dopo "Cosa guardo stasera?", una voce "Match del film" (sala, inviti, voti, match, avvio del party con due istanze).
- [ ] Spec: Stato ("piano 22c realizzato"), §7.3 con le decisioni 1–10 di questo piano dove cambiano il comportamento (posizione ottimista, stati durante l'ingresso, mazzo di 3, `ChildCount`, titoli mancanti votati "no", `onRegistered`, ingresso automatico dalla pagina, invito parziale, carta d'invito nel party, festa solo per i match nuovi), "Rimandato al 22c" risolto, §13 22c realizzato.
- [ ] `flutter analyze`, suite intera, build di release (`config/wonderflix.json` copiato dal checkout principale, non si committa): `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- [ ] `git commit -m "chore: app 0.16.0 and spec aligned with plan 22c"`

### Task 7: STOP — prova a mano con l'utente

Dopo la review finale del branch e i ritocchi. Due istanze (`WONDERFLIX_PROFILE=b`), due utenti amici, exe di release del worktree, plugin 1.10.0 di prova sul server. Spec §11.3: apertura e invito (carta e cassetta), "Inizia", voti con il gesto, i pulsanti e i tasti, un match e un no, "È un match!", uscita di un membro, "Altri 30", quasi match, scelta del primo e avvio del party con ingresso automatico dell'altro, chiusura della sala da parte di chi l'ha aperta, filtri che danno una pila vuota.

### Task 8: ok dell'utente e merge

Con l'ok dell'utente: `git fetch`, merge fast-forward su `main`, push.

## Release (con l'OK dell'utente a ogni passo)

1. **Plugin 1.10.0** (`docs/RELEASING.md`, parte del plugin): tag `watch-party-plugin-v1.10.0` e push; il workflow pubblica la pre-release con lo zip e l'md5; voce `1.10.0.0` in cima a `jellyfin-plugin-watch-party/manifest.json` (changelog in inglese breve sul match, `sourceUrl`, `checksum` dal file md5, `timestamp`), commit e push. Sul server: controllare che nessuno guardi (o solo sessioni in pausa da molto), fermare Jellyfin, spostare la build di prova in `~/wfwp-backup/1.10.0.0-prova`, avviare, installare 1.10.0.0 dal Catalogo, riavviare, controllare `Info` 1.10.0 con `match` e il log.
2. **App 0.16.0**: tag `v0.16.0` e push; il workflow crea la bozza con `WonderFlix-Setup-0.16.0.exe` e `.sha256`; note in italiano scritte da me nella bozza con la riga `<!-- wonderflix:min-version=0.16.0 -->`; la pubblica l'utente.
3. **Alla fine:** in `docs/IDEE.md` l'idea 9 esce e tra le fatte va "Spec P — match del film (plugin 1.10.0, app 0.16.0)"; Stato della spec "Realizzata"; commit e push.
