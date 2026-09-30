# WonderFlix — Piano 5c: entrare, restare, contorno del watch party

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** chiudere lo Spec B:
- **permessi** (`SyncPlayAccess`): con "solo entrare" niente "Guarda insieme"; senza accesso nessun elemento del watch party;
- **inviti**: "Davide ha avviato un watch party · Unisciti", per 10 s, solo dentro l'app, mai con il player aperto né per i gruppi già esistenti all'avvio;
- **barra in alto nel gruppo**: "Nel watch party" con "Torna al player" ed "Esci dal watch party" (anche per un gruppo senza nulla in coda);
- **"Guarda insieme" dal player** mentre si guarda da soli: il gruppo parte dal minuto attuale e il player si riapre sullo stesso punto in modalità gruppo, con lo schermo intero com'è;
- **rientro automatico** nello stesso gruppo a ogni riconnessione del WebSocket (poi il player rimanda `Ready`); se il gruppo non c'è più, avviso "Il watch party è terminato" e il player continua da solo;
- **video che non si apre**: `SetIgnoreWait(true)` (il gruppo non resta bloccato), schermata con "Riprova" ed "Esci dal watch party"; "Riprova" riuscito → `SetIgnoreWait(false)` e `Ready`;
- tolti dal gruppo dal server: il salto automatico dell'intro torna attivo;
- **Discord**: stato "Watch party · N persone";
- **"Copia diagnostica"** con lo stato del gruppo.

**Decisioni prese con l'utente (2026-09-30):** un piano unico in cinque gruppi; dal player il video si **riapre** sullo stesso punto (spec §5.2 aggiornato); inviti solo dentro l'app (spec §5.8); rientro a ogni riconnessione, senza limiti (spec §5.5).

**Architecture:**
- `JellyfinUser.syncPlayAccess` (da `Policy.SyncPlayAccess`) e `syncPlayAccessProvider`.
- `WatchPartyInvites` (Notifier) ascolta `WatchPartyDirectory` e propone i gruppi nuovi; `WatchPartyInviteCard` in `AppShell`.
- `WatchPartyButton` diventa "Nel watch party" quando si è in un gruppo.
- `PlayerWindow.isFullScreen()`: il routing, quando trasforma un player da solo in uno del gruppo, mantiene lo schermo intero.
- `WatchPartySession`: rientro su `ServerConnected(isReconnect: true)`, contatore `rejoins` nello stato, inoltro di `GroupDoesNotExist`/`GroupLeft`/`NotInGroup` agli avvisi ("terminato"), `lastDrift`.
- `GroupPlaybackDriver`: `onRejoined()` (rimanda `Ready`), `onUnloaded(failed:)` con `SetIgnoreWait`, `onDrift`.
- `PlayerController.leaveParty()`.
- `MediaSession.setParty(int?)`: Discord mostra "Watch party · N persone".
- `describeWatchParty` per la diagnostica.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, window_manager, `clock` + `fake_async`, `logging`.

**Spec:** `docs/superpowers/specs/2026-09-30-wonderflix-watch-party-design.md` (§5.2, §5.5, §5.8, §5.9, §5.10, §6.3, §7.1). **Piani precedenti:** `…-05a-watch-party-film.md`, `…-05b-watch-party-serie-avvisi.md` (codice su `main`).

---

## Regole per chi esegue

- **Commit:** con l'identità git già configurata (quella dell'utente). **MAI** trailer `Co-Authored-By` o righe "Generated with…". Non fare push.
- **Shell:** Git Bash su Windows. Tutti i comandi partono dalla root del worktree (`.claude/worktrees/watch-party-5c`, branch `feat/watch-party-5c`). Comandi git semplici, non composti con variabili.
- **Prima di ogni commit:** `flutter analyze` senza nessun problema e `flutter test` tutto verde. Se `lib/l10n/gen` manca o è vecchio, esegui prima `flutter gen-l10n`.
- **File generati:** se `flutter test`/`pub get`/`build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** non eseguire `dart format` su file interi.
- **Fine riga:** molti file sono CRLF (ARB, `player_screen.dart`, `app_shell.dart`, …). Edit mirati che mantengono le fini riga; non riscriverli.
- **Import:** se l'analyzer segnala un import superfluo o mancante, correggilo e segnalalo.
- **Icone:** solo `LucideIcons`, niente emoji.
- **Tempo:** solo `clock.now()`, mai `DateTime.now()`.
- **Test e zone:** gli eventi di uno stream arrivano nella zona in cui ci si è iscritti. Nei test con `fakeAsync` il container va creato **dentro** la zona finta.
- **Widget test:** qualunque `Timer` rimasto aperto a fine test fa fallire il test. L'orologio del gruppo ha dei timer: i test del player chiudono tutto con `finish` (smonta, 3 s, `container.dispose()`), gli altri escono dal gruppo a fine test. `find.byType` non trova le sottoclassi: per `WfButton` cerca il testo.
- **Router:** con go_router 18 dopo `push`/`pushReplacement` `routeInformationProvider.value.uri` torna la pagina di base; la pagina in cima è `GoRouter.state.uri` (lezione del 5b).
- **Fake:** niente mocktail. `FakeSyncPlayApi`, `FakeWatchPartyDirectory`, `FakePartyNavigator`, `FakePartyNotices`, `testGroup`, `testQueue`, `testSeriesQueue` in `test/support/watch_party_fakes.dart`; `FakeLibraryApi`, `testItem` in `test/support/library_fakes.dart`; `FakeVideoEngine`, `FakePlayerWindow`, `FakeMediaSession` in `test/support/playback_fakes.dart`; `FakeSessionController` in `test/support/fake_session_controller.dart`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test sfuggito al piano): correggilo in modo minimo, nello spirito del piano, e segnalalo. I test descrivono il comportamento: preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **`Policy.SyncPlayAccess`** è in `UserDto.Policy` (risposte di `/Users/Me` e `/Users/AuthenticateByName`): `CreateAndJoinGroups`, `JoinGroups`, `None`. Se manca si assume `CreateAndJoinGroups` (il server controlla comunque).
- **`POST /SyncPlay/SetIgnoreWait`** con `{"IgnoreWait": true|false}`: con `true` il gruppo non aspetta più i nostri `Ready`/`Buffering`.
- **`Join` di un gruppo in cui la sessione è già** (dopo una riconnessione): il server la "ripristina": manda `GroupJoined` e la coda, mette gli altri in pausa e aspetta il nostro `Ready`. Se la sessione era stata tolta, è un ingresso normale. Gruppo sparito: `GroupDoesNotExist`.
- **`ServerConnected(isReconnect: true)`** arriva da `ServerEventsClient` (stesso stream degli eventi del watch party) a ogni riconnessione del WebSocket.
- **window_manager:** `windowManager.isFullScreen()` → `Future<bool>`.
- **Discord:** la riga `state` dell'attività è quella sotto il titolo; oggi è il sottotitolo (in riproduzione) o "In pausa".

## Mappa dei file

```
l10n/app_it.arb, l10n/app_en.arb                    testi del Piano 5c
lib/core/jellyfin/auth_models.dart                  SyncPlayAccess, JellyfinUser.syncPlayAccess
lib/core/syncplay/syncplay_api.dart                 + setIgnoreWait
lib/core/media_session/media_session.dart           + setParty (e Noop)
lib/core/media_session/mirrored_media_session.dart  + setParty
lib/core/media_session/smtc_media_session.dart      + setParty (nulla)
lib/features/discord/discord_activity.dart          DiscordLabels.party, partySize
lib/features/discord/discord_presence.dart          + setParty
lib/features/discord/discord_providers.dart         etichetta "Watch party · N persone"
lib/features/settings/diagnostics.dart              riga "Watch party"
lib/features/player/player_window.dart              + isFullScreen
lib/features/player/player_controller.dart          + leaveParty
lib/features/player/player_overlay.dart             + onWatchTogether
lib/features/player/player_screen.dart              "Guarda insieme", rientro, errore, Discord, deriva
lib/features/detail/detail_header.dart              permessi
lib/app/app_shell.dart                              scheda d'invito
lib/features/watch_party/watch_party_providers.dart   syncPlayAccessProvider
lib/features/watch_party/watch_party_directory.dart   permessi
lib/features/watch_party/watch_party_invites.dart     WatchPartyInvites, WatchPartyInviteCard (nuovo)
lib/features/watch_party/watch_party_button.dart      "Nel watch party"
lib/features/watch_party/watch_party_actions.dart     esito (bool), nomi del gruppo
lib/features/watch_party/watch_party_routing.dart     schermo intero nel passaggio da solo a gruppo
lib/features/watch_party/watch_party_session.dart     rientro, rejoins, lastDrift, fine del gruppo
lib/features/watch_party/group_playback_driver.dart   onRejoined, onUnloaded(failed:), onDrift
lib/features/watch_party/party_notices.dart           avviso "terminato"
lib/features/watch_party/party_notice_pill.dart       testo "terminato"
```

## Gruppi per i subagent

| Gruppo | Task | Contenuto |
|---|---|---|
| A | 1–3 | testi, permessi (modello e interfaccia) |
| B | 4–5 | inviti, "Nel watch party" nella barra in alto |
| C | 6–7 | schermo intero nel passaggio, "Guarda insieme" dal player |
| D | 8–10 | rientro automatico, video che non si apre, salto dell'intro dopo l'uscita |
| E | 11–13 | Discord, diagnostica, verifica finale |

---

### Task 1: testi del Piano 5c

**Files:**
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/app/l10n_plan5c_test.dart`

- [ ] **Step 1: scrivi il test**

`test/app/l10n_plan5c_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 5c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.watchPartyInviteTitle('Davide'),
        'Davide ha avviato un watch party');
    expect(en.watchPartyInviteTitle('Davide'), 'Davide started a watch party');
    expect(it.watchPartyInParty, 'Nel watch party');
    expect(it.watchPartyBackToPlayer, 'Torna al player');
    expect(it.watchPartyDismiss, 'Chiudi');
    expect(it.watchPartyNoticeEnded, 'Il watch party è terminato');
    expect(en.watchPartyNoticeEnded, 'The watch party has ended');
    expect(it.discordWatchParty(1), 'Watch party · 1 persona');
    expect(it.discordWatchParty(3), 'Watch party · 3 persone');
    expect(en.discordWatchParty(3), 'Watch party · 3 people');
  });
}
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/app/l10n_plan5c_test.dart`
Expected: FAIL (getter mancanti).

- [ ] **Step 3: aggiungi i testi**

`l10n/app_it.arb` (CRLF): con un Edit mirato sull'ultima riga, `"watchPartyNoticeResync": "Riallineamento al gruppo"`, aggiungi la virgola e queste righe prima della `}` finale:

```json
  "watchPartyInviteTitle": "{name} ha avviato un watch party",
  "@watchPartyInviteTitle": {"placeholders": {"name": {"type": "String"}}},
  "watchPartyInParty": "Nel watch party",
  "watchPartyBackToPlayer": "Torna al player",
  "watchPartyDismiss": "Chiudi",
  "watchPartyNoticeEnded": "Il watch party è terminato",
  "discordWatchParty": "Watch party · {count, plural, =1{1 persona} other{{count} persone}}",
  "@discordWatchParty": {"placeholders": {"count": {"type": "int"}}}
```

`l10n/app_en.arb`, stesso metodo dopo `"watchPartyNoticeResync": "Resyncing with the group"`:

```json
  "watchPartyInviteTitle": "{name} started a watch party",
  "watchPartyInParty": "In a watch party",
  "watchPartyBackToPlayer": "Back to the player",
  "watchPartyDismiss": "Dismiss",
  "watchPartyNoticeEnded": "The watch party has ended",
  "discordWatchParty": "Watch party · {count, plural, =1{1 person} other{{count} people}}"
```

Run: `flutter gen-l10n`
Expected: nessun errore.

- [ ] **Step 4: verifica che passi**

Run: `flutter test test/app/l10n_plan5c_test.dart`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add l10n/app_it.arb l10n/app_en.arb test/app/l10n_plan5c_test.dart
git commit -m "feat: add plan 5c watch party strings"
```

---

### Task 2: permessi del watch party

**Files:**
- Modify: `lib/core/jellyfin/auth_models.dart`
- Modify: `lib/features/watch_party/watch_party_providers.dart`
- Test: `test/core/jellyfin/auth_models_test.dart` (nuovo), `test/features/watch_party/watch_party_access_test.dart` (nuovo)

- [ ] **Step 1: scrivi i test**

`test/core/jellyfin/auth_models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';

void main() {
  JellyfinUser user(Object? access) => JellyfinUser.fromJson({
        'Id': 'u1',
        'Name': 'Mario',
        if (access != null) 'Policy': {'SyncPlayAccess': access},
      });

  test('SyncPlayAccess dalla policy dell\'utente', () {
    expect(user('CreateAndJoinGroups').syncPlayAccess,
        SyncPlayAccess.createAndJoin);
    expect(user('JoinGroups').syncPlayAccess, SyncPlayAccess.joinOnly);
    expect(user('None').syncPlayAccess, SyncPlayAccess.none);
  });

  test('senza policy o con un valore sconosciuto: accesso completo', () {
    expect(user(null).syncPlayAccess, SyncPlayAccess.createAndJoin);
    expect(user('Boh').syncPlayAccess, SyncPlayAccess.createAndJoin);
    expect(const JellyfinUser(id: 'u1', name: 'Mario').syncPlayAccess,
        SyncPlayAccess.createAndJoin);
  });

  test('cosa permette ciascun valore', () {
    expect(SyncPlayAccess.createAndJoin.canCreate, isTrue);
    expect(SyncPlayAccess.createAndJoin.canJoin, isTrue);
    expect(SyncPlayAccess.joinOnly.canCreate, isFalse);
    expect(SyncPlayAccess.joinOnly.canJoin, isTrue);
    expect(SyncPlayAccess.none.canCreate, isFalse);
    expect(SyncPlayAccess.none.canJoin, isFalse);
  });
}
```

`test/features/watch_party/watch_party_access_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import '../../support/fake_session_controller.dart';

void main() {
  SyncPlayAccess accessFor(SessionState session) {
    final container = ProviderContainer.test(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(session)),
    ]);
    return container.read(syncPlayAccessProvider);
  }

  test('dell\'utente collegato; nessuno senza sessione', () {
    expect(
        accessFor(const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.joinOnly))),
        SyncPlayAccess.joinOnly);
    expect(accessFor(const SessionSignedIn(JellyfinUser(id: 'u1', name: 'Mario'))),
        SyncPlayAccess.createAndJoin);
    expect(accessFor(const SessionSignedOut()), SyncPlayAccess.none);
  });
}
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/jellyfin/auth_models_test.dart test/features/watch_party/watch_party_access_test.dart`
Expected: FAIL (`SyncPlayAccess` non definito).

- [ ] **Step 3: il modello**

In `lib/core/jellyfin/auth_models.dart`, prima di `class JellyfinUser`:

```dart
/// Cosa può fare l'utente con i watch party (`Policy.SyncPlayAccess`, spec B
/// §5.9). Il server lo controlla comunque: qui decide cosa mostrare.
enum SyncPlayAccess {
  createAndJoin,
  joinOnly,
  none;

  bool get canCreate => this == createAndJoin;

  bool get canJoin => this != none;
}

/// Valore sconosciuto o assente: accesso completo (decide il server).
SyncPlayAccess _syncPlayAccess(Object? policy) {
  final value =
      policy is Map<String, dynamic> ? policy['SyncPlayAccess'] : null;
  return switch (value) {
    'JoinGroups' => SyncPlayAccess.joinOnly,
    'None' => SyncPlayAccess.none,
    _ => SyncPlayAccess.createAndJoin,
  };
}
```

e sostituisci la classe `JellyfinUser` con:

```dart
class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    this.primaryImageTag,
    this.syncPlayAccess = SyncPlayAccess.createAndJoin,
  });

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String,
        name: json['Name'] as String,
        primaryImageTag: json['PrimaryImageTag'] as String?,
        syncPlayAccess: _syncPlayAccess(json['Policy']),
      );

  final String id;
  final String name;
  final String? primaryImageTag;
  final SyncPlayAccess syncPlayAccess;
}
```

- [ ] **Step 4: il provider**

In `lib/features/watch_party/watch_party_providers.dart` aggiungi gli import `import '../../core/jellyfin/auth_models.dart';` e `import '../auth/session_controller.dart';` e in fondo:

```dart
/// Permessi del watch party dell'utente collegato; nessuno senza sessione.
final syncPlayAccessProvider = Provider<SyncPlayAccess>((ref) {
  final session = ref.watch(sessionControllerProvider);
  return session is SessionSignedIn
      ? session.user.syncPlayAccess
      : SyncPlayAccess.none;
});
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/core/jellyfin/ test/features/watch_party/`
Expected: PASS.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/jellyfin/auth_models.dart lib/features/watch_party/watch_party_providers.dart test/core/jellyfin/auth_models_test.dart test/features/watch_party/watch_party_access_test.dart
git commit -m "feat: read the user's watch party permissions"
```

---

### Task 3: l'interfaccia segue i permessi

**Files:**
- Modify: `lib/features/detail/detail_header.dart`
- Modify: `lib/features/watch_party/watch_party_button.dart`
- Modify: `lib/features/watch_party/watch_party_directory.dart`
- Test: `test/features/detail/movie_detail_test.dart`, `test/features/watch_party/watch_party_button_test.dart`, `test/features/watch_party/watch_party_directory_test.dart`

Regole (spec B §5.9):
- "Guarda insieme" (dettagli; nel Task 7 anche il player) solo con `canCreate`;
- pulsante della barra in alto, elenco dei gruppi (nessuna richiesta a `/SyncPlay/List`) e inviti solo con `canJoin`.

- [ ] **Step 1: scrivi i test**

In `test/features/detail/movie_detail_test.dart`, in fondo a `main()` (se `JellyfinUser`/`SyncPlayAccess` non sono importati aggiungi `import 'package:wonderflix/core/jellyfin/auth_models.dart';`):

```dart
  testWidgets('solo entrare nei watch party: niente "Guarda insieme"',
      (tester) async {
    await pumpApp(
        tester, const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
        overrides: [
          libraryApiProvider.overrideWithValue(api),
          sessionControllerProvider.overrideWith(() => FakeSessionController(
              const SessionSignedIn(JellyfinUser(
                  id: 'u1',
                  name: 'Mario',
                  syncPlayAccess: SyncPlayAccess.joinOnly)))),
        ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Riprendi da 23:14'), findsOneWidget);
    expect(find.text('Guarda insieme'), findsNothing);
  });
```

In `test/features/watch_party/watch_party_button_test.dart` aggiungi l'import `import 'package:wonderflix/core/jellyfin/auth_models.dart';` e in fondo a `main()`:

```dart
  testWidgets('senza accesso ai watch party: nessun pulsante', (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: Align(
              alignment: Alignment.topRight, child: WatchPartyButton())),
      overrides: [
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory([testGroup()])),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(JellyfinUser(
                id: 'u1',
                name: 'Mario',
                syncPlayAccess: SyncPlayAccess.none)))),
      ],
    );
    expect(find.byKey(const Key('watch-party-button')), findsNothing);
  });
```

In `test/features/watch_party/watch_party_directory_test.dart` aggiungi l'import `import 'package:wonderflix/core/jellyfin/auth_models.dart';` e in fondo a `main()`:

```dart
  test('senza accesso ai watch party: nessuna richiesta', () {
    fakeAsync((async) {
      final container = ProviderContainer(overrides: [
        sessionControllerProvider.overrideWith(() => FakeSessionController(
            const SessionSignedIn(JellyfinUser(
                id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)))),
        syncPlayApiProvider.overrideWithValue(api),
      ]);
      container.listen(watchPartyDirectoryProvider, (_, _) {});
      async.elapse(const Duration(minutes: 2));
      expect(api.calls, isEmpty);
      expect(container.read(watchPartyDirectoryProvider), isEmpty);
      container.dispose();
    });
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/detail/movie_detail_test.dart test/features/watch_party/watch_party_button_test.dart test/features/watch_party/watch_party_directory_test.dart`
Expected: FAIL nei tre test nuovi.

- [ ] **Step 3: applica i permessi**

`lib/features/detail/detail_header.dart`: aggiungi l'import `import '../watch_party/watch_party_providers.dart';`, in `build` dopo `final action = primary;`:

```dart
    final canCreateParty = ref.watch(syncPlayAccessProvider).canCreate;
```

e nella condizione del pulsante "Guarda insieme" aggiungi `canCreateParty &&` all'inizio:

```dart
                    if (canCreateParty &&
                        action != null &&
                        const {ItemKind.movie, ItemKind.episode, ItemKind.series}
                            .contains(item.kind))
```

`lib/features/watch_party/watch_party_button.dart`: aggiungi l'import `import 'watch_party_providers.dart';` e all'inizio di `build`:

```dart
    if (!ref.watch(syncPlayAccessProvider).canJoin) {
      return const SizedBox.shrink();
    }
```

`lib/features/watch_party/watch_party_directory.dart`: in `build`, dopo `if (userId == null) return const [];`:

```dart
    // Senza accesso ai watch party l'elenco non serve.
    if (!ref.watch(syncPlayAccessProvider).canJoin) return const [];
```

- [ ] **Step 4: verifica che passino**

Run: `flutter test test/features/detail/ test/features/watch_party/`
Expected: PASS.

- [ ] **Step 5: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/detail/detail_header.dart lib/features/watch_party/watch_party_button.dart lib/features/watch_party/watch_party_directory.dart test/features/detail/movie_detail_test.dart test/features/watch_party/watch_party_button_test.dart test/features/watch_party/watch_party_directory_test.dart
git commit -m "feat: hide watch party actions the user cannot use"
```

---
### Task 4: inviti

**Files:**
- Create: `lib/features/watch_party/watch_party_invites.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Test: `test/features/watch_party/watch_party_invites_test.dart`, `test/features/watch_party/watch_party_invite_card_test.dart`

Regole (spec B §5.8):
- `WatchPartyInvites` ascolta l'elenco dei gruppi (`watchPartyDirectoryProvider`). La prima lettura dopo il login registra solo i gruppi esistenti; alle letture dopo, un gruppo mai visto diventa l'invito (il più recente, se più di uno);
- niente invito se si è già in un gruppo (o si sta entrando), con il player aperto o senza il permesso di entrare;
- l'invito resta 10 s; si chiude con la X, con "Unisciti" o aprendo il player;
- la scheda sta in `AppShell`, in alto a destra sotto la barra (il player, che è una pagina sopra la shell, la copre);
- dal nome del gruppo "Davide · Dune" (lo crea così WonderFlix) si ricavano chi l'ha avviato e il titolo; altrimenti il primo membro e il nome intero.

`WatchPartyInvites` non osserva la sessione nel `build` (la legge solo quando arriva un gruppo nuovo): così i test della shell, che non preparano la sessione, non la costruiscono.

- [ ] **Step 1: aggiorna i fake**

In `test/support/watch_party_fakes.dart`:
- nella classe `FakeWatchPartyDirectory` aggiungi:

```dart
  /// Simula una nuova lettura dell'elenco.
  void set(List<GroupInfo> groups) => state = groups;
```

- aggiungi l'import `import 'package:wonderflix/features/watch_party/watch_party_invites.dart';` e in fondo:

```dart
/// Invito fisso: registra le chiusure, senza timer.
class FakeWatchPartyInvites extends WatchPartyInvites {
  FakeWatchPartyInvites([this.initial]);

  final GroupInfo? initial;
  int dismissed = 0;

  @override
  GroupInfo? build() => initial;

  @override
  void dismiss() {
    dismissed++;
    state = null;
  }
}
```

(Il file `watch_party_invites.dart` nasce allo Step 4: fino ad allora il fake non compila. Scrivi i test degli Step 2–3, poi il codice, poi esegui.)

- [ ] **Step 2: scrivi i test degli inviti**

`test/features/watch_party/watch_party_invites_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/player/player_active.dart';
import 'package:wonderflix/features/watch_party/watch_party_directory.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late ProviderContainer container;
  final g1 = testGroup(id: 'g1', name: 'Luigi · Arrival');
  final g2 = testGroup(id: 'g2', name: 'Davide · Dune');
  final g3 = testGroup(id: 'g3', name: 'Peach · Up');

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', g1)));
      }
    };
  });

  tearDown(() => events.close());

  /// Dentro la zona finta: container e inviti attivi.
  void mount({JellyfinUser user = testUser}) {
    container = ProviderContainer(overrides: [
      sessionControllerProvider
          .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
      syncPlayApiProvider.overrideWithValue(api),
      watchPartyEventsProvider.overrideWithValue(events.stream),
      watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
    ]);
    container.listen(watchPartyInvitesProvider, (_, _) {});
  }

  void groups(FakeAsync async, List<GroupInfo> list) {
    (container.read(watchPartyDirectoryProvider.notifier)
            as FakeWatchPartyDirectory)
        .set(list);
    async.flushMicrotasks();
  }

  GroupInfo? invite() => container.read(watchPartyInvitesProvider);

  test('i gruppi della prima lettura non sono inviti; uno nuovo sì, per 10 s',
      () {
    fakeAsync((async) {
      mount();
      groups(async, [g1]);
      expect(invite(), isNull);
      groups(async, [g1, g2, g3]);
      expect(invite()?.id, 'g3', reason: 'il più recente');
      async.elapse(const Duration(seconds: 9));
      expect(invite()?.id, 'g3');
      async.elapse(const Duration(seconds: 1));
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('dentro un gruppo nessun invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
      async.flushMicrotasks();
      groups(async, [g1, g2]);
      expect(invite(), isNull);
      unawaited(container.read(watchPartySessionProvider.notifier).leave());
      async.flushMicrotasks();
      container.dispose();
    });
  });

  test('con il player aperto nessun invito; aprirlo chiude l\'invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      groups(async, [g2]);
      expect(invite()?.id, 'g2');
      container.read(playerActiveProvider.notifier).enter();
      async.flushMicrotasks();
      expect(invite(), isNull);
      groups(async, [g2, g3]);
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('senza il permesso di entrare nessun invito', () {
    fakeAsync((async) {
      mount(
          user: const JellyfinUser(
              id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none));
      groups(async, const []);
      groups(async, [g2]);
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('dismiss chiude l\'invito', () {
    fakeAsync((async) {
      mount();
      groups(async, const []);
      groups(async, [g2]);
      container.read(watchPartyInvitesProvider.notifier).dismiss();
      expect(invite(), isNull);
      async.elapse(const Duration(seconds: 20));
      expect(invite(), isNull);
      container.dispose();
    });
  });

  test('nomi dal nome del gruppo', () {
    expect(partyNameParts(g2), (host: 'Davide', title: 'Dune'));
    expect(
        partyNameParts(
            testGroup(name: 'Davide · Star Wars · Episodio IV')),
        (host: 'Davide', title: 'Star Wars · Episodio IV'));
    expect(
        partyNameParts(testGroup(name: 'Serata', participants: ['Luigi'])),
        (host: 'Luigi', title: 'Serata'));
    expect(partyNameParts(testGroup(name: 'Serata', participants: const [])),
        (host: 'Serata', title: 'Serata'));
  });
}
```

- [ ] **Step 3: scrivi i test della scheda**

`test/features/watch_party/watch_party_invite_card_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/watch_party/watch_party_invites.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';
import '../../support/watch_party_fakes.dart';

void main() {
  late FakeSyncPlayApi api;
  late StreamController<ServerEvent> events;
  late FakeWatchPartyInvites invites;
  final dune = testGroup(name: 'Davide · Dune', participants: ['Davide']);

  setUp(() {
    api = FakeSyncPlayApi();
    events = StreamController<ServerEvent>.broadcast();
    invites = FakeWatchPartyInvites(dune);
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', dune)));
      }
    };
  });

  tearDown(() => events.close());

  Future<void> pumpCard(WidgetTester tester) => pumpApp(
        tester,
        const Scaffold(
            body: Align(
                alignment: Alignment.topRight, child: WatchPartyInviteCard())),
        overrides: [
          watchPartyInvitesProvider.overrideWith(() => invites),
          syncPlayApiProvider.overrideWithValue(api),
          watchPartyEventsProvider.overrideWithValue(events.stream),
          sessionControllerProvider.overrideWith(
              () => FakeSessionController(const SessionSignedIn(testUser))),
        ],
      );

  testWidgets('chi l\'ha avviato e cosa si guarda; "Unisciti" entra',
      (tester) async {
    await pumpCard(tester);
    expect(find.text('Davide ha avviato un watch party'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    await tester.tap(find.text('Unisciti'));
    await tester.pumpAndSettle();
    expect(api.calls, ['join g1']);
    expect(invites.dismissed, 1);
    expect(find.byKey(const Key('watch-party-invite')), findsNothing);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });

  testWidgets('la X chiude l\'invito', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pump();
    expect(invites.dismissed, 1);
    expect(find.byKey(const Key('watch-party-invite')), findsNothing);
    expect(api.calls, isEmpty);
  });
}
```

- [ ] **Step 4: scrivi inviti e scheda**

`lib/features/watch_party/watch_party_invites.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/syncplay/syncplay_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import '../player/player_active.dart';
import 'watch_party_actions.dart';
import 'watch_party_directory.dart';
import 'watch_party_providers.dart';
import 'watch_party_session.dart';

/// Chi ha avviato il gruppo e cosa si guarda, dal nome "Davide · Dune" che
/// gli dà WonderFlix; altrimenti il primo membro e il nome intero.
({String host, String title}) partyNameParts(GroupInfo group) {
  final parts = group.name.split(' · ');
  if (parts.length >= 2) {
    return (host: parts.first, title: parts.sublist(1).join(' · '));
  }
  final host =
      group.participants.isEmpty ? group.name : group.participants.first;
  return (host: host, title: group.name);
}

/// Invito a un watch party appena nato (spec B §5.8): l'ultimo gruppo nuovo
/// comparso nell'elenco, per [showFor]. I gruppi della prima lettura dopo
/// il login non sono inviti. Niente inviti dentro un gruppo, con il player
/// aperto o senza il permesso di entrare.
class WatchPartyInvites extends Notifier<GroupInfo?> {
  static const showFor = Duration(seconds: 10);

  /// Gruppi dell'ultima lettura; `null` prima della prima.
  Set<String>? _known;
  Timer? _timer;

  @override
  GroupInfo? build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    _known = null;
    _timer = null;
    ref.listen(watchPartyDirectoryProvider, (_, groups) => _onGroups(groups));
    ref.listen(playerActiveProvider, (_, active) {
      if (active) dismiss();
    });
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = null;
  }

  void _onGroups(List<GroupInfo> groups) {
    final known = _known;
    _known = {for (final group in groups) group.id};
    if (known == null) return;
    final fresh = [
      for (final group in groups)
        if (!known.contains(group.id)) group,
    ];
    if (fresh.isEmpty) return;
    // La sessione si legge solo qui: nessun gruppo nuovo, nessuna sessione.
    if (!ref.read(syncPlayAccessProvider).canJoin ||
        ref.read(playerActiveProvider) ||
        ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
      return;
    }
    _timer?.cancel();
    state = fresh.last;
    _timer = Timer(showFor, dismiss);
  }
}

final watchPartyInvitesProvider =
    NotifierProvider<WatchPartyInvites, GroupInfo?>(WatchPartyInvites.new);

/// Scheda dell'invito, in alto a destra nella shell.
class WatchPartyInviteCard extends ConsumerWidget {
  const WatchPartyInviteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(watchPartyInvitesProvider);
    if (group == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final names = partyNameParts(group);
    final invites = ref.read(watchPartyInvitesProvider.notifier);
    return Material(
      key: const Key('watch-party-invite'),
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
                  const Icon(LucideIcons.users, size: 18, color: WfColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.watchPartyInviteTitle(names.host),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: l.watchPartyDismiss,
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: invites.dismiss,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 26, right: 8),
                child: Text(names.title,
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
                  onPressed: () {
                    invites.dismiss();
                    unawaited(joinWatchParty(context, ref, group.id));
                  },
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

- [ ] **Step 5: la scheda nella shell**

In `lib/app/app_shell.dart` (CRLF: Edit mirati) aggiungi l'import `import '../features/watch_party/watch_party_invites.dart';` e sostituisci il `child:` di `BackNavigationHandler`, cioè la `Column(...)`, con uno `Stack` che la contiene:

```dart
      body: BackNavigationHandler(
        child: Stack(
          children: [
            Column(
              children: [
                // … la barra e `Expanded(child: child)` di prima, invariate …
              ],
            ),
            // Invito a un watch party appena nato (spec B §5.8).
            const Positioned(top: 72, right: 24, child: WatchPartyInviteCard()),
          ],
        ),
      ),
```

(Il contenuto della `Column` non cambia: sposta solo l'indentazione. Se preferisci non reindentare, il file resta valido anche con l'indentazione vecchia: `dart format` non va eseguito.)

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/watch_party/ test/app/`
Expected: PASS (anche i test della shell: la scheda senza inviti non mostra nulla).

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_invites.dart lib/app/app_shell.dart test/support/watch_party_fakes.dart test/features/watch_party/watch_party_invites_test.dart test/features/watch_party/watch_party_invite_card_test.dart
git commit -m "feat: invite users to new watch parties"
```

---

### Task 5: "Nel watch party" nella barra in alto

**Files:**
- Modify: `lib/features/watch_party/watch_party_button.dart`
- Modify: `test/app/app_shell_test.dart`, `test/app/app_shell_back_button_test.dart`
- Test: `test/features/watch_party/watch_party_button_test.dart`

Regole (spec B §7.1): stando in un gruppo il pulsante della barra diventa "Nel watch party", con:
- "Torna al player": apre il player dell'elemento in riproduzione nel gruppo (disattivato se il gruppo non ha niente in coda, es. un gruppo aperto dall'elenco senza titolo);
- "Esci dal watch party".

Il pulsante ora osserva la sessione: i due test della shell devono sostituire `syncPlayApiProvider` e `watchPartyEventsProvider` (altrimenti la sessione chiede `clientInfoProvider`, non sostituito nei test).

- [ ] **Step 1: prepara i test della shell**

In `test/app/app_shell_test.dart` e `test/app/app_shell_back_button_test.dart` aggiungi gli import:

```dart
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';
```

(e `import '../support/watch_party_fakes.dart';` se manca), e negli `overrides`, accanto a quello di `watchPartyDirectoryProvider`:

```dart
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
```

- [ ] **Step 2: scrivi i test**

In `test/features/watch_party/watch_party_button_test.dart` aggiungi gli import:

```dart
import 'package:wonderflix/features/watch_party/watch_party_routing.dart';
```

e in fondo a `main()`:

```dart
  /// Nel gruppo `g1`; con [queue] il gruppo guarda qualcosa.
  Future<FakePartyNavigator> pumpInParty(WidgetTester tester,
      {PlayQueue? queue}) async {
    final navigator = FakePartyNavigator();
    await pumpApp(
      tester,
      const Scaffold(
          body: Align(
              alignment: Alignment.topRight, child: WatchPartyButton())),
      overrides: [
        watchPartyDirectoryProvider
            .overrideWith(() => FakeWatchPartyDirectory([testGroup()])),
        syncPlayApiProvider.overrideWithValue(api),
        watchPartyEventsProvider.overrideWithValue(events.stream),
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        partyNavigatorProvider.overrideWithValue(navigator),
      ],
    );
    api.onCall = (call) {
      if (call.startsWith('join')) {
        events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
      }
    };
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    unawaited(container.read(watchPartySessionProvider.notifier).join('g1'));
    await tester.pump();
    await tester.pump();
    if (queue != null) {
      events.add(SyncPlayGroupUpdated(PlayQueueUpdate('g1', queue)));
      await tester.pump();
      await tester.pump();
    }
    return navigator;
  }

  testWidgets('nel gruppo: "Nel watch party", torna al player ed esci',
      (tester) async {
    final navigator = await pumpInParty(tester, queue: testQueue());
    expect(find.text('Nel watch party'), findsOneWidget);
    expect(find.text('Watch party · 1'), findsNothing);

    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Torna al player'));
    await tester.pumpAndSettle();
    expect(navigator.opened, ['/play/m1?party=p1']);

    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esci dal watch party'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'leave');
    expect(find.text('Nel watch party'), findsNothing);
    expect(find.text('Watch party · 1'), findsOneWidget);
  });

  testWidgets('gruppo senza coda: "Torna al player" non fa nulla',
      (tester) async {
    final navigator = await pumpInParty(tester);
    await tester.tap(find.text('Nel watch party'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Torna al player'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(navigator.opened, isEmpty);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(WatchPartyButton)));
    await container.read(watchPartySessionProvider.notifier).leave();
    await tester.pump();
  });
```

Se `PlayQueue` non è importato nel file, l'import è `package:wonderflix/core/syncplay/syncplay_models.dart` (c'è già dal 5a). Se il menu resta aperto dopo il tocco sulla voce disattivata, chiudilo con `await tester.tapAt(Offset.zero); await tester.pumpAndSettle();` prima di uscire dal gruppo.

- [ ] **Step 3: verifica che falliscano**

Run: `flutter test test/features/watch_party/watch_party_button_test.dart`
Expected: FAIL (nel gruppo il pulsante mostra ancora l'elenco).

- [ ] **Step 4: il pulsante nel gruppo**

In `lib/features/watch_party/watch_party_button.dart` aggiungi gli import:

```dart
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import 'watch_party_routing.dart';
import 'watch_party_session.dart';
```

in `build`, dopo il controllo dei permessi:

```dart
    if (ref.watch(watchPartySessionProvider.select((s) => s.inGroup))) {
      return const _InPartyButton();
    }
```

e aggiorna il commento della classe: "Fuori da un gruppo: "Watch party · N" … Dentro un gruppo: "Nel watch party" con "Torna al player" ed "Esci dal watch party"." In fondo al file:

```dart
/// Stando in un gruppo (spec B §7.1): tornare al player o uscire.
class _InPartyButton extends ConsumerWidget {
  const _InPartyButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final party = ref.watch(watchPartySessionProvider);
    final playing = party.queue?.playing;
    return PopupMenuButton<String>(
      key: const Key('watch-party-in-party'),
      tooltip: party.group?.name,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        final session = ref.read(watchPartySessionProvider.notifier);
        switch (value) {
          case 'back':
            final entry = ref.read(watchPartySessionProvider).queue?.playing;
            if (entry == null) return;
            ref.read(partyNavigatorProvider).open(playerRoute(entry.itemId,
                start: session.estimatedPosition(),
                party: entry.playlistItemId));
          case 'leave':
            unawaited(session.leave());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'back',
          enabled: playing != null,
          child: Row(
            children: [
              const Icon(LucideIcons.play, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.watchPartyBackToPlayer),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              const Icon(LucideIcons.logOut, size: 18, color: WfColors.error),
              const SizedBox(width: 12),
              Text(l.watchPartyLeave),
            ],
          ),
        ),
      ],
      child: PartyChip(label: l.watchPartyInParty),
    );
  }
}
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/watch_party/ test/app/`
Expected: PASS.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_button.dart test/app/app_shell_test.dart test/app/app_shell_back_button_test.dart test/features/watch_party/watch_party_button_test.dart
git commit -m "feat: show the watch party state in the top bar"
```

---
### Task 6: schermo intero quando un player da solo entra nel gruppo

**Files:**
- Modify: `lib/features/player/player_window.dart`
- Modify: `lib/features/watch_party/watch_party_routing.dart`
- Modify: `test/support/playback_fakes.dart`
- Test: `test/features/watch_party/watch_party_routing_test.dart`

Quando il gruppo sceglie cosa guardare e in cima c'è un player **da solo** (`/play/…` senza `party`), il routing lo sostituisce con quello del gruppo. Nel Task 7 succederà con "Guarda insieme" dal player: lo schermo intero deve restare com'è, quindi il routing chiede alla finestra se è a schermo intero e lo passa nel percorso (`fs=1`).

- [ ] **Step 1: `isFullScreen` nella finestra e nel fake**

In `lib/features/player/player_window.dart`, nella classe astratta `PlayerWindow`, dopo `setFullScreen`:

```dart
  Future<bool> isFullScreen();
```

e in `WindowManagerPlayerWindow`, dopo `setFullScreen`:

```dart
  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();
```

In `test/support/playback_fakes.dart`, nella classe `FakePlayerWindow`:
- aggiungi `bool fullScreen = false;` dopo `final fullScreenCalls = <bool>[];`;
- sostituisci `setFullScreen` con:

```dart
  @override
  Future<void> setFullScreen(bool value) async {
    fullScreenCalls.add(value);
    fullScreen = value;
  }

  @override
  Future<bool> isFullScreen() async => fullScreen;
```

- [ ] **Step 2: scrivi i test del routing**

In `test/features/watch_party/watch_party_routing_test.dart`:
- aggiungi gli import `import 'package:wonderflix/features/player/player_providers.dart';` e `import '../../support/playback_fakes.dart';`;
- aggiungi `late FakePlayerWindow window;` accanto alle altre variabili, `window = FakePlayerWindow();` in `setUp` prima di creare il container e `playerWindowProvider.overrideWithValue(window),` negli `overrides`;
- in fondo a `main()`:

```dart
  test('player da solo che entra nel gruppo a schermo intero: resta così',
      () async {
    navigator.location = Uri.parse('/play/m1');
    window.fullScreen = true;
    await joinAndQueue(testQueue());
    expect(navigator.replaced, ['/play/m1?fs=1&party=p1']);
  });
```

Il test esistente "con un player già aperto lo sostituisce" resta com'è (finestra non a schermo intero: `/play/m1?party=p1`).

- [ ] **Step 3: verifica che fallisca**

Run: `flutter test test/features/watch_party/watch_party_routing_test.dart`
Expected: FAIL nel test nuovo (manca `fs=1`).

- [ ] **Step 4: aggiorna il routing**

In `lib/features/watch_party/watch_party_routing.dart`:
1. Import: `import 'package:logging/logging.dart';` e `import '../player/player_providers.dart';`, più `final _log = Logger('watchparty');` dopo gli import.
2. Sostituisci il corpo della callback di `ref.listen(watchPartySessionProvider.select(…), (_, playlistItemId) { … })` con:

```dart
      (_, playlistItemId) {
    if (playlistItemId != null) unawaited(_openParty(ref, playlistItemId));
  });
```

3. In fondo al file:

```dart
/// Apre il player dell'elemento [playlistItemId] del gruppo. Con un player
/// del gruppo già aperto non fa nulla (il cambio lo fa lui); con un player
/// da solo in cima ("Guarda insieme" dal player) lo sostituisce, lasciando
/// lo schermo intero com'è.
Future<void> _openParty(Ref ref, String playlistItemId) async {
  final navigator = ref.read(partyNavigatorProvider);
  final location = navigator.location;
  if (location.queryParameters.containsKey('party')) return;
  final entry = ref.read(watchPartySessionProvider).queue?.playing;
  if (entry == null || entry.playlistItemId != playlistItemId) return;
  String route(bool fullscreen) => playerRoute(entry.itemId,
      start: ref.read(watchPartySessionProvider.notifier).estimatedPosition(),
      fullscreen: fullscreen,
      party: playlistItemId);
  if (!location.path.startsWith('/play/')) {
    navigator.open(route(false));
    return;
  }
  var fullscreen = false;
  try {
    fullscreen = await ref.read(playerWindowProvider).isFullScreen();
  } on Object catch (error) {
    _log.info('stato dello schermo intero non disponibile: $error');
  }
  // Nel frattempo il gruppo può essere passato ad altro.
  if (!ref.mounted) return;
  final party = ref.read(watchPartySessionProvider);
  if (!party.inGroup || party.queue?.playing?.playlistItemId != playlistItemId) {
    return;
  }
  navigator.replace(route(fullscreen));
}
```

(Il resto del provider, compreso `ref.listen(partyNoticesProvider, …)`, non cambia. `playerRoute` è già importato.)

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/player/player_window.dart lib/features/watch_party/watch_party_routing.dart test/support/playback_fakes.dart test/features/watch_party/watch_party_routing_test.dart
git commit -m "feat: keep fullscreen when a solo player joins a watch party"
```

---

### Task 7: "Guarda insieme" dal player

**Files:**
- Modify: `lib/features/watch_party/watch_party_actions.dart`
- Modify: `lib/features/player/player_overlay.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/party_handover_test.dart`

Regole (spec B §5.2 aggiornato):
- nei controlli del player da solo c'è "Guarda insieme" (icona `users`), solo con il permesso di creare;
- crea il gruppo con la coda dell'elemento aperto (per un episodio anche i successivi), dal minuto attuale;
- quando arriva la coda, il routing sostituisce questo player con quello del gruppo sullo stesso punto (Task 6), mantenendo lo schermo intero;
- intanto questo player, che sta per essere sostituito, non deve uscire dallo schermo intero né nascondere il pannello media (`_handingOver`); se la creazione non riesce torna normale.

`startWatchParty` e `joinWatchParty` restituiscono ora `Future<bool>` (riuscito o no).

- [ ] **Step 1: scrivi il test**

In `test/features/watch_party/party_handover_test.dart`:
1. Porta fuori dal helper `pumpApp` la libreria e la finestra: `late FakeLibraryApi library;` e `late FakePlayerWindow window;` accanto alle altre variabili; nel helper assegna `library = FakeLibraryApi()…` e `window = FakePlayerWindow();`, e usa `playerWindowProvider.overrideWithValue(window),`.
2. Aggiungi al helper il parametro `{bool join = true}` e fai l'ingresso nel gruppo (le righe da `api.onCall = …` fino ai due `await tester.pump();`) solo `if (join)`.
3. In fondo a `main()`:

```dart
  testWidgets(
      '"Guarda insieme" dal player: stesso punto nel gruppo, schermo intero '
      'com\'è, un solo player', (tester) async {
    await pumpApp(tester, join: false);
    library.seriesEpisodes['s1'] = [
      episode('e4', 4),
      episode('e5', 5),
      episode('e6', 6),
    ];
    unawaited(router.push('/play/e4'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Schermo intero'));
    await tester.pump();
    expect(window.fullScreenCalls, [true]);

    api.onCall = (call) {
      if (call.startsWith('create')) {
        emit(GroupJoined('g1', testGroup(participants: ['Mario'])));
      }
      if (call.startsWith('queue')) {
        emit(PlayQueueUpdate('g1', testSeriesQueue()));
      }
    };
    await tester.tap(find.byTooltip('Guarda insieme'));
    await tester.pumpAndSettle();

    expect(api.calls.take(2), ['create Mario · Breaking Bad', 'queue e4,e5,e6']);
    expect(router.state.uri.toString(), '/play/e4?fs=1&party=p1');
    expect(find.byType(PlayerScreen, skipOffstage: false), findsOneWidget);
    expect(window.fullScreenCalls, [true],
        reason: 'il player sostituito non esce dallo schermo intero');
    await finish(tester);
  });
```

Se il tooltip del pulsante dello schermo intero non è "Schermo intero", usa quello di `l.playerFullscreen` (come negli altri test del player: `lookupAppLocalizations(const Locale('it')).playerFullscreen`).

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/watch_party/party_handover_test.dart`
Expected: FAIL (nessun pulsante "Guarda insieme" nel player).

- [ ] **Step 3: esito delle azioni**

In `lib/features/watch_party/watch_party_actions.dart`:
- `startWatchParty` e `joinWatchParty` restituiscono `Future<bool>` (il tipo di ritorno cambia, il corpo no);
- `_run` diventa:

```dart
/// `true` se [action] è riuscita; altrimenti mostra l'errore e `false`.
Future<bool> _run(BuildContext context, Future<void> Function() action,
    {required bool creating}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(
        content: Text(watchPartyErrorText(l, error, creating: creating))));
    return false;
  }
}
```

- [ ] **Step 4: il pulsante nei controlli**

In `lib/features/player/player_overlay.dart`:
- costruttore: dopo `this.partyBadge,` aggiungi `this.onWatchTogether,`;
- campi: dopo `final Widget? partyBadge;`:

```dart

  /// "Guarda insieme" (solo da soli e con il permesso); `null` = nessun
  /// pulsante.
  final VoidCallback? onWatchTogether;
```

- nella `Row` dei comandi, prima del pulsante con `LucideIcons.captions`:

```dart
                        if (onWatchTogether != null)
                          IconButton(
                            icon: const Icon(LucideIcons.users),
                            tooltip: l.watchPartyWatchTogether,
                            onPressed: onWatchTogether,
                          ),
```

- [ ] **Step 5: "Guarda insieme" nel player**

In `lib/features/player/player_screen.dart` (CRLF: Edit mirati):
1. Import: `import '../watch_party/watch_party_actions.dart';` e `import '../watch_party/watch_party_providers.dart';`
2. Dopo `_handOverTo`:

```dart
  /// "Guarda insieme" mentre si guarda da soli (spec B §5.2): il gruppo parte
  /// da qui, e il routing riapre il player sullo stesso punto in modalità
  /// gruppo. Intanto questo player, che sta per essere sostituito, non esce
  /// dallo schermo intero né nasconde il pannello media.
  Future<void> _watchTogether() async {
    final item = ref.read(playerControllerProvider(widget.args)).item;
    if (item == null || _leaving) return;
    _handingOver = true;
    final started = await startWatchParty(context, ref, item,
        start: _controller.engine.position);
    if (!started && mounted) _handingOver = false;
  }
```

3. In `build`, dopo `final party = …`:

```dart
    final canWatchTogether = widget.args.party == null &&
        ref.watch(syncPlayAccessProvider).canCreate &&
        view.item != null;
```

4. Nel `PlayerOverlay`, dopo `partyBadge: …,`:

```dart
                          onWatchTogether: canWatchTogether
                              ? () => unawaited(_watchTogether())
                              : null,
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/watch_party/ test/features/player/ test/features/detail/`
Expected: PASS.

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_actions.dart lib/features/player/player_overlay.dart lib/features/player/player_screen.dart test/features/watch_party/party_handover_test.dart
git commit -m "feat: start a watch party from the player"
```

---
### Task 8: rientro automatico dopo una caduta del WebSocket

**Files:**
- Modify: `lib/features/watch_party/watch_party_session.dart`
- Modify: `lib/features/watch_party/group_playback_driver.dart`
- Modify: `lib/features/watch_party/party_notices.dart`, `lib/features/watch_party/party_notice_pill.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/watch_party/watch_party_session_test.dart`, `test/features/watch_party/group_playback_driver_test.dart`, `test/features/watch_party/party_notices_test.dart`, `test/features/watch_party/party_notice_pill_test.dart`, `test/features/watch_party/party_player_test.dart`

Regole (spec B §5.5 aggiornato):
- a ogni `ServerConnected(isReconnect: true)`, se siamo in un gruppo, si manda `Join` sullo stesso gruppo (senza limiti);
- all'arrivo di `GroupJoined` di quel gruppo si aggiornano gruppo e stato, si sposta l'istante di ingresso (i comandi più vecchi si scartano) e si incrementa `rejoins` nello stato: il player lo vede e il driver rimanda `Ready` (il server aspetta il nostro `Ready`);
- se il gruppo non c'è più (`GroupDoesNotExist` durante il rientro) si esce: lo stato torna "nessun gruppo" e l'aggiornamento va agli avvisi, che mostrano "Il watch party è terminato"; il player continua da solo;
- lo stesso avviso quando il server ci toglie (`GroupLeft` o `NotInGroup` mentre siamo nel gruppo);
- la pillola degli avvisi resta nel player del gruppo anche dopo l'uscita, così l'avviso si vede.

- [ ] **Step 1: scrivi i test della sessione**

In `test/features/watch_party/watch_party_session_test.dart`, in fondo a `main()`:

```dart
  test('riconnessione: si rientra nello stesso gruppo', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    expect(state().rejoins, 0);

    serverAccepts(participants: ['Mario', 'Luigi']);
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, ['join g1', 'join g1']);
    expect(state().inGroup, isTrue);
    expect(state().rejoins, 1);
    expect(state().members, ['Mario', 'Luigi']);
  });

  test('prima connessione, o fuori da un gruppo: nessun rientro', () async {
    mount();
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(api.calls, isEmpty);

    serverAccepts();
    await session().join('g1');
    events.add(const ServerConnected(false));
    await pumpEventQueue();
    expect(api.calls, ['join g1']);
  });

  test('gruppo sparito durante il rientro: fuori, e l\'avviso lo sa',
      () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    api.onCall = (call) {
      if (call.startsWith('join')) emit(const GroupDoesNotExist(''));
    };
    events.add(const ServerConnected(true));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
    expect(updates.whereType<GroupDoesNotExist>(), hasLength(1));
  });

  test('il server ci toglie: l\'aggiornamento arriva agli avvisi', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(state().phase, WatchPartyPhase.none);
    expect(updates.whereType<GroupLeft>(), hasLength(1));
  });

  test('uscita nostra: nessun aggiornamento agli avvisi', () async {
    mount();
    serverAccepts();
    await session().join('g1');
    final updates = <GroupUpdate>[];
    final subscription = session().updates.listen(updates.add);
    addTearDown(subscription.cancel);

    await session().leave();
    emit(const GroupLeft('g1'));
    await pumpEventQueue();
    expect(updates, isEmpty);
  });
```

`ServerConnected` viene da `package:wonderflix/core/jellyfin/server_events.dart` (già importato).

- [ ] **Step 2: scrivi i test di driver, avvisi e pillola**

In `test/features/watch_party/group_playback_driver_test.dart`, in fondo a `main()`:

```dart
  test('dopo il rientro nel gruppo si rimanda Ready', () {
    fakeAsync((async) {
      setUpDriver(async);
      unawaited(driver.onRejoined());
      async.flushMicrotasks();
      expect(api.calls, ['ready']);
      expect(api.readyStates.last.position, const Duration(minutes: 10));
      tearDownDriver(async);
    });
  });

  test('rientro prima che il file sia aperto: niente', () {
    fakeAsync((async) {
      setUpDriver(async, load: false);
      unawaited(driver.onRejoined());
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });
```

In `test/features/watch_party/party_notices_test.dart`, in fondo a `main()`:

```dart
  test('gruppo sparito o server che ci toglie: "terminato"', () {
    fakeAsync((async) {
      mount(async);
      emit(async, const GroupLeft('g1'));
      expect(current()?.kind, PartyNoticeKind.ended);
      finish(async);
    });
  });
```

In `test/features/watch_party/party_notice_pill_test.dart`, nel test "testi di tutti gli avvisi":

```dart
    expect(text(const PartyNotice(PartyNoticeKind.ended)),
        'Il watch party è terminato');
```

- [ ] **Step 3: scrivi i test del player**

In `test/features/watch_party/party_player_test.dart`, in fondo a `main()`:

```dart
  testWidgets('riconnessione: rientro nel gruppo e Ready di nuovo',
      (tester) async {
    await pumpPartyPlayer(tester);
    final before = api.readyStates.length;
    events.add(const ServerConnected(true));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((c) => c == 'join g1'), hasLength(2));
    expect(api.readyStates.length, before + 1);
    await finish(tester);
  });

  testWidgets('gruppo sparito al rientro: avviso e si continua da soli',
      (tester) async {
    await pumpPartyPlayer(tester);
    api.onCall = (call) {
      if (call.startsWith('join')) emit(const GroupDoesNotExist(''));
    };
    events.add(const ServerConnected(true));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text(l.watchPartyNoticeEnded), findsOneWidget);
    expect(find.text(l.watchPartyButton(2)), findsNothing);
    await tester.tap(find.byTooltip(l.actionPlay));
    await tester.pump();
    expect(engine.calls, contains('play'));
    await finish(tester);
  });
```

- [ ] **Step 4: verifica che falliscano**

Run: `flutter test test/features/watch_party/`
Expected: FAIL nei test nuovi (`rejoins`, `onRejoined`, `PartyNoticeKind.ended` non definiti).

- [ ] **Step 5: la sessione**

In `lib/features/watch_party/watch_party_session.dart`:

1. In `WatchPartyState`: aggiungi il campo (con il costruttore `this.rejoins = 0,`):

```dart
  /// Rientri nel gruppo dopo una caduta del WebSocket: a ogni rientro il
  /// player rimanda `Ready`.
  final int rejoins;
```

e in `copyWith` il parametro `int? rejoins` con `rejoins: rejoins ?? this.rejoins,` (anche nel costruttore chiamato da `copyWith`).

2. Nella sessione, dopo `DateTime? _ghostLeftAt;`:

```dart

  /// Gruppo in cui stiamo rientrando dopo una riconnessione.
  String? _rejoining;
```

e azzeralo (`_rejoining = null;`) in `build()` e in `_reset()`.

3. In `_onEvent`, prima di `default:`:

```dart
      case ServerConnected(isReconnect: true):
        _rejoin();
```

4. Dopo `_leaveGhostGroup`:

```dart
  /// Dopo una caduta del WebSocket il server può averci tolto dal gruppo o
  /// averci perso dei comandi: si rientra nello stesso gruppo (spec B §5.5).
  /// Il server rimanda gruppo, coda e stato; il player rimanda `Ready`.
  void _rejoin() {
    final group = state.group;
    if (!state.inGroup || group == null) return;
    _rejoining = group.id;
    _log.info('WebSocket riconnesso: rientro nel watch party');
    unawaited(_api.join(group.id).catchError((Object error) =>
        _log.warning('rientro nel watch party non riuscito: $error')));
  }
```

5. All'inizio del caso `GroupJoined(:final info)` di `_onGroupUpdate`:

```dart
        if (_rejoining != null && state.inGroup && _isCurrent(info.id)) {
          _rejoining = null;
          // I comandi di prima della caduta non valgono più.
          _joinedAt = info.lastUpdatedAt;
          state = state.copyWith(
              group: info, groupState: info.state, rejoins: state.rejoins + 1);
          _log.info('rientrati nel watch party '
              '(${info.participants.length} membri)');
          return;
        }
```

6. Sostituisci i casi `GroupLeft() || NotInGroup()` e `GroupDoesNotExist()` con:

```dart
      case GroupLeft() || NotInGroup():
        if (state.inGroup) {
          _log.info('il server ci ha tolto dal watch party');
          _reset();
          // Gli avvisi mostrano "terminato" (dopo essersi svuotati).
          _updates.add(update);
        }
      case GroupDoesNotExist():
        if (_rejoining != null) {
          _log.info('il watch party non esiste più');
          _reset();
          _updates.add(update);
          return;
        }
        _failJoin(WatchPartyFailure.groupGone);
```

- [ ] **Step 6: driver, avvisi e pillola**

In `lib/features/watch_party/group_playback_driver.dart`, dopo `onUnloaded`:

```dart
  /// Rientrati nel gruppo dopo una caduta del WebSocket: il server aspetta
  /// il nostro `Ready`.
  Future<void> onRejoined() async {
    if (_disposed || !_loaded) return;
    await _sendReady();
  }
```

In `lib/features/watch_party/party_notices.dart`:
- aggiungi `ended` in fondo all'enum `PartyNoticeKind`;
- in `_onUpdate`, prima di `default:`:

```dart
      case GroupDoesNotExist() || GroupLeft() || NotInGroup():
        show(const PartyNotice(PartyNoticeKind.ended));
```

(se l'analyzer segnala il `default` come non raggiungibile, sostituiscilo con i casi rimasti: `GroupJoined() || LibraryAccessDenied() => break`).

In `lib/features/watch_party/party_notice_pill.dart`, in `partyNoticeText`:

```dart
    PartyNoticeKind.ended => l.watchPartyNoticeEnded,
```

- [ ] **Step 7: il player**

In `lib/features/player/player_screen.dart` (CRLF: Edit mirati):
1. Nel blocco `if (_inParty) { … }` di `build` aggiungi:

```dart
      ref.listen(watchPartySessionProvider.select((s) => s.rejoins),
          (_, _) => unawaited(_driver?.onRejoined()));
```

2. La pillola degli avvisi: la condizione `if (party != null && party.inGroup)` diventa `if (widget.args.party != null)`, con il commento "Anche dopo l'uscita dal gruppo: l'avviso "terminato" deve vedersi.".

- [ ] **Step 8: verifica che passino**

Run: `flutter test test/features/watch_party/ test/features/player/`
Expected: PASS (anche i test esistenti: quello "gruppo chiuso dal server" ora mostra anche l'avviso, senza cambiare le sue verifiche).

- [ ] **Step 9: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_session.dart lib/features/watch_party/group_playback_driver.dart lib/features/watch_party/party_notices.dart lib/features/watch_party/party_notice_pill.dart lib/features/player/player_screen.dart test/features/watch_party/watch_party_session_test.dart test/features/watch_party/group_playback_driver_test.dart test/features/watch_party/party_notices_test.dart test/features/watch_party/party_notice_pill_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: rejoin the watch party after a connection drop"
```

---

### Task 9: il video non si apre nel gruppo

**Files:**
- Modify: `lib/core/syncplay/syncplay_api.dart`
- Modify: `test/support/watch_party_fakes.dart`
- Modify: `lib/features/watch_party/group_playback_driver.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/core/syncplay/syncplay_api_test.dart`, `test/features/watch_party/group_playback_driver_test.dart`, `test/features/watch_party/party_player_test.dart`

Regole (spec B §6.3):
- se il player va in errore (anche dopo il ripiego sulla transcodifica), il driver manda `SetIgnoreWait(true)`, una volta sola: il gruppo non resta ad aspettarci;
- la schermata d'errore ha "Riprova" e, nel gruppo, "Esci dal watch party" (invece di "Indietro");
- quando il file si apre di nuovo, prima del `Ready` si manda `SetIgnoreWait(false)`.

- [ ] **Step 1: scrivi i test**

In `test/core/syncplay/syncplay_api_test.dart`, in fondo a `main()`:

```dart
  test('setIgnoreWait', () async {
    await api.setIgnoreWait(true);
    expect(adapter.requests.single.path, '/SyncPlay/SetIgnoreWait');
    expect(body(), {'IgnoreWait': true});
  });
```

In `test/features/watch_party/group_playback_driver_test.dart`, in fondo a `main()`:

```dart
  test('video non aperto: il gruppo non ci aspetta, finché non si riapre', () {
    fakeAsync((async) {
      setUpDriver(async);
      driver.onUnloaded(failed: true);
      driver.onUnloaded(failed: true);
      async.flushMicrotasks();
      expect(api.calls, ['ignore-wait true']);

      unawaited(driver.onLoaded());
      async.flushMicrotasks();
      expect(api.calls, ['ignore-wait true', 'ignore-wait false', 'ready']);
      tearDownDriver(async);
    });
  });

  test('file non più pronto senza errore: il gruppo aspetta come prima', () {
    fakeAsync((async) {
      setUpDriver(async);
      driver.onUnloaded();
      async.flushMicrotasks();
      expect(api.calls, isEmpty);
      tearDownDriver(async);
    });
  });
```

In `test/features/watch_party/party_player_test.dart`:
- aggiungi a `pumpPartyPlayer` il parametro `{int failOpens = 0}` e, subito dopo aver creato `engine`, `engine.failOpens = failOpens;`;
- in fondo a `main()`:

```dart
  testWidgets(
      'video che non si apre: il gruppo non aspetta, "Esci dal watch party"; '
      'Riprova riuscito torna nel gruppo', (tester) async {
    // Direct play e ripiego sulla transcodifica non riescono.
    await pumpPartyPlayer(tester, failOpens: 2);
    expect(find.text(l.playerErrorTitle), findsOneWidget);
    expect(api.calls, contains('ignore-wait true'));
    expect(find.text(l.watchPartyLeave), findsOneWidget);
    expect(find.text(l.playerBack), findsNothing);

    await tester.tap(find.text(l.retry));
    await tester.pumpAndSettle();
    final ignoreFalse = api.calls.indexOf('ignore-wait false');
    expect(ignoreFalse, greaterThanOrEqualTo(0));
    expect(api.calls.lastIndexOf('ready'), greaterThan(ignoreFalse));
    await finish(tester);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/core/syncplay/syncplay_api_test.dart test/features/watch_party/`
Expected: FAIL (`setIgnoreWait` e `onUnloaded(failed:)` non definiti).

- [ ] **Step 3: API e fake**

In `lib/core/syncplay/syncplay_api.dart`, dopo `ping`:

```dart
  /// Con `true` il gruppo non aspetta più i nostri `Ready` e `Buffering`
  /// (es. il video non si apre); con `false` torna ad aspettarli.
  Future<void> setIgnoreWait(bool ignore) =>
      _post('/SyncPlay/SetIgnoreWait', {'IgnoreWait': ignore});
```

In `test/support/watch_party_fakes.dart`, nella classe `FakeSyncPlayApi`, dopo `ping`:

```dart
  @override
  Future<void> setIgnoreWait(bool ignore) => _record('ignore-wait $ignore');
```

- [ ] **Step 4: il driver**

In `lib/features/watch_party/group_playback_driver.dart`:
1. Dopo `bool _disposed = false;`:

```dart

  /// Abbiamo chiesto al gruppo di non aspettarci (video non aperto).
  bool _ignoringWait = false;
```

2. Sostituisci `onUnloaded`:

```dart
  /// Il file non è più pronto (errore, "Riprova", ripiego sulla
  /// transcodifica): fino al prossimo [onLoaded] i comandi aspettano. Con
  /// [failed] (il video non si apre) il gruppo smette di aspettarci
  /// (spec B §6.3).
  void onUnloaded({bool failed = false}) {
    _loaded = false;
    if (!failed || _ignoringWait || _disposed) return;
    _ignoringWait = true;
    _log.info('video non aperto: il gruppo non ci aspetta');
    unawaited(_send('esclusione dall\'attesa', () => _api.setIgnoreWait(true)));
  }
```

3. In `onLoaded`, dopo l'attesa dell'orologio e prima di `await _sendReady();`:

```dart
    if (_ignoringWait) {
      _ignoringWait = false;
      await _send('ritorno nell\'attesa', () => _api.setIgnoreWait(false));
      if (_disposed) return;
    }
```

- [ ] **Step 5: il player**

In `lib/features/player/player_screen.dart` (CRLF: Edit mirati):
1. Nella callback del `ref.listen` sullo `status`, sostituisci:

```dart
        if (previous == PlayerStatus.ready) _driver?.onUnloaded();
```

con:

```dart
        if (previous == PlayerStatus.ready || status == PlayerStatus.error) {
          _driver?.onUnloaded(failed: status == PlayerStatus.error);
        }
```

2. `_PlayerError` riceve l'etichetta del pulsante per uscire: aggiungi al costruttore `required this.backLabel,`, il campo `final String backLabel;` e nel `WfButton.secondary` usa `label: backLabel,`. Dove si costruisce `_PlayerError` aggiungi:

```dart
                    // Nel gruppo uscire dal player è uscire dal gruppo.
                    backLabel: _inParty ? l.watchPartyLeave : l.playerBack,
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/core/syncplay/ test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/syncplay/syncplay_api.dart test/support/watch_party_fakes.dart lib/features/watch_party/group_playback_driver.dart lib/features/player/player_screen.dart test/core/syncplay/syncplay_api_test.dart test/features/watch_party/group_playback_driver_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: let the group go on when the video does not open"
```

---

### Task 10: tolti dal gruppo, il player torna del tutto da solo

**Files:**
- Modify: `lib/features/player/player_controller.dart`
- Modify: `lib/features/player/player_screen.dart`
- Test: `test/features/player/player_controller_test.dart`

Oggi, dopo che il server ci toglie dal gruppo, `PlayerController.inParty` resta vero (dipende da `args.party`): il salto automatico dell'intro resta spento e dopo "Riprova" il video non parte da solo. `leaveParty()` lo spegne.

- [ ] **Step 1: scrivi i test**

In `test/features/player/player_controller_test.dart`, dentro `group('watch party', …)`:

```dart
    test('leaveParty: di nuovo da solo (salto dell\'intro, partenza)',
        () async {
      settings = const PlayerSettings(autoSkipIntro: true);
      playback.segments = const [
        MediaSegment(
            type: MediaSegmentType.intro,
            start: Duration(seconds: 10),
            end: Duration(seconds: 90)),
      ];
      final controller = await startParty();
      controller.leaveParty();
      expect(controller.inParty, isFalse);
      engine.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      expect(engine.seeks, [const Duration(seconds: 90)]);

      engine.calls.clear();
      await controller.retry();
      await pumpEventQueue();
      expect(engine.calls, contains('play'));
    });
```

- [ ] **Step 2: verifica che fallisca**

Run: `flutter test test/features/player/player_controller_test.dart`
Expected: FAIL (`leaveParty` non definito).

- [ ] **Step 3: il controller**

In `lib/features/player/player_controller.dart` sostituisci il getter `inParty` con:

```dart
  /// Il server ci ha tolto dal gruppo: da qui il player è da solo.
  bool _leftParty = false;

  /// Il player fa parte di un watch party: parte e si ferma con il gruppo.
  bool get inParty => args.party != null && !_leftParty;

  /// Il server ci ha tolto dal gruppo: salto automatico dell'intro e
  /// partenza dopo un'apertura tornano come da soli.
  void leaveParty() => _leftParty = true;
```

- [ ] **Step 4: il player lo chiama**

In `lib/features/player/player_screen.dart`, nella callback del `ref.listen` su `inGroup` (dove si imposta `_partyDetached`), dopo `_detachParty();`:

```dart
        _controller.leaveParty();
```

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/player/ test/features/watch_party/`
Expected: PASS.

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/player/player_controller.dart lib/features/player/player_screen.dart test/features/player/player_controller_test.dart
git commit -m "fix: a player removed from the group behaves like a solo player"
```

---
### Task 11: Discord "Watch party · N persone"

**Files:**
- Modify: `lib/core/media_session/media_session.dart` (interfaccia e `NoopMediaSession`)
- Modify: `lib/core/media_session/mirrored_media_session.dart`
- Modify: `lib/core/media_session/smtc_media_session.dart`
- Modify: `lib/features/discord/discord_activity.dart`
- Modify: `lib/features/discord/discord_presence.dart`
- Modify: `lib/features/discord/discord_providers.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `test/support/playback_fakes.dart`
- Test: `test/features/discord/discord_activity_test.dart`, `test/core/media_session/mirrored_media_session_test.dart`, `test/features/watch_party/party_player_test.dart`

Regole (spec B §5.10): nel gruppo, mentre il video va, la riga di stato dell'attività Discord diventa "Watch party · N persone" (N = membri senza ripetizioni). In pausa resta "In pausa". Il resto dell'attività non cambia. Il player comunica il numero con `MediaSession.setParty(int?)` (`null` = fuori da un gruppo); il pannello di Windows lo ignora.

- [ ] **Step 1: scrivi i test**

In `test/features/discord/discord_activity_test.dart`, in fondo a `main()` (le etichette di prova sono in `labels`; qui ne serve una con il testo del gruppo):

```dart
  test('nel watch party: stato "Watch party · N persone" durante la visione',
      () {
    final partyLabels = DiscordLabels(
      paused: 'In pausa',
      button: "Chiedi l'accesso",
      party: (count) => 'Watch party · $count persone',
    );
    Map<String, Object?> activity({required bool playing, bool showTitle = true}) =>
        buildDiscordActivity(
          title: 'Breaking Bad',
          subtitle: 'S1:E4 · Pilot',
          playing: playing,
          settings: DiscordSettings(showTitle: showTitle),
          labels: partyLabels,
          partySize: 3,
        );
    expect(activity(playing: true)['state'], 'Watch party · 3 persone');
    expect(activity(playing: true, showTitle: false)['state'],
        'Watch party · 3 persone');
    expect(activity(playing: false)['state'], 'In pausa');
    expect(
        buildDiscordActivity(
          title: 'Breaking Bad',
          subtitle: 'S1:E4 · Pilot',
          playing: true,
          settings: const DiscordSettings(),
          labels: partyLabels,
        )['state'],
        'S1:E4 · Pilot',
        reason: 'fuori da un gruppo non cambia nulla');
  });
```

In `test/core/media_session/mirrored_media_session_test.dart`, nel test che chiama tutti i metodi, dopo `await session.setNextEnabled(true);` aggiungi `await session.setParty(2);` e, nel ciclo di verifiche su `[primary, mirror]`, `expect(s.parties, [2]);`.

In `test/features/watch_party/party_player_test.dart`:
- porta fuori dal helper la sessione media: `late FakeMediaSession mediaSession;`, nel helper `mediaSession = FakeMediaSession();` e `mediaSessionProvider.overrideWithValue(mediaSession),`;
- in fondo a `main()`:

```dart
  testWidgets('Discord: persone nel gruppo, niente fuori dal gruppo',
      (tester) async {
    await pumpPartyPlayer(tester);
    expect(mediaSession.parties.last, 2);
    emit(const GroupLeft('g1'));
    await tester.pump();
    await tester.pump();
    expect(mediaSession.parties.last, isNull);
    await finish(tester);
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/discord/ test/core/media_session/ test/features/watch_party/party_player_test.dart`
Expected: FAIL (`party`, `partySize`, `setParty`, `parties` non definiti).

- [ ] **Step 3: l'interfaccia e le sessioni**

In `lib/core/media_session/media_session.dart`, nell'interfaccia `MediaSession`, dopo `setNextEnabled`:

```dart
  /// Persone nel watch party (`null` = fuori da un gruppo). Solo Discord lo
  /// mostra.
  Future<void> setParty(int? members);
```

e in `NoopMediaSession`:

```dart
  @override
  Future<void> setParty(int? members) async {}
```

In `lib/core/media_session/mirrored_media_session.dart`, dopo `setNextEnabled`:

```dart
  @override
  Future<void> setParty(int? members) => _all((s) => s.setParty(members));
```

In `lib/core/media_session/smtc_media_session.dart`, dopo `setNextEnabled`:

```dart
  /// Il pannello di Windows non mostra il watch party.
  @override
  Future<void> setParty(int? members) async {}
```

In `test/support/playback_fakes.dart`, nella classe `FakeMediaSession`, dopo `final nextEnabled = <bool>[];`:

```dart
  final parties = <int?>[];
```

e dopo il metodo `setNextEnabled`:

```dart
  @override
  Future<void> setParty(int? members) async => parties.add(members);
```

- [ ] **Step 4: l'attività Discord**

In `lib/features/discord/discord_activity.dart`:
1. `DiscordLabels` riceve l'etichetta del gruppo:

```dart
class DiscordLabels {
  const DiscordLabels({required this.paused, required this.button, this.party});

  final String paused;

  /// Etichetta del pulsante verso `buttonUrl` (max 32 caratteri).
  final String button;

  /// "Watch party · N persone"; `null` = nessuna etichetta del gruppo.
  final String Function(int count)? party;
}
```

2. `buildDiscordActivity` riceve `int? partySize` (dopo `Uri? buttonUrl,`) e la riga `final state = …` diventa:

```dart
  final party = labels.party;
  // Nel watch party lo stato dice quante persone guardano (non svela il
  // titolo); in pausa resta "In pausa".
  final state = !playing
      ? labels.paused
      : partySize != null && party != null
          ? party(partySize)
          : (showTitle ? subtitle : null);
```

In `lib/features/discord/discord_presence.dart`:
- dopo `Duration? _position;`:

```dart

  /// Persone nel watch party; `null` = fuori da un gruppo.
  int? _partySize;
```

- dopo `setNextEnabled`:

```dart
  @override
  Future<void> setParty(int? members) async {
    _partySize = members;
    _sync();
  }
```

- in `clear()`, dopo `_position = null;`: `_partySize = null;`
- nella chiamata a `buildDiscordActivity` in `_desired()` aggiungi `partySize: _partySize,`.

In `lib/features/discord/discord_providers.dart`, in `discordLabelsProvider`:

```dart
  return DiscordLabels(
    paused: l.discordPaused,
    button: l.discordAccessButton,
    party: l.discordWatchParty,
  );
```

- [ ] **Step 5: il player lo comunica**

In `lib/features/player/player_screen.dart` (CRLF: Edit mirati):
1. In `initState`, dopo la chiamata a `setNextEnabled`:

```dart
    // Discord: quante persone nel watch party (`null` fuori da un gruppo).
    unawaited(_mediaSession.setParty(
        party != null && party.inGroup ? party.members.length : null));
```

2. In `dispose`, accanto a `if (!_handingOver) unawaited(_mediaSession.clear());`:

```dart
    if (!_handingOver) unawaited(_mediaSession.setParty(null));
```

3. In `build`, fuori dal blocco `if (_inParty)` (deve funzionare anche dopo l'uscita dal gruppo):

```dart
    if (widget.args.party != null) {
      ref.listen(
          watchPartySessionProvider
              .select((s) => s.inGroup ? s.members.length : null),
          (_, members) => unawaited(_mediaSession.setParty(members)));
    }
```

- [ ] **Step 6: verifica che passino**

Run: `flutter test test/features/discord/ test/core/media_session/ test/features/watch_party/ test/features/player/`
Expected: PASS.

- [ ] **Step 7: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/core/media_session/media_session.dart lib/core/media_session/mirrored_media_session.dart lib/core/media_session/smtc_media_session.dart lib/features/discord/discord_activity.dart lib/features/discord/discord_presence.dart lib/features/discord/discord_providers.dart lib/features/player/player_screen.dart test/support/playback_fakes.dart test/features/discord/discord_activity_test.dart test/core/media_session/mirrored_media_session_test.dart test/features/watch_party/party_player_test.dart
git commit -m "feat: show the watch party size on Discord"
```

---

### Task 12: il watch party nella diagnostica

**Files:**
- Modify: `lib/features/watch_party/watch_party_session.dart`
- Modify: `lib/features/watch_party/group_playback_driver.dart`
- Modify: `lib/features/player/player_screen.dart`
- Modify: `lib/features/settings/diagnostics.dart`
- Test: `test/features/settings/diagnostics_test.dart`, `test/features/watch_party/group_playback_driver_test.dart`

Regole (spec B §5.10): "Copia diagnostica" aggiunge, se si è in un gruppo, una riga con id del gruppo, stato, numero di membri, offset e ping dell'orologio, ritardo alla ripartenza e ultimo scarto misurato. Niente nomi (né del gruppo né dei membri) e niente token.

- [ ] **Step 1: scrivi i test**

In `test/features/settings/diagnostics_test.dart` aggiungi gli import:

```dart
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/watch_party_fakes.dart';
```

e in fondo a `main()`:

```dart
  test('describeWatchParty: solo dentro un gruppo, senza nomi', () {
    expect(describeWatchParty(state: const WatchPartyState()), isNull);
    final party = WatchPartyState(
      phase: WatchPartyPhase.inGroup,
      group: testGroup(participants: ['Mario', 'Luigi']),
      groupState: GroupState.playing,
    );
    expect(
        describeWatchParty(
          state: party,
          offset: const Duration(milliseconds: 1595),
          ping: const Duration(milliseconds: 20),
          startLag: const Duration(milliseconds: 180),
          lastDrift: const Duration(milliseconds: -35),
        ),
        'group=g1, state=playing, members=2, offset=1595 ms, ping=20 ms, '
        'startLag=180 ms, lastDrift=-35 ms');
    expect(describeWatchParty(state: party),
        'group=g1, state=playing, members=2, offset=-, ping=-, '
        'startLag=-, lastDrift=-');
  });

  test('buildDiagnostics: riga del watch party', () {
    final text = buildDiagnostics(
      appVersion: '0.1.0',
      windowsVersion: 'w',
      serverVersion: '10.11.9',
      player: const PlayerSettings(),
      discord: const DiscordSettings(),
      recentErrors: const [],
      watchParty: 'group=g1, state=paused',
    );
    expect(text, contains('\nWatch party: group=g1, state=paused\n'));
  });
```

In `test/features/watch_party/group_playback_driver_test.dart`:
- dopo `var resyncs = 0;` aggiungi `Duration? lastDrift;`; in `setUpDriver` azzeralo (`lastDrift = null;`) e passa al driver `onDrift: (drift) => lastDrift = drift,`;
- in fondo a `main()`:

```dart
  test('onDrift: l\'ultimo scarto misurato', () {
    fakeAsync((async) {
      setUpDriver(async);
      final unpause = command(SyncPlayCommandType.unpause);
      send(async, unpause);
      runPlayback(async, const Duration(seconds: 3),
          from: unpause, lag: const Duration(milliseconds: 300));
      expect(lastDrift, const Duration(milliseconds: 300));
      tearDownDriver(async);
    });
  });
```

- [ ] **Step 2: verifica che falliscano**

Run: `flutter test test/features/settings/diagnostics_test.dart test/features/watch_party/group_playback_driver_test.dart`
Expected: FAIL (`describeWatchParty`, `watchParty:`, `onDrift` non definiti).

- [ ] **Step 3: il driver e la sessione**

In `lib/features/watch_party/group_playback_driver.dart`:
- nel costruttore, dopo `void Function()? onResync,`: `void Function(Duration drift)? onDrift,` e nella lista di inizializzazione `_onDrift = onDrift,`;
- dopo il campo `_onResync`:

```dart

  /// Ultimo scarto misurato (media della finestra), per la diagnostica.
  final void Function(Duration drift)? _onDrift;
```

- in `_onTick`, subito dopo la chiamata `final action = _corrector.update(...);`:

```dart
    final drift = _corrector.lastDrift;
    if (drift != null) _onDrift?.call(drift);
```

In `lib/features/watch_party/watch_party_session.dart`, dopo `String? _rejoining;`:

```dart

  /// Ultimo scarto misurato dal player del gruppo (diagnostica).
  Duration? lastDrift;
```

e azzeralo (`lastDrift = null;`) in `build()` e in `_reset()`.

In `lib/features/player/player_screen.dart`, nel costruttore di `GroupPlaybackDriver` in `_attachParty`, dopo `startLag: session.startLag,`:

```dart
      onDrift: (drift) => session.lastDrift = drift,
```

- [ ] **Step 4: la diagnostica**

In `lib/features/settings/diagnostics.dart`:
1. Import: `import '../watch_party/watch_party_session.dart';`
2. Prima di `buildDiagnostics`:

```dart
/// Stato del watch party per la diagnostica (spec B §5.10); `null` fuori da
/// un gruppo. Niente nomi: solo id, stato e tempi.
String? describeWatchParty({
  required WatchPartyState state,
  Duration? offset,
  Duration? ping,
  Duration? startLag,
  Duration? lastDrift,
}) {
  final group = state.group;
  if (!state.inGroup || group == null) return null;
  String ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds} ms';
  return 'group=${group.id}, state=${state.groupState.name}, '
      'members=${state.members.length}, offset=${ms(offset)}, '
      'ping=${ms(ping)}, startLag=${ms(startLag)}, lastDrift=${ms(lastDrift)}';
}
```

3. `buildDiagnostics` riceve il parametro facoltativo `String? watchParty,` (dopo `required List<String> recentErrors,`) e, dopo la riga di Discord:

```dart
  if (watchParty != null) buffer.writeln('Watch party: $watchParty');
```

(scrivi la riga di Discord e questa come istruzioni separate: la catena `..writeln` finisce prima.)

4. In `collectDiagnosticsProvider`, prima di `return buildDiagnostics(`:

```dart
          String? watchParty;
          try {
            final session = ref.read(watchPartySessionProvider.notifier);
            final clock = session.serverClock;
            watchParty = describeWatchParty(
              state: ref.read(watchPartySessionProvider),
              offset: clock?.offset,
              ping: clock?.ping,
              startLag: session.startLag?.value,
              lastDrift: session.lastDrift,
            );
          } on Object catch (error) {
            _log.info('stato del watch party non disponibile: $error');
          }
```

e passa `watchParty: watchParty,` a `buildDiagnostics`.

- [ ] **Step 5: verifica che passino**

Run: `flutter test test/features/settings/ test/features/watch_party/`
Expected: PASS (il test esistente "buildDiagnostics: testo completo" non cambia: senza `watchParty` non c'è la riga).

- [ ] **Step 6: analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → tutti verdi.

```bash
git add lib/features/watch_party/watch_party_session.dart lib/features/watch_party/group_playback_driver.dart lib/features/player/player_screen.dart lib/features/settings/diagnostics.dart test/features/settings/diagnostics_test.dart test/features/watch_party/group_playback_driver_test.dart
git commit -m "feat: add the watch party state to the diagnostics"
```

---

### Task 13: verifica finale

**Files:** nessuno (salvo correzioni).

- [ ] **Step 1: analisi e test**

```bash
flutter analyze
flutter test
```

Expected: `No issues found!` e tutti i test verdi (erano 648 prima del piano).

- [ ] **Step 2: build di release con la configurazione**

```bash
export PATH="/c/Users/sidot/.cargo/bin:$PATH"
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `Built build\windows\x64\runner\Release\wonderflix.exe`. **Senza `--dart-define-from-file` l'app mostra "Configurazione mancante".** Se fallisce con `LNK1168`: `taskkill //IM wonderflix.exe //F` e riprova.

- [ ] **Step 3: controllo dei file generati**

Run: `git status --short`
Expected: nessun file modificato (altrimenti `git checkout -- windows/flutter/` se sono solo fini riga).

- [ ] **Step 4: istruzioni per la prova manuale (da riportare all'utente)**

Le due istanze le avvia l'utente (l'app avviata da Claude viene virtualizzata): A con doppio clic sull'exe, B da PowerShell nella stessa cartella con `$env:WONDERFLIX_PROFILE = 'b'; .\wonderflix.exe`.

Da controllare:
- **inviti:** con B sulla Home, A avvia un watch party → su B compare "Mario ha avviato un watch party" per 10 s, con "Unisciti" e la X; nessun invito con il player aperto;
- **barra in alto:** "Nel watch party" si vede solo stando in un gruppo con la shell davanti, cioè in un gruppo senza nulla in coda (per esempio creato da jellyfin-web senza titolo): se capita, provare "Torna al player" ed "Esci dal watch party"; se non si riesce a ottenerlo, basta segnalarlo;
- **dal player:** A guarda da solo (anche a schermo intero) e preme "Guarda insieme" nei controlli → il player si riapre sullo stesso punto nel gruppo, a schermo intero; B lo vede nell'elenco e entra;
- **rientro:** stacca la rete su B per 20–30 s e riattaccala → B rientra nel gruppo da solo e si riallinea (nei log `[watchparty]`: "WebSocket riconnesso: rientro nel watch party", "rientrati nel watch party"); se nel frattempo A è uscito e il gruppo è sparito, B vede "Il watch party è terminato" e continua da solo;
- **video che non si apre:** difficile da provocare; se capita, A non resta in attesa e B vede "Riprova" ed "Esci dal watch party";
- **permessi:** dalla Dashboard di Jellyfin imposta per l'utente B "SyncPlay: solo unirsi" → niente "Guarda insieme" (dettagli e player), ma elenco e inviti sì; "nessun accesso" → niente watch party; poi ripristina;
- **Discord:** durante un watch party l'attività mostra "Watch party · 2 persone";
- **diagnostica:** in un gruppo, "Copia diagnostica" contiene la riga "Watch party: group=…, state=…, members=2, offset=…, ping=…, startLag=…, lastDrift=…".
