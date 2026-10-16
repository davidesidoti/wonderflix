# WonderFlix — Piano 22b: match del film, la sala nell'app

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la prima parte app della Spec P:
- il nucleo: modelli, chiamate del plugin con il motivo dei 409, avvisi `MatchInvite`/`MatchUpdated`, funzione `match`;
- la sala nell'app (`matchRoomProvider`): apertura, ingresso, stato sempre più recente, riletture, uscita;
- la pagina `/match/:id` in attesa: membri, filtri, amici da invitare, "Inizia";
- gli ingressi: "Match" in Home e "Match del film" nel pannello Amici;
- gli inviti: la carta in alto a destra e la voce nella cassetta;
- l'uscita dalla sala lasciando la pagina e cambiando profilo.

La votazione (carta da trascinare, match, avvio del party, versione 0.16.0) arriva nel piano 22c.

**Architecture:**
- Nucleo in `lib/core/social/`:
  - `match_models.dart` (stato della sala);
  - `match_api.dart` (`MatchApi`, che lancia `MatchException` con il motivo del 409 e, per `InAnotherRoom`, l'id della propria sala).
- Gli avvisi vanno in `social_models.dart`, la voce in `inbox_models.dart`.
- La sala dell'app è una sola (il plugin ne tiene una per utente): `MatchRoomController` (`lib/features/match/match_room_controller.dart`). Tiene la vista della sala, accetta solo stati con `Rev` più alto, rilegge alla riconnessione, esce.
- L'interfaccia sta in `lib/features/match/`:
  - pagina, membri, azioni d'ingresso, pulsante e disponibilità degli ingressi;
  - inviti, con la cornice della carta estratta dalla carta d'invito al party;
  - i filtri, estratti da "Cosa guardo stasera?" e usati da tutte e due.

**Tech Stack:** Flutter (Windows), Dart, Riverpod 3 (`Notifier`), go_router, dio (`JellyfinHttp`), `flutter_test`, `fake_async`. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md` (§3, §6.4–6.5, §7.1–7.3, §8, §9, §11.2, §13). Il plugin è già fatto (piano 22a, `docs/superpowers/plans/2026-10-14-wonderflix-22a-match-plugin.md`): build di prova 1.10.0 sul server.

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 8):
1. **`MatchApi` a parte, non in `SocialApi`.** `SocialApi` trasforma ogni 409 in `SocialFailure.conflict` e perde il corpo. Il match ha dodici motivi diversi e, per `InAnotherRoom`, l'id della propria sala (piano 22a, correzione finale). `MatchApi` segue il modello di `RequestsApi`/`AccountApi`: legge il corpo del 409 e lancia solo `MatchException(failure, roomId:)`. Ha già tutte le nove chiamate, comprese voto, "Altri 30" e party che usa il 22c.
2. **`start` riceve i valori `wire` dei filtri** (`type`, `duration`, `genre`): il nucleo non importa `TonightFilters` dalle funzioni dell'app.
3. **Una sala sola nell'app**, `matchRoomProvider` globale (non una famiglia per id): il plugin ne tiene una per utente, e servono tutti la stessa (pagina, ingressi, inviti, cambio di profilo).
4. **Sala fantasma.** Un 409 `InAnotherRoom` con l'id di una sala che l'app non sta mostrando è una sala rimasta da un crash o da un'uscita persa: l'app ne esce (`Leave`) e riprova una volta. Se è la sala che l'app sta mostrando, l'avviso "Sei già in un'altra sala".
5. **Filtri condivisi con "Cosa guardo stasera?"**: stesse preferenze del profilo (`tonight.type`, `tonight.duration`, `tonight.genre`) e stesso widget (`TonightFiltersBar`, estratto dalla finestra).
6. **Carta d'invito.** La spec voleva una carta comune con due varianti. Qui ci sono due notifier e due carte che condividono cornice e animazione (`InviteCardFrame`, `InviteCardSlot`, estratte da `WatchPartyInviteCard`). Si vede un invito alla volta: mostrare un invito al match chiude quello al party, e un invito al party nuovo chiude quello al match.
7. **Uscita:** lasciando la pagina (dispose, in un microtask) e cambiando profilo (con lo stesso tempo massimo del party, 3 s). Chiudendo la finestra no: fuori dal player l'app non intercetta la chiusura, e ci pensa la pulizia del plugin (60–90 s).
8. **Fase di votazione:** in questo piano, dopo "Inizia", la pagina mostra solo i membri; il resto è del 22c. Una sala chiusa (anche con `PartyGroupId`) chiude la pagina; l'ingresso automatico nel party è del 22c.
9. **Stati in disordine** (piano 22a): si accettano solo stati della propria sala con `Rev` più alto dell'ultimo, sia dagli avvisi sia dalle risposte.
10. **Ingressi nascosti** anche mentre si è già in una sala (`matchEntryProvider`): un secondo "Match" darebbe solo `InAnotherRoom`.
11. **Testi in più** rispetto alla spec §9: `matchFriendsOnline` ("Amici online") e `matchNoFriendsOnline` ("Nessun amico online"), per l'elenco degli amici da invitare.

## Global Constraints

- App **0.15.1**: la versione 0.16.0 si mette nel piano 22c. Nessuna dipendenza nuova.
- Endpoint del plugin 1.10.0 sotto `/WonderFlixWatchParty/Match` (spec P §6.4): `POST Match`, `GET Match/{roomId}`, `POST Match/{roomId}/Invites` `{UserIds}`, `/Join`, `/Leave`, `/Start` `{Type, Duration, Genre}`, `/Votes` `{ItemId, Yes}`, `/More`, `/Party` `{GroupId}`. Un 409 ha il corpo `{"Reason": "…"}`, e `RoomId` solo con `InAnotherRoom`. Un 404 vuol dire plugin senza il match.
- Motivi dei 409: `InAnotherRoom`, `NotMember`, `NotCreator`, `Started`, `Closed`, `Full`, `NotInvited`, `NotEnoughMembers`, `NotStarted`, `NotNext`, `NotFinished`, `NotYourParty`.
- Stato: `RoomId`, `Rev`, `Phase` (`Waiting`/`Voting`/`Closed`), `CreatorId`, `CreatorName`, `Members` (`UserId`, `Name`, `Voted`), `Stack`, `Matches`, `NearMatches` (`ItemId`, `Yes`, `Of`), `ClosedReason` (`CreatorLeft`/`Inactive`/`PartyStarted`) e `PartyGroupId` solo se ci sono. Id in formato `"N"` (senza trattini): si confrontano sempre normalizzati.
- Avvisi: `{"Protocol":1,"Type":"MatchInvite","FromName":…,"RoomId":…}` e `{"Protocol":1,"Type":"MatchUpdated","State":{…}}`. Voce di cassetta `Type` `MatchInvite` con `RoomId` e `FromName`.
- Funzione del plugin `"match"`; come gli amici vale solo con l'accesso ai watch party. Gli ingressi chiedono anche `syncPlayAccess.canCreate`.
- Testi (it/en) dalla spec §9 per le chiavi di questo piano, con le due in più della decisione 11.
- Icone solo `LucideIcons`, colori `WfColors`, `clock.now()`; nei log mai titoli o nomi.

## Review Focus

1. **Sala fantasma dopo un crash:** "Match" deve aprire una sala nuova anche se il plugin crede che si sia ancora in una vecchia. Test: Task 3 (`aGhostRoomIsLeftAndOpenRetried`).
2. **Avvisi in disordine o di un'altra sala:** uno stato con `Rev` più basso o di un'altra sala non sostituisce mai quello mostrato. Test: Task 3 (`onlyNewerStatesOfTheOwnRoomCount`).
3. **Invito vecchio nella cassetta** (sala chiusa o già iniziata): un avviso con il motivo, nessuna pagina aperta. Test: Task 6 (`anOldMatchInviteSaysWhy`).
4. **Lasciare la pagina** (Esc, ←, un'altra voce della barra) esce dalla sala una volta sola, e solo da quella sala. Test: Task 4 (`leavingThePageLeavesTheRoomOnce`).
5. **Senza permesso di creare, dentro un watch party o già in una sala**, nessun pulsante "Match" (né in Home né nel pannello Amici). Test: Task 5 (`theEntriesNeedFeatureCanCreateAndNoRoom`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `flutter`, `dart` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-22b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera, tutta verde, con **`flutter test --concurrency=4`**. Con i 16 processi predefiniti il PC si è riavviato due volte il 2026-10-10;
  - la base di partenza è di **2937** test verdi (`main` `91f5498`, verificato il 2026-10-16 con `--concurrency=4`).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa. In un worktree appena creato `lib/l10n/gen/` non c'è: fai `flutter gen-l10n` prima di tutto.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Codice:**
  - durate, misure e limiti come costanti nominate e commentate;
  - commenti in italiano, codice in inglese;
  - icone solo `LucideIcons`, colori `WfColors`;
  - `clock.now()`, mai `DateTime.now()`;
  - nei log mai titoli o nomi: solo il tipo dell'errore o il nome del `MatchFailure`.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container dei test hanno `retry: (_, _) => null`;
  - in un provider, tutti i `ref.watch` stanno prima del primo `await`;
  - **spinner e `pumpAndSettle`:** il carosello e gli shimmer non si fermano mai. Nei test della Home usa `pump()` e `pump(durata)`, non `pumpAndSettle`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, uno `switch` esaustivo da completare in un file non elencato, un'icona Lucide con un altro nome):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-16 sul codice di `main` (`91f5498`).

- **`SocialApi`** (`lib/core/social/social_api.dart`): `_call` mappa 404 → `unavailable`, 401/403/400 → `forbidden`, 409 → `conflict`, 429 → `rateLimited`, e non legge il corpo. **`RequestsApi`/`AccountApi`** leggono `{Code}` dal corpo di `ServerErrorException(statusCode, body)` / `ForbiddenException(body)` con `static String? _code(Object? body)`. `mapDioException` dà 401 → `UnauthorizedException`, 403 → `ForbiddenException(data)`, 404 → `NotFoundException`, altri → `ServerErrorException(code, data)`.
- **`JellyfinHttp`**: `get(path, {query, quietStatuses})`, `post(path, {Object? body, quietStatuses})`, `put`, `delete`. `asJsonMap(Object?)` (lancia se non è un oggetto). Provider `jellyfinHttpProvider` in `lib/app/providers.dart`. I test delle API usano `FakeAdapter` (`test/support/fake_adapter.dart`): `FakeAdapter((_) => const FakeResponse(204))`, `adapter.handler = (_) => const FakeResponse(200, {...})`, `adapter.requests.last` (`path`, `method`, `data`), `JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter)`.
- **Avvisi:** `sealed class SocialEvent` e `parseSocialEvent` in `lib/core/social/social_models.dart` (tipi sconosciuti → `null`). L'elenco `socialEventTypes` sta in `lib/core/party_channel/party_channel_models.dart`: un tipo nuovo va aggiunto lì **e** in `parseSocialEvent`. `socialEventsProvider` (`lib/features/social/social_providers.dart`) è un `Stream<SocialEvent>`; `ServerConnected(isReconnect)` arriva su `watchPartyEventsProvider`.
- **Funzioni:** `PluginFeatures` (costanti in `social_models.dart`); `SocialFeatures` in `social_providers.dart` con campo, `==`, `hashCode`, `toString` e una riga in `SocialAvailability.refresh()` (`_canJoin && …` per le funzioni dei watch party). `describePluginFeatures` in `lib/features/settings/diagnostics.dart`.
- **Cassetta:** `sealed class InboxEntry`, `inboxEntryFromJson` (tipo sconosciuto → `null`). In `lib/features/inbox/inbox_panel.dart` ci sono due `switch (entry)` esaustivi (icona e contenuto), `_inviteFromSpan(text, name)`, `_mutedStyle`, `_timeStyle`, `InboxRequestIcon(icon:, size:)`, `InboxPanel.leadingSize`, e `_InviteContent` con la guardia `_joining`.
- **Carta d'invito:** `WatchPartyInviteCard` (`lib/features/watch_party/watch_party_invites.dart`) con `AnimatedSwitcher` (entra da destra, `WfMotion.medium`, `IgnorePointer` sull'uscente) e `_card(...)` (`Material` 340 px, chiave `watch-party-invite`). Sta nella `Column` di `lib/app/app_shell.dart` (`top: 72, right: 24`) con `FriendRequestCard`. `FriendRequestNotices` è il modello di un notifier con timer di 10 s.
- **Home:** `TonightButton(onPressed:)` in tre posti di `lib/features/home/home_screen.dart`: stato vuoto, `HeroCarousel(corner:)` (un solo widget `corner`), `_TonightCorner`. `_openTonight()` usa il contesto della Home.
- **Pannello Amici:** `lib/features/friends/friends_panel.dart`, intestazione poi campo di ricerca, poi `_PartyCodeEntry` ("Ho un codice", `TextButton.icon` oro); `sortFriends(friends)`; `FriendEntry(userId, name, online, party, nowPlaying)`; `friendsControllerProvider` → `FriendsState.snapshot.friends`.
- **"Cosa guardo stasera?":** filtri in un `Wrap` di `tonight_dialog.dart` (`SegmentedButton` tipo e durata, `FilterPicker` genere); preferenze `tonightTypeKey`/`tonightDurationKey`/`tonightGenreKey` in `tonight_controller.dart` (lette in `build`, scritte in `setFilters`, genere vuoto con `clearString`); `tonightGenresProvider(TonightType)`.
- **Rotte:** `ShellRoute` in `lib/app/router.dart`, pagine con `detailPage(context, state, child, underBar: true)`; percorsi in `lib/app/navigation.dart`; `BackNavigationHandler` fa `pop` con Esc, Alt+← e il tasto indietro (nessuna pagina usa `PopScope`). Titolo di pagina come La mia lista: `Text(l.x.toUpperCase(), style: WfText.display(40))` in `Padding(fromLTRB(32, 16, 32, 12))`.
- **Cambio di profilo:** `changeProfile` (`lib/features/profiles/profile_switch.dart`), `partyLeaveTimeout` (3 s), esce dal watch party prima di `session.switchProfile()`.
- **Avvisi a schermo:** nessun helper comune; `final messenger = ScaffoldMessenger.maybeOf(context)` prima delle attese, poi `messenger?.showSnackBar(SnackBar(content: Text(...)))`.
- **Test:** `pumpApp(tester, child, overrides:)`, `pumpAppRouter(tester, router, overrides:)`; `socialTestOverrides(api, events:, features:)` (sessione con `testUser` = `JellyfinUser(id: 'u1', name: 'Mario')`); `FakeSocialAvailability`; `testFriend(userId, name, online:)`; `syncPlayAccessProvider.overrideWithValue(SyncPlayAccess.joinOnly)`.

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/match_models.dart` | fasi, motivi della chiusura, membri, quasi match, stato, id normalizzati |
| `lib/core/social/match_api.dart` | `MatchApi`, `MatchFailure`, `MatchException` |
| `lib/core/social/social_models.dart`, `lib/core/party_channel/party_channel_models.dart` (modifiche) | `MatchInviteEvent`, `MatchUpdatedEvent`, tipi degli avvisi, `PluginFeatures.match` |
| `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart` (modifiche) | `SocialFeatures.match` |
| `l10n/app_it.arb`, `l10n/app_en.arb` (modifiche) | testi |
| `lib/features/match/match_providers.dart` | `matchApiProvider` |
| `lib/features/match/match_room_controller.dart` | `MatchRoomView`, `MatchRoomController`, `matchRoomProvider` |
| `lib/features/tonight/tonight_filters_bar.dart`, `tonight_controller.dart`, `tonight_dialog.dart` | filtri condivisi |
| `lib/features/match/match_actions.dart` | apri, entra, testi dei motivi |
| `lib/features/match/match_screen.dart`, `match_members_bar.dart` | la pagina |
| `lib/app/router.dart`, `lib/app/navigation.dart` (modifiche) | rotta `/match/:id` |
| `lib/features/match/match_entry.dart` | `matchEntryProvider`, `MatchButton` |
| `lib/features/home/home_screen.dart`, `lib/features/friends/friends_panel.dart` (modifiche) | ingressi |
| `lib/features/watch_party/invite_card_frame.dart`, `watch_party_invites.dart` (modifiche) | cornice comune della carta |
| `lib/features/match/match_invites.dart` | `MatchInvites`, `MatchInviteCard` |
| `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart`, `lib/app/app_shell.dart` (modifiche) | voce `MatchInvite` e carta nella shell |
| `lib/features/profiles/profile_switch.dart` (modifica) | uscita al cambio di profilo |
| `test/support/match_fakes.dart` | `FakeMatchApi`, stati e avvisi di prova |

---

## Gruppo A — nucleo

### Task 1: `MatchState`, `MatchApi`, `matchApiProvider`

**Files:**
- Create: `lib/core/social/match_models.dart`, `lib/core/social/match_api.dart`, `lib/features/match/match_providers.dart`
- Test: `test/core/social/match_models_test.dart`, `test/core/social/match_api_test.dart`

**Interfaces:**
- Produces:
  - `enum MatchPhase { waiting, voting, closed }` con `wire` e `static MatchPhase fromWire(Object?)` (sconosciuto → `closed`);
  - `enum MatchClosedReason { creatorLeft, inactive, partyStarted }` con `wire` e `static MatchClosedReason? fromWire(Object?)`;
  - `const matchMinMembers = 2`; `String normalizeMatchId(String id)`;
  - `class MatchMember {userId, name, voted}`, `class MatchNearMatch {itemId, yes, of}`, `class MatchState {roomId, rev, phase, creatorId, creatorName, members, stack, matches, nearMatches, closedReason, partyGroupId}` con `fromJson`, `bool isCreator(String userId)`, `bool hasMember(String userId)`;
  - `enum MatchFailure { unavailable, invalid, rateLimited, inAnotherRoom, notMember, notCreator, started, closed, full, notInvited, notEnoughMembers, notStarted, notNext, notFinished, notYourParty, conflict, network }`;
  - `class MatchException { MatchFailure failure; String? roomId; }`;
  - `class MatchApi` con `open()`, `state(roomId)`, `invite(roomId, userIds)`, `join(roomId)`, `leave(roomId)`, `start(roomId, {type, duration, genre})`, `vote(roomId, itemId, {required bool yes})`, `more(roomId)`, `party(roomId, groupId)`;
  - `final matchApiProvider = Provider<MatchApi>(...)`.

- [ ] **Step 1: test che falliscono**

`test/core/social/match_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_models.dart';

void main() {
  test('lo stato del plugin', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 4,
      'Phase': 'Voting',
      'CreatorId': 'u1',
      'CreatorName': 'Mario',
      'Members': [
        {'UserId': 'u1', 'Name': 'Mario', 'Voted': 3},
        {'UserId': 'u2', 'Name': 'Luigi', 'Voted': 1},
      ],
      'Stack': ['m1', 'm2', 'm3'],
      'Matches': ['m1'],
      'NearMatches': [
        {'ItemId': 'm2', 'Yes': 1, 'Of': 2},
      ],
    });

    expect(state.roomId, 'r1');
    expect(state.rev, 4);
    expect(state.phase, MatchPhase.voting);
    expect(state.creatorName, 'Mario');
    expect([for (final m in state.members) '${m.userId} ${m.name} ${m.voted}'],
        ['u1 Mario 3', 'u2 Luigi 1']);
    expect(state.stack, ['m1', 'm2', 'm3']);
    expect(state.matches, ['m1']);
    expect(state.nearMatches.single.itemId, 'm2');
    expect((state.nearMatches.single.yes, state.nearMatches.single.of), (1, 2));
    expect(state.closedReason, isNull);
    expect(state.partyGroupId, isNull);
  });

  test('una sala chiusa con il party', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 9,
      'Phase': 'Closed',
      'CreatorId': 'u1',
      'CreatorName': 'Mario',
      'Members': [],
      'Stack': [],
      'Matches': [],
      'NearMatches': [],
      'ClosedReason': 'PartyStarted',
      'PartyGroupId': 'g1',
    });

    expect(state.phase, MatchPhase.closed);
    expect(state.closedReason, MatchClosedReason.partyStarted);
    expect(state.partyGroupId, 'g1');
  });

  test('valori sconosciuti e liste mancanti', () {
    final state = MatchState.fromJson(
        {'RoomId': 'r1', 'Rev': 1, 'Phase': 'Boh', 'CreatorId': 'u1'});

    expect(state.phase, MatchPhase.closed);
    expect(state.creatorName, '');
    expect(state.members, isEmpty);
    expect(state.stack, isEmpty);
    expect(MatchClosedReason.fromWire('Boh'), isNull);
  });

  test('creatore e membri con gli id normalizzati', () {
    final state = MatchState.fromJson({
      'RoomId': 'r1',
      'Rev': 1,
      'Phase': 'Waiting',
      'CreatorId': 'abcdef0123456789abcdef0123456789',
      'Members': [
        {'UserId': 'abcdef0123456789abcdef0123456789', 'Name': 'Mario'},
      ],
    });

    expect(state.isCreator('ABCDEF01-2345-6789-ABCD-EF0123456789'), isTrue);
    expect(state.hasMember('abcdef01-2345-6789-abcd-ef0123456789'), isTrue);
    expect(state.isCreator('u2'), isFalse);
    expect(state.members.single.voted, 0);
  });
}
```

`test/core/social/match_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

const _state = {
  'RoomId': 'r1',
  'Rev': 2,
  'Phase': 'Waiting',
  'CreatorId': 'u1',
  'CreatorName': 'Mario',
  'Members': [
    {'UserId': 'u1', 'Name': 'Mario', 'Voted': 0},
  ],
  'Stack': [],
  'Matches': [],
  'NearMatches': [],
};

void main() {
  late FakeAdapter adapter;
  late MatchApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(200, _state));
    api = MatchApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  ({String method, String path, Object? data}) last() {
    final request = adapter.requests.last;
    return (method: request.method, path: request.path, data: request.data);
  }

  test('apertura, stato, ingresso, inizio e altri 30 danno lo stato', () async {
    expect((await api.open()).roomId, 'r1');
    expect(last(), (method: 'POST', path: '/WonderFlixWatchParty/Match', data: null));

    expect((await api.state('r1')).rev, 2);
    expect(last().method, 'GET');
    expect(last().path, '/WonderFlixWatchParty/Match/r1');

    await api.join('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Join');

    await api.start('r1', type: 'movies', duration: '90', genre: 'Horror');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Start');
    expect(last().data, {'Type': 'movies', 'Duration': '90', 'Genre': 'Horror'});

    await api.start('r1', type: 'both', duration: 'any');
    expect(last().data, {'Type': 'both', 'Duration': 'any', 'Genre': null});

    await api.more('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/More');
  });

  test('inviti, uscita, voto e party', () async {
    adapter.handler = (_) => const FakeResponse(204);

    await api.invite('r1', ['u2', 'u3']);
    expect(last(), (
      method: 'POST',
      path: '/WonderFlixWatchParty/Match/r1/Invites',
      data: {'UserIds': ['u2', 'u3']}
    ));

    await api.leave('r1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Leave');

    await api.vote('r1', 'm1', yes: false);
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Votes');
    expect(last().data, {'ItemId': 'm1', 'Yes': false});

    await api.party('r1', 'g1');
    expect(last().path, '/WonderFlixWatchParty/Match/r1/Party');
    expect(last().data, {'GroupId': 'g1'});
  });

  Future<MatchException> failure(FakeResponse response) async {
    adapter.handler = (_) => response;
    try {
      await api.join('r1');
    } on MatchException catch (error) {
      return error;
    }
    fail('nessuna eccezione');
  }

  test('i 409 dicono il motivo; InAnotherRoom anche la propria sala',
      () async {
    final another = await failure(const FakeResponse(
        409, {'Reason': 'InAnotherRoom', 'RoomId': 'r9'}));
    expect(another.failure, MatchFailure.inAnotherRoom);
    expect(another.roomId, 'r9');

    const reasons = {
      'NotMember': MatchFailure.notMember,
      'NotCreator': MatchFailure.notCreator,
      'Started': MatchFailure.started,
      'Closed': MatchFailure.closed,
      'Full': MatchFailure.full,
      'NotInvited': MatchFailure.notInvited,
      'NotEnoughMembers': MatchFailure.notEnoughMembers,
      'NotStarted': MatchFailure.notStarted,
      'NotNext': MatchFailure.notNext,
      'NotFinished': MatchFailure.notFinished,
      'NotYourParty': MatchFailure.notYourParty,
      'Boh': MatchFailure.conflict,
    };
    for (final MapEntry(:key, :value) in reasons.entries) {
      final error = await failure(FakeResponse(409, {'Reason': key}));
      expect(error.failure, value, reason: key);
      expect(error.roomId, isNull, reason: key);
    }
    expect((await failure(const FakeResponse(409))).failure,
        MatchFailure.conflict);
  });

  test('gli altri errori', () async {
    expect((await failure(const FakeResponse(404))).failure,
        MatchFailure.unavailable);
    expect((await failure(const FakeResponse(400))).failure,
        MatchFailure.invalid);
    expect((await failure(const FakeResponse(403))).failure,
        MatchFailure.invalid);
    expect((await failure(const FakeResponse(429))).failure,
        MatchFailure.rateLimited);
    expect((await failure(const FakeResponse(500))).failure,
        MatchFailure.network);
    expect((await failure(const FakeResponse(200, ['non', 'uno', 'stato'])))
        .failure, MatchFailure.network);
  });
}
```

(Se `FakeResponse` ha un costruttore diverso per il corpo, o `request.data` arriva già codificato, adegua i test come fanno `requests_api_test.dart` e `social_api_test.dart`.)

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/match_models_test.dart test/core/social/match_api_test.dart`
Expected: errori di compilazione (`match_models.dart` e `match_api.dart` non esistono).

- [ ] **Step 3: il codice**

`lib/core/social/match_models.dart`:

```dart
/// Membri per iniziare una sala del match: chi l'ha aperta e almeno un amico
/// (come il plugin, spec P §6.4).
const matchMinMembers = 2;

/// Lo stesso id, con o senza trattini e maiuscole: il plugin usa il formato
/// "N" di Jellyfin.
String normalizeMatchId(String id) => id.replaceAll('-', '').toLowerCase();

/// Fasi di una sala del match (spec P §6.1).
enum MatchPhase {
  waiting('Waiting'),
  voting('Voting'),
  closed('Closed');

  const MatchPhase(this.wire);

  final String wire;

  /// Un valore sconosciuto vale [closed]: una sala che non capiamo non si usa.
  static MatchPhase fromWire(Object? raw) =>
      values.firstWhere((phase) => phase.wire == raw, orElse: () => closed);
}

/// Perché una sala si è chiusa (spec P §6.1).
enum MatchClosedReason {
  creatorLeft('CreatorLeft'),
  inactive('Inactive'),
  partyStarted('PartyStarted');

  const MatchClosedReason(this.wire);

  final String wire;

  /// `null` se manca o non lo conosciamo.
  static MatchClosedReason? fromWire(Object? raw) {
    for (final reason in values) {
      if (reason.wire == raw) return reason;
    }
    return null;
  }
}

/// Un membro della sala: quanti voti ha dato, mai quali.
class MatchMember {
  const MatchMember(
      {required this.userId, required this.name, required this.voted});

  factory MatchMember.fromJson(Map<String, dynamic> json) => MatchMember(
        userId: json['UserId'] as String,
        name: json['Name'] as String? ?? '',
        voted: (json['Voted'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String name;
  final int voted;
}

/// Un quasi match (spec P §6.3): quanti sì su quanti membri.
class MatchNearMatch {
  const MatchNearMatch(
      {required this.itemId, required this.yes, required this.of});

  factory MatchNearMatch.fromJson(Map<String, dynamic> json) => MatchNearMatch(
        itemId: json['ItemId'] as String,
        yes: (json['Yes'] as num).toInt(),
        of: (json['Of'] as num).toInt(),
      );

  final String itemId;
  final int yes;
  final int of;
}

/// Lo stato di una sala (spec P §6.4): dalle risposte e da `MatchUpdated`.
class MatchState {
  const MatchState({
    required this.roomId,
    required this.rev,
    required this.phase,
    required this.creatorId,
    required this.creatorName,
    this.members = const [],
    this.stack = const [],
    this.matches = const [],
    this.nearMatches = const [],
    this.closedReason,
    this.partyGroupId,
  });

  factory MatchState.fromJson(Map<String, dynamic> json) => MatchState(
        roomId: json['RoomId'] as String,
        rev: (json['Rev'] as num).toInt(),
        phase: MatchPhase.fromWire(json['Phase']),
        creatorId: json['CreatorId'] as String,
        creatorName: json['CreatorName'] as String? ?? '',
        members: [
          for (final raw in json['Members'] as List? ?? const [])
            MatchMember.fromJson(raw as Map<String, dynamic>),
        ],
        stack: [for (final raw in json['Stack'] as List? ?? const []) raw as String],
        matches: [
          for (final raw in json['Matches'] as List? ?? const []) raw as String,
        ],
        nearMatches: [
          for (final raw in json['NearMatches'] as List? ?? const [])
            MatchNearMatch.fromJson(raw as Map<String, dynamic>),
        ],
        closedReason: MatchClosedReason.fromWire(json['ClosedReason']),
        partyGroupId: json['PartyGroupId'] as String?,
      );

  final String roomId;

  /// Cresce a ogni cambio: lo stato con il numero più alto è il più recente.
  final int rev;
  final MatchPhase phase;
  final String creatorId;
  final String creatorName;

  /// Chi ha aperto per primo, poi nell'ordine d'ingresso.
  final List<MatchMember> members;

  /// La pila, uguale per tutti e nello stesso ordine.
  final List<String> stack;

  /// I match, nell'ordine in cui sono usciti.
  final List<String> matches;

  /// Solo quando tutti hanno votato tutta la pila.
  final List<MatchNearMatch> nearMatches;
  final MatchClosedReason? closedReason;

  /// Il party privato avviato da chi ha aperto la sala.
  final String? partyGroupId;

  bool isCreator(String userId) =>
      normalizeMatchId(userId) == normalizeMatchId(creatorId);

  bool hasMember(String userId) => members.any(
      (member) => normalizeMatchId(member.userId) == normalizeMatchId(userId));
}
```

`lib/core/social/match_api.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'match_models.dart';

final _log = Logger('match');

/// Perché una chiamata del match non è riuscita (spec P §6.4).
enum MatchFailure {
  /// 404: plugin assente o senza il match (il plugin non risponde mai 404).
  unavailable,

  /// 400, 401, 403: richiesta non valida o non ammessa.
  invalid,

  /// 429: troppi voti o inviti in poco tempo.
  rateLimited,

  // I motivi dei 409 (`{Reason}`).
  inAnotherRoom,
  notMember,
  notCreator,
  started,
  closed,
  full,
  notInvited,
  notEnoughMembers,
  notStarted,
  notNext,
  notFinished,
  notYourParty,

  /// Un 409 con un motivo che non conosciamo.
  conflict,

  /// Rete, errore del server o risposta di forma inattesa.
  network,
}

class MatchException implements Exception {
  const MatchException(this.failure, {this.roomId});

  final MatchFailure failure;

  /// Con [MatchFailure.inAnotherRoom]: la sala in cui il plugin ci vede già
  /// (piano 22a), per uscirne o rientrarci.
  final String? roomId;

  @override
  String toString() => 'MatchException(${failure.name})';
}

/// Endpoint del match del plugin (spec P §6.4). Lancia solo [MatchException].
class MatchApi {
  MatchApi(this._http);

  static const _base = '/WonderFlixWatchParty/Match';

  /// Esiti previsti (sala chiusa, già in una sala, voto fuori ordine, troppi
  /// voti): nel log come info, non tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {403, 404, 409, 429};

  final JellyfinHttp _http;

  /// Apre una sala nuova; chi chiama ne è l'unico membro.
  Future<MatchState> open() =>
      _call(() async => _state(await _http.post(_base, quietStatuses: _quiet)));

  /// Lo stato della sala, per i membri.
  Future<MatchState> state(String roomId) => _call(() async =>
      _state(await _http.get('$_base/$roomId', quietStatuses: _quiet)));

  /// Invita amici (solo chi ha aperto, in attesa).
  Future<void> invite(String roomId, List<String> userIds) => _call(() =>
      _http.post('$_base/$roomId/Invites',
          body: {'UserIds': userIds}, quietStatuses: _quiet));

  /// Entra su invito; per chi è già dentro, lo stato.
  Future<MatchState> join(String roomId) => _call(() async => _state(
      await _http.post('$_base/$roomId/Join', quietStatuses: _quiet)));

  /// Esce; il plugin risponde 204 anche se non eravamo nella sala.
  Future<void> leave(String roomId) => _call(
      () => _http.post('$_base/$roomId/Leave', quietStatuses: _quiet));

  /// "Inizia" con i filtri, nei valori di "Cosa guardo stasera?".
  Future<MatchState> start(String roomId,
          {required String type, required String duration, String? genre}) =>
      _call(() async => _state(await _http.post('$_base/$roomId/Start',
          body: {'Type': type, 'Duration': duration, 'Genre': genre},
          quietStatuses: _quiet)));

  /// Il voto per il prossimo titolo della pila.
  Future<void> vote(String roomId, String itemId, {required bool yes}) =>
      _call(() => _http.post('$_base/$roomId/Votes',
          body: {'ItemId': itemId, 'Yes': yes}, quietStatuses: _quiet));

  /// "Altri 30", quando tutti hanno finito.
  Future<MatchState> more(String roomId) => _call(() async => _state(
      await _http.post('$_base/$roomId/More', quietStatuses: _quiet)));

  /// Il party privato avviato da chi ha aperto: i membri ci entrano.
  Future<void> party(String roomId, String groupId) => _call(() =>
      _http.post('$_base/$roomId/Party',
          body: {'GroupId': groupId}, quietStatuses: _quiet));

  static MatchState _state(Object? data) => MatchState.fromJson(asJsonMap(data));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const MatchException(MatchFailure.unavailable);
    } on UnauthorizedException {
      throw const MatchException(MatchFailure.invalid);
    } on ForbiddenException {
      throw const MatchException(MatchFailure.invalid);
    } on ServerErrorException catch (error) {
      if (error.statusCode == 409) {
        throw MatchException(_reason(error.body), roomId: _roomId(error.body));
      }
      throw MatchException(switch (error.statusCode) {
        400 => MatchFailure.invalid,
        429 => MatchFailure.rateLimited,
        _ => MatchFailure.network,
      });
    } on ApiException {
      throw const MatchException(MatchFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta del match non valida: ${error.runtimeType}');
      throw const MatchException(MatchFailure.network);
    }
  }

  static MatchFailure _reason(Object? body) =>
      switch (body is Map ? body['Reason'] : null) {
        'InAnotherRoom' => MatchFailure.inAnotherRoom,
        'NotMember' => MatchFailure.notMember,
        'NotCreator' => MatchFailure.notCreator,
        'Started' => MatchFailure.started,
        'Closed' => MatchFailure.closed,
        'Full' => MatchFailure.full,
        'NotInvited' => MatchFailure.notInvited,
        'NotEnoughMembers' => MatchFailure.notEnoughMembers,
        'NotStarted' => MatchFailure.notStarted,
        'NotNext' => MatchFailure.notNext,
        'NotFinished' => MatchFailure.notFinished,
        'NotYourParty' => MatchFailure.notYourParty,
        _ => MatchFailure.conflict,
      };

  static String? _roomId(Object? body) {
    if (body is! Map) return null;
    final id = body['RoomId'];
    return id is String ? id : null;
  }
}
```

`lib/features/match/match_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/match_api.dart';

/// Gli endpoint del match del plugin (spec P §7.1).
final matchApiProvider =
    Provider<MatchApi>((ref) => MatchApi(ref.watch(jellyfinHttpProvider)));
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi `flutter analyze` e la suite intera (`flutter test --concurrency=4`): verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): match models and plugin api"
```

### Task 2: avvisi, funzione `match`, testi e finti

**Files:**
- Modify: `lib/core/social/social_models.dart`, `lib/core/party_channel/party_channel_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Create (test): `test/support/match_fakes.dart`
- Test: `test/core/social/social_models_test.dart`, `test/features/social/social_providers_test.dart`, `test/features/settings/diagnostics_test.dart` (test nuovi o righe in più)

**Interfaces:**
- Consumes: `MatchState`, `MatchApi`, `MatchException` (Task 1).
- Produces:
  - `PluginFeatures.match = 'match'`; `SocialFeatures.match` (`bool`, default `false`, `_canJoin &&` come gli amici);
  - `final class MatchInviteEvent extends SocialEvent {String roomId; String fromName;}`, `final class MatchUpdatedEvent extends SocialEvent {MatchState state;}`; `socialEventTypes` con `'MatchInvite'` e `'MatchUpdated'`;
  - testi: `matchButton`, `matchTitle`, `matchInviteFriend`, `matchInvited`, `matchStart`, `matchNeedFriend`, `matchWaitingFor(name)`, `matchFailed`, `matchClosed`, `matchAlreadyStarted`, `matchFull`, `matchInAnotherRoom`, `matchInviteFrom(name)`, `matchFriendsOnline`, `matchNoFriendsOnline`;
  - in `test/support/match_fakes.dart`: `testMatchState({...})`, `matchStateJson(MatchState)`, `matchUpdatedReceived(MatchState)`, `matchInviteReceived(String roomId, String fromName)`, `class FakeMatchApi implements MatchApi` con `calls`, `rooms`, `nextRoomId`, `failures` (una volta), `failAlways` (sempre), `enterGate`.

- [ ] **Step 1: test che falliscono**

`test/support/match_fakes.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';

/// Una sala di prova: `r1`, aperta da Mario (`testUser`), in attesa.
MatchState testMatchState({
  String roomId = 'r1',
  int rev = 1,
  MatchPhase phase = MatchPhase.waiting,
  String creatorId = 'u1',
  String creatorName = 'Mario',
  List<MatchMember> members = const [
    MatchMember(userId: 'u1', name: 'Mario', voted: 0),
  ],
  List<String> stack = const [],
  List<String> matches = const [],
  List<MatchNearMatch> nearMatches = const [],
  MatchClosedReason? closedReason,
  String? partyGroupId,
}) =>
    MatchState(
      roomId: roomId,
      rev: rev,
      phase: phase,
      creatorId: creatorId,
      creatorName: creatorName,
      members: members,
      stack: stack,
      matches: matches,
      nearMatches: nearMatches,
      closedReason: closedReason,
      partyGroupId: partyGroupId,
    );

/// Il JSON di [state], come lo manda il plugin.
Map<String, Object?> matchStateJson(MatchState state) => {
      'RoomId': state.roomId,
      'Rev': state.rev,
      'Phase': state.phase.wire,
      'CreatorId': state.creatorId,
      'CreatorName': state.creatorName,
      'Members': [
        for (final member in state.members)
          {'UserId': member.userId, 'Name': member.name, 'Voted': member.voted},
      ],
      'Stack': state.stack,
      'Matches': state.matches,
      'NearMatches': [
        for (final near in state.nearMatches)
          {'ItemId': near.itemId, 'Yes': near.yes, 'Of': near.of},
      ],
      if (state.closedReason case final reason?) 'ClosedReason': reason.wire,
      if (state.partyGroupId case final group?) 'PartyGroupId': group,
    };

/// Come arriva dal WebSocket lo stato di una sala.
PartyChannelReceived matchUpdatedReceived(MatchState state) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'MatchUpdated',
      'State': matchStateJson(state),
    }));

/// Come arriva dal WebSocket l'invito a una sala.
PartyChannelReceived matchInviteReceived(String roomId, String fromName) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'MatchInvite',
      'FromName': fromName,
      'RoomId': roomId,
    }));

/// Plugin del match finto: le sale in [rooms], ogni chiamata in [calls]
/// (`open`, `state r1`, `invite r1 u2,u3`, `join r1`, `leave r1`,
/// `start r1 movies any -`, `vote r1 m1 yes`, `more r1`, `party r1 g1`).
class FakeMatchApi implements MatchApi {
  final calls = <String>[];

  /// Le sale per id: `state`, `join` e `more` rispondono con questa.
  final rooms = <String, MatchState>{};

  /// La sala che crea il prossimo [open].
  String nextRoomId = 'r1';

  /// Errori per chiamata (la stringa di [calls]): valgono una volta.
  final failures = <String, MatchException>{};

  /// Errori per chiamata che valgono sempre.
  final failAlways = <String, MatchException>{};

  /// Se valorizzato, [open] e [join] aspettano che si completi.
  Completer<void>? enterGate;

  void _throwIfFailing(String call) {
    final error = failures.remove(call) ?? failAlways[call];
    if (error != null) throw error;
  }

  @override
  Future<MatchState> open() async {
    calls.add('open');
    await enterGate?.future;
    _throwIfFailing('open');
    return rooms[nextRoomId] ??= testMatchState(roomId: nextRoomId);
  }

  @override
  Future<MatchState> state(String roomId) async {
    calls.add('state $roomId');
    _throwIfFailing('state $roomId');
    return rooms[roomId] ??
        (throw const MatchException(MatchFailure.notMember));
  }

  @override
  Future<void> invite(String roomId, List<String> userIds) async {
    final call = 'invite $roomId ${userIds.join(',')}';
    calls.add(call);
    _throwIfFailing(call);
  }

  @override
  Future<MatchState> join(String roomId) async {
    calls.add('join $roomId');
    await enterGate?.future;
    _throwIfFailing('join $roomId');
    return rooms[roomId] ?? (throw const MatchException(MatchFailure.closed));
  }

  @override
  Future<void> leave(String roomId) async {
    calls.add('leave $roomId');
    _throwIfFailing('leave $roomId');
  }

  @override
  Future<MatchState> start(String roomId,
      {required String type, required String duration, String? genre}) async {
    final call = 'start $roomId $type $duration ${genre ?? '-'}';
    calls.add(call);
    _throwIfFailing(call);
    final room = rooms[roomId] ?? testMatchState(roomId: roomId);
    return rooms[roomId] = testMatchState(
      roomId: roomId,
      rev: room.rev + 1,
      phase: MatchPhase.voting,
      creatorId: room.creatorId,
      creatorName: room.creatorName,
      members: room.members,
    );
  }

  @override
  Future<void> vote(String roomId, String itemId, {required bool yes}) async {
    final call = 'vote $roomId $itemId ${yes ? 'yes' : 'no'}';
    calls.add(call);
    _throwIfFailing(call);
  }

  @override
  Future<MatchState> more(String roomId) async {
    calls.add('more $roomId');
    _throwIfFailing('more $roomId');
    return rooms[roomId] ?? (throw const MatchException(MatchFailure.closed));
  }

  @override
  Future<void> party(String roomId, String groupId) async {
    final call = 'party $roomId $groupId';
    calls.add(call);
    _throwIfFailing(call);
  }
}
```

In fondo a `test/core/social/social_models_test.dart` (con gli `import` di `dart:convert`, `match_models.dart` e `../../support/match_fakes.dart` se mancano):

```dart
  test('avvisi del match: invito e stato della sala', () {
    final invite = parseSocialEvent(
        jsonEncode({'Protocol': 1, 'Type': 'MatchInvite', 'FromName': 'Luigi', 'RoomId': 'r1'}));
    expect(invite, isA<MatchInviteEvent>());
    expect((invite! as MatchInviteEvent).roomId, 'r1');
    expect((invite as MatchInviteEvent).fromName, 'Luigi');

    final updated = parseSocialEvent(matchUpdatedReceived(
            testMatchState(rev: 7, phase: MatchPhase.voting, stack: ['m1']))
        .payload);
    expect(updated, isA<MatchUpdatedEvent>());
    final state = (updated! as MatchUpdatedEvent).state;
    expect((state.roomId, state.rev, state.phase, state.stack),
        ('r1', 7, MatchPhase.voting, ['m1']));

    // Senza stato: avviso malformato, ignorato.
    expect(parseSocialEvent(jsonEncode({'Protocol': 1, 'Type': 'MatchUpdated'})),
        isNull);
  });
```

In `test/features/social/social_providers_test.dart`, dopo il test "Info con l'attività degli amici", con lo stesso montaggio:

```dart
  test('Info con il match: funzione match, solo con i watch party', () async {
    api.install(features: const {
      PluginFeatures.friends,
      PluginFeatures.match,
    });
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true, match: true));

    final noParty = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(noParty.read(socialAvailabilityProvider).match, isFalse);
  });
```

In `test/features/settings/diagnostics_test.dart`, nel test `describePluginFeatures`, una riga:

```dart
    expect(describePluginFeatures(const {PluginFeatures.match}), 'match');
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/social_models_test.dart test/features/social/social_providers_test.dart test/features/settings/diagnostics_test.dart`
Expected: errori di compilazione (`MatchInviteEvent`, `PluginFeatures.match`, `SocialFeatures(match:)` non esistono).

- [ ] **Step 3: il codice**

In `lib/core/social/social_models.dart`:
- import `'match_models.dart'`;
- in `PluginFeatures`, in fondo:

```dart
  /// Il match del film (spec P §6.7).
  static const match = 'match';
```

- dopo `InboxChangedEvent`:

```dart
/// Un amico ci invita nella sua sala del match (spec P §6.5).
final class MatchInviteEvent extends SocialEvent {
  const MatchInviteEvent({required this.roomId, required this.fromName});

  final String roomId;
  final String fromName;
}

/// Lo stato di una sala del match di cui siamo membri (spec P §6.5).
final class MatchUpdatedEvent extends SocialEvent {
  const MatchUpdatedEvent(this.state);

  final MatchState state;
}
```

- in `parseSocialEvent`, dopo il caso `'InboxChanged'`:

```dart
      case 'MatchInvite':
        return MatchInviteEvent(
          roomId: json['RoomId'] as String,
          fromName: json['FromName'] as String? ?? '',
        );
      case 'MatchUpdated':
        return MatchUpdatedEvent(
            MatchState.fromJson(json['State'] as Map<String, dynamic>));
```

In `lib/core/party_channel/party_channel_models.dart`, in `socialEventTypes` dopo `'InboxChanged'`: `'MatchInvite',` e `'MatchUpdated',`; nel commento sopra aggiungi "spec P §6.5".

In `lib/features/social/social_providers.dart`, in `SocialFeatures`:
- costruttore: `this.match = false,` dopo `this.friendsActivity = false,`;
- campo dopo `friendsActivity`:

```dart
  /// Il match del film (spec P §7.1): come gli amici, solo con l'accesso ai
  /// watch party.
  final bool match;
```

- `==`: `other.match == match &&` dopo `friendsActivity`; `hashCode`: `match,` dopo `friendsActivity,`; `toString`: `match: $match` dopo `friendsActivity: $friendsActivity`;
- in `SocialAvailability.refresh()`, dopo `friendsActivity: …`:

```dart
        match: _canJoin && info.features.contains(PluginFeatures.match),
```

- cerca con `grep` altri `SocialFeatures(` in `lib/` che elencano tutte le funzioni (per esempio dove l'accesso ai watch party cambia) e aggiungi `match` allo stesso modo.

In `lib/features/settings/diagnostics.dart`, in `describePluginFeatures` dopo la riga di `friendsActivity`: `if (features.contains(PluginFeatures.match)) 'match',`.

In `l10n/app_it.arb`, in fondo (con la virgola sull'ultima riga di prima):

```json
  "matchButton": "Match",
  "matchTitle": "Match del film",
  "matchInviteFriend": "Invita",
  "matchInvited": "Invitato",
  "matchStart": "Inizia",
  "matchNeedFriend": "Serve almeno un amico nella sala",
  "matchWaitingFor": "In attesa che {name} inizi…",
  "@matchWaitingFor": {"placeholders": {"name": {"type": "String"}}},
  "matchFailed": "Non riuscito, riprova",
  "matchClosed": "Sala chiusa",
  "matchAlreadyStarted": "Il match è già iniziato",
  "matchFull": "Sala piena",
  "matchInAnotherRoom": "Sei già in un'altra sala",
  "matchInviteFrom": "{name} ti invita a un match",
  "@matchInviteFrom": {"placeholders": {"name": {"type": "String"}}},
  "matchFriendsOnline": "Amici online",
  "matchNoFriendsOnline": "Nessun amico online"
```

In `l10n/app_en.arb`, in fondo:

```json
  "matchButton": "Match",
  "matchTitle": "Movie match",
  "matchInviteFriend": "Invite",
  "matchInvited": "Invited",
  "matchStart": "Start",
  "matchNeedFriend": "At least one friend has to join",
  "matchWaitingFor": "Waiting for {name} to start…",
  "@matchWaitingFor": {"placeholders": {"name": {"type": "String"}}},
  "matchFailed": "Didn't work, try again",
  "matchClosed": "Room closed",
  "matchAlreadyStarted": "The match has already started",
  "matchFull": "Room full",
  "matchInAnotherRoom": "You're already in another room",
  "matchInviteFrom": "{name} invited you to a movie match",
  "@matchInviteFrom": {"placeholders": {"name": {"type": "String"}}},
  "matchFriendsOnline": "Friends online",
  "matchNoFriendsOnline": "No friends online"
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test l10n
git commit -m "feat(app): match events, plugin feature and texts"
```

---

## Gruppo B — la sala

### Task 3: `MatchRoomController`

**Files:**
- Create: `lib/features/match/match_room_controller.dart`
- Test: `test/features/match/match_room_controller_test.dart`

**Interfaces:**
- Consumes: `MatchApi`, `MatchException`, `MatchFailure`, `MatchState`, `normalizeMatchId` (Task 1); `matchApiProvider` (Task 1); `MatchUpdatedEvent`, `SocialFeatures.match` (Task 2); `TonightFilters` (`lib/features/tonight/tonight_logic.dart`).
- Produces:
  - `@immutable class MatchRoomView {String roomId; MatchState? state; bool gone; bool get closed; MatchRoomView copyWith({MatchState? state, bool? gone})}`;
  - `class MatchRoomController extends Notifier<MatchRoomView?>` con `bool get entering`, `Future<MatchFailure?> open()`, `Future<MatchFailure?> join(String roomId)`, `Future<void> reload()`, `Future<void> leave([String? roomId])`, `Future<MatchFailure?> invite(List<String> userIds)`, `Future<MatchFailure?> start(TonightFilters filters)`;
  - `final matchRoomProvider = NotifierProvider<MatchRoomController, MatchRoomView?>(MatchRoomController.new)`.

- [ ] **Step 1: test che falliscono**

`test/features/match/match_room_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/tonight/tonight_logic.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';
import '../../support/match_fakes.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeMatchApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;

  setUp(() {
    api = FakeMatchApi();
    events = StreamController<ServerEvent>.broadcast();
    container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        socialAvailabilityProvider.overrideWith(() =>
            FakeSocialAvailability(const SocialFeatures(friends: true, match: true))),
        matchApiProvider.overrideWithValue(api),
      ],
      retry: (_, _) => null,
    );
    container.listen(matchRoomProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await events.close();
  });

  MatchRoomController controller() => container.read(matchRoomProvider.notifier);
  MatchRoomView? room() => container.read(matchRoomProvider);

  const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);
  const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);

  Future<void> push(MatchState state) async {
    events.add(matchUpdatedReceived(state));
    await pumpEventQueue();
  }

  test('aprire una sala la tiene nell\'app', () async {
    expect(await controller().open(), isNull);
    expect(room()!.roomId, 'r1');
    expect(room()!.state!.phase, MatchPhase.waiting);
    expect(room()!.closed, isFalse);
    expect(api.calls, ['open']);
  });

  test('aGhostRoomIsLeftAndOpenRetried', () async {
    api.failures['open'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r9');

    expect(await controller().open(), isNull);

    expect(api.calls, ['open', 'leave r9', 'open']);
    expect(room()!.roomId, 'r1');
  });

  test('la sala fantasma si lascia una volta sola', () async {
    api.failAlways['open'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r9');

    expect(await controller().open(), MatchFailure.inAnotherRoom);

    expect(api.calls, ['open', 'leave r9', 'open']);
    expect(room(), isNull);
  });

  test('la sala che l\'app mostra non è una sala fantasma', () async {
    await controller().open();
    api.failures['join r2'] =
        const MatchException(MatchFailure.inAnotherRoom, roomId: 'r1');

    expect(await controller().join('r2'), MatchFailure.inAnotherRoom);

    expect(api.calls, ['open', 'join r2']);
    expect(room()!.roomId, 'r1');
  });

  test('entrare su invito; i motivi del no', () async {
    api.rooms['r2'] = testMatchState(
        roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi', members: [luigi, mario]);

    expect(await controller().join('r2'), isNull);
    expect(room()!.state!.creatorName, 'Luigi');

    await controller().leave();
    api.failures['join r3'] = const MatchException(MatchFailure.started);
    expect(await controller().join('r3'), MatchFailure.started);
    expect(room(), isNull);
  });

  test('entering vale mentre si entra', () async {
    api.enterGate = Completer<void>();
    final opening = controller().open();
    await pumpEventQueue();
    expect(controller().entering, isTrue);

    api.enterGate!.complete();
    await opening;
    expect(controller().entering, isFalse);
  });

  test('onlyNewerStatesOfTheOwnRoomCount', () async {
    await controller().open();

    await push(testMatchState(rev: 3, members: [mario, luigi]));
    expect(room()!.state!.rev, 3);
    expect(room()!.state!.members, hasLength(2));

    await push(testMatchState(rev: 2));
    await push(testMatchState(rev: 3));
    await push(testMatchState(roomId: 'r2', rev: 9));
    expect(room()!.roomId, 'r1');
    expect(room()!.state!.rev, 3);
    expect(room()!.state!.members, hasLength(2));
  });

  test('alla riconnessione si rilegge; fuori dalla sala diventa gone', () async {
    await controller().open();

    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['open'], reason: 'la prima connessione non rilegge');

    api.rooms['r1'] = testMatchState(rev: 5);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls.last, 'state r1');
    expect(room()!.state!.rev, 5);

    api.rooms.remove('r1');
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(room()!.gone, isTrue);
    expect(room()!.closed, isTrue);
  });

  test('uscire: solo dalla propria sala, e non da una sala chiusa', () async {
    await controller().open();

    await controller().leave('r2');
    expect(room()!.roomId, 'r1');

    await controller().leave('r1');
    expect(room(), isNull);
    expect(api.calls.last, 'leave r1');

    await controller().open();
    await push(testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.creatorLeft));
    expect(room()!.closed, isTrue);
    final calls = api.calls.length;
    await controller().leave();
    expect(room(), isNull);
    expect(api.calls, hasLength(calls));
  });

  test('un errore dell\'uscita non ferma niente', () async {
    await controller().open();
    api.failures['leave r1'] = const MatchException(MatchFailure.network);

    await controller().leave();

    expect(room(), isNull);
  });

  test('inviti e inizio passano i valori del plugin', () async {
    expect(await controller().invite(['u2']), MatchFailure.closed,
        reason: 'fuori da una sala');
    expect(api.calls, isEmpty);

    await controller().open();
    expect(await controller().invite(['u2', 'u3']), isNull);
    expect(api.calls.last, 'invite r1 u2,u3');

    expect(
        await controller().start(const TonightFilters(
            type: TonightType.movies,
            duration: TonightDuration.under90,
            genre: 'Horror')),
        isNull);
    expect(api.calls.last, 'start r1 movies 90 Horror');
    expect(room()!.state!.phase, MatchPhase.voting);

    api.failures['start r1 both any -'] =
        const MatchException(MatchFailure.notEnoughMembers);
    expect(await controller().start(const TonightFilters()),
        MatchFailure.notEnoughMembers);
  });

  test('senza la funzione match la sala sparisce', () async {
    await controller().open();
    (container.read(socialAvailabilityProvider.notifier)
            as FakeSocialAvailability)
        .set(SocialFeatures.none);
    await pumpEventQueue();

    expect(room(), isNull);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/match/match_room_controller_test.dart`
Expected: errore di compilazione (`match_room_controller.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/match/match_room_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/server_events.dart';
import '../../core/social/match_api.dart';
import '../../core/social/match_models.dart';
import '../../core/social/social_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';
import '../tonight/tonight_logic.dart';
import '../watch_party/watch_party_providers.dart';
import 'match_providers.dart';

final _log = Logger('match');

/// La sala del match dell'app (spec P §7.3).
@immutable
class MatchRoomView {
  const MatchRoomView({required this.roomId, this.state, this.gone = false});

  final String roomId;

  /// L'ultimo stato ricevuto; `null` finché non ne arriva uno.
  final MatchState? state;

  /// Non siamo più nella sala (409 `NotMember` rileggendo): la pagina si
  /// chiude con "Sala chiusa".
  final bool gone;

  bool get closed => gone || state?.phase == MatchPhase.closed;

  MatchRoomView copyWith({MatchState? state, bool? gone}) => MatchRoomView(
        roomId: roomId,
        state: state ?? this.state,
        gone: gone ?? this.gone,
      );
}

/// L'unica sala del match dell'app: il plugin ne tiene una per utente (piano
/// 22b, decisione 3). Accetta solo stati della sua sala più recenti di
/// quello che ha (decisione 9), rilegge a ogni riconnessione, esce quando
/// la pagina si chiude o si cambia profilo.
class MatchRoomController extends Notifier<MatchRoomView?> {
  bool _entering = false;

  /// Un'apertura o un ingresso è in corso: un secondo clic non ne fa un altro.
  bool get entering => _entering;

  MatchApi get _api => ref.read(matchApiProvider);

  @override
  MatchRoomView? build() {
    // Cambiando account la sala di prima non è più nostra.
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
      return null;
    }
    final notices = ref.watch(socialEventsProvider).listen((event) {
      if (event is MatchUpdatedEvent) _apply(event.state);
    });
    final connections = ref.watch(watchPartyEventsProvider).listen((event) {
      // Gli stati persi mentre il WebSocket era giù.
      if (event is ServerConnected && event.isReconnect) unawaited(reload());
    });
    ref.onDispose(() {
      unawaited(notices.cancel());
      unawaited(connections.cancel());
    });
    return null;
  }

  /// Apre una sala nuova (spec P §7.2); `null` se è riuscito.
  Future<MatchFailure?> open() => _enter(_api.open);

  /// Entra nella sala [roomId] su invito; `null` se è riuscito.
  Future<MatchFailure?> join(String roomId) => _enter(() => _api.join(roomId));

  /// Un 409 `InAnotherRoom` con una sala che l'app non sta mostrando è una
  /// sala rimasta da un crash o da un'uscita persa: se ne esce e si riprova
  /// una volta (piano 22b, decisione 4).
  Future<MatchFailure?> _enter(Future<MatchState> Function() request) async {
    if (_entering) return null;
    _entering = true;
    try {
      for (var attempt = 0;; attempt++) {
        try {
          final next = await request();
          if (!ref.mounted) return null;
          state = MatchRoomView(roomId: next.roomId, state: next);
          return null;
        } on MatchException catch (error) {
          final other = error.roomId;
          if (error.failure != MatchFailure.inAnotherRoom ||
              other == null ||
              attempt > 0 ||
              _shows(other)) {
            _log.info('sala del match non raggiunta: ${error.failure.name}');
            return error.failure;
          }
          try {
            await _api.leave(other);
          } on MatchException catch (leaveError) {
            _log.info('uscita dalla sala rimasta: ${leaveError.failure.name}');
            return error.failure;
          }
          if (!ref.mounted) return null;
        }
      }
    } finally {
      _entering = false;
    }
  }

  /// L'app mostra la sala aperta [roomId].
  bool _shows(String roomId) {
    final current = state;
    return current != null &&
        !current.closed &&
        normalizeMatchId(current.roomId) == normalizeMatchId(roomId);
  }

  void _apply(MatchState next) {
    final current = state;
    if (current == null ||
        normalizeMatchId(current.roomId) != normalizeMatchId(next.roomId)) {
      return;
    }
    final have = current.state;
    if (have != null && next.rev <= have.rev) return;
    state = current.copyWith(state: next);
  }

  /// Rilegge lo stato; fuori dalla sala la vista diventa [MatchRoomView.gone].
  Future<void> reload() async {
    final current = state;
    if (current == null || current.closed) return;
    try {
      final next = await _api.state(current.roomId);
      if (!ref.mounted) return;
      _apply(next);
    } on MatchException catch (error) {
      if (!ref.mounted) return;
      final now = state;
      if (error.failure == MatchFailure.notMember &&
          now != null &&
          normalizeMatchId(now.roomId) == normalizeMatchId(current.roomId)) {
        state = now.copyWith(gone: true);
      } else {
        _log.info('sala del match non riletta: ${error.failure.name}');
      }
    }
  }

  /// Esce dalla sala (spec P §7.3): con [roomId], solo se è quella. La sala
  /// sparisce subito dall'app; una sala chiusa non va lasciata.
  Future<void> leave([String? roomId]) async {
    final current = state;
    if (current == null) return;
    if (roomId != null &&
        normalizeMatchId(roomId) != normalizeMatchId(current.roomId)) {
      return;
    }
    state = null;
    if (current.closed) return;
    try {
      await _api.leave(current.roomId);
    } on MatchException catch (error) {
      // La pulizia del plugin la chiuderà comunque (spec P §6.1).
      _log.info('uscita dalla sala del match: ${error.failure.name}');
    }
  }

  /// Invita amici (solo chi ha aperto, in attesa).
  Future<MatchFailure?> invite(List<String> userIds) async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    try {
      await _api.invite(current.roomId, userIds);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }

  /// "Inizia" con i filtri di "Cosa guardo stasera?" (piano 22b, decisione 2).
  Future<MatchFailure?> start(TonightFilters filters) async {
    final current = state;
    if (current == null || current.closed) return MatchFailure.closed;
    try {
      final next = await _api.start(current.roomId,
          type: filters.type.wire,
          duration: filters.duration.wire,
          genre: filters.genre);
      if (ref.mounted) _apply(next);
      return null;
    } on MatchException catch (error) {
      return error.failure;
    }
  }
}

final matchRoomProvider =
    NotifierProvider<MatchRoomController, MatchRoomView?>(
        MatchRoomController.new);
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): match room controller"
```

---

## Gruppo C — interfaccia

### Task 4: filtri condivisi, pagina della sala, rotta e azioni

**Files:**
- Create: `lib/features/tonight/tonight_filters_bar.dart`, `lib/features/match/match_actions.dart`, `lib/features/match/match_members_bar.dart`, `lib/features/match/match_screen.dart`
- Modify: `lib/features/tonight/tonight_controller.dart`, `lib/features/tonight/tonight_dialog.dart`, `lib/app/router.dart`, `lib/app/navigation.dart`
- Test: `test/features/match/match_screen_test.dart`, `test/features/match/match_actions_test.dart`

**Interfaces:**
- Consumes: `matchRoomProvider`, `MatchRoomView`, `MatchRoomController` (Task 3); `MatchFailure`, `MatchState`, `matchMinMembers` (Task 1); testi (Task 2); `friendsControllerProvider`, `sortFriends`; `tonightGenresProvider`; `profilePreferencesProvider`; `currentUserIdProvider`.
- Produces:
  - `TonightFilters readTonightFilters(ProfilePreferences prefs)` e `Future<void> writeTonightFilters(ProfilePreferences prefs, TonightFilters filters)` (in `tonight_controller.dart`);
  - `class TonightFiltersBar extends ConsumerWidget {TonightFilters filters; ValueChanged<TonightFilters> onChanged}`;
  - `String matchRoute(String roomId)` (in `navigation.dart`);
  - `String matchFailureText(AppLocalizations l, MatchFailure failure)`, `Future<bool> openMatchRoom(BuildContext, WidgetRef)`, `Future<bool> joinMatchRoom(BuildContext, WidgetRef, String roomId)`;
  - `class MatchMembersBar extends StatelessWidget {MatchState state}`;
  - `class MatchScreen extends ConsumerStatefulWidget {String roomId}`.

- [ ] **Step 1: test che falliscono**

`test/features/match/match_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/social/match_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/library/library_providers.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/match/match_screen.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/tonight/tonight_controller.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

import '../../support/library_fakes.dart';
import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeMatchApi match;
  late FakeSocialApi social;
  late SharedPreferences prefs;

  const mario = MatchMember(userId: 'u1', name: 'Mario', voted: 0);
  const luigi = MatchMember(userId: 'u2', name: 'Luigi', voted: 0);

  setUp(() async {
    match = FakeMatchApi();
    social = FakeSocialApi()
      ..snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true),
        testFriend('u3', 'Peach', online: true),
        testFriend('u4', 'Toad'),
      ]);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// La Home finta con "apri" e la pagina della sala `r1` già aperta.
  Future<ProviderContainer> pumpRoom(WidgetTester tester,
      {MatchState? state}) async {
    match.rooms['r1'] = state ?? testMatchState();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => unawaited(openMatchRoom(context, ref)),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/match/:id',
          builder: (context, state) => Scaffold(
              body: MatchScreen(roomId: state.pathParameters['id']!)),
        ),
      ],
    );
    await pumpAppRouter(tester, router, overrides: [
      ...socialTestOverrides(social,
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      sharedPreferencesProvider.overrideWithValue(prefs),
      libraryApiProvider.overrideWithValue(FakeLibraryApi()),
    ]);
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(MatchScreen)));
  }

  testWidgets('chi ha aperto: filtri, amici online da invitare, Inizia spento',
      (tester) async {
    await pumpRoom(tester);

    expect(find.text('MATCH DEL FILM'), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);
    expect(find.byKey(const Key('tonight-type')), findsOneWidget);
    expect(find.text('Amici online'), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u2')), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u3')), findsOneWidget);
    expect(find.byKey(const Key('match-invite-u4')), findsNothing,
        reason: 'offline');
    expect(find.text('Serve almeno un amico nella sala'), findsOneWidget);
    expect(tester.widget<WfButton>(find.byKey(const Key('match-start'))).onPressed,
        isNull);
  });

  testWidgets('Invita manda l\'invito e diventa Invitato', (tester) async {
    await pumpRoom(tester);

    await tester.tap(find.byKey(const Key('match-invite-u2')));
    await tester.pumpAndSettle();

    expect(match.calls.last, 'invite r1 u2');
    expect(find.descendant(
            of: find.byKey(const Key('match-invite-u2')),
            matching: find.text('Invitato')),
        findsOneWidget);
  });

  testWidgets('con un amico dentro: niente invito per lui, Inizia con i filtri',
      (tester) async {
    prefs.setString(tonightTypeKey, 'movies');
    await pumpRoom(tester, state: testMatchState(members: [mario, luigi]));

    expect(find.byKey(const Key('match-invite-u2')), findsNothing);
    expect(find.text('Serve almeno un amico nella sala'), findsNothing);

    await tester.tap(find.byKey(const Key('match-start')));
    await tester.pumpAndSettle();

    expect(match.calls.last, 'start r1 movies any -');
  });

  testWidgets('chi è entrato su invito aspetta chi ha aperto', (tester) async {
    await pumpRoom(tester,
        state: testMatchState(
            creatorId: 'u2', creatorName: 'Luigi', members: [luigi, mario]));

    expect(find.text('In attesa che Luigi inizi…'), findsOneWidget);
    expect(find.byKey(const Key('match-start')), findsNothing);
    expect(find.byKey(const Key('tonight-type')), findsNothing);
  });

  testWidgets('leavingThePageLeavesTheRoomOnce', (tester) async {
    final container = await pumpRoom(tester);

    GoRouter.of(tester.element(find.byType(MatchScreen))).pop();
    await tester.pumpAndSettle();

    expect(match.calls.where((call) => call == 'leave r1'), hasLength(1));
    expect(container.read(matchRoomProvider), isNull);
  });

  testWidgets('una sala chiusa chiude la pagina con "Sala chiusa"',
      (tester) async {
    final container = await pumpRoom(tester);

    match.rooms['r1'] = testMatchState(
        rev: 2,
        phase: MatchPhase.closed,
        closedReason: MatchClosedReason.creatorLeft);
    await container.read(matchRoomProvider.notifier).reload();
    await tester.pumpAndSettle();

    expect(find.byType(MatchScreen), findsNothing);
    expect(find.text('Sala chiusa'), findsOneWidget);
    expect(match.calls.where((call) => call.startsWith('leave')), isEmpty,
        reason: 'una sala chiusa non si lascia');
  });
}
```

`test/features/match/match_actions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/match_api.dart';
import 'package:wonderflix/features/match/match_actions.dart';
import 'package:wonderflix/l10n/gen/app_localizations_it.dart';

void main() {
  test('i motivi diventano testi', () {
    final l = AppLocalizationsIt();
    expect(matchFailureText(l, MatchFailure.started), 'Il match è già iniziato');
    expect(matchFailureText(l, MatchFailure.closed), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notInvited), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.notMember), 'Sala chiusa');
    expect(matchFailureText(l, MatchFailure.full), 'Sala piena');
    expect(matchFailureText(l, MatchFailure.inAnotherRoom),
        'Sei già in un\'altra sala');
    expect(matchFailureText(l, MatchFailure.network), 'Non riuscito, riprova');
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/match/match_screen_test.dart test/features/match/match_actions_test.dart`
Expected: errori di compilazione (`MatchScreen`, `openMatchRoom`, `matchFailureText` non esistono).

- [ ] **Step 3: il codice**

**Filtri condivisi.** In `lib/features/tonight/tonight_controller.dart`, dopo le tre chiavi:

```dart
/// I filtri salvati nel profilo (spec M §8.4); li usa anche la sala del match
/// (piano 22b, decisione 5).
TonightFilters readTonightFilters(ProfilePreferences prefs) {
  final genre = prefs.getString(tonightGenreKey);
  return TonightFilters(
    type: TonightType.parse(prefs.getString(tonightTypeKey)),
    duration: TonightDuration.parse(prefs.getString(tonightDurationKey)),
    // In un profilo "nessun valore" è una stringa vuota (`clearString`).
    genre: genre == null || genre.isEmpty ? null : genre,
  );
}

/// Salva [filters] nel profilo.
Future<void> writeTonightFilters(
    ProfilePreferences prefs, TonightFilters filters) async {
  final genre = filters.genre;
  await Future.wait([
    prefs.setString(tonightTypeKey, filters.type.wire),
    prefs.setString(tonightDurationKey, filters.duration.wire),
    genre == null
        ? prefs.clearString(tonightGenreKey)
        : prefs.setString(tonightGenreKey, genre),
  ]);
}
```

e in `TonightController` `build()` usa `filters: readTonightFilters(ref.read(profilePreferencesProvider))` al posto della lettura a mano, e `setFilters` usa `await writeTonightFilters(ref.read(profilePreferencesProvider), next)` al posto del `Future.wait` (il resto di `setFilters` resta com'è).

`lib/features/tonight/tonight_filters_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../catalog/catalog_filters_bar.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// I filtri di "Cosa guardo stasera?" (spec M §8.4): tipo, durata (solo per
/// i film) e genere. Li usa anche la sala del match (spec P §7.3).
class TonightFiltersBar extends ConsumerWidget {
  const TonightFiltersBar(
      {super.key, required this.filters, required this.onChanged});

  final TonightFilters filters;
  final ValueChanged<TonightFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final genres = ref.watch(tonightGenresProvider(filters.type)).value ??
        const <String>[];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<TonightType>(
          key: const Key('tonight-type'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: TonightType.movies, label: Text(l.tonightTypeMovies)),
            ButtonSegment(
                value: TonightType.series, label: Text(l.tonightTypeSeries)),
            ButtonSegment(
                value: TonightType.both, label: Text(l.tonightTypeBoth)),
          ],
          selected: {filters.type},
          onSelectionChanged: (selection) =>
              onChanged(filters.copyWith(type: selection.first)),
        ),
        SegmentedButton<TonightDuration>(
          key: const Key('tonight-duration'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: TonightDuration.any, label: Text(l.tonightDurationAny)),
            ButtonSegment(
                value: TonightDuration.under90,
                label: Text(l.tonightDuration90)),
            ButtonSegment(
                value: TonightDuration.under120,
                label: Text(l.tonightDuration120)),
          ],
          selected: {filters.duration},
          // La durata vale solo per i film (spec M §8.4).
          onSelectionChanged: filters.type == TonightType.series
              ? null
              : (selection) =>
                  onChanged(filters.copyWith(duration: selection.first)),
        ),
        FilterPicker<String?>(
          value: filters.genre,
          items: {
            null: l.catalogAllGenres,
            for (final genre in genres) genre: genre,
          },
          onChanged: (genre) => onChanged(filters.copyWith(genre: genre)),
        ),
      ],
    );
  }
}
```

In `lib/features/tonight/tonight_dialog.dart` (con l'import di `tonight_filters_bar.dart`): il `Wrap` dei filtri (da `Wrap(` con i due `SegmentedButton` e il `FilterPicker` fino alla sua chiusura) diventa `TonightFiltersBar(filters: filters, onChanged: _filters),`. La riga `final genres = ref.watch(tonightGenresProvider(filters.type)).value ?? …` e l'import di `catalog_filters_bar.dart` si tolgono se non servono più; il `ref.listen` sui generi resta nella finestra. I test di `test/features/tonight/` devono restare verdi senza modifiche.

**Rotta.** In `lib/app/navigation.dart`, dopo `collectionRoute`:

```dart
/// Percorso della pagina della sala del match [roomId] (spec P §7.3).
String matchRoute(String roomId) => '/match/$roomId';
```

In `lib/app/router.dart`, dentro lo `ShellRoute` dopo `/collection/:id` (con l'import di `../features/match/match_screen.dart`):

```dart
          GoRoute(
            path: '/match/:id',
            pageBuilder: (context, state) => detailPage(
              context,
              state,
              MatchScreen(
                key: ValueKey(state.pathParameters['id']),
                roomId: state.pathParameters['id']!,
              ),
              underBar: true,
            ),
          ),
```

**Azioni.** `lib/features/match/match_actions.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';
import '../../core/social/match_api.dart';
import '../../l10n/gen/app_localizations.dart';
import 'match_room_controller.dart';

/// Il testo dell'avviso per un no del plugin (spec P §7.2).
String matchFailureText(AppLocalizations l, MatchFailure failure) =>
    switch (failure) {
      MatchFailure.started => l.matchAlreadyStarted,
      MatchFailure.closed ||
      MatchFailure.notInvited ||
      MatchFailure.notMember =>
        l.matchClosed,
      MatchFailure.full => l.matchFull,
      MatchFailure.inAnotherRoom => l.matchInAnotherRoom,
      _ => l.matchFailed,
    };

/// "Match": apre una sala nuova e la sua pagina (spec P §7.2). `false` se
/// non è partita (l'avviso lo dice).
Future<bool> openMatchRoom(BuildContext context, WidgetRef ref) =>
    _enter(context, ref, (controller) => controller.open());

/// "Unisciti" a un invito: entra nella sala e apre la sua pagina.
Future<bool> joinMatchRoom(
        BuildContext context, WidgetRef ref, String roomId) =>
    _enter(context, ref, (controller) => controller.join(roomId));

Future<bool> _enter(BuildContext context, WidgetRef ref,
    Future<MatchFailure?> Function(MatchRoomController) action) async {
  // Tutto quello che serve dopo l'attesa si prende prima: chi ha chiamato
  // (il pannello Amici, la carta) può sparire nel frattempo.
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final controller = ref.read(matchRoomProvider.notifier);
  if (controller.entering) return false;
  final failure = await action(controller);
  if (failure != null) {
    messenger?.showSnackBar(SnackBar(content: Text(matchFailureText(l, failure))));
    return false;
  }
  final room = container.read(matchRoomProvider);
  if (room == null) return false;
  unawaited(router.push(matchRoute(room.roomId)));
  return true;
}
```

**Membri.** `lib/features/match/match_members_bar.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/social/match_models.dart';
import '../../ui/user_avatar.dart';

/// Diametro degli avatar dei membri.
const _avatarSize = 40.0;

/// I membri della sala con l'avatar e il nome, chi ha aperto per primo (spec
/// P §7.3). La votazione aggiunge i conteggi (piano 22c).
class MatchMembersBar extends StatelessWidget {
  const MatchMembersBar({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          for (final member in state.members)
            Row(
              key: ValueKey('match-member-${member.userId}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar.lookup(
                    userId: member.userId, name: member.name, size: _avatarSize),
                const SizedBox(width: 8),
                Text(member.name),
              ],
            ),
        ],
      );
}
```

**Pagina.** `lib/features/match/match_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/match_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../friends/friends_controller.dart';
import '../friends/friends_panel.dart';
import '../library/library_providers.dart';
import '../profiles/profile_preferences.dart';
import '../tonight/tonight_controller.dart';
import '../tonight/tonight_filters_bar.dart';
import '../tonight/tonight_logic.dart';
import 'match_actions.dart';
import 'match_members_bar.dart';
import 'match_room_controller.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// La sala del match (spec P §7.3). In questo piano l'attesa; la votazione
/// arriva nel piano 22c. Lasciare la pagina fa uscire dalla sala.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  late final MatchRoomController _controller;
  late TonightFilters _filters;

  /// Amici invitati da questa pagina: il pulsante dice "Invitato".
  final _invited = <String>{};
  bool _starting = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(matchRoomProvider.notifier);
    _filters = readTonightFilters(ref.read(profilePreferencesProvider));
  }

  @override
  void dispose() {
    // Lasciare la pagina fa uscire dalla sala (spec P §7.3). In un microtask:
    // dentro lo smontaggio dell'albero i provider non si cambiano.
    final controller = _controller;
    final roomId = widget.roomId;
    scheduleMicrotask(() => unawaited(controller.leave(roomId)));
    super.dispose();
  }

  bool _isThisRoom(MatchRoomView? view) =>
      view != null &&
      normalizeMatchId(view.roomId) == normalizeMatchId(widget.roomId);

  /// La sala è chiusa, persa o lasciata altrove: la pagina si chiude, con
  /// "Sala chiusa" se non è partito il party (piano 22b, decisione 8).
  void _onRoom(MatchRoomView? view) {
    if (_closing) return;
    final ours = _isThisRoom(view);
    if (ours && !view!.closed) return;
    _closing = true;
    final notice = ours &&
        view!.state?.closedReason != MatchClosedReason.partyStarted;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (notice) {
        messenger?.showSnackBar(SnackBar(content: Text(l.matchClosed)));
      }
      final router = GoRouter.of(context);
      if (router.canPop()) router.pop();
    });
  }

  void _setFilters(TonightFilters next) {
    setState(() => _filters = next);
    unawaited(writeTonightFilters(ref.read(profilePreferencesProvider), next));
  }

  Future<void> _invite(String userId) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failure = await _controller.invite([userId]);
    if (!mounted) return;
    if (failure == null) {
      setState(() => _invited.add(userId));
    } else {
      messenger?.showSnackBar(
          SnackBar(content: Text(matchFailureText(l, failure))));
    }
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _starting = true);
    final failure = await _controller.start(_filters);
    if (!mounted) return;
    setState(() => _starting = false);
    if (failure != null) {
      messenger?.showSnackBar(
          SnackBar(content: Text(matchFailureText(l, failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen(matchRoomProvider, (_, view) => _onRoom(view));
    final view = ref.watch(matchRoomProvider);
    final state = _isThisRoom(view) ? view!.state : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 12),
          child: Text(l.matchTitle.toUpperCase(), style: WfText.display(40)),
        ),
        Expanded(
          child: state == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  children: [
                    MatchMembersBar(state: state),
                    const SizedBox(height: 32),
                    if (state.phase == MatchPhase.waiting) _waiting(l, state),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _waiting(AppLocalizations l, MatchState state) {
    if (!state.isCreator(ref.watch(currentUserIdProvider))) {
      return Text(l.matchWaitingFor(state.creatorName),
          style: _muted.copyWith(fontSize: 16));
    }
    final enough = state.members.length >= matchMinMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TonightFiltersBar(filters: _filters, onChanged: _setFilters),
        const SizedBox(height: 32),
        _InviteFriends(state: state, invited: _invited, onInvite: _invite),
        const SizedBox(height: 32),
        Row(
          children: [
            WfButton.primary(
              key: const Key('match-start'),
              label: l.matchStart,
              icon: LucideIcons.play,
              onPressed: enough && !_starting ? () => unawaited(_start()) : null,
            ),
            if (!enough) ...[
              const SizedBox(width: 16),
              Flexible(child: Text(l.matchNeedFriend, style: _muted)),
            ],
          ],
        ),
      ],
    );
  }
}

/// Diametro degli avatar degli amici da invitare.
const _friendAvatarSize = 32.0;

/// Gli amici online, fuori da un watch party e non ancora nella sala, con
/// "Invita" (spec P §7.3). Un nuovo clic su "Invitato" rimanda l'invito.
class _InviteFriends extends ConsumerWidget {
  const _InviteFriends(
      {required this.state, required this.invited, required this.onInvite});

  final MatchState state;
  final Set<String> invited;
  final Future<void> Function(String userId) onInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friends = ref.watch(friendsControllerProvider.select(
        (s) => s.snapshot.friends));
    final online = [
      for (final FriendEntry friend in sortFriends(friends))
        if (friend.online && friend.party == null && !state.hasMember(friend.userId))
          friend,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.matchFriendsOnline,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        if (online.isEmpty) Text(l.matchNoFriendsOnline, style: _muted),
        for (final friend in online)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                UserAvatar.lookup(
                    userId: friend.userId,
                    name: friend.name,
                    size: _friendAvatarSize),
                const SizedBox(width: 12),
                Expanded(child: Text(friend.name)),
                TextButton(
                  key: Key('match-invite-${friend.userId}'),
                  onPressed: () => unawaited(onInvite(friend.userId)),
                  style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                  child: Text(invited.contains(friend.userId)
                      ? l.matchInvited
                      : l.matchInviteFriend),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

(`WfText.display` sta in `lib/app/theme.dart` come `WfColors`, se no correggi l'import. `friendsControllerProvider` serve acceso: con la funzione `friends` si carica da solo.)

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi i test di `test/features/tonight/`.
Expected: PASS. Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): match room page with filters and friend invites"
```

### Task 5: ingressi in Home e nel pannello Amici

**Files:**
- Create: `lib/features/match/match_entry.dart`
- Modify: `lib/features/home/home_screen.dart`, `lib/features/friends/friends_panel.dart`
- Test: `test/features/match/match_entry_test.dart`, `test/features/match/match_friends_entry_test.dart`

**Interfaces:**
- Consumes: `matchRoomProvider` (Task 3); `openMatchRoom` (Task 4); `SocialFeatures.match` (Task 2); `syncPlayAccessProvider`, `watchPartySessionProvider`.
- Produces: `final matchEntryProvider = Provider<bool>(...)`; `class MatchButton extends ConsumerWidget {VoidCallback onPressed}` (chiave `match-button`, nascosto senza `matchEntryProvider`).

- [ ] **Step 1: test che falliscono**

`test/features/match/match_entry_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/match/match_entry.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  var pressed = 0;

  setUp(() {
    match = FakeMatchApi();
    pressed = 0;
  });

  Future<ProviderContainer> pumpButton(WidgetTester tester,
      {SocialFeatures features = const SocialFeatures(friends: true, match: true),
      SyncPlayAccess? access}) async {
    await pumpApp(
      tester,
      Scaffold(body: Center(child: MatchButton(onPressed: () => pressed++))),
      overrides: [
        ...socialTestOverrides(FakeSocialApi(), features: features),
        matchApiProvider.overrideWithValue(match),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        partyChannelApiProvider
            .overrideWithValue(FakePartyChannelApi()..install()),
        if (access != null) syncPlayAccessProvider.overrideWithValue(access),
      ],
    );
    return ProviderScope.containerOf(tester.element(find.byType(MatchButton)));
  }

  testWidgets('theEntriesNeedFeatureCanCreateAndNoRoom', (tester) async {
    final container = await pumpButton(tester);
    expect(find.byKey(const Key('match-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('match-button')));
    expect(pressed, 1);

    // Già in una sala: niente pulsante.
    await container.read(matchRoomProvider.notifier).open();
    await tester.pump();
    expect(find.byKey(const Key('match-button')), findsNothing);
    await container.read(matchRoomProvider.notifier).leave();
    await tester.pump();
    expect(find.byKey(const Key('match-button')), findsOneWidget);
  });

  testWidgets('senza la funzione o senza il permesso di creare, niente',
      (tester) async {
    await pumpButton(tester, features: const SocialFeatures(friends: true));
    expect(find.byKey(const Key('match-button')), findsNothing);

    await pumpButton(tester, access: SyncPlayAccess.joinOnly);
    expect(find.byKey(const Key('match-button')), findsNothing);
  });
}
```

`test/features/match/match_friends_entry_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/features/friends/friends_panel.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  testWidgets('"Match del film" nel pannello Amici apre una sala e chiude il '
      'pannello', (tester) async {
    final match = FakeMatchApi();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
      ),
      GoRoute(
          path: '/match/:id',
          builder: (_, state) => Text('pagina ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: [
      ...socialTestOverrides(FakeSocialApi(),
          features: const SocialFeatures(friends: true, match: true)),
      matchApiProvider.overrideWithValue(match),
      syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      partyChannelApiProvider
          .overrideWithValue(FakePartyChannelApi()..install()),
    ]);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.friends);
    await tester.pump();

    await tester.tap(find.byKey(const Key('friends-match')));
    await tester.pumpAndSettle();

    expect(match.calls, ['open']);
    expect(find.text('pagina r1'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });
}
```

(Se `syncPlayApiProvider` o `partyChannelApiProvider` stanno in un altro file, correggi l'import come negli altri test del pannello Amici.)

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/match/match_entry_test.dart test/features/match/match_friends_entry_test.dart`
Expected: errori di compilazione (`MatchButton`, chiave `friends-match`).

- [ ] **Step 3: il codice**

`lib/features/match/match_entry.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_providers.dart';
import '../watch_party/watch_party_session.dart';
import 'match_room_controller.dart';

/// Gli ingressi "Match" si vedono (spec P §7.1–7.2): con la funzione del
/// plugin, il permesso di creare gruppi, fuori da un watch party e fuori da
/// una sala (piano 22b, decisione 10).
final matchEntryProvider = Provider<bool>((ref) {
  if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
    return false;
  }
  if (!ref.watch(syncPlayAccessProvider.select((a) => a.canCreate))) {
    return false;
  }
  if (ref.watch(watchPartySessionProvider.select((s) => s.phase)) !=
      WatchPartyPhase.none) {
    return false;
  }
  final room = ref.watch(matchRoomProvider);
  return room == null || room.closed;
});

/// "Match" in Home, accanto a "Cosa guardo stasera?" (spec P §7.2). Come
/// `TonightButton` non agisce da solo: [onPressed] è di chi lo mette.
class MatchButton extends ConsumerWidget {
  const MatchButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(matchEntryProvider)) return const SizedBox.shrink();
    return WfButton.secondary(
      key: const Key('match-button'),
      label: AppLocalizations.of(context).matchButton,
      icon: LucideIcons.heartHandshake,
      onPressed: onPressed,
    );
  }
}
```

In `lib/features/home/home_screen.dart` (con gli import di `../match/match_actions.dart` e `../match/match_entry.dart`):
- dopo `_openTonight`:

```dart
  /// "Match": con il contesto della Home, come "Cosa guardo stasera?".
  void _openMatch() => unawaited(openMatchRoom(context, ref));
```

- un widget in fondo al file:

```dart
/// "Match" e "Cosa guardo stasera?" uno accanto all'altro (spec P §7.2).
class _EntryButtons extends StatelessWidget {
  const _EntryButtons({required this.onTonight, required this.onMatch});

  final VoidCallback onTonight;
  final VoidCallback onMatch;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          MatchButton(onPressed: onMatch),
          TonightButton(onPressed: onTonight),
        ],
      );
}
```

- nei tre posti dove c'è `TonightButton(onPressed: _openTonight)` (stato vuoto, `corner:` di `HeroCarousel`, `_TonightCorner`) usa `_EntryButtons(onTonight: _openTonight, onMatch: _openMatch)`. `_TonightCorner` riceve anche `onMatch` e lo passa.

In `lib/features/friends/friends_panel.dart` (con gli import di `../match/match_actions.dart` e `../match/match_entry.dart`), dopo il `Padding` del campo di ricerca e prima di "Ho un codice":

```dart
          if (ref.watch(matchEntryProvider))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
                child: TextButton.icon(
                  key: const Key('friends-match'),
                  onPressed: () {
                    ref.read(shellPanelProvider.notifier).close();
                    unawaited(openMatchRoom(context, ref));
                  },
                  icon: const Icon(LucideIcons.heartHandshake, size: 16),
                  label: Text(l.matchTitle),
                  style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                ),
              ),
            ),
```

(Se durante la ricerca "Ho un codice" sparisce, fai sparire anche questo nello stesso modo, dentro la stessa `Visibility`.)

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `test/features/home/`.
Expected: PASS (nei test della Home la funzione `match` è spenta: il pulsante non c'è e i test esistenti non cambiano). Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): match entries in home and friends panel"
```

### Task 6: inviti, carta e voce nella cassetta

**Files:**
- Create: `lib/features/watch_party/invite_card_frame.dart`, `lib/features/match/match_invites.dart`
- Modify: `lib/features/watch_party/watch_party_invites.dart`, `lib/app/app_shell.dart`, `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart`, `test/support/social_fakes.dart`
- Test: `test/features/match/match_invites_test.dart`, `test/features/inbox/inbox_match_invite_test.dart`, `test/core/social/inbox_models_test.dart` (test nuovo)

**Interfaces:**
- Consumes: `MatchInviteEvent` (Task 2); `matchRoomProvider` (Task 3); `joinMatchRoom` (Task 4); `watchPartyInvitesProvider`, `playerActiveProvider`.
- Produces:
  - `class InviteCardFrame extends StatelessWidget {IconData icon; String title; String? subtitle; VoidCallback onDismiss; VoidCallback onJoin}` e `class InviteCardSlot extends StatelessWidget {Object? id; Widget? card}`;
  - `class MatchInvites extends Notifier<MatchInviteEvent?>` con `showFor` (10 s) e `dismiss()`; `matchInvitesProvider`; `class MatchInviteCard extends ConsumerWidget` (chiave della carta `match-invite`);
  - `final class MatchInviteEntry extends InboxEntry {String roomId; String fromName;}`; `testMatchInviteEntry(...)` in `social_fakes.dart`.

- [ ] **Step 1: test che falliscono**

`test/features/match/match_invites_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/features/match/match_invites.dart';
import 'package:wonderflix/features/match/match_providers.dart';
import 'package:wonderflix/features/match/match_room_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/match_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeMatchApi match;
  late StreamController<ServerEvent> events;

  setUp(() {
    match = FakeMatchApi();
    events = StreamController<ServerEvent>.broadcast();
  });

  tearDown(() => events.close());

  List<Override> overrides() => [
        ...socialTestOverrides(FakeSocialApi(),
            events: events.stream,
            features: const SocialFeatures(friends: true, parties: true, match: true)),
        matchApiProvider.overrideWithValue(match),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
      ];

  test('un invito resta 10 s; non con il player aperto né dentro una sala', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: overrides(), retry: (_, _) => null);
      addTearDown(container.dispose);
      container.listen(matchInvitesProvider, (_, _) {});
      async.flushMicrotasks();

      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider)?.roomId, 'r2');
      async.elapse(MatchInvites.showFor);
      expect(container.read(matchInvitesProvider), isNull);

      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider), isNull);
      container.read(playerActiveProvider.notifier).leave();
      async.flushMicrotasks();

      unawaited(container.read(matchRoomProvider.notifier).open());
      async.flushMicrotasks();
      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider), isNull);
    });
  });

  test('un invito alla volta: il match chiude il party e viceversa', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: overrides(), retry: (_, _) => null);
      addTearDown(container.dispose);
      container.listen(matchInvitesProvider, (_, _) {});
      container.listen(watchPartyInvitesProvider, (_, _) {});
      async.flushMicrotasks();

      events.add(partyInviteReceived('g1', 'Peach · Up', 'Peach'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider), isNotNull);

      events.add(matchInviteReceived('r2', 'Luigi'));
      async.flushMicrotasks();
      expect(container.read(matchInvitesProvider)?.roomId, 'r2');
      expect(container.read(watchPartyInvitesProvider), isNull);

      events.add(partyInviteReceived('g2', 'Toad · Alien', 'Toad'));
      async.flushMicrotasks();
      expect(container.read(watchPartyInvitesProvider), isNotNull);
      expect(container.read(matchInvitesProvider), isNull);
    });
  });

  testWidgets('la carta: chi invita, X chiude, Unisciti entra e apre la sala',
      (tester) async {
    match.rooms['r2'] = testMatchState(
        roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi');
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
              body: Align(
                  alignment: Alignment.topRight, child: MatchInviteCard()))),
      GoRoute(
          path: '/match/:id',
          builder: (_, state) => Text('pagina ${state.pathParameters['id']}')),
    ]);
    await pumpAppRouter(tester, router, overrides: overrides());

    events.add(matchInviteReceived('r2', 'Luigi'));
    await tester.pumpAndSettle();
    expect(find.text('Luigi ti invita a un match'), findsOneWidget);

    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(match.calls, ['join r2']);
    expect(find.text('pagina r2'), findsOneWidget);
  });
}
```

(Se `pumpAppRouter` non mostra `Scaffold`/`ScaffoldMessenger` per le snackbar, il test non ne ha bisogno. Se `testUser` non serve, togli l'import.)

`test/features/inbox/inbox_match_invite_test.dart`, con il montaggio di `inbox_recommendation_test.dart` (pannello dentro un `GoRouter` che ha anche `/match/:id` → `Text('pagina ${id}')`, `socialTestOverrides(api, features: const SocialFeatures(inbox: true, match: true))`, `matchApiProvider.overrideWithValue(match)`):

```dart
  testWidgets('invito al match: chi invita, Unisciti entra, apre la sala e '
      'chiude il pannello', (tester) async {
    match.rooms['r2'] = testMatchState(roomId: 'r2', creatorId: 'u2', creatorName: 'Luigi');
    final container = await pumpPanel(tester, [testMatchInviteEntry()]);

    expect(find.textContaining('Luigi ti invita a un match'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-match-join-mi1')));
    await tester.pumpAndSettle();

    expect(match.calls, ['join r2']);
    expect(find.text('pagina r2'), findsOneWidget);
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  testWidgets('anOldMatchInviteSaysWhy', (tester) async {
    match.failures['join r2'] = const MatchException(MatchFailure.started);
    final container = await pumpPanel(tester, [testMatchInviteEntry()]);

    await tester.tap(find.byKey(const Key('inbox-match-join-mi1')));
    await tester.pumpAndSettle();

    expect(find.text('Il match è già iniziato'), findsOneWidget);
    expect(find.textContaining('pagina'), findsNothing);
    expect(container.read(shellPanelProvider), ShellPanel.inbox);
  });
```

(Il `pumpPanel` del file nuovo è quello di `inbox_recommendation_test.dart` con le due aggiunte; le snackbar hanno bisogno di uno `Scaffold`, che quel montaggio ha.)

In `test/core/social/inbox_models_test.dart`:

```dart
  test('voce d\'invito al match', () {
    final entry = inboxEntryFromJson({
      'Id': 'mi1',
      'Seq': 3,
      'CreatedAt': '2026-10-14T20:00:00Z',
      'Read': false,
      'Type': 'MatchInvite',
      'RoomId': 'r2',
      'FromName': 'Luigi',
    });
    expect(entry, isA<MatchInviteEntry>());
    expect((entry! as MatchInviteEntry).roomId, 'r2');
    expect((entry as MatchInviteEntry).fromName, 'Luigi');
  });
```

In `test/support/social_fakes.dart`, dopo `testRecommendationEntry`:

```dart
/// Un invito al match nella cassetta: Luigi, sala `r2`.
MatchInviteEntry testMatchInviteEntry({
  String id = 'mi1',
  int seq = 1,
  bool read = false,
  String roomId = 'r2',
  String fromName = 'Luigi',
}) =>
    MatchInviteEntry(
      id: id,
      seq: seq,
      createdAt: DateTime.utc(2026, 10, 14, 20),
      read: read,
      roomId: roomId,
      fromName: fromName,
    );
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/match/match_invites_test.dart test/features/inbox/inbox_match_invite_test.dart test/core/social/inbox_models_test.dart`
Expected: errori di compilazione (`MatchInvites`, `MatchInviteCard`, `MatchInviteEntry` non esistono).

- [ ] **Step 3: il codice**

`lib/features/watch_party/invite_card_frame.dart`: sposta qui, invariati, l'`AnimatedSwitcher` di `WatchPartyInviteCard.build` e il `Material` di `_card`, come due widget:

```dart
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';

/// Il posto della carta d'invito in alto a destra (spec C §11.4): entra da
/// destra e se ne va in dissolvenza; quella che esce non riceve più clic.
/// [card] `null` = nessun invito; [id] distingue un invito dall'altro.
class InviteCardSlot extends StatelessWidget {
  const InviteCardSlot({super.key, required this.id, required this.card});

  final Object? id;
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final current = card == null
        ? const SizedBox.shrink(key: ValueKey('no-invite'))
        : KeyedSubtree(key: ValueKey(id), child: card!);
    return AnimatedSwitcher(
      duration: WfMotion.of(context).duration(WfMotion.medium),
      transitionBuilder: (child, animation) => IgnorePointer(
        // L'invito che se ne va non accetta più "Unisciti".
        ignoring: child.key != current.key,
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.3, 0), end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation, curve: WfMotion.emphasized)),
            child: child,
          ),
        ),
      ),
      child: current,
    );
  }
}

/// La carta d'invito (watch party e match, spec P §7.2): icona, titolo,
/// sottotitolo, X e "Unisciti".
class InviteCardFrame extends StatelessWidget {
  const InviteCardFrame({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onDismiss,
    required this.onJoin,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onDismiss;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subtitle = this.subtitle;
    return Material(
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: WfColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 26, right: 8),
                  child: Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: WfColors.creamMuted)),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: WfButton.primary(
                  label: l.watchPartyJoin,
                  icon: LucideIcons.play,
                  onPressed: onJoin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `lib/features/watch_party/watch_party_invites.dart`, `WatchPartyInviteCard.build` diventa (e `_card` sparisce, con gli import non più usati):

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final invite = ref.watch(watchPartyInvitesProvider);
    final invites = ref.read(watchPartyInvitesProvider.notifier);
    final names = invite == null ? null : partyNameParts(invite.group);
    return InviteCardSlot(
      id: invite?.group.id,
      card: invite == null
          ? null
          : InviteCardFrame(
              key: const Key('watch-party-invite'),
              icon: LucideIcons.users,
              title: invite.invitedBy != null
                  ? l.partyInviteTitle(invite.invitedBy!)
                  : l.watchPartyInviteTitle(names!.host),
              subtitle: names!.title,
              onDismiss: invites.dismiss,
              onJoin: () {
                invites.dismiss();
                unawaited(joinWatchParty(context, ref, invite.group.id));
              },
            ),
    );
  }
```

I test di `watch_party_invite_card_test.dart` devono restare verdi senza modifiche.

`lib/features/match/match_invites.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import '../social/social_providers.dart';
import '../watch_party/invite_card_frame.dart';
import '../watch_party/watch_party_invites.dart';
import 'match_actions.dart';
import 'match_room_controller.dart';

/// Invito a una sala del match appena arrivato (spec P §7.2): per
/// [showFor]; non con il player aperto né stando già in una sala. Si vede un
/// invito alla volta (piano 22b, decisione 6).
class MatchInvites extends Notifier<MatchInviteEvent?> {
  static const showFor = Duration(seconds: 10);

  Timer? _timer;

  @override
  MatchInviteEvent? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _timer?.cancel();
    _timer = null;
    ref.onDispose(() => _timer?.cancel());
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.match))) {
      return null;
    }
    final subscription = ref.watch(socialEventsProvider).listen((event) {
      if (event is MatchInviteEvent) _show(event);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    // Un invito al party arrivato dopo prende il posto di questo.
    ref.listen(watchPartyInvitesProvider, (_, invite) {
      if (invite != null) dismiss();
    });
    return null;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _show(MatchInviteEvent event) {
    if (ref.read(playerActiveProvider)) return;
    final room = ref.read(matchRoomProvider);
    if (room != null && !room.closed) return;
    ref.read(watchPartyInvitesProvider.notifier).dismiss();
    _timer?.cancel();
    state = event;
    _timer = Timer(showFor, dismiss);
  }
}

final matchInvitesProvider =
    NotifierProvider<MatchInvites, MatchInviteEvent?>(MatchInvites.new);

/// La carta dell'invito al match, nello stesso posto di quella del party.
class MatchInviteCard extends ConsumerWidget {
  const MatchInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final invite = ref.watch(matchInvitesProvider);
    final invites = ref.read(matchInvitesProvider.notifier);
    return InviteCardSlot(
      id: invite?.roomId,
      card: invite == null
          ? null
          : InviteCardFrame(
              key: const Key('match-invite'),
              icon: LucideIcons.heartHandshake,
              title: l.matchInviteFrom(invite.fromName),
              onDismiss: invites.dismiss,
              onJoin: () {
                invites.dismiss();
                unawaited(joinMatchRoom(context, ref, invite.roomId));
              },
            ),
    );
  }
}
```

In `lib/app/app_shell.dart` (con l'import di `../features/match/match_invites.dart`), nella `Column` degli inviti: `children: [WatchPartyInviteCard(), MatchInviteCard(), FriendRequestCard()]`, e nel commento sopra "e invito a una sala del match (spec P §7.2)".

In `lib/core/social/inbox_models.dart`, dopo `RecommendationEntry`:

```dart
/// Un amico ci invita nella sua sala del match (spec P §6.5).
final class MatchInviteEntry extends InboxEntry {
  const MatchInviteEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.roomId,
    required this.fromName,
  });

  final String roomId;
  final String fromName;
}
```

e in `inboxEntryFromJson`, prima di `_ => null`:

```dart
    'MatchInvite' => MatchInviteEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        roomId: json['RoomId'] as String,
        fromName: json['FromName'] as String? ?? '',
      ),
```

In `lib/features/inbox/inbox_panel.dart` (con l'import di `../match/match_actions.dart`):
- nel primo `switch (entry)` (icona): `MatchInviteEntry() => const InboxRequestIcon(icon: LucideIcons.heartHandshake, size: InboxPanel.leadingSize),`;
- nel secondo (contenuto): `MatchInviteEntry() => _MatchInviteContent(entry: entry, time: widget.time),`;
- dopo `_InviteContent`:

```dart
/// Invito al match: chi invita e "Unisciti" (spec P §7.2). Il plugin dice
/// se la sala c'è ancora: un no diventa un avviso con il motivo.
class _MatchInviteContent extends ConsumerStatefulWidget {
  const _MatchInviteContent({required this.entry, required this.time});

  final MatchInviteEntry entry;
  final String time;

  @override
  ConsumerState<_MatchInviteContent> createState() =>
      _MatchInviteContentState();
}

class _MatchInviteContentState extends ConsumerState<_MatchInviteContent> {
  /// Un ingresso partito da questa voce è in corso (come per i party).
  bool _joining = false;

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    final panel = ref.read(shellPanelProvider.notifier);
    try {
      final joined = await joinMatchRoom(context, ref, widget.entry.roomId);
      if (joined) panel.close();
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entry = widget.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
            _inviteFromSpan(l.matchInviteFrom(entry.fromName), entry.fromName),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _mutedStyle),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(widget.time,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _timeStyle),
            ),
            TextButton(
              key: Key('inbox-match-join-${entry.id}'),
              onPressed: _joining ? null : () => unawaited(_join()),
              style: TextButton.styleFrom(
                foregroundColor: WfColors.gold,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(l.watchPartyJoin),
            ),
          ],
        ),
      ],
    );
  }
}
```

(Cerca con `grep` altri `switch` esaustivi su `InboxEntry` in `lib/` e completali allo stesso modo.)

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `test/features/watch_party/` e `test/features/inbox/`.
Expected: PASS. Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): match invite card and inbox entry"
```

### Task 7: uscita dalla sala cambiando profilo

**Files:**
- Modify: `lib/features/profiles/profile_switch.dart`
- Test: `test/features/profiles/profile_switch_test.dart` (test nuovo)

**Interfaces:**
- Consumes: `matchRoomProvider`, `MatchRoomController.leave` (Task 3); `partyLeaveTimeout`.

- [ ] **Step 1: test che fallisce**

In `test/features/profiles/profile_switch_test.dart` (con gli import di `match_providers.dart`, `match_room_controller.dart`, `social_providers.dart`, `watch_party_providers.dart`, `../../support/match_fakes.dart` e `../../support/social_fakes.dart`):
- un campo `late FakeMatchApi match;`, creato in `pumpButton` con `match = FakeMatchApi();`;
- negli `overrides` di `pumpButton`, dopo quelli di oggi (così `changeProfile` legge una sala del match finta, mai il plugin vero):

```dart
        socialAvailabilityProvider.overrideWith(
            () => FakeSocialAvailability(const SocialFeatures(match: true))),
        matchApiProvider.overrideWithValue(match),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
```

- un test nuovo:

```dart
  testWidgets('cambiando profilo si esce dalla sala del match', (tester) async {
    await pumpButton(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.text('vai')));
    await container.read(matchRoomProvider.notifier).open();

    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();

    expect(match.calls, ['open', 'leave r1']);
    expect(container.read(matchRoomProvider), isNull);
    expect(session.switchCalls, 1);
  });
```

Gli altri test del file restano com'erano: senza sala aperta il cambio resta immediato.

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/profiles/profile_switch_test.dart`
Expected: FAIL (`leave r1` non c'è).

- [ ] **Step 3: il codice**

In `lib/features/profiles/profile_switch.dart` (con l'import di `../match/match_room_controller.dart`):
- dopo `final userId = …` leggi `final match = ref.read(matchRoomProvider.notifier);`;
- nel commento della funzione aggiungi "Esce anche dalla sala del match (spec P §7.3)";
- prima di `if (addProfile)`:

```dart
  // Spec P §7.3: una sala lasciata aperta resterebbe al profilo di prima.
  if (container.read(matchRoomProvider) != null) {
    try {
      await match.leave().timeout(partyLeaveTimeout);
    } on TimeoutException {
      _log.info('uscita dalla sala del match lenta: si cambia profilo lo stesso');
    }
    final now = container.read(sessionControllerProvider);
    if (userId == null || now is! SessionSignedIn || now.user.id != userId) {
      return;
    }
  }
```

- [ ] **Step 4: il test passa**

Run: lo stesso comando dello Step 2.
Expected: PASS. Poi `flutter analyze` e la suite intera: verdi.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): leave the match room when switching profile"
```

---

## Gruppo D — chiusura

### Task 8: allineamento della spec e build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md`
- Modify: `docs/superpowers/plans/2026-10-16-wonderflix-22b-match-sala-app.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** aggiungi "piano 22b realizzato (`docs/superpowers/plans/2026-10-16-wonderflix-22b-match-sala-app.md`)".
- **§7.1:** le chiamate stanno in `MatchApi` (`MatchException` con motivo e `RoomId`), non in `SocialApi` (decisione 1); `start` con i valori `wire` (decisione 2).
- **§7.2:** la carta d'invito: due notifier con cornice comune, un invito alla volta (decisione 6); la sala fantasma si lascia e si riprova una volta (decisione 4); ingressi nascosti anche dentro una sala (decisione 10).
- **§7.3:** una sala sola nell'app (decisione 3); filtri condivisi con "Cosa guardo stasera?" (decisione 5); uscita con la pagina e il cambio di profilo, non chiudendo la finestra (decisione 7); stati con `Rev` più alto (decisione 9).
- **§9:** `matchFriendsOnline`, `matchNoFriendsOnline` (decisione 11).
- **§13:** 22b realizzato; il 22c fa votazione, avvio del party e versione 0.16.0.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 2: build**

`flutter analyze`, la suite intera (`flutter test --concurrency=4`) e la build di release per la prova a mano: copia `config/wonderflix.json` del checkout principale nel worktree (non si committa), poi `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.

- [ ] **Step 3: commit**

```powershell
git add docs
git commit -m "docs: align the movie match spec with plan 22b"
```

### Task 9: STOP — prova a mano con l'utente

Il subagent si ferma dopo il Task 8. L'orchestratore fa la review finale del branch e i ritocchi, poi chiede all'utente la prova a mano. Il plugin 1.10.0 è già sul server (piano 22a).

Prova con due istanze (`WONDERFLIX_PROFILE=b`) e due utenti amici, con l'exe di release del worktree:
1. "Match" in Home (accanto a "Cosa guardo stasera?") e "Match del film" nel pannello Amici aprono la pagina della sala con i filtri e gli amici online.
2. "Invita" sull'altro: gli arriva la carta in alto a destra e la voce nella cassetta. "Unisciti" dalla carta, poi una seconda prova dalla cassetta, apre la sala; chi ha aperto vede il secondo membro.
3. "Inizia" si accende con due membri; dopo l'inizio la pagina mostra i membri (la votazione è del 22c).
4. Esc o ← fa uscire dalla sala; se esce chi l'ha aperta, l'altro vede "Sala chiusa" e torna indietro.
5. Una voce di cassetta vecchia (sala chiusa o già iniziata) dice il motivo.
6. Il cambio di profilo dentro una sala esce dalla sala.

### Task 10: ok dell'utente e merge

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente release: l'app 0.16.0 esce alla fine del 22c.
